import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app/theme.dart';
import '../core/repository.dart';
import '../shared/components.dart';

const _authRedirect = String.fromEnvironment(
  'AUTH_REDIRECT_URL',
  defaultValue: 'com.kang88.carcar://login-callback',
);

String? _emailError(String? value) =>
    value != null &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
    ? null
    : '이메일 주소를 확인해 주세요.';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.client,
    required this.onDemo,
    this.startupError,
    this.startupNotice,
  });
  final SupabaseClient? client;
  final Future<void> Function() onDemo;
  final String? startupError;
  final String? startupNotice;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  var _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _signUp = false, _busy = false, _obscure = true;
  String? _error, _notice;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_signUp) {
        final result = await widget.client!.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          emailRedirectTo: _authRedirect,
        );
        if (mounted && result.session == null) {
          setState(
            () => _notice = '이메일을 확인해 주세요. 확인이 필요한 계정이라면 가입 안내를 받을 수 있어요.',
          );
        }
      } else {
        await widget.client!.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailHelp({required bool recovery}) async {
    if (_busy) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmailHelpDialog(
        client: widget.client!,
        initialEmail: _email.text.trim(),
        recovery: recovery,
      ),
    );
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
                      crossAxisAlignment: CrossAxisAlignment.center,
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
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.client == null
                ? '차곡을 먼저 만나보세요'
                : _signUp
                ? '가족과 함께 시작해요'
                : '다시 만나 반가워요',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            widget.client == null
                ? '가입 없이 화면과 주차 기록을 체험할 수 있어요.'
                : '이메일로 간편하게 시작하세요.',
            style: const TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 24),
          if (widget.startupError != null)
            StatusNotice(widget.startupError!, error: true),
          if (widget.startupNotice != null) StatusNotice(widget.startupNotice!),
          if (_error != null) StatusNotice(_error!, error: true),
          if (_notice != null) StatusNotice(_notice!),
          if (widget.client != null) ...[
            TextFormField(
              controller: _email,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '이메일',
                hintText: 'name@example.com',
              ),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: _emailError,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              autofillHints: [
                _signUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: '비밀번호',
                helperText: _signUp ? '8자 이상으로 입력해 주세요.' : null,
                suffixIcon: IconButton(
                  tooltip: _obscure ? '비밀번호 표시' : '비밀번호 숨기기',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (v) => v == null || v.length < (_signUp ? 8 : 1)
                  ? '비밀번호를 ${_signUp ? '8자 이상 ' : ''}입력해 주세요.'
                  : null,
              onFieldSubmitted: (_) => _busy ? null : _submit(),
            ),
            const SizedBox(height: 24),
            BusyButton(
              label: _signUp ? '계정 만들기' : '로그인',
              onPressed: _submit,
              busy: _busy,
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _signUp = !_signUp;
                      _form = GlobalKey<FormState>();
                      _error = null;
                      _notice = null;
                    }),
              child: Text(_signUp ? '이미 계정이 있어요 · 로그인' : '처음 오셨나요? 계정 만들기'),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _emailHelp(recovery: true),
                  child: const Text('비밀번호를 잊으셨나요?'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _emailHelp(recovery: false),
                  child: const Text('가입 확인 메일 다시 받기'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 16),
          ],
          widget.client == null
              ? BusyButton(
                  label: '체험 시작하기',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: widget.onDemo,
                )
              : OutlinedButton(
                  onPressed: _busy ? null : widget.onDemo,
                  child: const Text('가입 없이 먼저 둘러보기'),
                ),
          const SizedBox(height: 14),
          const Text(
            '체험 기록은 이 기기에만 저장돼요.\n실제 가족 공유는 서버 연결 후 사용할 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.7),
          ),
        ],
      ),
    ),
  );
}

class _EmailHelpDialog extends StatefulWidget {
  const _EmailHelpDialog({
    required this.client,
    required this.initialEmail,
    required this.recovery,
  });
  final SupabaseClient client;
  final String initialEmail;
  final bool recovery;
  @override
  State<_EmailHelpDialog> createState() => _EmailHelpDialogState();
}

class _EmailHelpDialogState extends State<_EmailHelpDialog> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  int _cooldown = 0;
  Timer? _timer;
  String? _error, _notice;

  Future<void> _send() async {
    if (_busy || _cooldown > 0 || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (widget.recovery) {
        await widget.client.auth.resetPasswordForEmail(
          _email.text.trim(),
          redirectTo: _authRedirect,
        );
      } else {
        await widget.client.auth.resend(
          type: OtpType.signup,
          email: _email.text.trim(),
          emailRedirectTo: _authRedirect,
        );
      }
      if (!mounted) return;
      _requestNotice();
    } on Object catch (error) {
      if (mounted) {
        if (error is AuthException &&
            const {
              'user_not_found',
              'email_exists',
              'user_already_exists',
              'email_not_confirmed',
            }.contains(error.code)) {
          // Do not reveal whether this address belongs to an eligible account.
          // This conditional notice does not claim that an email was delivered.
          _requestNotice();
        } else {
          _error =
              error is AuthException &&
                  (error.statusCode == '429' ||
                      error.code == 'over_email_send_rate_limit')
              ? '요청이 많아요. 잠시 후 다시 시도해 주세요.'
              : '메일 요청을 완료하지 못했어요. 주소와 연결을 확인하고 다시 시도해 주세요.';
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _requestNotice() {
    _notice = widget.recovery
        ? '등록된 계정이라면 비밀번호 재설정 안내를 받을 수 있어요. 메일함과 스팸함을 확인해 주세요.'
        : '가입 확인이 필요한 계정이라면 안내 메일을 받을 수 있어요. 메일함과 스팸함을 확인해 주세요.';
    _cooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown--);
      if (_cooldown == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.recovery ? '비밀번호 재설정' : '가입 확인 메일'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.recovery
                      ? '가입한 이메일로 재설정 링크를 요청해 주세요. 이 기기에서 메일의 링크를 열면 새 비밀번호를 정할 수 있어요.'
                      : '가입할 때 입력한 이메일을 확인해 주세요. 이미 가입 확인을 마쳤다면 로그인할 수 있어요.',
                ),
                const SizedBox(height: 20),
                if (_error != null) StatusNotice(_error!, error: true),
                if (_notice != null) StatusNotice(_notice!),
                TextFormField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: '이메일'),
                  validator: _emailError,
                  onFieldSubmitted: (_) => _send(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: _busy || _cooldown > 0 ? null : _send,
          child: Text(
            _busy
                ? '요청 중…'
                : _cooldown > 0
                ? '$_cooldown초 후 다시 요청'
                : '안내 메일 요청',
          ),
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
