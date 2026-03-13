import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../pages/premium/premium_paywall_page.dart';
import '../../../services/supabase/content_service.dart';
import '../../../services/supabase/session_service.dart';
import '../../../services/supabase/results_service.dart';

// ✅ RevenueCat source of truth (same as Home)
import '../../../services/revenuecat/revenuecat_service.dart';

// ✅ PDF export
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  bool _loading = true;

  Map<String, dynamic>? _session;
  List<Map<String, dynamic>> _modules = [];
  final Map<String, List<Map<String, dynamic>>> _questionsByModule = {};

  Map<String, String> _me = {};
  Map<String, String> _partner = {}; // actually: "other user" in the session

  int _totalQuestions = 0;
  int _myCount = 0;
  int _partnerCount = 0;

  RealtimeChannel? _responsesChannel;
  RealtimeChannel? _sessionChannel;

  // ✅ NEW: realtime for shared summary changes
  RealtimeChannel? _aiCoupleChannel;

  Timer? _reloadDebounce;

  // ⚡ Performance: cache modules + questions (static content) so realtime reloads
  // only re-fetch session + responses.
  bool _contentLoaded = false;

  // ✅ Keep Pro status reactive without spamming refresh calls
  late final VoidCallback _proListener;

  bool get _isPro => RevenueCatService.instance.isPro.value;

  // ✅ Hard gate: DB truth (prevents spoofing)
  bool _dbPro = false;
  bool _dbProReady = false;

  // ✅ AI summary state
  bool _aiBusy = false; // "I pressed generate" state
  Map<String, dynamic>? _aiSummaryJson;
  String? _aiSummaryRaw; // fallback if JSON parsing fails

  // ✅ Track whether summary came from shared couple cache
  bool _aiSummaryIsShared = false;

  // ✅ Simple error field for generation failures (function / client errors)
  String? _aiErrorMessage;

  // ✅ Shared table generation status (so partner sees "generating" too)
  String? _aiSharedStatus; // generating | ready | error | null
  String? _aiSharedError; // error_message from ai_couple_summaries

  bool get _aiGeneratingFromDb => _aiSharedStatus == 'generating';

  // ✅ Poll so it appears automatically
  Timer? _aiPollTimer;
  int _aiPollTicks = 0;

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
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, color: Colors.white),
        label: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget _outlineButton({
    required String text,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon == null
          ? const SizedBox.shrink()
          : Icon(icon, color: _primaryPurple),
      label: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: _primaryPurple,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: Colors.white,
        side: const BorderSide(color: _cardBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  Widget _buildHeroCard({
    required double? overall,
    required bool partnerJoined,
    required bool finalReady,
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
          Text(
            finalReady ? 'Your final\nrelationship results' : 'Your live\nrelationship results',
            style: const TextStyle(
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            !partnerJoined
                ? 'Waiting for your partner to join before full compatibility insights appear.'
                : finalReady
                ? 'Your final compatibility breakdown is ready to explore.'
                : 'Your results update automatically as both of you answer more questions.',
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
                        'Overall compatibility',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        overall == null ? '—' : '${overall.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    finalReady ? 'Final' : 'Live',
                    style: const TextStyle(
                      color: _primaryPurple,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    _proListener = () async {
      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });

      await _refreshDbPro();
    };
    RevenueCatService.instance.isPro.addListener(_proListener);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initRevenueCat();
    });

    _load().then((_) => _setupRealtime());

    _refreshDbPro();
    _loadAiSummaryFromDb();
  }

  Future<void> _initRevenueCat() async {
    try {
      await RevenueCatService.instance.configureIfNeeded();
      await RevenueCatService.instance.refresh();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    RevenueCatService.instance.isPro.removeListener(_proListener);

    _reloadDebounce?.cancel();
    _stopAiPolling();

    final sb = Supabase.instance.client;
    if (_responsesChannel != null) sb.removeChannel(_responsesChannel!);
    if (_sessionChannel != null) sb.removeChannel(_sessionChannel!);
    if (_aiCoupleChannel != null) sb.removeChannel(_aiCoupleChannel!);

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

  Future<void> _openProPaywall() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PremiumPaywallPage()),
    );

    if (changed == true) {
      try {
        await RevenueCatService.instance.refresh();
      } catch (_) {}
      await _refreshDbPro();
      if (mounted) setState(() {});
    }
  }

  /// ✅ DB truth: checks purchases table.
  Future<void> _refreshDbPro() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _dbPro = false;
        _dbProReady = true;
      });
      return;
    }

    try {
      final res = await sb
          .from('purchases')
          .select('id')
          .eq('user_id', uid)
          .eq('type', 'lifetime_unlock')
          .limit(1);

      final has = (res as List).isNotEmpty;

      if (!mounted) return;
      setState(() {
        _dbPro = has;
        _dbProReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dbPro = false;
        _dbProReady = true;
      });
    }
  }

  bool get _hardPro => _dbProReady && _dbPro;

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);

    final sb = Supabase.instance.client;
    final myId = sb.auth.currentUser!.id;

    final session = await _sessionService.getSession(widget.sessionId);
    final otherId = _otherUserId(session);

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

    // After session loads, attempt to load summary again
    _loadAiSummaryFromDb();
  }

  void _setupRealtime() {
    final sb = Supabase.instance.client;

    if (_responsesChannel != null) {
      sb.removeChannel(_responsesChannel!);
      _responsesChannel = null;
    }
    if (_sessionChannel != null) {
      sb.removeChannel(_sessionChannel!);
      _sessionChannel = null;
    }
    if (_aiCoupleChannel != null) {
      sb.removeChannel(_aiCoupleChannel!);
      _aiCoupleChannel = null;
    }

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

    // ✅ NEW: realtime updates for shared AI summary (partner sees it instantly)
    _aiCoupleChannel = sb.channel('realtime:ai_couple_summaries:${widget.sessionId}');
    _aiCoupleChannel!
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'ai_couple_summaries',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'session_id',
        value: widget.sessionId,
      ),
      callback: (_) {
        _loadAiSummaryFromDb();
      },
    )
        .subscribe();
  }

  bool get _partnerJoined => (_session?['partner_id'] as String?) != null;

  // ✅ Trust DB status (because you have triggers)
  bool get _finalReady => ((_session?['status'] as String?) == 'completed');

  // --- AI summary helpers -----------------------------------------------------

  String _cleanJsonishText(String s) {
    var t = s.trim();
    t = t.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    t = t.replaceFirst(RegExp(r'```$', caseSensitive: false), '');
    t = t.replaceFirst(RegExp(r'^\s*json\s*', caseSensitive: false), '');
    return t.trim();
  }

  String? _extractFirstJsonObject(String s) {
    final t = _cleanJsonishText(s);
    final start = t.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    for (var i = start; i < t.length; i++) {
      final ch = t[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          return t.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _tryParseSummary(dynamic summary) {
    if (summary == null) return null;

    if (summary is Map) {
      return Map<String, dynamic>.from(summary as Map);
    }

    if (summary is String) {
      final candidate = _extractFirstJsonObject(summary) ?? _cleanJsonishText(summary);
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    return null;
  }

  String _formatAiSummaryForPdf(Map<String, dynamic> j) {
    final headline = (j['headline'] ?? '').toString();

    List<String> list(String key) {
      final v = j[key];
      if (v is List) {
        return v.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
      }
      return const [];
    }

    final strengths = list('strengths');
    final risks = list('risks');
    final prompts = list('discussion_prompts');
    final next = list('next_steps');

    final b = StringBuffer();
    if (headline.trim().isNotEmpty) b.writeln(headline.trim());

    void addSection(String title, List<String> items) {
      if (items.isEmpty) return;
      if (b.isNotEmpty) b.writeln();
      b.writeln('$title:');
      for (final s in items) {
        b.writeln('• $s');
      }
    }

    addSection('Strengths', strengths);
    addSection('Risks', risks);
    addSection('Discussion prompts', prompts);
    addSection('Next steps', next);

    return b.toString().trim();
  }

  bool get _hasAiSummary =>
      _aiSummaryJson != null || (_aiSummaryRaw != null && _aiSummaryRaw!.trim().isNotEmpty);

  void _stopAiPolling() {
    _aiPollTimer?.cancel();
    _aiPollTimer = null;
    _aiPollTicks = 0;
  }

  /// ✅ Poll for BOTH users when DB says "generating"
  void _startAiPollingWhenGenerating() {
    if (!_finalReady) return;
    if (_hasAiSummary) return;

    if (_aiPollTimer != null) return;

    _aiPollTicks = 0;
    _aiPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      _aiPollTicks += 1;

      // Poll for up to ~60s
      if (_aiPollTicks > 30) {
        _stopAiPolling();
        if (!mounted) return;
        setState(() {});
        return;
      }

      await _loadAiSummaryFromDb();

      // Stop if ready or error
      if (_hasAiSummary || _aiSharedStatus == 'error') {
        _stopAiPolling();
      }
    });
  }

  void _startAiPollingAfterGenerate() {
    if (!_finalReady) return;
    if (_hasAiSummary) return;

    if (_aiPollTimer != null) return;

    _aiPollTicks = 0;
    _aiPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      _aiPollTicks += 1;

      // Poll for up to ~45s
      if (_aiPollTicks > 22) {
        _stopAiPolling();
        if (!mounted) return;
        setState(() {});
        return;
      }

      await _loadAiSummaryFromDb();
      if (_hasAiSummary || _aiSharedStatus == 'error') {
        _stopAiPolling();
      }
    });
  }

  /// ✅ Loads shared couple summary first (incl. status), then falls back to per-user ai_summaries.
  Future<void> _loadAiSummaryFromDb() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    // 1) Try shared couple summary (available to both participants)
    try {
      final shared = await sb
          .from('ai_couple_summaries')
          .select('summary,status,error_message,updated_at')
          .eq('session_id', widget.sessionId)
          .maybeSingle();

      final sharedRaw = shared?['summary'];
      final sharedParsed = _tryParseSummary(sharedRaw);

      final sharedStatusRaw = shared?['status']?.toString();
      final sharedErr = shared?['error_message']?.toString();

      final rawText = (sharedRaw ?? '').toString().trim();

      // ✅ Treat '{}' (placeholder) as "no summary"
      final hasSharedSummary =
          rawText.isNotEmpty && rawText != '{}' && rawText.toLowerCase() != 'null';

      // ✅ Infer status if status is missing/unknown
      String? inferredStatus;
      if (shared == null) {
        inferredStatus = null;
      } else if (sharedStatusRaw == 'error' ||
          sharedStatusRaw == 'ready' ||
          sharedStatusRaw == 'generating') {
        inferredStatus = sharedStatusRaw;
      } else {
        inferredStatus = hasSharedSummary ? 'ready' : 'generating';
      }

      if (!mounted) return;

      setState(() {
        _aiSharedStatus = inferredStatus;
        _aiSharedError =
        (sharedErr != null && sharedErr.trim().isNotEmpty) ? sharedErr : null;
      });

      // If summary exists -> show it
      if (hasSharedSummary) {
        if (!mounted) return;
        setState(() {
          _aiSummaryIsShared = true;
          _aiSummaryJson = sharedParsed;
          // Only show raw if it's not '{}' and parsing failed
          _aiSummaryRaw = (sharedParsed == null) ? rawText : null;
        });
        _stopAiPolling();
        return;
      }

      // If DB says generating -> show generating and poll (even for partner)
      if (_aiSharedStatus == 'generating') {
        _startAiPollingWhenGenerating();
        return;
      }

      // If DB says error -> show error (don't fall back to per-user)
      if (_aiSharedStatus == 'error') {
        _stopAiPolling();
        return;
      }
    } catch (_) {
      // ignore and fallback to per-user
    }

    // 2) Fallback to per-user summary (legacy)
    try {
      final row = await sb
          .from('ai_summaries')
          .select('summary')
          .eq('session_id', widget.sessionId)
          .eq('user_id', uid)
          .maybeSingle();

      final raw = row?['summary'];
      final parsed = _tryParseSummary(raw);
      final rawText = (raw ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _aiSummaryIsShared = false;
        _aiSummaryJson = parsed;
        _aiSummaryRaw =
        (parsed == null && rawText.isNotEmpty && rawText != '{}' && rawText.toLowerCase() != 'null')
            ? rawText
            : null;
      });
    } catch (e) {
      debugPrint('load ai summary failed: $e');
    }
  }

  /// ✅ Generates AI summary via Supabase Edge Function (Pro-only).
  /// If it returns 202, we simply show "generating" UI and poll until it appears.
  Future<void> _generateAiSummary() async {
    if (_aiBusy) return;

    if (!_finalReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI summary unlocks when final results are ready.')),
      );
      return;
    }

    if (!_partnerJoined) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for partner to join.')),
      );
      return;
    }

    // Hard gate: DB truth
    if (!_hardPro) {
      await _openProPaywall();
      if (!_hardPro && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pro is required to generate the AI summary.')),
        );
      }
      return;
    }

    setState(() {
      _aiBusy = true;
      _aiErrorMessage = null;
      _aiSharedError = null;
    });

    try {
      final sb = Supabase.instance.client;

      final res = await sb.functions.invoke(
        'ai_summary',
        body: {'sessionId': widget.sessionId},
      );

      // 202: summary is generating somewhere (or lock held). We just poll.
      if (res.status == 202) {
        await _loadAiSummaryFromDb();
        if (_hasAiSummary) {
          _stopAiPolling();
          return;
        }
        _startAiPollingAfterGenerate();
        return;
      }

      if (res.status != 200) {
        throw Exception('ai_summary failed: status=${res.status}, data=${res.data}');
      }

      final data = res.data;
      dynamic summaryCandidate;
      if (data is Map) summaryCandidate = data['summary'];

      final parsed = _tryParseSummary(summaryCandidate);

      if (parsed != null) {
        if (!mounted) return;
        setState(() {
          _aiSummaryIsShared = true;
          _aiSummaryJson = parsed;
          _aiSummaryRaw = null;
        });
        _stopAiPolling();
        return;
      }

      await _loadAiSummaryFromDb();

      if (!_hasAiSummary) {
        _startAiPollingAfterGenerate();
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('ai_summary FunctionException: $e');

      setState(() {
        _aiErrorMessage = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI summary failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  // --- PDF export -------------------------------------------------------------

  Future<void> _exportFinalPdf() async {
    if (!_finalReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Final results are not ready yet.')),
      );
      return;
    }

    if (!_hardPro) {
      await _openProPaywall();
      if (!_hardPro) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pro is required to export the PDF.')),
        );
      }
      return;
    }

    if (!_partnerJoined) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for partner to join.')),
      );
      return;
    }

    final overall = _computeOverallScore();
    final buckets = _alignmentBuckets();

    final doc = pw.Document();

    String listOrDash(List<String> items) => items.isEmpty ? '—' : items.join(', ');

    final moduleLines = <String>[];
    for (final m in _modules) {
      final moduleId = m['id'] as String;
      final title = m['title'] as String;
      final qs = _questionsByModule[moduleId] ?? const [];
      final score = _computeModuleScore(qs, _me, _partner);
      final label = score == null ? '—' : '${score.toStringAsFixed(0)}%';
      moduleLines.add('$title: $label');
    }

    final mismatches = _topMismatchEntries(limit: 20);

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text(
            'Aligna — Final Compatibility Report',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Session: ${widget.sessionId}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 6),
          pw.Text('Answered: You $_myCount / $_totalQuestions, Partner $_partnerCount / $_totalQuestions'),
          pw.SizedBox(height: 12),
          pw.Text('Overall compatibility', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(overall == null ? '—' : '${overall.toStringAsFixed(0)}%'),
          pw.SizedBox(height: 12),
          pw.Text('Quick insight', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Strong alignment: ${listOrDash(buckets.strong)}'),
          pw.Text('Moderate alignment: ${listOrDash(buckets.moderate)}'),
          pw.Text('Major differences: ${listOrDash(buckets.major)}'),
          pw.SizedBox(height: 14),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text('Module scores', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ...moduleLines.map((l) => pw.Text('• $l')),
          pw.SizedBox(height: 14),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text('Top mismatches', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (mismatches.isEmpty)
            pw.Text('—')
          else
            ...mismatches.map(
                  (e) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${e.moduleTitle} — severity ${e.severity.toStringAsFixed(1)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(e.questionText),
                  pw.Text('You: ${e.myAnswer}'),
                  pw.Text('Partner: ${e.partnerAnswer}'),
                  pw.SizedBox(height: 8),
                ],
              ),
            ),
          if (_aiSummaryJson != null) ...[
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text('AI Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text(_formatAiSummaryForPdf(_aiSummaryJson!)),
          ] else if (_aiSummaryRaw != null && _aiSummaryRaw!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text('AI Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text(_aiSummaryRaw!.trim()),
          ],
        ],
      ),
    );

    try {
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'Aligna_Report_${widget.sessionId}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e')),
      );
    }
  }

  // --- scoring ----------------------------------------------------------------

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

  List<_MismatchEntry> _topMismatchEntries({int limit = 10}) {
    final entries = <_MismatchEntry>[];

    if (!_partnerJoined) return entries;

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
    return entries.take(min(limit, entries.length)).toList();
  }

  List<Widget> _buildTopMismatches({int limit = 10}) {
    final top = _topMismatchEntries(limit: limit);

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

  Widget _aiGeneratingHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your summary is being generated…',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 6),
          Text(
            'This usually takes a few seconds. You can stay here — it will appear automatically.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _pageBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final overall = _computeOverallScore();
    final buckets = _alignmentBuckets();
    String listOrDash(List<String> items) => items.isEmpty ? '—' : items.join(', ');

    final mismatchLimit = _isPro ? 20 : 5;

    final effectiveAiError =
    (_aiSharedStatus == 'error' && (_aiSharedError ?? '').trim().isNotEmpty)
        ? _aiSharedError
        : _aiErrorMessage;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
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
            Expanded(
              child: Text(
                _finalReady ? 'Results' : 'Live Results',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildHeroCard(
            overall: overall,
            partnerJoined: _partnerJoined,
            finalReady: _finalReady,
          ),
          const SizedBox(height: 14),

          _StatusCard(
            partnerJoined: _partnerJoined,
            total: _totalQuestions,
            myCount: _myCount,
            partnerCount: _partnerCount,
            finalReady: _finalReady,
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
                  'Quick insight',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),

                if (!_partnerJoined || overall == null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _softPurple,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'Answer more questions together to unlock insights.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                else if (_isPro) ...[
                  _InsightLine(
                    icon: Icons.favorite_rounded,
                    text: 'Strong alignment in: ${listOrDash(buckets.strong)}',
                    bg: const Color(0xFFEFFAF3),
                  ),
                  const SizedBox(height: 10),
                  _InsightLine(
                    icon: Icons.balance_rounded,
                    text: 'Moderate alignment in: ${listOrDash(buckets.moderate)}',
                    bg: const Color(0xFFFFF8E8),
                  ),
                  const SizedBox(height: 10),
                  _InsightLine(
                    icon: Icons.priority_high_rounded,
                    text: 'Major differences in: ${listOrDash(buckets.major)}',
                    bg: const Color(0xFFFFF0F3),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _softPurple,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'Unlock Pro to see deeper insight across your modules.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _gradientButton(
                    text: 'Unlock Pro',
                    onPressed: _openProPaywall,
                    icon: Icons.auto_awesome_rounded,
                  ),
                ],

                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 18),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'AI Summary',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (!_hasAiSummary && !_isPro)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _softPink,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Pro',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _primaryPurple,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                if (!_finalReady)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _softPurple,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'AI summary unlocks when final results are ready.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                else if (_hasAiSummary) ...[
                  if (_aiSummaryIsShared)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Shared summary for both of you.',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _cardBorder),
                    ),
                    child: _aiSummaryJson != null
                        ? _AiSummaryView(json: _aiSummaryJson!)
                        : Text(
                      _aiSummaryRaw ?? '',
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'AI-generated insights are based on the answers provided and are intended for informational purposes only. They should not be considered professional relationship advice.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      _outlineButton(
                        text: 'Refresh',
                        onPressed: _aiBusy ? null : _loadAiSummaryFromDb,
                        icon: Icons.refresh_rounded,
                      ),
                      _outlineButton(
                        text: 'Copy',
                        onPressed: () async {
                          final text = _aiSummaryJson != null
                              ? const JsonEncoder.withIndent('  ').convert(_aiSummaryJson)
                              : (_aiSummaryRaw ?? '');
                          if (text.trim().isEmpty) return;
                          await Clipboard.setData(ClipboardData(text: text));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Summary copied')),
                          );
                        },
                        icon: Icons.copy_rounded,
                      ),
                    ],
                  ),
                ] else if (_aiBusy || _aiGeneratingFromDb) ...[
                  _aiGeneratingHint(),
                ] else if ((effectiveAiError ?? '').isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F3),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI summary failed to generate.',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          effectiveAiError!,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _gradientButton(
                    text: _isPro ? (_aiBusy ? 'Generating…' : 'Try again') : 'Unlock Pro',
                    onPressed: _isPro ? (_aiBusy ? null : _generateAiSummary) : _openProPaywall,
                    icon: _isPro ? Icons.refresh_rounded : Icons.auto_awesome_rounded,
                  ),
                ] else if (!_isPro) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _softPurple,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'Unlock Pro to generate an AI summary of your compatibility.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _gradientButton(
                    text: 'Unlock Pro',
                    onPressed: _openProPaywall,
                    icon: Icons.auto_awesome_rounded,
                  ),
                ] else ...[
                  _gradientButton(
                    text: _aiBusy ? 'Generating…' : 'Generate summary',
                    onPressed: _aiBusy ? null : _generateAiSummary,
                    icon: Icons.auto_awesome_rounded,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),
          const Text(
            'Module scores',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                    ? (_finalReady ? 'Final result' : 'Live result')
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              if (!_isPro)
                TextButton(
                  onPressed: _openProPaywall,
                  child: const Text(
                    'Unlock full',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _primaryPurple,
                    ),
                  ),
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
            if (!_isPro)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Showing $mismatchLimit mismatches. Unlock Pro to see more.',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
          ],

          const SizedBox(height: 24),

          if (_finalReady) ...[
            _gradientButton(
              text: !_dbProReady
                  ? 'Checking…'
                  : (_hardPro ? 'Export Final Report (PDF)' : 'Unlock Pro to Export'),
              onPressed: () async {
                await _refreshDbPro();
                if (!mounted) return;
                await _exportFinalPdf();
              },
              icon: Icons.picture_as_pdf_rounded,
            ),
            const SizedBox(height: 8),
            Text(
              _hardPro ? 'Exports your final results as a PDF.' : 'Export is a Pro feature.',
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ] else
            const _EmptyHint(
              text: 'Live results are shown now. Final results unlock when both finish all questions.',
            ),
        ],
      ),
    );
  }
}

