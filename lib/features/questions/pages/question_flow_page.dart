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

  bool _loading = true;
  List<Map<String, dynamic>> _questions = [];

  // Saved answers from DB
  Map<String, String> _myAnswers = {}; // questionId -> value

  // Draft answers (local only until Next)
  final Map<String, String> _draft = {}; // questionId -> value

  int _index = 0;

  // ✅ Only show Resume after the user has navigated backwards at least once
  bool _wentBackOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final qs = await _content.fetchQuestionsForModule(widget.moduleId);
    final my = await _responses.getMyResponsesMap(widget.sessionId);

    // ✅ Resume based on SAVED answers only
    int resumeIndex = 0;
    if (qs.isNotEmpty) {
      final firstUnanswered = qs.indexWhere((q) {
        final qid = q['id'] as String;
        final v = my[qid];
        return v == null || v.isEmpty;
      });

      // If complete, start at first question
      resumeIndex = firstUnanswered == -1 ? 0 : firstUnanswered;
    }

    setState(() {
      _questions = qs;
      _myAnswers = my;
      _draft.clear();
      _loading = false;
      _index = resumeIndex;
      _wentBackOnce = false; // ✅ reset on reload
    });
  }

  Map<String, dynamic> get _q => _questions[_index];
  String get _qid => _q['id'] as String;
  String get _qtype => _q['qtype'] as String;

  String? get _savedValue => _myAnswers[_qid];

  /// ✅ What we show in UI:
  /// saved -> draft -> default (scale only) -> empty
  String get _effectiveValue {
    final saved = _savedValue;
    if (saved != null && saved.isNotEmpty) return saved;

    final d = _draft[_qid];
    if (d != null && d.isNotEmpty) return d;

    if (_qtype == 'scale_1_5') return '3'; // show default, still not saved
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
    // Scale always allowed (default 3)
    if (_qtype == 'scale_1_5') return true;

    // Other types require a draft or saved selection
    return _effectiveValue.isNotEmpty;
  }

  void _setDraft(String value) {
    _draft[_qid] = value;
    setState(() {});
  }

  Future<void> _commitCurrentToDb() async {
    final valueToSave = _effectiveValue;

    // For non-scale: if nothing selected, do nothing
    if (_qtype != 'scale_1_5' && valueToSave.isEmpty) return;

    // For scale: valueToSave will be default 3 if untouched
    _myAnswers[_qid] = valueToSave;
    _draft.remove(_qid);
    setState(() {});

    await _responses.upsertResponse(
      sessionId: widget.sessionId,
      questionId: _qid,
      value: valueToSave,
    );
  }

  Future<void> _next() async {
    await _commitCurrentToDb();

    if (_index < _questions.length - 1) {
      setState(() => _index++);
      return;
    }

    // ✅ Finished module → always go back to Modules page
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ModuleListPage(sessionId: widget.sessionId),
      ),
          (route) => route.isFirst, // keeps the app root only
    );
  }


  void _back() {
    if (_index > 0) {
      _wentBackOnce = true; // ✅ Resume becomes eligible only after going back
      setState(() => _index--);
    }
  }

  void _jumpToFirstUnanswered() {
    final i = _questions.indexWhere((q) {
      final qid = q['id'] as String;
      final v = _myAnswers[qid]; // SAVED only
      return v == null || v.isEmpty;
    });
    if (i != -1) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.moduleTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.moduleTitle)),
        body: const Center(child: Text('No questions in this module yet.')),
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

    final showResume =
        _wentBackOnce && // ✅ key change: only after user went back
            !_isModuleComplete &&
            firstUnansweredIndex != -1 &&
            firstUnansweredIndex != _index;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.moduleTitle),
        actions: [
          if (_isModuleComplete)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: Text('Done ✅', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Question ${_index + 1} of ${_questions.length}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const Spacer(),
                if (showResume)
                  TextButton(
                    onPressed: _jumpToFirstUnanswered,
                    child: const Text('Resume'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),

            Expanded(
              child: _QuestionWidget(
                qtype: _qtype,
                choices: _q['choices'],
                value: effectiveValue,
                onChanged: _setDraft, // ✅ drafts only
              ),
            ),

            Row(
              children: [
                TextButton(
                  onPressed: _index == 0 ? null : _back,
                  child: const Text('Back'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _canGoNext ? _next : null,
                  child: Text(_index == _questions.length - 1 ? 'Finish' : 'Next'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _QuestionWidget extends StatelessWidget {
  final String qtype;
  final dynamic choices; // jsonb
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your answer: $v', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Slider(
              min: 1,
              max: 5,
              divisions: 4,
              value: v.toDouble(),
              onChanged: (x) => onChanged(x.round().toString()),
            ),
            const SizedBox(height: 8),
            const Text(
              '1 = Not important • 5 = Very important',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        );

      case 'yes_no':
        return Column(
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
        return const Text('Unknown question type.');
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
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.black : Colors.black12),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            if (selected) const Icon(Icons.check_circle),
          ],
        ),
      ),
    );
  }
}
