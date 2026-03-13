import 'dart:math';
import 'package:flutter/material.dart';

import '../../../services/supabase/content_service.dart';
import '../../../services/supabase/response_service.dart';
import 'module_list_page.dart';

class QuestionFlowPage extends StatefulWidget {
  final String sessionId;
  final String moduleId;
  final String moduleTitle;

  const QuestionFlowPage({
    super.key,
    required this.sessionId,
    required this.moduleId,
    required this.moduleTitle,
  });

  @override
  State<QuestionFlowPage> createState() => _QuestionFlowPageState();
}

class _QuestionFlowPageState extends State<QuestionFlowPage> {
  final _content = ContentService();
  final _responses = ResponseService();

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
  List<Map<String, dynamic>> _questions = [];

  // Saved answers from DB
  Map<String, String> _myAnswers = {};

  // Draft answers (local only until Next)
  final Map<String, String> _draft = {};

  int _index = 0;

  // Only show Resume after the user has navigated backwards at least once
  bool _wentBackOnce = false;

  // Prevent one-frame UI flicker while moving to next question
  bool _isAdvancing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final qs = await _content.fetchQuestionsForModule(widget.moduleId);
    final my = await _responses.getMyResponsesMap(widget.sessionId);

    int resumeIndex = 0;
    if (qs.isNotEmpty) {
      final firstUnanswered = qs.indexWhere((q) {
        final qid = q['id'] as String;
        final v = my[qid];
        return v == null || v.isEmpty;
      });

      resumeIndex = firstUnanswered == -1 ? 0 : firstUnanswered;
    }