class _AiSummaryView extends StatelessWidget {
  final Map<String, dynamic> json;
  const _AiSummaryView({required this.json});

  List<String> _list(String key) {
    final v = json[key];
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final headline = (json['headline'] ?? '').toString();
    final strengths = _list('strengths');
    final risks = _list('risks');
    final prompts = _list('discussion_prompts');
    final next = _list('next_steps');

    Widget section(String title, List<String> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ...items.map(
                  (s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $s', style: const TextStyle(color: Colors.black87)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (headline.trim().isNotEmpty)
          Text(headline, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        section('Strengths', strengths),
        section('Risks', risks),
        section('Discussion prompts', prompts),
        section('Next steps', next),
      ],
    );
  }
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
          Text(
            finalReady ? 'Final results ready' : 'Live progress',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          _MiniProgressRow(
            label: 'You',
            value: total == 0 ? 0 : (myCount / total).clamp(0, 1),
            text: '$myCount / $total answered',
            color: const Color(0xFF7B5CF0),
          ),
          const SizedBox(height: 14),
          _MiniProgressRow(
            label: 'Partner',
            value: !partnerJoined || total == 0 ? 0 : (partnerCount / total).clamp(0, 1),
            text: partnerJoined ? '$partnerCount / $total answered' : 'Not joined yet',
            color: const Color(0xFFE96BD2),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFF0EAFB)),
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF6A42E8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: const Color(0xFFF0EAFB),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF7B5CF0)),
              ),
            )
          else
            const Text(
              'Not enough shared answers yet',
              style: TextStyle(color: Colors.black54),
            ),
          const SizedBox(height: 8),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0EAFB)),
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
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0EAFB)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.black54),
      ),
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

class _MiniProgressRow extends StatelessWidget {
  final String label;
  final double value;
  final String text;
  final Color color;

  const _MiniProgressRow({
    required this.label,
    required this.value,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: const Color(0xFFF0EAFB),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _InsightLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color bg;

  const _InsightLine({
    required this.icon,
    required this.text,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6A42E8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                height: 1.35,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}