import 'package:supabase_flutter/supabase_flutter.dart';

class ResponseService {
  final SupabaseClient _sb = Supabase.instance.client;

  Future<void> upsertResponse({
    required String sessionId,
    required String questionId,
    required String value,
  }) async {
    final userId = _sb.auth.currentUser!.id;

    await _sb.from('responses').upsert(
      {
        'session_id': sessionId,
        'user_id': userId,
        'question_id': questionId,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'session_id,user_id,question_id',
    );
  }

  Future<int> myAnsweredCount(String sessionId) async {
    final userId = _sb.auth.currentUser!.id;
    final res = await _sb
        .from('responses')
        .select('id')
        .eq('session_id', sessionId)
        .eq('user_id', userId);

    return (res as List).length;
  }

  // ✅ Generic count for any user (used for "other partner")
  Future<int> userAnsweredCount(String sessionId, String userId) async {
    final res = await _sb
        .from('responses')
        .select('id')
        .eq('session_id', sessionId)
        .eq('user_id', userId);

    return (res as List).length;
  }

  Future<Map<String, String>> getMyResponsesMap(String sessionId) async {
    final userId = _sb.auth.currentUser!.id;

    final res = await _sb
        .from('responses')
        .select('question_id, value')
        .eq('session_id', sessionId)
        .eq('user_id', userId);

    final list = (res as List).cast<Map<String, dynamic>>();
    return {
      for (final row in list) row['question_id'] as String: row['value'] as String
    };
  }

  Future<int> myAnsweredCountForModule(String sessionId, String moduleId) async {
    final userId = _sb.auth.currentUser!.id;

    final res = await _sb
        .from('responses')
        .select('id, questions!inner(module_id)')
        .eq('session_id', sessionId)
        .eq('user_id', userId)
        .eq('questions.module_id', moduleId);

    return (res as List).length;
  }

  Future<int> userAnsweredCountForModule(
      String sessionId,
      String userId,
      String moduleId,
      ) async {
    final res = await _sb
        .from('responses')
        .select('id, questions!inner(module_id)')
        .eq('session_id', sessionId)
        .eq('user_id', userId)
        .eq('questions.module_id', moduleId);

    return (res as List).length;
  }


}
