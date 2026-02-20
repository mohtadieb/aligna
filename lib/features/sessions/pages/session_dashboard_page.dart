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

  // Module progress
  List<Map<String, dynamic>> _modules = [];
  final Map<String, int> _totalByModule = {};
  final Map<String, int> _answeredByModule = {};
  final Map<String, int> _otherAnsweredByModule = {};

  // ✅ Continue behavior (MY progress only)
  String? _firstMyIncompleteModuleId;
  String? _firstMyIncompleteModuleTitle;

  RealtimeChannel? _sessionChannel;
  Timer? _reloadDebounce;

  // ✅ Completed celebration (show once per session per user)
  bool _celebrationShowing = false;
  bool _checkedCompletionOnceAfterInitialLoad = false;

  String get _currentUserId {
    final id = sb.auth.currentUser?.id;
    // If you ever support "anonymous / no auth", you can fall back to device id.
    return id ?? 'unknown_user';
  }

  static const String _celebrationPrefPrefix = 'aligna:celebration_shown';

  String _celebrationKey() => '$_celebrationPrefPrefix:${_currentUserId}:${widget.sessionId}';

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

        // ✅ Celebration trigger (status becomes completed)
        if (statusChanged && newStatus == 'completed') {
          await _maybeShowCompletedCelebration();
        }

        // ✅ Only reload for meaningful changes
        if (!partnerJustJoined && !statusChanged) return;

        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
          if (mounted) _loadAll(showLoading: false);
        });
      },
    )
        .subscribe();
  }

  // ✅ Finds first incomplete module for *ME only*
  String? _computeFirstMyIncompleteModuleId() {
    for (final m in _modules) {
      final moduleId = m['id'] as String;
      final total = _totalByModule[moduleId] ?? 0;
      final myAnswered = _answeredByModule[moduleId] ?? 0;

      // Treat empty module as incomplete
      if (total == 0) return moduleId;

      if (myAnswered < total) return moduleId;
    }
    return null;
  }

  Future<void> _maybeShowCompletedCelebration() async {
    if (!mounted) return;
    if (_celebrationShowing) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_celebrationKey()) ?? false;
    if (alreadyShown) return;

    _celebrationShowing = true;
    await prefs.setBool(_celebrationKey(), true);

    // Show after frame to avoid flicker / conflicts with rebuild
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

      // Supabase can return Map or List depending on settings
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

      // ✅ If user opens dashboard after session already completed, still show once.
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

  @override
  Widget build(BuildContext context) {
    if (_loading || _session == null) {
      return const Scaffold(
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
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          IconButton(
            onPressed: () => _loadAll(showLoading: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invite code', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Text(
                      inviteCode,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: inviteCode));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy',
                )
              ],
            ),
            const SizedBox(height: 14),
            Text(
              partnerJoined ? 'Partner joined ✅' : 'Partner hasn’t joined yet — you can already start.',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Progress',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text('You: $_myCount / $_totalQuestions'),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(value: myProgress, minHeight: 8),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    partnerJoined ? 'Partner: $_otherCount / $_totalQuestions' : 'Partner: not joined yet',
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(value: otherProgress, minHeight: 8),
                  ),
                  const SizedBox(height: 12),
                  if (hasMyIncomplete && _firstMyIncompleteModuleTitle != null)
                    Text(
                      partnerJoined
                          ? 'Next up: $_firstMyIncompleteModuleTitle ($nextMine/$nextTotal • Partner $nextOther/$nextTotal)'
                          : 'Next up: $_firstMyIncompleteModuleTitle ($nextMine/$nextTotal)',
                      style: const TextStyle(color: Colors.black54),
                    )
                  else
                    const Text(
                      'You’ve completed all modules.',
                      style: TextStyle(color: Colors.black54),
                    ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResultsPage(sessionId: widget.sessionId),
                    ),
                  );
                },
                child: const Text('View Results'),
              ),
            ),
            if (hasMyIncomplete) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _continue,
                  child: const Text('Continue'),
                ),
              ),
            ],
            const SizedBox(height: 12),
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
                child: const Text('Open module list'),
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
  State<_CompletedCelebrationDialog> createState() => _CompletedCelebrationDialogState();
}

class _CompletedCelebrationDialogState extends State<_CompletedCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Pre-generated particles (so no random changes mid-animation)
  late final List<_ConfettiParticle> _particles;
  final _rand = Random();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward(); // play once

    _particles = List.generate(90, (_) => _makeParticle());
  }

  _ConfettiParticle _makeParticle() {
    // Launch upwards-ish from the top-center area
    final angle = (-pi / 2) + (_rand.nextDouble() * 0.9 - 0.45); // around straight up
    final speed = 250 + _rand.nextDouble() * 260; // px/s
    final size = 4 + _rand.nextDouble() * 6;

    // Slight variation in gravity + spin
    final gravity = 650 + _rand.nextDouble() * 550;
    final rotationSpeed = (_rand.nextDouble() * 8 - 4);

    // Confetti palette
    const colors = [
      Color(0xFF5B8DEF),
      Color(0xFF7ED957),
      Color(0xFFFFC857),
      Color(0xFFFF6B6B),
      Color(0xFFB16CEA),
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
      // small horizontal spread from center
      xOffset: (_rand.nextDouble() * 120) - 60,
      // start slightly above the emoji area
      yOffset: -10 - _rand.nextDouble() * 20,
      // some are rectangles, some are circles
      isCircle: _rand.nextBool(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // 🎊 Confetti layer (behind content)
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

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🎉', style: theme.textTheme.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Both of you finished!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your session is complete. You can view your results now.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Not now'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onViewResults();
                          },
                          child: const Text('View Results'),
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

  // Relative start offsets from the burst origin
  final double xOffset;
  final double yOffset;

  final bool isCircle;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.t,
    required this.particles,
  });

  final double t; // 0..1
  final List<_ConfettiParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    // Burst origin near top-middle inside the dialog
    final origin = Offset(size.width / 2, 58);

    // Convert t into seconds for physics
    final totalSeconds = 1.1;
    final time = t * totalSeconds;

    for (final p in particles) {
      // Initial velocity components
      final vx = cos(p.angle) * p.speed;
      final vy = sin(p.angle) * p.speed;

      // Position under gravity (y positive downward)
      final dx = (vx * time) + p.xOffset;
      final dy = (vy * time) + (0.5 * p.gravity * time * time) + p.yOffset;

      // Slight fade near end
      final fade = (t < 0.85) ? 1.0 : (1.0 - ((t - 0.85) / 0.15)).clamp(0.0, 1.0);

      // Only draw while still mostly within the dialog bounds
      final pos = origin + Offset(dx, dy);
      if (pos.dy > size.height + 20) continue;

      final paint = Paint()..color = p.color.withValues(alpha: 0.9 * fade);

      // Spin
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