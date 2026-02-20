import 'package:flutter/material.dart';

class PremiumGate extends StatelessWidget {
  final bool isPremium;
  final Widget child;
  final Widget locked;

  const PremiumGate({
    super.key,
    required this.isPremium,
    required this.child,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) => isPremium ? child : locked;
}
