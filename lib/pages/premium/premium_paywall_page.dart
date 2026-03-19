import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../services/revenuecat/revenuecat_service.dart';

class PremiumPaywallPage extends StatefulWidget {
  const PremiumPaywallPage({super.key});

  @override
  State<PremiumPaywallPage> createState() => _PremiumPaywallPageState();
}

class _PremiumPaywallPageState extends State<PremiumPaywallPage> {
  static const _brandGradient = LinearGradient(
    colors: [
      Color(0xFF7B5CF0),
      Color(0xFFE96BD2),
      Color(0xFFFFA96C),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _pageBg = Color(0xFFF8F5FF);
  static const _cardBorder = Color(0xFFF0EAFB);
  static const _primaryPurple = Color(0xFF6A42E8);
  static const _softPurple = Color(0xFFF8F5FF);
  static const _softPink = Color(0xFFFFF4FB);

  bool _busy = false;
  bool _popped = false;

  @override
  void initState() {
    super.initState();

    RevenueCatService.instance.isPro.addListener(_maybeAutoPopIfPro);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoPopIfPro();
    });
  }

  @override
  void dispose() {
    RevenueCatService.instance.isPro.removeListener(_maybeAutoPopIfPro);
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

      await RevenueCatUI.presentPaywallIfNeeded(
        RevenueCatService.entitlementId,
      );

      await RevenueCatService.instance.refresh();

      if (!mounted) return;

      if (RevenueCatService.instance.isPro.value) {
        _maybeAutoPopIfPro();
      } else {
        _showSnack('Purchase not completed.');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack(RevenueCatService.instance.messageForPurchaseError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await RevenueCatService.instance.configureIfNeeded();

      final result = await RevenueCatService.instance.restoreWithResult();
      await RevenueCatService.instance.refresh();

      if (!mounted) return;

      if (result.status == RestorePurchaseStatus.restored) {
        _maybeAutoPopIfPro();
        return;
      }

      _showSnack(result.message);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Restore failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCustomerCenter() async {
    try {
      await RevenueCatUI.presentCustomerCenter();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Customer Center failed: $e');
    }
  }

  Widget _gradientButton({
    required String text,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: _brandGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B5CF0).withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlineActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _softPurple,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: _primaryPurple, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.black54,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.black38,
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _pageBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        children: [
          Image.asset(
            'assets/icon/aligna_inapp_icon.png',
            height: 28,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Aligna Pro',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: _brandGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7B5CF0).withOpacity(0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Unlock\nAligna Pro',
                    style: TextStyle(
                      fontSize: 30,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Get deeper relationship insights, more advanced results, and future premium features with a one-time lifetime unlock.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _softPink,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Lifetime Unlock',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _primaryPurple,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'What you unlock',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Upgrade once and keep access to premium Aligna features on this account.',
                    style: TextStyle(
                      color: Colors.black54,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _ProFeatureRow(
                    icon: Icons.insights_rounded,
                    text: 'Deep insight buckets',
                  ),
                  const SizedBox(height: 10),
                  const _ProFeatureRow(
                    icon: Icons.compare_arrows_rounded,
                    text: 'Full mismatch breakdown',
                  ),
                  const SizedBox(height: 10),
                  const _ProFeatureRow(
                    icon: Icons.picture_as_pdf_rounded,
                    text: 'Export report (PDF)',
                  ),
                  const SizedBox(height: 10),
                  const _ProFeatureRow(
                    icon: Icons.auto_awesome_rounded,
                    text: 'AI relationship summary',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _outlineActionTile(
              icon: Icons.restore_rounded,
              title: 'Restore purchases',
              subtitle:
              'Use this only if this same Aligna account previously bought Pro.',
              onTap: _busy ? null : _restore,
            ),
            const SizedBox(height: 12),
            _outlineActionTile(
              icon: Icons.manage_accounts_outlined,
              title: 'Customer Center',
              subtitle: 'Manage your purchases and subscription settings.',
              onTap: _openCustomerCenter,
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<bool>(
              valueListenable: RevenueCatService.instance.isReady,
              builder: (_, ready, __) {
                return ValueListenableBuilder<bool>(
                  valueListenable: RevenueCatService.instance.isPro,
                  builder: (_, isPro, __) {
                    final buttonLabel = !ready
                        ? 'Loading…'
                        : (isPro
                        ? 'Already unlocked'
                        : (_busy ? 'Opening…' : 'Continue'));

                    final helperText = !ready
                        ? 'Checking your purchase status…'
                        : (isPro
                        ? 'You already have Aligna Pro on this account.'
                        : 'One-time lifetime purchase. If you already bought Pro on another Aligna account, please log back into that original account.');

                    return Column(
                      children: [
                        _gradientButton(
                          text: buttonLabel,
                          onPressed: (!ready || _busy || isPro)
                              ? null
                              : _startPurchaseFlow,
                          icon: isPro
                              ? Icons.check_circle_rounded
                              : Icons.lock_open_rounded,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          helperText,
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

class _ProFeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ProFeatureRow({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF8F5FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 18,
            color: const Color(0xFF6A42E8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}