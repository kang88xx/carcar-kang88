import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app/theme.dart';
import '../core/repository.dart';
import '../shared/components.dart';

const authRedirect = String.fromEnvironment(
  'AUTH_REDIRECT_URL',
  defaultValue: 'com.kang88.carcar://login-callback',
);

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.client,
    required this.onDemo,
    this.startupError,
    this.startupNotice,
    this.onGoogleSignIn,
  });
  final SupabaseClient? client;
  final Future<void> Function() onDemo;
  final Future<bool> Function()? onGoogleSignIn;
  final String? startupError, startupNotice;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _busy = false;
  String? _error, _notice;

  Future<void> _google() async {
    if (_busy || widget.client == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final launched =
          await (widget.onGoogleSignIn?.call() ??
              widget.client!.auth.signInWithOAuth(
                OAuthProvider.google,
                redirectTo: kIsWeb ? Uri.base.origin : authRedirect,
                scopes: 'openid email profile',
                queryParams: {'prompt': 'select_account'},
                authScreenLaunchMode: LaunchMode.externalApplication,
              ));
      if (!launched) {
        throw const AppException('Google 로그인 창을 열지 못했어요. 다시 시도해 주세요.');
      }
      if (mounted) {
        setState(
          () => _notice = 'Google에서 로그인하면 차자리로 돌아와요. 취소했다면 다시 시작할 수 있어요.',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 600 ? 24 : 48,
              vertical: 32,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: constraints.maxWidth > 850
                  ? Row(
                      children: [
                        Expanded(child: _intro()),
                        const SizedBox(width: 90),
                        Expanded(child: _formPanel()),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _intro(),
                        const SizedBox(height: 40),
                        _formPanel(),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _intro() => LayoutBuilder(
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Brand(large: true),
        const SizedBox(height: 42),
        Text(
          '우리 차,\n어디에 주차했더라?',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: constraints.maxWidth < 312 ? 28 : 36,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '한 번 기록하면, 온 가족이 알아요.\n복잡한 지하 주차장에서도 헤매지 않도록.',
          style: TextStyle(color: Palette.muted, fontSize: 16, height: 1.8),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Palette.soft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.directions_car_filled_outlined,
                color: Palette.green,
                size: 32,
              ),
              SizedBox(width: 18),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'B2 · C구역 · 24번',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '이렇게 간단하게 기억해요.',
                      style: TextStyle(color: Palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _formPanel() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.client == null ? '차자리를 먼저 만나보세요' : '우리 가족의 차 한 대',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          widget.client == null
              ? '가입 없이 화면과 주차 기록을 체험할 수 있어요.'
              : 'Google로 시작하고, 차량을 등록하거나 가족의 초대를 받아요.',
          style: const TextStyle(color: Palette.muted, height: 1.6),
        ),
        const SizedBox(height: 24),
        if (widget.startupError != null)
          StatusNotice(widget.startupError!, error: true),
        if (widget.startupNotice != null) StatusNotice(widget.startupNotice!),
        if (_error != null) StatusNotice(_error!, error: true),
        if (_notice != null) StatusNotice(_notice!),
        if (widget.client != null) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _google,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Image.asset(
                    'assets/brand/google-g.png',
                    width: 20,
                    height: 20,
                  ),
            label: const Text('Google로 계속하기'),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Palette.ink,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '별도의 차자리 비밀번호나 인증 문자는 필요 없어요.',
            style: TextStyle(fontSize: 12, color: Palette.muted, height: 1.6),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
        ],
        widget.client == null
            ? BusyButton(
                label: '체험 시작하기',
                icon: Icons.arrow_forward_rounded,
                onPressed: widget.onDemo,
              )
            : TextButton(
                onPressed: _busy ? null : widget.onDemo,
                child: const Text('가입 없이 먼저 둘러보기'),
              ),
        const SizedBox(height: 14),
        const Text(
          '체험 기록은 이 기기에만 저장돼요.\n실제 가족 공유는 Google 로그인 후 사용할 수 있어요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.7),
        ),
      ],
    ),
  );
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    required this.client,
    required this.onComplete,
    required this.onCancel,
  });
  final SupabaseClient client;
  final Future<void> Function() onComplete, onCancel;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  late final String? _userId;
  bool _busy = false, _obscure = true, _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _userId = widget.client.auth.currentUser?.id;
  }

  Future<void> _save() async {
    if (_busy || (!_changed && !_form.currentState!.validate())) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_changed) {
        if (_userId == null || widget.client.auth.currentUser?.id != _userId) {
          throw const AppException('재설정 링크가 만료되었어요. 새 링크를 요청해 주세요.');
        }
        final result = await widget.client.auth.updateUser(
          UserAttributes(password: _password.text),
        );
        if (result.user?.id != _userId) {
          throw const AppException('비밀번호 변경을 확인하지 못했어요. 다시 시도해 주세요.');
        }
        _changed = true;
      }
      if (!mounted) return;
      _password.clear();
      _confirmation.clear();
      await widget.onComplete();
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onCancel();
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Surface(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Brand(),
                      const SizedBox(height: 28),
                      Text(
                        '새 비밀번호',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('앞으로 로그인할 때 사용할 비밀번호를 정해 주세요.'),
                      const SizedBox(height: 24),
                      if (_error != null) StatusNotice(_error!, error: true),
                      if (_changed)
                        const StatusNotice('비밀번호를 변경했어요. 로그인 화면으로 돌아가 주세요.')
                      else ...[
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: '새 비밀번호',
                            helperText: '8자 이상으로 입력해 주세요.',
                            suffixIcon: IconButton(
                              tooltip: _obscure ? '비밀번호 표시' : '비밀번호 숨기기',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.length < 8
                              ? '비밀번호를 8자 이상 입력해 주세요.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmation,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(
                            labelText: '새 비밀번호 확인',
                          ),
                          validator: (value) =>
                              value != _password.text ||
                                  value == null ||
                                  value.isEmpty
                              ? '두 비밀번호가 같아야 해요.'
                              : null,
                          onFieldSubmitted: (_) => _save(),
                        ),
                      ],
                      const SizedBox(height: 24),
                      BusyButton(
                        label: _changed ? '로그인으로 돌아가기' : '비밀번호 변경',
                        onPressed: _save,
                        busy: _busy,
                      ),
                      if (!_changed)
                        TextButton(
                          onPressed: _busy ? null : _cancel,
                          child: const Text('취소하고 로그인으로 돌아가기'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
