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

  bool _loading = false;

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final code = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'AL-$code';
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final session = sb.auth.currentSession;

      if (session == null) {
        throw Exception('You are not logged in.');
      }

      final userId = session.user.id;
      final invite = _generateInviteCode();

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
        SnackBar(content: Text('Failed to create session: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _pageBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        children: [
          Image.asset(
            'assets/icon/aligna_inapp_icon.png',
            height: 28,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Create session',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
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
                    'Create a private\nsession',
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Start a new Aligna session and invite your partner with a private code.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                    'What happens next?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CreateStep(
                    icon: Icons.auto_awesome_rounded,
                    title: 'A session gets created instantly',
                    subtitle: 'We’ll generate a private invite code for you.',
                  ),
                  const SizedBox(height: 12),
                  _CreateStep(
                    icon: Icons.share_rounded,
                    title: 'Share your invite code',
                    subtitle: 'Send it to your partner so they can join your session.',
                  ),
                  const SizedBox(height: 12),
                  _CreateStep(
                    icon: Icons.favorite_outline_rounded,
                    title: 'Start answering together',
                    subtitle: 'Your results update as both of you complete modules.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _softPurple,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'Your session is private. Only someone with your invite code can join.',
                style: TextStyle(
                  color: Colors.black54,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _gradientButton(
              text: _loading ? 'Creating...' : 'Create session',
              onPressed: _loading ? null : _create,
              icon: Icons.add_circle_outline_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _CreateStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF8F5FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF6A42E8),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}