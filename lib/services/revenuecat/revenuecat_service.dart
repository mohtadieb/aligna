import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum RestorePurchaseStatus {
  restored,
  noPurchasesFound,
  belongsToDifferentAccount,
  cancelled,
  failed,
}

class RestorePurchaseResult {
  final RestorePurchaseStatus status;
  final String message;

  const RestorePurchaseResult({
    required this.status,
    required this.message,
  });
}

class RevenueCatService {
  RevenueCatService._();
  static final RevenueCatService instance = RevenueCatService._();

  static const String entitlementId = 'aligna_pro';

  // ✅ RevenueCat public SDK keys
  static const String _androidKey = 'goog_LUZyQFBXffRkeGgynKOBLjpJGoT';
  // static const String _iosKey = 'test_SCJkyqEfQqDuuCxFkdryDKtDrBF';

  /// True only after we've finished at least 1 RC refresh for the current auth state.
  /// UI can use this to avoid "Unlock Pro" flicker.
  final ValueNotifier<bool> isReady = ValueNotifier<bool>(false);

  /// Current entitlement state for the current user.
  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);

  bool _configured = false;
  String? _configuredForUserId;

  /// Call this whenever Supabase auth user changes (login/logout/refresh).
  /// - On logout: clears state
  /// - On login: configures/logs in and refreshes
  Future<void> handleAuthUserChanged() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      await resetForLogout();
      isReady.value = true;
      return;
    }

    await configureIfNeeded();
  }

  Future<void> configureIfNeeded() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    isReady.value = false;

    final apiKey = _androidKey;

    if (!_configured) {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);

      final configuration = PurchasesConfiguration(apiKey)..appUserID = user.id;
      await Purchases.configure(configuration);

      Purchases.addCustomerInfoUpdateListener((info) {
        _applyCustomerInfo(info);
        isReady.value = true;
      });

      _configured = true;
      _configuredForUserId = user.id;

      await refresh();
      return;
    }

    if (_configuredForUserId != user.id) {
      try {
        final result = await Purchases.logIn(user.id);
        _applyCustomerInfo(result.customerInfo);
      } catch (_) {
        // ignore; refresh below will try again
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
      isReady.value = true;
    }
  }

  void _applyCustomerInfo(CustomerInfo info) {
    isPro.value = info.entitlements.active.containsKey(entitlementId);
  }

  bool _looksLikeDifferentAccountError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('receipt already in use') ||
        text.contains('receipt is already in use') ||
        text.contains('already in use by another') ||
        text.contains('belongs to another') ||
        text.contains('different app user') ||
        text.contains('original app user id') ||
        text.contains('receiptinusebyothersubscriber') ||
        text.contains('receiptalreadyinuse');
  }

  bool _looksLikeCancelledError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('purchasecancelled') ||
        text.contains('purchase cancelled') ||
        text.contains('user cancelled') ||
        text.contains('cancelled');
  }

  String messageForPurchaseError(Object error) {
    final text = error.toString().toLowerCase();

    if (_looksLikeDifferentAccountError(error)) {
      return 'This purchase belongs to another Aligna account. Please log in with the account that originally purchased Aligna Pro.';
    }

    if (text.contains('already own this item') ||
        text.contains('already purchased') ||
        text.contains('productalreadypurchasederror')) {
      return 'You already own Aligna Pro on this Google Play account. Please log in with the original Aligna account, or use Restore Purchases on that account.';
    }

    if (_looksLikeCancelledError(error)) {
      return 'Purchase cancelled.';
    }

    if (text.contains('network')) {
      return 'Network error. Please check your connection and try again.';
    }

    return 'Purchase failed. Please try again.';
  }

  Future<RestorePurchaseResult> restoreWithResult() async {
    isReady.value = false;

    try {
      final info = await Purchases.restorePurchases();
      _applyCustomerInfo(info);

      if (isPro.value) {
        return const RestorePurchaseResult(
          status: RestorePurchaseStatus.restored,
          message: 'Your purchase has been restored.',
        );
      }

      return const RestorePurchaseResult(
        status: RestorePurchaseStatus.noPurchasesFound,
        message: 'No purchases were found for this account.',
      );
    } on PlatformException catch (e) {
      if (_looksLikeDifferentAccountError(e)) {
        return const RestorePurchaseResult(
          status: RestorePurchaseStatus.belongsToDifferentAccount,
          message:
          'This purchase belongs to another Aligna account. Please log in with the account that originally purchased Aligna Pro.',
        );
      }

      if (_looksLikeCancelledError(e)) {
        return const RestorePurchaseResult(
          status: RestorePurchaseStatus.cancelled,
          message: 'Restore cancelled.',
        );
      }

      return RestorePurchaseResult(
        status: RestorePurchaseStatus.failed,
        message: 'Restore failed. Please try again.\n\n${e.message ?? e.code}',
      );
    } catch (_) {
      return const RestorePurchaseResult(
        status: RestorePurchaseStatus.failed,
        message: 'Restore failed. Please try again.',
      );
    } finally {
      isReady.value = true;
    }
  }

  Future<void> restore() async {
    await restoreWithResult();
  }

  /// Clears UI state (no anonymous RevenueCat user creation).
  Future<void> resetForLogout() async {
    isReady.value = false;
    isPro.value = false;
    _configuredForUserId = null;

    if (!_configured) {
      isReady.value = true;
      return;
    }

    try {
      await Purchases.invalidateCustomerInfoCache();
      // Keep this off if you do not support guest users:
      // await Purchases.logOut();
    } catch (_) {
      // ignore
    } finally {
      isReady.value = true;
    }
  }
}