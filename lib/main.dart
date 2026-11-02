import 'dart:async';
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
import 'features/auth_screen.dart';
import 'features/shell.dart';

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
        authOptions: FlutterAuthClientOptions(
          localStorage: kIsWeb ? null : const SecureSessionStorage(),
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
    ),
  );
}

class CarcarApp extends StatefulWidget {
  const CarcarApp({
    super.key,
    required this.preferences,
    this.client,
    this.startupError,
    this.repositoryFactory = SupabaseParkingRepository.new,
  });
  final SharedPreferences preferences;
  final SupabaseClient? client;
  final String? startupError;
  final ParkingRepository Function(SupabaseClient) repositoryFactory;
  @override
  State<CarcarApp> createState() => _CarcarAppState();
}

class _CarcarAppState extends State<CarcarApp> with WidgetsBindingObserver {
  AppController? _controller;
  DeviceNotificationController? _notifications;
  StreamSubscription<AuthState>? _authSubscription;
  bool _startingDemo = false;
  bool _passwordRecovery = false;
  int _authGeneration = 0;
  String? _cleanupNotice;
  String? _authNotice;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // GoTrue replays its auth events, including password recovery from a cold
    // start link. Handle those before opening a signed-in controller.
    _authSubscription = widget.client?.auth.onAuthStateChange.listen(
      (state) {
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

  Future<void> _clearNativeSnapshot() async {
    try {
      await Future.wait([
        NativeBridge.clearSnapshot(),
        NativeBridge.disablePush(),
      ]).timeout(const Duration(seconds: 5));
      _cleanupNotice = null;
    } on Object {
      _cleanupNotice =
          '이 기기의 이전 위젯·알림을 모두 지웠는지 확인하지 못했어요. 기기에서 위젯과 알림을 직접 확인해 주세요.';
    }
  }

  Future<void> _clearController() async {
    _authGeneration++;
    _notifications?.dispose();
    _notifications = null;
    _controller?.dispose();
    _controller = null;
    if (mounted) setState(() {});
    await _clearNativeSnapshot();
    if (mounted) setState(() {});
  }

  Future<void> _changeRealSession(String userId) async {
    final generation = ++_authGeneration;
    _notifications?.dispose();
    _notifications = null;
    _controller?.dispose();
    _controller = null;
    if (mounted) setState(() {});
    await _clearNativeSnapshot();
    if (!mounted ||
        generation != _authGeneration ||
        widget.client?.auth.currentUser?.id != userId) {
      return;
    }
    _connectReal();
    setState(() {});
  }

  Future<void> _demo() async {
    if (_startingDemo) return;
    _startingDemo = true;
    try {
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
    String? notificationWarning;
    try {
      await _notifications?.unregisterForLogout();
    } on Object catch (error) {
      notificationWarning = friendlyError(error);
    }
    await _controller?.repository.signOut();
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
    if (state == AppLifecycleState.resumed && _controller != null) {
      unawaited(_controller!.refresh());
      unawaited(_notifications?.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _notifications?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '차곡 · 우리 차의 자리',
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
      ? AuthScreen(
          client: widget.client,
          onDemo: _demo,
          startupError: _cleanupNotice ?? widget.startupError,
          startupNotice: _authNotice,
        )
      : AppShell(
          key: ValueKey(_controller),
          controller: _controller!,
          preferences: widget.preferences,
          onLogout: _logout,
          notifications: _notifications,
        );
}
