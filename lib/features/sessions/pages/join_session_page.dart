import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase/session_service.dart';
import 'session_dashboard_page.dart';

class JoinSessionPage extends StatefulWidget {
  final String? initialCode;
  const JoinSessionPage({super.key, this.initialCode});

  @override
  State<JoinSessionPage> createState() => _JoinSessionPageState();
}

class _JoinSessionPageState extends State<JoinSessionPage> {
  final sb = Supabase.instance.client;
  final _service = SessionService();

  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null && widget.initialCode!.trim().isNotEmpty) {
      _controller.text = widget.initialCode!.trim().toUpperCase();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _loading = true);

    try {
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final session = await _service.joinByInviteCode(code);

      final sessionId = session['id'] as String;
      final partnerId = session['partner_id'] as String?;

      // Safety: if partner is still null, something went wrong
      if (partnerId == null) {
        throw Exception('Could not join this session yet. Please try again.');
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SessionDashboardPage(sessionId: sessionId),
        ),
      );
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();

      if (msg.contains('invalid invite code')) {
        _show('Invalid invite code');
      } else if (msg.contains('session already joined')) {
        _show('This session already has a partner.');
      } else if (msg.contains('cannot join your own session')) {
        _show('You created this session. Open it from your sessions list.');
      } else {
        _show('Failed to join: ${e.message}');
      }
    } catch (e) {
      _show('Failed to join: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final hasPrefill = widget.initialCode != null && widget.initialCode!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Join session')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              hasPrefill
                  ? 'Invite detected ✅\nConfirm and join.'
                  : 'Paste the invite code your partner shared.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Invite code',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _join,
                child: Text(_loading ? 'Joining...' : 'Join'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
