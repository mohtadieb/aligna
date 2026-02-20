import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_dashboard_page.dart';

class ArchivedSessionsPage extends StatefulWidget {
  const ArchivedSessionsPage({super.key});

  @override
  State<ArchivedSessionsPage> createState() => _ArchivedSessionsPageState();
}

class _ArchivedSessionsPageState extends State<ArchivedSessionsPage> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _loadArchived();
  }

  Future<void> _loadArchived() async {
    setState(() => _loading = true);

    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _sessions = [];
        _loading = false;
      });
      return;
    }

    final res = await sb
        .from('pair_sessions')
        .select('id, created_by, partner_id, invite_code, status, created_at, completed_at, archived_at')
        .or('created_by.eq.$uid,partner_id.eq.$uid')
        .not('archived_at', 'is', null)
        .order('archived_at', ascending: false);

    if (!mounted) return;

    setState(() {
      _sessions = (res as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  String _statusLabel(Map<String, dynamic> s) {
    final status = (s['status'] as String?) ?? 'waiting';
    if (status == 'completed') return 'Completed ✅';
    final partnerId = s['partner_id'] as String?;
    if (partnerId == null) return 'Waiting for partner';
    return 'Active';
  }

  Color _statusBg(Map<String, dynamic> s) {
    final status = (s['status'] as String?) ?? 'waiting';
    if (status == 'completed') return Colors.green.withOpacity(0.12);
    final partnerId = s['partner_id'] as String?;
    if (partnerId == null) return Colors.orange.withOpacity(0.12);
    return Colors.blue.withOpacity(0.12);
  }

  Future<void> _unarchive(String sessionId) async {
    await sb.from('pair_sessions').update({'archived_at': null}).eq('id', sessionId);
    await _loadArchived();
  }

  @override
  Widget build(BuildContext context) {
    final user = sb.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archived sessions'),
        actions: [
          IconButton(
            onPressed: _loadArchived,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: user == null
            ? const Center(child: Text('Please log in first.'))
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : _sessions.isEmpty
            ? const Center(
          child: Text(
            'No archived sessions.',
            style: TextStyle(color: Colors.black54),
          ),
        )
            : ListView.separated(
          itemCount: _sessions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final s = _sessions[i];
            final id = s['id'] as String;
            final invite = s['invite_code'] as String? ?? '';
            final label = _statusLabel(s);

            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionDashboardPage(sessionId: id),
                  ),
                );
                await _loadArchived();
              },
              onLongPress: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Unarchive session?'),
                    content: const Text('This will move it back to your sessions list.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Unarchive'),
                      ),
                    ],
                  ),
                );

                if (ok == true) {
                  await _unarchive(id);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            invite.isEmpty ? 'Session' : invite,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$label • Long-press to unarchive',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _statusBg(s),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label.replaceAll(' ✅', ''),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
