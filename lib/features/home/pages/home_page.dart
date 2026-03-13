import 'dart:async';

import 'package:app/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ RevenueCat UI + service
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../../../services/revenuecat/revenuecat_service.dart';

// ✅ Pro explainer page (single entry point)
import '../../../pages/premium/premium_paywall_page.dart';

import '../../sessions/pages/create_session_page.dart';
import '../../sessions/pages/join_session_page.dart';
import '../../sessions/pages/session_dashboard_page.dart';
import '../../sessions/pages/archived_sessions_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _sessions = [];

  RealtimeChannel? _channel;
  Timer? _reloadDebounce;

  StreamSubscription<AuthState>? _authSub;

  static const _brandGradient = LinearGradient(
    colors: [
      Color(0xFF7B5CF0),
      Color(0xFFE96BD2),
      Color(0xFFFFA96C),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  void initState() {
    super.initState();

    _listenToAuthChanges();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await RevenueCatService.instance.handleAuthUserChanged();

      if (!mounted) return;

      if (sb.auth.currentUser != null) {
        await _loadMySessions(showLoading: true);
        _setupRealtime();
      } else {
        setState(() {
          _loading = false;
          _sessions = [];
        });
      }
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _authSub?.cancel();
    _stopRealtime();
    super.dispose();
  }

  void _listenToAuthChanges() {
    _authSub = sb.auth.onAuthStateChange.listen((event) async {
      final user = sb.auth.currentUser;

      await RevenueCatService.instance.handleAuthUserChanged();

      if (user == null) {
        _reloadDebounce?.cancel();
        _stopRealtime();

        if (!mounted) return;
        setState(() {
          _sessions = [];
          _loading = false;
        });
        return;
      }

      _setupRealtime();
      await _loadMySessions(showLoading: true);

      if (mounted) setState(() {});
    });
  }

  void _stopRealtime() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  void _setupRealtime() {
    if (sb.auth.currentUser == null) return;
    if (_channel != null) return;

    _channel = sb.channel('realtime:pair_sessions_home');

    _channel!
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'pair_sessions',
      callback: (payload) {
        final uid = sb.auth.currentUser?.id;
        if (uid == null) return;

        final newRow = payload.newRecord;
        final oldRow = payload.oldRecord;

        if (newRow == null || oldRow == null) return;

        final newCreatedBy = newRow['created_by'] as String?;
        final newPartnerId = newRow['partner_id'] as String?;
        final oldCreatedBy = oldRow['created_by'] as String?;
        final oldPartnerId = oldRow['partner_id'] as String?;

        final belongsToMe = (newCreatedBy == uid) ||
            (newPartnerId == uid) ||
            (oldCreatedBy == uid) ||
            (oldPartnerId == uid);

        if (!belongsToMe) return;

        final oldStatus = oldRow['status'] as String?;
        final newStatus = newRow['status'] as String?;

        final partnerJustJoined = (oldPartnerId == null) && (newPartnerId != null);
        final justCompleted = (oldStatus != 'completed') && (newStatus == 'completed');

        if (!partnerJustJoined && !justCompleted) return;

        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
          if (mounted) _loadMySessions(showLoading: false);
        });
      },
    ).subscribe();
  }

  Future<void> _loadMySessions({bool showLoading = true}) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() => _loading = true);
    }

    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _sessions = [];
        _loading = false;
      });
      return;
    }

    try {
      final res = await sb
          .from('pair_sessions')
          .select('id, created_by, partner_id, invite_code, status, created_at, completed_at')
          .or('created_by.eq.$uid,partner_id.eq.$uid')
          .isFilter('archived_at', null)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _sessions = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _statusLabel(Map<String, dynamic> s) {
    final status = (s['status'] as String?) ?? 'waiting';
    if (status == 'completed') return 'Completed';
    final partnerId = s['partner_id'] as String?;
    if (partnerId == null) return 'Waiting for partner';
    return 'Active';
  }

  Color _statusBg(Map<String, dynamic> s) {
    final status = (s['status'] as String?) ?? 'waiting';
    if (status == 'completed') return Colors.green.withOpacity(0.12);
    final partnerId = s['partner_id'] as String?;
    if (partnerId == null) return Colors.orange.withOpacity(0.12);
    return const Color(0xFF7B5CF0).withOpacity(0.12);
  }

  Color _statusText(Map<String, dynamic> s) {
    final status = (s['status'] as String?) ?? 'waiting';
    if (status == 'completed') return Colors.green.shade700;
    final partnerId = s['partner_id'] as String?;
    if (partnerId == null) return Colors.orange.shade800;
    return const Color(0xFF6A42E8);
  }

  bool _canDelete(Map<String, dynamic> s) {
    final me = sb.auth.currentUser?.id;
    final createdBy = s['created_by'] as String?;
    final partnerId = s['partner_id'] as String?;
    final status = (s['status'] as String?) ?? 'waiting';

    return me != null && createdBy == me && partnerId == null && status != 'completed';
  }

  Future<void> _archiveSession(String sessionId) async {
    await sb
        .from('pair_sessions')
        .update({'archived_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', sessionId);

    await _loadMySessions(showLoading: true);
  }

  Future<void> _deleteSession(String sessionId) async {
    await sb.from('pair_sessions').delete().eq('id', sessionId);
    await _loadMySessions(showLoading: true);
  }

  Future<void> _showSessionActions(Map<String, dynamic> s) async {
    final id = s['id'] as String;
    final invite = (s['invite_code'] as String?) ?? 'Session';
    final canDelete = _canDelete(s);

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('Archive'),
                  subtitle: const Text('Hide from your sessions list'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _archiveSession(id);
                  },
                ),
                if (canDelete) ...[
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text(
                      'Delete session',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('Only possible before your partner joins'),
                    onTap: () async {
                      Navigator.pop(ctx);

                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: const Text('Delete session?'),
                          content: const Text(
                            'This permanently deletes the session and its responses.\n\nThis cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );

                      if (ok == true) {
                        await _deleteSession(id);
                      }
                    },
                  ),
                ],
                if (!canDelete) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Delete is only available for sessions you created before your partner joins.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPro() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PremiumPaywallPage()),
    );

    if (changed == true) {
      await RevenueCatService.instance.refresh();
      if (mounted) setState(() {});
    }
  }

  Future<void> _openProManagement() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aligna Pro',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restore),
                  title: const Text('Restore purchases'),
                  subtitle: const Text('If you already bought Pro on this account'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await RevenueCatService.instance.restore();
                      await RevenueCatService.instance.refresh();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Restore complete')),
                      );
                      setState(() {});
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Restore failed: $e')),
                      );
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Customer Center'),
                  subtitle: const Text('Manage purchases'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await RevenueCatUI.presentCustomerCenter();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Customer Center failed: $e')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _proChip() {
    return ValueListenableBuilder<bool>(
      valueListenable: RevenueCatService.instance.isReady,
      builder: (_, ready, __) {
        return ValueListenableBuilder<bool>(
          valueListenable: RevenueCatService.instance.isPro,
          builder: (_, isPro, __) {
            final label = !ready ? '…' : (isPro ? 'Pro' : 'Unlock Pro');
            final icon = !ready
                ? Icons.hourglass_top
                : (isPro ? Icons.verified_rounded : Icons.lock_outline_rounded);

            return Container(
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                gradient: isPro ? _brandGradient : null,
                color: isPro ? null : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: isPro ? null : Border.all(color: Colors.black12),
              ),
              child: TextButton.icon(
                onPressed: !ready ? null : (isPro ? _openProManagement : _openPro),
                icon: Icon(
                  icon,
                  size: 18,
                  color: isPro ? Colors.white : const Color(0xFF6A42E8),
                ),
                label: Text(
                  label,
                  style: TextStyle(
                    color: isPro ? Colors.white : const Color(0xFF6A42E8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: _brandGradient,
        borderRadius: BorderRadius.circular(28),
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
            'Build stronger\nrelationship clarity',
            style: TextStyle(
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Create a private session, invite your partner, and discover your compatibility together.',
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String text,
    required VoidCallback onPressed,
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
          minimumSize: const Size.fromHeight(56),
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE8DFFB)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6A42E8),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_outline_rounded,
                size: 44,
                color: Color(0xFF7B5CF0),
              ),
              SizedBox(height: 14),
              Text(
                'No sessions yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Create one or join with a code to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final invite = s['invite_code'] as String? ?? '';
    final label = _statusLabel(s);

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionDashboardPage(sessionId: id),
          ),
        );
        await _loadMySessions(showLoading: true);
      },
      onLongPress: () => _showSessionActions(s),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: const Color(0xFFF0EAFB)),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: _brandGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invite.isEmpty ? 'Session' : invite,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _statusBg(s),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _statusText(s),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5FF),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset(
              'assets/icon/aligna_inapp_icon.png',
              width: 28,
              height: 28,
            ),
            const SizedBox(width: 10),
            const Text(
              'Aligna',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ],
        ),
        actions: [
          _proChip(),
          IconButton(
            onPressed: () => _loadMySessions(showLoading: true),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 18),
              _buildPrimaryButton(
                text: 'Create session',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateSessionPage()),
                  );
                  await _loadMySessions(showLoading: true);
                },
              ),
              const SizedBox(height: 12),
              _buildSecondaryButton(
                text: 'Join session',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JoinSessionPage()),
                  );
                  await _loadMySessions(showLoading: true);
                },
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Your sessions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ArchivedSessionsPage()),
                      );
                      await _loadMySessions(showLoading: true);
                    },
                    child: const Text(
                      'Archived',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6A42E8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_sessions.isEmpty)
                _buildEmptyState()
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final s = _sessions[i];
                      return _buildSessionCard(s);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}