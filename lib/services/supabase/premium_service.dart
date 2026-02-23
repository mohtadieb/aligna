import 'package:supabase_flutter/supabase_flutter.dart';

class PremiumService {
  final SupabaseClient _sb;

  PremiumService({SupabaseClient? client})
      : _sb = client ?? Supabase.instance.client;

  /// True if user has lifetime unlock.
  /// Uses your existing RPC (recommended).
  Future<bool> hasPremium() async {
    final res = await _sb.rpc('has_premium');
    if (res is bool) return res;
    if (res is num) return res != 0;
    return false;
  }
}
