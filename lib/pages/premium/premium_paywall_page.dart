import 'package:flutter/material.dart';
import '../../services/supabase/premium_service.dart';

class PremiumPaywallPage extends StatefulWidget {
  const PremiumPaywallPage({super.key});

  @override
  State<PremiumPaywallPage> createState() => _PremiumPaywallPageState();
}

class _PremiumPaywallPageState extends State<PremiumPaywallPage> {
  final _premium = PremiumService();
  bool _busy = false;

  Future<void> _devUnlock() async {
    setState(() => _busy = true);
    try {
      await _premium.devUnlockLifetime(platform: 'unknown');
      if (!mounted) return;
      Navigator.pop(context, true); // tells previous page to refresh
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unlock failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
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
                  Text('Lifetime Unlock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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
            const Spacer(),

            // DEV button now — later replaced by real purchase flow (RevenueCat)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _busy ? null : _devUnlock,
                child: Text(_busy ? 'Unlocking…' : 'Unlock Premium (DEV)'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Payments integration comes next (RevenueCat).',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
