import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RevenueCatService {
  RevenueCatService._();
  static final RevenueCatService instance = RevenueCatService._();

  static const String entitlementId = 'aligna_pro';

  // ✅ RevenueCat public SDK keys
  static const String _androidKey = 'test_SCJkyqEfQqDuuCxFkdryDKtDrBF';
  static const String _iosKey = 'test_SCJkyqEfQqDuuCxFkdryDKtDrBF';

  /// True only after we've finished at least 1 RC refresh for the current auth state.
  /// UI can use this to avoid "Unlock Pro" flicker.
  final ValueNotifier<bool> isReady = ValueNotifier<bool>(false);

  /// Current entitlement state for the current user.
  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);

  bool _configured = false;
  String? _configuredForUserId;

  /// Call this whenever Supabase auth user changes (login/logout/refresh).
  /// - On logout: clears state + logs out RevenueCat user
  /// - On login: configures/logs in and refreshes
  Future<void> handleAuthUserChanged() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      await resetForLogout();
      // mark ready so UI doesn't hang on "…"
      isReady.value = true;
      return;
    }

    await configureIfNeeded();
  }

  Future<void> configureIfNeeded() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // We're about to refresh for this user
    isReady.value = false;

    final apiKey = Platform.isAndroid ? _androidKey : _iosKey;

    // First-time configure
    if (!_configured) {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);

      final configuration = PurchasesConfiguration(apiKey)..appUserID = user.id;
      await Purchases.configure(configuration);

      Purchases.addCustomerInfoUpdateListener((info) {
        _applyCustomerInfo(info);
        // listener implies we got info
        isReady.value = true;
      });

      _configured = true;
      _configuredForUserId = user.id;

      await refresh();
      return;
    }

    // SDK already configured; if user changed, log in new user
    if (_configuredForUserId != user.id) {
      try {
        final result = await Purchases.logIn(user.id);
        _applyCustomerInfo(result.customerInfo);
      } catch (_) {
        // ignore; we'll refresh anyway
      }
      _configuredForUserId = user.id;
    }

    await refresh();
  }

  Future<void> refresh() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _applyCustomerInfo(info);
    } catch (_) {
      // keep UI stable if RC temporarily unavailable
    } finally {
      // Whether it succeeded or not, UI can stop showing "…"
      isReady.value = true;
    }
  }

  void _applyCustomerInfo(CustomerInfo info) {
    isPro.value = info.entitlements.active.containsKey(entitlementId);
  }

  Future<void> restore() async {
    isReady.value = false;
    try {
      final info = await Purchases.restorePurchases();
      _applyCustomerInfo(info);
    } catch (_) {
      // ignore
    } finally {
      isReady.value = true;
    }
  }

  /// Clears UI state (no anonymous RevenueCat user creation).
  Future<void> resetForLogout() async {
    isReady.value = false;
    isPro.value = false;
    _configuredForUserId = null;

    // If RC was never configured, we’re still “ready” for UI purposes
    if (!_configured) {
      isReady.value = true;
      return;
    }

    try {
      await Purchases.invalidateCustomerInfoCache();
      // ✅ Keep this OFF if you don’t support guest users:
      // await Purchases.logOut();
    } catch (_) {
      // ignore
    } finally {
      isReady.value = true;
    }
  }
}