import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordPage extends StatefulWidget {
  final VoidCallback? onPasswordUpdated;

  // ADDED:
  // Pass the recovery token_hash from your deep link into this page.
  // Example from your deep-link handler:
  // ResetPasswordPage(recoveryTokenHash: tokenHash)
  final String? recoveryTokenHash;

  const ResetPasswordPage({
    super.key,
    this.onPasswordUpdated,
    this.recoveryTokenHash, // ADDED
  });

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();

  static const _brandGradient = LinearGradient(
    colors: [
      Color(0xFF7B5CF0),
      Color(0xFFE96BD2),
      Color(0xFFFFA96C),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _pageBg = Color(0xFFF8F5FF);
  static const _cardBorder = Color(0xFFF0EAFB);
  static const _primaryPurple = Color(0xFF6A42E8);
  static const _softPurple = Color(0xFFF8F5FF);

  bool _isSaving = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  // ADDED:
  // Prevents repeated recovery-session verification calls.
  bool _recoverySessionPrepared = false;

  @override
  void initState() {
    super.initState();

    // ADDED:
    // If this page was opened from a recovery deep link, try to create
    // the Supabase recovery session immediately.
    _prepareRecoverySessionIfNeeded();
  }

  @override
  void dispose() {
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  // ADDED:
  // This is the key fix:
  // verifyOTP with OtpType.recovery exchanges the token_hash from the email
  // link for a valid recovery session inside the app.
  Future<void> _prepareRecoverySessionIfNeeded() async {
    if (_recoverySessionPrepared) return;

    // If a session already exists, nothing else is needed.
    final existingSession = Supabase.instance.client.auth.currentSession;
    if (existingSession != null) {
      _recoverySessionPrepared = true;
      return;
    }

    final tokenHash = widget.recoveryTokenHash;
    if (tokenHash == null || tokenHash.isEmpty) {
      return;
    }

    try {
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.recovery,
        tokenHash: tokenHash,
      );

      _recoverySessionPrepared = true;
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error preparing recovery session: $e')),
      );
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _primaryPurple),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _primaryPurple, width: 1.4),
      ),
    );
  }

  Widget _gradientButton({
    required String text,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: _brandGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B5CF0).withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNewPassword() async {
    FocusScope.of(context).unfocus();

    final p1 = _pw1.text.trim();
    final p2 = _pw2.text.trim();

    if (p1.isEmpty || p2.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in both password fields.')),
      );
      return;
    }

    if (p1.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your new password must be at least 8 characters.'),
        ),
      );
      return;
    }

    if (p1 != p2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // ADDED:
      // Make sure the recovery token has been exchanged for a real session
      // before trying to update the password.
      await _prepareRecoverySessionIfNeeded();

      // ADDED:
      // Guard against calling updateUser without a valid recovery session.
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw const AuthException(
          'Recovery session could not be established. Please reopen the password reset link and try again.',
        );
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: p1),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your password has been updated successfully.'),
        ),
      );

      widget.onPasswordUpdated?.call();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const SizedBox(height: 8),
            Center(
              child: Image.asset(
                'assets/icon/aligna_inapp_icon.png',
                height: 74,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: _brandGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7B5CF0).withOpacity(0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose a new\npassword',
                    style: TextStyle(
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Set a secure new password to regain access to your Aligna account.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reset password',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your password should be at least 8 characters and easy for you to remember, but hard for others to guess.',
                    style: TextStyle(
                      color: Colors.black54,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _pw1,
                    obscureText: _obscure1,
                    textInputAction: TextInputAction.next,
                    decoration: _inputDecoration(
                      label: 'New password',
                      icon: Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() => _obscure1 = !_obscure1);
                        },
                        icon: Icon(
                          _obscure1
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pw2,
                    obscureText: _obscure2,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_isSaving) _saveNewPassword();
                    },
                    decoration: _inputDecoration(
                      label: 'Confirm new password',
                      icon: Icons.lock_reset_rounded,
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() => _obscure2 = !_obscure2);
                        },
                        icon: Icon(
                          _obscure2
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _gradientButton(
                    text: _isSaving ? 'Saving...' : 'Save new password',
                    onPressed: _isSaving ? null : _saveNewPassword,
                    icon: Icons.check_circle_outline_rounded,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _softPurple,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'For security, this page should only be opened from the password reset email link.',
                      style: TextStyle(
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}