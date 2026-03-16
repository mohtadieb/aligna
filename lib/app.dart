import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/pages/auth_page.dart';
import 'features/auth/pages/reset_password_page.dart';
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

  StreamSubscription<Uri>? _linkSub;

  bool _initialLinkChecked = false;
  bool _forcePasswordRecovery = false;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleUri(initial);
      }
    } catch (_) {
      // Ignore and continue boot.
    } finally {
      if (mounted) {
        setState(() {
          _initialLinkChecked = true;
        });
      }
    }

    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    });
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'aligna') return;

    if (uri.host == 'invite') {
      String? code;

      if (uri.pathSegments.isNotEmpty) {
        code = uri.pathSegments.first;
      } else {
        code = uri.queryParameters['code'];
      }

      if (code == null || code.trim().isEmpty) return;

      final cleaned = code.trim().toUpperCase();

      _navKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => JoinSessionPage(initialCode: cleaned),
        ),
      );
      return;
    }

    if (uri.host == 'reset-password') {
      if (!mounted) return;

      setState(() {
        _forcePasswordRecovery = true;
      });
    }
  }

  void _onPasswordResetCompleted() {
    if (!mounted) return;

    setState(() {
      _forcePasswordRecovery = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialLinkChecked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Aligna',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      title: 'Aligna',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: _RootGate(
        forcePasswordRecovery: _forcePasswordRecovery,
        onPasswordResetCompleted: _onPasswordResetCompleted,
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  final bool forcePasswordRecovery;
  final VoidCallback onPasswordResetCompleted;

  const _RootGate({
    required this.forcePasswordRecovery,
    required this.onPasswordResetCompleted,
  });

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool? _seenOnboarding;
  bool _prefillRegister = false;
  bool _isInPasswordRecovery = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _loadFlags();
    _listenToAuthChanges();
  }

  @override
  void didUpdateWidget(covariant _RootGate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.forcePasswordRecovery && !_isInPasswordRecovery) {
      _isInPasswordRecovery = true;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _listenToAuthChanges() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;

      if (!mounted) return;

      if (event == AuthChangeEvent.passwordRecovery) {
        setState(() {
          _isInPasswordRecovery = true;
        });
        return;
      }

      if (event == AuthChangeEvent.userUpdated) {
        setState(() {
          _isInPasswordRecovery = false;
        });
        return;
      }

      if (event == AuthChangeEvent.signedOut) {
        setState(() {
          _isInPasswordRecovery = false;
        });
      }
    });
  }

  Future<void> _loadFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_seen') ?? false;
    final prefillRegister = prefs.getBool('auth_prefill_register') ?? false;

    if (!mounted) return;

    setState(() {
      _seenOnboarding = seen;
      _prefillRegister = prefillRegister;
      if (widget.forcePasswordRecovery) {
        _isInPasswordRecovery = true;
      }
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

  void _handlePasswordResetCompleted() {
    setState(() {
      _isInPasswordRecovery = false;
    });
    widget.onPasswordResetCompleted();
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

    if (_isInPasswordRecovery) {
      return ResetPasswordPage(
        onPasswordUpdated: _handlePasswordResetCompleted,
      );
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            Supabase.instance.client.auth.currentSession == null) {
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