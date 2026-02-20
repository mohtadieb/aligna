import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../home/pages/home_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _isLogin = true;

  Future<void> _submit() async {
    setState(() => _loading = true);

    try {
      final sb = Supabase.instance.client;
      final email = _email.text.trim();
      final pass = _password.text;

      if (_isLogin) {
        await sb.auth.signInWithPassword(email: email, password: pass);
      } else {
        // Create account
        await sb.auth.signUp(email: email, password: pass);

        // IMPORTANT: sign up may not create a session if email confirmation is enabled,
        // so we sign in right after.
        await sb.auth.signInWithPassword(email: email, password: pass);
      }

      // No manual navigation needed anymore — AuthGate will swap screens.
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aligna')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading
                    ? 'Please wait...'
                    : (_isLogin ? 'Login' : 'Create account')),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() => _isLogin = !_isLogin),
              child: Text(_isLogin
                  ? 'No account? Create one'
                  : 'Have an account? Login'),
            ),
          ],
        ),
      ),
    );
  }
}
