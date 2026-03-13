import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/pages/auth_page.dart';
import 'features/home/pages/home_page.dart';
import 'features/onboarding/pages/onboarding_page.dart';
import 'features/sessions/pages/join_session_page.dart';
import 'services/revenuecat/revenuecat_service.dart';

class AlignaApp extends StatefulWidget {
  const AlignaApp({super.key});

  @override
  State<AlignaApp> createState() => _AlignaAppState();
}

class _AlignaAppState extends State<AlignaApp> {
  final _navKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleUri(initial);
      }
    } catch (_) {}

    _sub = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    });
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'app') return;

    String? code;

    if (uri.host == 'invite') {
      if (uri.pathSegments.isNotEmpty) {
        code = uri.pathSegments.first;
      } else {
        code = uri.queryParameters['code'];
      }
    }

    if (code == null || code.trim().isEmpty) return;

    final cleaned = code.trim().toUpperCase();

    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => JoinSessionPage(initialCode: cleaned),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      title: 'Aligna',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const _RootGate(),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool? _seenOnboarding;
  bool _prefillRegister = false;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_seen') ?? false;
    final prefillRegister = prefs.getBool('auth_prefill_register') ?? false;

    if (!mounted) return;

    setState(() {
      _seenOnboarding = seen;
      _prefillRegister = prefillRegister;
    });
  }

  Future<void> _consumeRegisterPrefillIfNeeded() async {
    if (!_prefillRegister) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auth_prefill_register', false);

    if (!mounted) return;

    setState(() {
      _prefillRegister = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_seenOnboarding == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_seenOnboarding!) {
      return const OnboardingPage();
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = Supabase.instance.client.auth.currentSession;
        final user = session?.user;

        if (user == null) {
          final showRegisterFirst = _prefillRegister;

          if (showRegisterFirst) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _consumeRegisterPrefillIfNeeded();
            });
          }

          return AuthPage(initialIsLogin: !showRegisterFirst);
        }

        return const _PostLoginBootstrap(child: HomePage());
      },
    );
  }
}

class _PostLoginBootstrap extends StatefulWidget {
  final Widget child;
  const _PostLoginBootstrap({required this.child});

  @override
  State<_PostLoginBootstrap> createState() => _PostLoginBootstrapState();
}

class _PostLoginBootstrapState extends State<_PostLoginBootstrap> {
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runOnce();
  }

  Future<void> _runOnce() async {
    if (_done) return;
    _done = true;

    await RevenueCatService.instance.configureIfNeeded();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auth_prefill_register', false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}