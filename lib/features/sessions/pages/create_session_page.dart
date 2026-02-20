import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_dashboard_page.dart';

class CreateSessionPage extends StatefulWidget {
  const CreateSessionPage({super.key});

  @override
  State<CreateSessionPage> createState() => _CreateSessionPageState();
}

class _CreateSessionPageState extends State<CreateSessionPage> {
  final SupabaseClient sb = Supabase.instance.client;
  bool _loading = false;

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final code = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'AL-$code';
  }

  Future<void> _create() async {
    setState(() => _loading = true);

    try {
      final session = sb.auth.currentSession;

      if (session == null) {
        throw Exception('You are not logged in.');
      }

      final userId = session.user.id;

      // Generate invite code
      final invite = _generateInviteCode();

      // Insert session
      final result = await sb
          .from('pair_sessions')
          .insert({
        'created_by': userId,
        'invite_code': invite,
        'status': 'waiting',
      })
          .select('id')
          .single();

      final sessionId = result['id'] as String;

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SessionDashboardPage(sessionId: sessionId),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create session: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create session')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Create a new alignment session and share the invite code with your partner.',
              style: TextStyle(color: Colors.black54),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _create,
                child: Text(_loading ? 'Creating...' : 'Create'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
