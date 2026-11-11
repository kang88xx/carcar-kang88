import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/theme.dart';
import 'core/app_controller.dart';
import 'core/native_bridge.dart';
import 'core/device_notifications.dart';
import 'core/repository.dart';
import 'core/session_storage.dart';
import 'core/invite_links.dart';
import 'core/widget_links.dart';
import 'features/auth_screen.dart';
import 'features/shell.dart';

/// Ends a stalled server request itself at the save time limit, so a save the
/// app already reported as failed is not left open to arrive later as a stale
/// location. Token renewal and connecting come before this takes effect and
/// are bounded by the AppController timeouts only.
const serverRequestOptions = PostgrestClientOptions(
  requestTimeout: Duration(seconds: 15),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  SupabaseClient? client;
  String? startupError;
  if (url.isNotEmpty && key.isNotEmpty) {
    try {
      final parsed = Uri.tryParse(url);
      if (parsed == null ||
          parsed.scheme != 'https' ||
          parsed.host.isEmpty ||
          key.startsWith('sb_secret_')) {
        throw const AppException('서버 주소 또는 공개 키 설정을 확인해 주세요.');
      }
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        postgrestOptions: serverRequestOptions,
        authOptions: FlutterAuthClientOptions(
          localStorage: kIsWeb ? null : const SecureSessionStorage(),
          detectSessionInUriPredicate: (uri) => kIsWeb
              ? (uri.scheme == 'https' || uri.scheme == 'http') &&
                    uri.origin == Uri.base.origin &&
                    (uri.queryParameters.containsKey('code') ||
                        uri.fragment.contains('access_token='))
              : isAuthCallback(uri),
        ),
      );
      client = Supabase.instance.client;
    } on Object {
      startupError = '서버 연결 설정을 확인하지 못했어요. 앱을 다시 열거나 관리자에게 문의해 주세요.';
    }
  }
  runApp(
    CarcarApp(
      preferences: await SharedPreferences.getInstance(),
      client: client,
      startupError: startupError,
      createAppleAuth: client == null
          ? null
          : () => GoTrueClient(
              url: '$url/auth/v1',
              headers: {'apikey': key},
              autoRefreshToken: false,
            ),
    ),
  );
}

class CarcarApp extends StatefulWidget {
  const CarcarApp({
    super.key,
    required this.preferences,
    this.client,
    this.startupError,
    this.createAppleAuth,
    this.repositoryFactory = SupabaseParkingRepository.new,
    this.incomingLinks,
    this.initialLink,
  });
  final SharedPreferences preferences;
  final SupabaseClient? client;
  final GoTrueClient Function()? createAppleAuth;
  final String? startupError;
  final ParkingRepository Function(SupabaseClient) repositoryFactory;
  final Stream<Uri>? incomingLinks;
  final Future<Uri?> Function()? initialLink;
  @override
  State<CarcarApp> createState() => _CarcarAppState();
}

