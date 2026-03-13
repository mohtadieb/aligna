import 'package:app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/pages/auth_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
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

  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _finishing = false;

  final List<_OnboardingItem> _items = const [
    _OnboardingItem(
      title: 'Discover your\ncompatibility',
      subtitle:
      'Aligna helps couples explore how aligned they are across the topics that matter most.',
      icon: Icons.favorite_rounded,
      accentBg: Color(0xFFFFF0F3),
    ),
    _OnboardingItem(
      title: 'Answer together\nin private sessions',
      subtitle:
      'Create a private session, invite your partner, and complete thoughtful modules at your own pace.',
      icon: Icons.lock_rounded,
      accentBg: Color(0xFFF3EEFF),
    ),
    _OnboardingItem(
      title: 'Get insights,\nresults, and clarity',
      subtitle:
      'See your progress, compare answers, and unlock deeper relationship insights with Aligna.',
      icon: Icons.auto_awesome_rounded,
      accentBg: Color(0xFFFFF7EC),
    ),
  ];

  bool get _isLastPage => _currentIndex == _items.length - 1;

  Future<void> _goNext() async {
    HapticFeedback.lightImpact();

    if (_isLastPage) {
      await _finish();
      return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _skip() async {
    HapticFeedback.selectionClick();
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;

    setState(() {
      _finishing = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    await prefs.setBool('auth_prefill_register', true);

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AlignaApp()),
          (route) => false,
    );
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

  Widget _outlineButton({
    required String text,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: Colors.white,
        side: const BorderSide(color: _cardBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: const Text(
        'Skip',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: _primaryPurple,
        ),
      ),
    );
  }

  Widget _buildTopHero(_OnboardingItem item) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
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
        children: [
          Hero(
            tag: 'app-onboarding-icon',
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Icon(
                  item.icon,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 30,
              height: 1.08,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.subtitle,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(_OnboardingItem item) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
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
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: item.accentBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: _primaryPurple,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.supportTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...item.points.map(
                (point) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: _primaryPurple,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(
                        color: Colors.black87,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(_OnboardingItem item) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            children: [
              Hero(
                tag: 'app-app-icon',
                child: Material(
                  color: Colors.transparent,
                  child: Center(
                    child: Image.asset(
                      'assets/icon/aligna_inapp_icon.png',
                      height: 68,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildTopHero(item),
              const SizedBox(height: 16),
              _buildInfoCard(item),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_items.length, (index) {
        final selected = index == _currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected ? _primaryPurple : const Color(0xFFD8CCF6),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _items.length,
                onPageChanged: (index) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: KeyedSubtree(
                      key: ValueKey(index),
                      child: _buildPage(_items[index]),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                children: [
                  _buildDots(),
                  const SizedBox(height: 18),
                  _gradientButton(
                    text: _isLastPage ? 'Get started' : 'Continue',
                    onPressed: _finishing ? null : _goNext,
                    icon: _isLastPage
                        ? Icons.rocket_launch_rounded
                        : Icons.arrow_forward_rounded,
                  ),
                  const SizedBox(height: 10),
                  if (!_isLastPage)
                    _outlineButton(
                      text: 'Skip',
                      onPressed: _finishing ? null : _skip,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentBg;

  const _OnboardingItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentBg,
  });

  String get supportTitle {
    switch (title) {
      case 'Discover your\ncompatibility':
        return 'Understand what matters most';
      case 'Answer together\nin private sessions':
        return 'A guided experience for both of you';
      case 'Get insights,\nresults, and clarity':
        return 'Turn answers into useful reflection';
      default:
        return 'Welcome to Aligna';
    }
  }

  List<String> get points {
    switch (title) {
      case 'Discover your\ncompatibility':
        return const [
          'Explore key relationship topics in a structured and thoughtful way.',
          'See how aligned you are across values, lifestyle, communication, and more.',
          'Build better conversations around the areas that matter most.',
        ];
      case 'Answer together\nin private sessions':
        return const [
          'Create a private session and invite your partner with a simple code.',
          'Move through modules at your own pace without losing progress.',
          'Keep your answers organized in one calm, premium experience.',
        ];
      case 'Get insights,\nresults, and clarity':
        return const [
          'Track progress live as both of you complete your session.',
          'Review results, compare answers, and spot strong alignment or differences.',
          'Unlock deeper insights that help guide more meaningful conversations.',
        ];
      default:
        return const [];
    }
  }
}