import 'package:supabase_flutter/supabase_flutter.dart';

class ResultsService {
  final SupabaseClient _sb = Supabase.instance.client;

  Future<Map<String, String>> getResponsesMapForUser({
    required String sessionId,
    required String userId,
  }) async {
    final res = await _sb
        .from('responses')
        .select('question_id, value')
        .eq('session_id', sessionId)
        .eq('user_id', userId);

    final list = (res as List).cast<Map<String, dynamic>>();
    return {
      for (final row in list)
        row['question_id'] as String: row['value'] as String
    };
  }
}
