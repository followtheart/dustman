import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/fileclaw/dto.dart';
import '../providers/auth_provider.dart';

/// FileClaw 账户页：未登录态承载登录 / 注册 / 短信 OTP / 找回密码四模；
/// 已登录态显示当前用户信息与登出。
///
/// 仅在 Pro 版编译时被引用（kIsPro 守卫见 app.dart / home_screen.dart）。
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账户'), centerTitle: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Consumer<AuthProvider>(
            builder: (context, auth, _) {
              return switch (auth.state) {
                AuthState.loading => const _LoadingView(),
                AuthState.unauthenticated ||
                AuthState.busy =>
                  const _UnauthenticatedView(),
                AuthState.authenticated => const _AuthenticatedView(),
              };
            },
          ),
        ),
      ),
    );
  }
}

// ── Loading ──────────────────────────────────────────


class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在恢复登录会话…'),
        ],
      ),
    );
  }
}

// ── Authenticated ────────────────────────────────────


class _AuthenticatedView extends StatelessWidget {
  const _AuthenticatedView();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    if (profile == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: Text(
                      profile.displayName.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName,
                          style: Theme.of(context).textTheme.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text('状态：${profile.status}'),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              if (profile.email != null) _IdentityRow(label: '邮箱', value: profile.email!),
              if (profile.phone != null) _IdentityRow(label: '手机号', value: profile.phone!),
              const SizedBox(height: 16),
              _PlanRow(profile: profile),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => auth.logout(),
                  icon: const Icon(Icons.logout),
                  label: const Text('退出登录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label)),
          Expanded(child: Text(value, style: const TextStyle(fontFamily: 'monospace'))),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.profile});
  final MeProfile profile;

  @override
  Widget build(BuildContext context) {
    final ratio = profile.quotaAllowance == 0
        ? 0.0
        : (profile.quotaUsed / profile.quotaAllowance).clamp(0.0, 1.0);
    final plan = switch (profile.subscriptionPlan) {
      'monthly' => 'Pro 月付',
      'annual' => 'Pro 年付',
      _ => '免费',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 64, child: Text('套餐')),
            Expanded(child: Text(plan)),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: ratio),
              const SizedBox(height: 4),
              Text(
                '${profile.quotaRemaining} / ${profile.quotaAllowance} tokens 可用',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Unauthenticated（含登录 / 注册 / OTP / 找回 / 验证）───


enum _Mode { passwordLogin, smsLogin, register, forgot }

class _UnauthenticatedView extends StatefulWidget {
  const _UnauthenticatedView();

  @override
  State<_UnauthenticatedView> createState() => _UnauthenticatedViewState();
}

class _UnauthenticatedViewState extends State<_UnauthenticatedView> {
  _Mode _mode = _Mode.passwordLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.passwordLogin, label: Text('密码登录')),
              ButtonSegment(value: _Mode.smsLogin, label: Text('短信登录')),
              ButtonSegment(value: _Mode.register, label: Text('注册')),
              ButtonSegment(value: _Mode.forgot, label: Text('找回')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: switch (_mode) {
                _Mode.passwordLogin => const _PasswordLoginForm(),
                _Mode.smsLogin => const _SmsLoginForm(),
                _Mode.register => const _RegisterForm(),
                _Mode.forgot => const _ForgotForm(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── 密码登录 ─────────────────────────────────────


class _PasswordLoginForm extends StatefulWidget {
  const _PasswordLoginForm();

  @override
  State<_PasswordLoginForm> createState() => _PasswordLoginFormState();
}

class _PasswordLoginFormState extends State<_PasswordLoginForm> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.state == AuthState.busy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _identifier,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: '邮箱或手机号',
            prefixIcon: Icon(Icons.person_outline),
          ),
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          enabled: !busy,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: '密码',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          autofillHints: const [AutofillHints.password],
        ),
        const SizedBox(height: 12),
        _ErrorBanner(auth.lastError),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy ? null : () => _submit(auth),
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('登录'),
          ),
        ),
      ],
    );
  }

  Future<void> _submit(AuthProvider auth) async {
    final ok = await auth.loginWithPassword(
      identifier: _identifier.text.trim(),
      password: _password.text,
    );
    if (!ok && mounted) _showError(context, auth.lastError);
  }
}

// ── 短信登录 ─────────────────────────────────────


class _SmsLoginForm extends StatefulWidget {
  const _SmsLoginForm();

  @override
  State<_SmsLoginForm> createState() => _SmsLoginFormState();
}

