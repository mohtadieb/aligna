import 'package:supabase_flutter/supabase_flutter.dart';

class PremiumService {
  final SupabaseClient _sb;

  PremiumService({SupabaseClient? client})
      : _sb = client ?? Supabase.instance.client;

  /// True if user has lifetime unlock.
  Future<bool> hasPremium() async {
    final res = await _sb.rpc('has_premium');
    if (res is bool) return res;
    if (res is num) return res != 0;
    return false;
  }

  /// DEV ONLY: creates a lifetime unlock record for the current user.
  /// Remove/disable this when you integrate real payments.
  Future<void> devUnlockLifetime({String platform = 'unknown'}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    final tx = 'dev_${DateTime.now().millisecondsSinceEpoch}';

    await _sb.from('purchases').insert({
      'user_id': uid,
      'type': 'lifetime_unlock',
      'platform': platform,
      'transaction_id': tx,
    });
  }
}
