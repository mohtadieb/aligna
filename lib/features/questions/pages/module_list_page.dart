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

    if (id == null || title == null) return;

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
            color: const Color(0xFF7B5CF0).withValues(alpha: 0.18),
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

  Widget _buildHeroCard({
    required int completedCount,
    required int totalCount,
    required bool hasIncomplete,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _brandGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B5CF0).withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose your\nnext module',
            style: TextStyle(
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasIncomplete
                ? 'Pick up where you left off or jump into any module you want to review.'
                : 'Nice work — you’ve completed all available modules.',
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
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    label: 'Completed',
                    value: '$completedCount / $totalCount',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HeroStat(
                    label: 'Next up',
                    value: hasIncomplete
                        ? (_firstIncompleteModuleTitle ?? 'Continue')
                        : 'All done',
                  ),
                ),
              ],
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
          const Expanded(
            child: Text(
              'Modules',
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
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final hasIncomplete = _firstIncompleteModuleId != null;
    final completedCount = _modules.where((m) {
      final moduleId = m['id'] as String;
      final total = _totalByModule[moduleId] ?? 0;
      final answered = _answeredByModule[moduleId] ?? 0;
      return total > 0 && answered >= total;
    }).length;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _buildHeroCard(
                completedCount: completedCount,
                totalCount: _modules.length,
                hasIncomplete: hasIncomplete,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                'All modules',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            sliver: SliverList.separated(
              itemCount: _modules.length,
              itemBuilder: (context, index) {
                final m = _modules[index];
                final moduleId = m['id'] as String;
                final title = m['title'] as String;

                final total = _totalByModule[moduleId] ?? 0;
                final answered = _answeredByModule[moduleId] ?? 0;
                final progress = total == 0 ? 0.0 : answered / total;

                final completed = total > 0 && answered >= total;
                final percent = (progress * 100).round();
                final isNextUp =
                    _continueReady && hasIncomplete && _firstIncompleteModuleId == moduleId;

                return InkWell(
                  borderRadius: BorderRadius.circular(22),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      border: Border.all(color: _cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                            const SizedBox(width: 12),
                            if (completed)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _softPink,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Completed',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: _primaryPurple,
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _softPurple,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '$percent%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: _primaryPurple,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: const Color(0xFFF0EAFB),
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF7B5CF0),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$answered / $total answered',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        if (isNextUp) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _softPurple,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: _primaryPurple,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Next up',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _primaryPurple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 12),
            ),
          ),
        ],
      ),
      bottomNavigationBar: (user == null || !_continueReady)
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                icon: Icons.bar_chart_rounded,
              ),
              if (hasIncomplete) ...[
                const SizedBox(height: 10),
                _gradientButton(
                  text: 'Continue',
                  onPressed: _continue,
                  icon: Icons.arrow_forward_rounded,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;

  const _HeroStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}