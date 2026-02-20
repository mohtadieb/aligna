import 'package:supabase_flutter/supabase_flutter.dart';

class ContentService {
  final SupabaseClient _sb = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchModules() async {
    final res = await _sb
        .from('modules')
        .select('id, title, order_index')
        .order('order_index', ascending: true);

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchQuestionsForModule(String moduleId) async {
    final res = await _sb
        .from('questions')
        .select('id, module_id, text, qtype, weight, choices, order_index')
        .eq('module_id', moduleId)
        .order('order_index', ascending: true);

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchQuestionsForModules(List<String> moduleIds) async {
    if (moduleIds.isEmpty) return [];

    final res = await _sb
        .from('questions')
        .select('id, module_id, text, qtype, weight, choices, order_index')
        .inFilter('module_id', moduleIds)
        .order('module_id', ascending: true)
        .order('order_index', ascending: true);

    return (res as List).cast<Map<String, dynamic>>();
  }


  Future<int> questionCountForModule(String moduleId) async {
    final res = await _sb
        .from('questions')
        .select('id')
        .eq('module_id', moduleId);

    return (res as List).length;
  }

  // ✅ ADD THIS (used by SessionDashboard + Results)
  Future<int> fetchTotalQuestionCount() async {
    final res = await _sb.from('questions').select('id');
    return (res as List).length;
  }
}
