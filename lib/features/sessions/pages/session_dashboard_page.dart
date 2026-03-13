import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../questions/pages/module_list_page.dart';
import '../../questions/pages/question_flow_page.dart';
import '../../results/pages/results_page.dart';

class SessionDashboardPage extends StatefulWidget {
  final String sessionId;

  const SessionDashboardPage({super.key, required this.sessionId});

  @override
  State<SessionDashboardPage> createState() => _SessionDashboardPageState();
}

class _SessionDashboardPageState extends State<SessionDashboardPage> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _session;

  int _totalQuestions = 0;
  int _myCount = 0;
  int _otherCount = 0;

  List<Map<String, dynamic>> _modules = [];
  final Map<String, int> _totalByModule = {};
  final Map<String, int> _answeredByModule = {};
  final Map<String, int> _otherAnsweredByModule = {};

  String? _firstMyIncompleteModuleId;
  String? _firstMyIncompleteModuleTitle;

  RealtimeChannel? _sessionChannel;
  Timer? _reloadDebounce;

  bool _celebrationShowing = false;
  bool _checkedCompletionOnceAfterInitialLoad = false;

  static const _brandGradient = LinearGradient(
    colors: [
      Color(0xFF7B5CF0),
      Color(0xFFE96BD2),
      Color(0xFFFFA96C),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  String get _currentUserId {
    final id = sb.auth.currentUser?.id;
    return id ?? 'unknown_user';
  }

  static const String _celebrationPrefPrefix = 'app:celebration_shown';

  String _celebrationKey() =>
      '$_celebrationPrefPrefix:${_currentUserId}:${widget.sessionId}';

  @override
  void initState() {
    super.initState();
    _loadAll(showLoading: true).then((_) => _setupSessionRealtime());
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    if (_sessionChannel != null) {
      sb.removeChannel(_sessionChannel!);
      _sessionChannel = null;
    }
    super.dispose();
  }

  void _setupSessionRealtime() {
    if (_sessionChannel != null) return;

    _sessionChannel = sb.channel('realtime:pair_sessions:${widget.sessionId}');

    _sessionChannel!
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'pair_sessions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: widget.sessionId,
      ),
      callback: (payload) async {
        final newRow = payload.newRecord;
        if (newRow == null) return;

        final oldRow = payload.oldRecord ?? const <String, dynamic>{};

        final oldPartner = oldRow['partner_id'] as String?;
        final newPartner = newRow['partner_id'] as String?;

        final oldStatus = oldRow['status'] as String?;
        final newStatus = newRow['status'] as String?;

        final partnerJustJoined = oldPartner == null && newPartner != null;
        final statusChanged = oldStatus != newStatus;

        if (statusChanged && newStatus == 'completed') {
          await _maybeShowCompletedCelebration();
        }

        if (!partnerJustJoined && !statusChanged) return;

        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
          if (mounted) _loadAll(showLoading: false);
        });
      },
    ).subscribe();
  }

  String? _computeFirstMyIncompleteModuleId() {
    for (final m in _modules) {
      final moduleId = m['id'] as String;
      final total = _totalByModule[moduleId] ?? 0;
      final myAnswered = _answeredByModule[moduleId] ?? 0;

      if (total == 0) return moduleId;
      if (myAnswered < total) return moduleId;
    }
    return null;
  }

  Future<void> _maybeShowCompletedCelebration() async {
    if (!mounted || _celebrationShowing) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_celebrationKey()) ?? false;
    if (alreadyShown) return;

    _celebrationShowing = true;
    await prefs.setBool(_celebrationKey(), true);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _CompletedCelebrationDialog(
          onViewResults: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ResultsPage(sessionId: widget.sessionId),
              ),
            );
          },
        ),
      );

      _celebrationShowing = false;
    });
  }

  Future<void> _loadAll({required bool showLoading}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }

    try {
      final raw = await sb.rpc('get_session_dashboard', params: {
        'p_session_id': widget.sessionId,
      });

      final data = (raw is Map<String, dynamic>)
          ? raw
          : (raw is List && raw.isNotEmpty)
          ? (raw.first as Map).cast<String, dynamic>()
          : null;

      if (data == null) {
        throw Exception('Dashboard load failed (no data returned)');
      }

      final session = (data['session'] as Map).cast<String, dynamic>();
      final totalQuestions = (data['total_questions'] as num?)?.toInt() ?? 0;
      final myCount = (data['my_count'] as num?)?.toInt() ?? 0;
      final otherCount = (data['other_count'] as num?)?.toInt() ?? 0;

      final modules = ((data['modules'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

      _totalByModule.clear();
      _answeredByModule.clear();
      _otherAnsweredByModule.clear();

      for (final m in modules) {
        final id = m['id'] as String;
        _totalByModule[id] = (m['total'] as num?)?.toInt() ?? 0;
        _answeredByModule[id] = (m['mine'] as num?)?.toInt() ?? 0;
        _otherAnsweredByModule[id] = (m['other'] as num?)?.toInt() ?? 0;
      }

      _modules = modules;

      final firstMyId = _computeFirstMyIncompleteModuleId();
      String? firstMyTitle;
      if (firstMyId != null) {
        final match = modules.where((m) => m['id'] == firstMyId).toList();
        if (match.isNotEmpty) firstMyTitle = match.first['title'] as String?;
      }

      if (!mounted) return;

      setState(() {
        _session = session;
        _totalQuestions = totalQuestions;
        _myCount = myCount;
        _otherCount = otherCount;
        _modules = modules;
        _firstMyIncompleteModuleId = firstMyId;
        _firstMyIncompleteModuleTitle = firstMyTitle;
        _loading = false;
      });

      if (!_checkedCompletionOnceAfterInitialLoad) {
        _checkedCompletionOnceAfterInitialLoad = true;
        final status = session['status'] as String?;
        if (status == 'completed') {
          await _maybeShowCompletedCelebration();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load session: $e')),
      );
    }
  }

  Future<void> _continue() async {
    final moduleId = _firstMyIncompleteModuleId;
    final title = _firstMyIncompleteModuleTitle;

    if (moduleId == null || title == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionFlowPage(
          sessionId: widget.sessionId,
          moduleId: moduleId,
          moduleTitle: title,
        ),
      ),
    );

    await _loadAll(showLoading: false);
  }

  Widget _buildTopHero({
    required String inviteCode,
    required bool partnerJoined,
  }) {
    return Container(
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
          const Text(
            'Your private\nsession space',
            style: TextStyle(
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            partnerJoined
                ? 'Your partner joined. Keep going and complete the session together.'
                : 'Share your invite code and start answering questions right away.',
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Invite code',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        inviteCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: IconButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: inviteCode));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite code copied')),
                      );
                    },
                    icon: const Icon(
                      Icons.copy_rounded,
                      color: Color(0xFF6A42E8),
                    ),
                    tooltip: 'Copy',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard({
    required bool partnerJoined,
    required double myProgress,
    required double otherProgress,
    required bool hasMyIncomplete,
    required int nextMine,
    required int nextOther,
    required int nextTotal,
  }) {
    return Container(
      width: double.infinity,
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
        border: Border.all(color: const Color(0xFFF0EAFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progress',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'You',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '$_myCount / $_totalQuestions answered',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: myProgress,
              minHeight: 10,
              backgroundColor: const Color(0xFFF0EAFB),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF7B5CF0)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Partner',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            partnerJoined
                ? '$_otherCount / $_totalQuestions answered'
                : 'Not joined yet',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: otherProgress,
              minHeight: 10,
              backgroundColor: const Color(0xFFF0EAFB),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFE96BD2)),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F5FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              hasMyIncomplete && _firstMyIncompleteModuleTitle != null
                  ? partnerJoined
                  ? 'Next up: $_firstMyIncompleteModuleTitle ($nextMine/$nextTotal • Partner $nextOther/$nextTotal)'
                  : 'Next up: $_firstMyIncompleteModuleTitle ($nextMine/$nextTotal)'
                  : 'You’ve completed all modules.',
              style: const TextStyle(
                color: Colors.black87,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(bool partnerJoined) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: partnerJoined
            ? Colors.green.withOpacity(0.10)
            : const Color(0xFFFFA96C).withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            partnerJoined ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 18,
            color: partnerJoined ? Colors.green.shade700 : Colors.orange.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              partnerJoined
                  ? 'Partner joined successfully.'
                  : 'Partner hasn’t joined yet — you can already start.',
              style: TextStyle(
                color: partnerJoined
                    ? Colors.green.shade800
                    : Colors.orange.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientButton({
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
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _outlineButton({
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
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6A42E8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _session == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F5FF),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final inviteCode = _session!['invite_code'] as String;
    final partnerId = _session!['partner_id'] as String?;
    final partnerJoined = partnerId != null;

    final myProgress = _totalQuestions == 0 ? 0.0 : _myCount / _totalQuestions;
    final otherProgress =
    (!partnerJoined || _totalQuestions == 0) ? 0.0 : _otherCount / _totalQuestions;

    final hasMyIncomplete = _firstMyIncompleteModuleId != null;

    final nextId = _firstMyIncompleteModuleId;
    final nextTotal = nextId == null ? 0 : (_totalByModule[nextId] ?? 0);
    final nextMine = nextId == null ? 0 : (_answeredByModule[nextId] ?? 0);
    final nextOther = nextId == null ? 0 : (_otherAnsweredByModule[nextId] ?? 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5FF),
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
                'Session',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _loadAll(showLoading: true),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopHero(
                      inviteCode: inviteCode,
                      partnerJoined: partnerJoined,
                    ),
                    const SizedBox(height: 14),
                    _buildInfoPill(partnerJoined),
                    const SizedBox(height: 16),
                    _buildProgressCard(
                      partnerJoined: partnerJoined,
                      myProgress: myProgress,
                      otherProgress: otherProgress,
                      hasMyIncomplete: hasMyIncomplete,
                      nextMine: nextMine,
                      nextOther: nextOther,
                      nextTotal: nextTotal,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    const Spacer(),
                    _outlineButton(
                      text: 'View Results',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ResultsPage(sessionId: widget.sessionId),
                          ),
                        );
                      },
                    ),
                    if (hasMyIncomplete) ...[
                      const SizedBox(height: 12),
                      _gradientButton(
                        text: 'Continue',
                        onPressed: _continue,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ModuleListPage(sessionId: widget.sessionId),
                            ),
                          );
                          await _loadAll(showLoading: false);
                        },
                        child: const Text(
                          'Open module list',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6A42E8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedCelebrationDialog extends StatefulWidget {
  const _CompletedCelebrationDialog({required this.onViewResults});

  final VoidCallback onViewResults;

  @override
  State<_CompletedCelebrationDialog> createState() =>
      _CompletedCelebrationDialogState();
}

class _CompletedCelebrationDialogState extends State<_CompletedCelebrationDialog>
    with SingleTickerProviderStateMixin {
  static const _brandGradient = LinearGradient(
    colors: [
      Color(0xFF7B5CF0),
      Color(0xFFE96BD2),
      Color(0xFFFFA96C),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _cardBorder = Color(0xFFF0EAFB);
  static const _primaryPurple = Color(0xFF6A42E8);
  static const _softPurple = Color(0xFFF8F5FF);
  static const _softPink = Color(0xFFFFF4FB);

  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;
  final _rand = Random();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();

    _particles = List.generate(90, (_) => _makeParticle());
  }

  _ConfettiParticle _makeParticle() {
    final angle = (-pi / 2) + (_rand.nextDouble() * 0.9 - 0.45);
    final speed = 250 + _rand.nextDouble() * 260;
    final size = 4 + _rand.nextDouble() * 6;
    final gravity = 650 + _rand.nextDouble() * 550;
    final rotationSpeed = (_rand.nextDouble() * 8 - 4);

    const colors = [
      Color(0xFF7B5CF0),
      Color(0xFFE96BD2),
      Color(0xFFFFA96C),
      Color(0xFFB16CEA),
      Color(0xFFFFC857),
      Color(0xFF4ECDC4),
    ];

    return _ConfettiParticle(
      angle: angle,
      speed: speed,
      size: size,
      gravity: gravity,
      rotation: _rand.nextDouble() * pi,
      rotationSpeed: rotationSpeed,
      color: colors[_rand.nextInt(colors.length)],
      xOffset: (_rand.nextDouble() * 120) - 60,
      yOffset: -10 - _rand.nextDouble() * 20,
      isCircle: _rand.nextBool(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _gradientButton({
    required String text,
    required VoidCallback onPressed,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
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
      ),
    );
  }

  Widget _outlineButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: Colors.white,
        side: const BorderSide(color: _cardBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: _primaryPurple,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  return CustomPaint(
                    painter: _ConfettiPainter(
                      t: _controller.value,
                      particles: _particles,
                    ),
                  );
                },
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
              border: Border.all(color: _cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  decoration: const BoxDecoration(
                    gradient: _brandGradient,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                          ),
                        ),
                        child: const Icon(
                          Icons.celebration_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'You both finished!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Your session is complete and your compatibility results are ready to explore together.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _softPurple,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: _primaryPurple,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You can view your final results now or come back to them later from the session page.',
                                style: TextStyle(
                                  color: Colors.black87,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _outlineButton(
                              text: 'Not now',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _gradientButton(
                              text: 'View Results',
                              icon: Icons.arrow_forward_rounded,
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onViewResults();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiParticle {
  _ConfettiParticle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.gravity,
    required this.rotation,
    required this.rotationSpeed,
    required this.color,
    required this.xOffset,
    required this.yOffset,
    required this.isCircle,
  });

  final double angle;
  final double speed;
  final double size;
  final double gravity;
  final double rotation;
  final double rotationSpeed;
  final Color color;
  final double xOffset;
  final double yOffset;
  final bool isCircle;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.t,
    required this.particles,
  });

  final double t;
  final List<_ConfettiParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, 58);
    const totalSeconds = 1.1;
    final time = t * totalSeconds;

    for (final p in particles) {
      final vx = cos(p.angle) * p.speed;
      final vy = sin(p.angle) * p.speed;

      final dx = (vx * time) + p.xOffset;
      final dy = (vy * time) + (0.5 * p.gravity * time * time) + p.yOffset;

      final fade =
      (t < 0.85) ? 1.0 : (1.0 - ((t - 0.85) / 0.15)).clamp(0.0, 1.0);

      final pos = origin + Offset(dx, dy);
      if (pos.dy > size.height + 20) continue;

      final paint = Paint()..color = p.color.withValues(alpha: 0.9 * fade);

      final rot = p.rotation + p.rotationSpeed * time;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(rot);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        final rect = Rect.fromCenter(
          center: Offset.zero,
          width: p.size * 1.1,
          height: p.size * 0.6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          paint,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.t != t;
  }
}