class _CarcarAppState extends State<CarcarApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  AppController? _controller;
  DeviceNotificationController? _notifications;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<Uri>? _inviteSubscription;
  late final PendingInvite _pendingInvite;
  bool _startingDemo = false;
  bool _passwordRecovery = false;
  int _authGeneration = 0;
  int _widgetLinkId = 0, _linkSessionEpoch = 0;
  WidgetDestination? _widgetDestination;
  String? _widgetLinkUserId;
  String? _cleanupNotice;
  String? _authNotice;
  String? _inviteNotice;
  // The user whose native widget, finding display and push registration are
  // known to be on this device. Only written after a confirmed cleanup.
  static const _lastUserKey = 'carcar.session.user';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pendingInvite = PendingInvite(widget.preferences);
    if (widget.client != null ||
        widget.incomingLinks != null ||
        widget.initialLink != null ||
        NativeBridge.supportsOcr) {
      final links =
          widget.incomingLinks ??
          (kIsWeb ? const Stream<Uri>.empty() : AppLinks().uriLinkStream);
      _inviteSubscription = links.listen(
        (uri) => unawaited(_receiveLink(uri)),
        onError: (_) {
          if (mounted) {
            setState(() => _inviteNotice = '초대 링크를 읽지 못했어요. 받은 링크를 붙여 넣어 주세요.');
          }
        },
      );
      final initial =
          widget.initialLink ??
          (kIsWeb ? () async => Uri.base : AppLinks().getInitialLink);
      final linkEpoch = _linkSessionEpoch;
      final initialUserId = widget.client?.auth.currentUser?.id;
      unawaited(
        initial()
            .then((uri) async {
              if (uri == null || !mounted) return;
              if (parseWidgetLink(uri) != null &&
                  (linkEpoch != _linkSessionEpoch ||
                      (initialUserId != null &&
                          initialUserId !=
                              widget.client?.auth.currentUser?.id))) {
                return;
              }
              await _receiveLink(uri);
            })
            .catchError((Object _) {}),
      );
    }
    // GoTrue replays its auth events, including password recovery from a cold
    // start link. Handle those before opening a signed-in controller.
    _authSubscription = widget.client?.auth.onAuthStateChange.listen(
      (state) {
        // Local sign-out emits after storage cleanup. A newer login may have
        // completed while that cleanup was pending, so ignore obsolete events.
        if (!mounted ||
            state.session?.user.id != widget.client?.auth.currentUser?.id) {
          return;
        }
        if (state.event == AuthChangeEvent.passwordRecovery &&
            state.session != null) {
          _passwordRecovery = true;
          unawaited(_clearController());
        } else if (state.session == null &&
            (_controller?.isDemo == false || _passwordRecovery)) {
          _passwordRecovery = false;
          unawaited(_clearController());
        } else if (!_passwordRecovery &&
            state.session != null &&
            (_controller == null ||
                _controller!.isDemo ||
                _controller!.repository.userId != state.session!.user.id)) {
          unawaited(_changeRealSession(state.session!.user.id));
        } else if (state.event == AuthChangeEvent.tokenRefreshed &&
            _controller != null) {
          unawaited(_controller!.refresh());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() {
          _cleanupNotice = '로그인 연결을 확인하지 못했어요. 네트워크 연결 후 다시 시도해 주세요.';
        });
      },
    );
  }

  void _connectReal() {
    _controller = AppController(
      widget.repositoryFactory(widget.client!),
      preferences: widget.preferences,
    );
    unawaited(_controller!.initialize());
    if (_controller!.repository is SupabaseParkingRepository) {
      _notifications = DeviceNotificationController(
        client: widget.client!,
        preferences: widget.preferences,
      );
      unawaited(_notifications!.initialize());
    }
  }

  Future<void> _receiveLink(Uri uri) async {
    if (!mounted) return;
    final destination = parseWidgetLink(uri);
    if (destination != null) {
      if (_passwordRecovery) return;
      setState(() {
        _widgetDestination = destination;
        _widgetLinkId++;
        _widgetLinkUserId =
            _controller?.repository.userId ??
            widget.client?.auth.currentUser?.id;
      });
      return;
    }
    try {
      if (await _pendingInvite.receive(uri) && mounted) {
        setState(() => _inviteNotice = null);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _inviteNotice = '초대 링크를 보관하지 못했어요. 앱을 다시 열면 받은 링크를 붙여 넣어 주세요.',
        );
      }
    }
  }

  void _consumeWidgetLink(int id) {
    if (id != _widgetLinkId || !mounted) return;
    setState(() {
      _widgetDestination = null;
      _widgetLinkUserId = null;
    });
  }

  void _discardWidgetLink() {
    _linkSessionEpoch++;
    _widgetDestination = null;
    _widgetLinkUserId = null;
  }

  Future<void> _clearInvite() async {
    try {
      await _pendingInvite.clear();
      if (mounted) setState(() => _inviteNotice = null);
    } on Object {
      if (mounted) {
        setState(() => _inviteNotice = '초대 닫기를 저장하지 못했어요. 다시 시도해 주세요.');
      }
    }
  }

  Future<void> _clearNativeSnapshot({bool resetIcon = true}) async {
    try {
      await Future.wait([
        NativeBridge.clearSnapshot(),
        NativeBridge.disablePush(),
        if (resetIcon) NativeBridge.syncLauncherIcon(null),
      ]).timeout(const Duration(seconds: 5));
      _cleanupNotice = null;
    } on Object {
      _cleanupNotice =
          '이 기기의 이전 위젯·알림을 모두 지웠는지 확인하지 못했어요. 기기에서 위젯과 알림을 직접 확인해 주세요.';
    }
  }

  void _forgetLastUser() => unawaited(
    widget.preferences.remove(_lastUserKey).catchError((Object _) => false),
  );

  Future<void> _clearController() async {
    _discardWidgetLink();
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _authGeneration++;
    _notifications?.dispose();
    _notifications = null;
    _controller?.dispose();
    _controller = null;
    // Forget the user before the native cleanup: if the cleanup is interrupted,
    // the next sign-in cleans again instead of trusting leftover state.
    _forgetLastUser();
    if (mounted) setState(() {});
    await _clearNativeSnapshot();
    if (mounted) setState(() {});
  }

  Future<void> _changeRealSession(String userId) async {
    // Reopening the app as the same signed-in user keeps that user's own
    // widget, finding display and push registration. Every other entry (other
    // account, demo, unknown previous user) cleans the device first.
    final sameUserRestart =
        _controller == null &&
        widget.preferences.getString(_lastUserKey) == userId;
    if (_controller != null ||
        (_widgetLinkUserId != null && _widgetLinkUserId != userId)) {
      _discardWidgetLink();
    }
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    final generation = ++_authGeneration;
    _notifications?.dispose();
    _notifications = null;
    _controller?.dispose();
    _controller = null;
    if (mounted) setState(() {});
    if (!sameUserRestart) {
      _forgetLastUser();
      await _clearNativeSnapshot(resetIcon: false);
      if (!mounted ||
          generation != _authGeneration ||
          widget.client?.auth.currentUser?.id != userId) {
        return;
      }
      if (_cleanupNotice == null) {
        unawaited(
          widget.preferences
              .setString(_lastUserKey, userId)
              .catchError((Object _) => false),
        );
      }
    }
    _connectReal();
    setState(() {});
  }

  Future<void> _demo() async {
    if (_startingDemo) return;
    _startingDemo = true;
    try {
      _forgetLastUser();
      final repo = DemoParkingRepository(widget.preferences);
      await repo.initialize();
      if (!mounted) return;
      _controller?.dispose();
      _controller = AppController(repo, preferences: widget.preferences);
      setState(() {});
      await _controller!.initialize();
    } finally {
      _startingDemo = false;
    }
  }

  Future<void> _logout() async {
    final controller = _controller;
    final notifications = _notifications;
    final generation = _authGeneration;
    if (controller == null) return;
    String? notificationWarning;
    try {
      await notifications?.unregisterForLogout();
    } on Object catch (error) {
      notificationWarning = friendlyError(error);
    }
    if (!mounted ||
        !identical(controller, _controller) ||
        generation != _authGeneration ||
        widget.client?.auth.currentUser?.id !=
            (controller.isDemo ? null : controller.repository.userId)) {
      return;
    }
    await controller.repository.signOut();
    if (!mounted ||
        !identical(controller, _controller) ||
        generation != _authGeneration ||
        widget.client?.auth.currentUser != null) {
      return;
    }
    await _clearController();
    if (notificationWarning != null && mounted) {
      setState(() {
        _cleanupNotice = {
          if (_cleanupNotice != null) _cleanupNotice!,
          notificationWarning!,
        }.join('\n');
      });
    }
  }

  Future<void> _accountDeleted(AppController controller) async {
    if (!mounted ||
        !identical(controller, _controller) ||
        widget.client?.auth.currentUser != null) {
      return;
    }
    await _clearController();
  }

  Future<void> _finishPasswordRecovery({required bool completed}) async {
    await widget.client!.auth.signOut(scope: SignOutScope.local);
    _passwordRecovery = false;
    await _clearController();
    if (completed && mounted) {
      setState(() {
        _authNotice = '비밀번호를 변경했어요. 새 비밀번호로 로그인해 주세요.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller?.appActive = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && _controller != null) {
      unawaited(_controller!.refresh());
      unawaited(_notifications?.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _inviteSubscription?.cancel();
    _notifications?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigatorKey,
    title: '차자리 · 우리 차의 자리',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: _buildHome(),
    onGenerateRoute: (_) =>
        MaterialPageRoute<void>(builder: (_) => _buildHome()),
  );

  Widget _buildHome() => _passwordRecovery && widget.client != null
      ? PasswordRecoveryScreen(
          client: widget.client!,
          onComplete: () => _finishPasswordRecovery(completed: true),
          onCancel: () => _finishPasswordRecovery(completed: false),
        )
      : _controller == null
      // Signed in, but this account's home is still being prepared. Show
      // progress instead of a login screen that looks like nothing happened.
      ? widget.client?.auth.currentUser != null
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : AuthScreen(
                client: widget.client,
                createAppleAuth: widget.createAppleAuth,
                onDemo: _demo,
                startupError:
                    _inviteNotice ?? _cleanupNotice ?? widget.startupError,
                startupNotice: _pendingInvite.code != null
                    ? '가족 초대를 받았어요. 로그인하면 바로 참여할 수 있어요.'
                    : _authNotice,
              )
      : AppShell(
          key: ValueKey(_controller),
          controller: _controller!,
          preferences: widget.preferences,
          onLogout: _logout,
          onAccountDeleted: _accountDeleted,
          notifications: _notifications,
          pendingInvite: _pendingInvite.code,
          inviteNotice: _inviteNotice,
          onClearInvite: _clearInvite,
          widgetDestination: _widgetDestination,
          widgetLinkId: _widgetLinkId,
          onWidgetLinkHandled: _consumeWidgetLink,
        );
}
