import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase/content_service.dart';
import '../../../services/supabase/response_service.dart';
import '../../results/pages/results_page.dart';
import 'question_flow_page.dart';

class ModuleListPage extends StatefulWidget {
  final String sessionId;
  const ModuleListPage({super.key, required this.sessionId});

  @override
  State<ModuleListPage> createState() => _ModuleListPageState();
}

class _ModuleListPageState extends State<ModuleListPage> {
  final _content = ContentService();
  final _responses = ResponseService();

  bool _loading = true;

  // Only show bottom buttons once computed
  bool _continueReady = false;

  List<Map<String, dynamic>> _modules = [];
  final Map<String, int> _totalByModule = {};
  final Map<String, int> _answeredByModule = {};

  String? _firstIncompleteModuleId;
  String? _firstIncompleteModuleTitle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _computeFirstIncompleteModuleId(List<Map<String, dynamic>> modules) {
    for (final m in modules) {
      final moduleId = m['id'] as String;
      final total = _totalByModule[moduleId] ?? 0;
      final answered = _answeredByModule[moduleId] ?? 0;

      // Treat empty module as incomplete
      if (total == 0) return moduleId;

      if (answered < total) return moduleId;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _continueReady = false;
    });

    final modules = await _content.fetchModules();

    _totalByModule.clear();
    _answeredByModule.clear();

    for (final m in modules) {
      final moduleId = m['id'] as String;
      _totalByModule[moduleId] = await _content.questionCountForModule(moduleId);
      _answeredByModule[moduleId] =
      await _responses.myAnsweredCountForModule(widget.sessionId, moduleId);
    }

    final firstId = _computeFirstIncompleteModuleId(modules);
    String? firstTitle;
    if (firstId != null) {
      final match = modules.where((m) => m['id'] == firstId).toList();
      if (match.isNotEmpty) firstTitle = match.first['title'] as String?;
    }

    if (!mounted) return;

    setState(() {
      _modules = modules;
      _firstIncompleteModuleId = firstId;
      _firstIncompleteModuleTitle = firstTitle;

      _loading = false;
      _continueReady = true;
    });
  }

  Future<void> _continue() async {
    final id = _firstIncompleteModuleId;
    final title = _firstIncompleteModuleTitle;

    if (id == null || title == null) return; // ✅ shouldn't be shown anyway

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionFlowPage(
          sessionId: widget.sessionId,
          moduleId: id,
          moduleTitle: title,
        ),
      ),
    );

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final hasIncomplete = _firstIncompleteModuleId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modules'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        itemCount: _modules.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final m = _modules[index];
          final moduleId = m['id'] as String;
          final title = m['title'] as String;

          final total = _totalByModule[moduleId] ?? 0;
          final answered = _answeredByModule[moduleId] ?? 0;
          final progress = total == 0 ? 0.0 : answered / total;

          final completed = total > 0 && answered >= total;
          final percent = (progress * 100).round();

          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
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
              await _load();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (completed)
                        const Text(
                          'Completed ✅',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        )
                      else
                        Text(
                          '$percent%',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(value: progress, minHeight: 8),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$answered / $total answered',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  if (_continueReady && hasIncomplete && _firstIncompleteModuleId == moduleId)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Next up',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: (user == null || !_continueReady)
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              if (hasIncomplete) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _continue,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