class _SmsLoginFormState extends State<_SmsLoginForm> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  int _cooldown = 0;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.state == AuthState.busy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _phone,
          enabled: !busy,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: '手机号',
            prefixIcon: Icon(Icons.smartphone_outlined),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '验证码',
                  prefixIcon: Icon(Icons.sms_outlined),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: (busy || _cooldown > 0) ? null : () => _sendCode(auth),
              child: Text(_cooldown > 0 ? '${_cooldown}s' : '获取验证码'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ErrorBanner(auth.lastError),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy ? null : () => _submit(auth),
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('登录'),
          ),
        ),
      ],
    );
  }

  Future<void> _sendCode(AuthProvider auth) async {
    final ok = await auth.requestSmsCode(phone: _phone.text.trim(), purpose: 'login');
    if (!ok) {
      if (mounted) _showError(context, auth.lastError);
      return;
    }
    setState(() => _cooldown = 60);
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldown--);
      return _cooldown > 0;
    });
  }

  Future<void> _submit(AuthProvider auth) async {
    final ok = await auth.loginWithSms(
      phone: _phone.text.trim(),
      code: _code.text.trim(),
    );
    if (!ok && mounted) _showError(context, auth.lastError);
  }
}

// ── 注册 + 验证 ─────────────────────────────────


class _RegisterForm extends StatefulWidget {
  const _RegisterForm();

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _pendingVerify = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _isEmail => _identifier.text.contains('@');

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.state == AuthState.busy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _identifier,
          enabled: !busy && !_pendingVerify,
          decoration: const InputDecoration(
            labelText: '邮箱或手机号',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          enabled: !busy && !_pendingVerify,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: '密码（≥8 位）',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (_pendingVerify) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '验证码',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _ErrorBanner(auth.lastError),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy
                ? null
                : (_pendingVerify ? () => _verify(auth) : () => _register(auth)),
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_pendingVerify ? '完成验证' : '发送验证码'),
          ),
        ),
        if (_pendingVerify)
          TextButton(
            onPressed: busy ? null : () => setState(() => _pendingVerify = false),
            child: const Text('返回修改'),
          ),
      ],
    );
  }

  Future<void> _register(AuthProvider auth) async {
    final ident = _identifier.text.trim();
    final ok = await auth.register(
      email: _isEmail ? ident : null,
      phone: _isEmail ? null : ident,
      password: _password.text,
    );
    if (ok && mounted) {
      setState(() => _pendingVerify = true);
    } else if (mounted) {
      _showError(context, auth.lastError);
    }
  }

  Future<void> _verify(AuthProvider auth) async {
    final ident = _identifier.text.trim();
    final ok = await auth.verify(target: ident, code: _code.text.trim());
    if (ok && mounted) {
      // 验证完直接帮用户密码登录
      await auth.loginWithPassword(identifier: ident, password: _password.text);
    } else if (mounted) {
      _showError(context, auth.lastError);
    }
  }
}

// ── 找回密码 ─────────────────────────────────────


class _ForgotForm extends StatefulWidget {
  const _ForgotForm();

  @override
  State<_ForgotForm> createState() => _ForgotFormState();
}

class _ForgotFormState extends State<_ForgotForm> {
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _pendingReset = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.state == AuthState.busy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _identifier,
          enabled: !busy && !_pendingReset,
          decoration: const InputDecoration(
            labelText: '邮箱或手机号',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        if (_pendingReset) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '验证码',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !busy,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '新密码（≥8 位）',
              prefixIcon: const Icon(Icons.lock_reset),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _ErrorBanner(auth.lastError),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy
                ? null
                : (_pendingReset ? () => _reset(auth) : () => _request(auth)),
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_pendingReset ? '重置密码' : '发送验证码'),
          ),
        ),
        if (_pendingReset)
          TextButton(
            onPressed: busy ? null : () => setState(() => _pendingReset = false),
            child: const Text('返回修改'),
          ),
      ],
    );
  }

  Future<void> _request(AuthProvider auth) async {
    final ok = await auth.forgotPassword(_identifier.text.trim());
    if (ok && mounted) {
      setState(() => _pendingReset = true);
    } else if (mounted) {
      _showError(context, auth.lastError);
    }
  }

  Future<void> _reset(AuthProvider auth) async {
    final ok = await auth.resetPassword(
      identifier: _identifier.text.trim(),
      code: _code.text.trim(),
      newPassword: _password.text,
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已重置，请用新密码登录')),
      );
      setState(() => _pendingReset = false);
    } else if (mounted) {
      _showError(context, auth.lastError);
    }
  }
}

// ── 通用错误条 ──────────────────────────────────


class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        message!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

void _showError(BuildContext context, String? msg) {
  if (msg == null || msg.isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
