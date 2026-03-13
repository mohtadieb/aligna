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
  static const _softPink = Color(0xFFFFF4FB);

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

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final session = await _service.joinByInviteCode(code);

      final sessionId = session['id'] as String;
      final partnerId = session['partner_id'] as String?;

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
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

  InputDecoration _inputDecoration() {
    return InputDecoration(
      labelText: 'Invite code',
      hintText: 'AL-XXXXXX',
      prefixIcon: const Icon(
        Icons.key_rounded,
        color: _primaryPurple,
      ),
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
              'Join session',
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
    final hasPrefill = widget.initialCode != null && widget.initialCode!.isNotEmpty;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPrefill ? 'Invite found —\njoin instantly' : 'Join your partner’s\nsession',
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasPrefill
                        ? 'We detected an invite code. Confirm it below and join the session.'
                        : 'Paste the invite code your partner shared with you to enter the session.',
                    style: const TextStyle(
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
                    'Enter invite code',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasPrefill
                        ? 'The code is already filled in below.'
                        : 'Invite codes usually look like AL-XXXXXX.',
                    style: const TextStyle(
                      color: Colors.black54,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _inputDecoration(),
                    onChanged: (value) {
                      final upper = value.toUpperCase();
                      if (upper != value) {
                        _controller.value = _controller.value.copyWith(
                          text: upper,
                          selection: TextSelection.collapsed(offset: upper.length),
                        );
                      }
                    },
                    onSubmitted: (_) {
                      if (!_loading) _join();
                    },
                  ),
                  const SizedBox(height: 18),
                  _gradientButton(
                    text: _loading ? 'Joining...' : 'Join session',
                    onPressed: _loading ? null : _join,
                    icon: Icons.group_add_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hasPrefill ? _softPink : _softPurple,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                hasPrefill
                    ? 'Double-check the code before joining. Once you enter the session, your progress will be linked to it.'
                    : 'Make sure you use the exact code your partner shared. Each session can only be joined by one partner.',
                style: const TextStyle(
                  color: Colors.black54,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}