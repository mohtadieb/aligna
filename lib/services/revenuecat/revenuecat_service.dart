import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RevenueCatService {
  RevenueCatService._();
  static final RevenueCatService instance = RevenueCatService._();

  static const String entitlementId = 'aligna_pro';

  // ✅ Your public test SDK key
  static const String _androidKey = 'test_SCJkyqEfQqDuuCxFkdryDKtDrBF';
  static const String _iosKey = 'test_SCJkyqEfQqDuuCxFkdryDKtDrBF'; // replace later if different

  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);

  bool _configured = false;

  Future<void> configureIfNeeded() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final apiKey = Platform.isAndroid ? _androidKey : _iosKey;

    if (!_configured) {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);

      final configuration = PurchasesConfiguration(apiKey)
        ..appUserID = user.id; // ✅ stable user id

      await Purchases.configure(configuration);

      Purchases.addCustomerInfoUpdateListener((info) {
        _applyCustomerInfo(info);
      });

      _configured = true;
    } else {
      // If your app can switch users without restart, keep RC in sync
      try {
        final result = await Purchases.logIn(user.id);
        _applyCustomerInfo(result.customerInfo);
      } catch (_) {
        // ignore and just refresh
      }
    }

    await refresh();
  }

  Future<void> refresh() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _applyCustomerInfo(info);
    } catch (_) {
      // Don’t crash UI if RevenueCat is temporarily unavailable
    }
  }

  bool hasEntitlement(CustomerInfo info) {
    return info.entitlements.active.containsKey(entitlementId);
  }

  void _applyCustomerInfo(CustomerInfo info) {
    isPro.value = hasEntitlement(info);
  }

  Future<bool> checkPro() async {
    final info = await Purchases.getCustomerInfo();
    return hasEntitlement(info);
  }

  Future<void> restore() async {
    final info = await Purchases.restorePurchases();
    _applyCustomerInfo(info);
  }
}