    setState(() {
      _questions = qs;
      _myAnswers = my;
      _draft.clear();
      _loading = false;
      _index = resumeIndex;
      _wentBackOnce = false;
      _isAdvancing = false;
    });
  }

  Map<String, dynamic> get _q => _questions[_index];
  String get _qid => _q['id'] as String;
  String get _qtype => _q['qtype'] as String;

  String? get _savedValue => _myAnswers[_qid];

  bool get _hasUnsavedChangeForCurrent {
    final saved = _savedValue;
    final d = _draft[_qid];

    return saved != null &&
        saved.isNotEmpty &&
        d != null &&
        d.isNotEmpty &&
        d != saved;
  }

  String get _effectiveValue {
    final d = _draft[_qid];
    if (d != null && d.isNotEmpty) return d;

    final saved = _savedValue;
    if (saved != null && saved.isNotEmpty) return saved;

    if (_qtype == 'scale_1_5') return '3';
    return '';
  }

  bool get _isModuleComplete {
    if (_questions.isEmpty) return false;
    for (final q in _questions) {
      final qid = q['id'] as String;
      final v = _myAnswers[qid];
      if (v == null || v.isEmpty) return false;
    }
    return true;
  }

  bool get _canGoNext {
    if (_qtype == 'scale_1_5') return true;
    return _effectiveValue.isNotEmpty;
  }

  void _setDraft(String value) {
    _draft[_qid] = value;
    setState(() {});
  }

  Future<void> _commitCurrentToDb({bool rebuild = true}) async {
    final valueToSave = _effectiveValue;

    if (_qtype != 'scale_1_5' && valueToSave.isEmpty) return;

    _myAnswers[_qid] = valueToSave;
    _draft.remove(_qid);

    if (rebuild) {
      setState(() {});
    }

    await _responses.upsertResponse(
      sessionId: widget.sessionId,
      questionId: _qid,
      value: valueToSave,
    );
  }

  Future<void> _next() async {
    if (_isAdvancing) return;

    setState(() {
      _isAdvancing = true;
    });

    await _commitCurrentToDb(rebuild: false);

    if (!mounted) return;

    if (_index < _questions.length - 1) {
      setState(() {
        _index++;
        _isAdvancing = false;
      });
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ModuleListPage(sessionId: widget.sessionId),
      ),
          (route) => route.isFirst,
    );
  }

  void _back() {
    if (_index > 0) {
      _wentBackOnce = true;
      setState(() => _index--);
    }
  }

  void _jumpToFirstUnanswered() {
    final i = _questions.indexWhere((q) {
      final qid = q['id'] as String;
      final v = _myAnswers[qid];
      return v == null || v.isEmpty;
    });
    if (i != -1) setState(() => _index = i);
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

  Widget _outlineButton({
    required String text,
    required VoidCallback? onPressed,
    IconData? icon,
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: _primaryPurple, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _primaryPurple,
            ),
          ),
        ],
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
          Expanded(
            child: Text(
              widget.moduleTitle,
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
        if (_isModuleComplete)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _softPink,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Center(
              child: Text(
                'Done',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _primaryPurple,
                ),
              ),
            ),
          ),
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _pageBg,
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: _pageBg,
        appBar: _buildAppBar(),
        body: const Center(
          child: Text('No questions in this module yet.'),
        ),
      );
    }

    final text = _q['text'] as String;
    final effectiveValue = _effectiveValue;
    final progress = (_index + 1) / _questions.length;

    final firstUnansweredIndex = _questions.indexWhere((q) {
      final qid = q['id'] as String;
      final v = _myAnswers[qid];
      return v == null || v.isEmpty;
    });

    final showResume = !_isAdvancing &&
        _wentBackOnce &&
        !_isModuleComplete &&
        firstUnansweredIndex != -1 &&
        firstUnansweredIndex != _index;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      'Question ${_index + 1} of ${_questions.length}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          '${(progress * 100).round()}% complete',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (_hasUnsavedChangeForCurrent)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.18),
                              ),
                            ),
                            child: const Text(
                              'Unsaved change',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (showResume)
                          TextButton(
                            onPressed: _jumpToFirstUnanswered,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                            ),
                            child: const Text(
                              'Resume',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
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
                    border: Border.all(color: _cardBorder),
                  ),
                  child: _QuestionWidget(
                    qtype: _qtype,
                    choices: _q['choices'],
                    value: effectiveValue,
                    onChanged: _setDraft,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _outlineButton(
                      text: 'Back',
                      onPressed: _index == 0 ? null : _back,
                      icon: Icons.arrow_back_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _gradientButton(
                      text: _index == _questions.length - 1 ? 'Finish' : 'Next',
                      onPressed: _canGoNext ? _next : null,
                      icon: _index == _questions.length - 1
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionWidget extends StatelessWidget {
  final String qtype;
  final dynamic choices;
  final String? value;
  final ValueChanged<String> onChanged;

  const _QuestionWidget({
    required this.qtype,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  List<String> _choicesAsList() {
    if (choices is List) {
      return (choices as List).map((e) => e.toString()).toList();
    }
    if (choices is String) {
      final s = (choices as String).trim();
      if (s.startsWith('[') && s.endsWith(']')) {
        final inner = s.substring(1, s.length - 1).trim();
        if (inner.isEmpty) return [];
        return inner
            .split(',')
            .map((x) => x.trim().replaceAll('"', ''))
            .where((x) => x.isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    switch (qtype) {
      case 'scale_1_5':
        final v = int.tryParse(value ?? '') ?? 3;
        return ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5FF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF0EAFB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your answer: $v',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      activeTrackColor: const Color(0xFF7B5CF0),
                      inactiveTrackColor: const Color(0xFFEADFFF),
                      thumbColor: const Color(0xFF6A42E8),
                      overlayColor: const Color(0xFF7B5CF0).withOpacity(0.12),
                    ),
                    child: Slider(
                      min: 1,
                      max: 5,
                      divisions: 4,
                      value: v.toDouble(),
                      onChanged: (x) => onChanged(x.round().toString()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '1 = Not important',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Text(
                        '5 = Very important',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

      case 'yes_no':
        return ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            _ChoiceTile(
              label: 'Yes',
              selected: value == 'yes',
              onTap: () => onChanged('yes'),
            ),
            const SizedBox(height: 12),
            _ChoiceTile(
              label: 'No',
              selected: value == 'no',
              onTap: () => onChanged('no'),
            ),
          ],
        );

      case 'single_choice':
        final list = _choicesAsList();
        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final option = list[i];
            return _ChoiceTile(
              label: option,
              selected: value == option,
              onTap: () => onChanged(option),
            );
          },
        );

      default:
        return const Center(
          child: Text('Unknown question type.'),
        );
    }
  }
}

class _ChoiceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF8F5FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF6A42E8) : const Color(0xFFF0EAFB),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: const Color(0xFF7B5CF0).withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: selected
                  ? const Icon(
                Icons.check_circle_rounded,
                key: ValueKey('selected'),
                color: Color(0xFF6A42E8),
              )
                  : const Icon(
                Icons.radio_button_unchecked_rounded,
                key: ValueKey('unselected'),
                color: Color(0xFFCCBFEF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}