import 'package:shared_preferences/shared_preferences.dart';

class CelebrationOnceStore {
  static const _prefix = 'celebration_shown';

  String _key({required String userId, required String sessionId}) =>
      '$_prefix:$userId:$sessionId';

  Future<bool> hasShown({
    required String userId,
    required String sessionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId: userId, sessionId: sessionId)) ?? false;
  }

  Future<void> markShown({
    required String userId,
    required String sessionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId: userId, sessionId: sessionId), true);
  }
}
