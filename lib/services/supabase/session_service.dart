import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  final SupabaseClient _sb = Supabase.instance.client;

  Future<Map<String, dynamic>> getSession(String sessionId) async {
    final res = await _sb
        .from('pair_sessions')
        .select('id, created_by, partner_id, invite_code, status, created_at')
        .eq('id', sessionId)
        .single();
    return res;
  }

  /// ✅ Uses DB function `join_pair_session(invite_code)` (row lock + validation)
  Future<Map<String, dynamic>> joinByInviteCode(String inviteCode) async {
    final code = inviteCode.trim().toUpperCase();
    if (code.isEmpty) throw Exception('Invite code is empty');

    final res = await _sb.rpc('join_pair_session', params: {
      'p_invite_code': code,
    });

    // Supabase Dart can return Map or List depending on function signature/settings
    if (res is Map<String, dynamic>) return res;
    if (res is List && res.isNotEmpty) {
      return (res.first as Map).cast<String, dynamic>();
    }

    throw Exception('Join failed (no session returned)');
  }
}
