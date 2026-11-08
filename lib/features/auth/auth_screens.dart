import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_text.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/cycle_repository.dart';
import '../../routing/app_router.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _validateEmail(String? v) {
  if (v == null || v.trim().isEmpty) return 'Enter your email address';
  if (!_emailPattern.hasMatch(v.trim())) return 'Enter a valid email address';
  return null;
}

String? _validateNewPassword(String? v) {
  if (v == null || v.length < 8) return 'Use at least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
    return 'Use a mix of letters and numbers';
  }
  return null;
}

/// Shared layout: logo, title, subtitle and a form card.
class _AuthLayout extends StatelessWidget {
  const _AuthLayout({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '',
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AppLogo(size: 84)),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: context.text.headlineSmall,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.cycle.muted),
                ),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    this.validator,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autofillHints: widget.autofillHints,
      validator: widget.validator,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Show password' : 'Hide password',
          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message!,
          style: TextStyle(color: context.colors.error),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Sign in

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).signIn(_email.text, _password.text);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in to see your cycle.',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: _validateEmail,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 14),
                _PasswordField(
                  controller: _password,
                  label: 'Password',
                  autofillHints: const [AutofillHints.password],
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                  onSubmitted: _submit,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push(AppRoutes.forgotPassword),
                    child: const Text('Forgot password?'),
                  ),
                ),
                _ErrorText(_error),
                GradientButton(
                  label: 'Sign In',
                  loading: _busy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.pushReplacement(AppRoutes.signUp),
                  child: const Text("New here? Create an account"),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Sign up

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _adult = false;
  bool _agreed = false;
  bool _consent = false;
  bool _busy = false;
  String? _error;
  String? _sentTo;

  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => context.push(AppRoutes.privacy);
  late final TapGestureRecognizer _disclaimerTap = TapGestureRecognizer()
    ..onTap = () => context.push(AppRoutes.disclaimer);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _privacyTap.dispose();
    _disclaimerTap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    if (!_adult || !_agreed || !_consent) {
      setState(() => _error =
          'Please tick all three boxes to create your account.');
      return;
    }
    if (!valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final startedSession = await ref
          .read(repositoryProvider)
          .signUp(_email.text, _password.text);
      if (!startedSession && mounted) {
        setState(() => _sentTo = _email.text.trim());
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sentTo != null) {
      return _AuthLayout(
        title: 'Check your email',
        subtitle: 'We sent a confirmation link to $_sentTo. '
            'Open it, then come back and sign in.',
        children: [
          const NoticeCard(
            icon: Icons.mark_email_unread_outlined,
            text: "Can't find it? Check your spam folder. The link works once.",
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: 'Go to Sign In',
            onPressed: () => context.pushReplacement(AppRoutes.signIn),
          ),
        ],
      );
    }

    final linkStyle = TextStyle(
      color: context.colors.primary,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );

    return _AuthLayout(
      title: 'Create your account',
      subtitle: 'Your data stays private to your account.',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: _validateEmail,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 14),
                _PasswordField(
                  controller: _password,
                  label: 'Password',
                  autofillHints: const [AutofillHints.newPassword],
                  validator: _validateNewPassword,
                ),
                const SizedBox(height: 4),
                Text(
                  'At least 8 characters, with letters and numbers.',
                  style: context.text.bodySmall
                      ?.copyWith(color: context.cycle.muted),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _adult,
                  onChanged: (v) => setState(() => _adult = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I am 18 or older'),
                ),
                CheckboxListTile(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text.rich(
                    TextSpan(
                      style: context.text.bodyMedium,
                      children: [
                        const TextSpan(text: "I've read the "),
                        TextSpan(
                          text: 'privacy notice',
                          style: linkStyle,
                          recognizer: _privacyTap,
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'health disclaimer',
                          style: linkStyle,
                          recognizer: _disclaimerTap,
                        ),
                      ],
                    ),
                  ),
                ),
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(AppText.healthConsentLabel),
                ),
                const SizedBox(height: 8),
                _ErrorText(_error),
                GradientButton(
                  label: 'Create Account',
                  loading: _busy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.pushReplacement(AppRoutes.signIn),
                  child: const Text('Already have an account? Sign in'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Forgot

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return _AuthLayout(
        title: 'Check your email',
        subtitle: 'If an account exists for that address, we have sent a '
            'link to reset your password.',
        children: [
          GradientButton(
            label: 'Back to Sign In',
            onPressed: () => context.pushReplacement(AppRoutes.signIn),
          ),
        ],
      );
    }
    return _AuthLayout(
      title: 'Reset your password',
      subtitle: "Enter your email and we'll send you a reset link.",
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: _validateEmail,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 16),
              _ErrorText(_error),
              GradientButton(
                label: 'Send Reset Link',
                loading: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Reset

/// Shown after opening a password-reset link.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).updatePassword(_password.text);
      if (mounted) showMessage(context, 'Password updated');
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthLayout(
      title: 'Choose a new password',
      subtitle: 'You opened a password reset link.',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PasswordField(
                controller: _password,
                label: 'New password',
                autofillHints: const [AutofillHints.newPassword],
                validator: _validateNewPassword,
              ),
              const SizedBox(height: 14),
              _PasswordField(
                controller: _confirm,
                label: 'Confirm new password',
                validator: (v) =>
                    v != _password.text ? 'Passwords do not match' : null,
                onSubmitted: _submit,
              ),
              const SizedBox(height: 16),
              _ErrorText(_error),
              GradientButton(
                label: 'Save Password',
                loading: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(repositoryProvider).signOut(),
                child: Text(
                  'Cancel and sign out',
                  style: TextStyle(color: AppTheme.plum.withValues(alpha: 0.8)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
