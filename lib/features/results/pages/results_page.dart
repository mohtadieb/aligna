import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../pages/premium/premium_paywall_page.dart';
import '../../../services/supabase/content_service.dart';
import '../../../services/supabase/session_service.dart';
import '../../../services/supabase/results_service.dart';
import '../../../services/supabase/premium_service.dart';

class ResultsPage extends StatefulWidget {
  final String sessionId;
  const ResultsPage({super.key, required this.sessionId});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  final _content = ContentService();
  final _sessionService = SessionService();
  final _resultsService = ResultsService();
  final _premiumService = PremiumService();

  bool _loading = true;

  Map<String, dynamic>? _session;
  List<Map<String, dynamic>> _modules = [];
  final Map<String, List<Map<String, dynamic>>> _questionsByModule = {};

  Map<String, String> _me = {};
  Map<String, String> _partner = {}; // actually: "other user" in the session

  int _totalQuestions = 0;
  int _myCount = 0;
  int _partnerCount = 0;

  bool _isPremium = false;

  RealtimeChannel? _responsesChannel;
  RealtimeChannel? _sessionChannel;
  Timer? _reloadDebounce;

  // ⚡ Performance: cache modules + questions (static content) so realtime reloads
  // only re-fetch session + responses.
  bool _contentLoaded = false;

  @override
  void initState() {
    super.initState();
    _load().then((_) => _setupRealtime());
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    final sb = Supabase.instance.client;
    if (_responsesChannel != null) sb.removeChannel(_responsesChannel!);
    if (_sessionChannel != null) sb.removeChannel(_sessionChannel!);
    super.dispose();
  }

  String? _otherUserId(Map<String, dynamic> session) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return null;

    final createdBy = session['created_by'] as String?;
    final partnerId = session['partner_id'] as String?;

    if (createdBy == null || partnerId == null) return null;

