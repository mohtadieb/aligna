import 'package:flutter/material.dart';

// ✅ RevenueCat UI + service
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../../services/revenuecat/revenuecat_service.dart';

class PremiumPaywallPage extends StatefulWidget {
  const PremiumPaywallPage({super.key});

  @override
  State<PremiumPaywallPage> createState() => _PremiumPaywallPageState();
}

class _PremiumPaywallPageState extends State<PremiumPaywallPage> {
  bool _busy = false;

  Future<void> _startPurchaseFlow() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await RevenueCatService.instance.configureIfNeeded();

      // Show paywall (only if user doesn't already have entitlement)
      await RevenueCatUI.presentPaywallIfNeeded(RevenueCatService.entitlementId);

      // Refresh local entitlement cache
      await RevenueCatService.instance.refresh();

      if (!mounted) return;

      if (RevenueCatService.instance.isPro.value) {
        Navigator.pop(context, true);
      } else {
        // They may have dismissed without buying
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase not completed.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paywall error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await RevenueCatService.instance.configureIfNeeded();
      await RevenueCatService.instance.restore();
      await RevenueCatService.instance.refresh();

      if (!mounted) return;

      if (RevenueCatService.instance.isPro.value) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No purchases found to restore.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCustomerCenter() async {
    try {
      await RevenueCatUI.presentCustomerCenter();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Customer Center failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aligna Pro')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lifetime Unlock',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 8),
                  Text('Unlock advanced analytics and future features like AI summaries.'),
                  SizedBox(height: 10),
                  Text('✅ Deep insight buckets'),
                  Text('✅ Full mismatch breakdown'),
                  Text('✅ Export report (PDF)'),
                  Text('✅ AI relationship summary (coming soon)'),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Tools
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restore),
                    title: const Text('Restore purchases'),
                    subtitle: const Text('If you already bought Pro on this account'),
                    onTap: _busy ? null : _restore,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('Customer Center'),
                    subtitle: const Text('Manage purchases'),
                    onTap: _openCustomerCenter,
                  ),
                ],
              ),
            ),

            const Spacer(),

            ValueListenableBuilder<bool>(
              valueListenable: RevenueCatService.instance.isPro,
              builder: (_, isPro, __) {
                return Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: (_busy || isPro) ? null : _startPurchaseFlow,
                        child: Text(
                          isPro ? 'Already unlocked ✅' : (_busy ? 'Opening…' : 'Continue'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isPro
                          ? 'You already have Aligna Pro on this account.'
                          : 'One-time lifetime purchase.',
                      style: const TextStyle(color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
