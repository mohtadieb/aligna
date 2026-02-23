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
  bool _popped = false;

  @override
  void initState() {
    super.initState();

    // Listen for Pro becoming true (purchase/restore)
    RevenueCatService.instance.isPro.addListener(_maybeAutoPopIfPro);

    // Also do an immediate check (if already Pro before opening)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoPopIfPro();
    });
  }

  @override
  void dispose() {
    RevenueCatService.instance.isPro.removeListener(_maybeAutoPopIfPro);
    super.dispose();
  }

  void _maybeAutoPopIfPro() {
    if (!mounted) return;
    if (_popped) return;

    final isPro = RevenueCatService.instance.isPro.value;
    if (!isPro) return;

    final nav = Navigator.of(context);
    if (!nav.canPop()) return;

    _popped = true;
    nav.pop(true);
  }

  Future<void> _startPurchaseFlow() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await RevenueCatService.instance.configureIfNeeded();

      await RevenueCatUI.presentPaywallIfNeeded(RevenueCatService.entitlementId);

      // Refresh local entitlement cache
      await RevenueCatService.instance.refresh();

      if (!mounted) return;

      if (RevenueCatService.instance.isPro.value) {
        _maybeAutoPopIfPro();
      } else {
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
        _maybeAutoPopIfPro();
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
              valueListenable: RevenueCatService.instance.isReady,
              builder: (_, ready, __) {
                return ValueListenableBuilder<bool>(
                  valueListenable: RevenueCatService.instance.isPro,
                  builder: (_, isPro, __) {
                    final buttonLabel =
                    !ready ? 'Loading…' : (isPro ? 'Already unlocked ✅' : (_busy ? 'Opening…' : 'Continue'));

                    return Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: (!ready || _busy || isPro) ? null : _startPurchaseFlow,
                            child: Text(buttonLabel),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          !ready
                              ? 'Checking your purchase status…'
                              : (isPro ? 'You already have Aligna Pro on this account.' : 'One-time lifetime purchase.'),
                          style: const TextStyle(color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}