    return myId == createdBy ? partnerId : createdBy;
  }

  Future<void> _openPaywall() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PremiumPaywallPage()),
    );

    // If paywall returns true (or any non-null), refresh premium state
    if (changed == true && mounted) {
      await _refreshPremiumOnly();
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshPremiumOnly() async {
    try {
      final p = await _premiumService.hasPremium();
      _isPremium = p;
    } catch (_) {
      // If RPC fails, keep previous state (don’t break results)
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);

    final sb = Supabase.instance.client;
    final myId = sb.auth.currentUser!.id;

    // Premium state (cheap RPC)
    try {
      _isPremium = await _premiumService.hasPremium();
    } catch (_) {
      // Keep previous value
    }

    // Always fetch session + responses (dynamic)
    final session = await _sessionService.getSession(widget.sessionId);
    final otherId = _otherUserId(session);

    // ⚡ Load content once (static)
    if (!_contentLoaded) {
      final modules = await _content.fetchModules();
      final moduleIds = modules.map((m) => m['id'] as String).toList();

      final allQuestions = await _content.fetchQuestionsForModules(moduleIds);

      final questionsByModule = <String, List<Map<String, dynamic>>>{};
      for (final id in moduleIds) {
        questionsByModule[id] = <Map<String, dynamic>>[];
      }

      int total = 0;
      for (final q in allQuestions) {
        final mid = q['module_id'] as String;
        (questionsByModule[mid] ??= <Map<String, dynamic>>[]).add(q);
        total += 1;
      }

      _modules = modules;
      _questionsByModule
        ..clear()
        ..addAll(questionsByModule);
      _totalQuestions = total;

      _contentLoaded = true;
    }

    // Responses
    final myMap = await _resultsService.getResponsesMapForUser(
      sessionId: widget.sessionId,
      userId: myId,
    );

    Map<String, String> otherMap = {};
    if (otherId != null) {
      otherMap = await _resultsService.getResponsesMapForUser(
        sessionId: widget.sessionId,
        userId: otherId,
      );
    }

    if (!mounted) return;

    setState(() {
      _session = session;

      _me = myMap;
      _partner = otherMap;

      _myCount = myMap.length;
      _partnerCount = otherMap.length;

      _loading = false;
    });
  }

  void _setupRealtime() {
    final sb = Supabase.instance.client;

    // Clean previous
    if (_responsesChannel != null) {
      sb.removeChannel(_responsesChannel!);
      _responsesChannel = null;
    }
    if (_sessionChannel != null) {
      sb.removeChannel(_sessionChannel!);
      _sessionChannel = null;
    }

    // 1) responses changes (live scoring)
    _responsesChannel = sb.channel('realtime:responses:${widget.sessionId}');
    _responsesChannel!
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'responses',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'session_id',
        value: widget.sessionId,
      ),
      callback: (_) {
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 350), () {
          _load(silent: true);
        });
      },
    )
        .subscribe();

    // 2) session row changes (partner joins / completed status)
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
      callback: (payload) {
        final newRow = payload.newRecord;
        if (newRow == null) return;

        final oldRow = payload.oldRecord ?? const <String, dynamic>{};

        final oldPartner = oldRow['partner_id'] as String?;
        final newPartner = newRow['partner_id'] as String?;

        final oldStatus = oldRow['status'] as String?;
        final newStatus = newRow['status'] as String?;

        final partnerJustJoined = oldPartner == null && newPartner != null;
        final statusChanged = oldStatus != newStatus;

        if (!partnerJustJoined && !statusChanged) return;

        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
          _load(silent: true);
        });
      },
    )
        .subscribe();
  }

  bool get _partnerJoined => (_session?['partner_id'] as String?) != null;

  // ✅ Trust DB status (because you have triggers)
  bool get _finalReady => ((_session?['status'] as String?) == 'completed');

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final overall = _computeOverallScore();
    final buckets = _alignmentBuckets();
    String listOrDash(List<String> items) => items.isEmpty ? '—' : items.join(', ');

    final mismatchLimit = _isPremium ? 20 : 5;

    return Scaffold(
      appBar: AppBar(
        title: Text(_finalReady ? 'Results (Final)' : 'Results (Live)'),
        actions: [
          IconButton(
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(
            partnerJoined: _partnerJoined,
            total: _totalQuestions,
            myCount: _myCount,
            partnerCount: _partnerCount,
            finalReady: _finalReady,
          ),
          const SizedBox(height: 16),

          // ✅ Overall + Insight
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
                  'Overall compatibility',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                if (!_partnerJoined)
                  const Text(
                    'Waiting for partner to join to calculate compatibility.',
                    style: TextStyle(color: Colors.black54),
                  )
                else if (overall == null)
                  const Text(
                    'Not enough shared answers yet.',
                    style: TextStyle(color: Colors.black54),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${overall.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (overall / 100).clamp(0, 1),
                            minHeight: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Quick insight',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (!_isPremium)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: const Text(
                          'Premium',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                if (!_partnerJoined || overall == null)
                  const Text(
                    'Answer more questions together to unlock insights.',
                    style: TextStyle(color: Colors.black54),
                  )
                else if (_isPremium) ...[
                  Text('🟢 Strong alignment in: ${listOrDash(buckets.strong)}'),
                  const SizedBox(height: 6),
                  Text('🟡 Moderate alignment in: ${listOrDash(buckets.moderate)}'),
                  const SizedBox(height: 6),
                  Text('🔴 Major differences in: ${listOrDash(buckets.major)}'),
                ] else ...[
                  const Text(
                    'Unlock Premium to see deep insights across modules.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _openPaywall,
                      child: const Text('Unlock Premium'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            'Module scores',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ..._modules.map((m) {
            final moduleId = m['id'] as String;
            final title = m['title'] as String;
            final qs = _questionsByModule[moduleId] ?? const [];

            final score = _computeModuleScore(qs, _me, _partner);
            final label = score == null ? '—' : '${score.toStringAsFixed(0)}%';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ModuleScoreTile(
                title: title,
                scoreLabel: label,
                progress: score == null ? null : (score / 100.0),
                subtitle: _partnerJoined
                    ? (_finalReady ? 'Final' : 'Live (updates automatically)')
                    : 'Waiting for partner to join',
              ),
            );
          }),

          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Top mismatches',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (!_isPremium)
                TextButton(
                  onPressed: _openPaywall,
                  child: const Text('Unlock full'),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (!_partnerJoined)
            const _EmptyHint(
              text: 'Partner hasn’t joined yet. Mismatches will appear once both answer.',
            )
          else ...[
            ..._buildTopMismatches(limit: mismatchLimit),
            if (!_isPremium)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Showing $mismatchLimit mismatches. Unlock Premium to see more.',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
          ],

          const SizedBox(height: 24),

          // Export gating
          if (_finalReady) ...[
            if (_isPremium)
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('PDF export comes in phase 2 ✅')),
                    );
                  },
                  child: const Text('Export Final Report (Soon)'),
                ),
              )
            else
              Column(
                children: [
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _openPaywall,
                      child: const Text('Unlock Premium to Export'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Export is a Premium feature.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
          ] else
            const _EmptyHint(
              text: 'Live results are shown now. Final results unlock when both finish all questions.',
            ),
        ],
      ),
    );
  }

  double? _computeModuleScore(
      List<Map<String, dynamic>> questions,
      Map<String, String> a,
      Map<String, String> b,
      ) {
    if (!_partnerJoined) return null;

    double mismatchSum = 0;
    double maxSum = 0;

    for (final q in questions) {
      final qid = q['id'] as String;
      final qtype = q['qtype'] as String;
      final weight = (q['weight'] as int?) ?? 1;

      final av = a[qid];
      final bv = b[qid];

      if (av == null || bv == null) continue;

      final maxForQ = _maxMismatchForType(qtype) * weight;
      final mismatch = _mismatchFor(qtype, av, bv) * weight;

      maxSum += maxForQ;
      mismatchSum += mismatch;
    }

    if (maxSum <= 0) return null;

    final score = 100 - (mismatchSum / maxSum) * 100;
    return score.clamp(0, 100);
  }

  // ✅ Overall score across ALL questions (weighted)
  double? _computeOverallScore() {
    if (!_partnerJoined) return null;

    double mismatchSum = 0;
    double maxSum = 0;

    for (final m in _modules) {
      final moduleId = m['id'] as String;
      final qs = _questionsByModule[moduleId] ?? const [];

      for (final q in qs) {
        final qid = q['id'] as String;
        final qtype = q['qtype'] as String;
        final weight = (q['weight'] as int?) ?? 1;

        final av = _me[qid];
        final bv = _partner[qid];
        if (av == null || bv == null) continue;

        final maxForQ = _maxMismatchForType(qtype) * weight;
        final mismatch = _mismatchFor(qtype, av, bv) * weight;

        maxSum += maxForQ;
        mismatchSum += mismatch;
      }
    }

    if (maxSum <= 0) return null;

    final score = 100 - (mismatchSum / maxSum) * 100;
    return score.clamp(0, 100);
  }

  // ✅ Strong / Moderate / Major buckets based on module scores
  ({List<String> strong, List<String> moderate, List<String> major}) _alignmentBuckets({
    double strongThreshold = 80,
    double moderateThreshold = 55,
  }) {
    final strong = <String>[];
    final moderate = <String>[];
    final major = <String>[];

    if (!_partnerJoined) return (strong: strong, moderate: moderate, major: major);

    for (final m in _modules) {
      final moduleId = m['id'] as String;
      final title = m['title'] as String;
      final qs = _questionsByModule[moduleId] ?? const [];

      final score = _computeModuleScore(qs, _me, _partner);
      if (score == null) continue;

      if (score >= strongThreshold) {
        strong.add(title);
      } else if (score >= moderateThreshold) {
        moderate.add(title);
      } else {
        major.add(title);
      }
    }

    strong.sort();
    moderate.sort();
    major.sort();

    return (strong: strong, moderate: moderate, major: major);
  }

  // ✅ Smarter text comparisons
  String _normalizeText(String s) {
    var t = s.trim().toLowerCase();
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), '');
    return t;
  }

  Set<String> _tokenize(String s) {
    final t = _normalizeText(s);
    if (t.isEmpty) return {};
    return t.split(' ').where((w) => w.isNotEmpty).toSet();
  }

  /// 0..1 similarity (1 = identical)
  double _textSimilarity(String a, String b) {
    final A = _tokenize(a);
    final B = _tokenize(b);
    if (A.isEmpty && B.isEmpty) return 1.0;
    if (A.isEmpty || B.isEmpty) return 0.0;

    final intersection = A.intersection(B).length;
    final union = A.union(B).length;
    if (union == 0) return 0.0;

    return intersection / union;
  }

  double _maxMismatchForType(String qtype) {
    switch (qtype) {
      case 'scale_1_5':
        return 4;
      case 'yes_no':
        return 1;
      case 'single_choice':
        return 1;
      case 'text':
        return 1;
      default:
        return 1;
    }
  }

  double _mismatchFor(String qtype, String a, String b) {
    switch (qtype) {
      case 'scale_1_5':
        final ai = int.tryParse(a) ?? 3;
        final bi = int.tryParse(b) ?? 3;
        return (ai - bi).abs().toDouble();
      case 'yes_no':
      case 'single_choice':
        return a == b ? 0 : 1;
      case 'text':
        final sim = _textSimilarity(a, b);
        return (1.0 - sim).clamp(0.0, 1.0);
      default:
        return a == b ? 0 : 1;
    }
  }

  List<Widget> _buildTopMismatches({int limit = 10}) {
    final entries = <_MismatchEntry>[];

    for (final m in _modules) {
      final moduleId = m['id'] as String;
      final moduleTitle = m['title'] as String;
      final qs = _questionsByModule[moduleId] ?? const [];

      for (final q in qs) {
        final qid = q['id'] as String;
        final qtype = q['qtype'] as String;
        final weight = (q['weight'] as int?) ?? 1;

        final a = _me[qid];
        final b = _partner[qid];
        if (a == null || b == null) continue;

        final mismatch = _mismatchFor(qtype, a, b) * weight;
        if (mismatch <= 0) continue;

        entries.add(_MismatchEntry(
          moduleTitle: moduleTitle,
          questionText: q['text'] as String,
          myAnswer: a,
          partnerAnswer: b,
          severity: mismatch,
        ));
      }
    }

    entries.sort((x, y) => y.severity.compareTo(x.severity));
    final top = entries.take(min(limit, entries.length)).toList();

    if (top.isEmpty) {
      return const [
        _EmptyHint(text: 'No mismatches yet — or not enough answered by both.'),
      ];
    }

    return top.map((e) {
      final prompts = _promptsFor(e.moduleTitle, e.questionText);

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.moduleTitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                e.questionText,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _AnswerChip(label: 'You', value: e.myAnswer)),
                  const SizedBox(width: 10),
                  Expanded(child: _AnswerChip(label: 'Partner', value: e.partnerAnswer)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Talk about this', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ...prompts.map(
                          (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $p'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          final text = prompts.map((p) => '• $p').join('\n');
                          await Clipboard.setData(ClipboardData(text: text));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Prompts copied')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<String> _promptsFor(String moduleTitle, String questionText) {
    final k = questionText.trim().toLowerCase();
    final specific = _promptOverrides[k];
    if (specific != null) return specific;

    return _modulePrompts[moduleTitle] ??
        const [
          'What does your answer look like in real life?',
          'What would make you feel understood on this topic?',
        ];
  }

  static final Map<String, List<String>> _promptOverrides = {
    'should finances be fully shared in marriage?': [
      'What does “shared” mean to you (one account vs shared bills vs full transparency)?',
      'What boundaries would still feel healthy for each of you?',
    ],
    'do you want children?': [
      'What does “having children” mean for your timeline and priorities?',
      'What would make you feel safe and supported in that decision?',
    ],
    'should phones/social media be fully transparent in a relationship?': [
      'What does trust look like for you without feeling controlled?',
      'What boundaries would protect the relationship while respecting privacy?',
    ],
    'is yelling ever acceptable during conflict?': [
      'What does a “safe conflict” look like to each of you?',
      'What should happen if someone crosses the line during an argument?',
    ],
    'how important is religion/faith in daily life?': [
      'What daily practices are non-negotiable for you?',
      'What would a respectful difference look like if your levels aren’t the same?',
    ],
  };

  static final Map<String, List<String>> _modulePrompts = {
    'Values & life goals': [
      'What are your top 3 non-negotiables for the next 5 years?',
      'Where can you compromise and where can you not?',
    ],
    'Money & lifestyle': [
      'What does financial safety mean to you?',
      'How do you want to handle budgets, savings, and big purchases as a team?',
    ],
    'Children & parenting': [
      'What kind of home environment do you want your kids to grow up in?',
      'How should decisions be made when you disagree on parenting?',
    ],
    'Boundaries & communication': [
      'What helps you feel emotionally safe during conflict?',
      'What are your boundaries around privacy, friends, and communication?',
    ],
  };
}

class _StatusCard extends StatelessWidget {
  final bool partnerJoined;
  final int total;
  final int myCount;
  final int partnerCount;
  final bool finalReady;

  const _StatusCard({
    required this.partnerJoined,
    required this.total,
    required this.myCount,
    required this.partnerCount,
    required this.finalReady,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            finalReady ? 'Final results ready ✅' : 'Live results',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('You: $myCount / $total'),
          const SizedBox(height: 4),
          Text(partnerJoined ? 'Partner: $partnerCount / $total' : 'Partner: not joined yet'),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (myCount / total).clamp(0, 1),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleScoreTile extends StatelessWidget {
  final String title;
  final String scoreLabel;
  final double? progress;
  final String subtitle;

  const _ModuleScoreTile({
    required this.title,
    required this.scoreLabel,
    required this.progress,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                scoreLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            )
          else
            const Text('Not enough shared answers yet', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _AnswerChip extends StatelessWidget {
  final String label;
  final String value;

  const _AnswerChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(text, style: const TextStyle(color: Colors.black54)),
    );
  }
}

class _MismatchEntry {
  final String moduleTitle;
  final String questionText;
  final String myAnswer;
  final String partnerAnswer;
  final double severity;

  _MismatchEntry({
    required this.moduleTitle,
    required this.questionText,
    required this.myAnswer,
    required this.partnerAnswer,
    required this.severity,
  });
}
