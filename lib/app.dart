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
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _appLinks = AppLinks();

  static const _handledAuthCallbackKey = 'handled_auth_callback_uri';
  static const _handledAuthCallbackAtKey = 'handled_auth_callback_at_ms';

  StreamSubscription<Uri>? _linkSub;

  bool _initialLinkChecked = false;
  bool _forcePasswordRecovery = false;
  bool _isHandlingAuthCallback = false;
  bool _suppressSignedInUi = false;

  String? _pendingSnackBarMessage;

  // ADDED:
  // Stores the reset token_hash from the incoming deep link so it can be
  // passed to ResetPasswordPage and used for verifyOTP(...).
  String? _passwordRecoveryTokenHash;

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
        await _handleUri(initial);
      }
    } catch (_) {
      // Ignore and continue boot.
    } finally {
      if (mounted) {
        setState(() {
          _initialLinkChecked = true;
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _flushPendingSnackBar();
      });
    }

    _linkSub = _appLinks.uriLinkStream.listen((uri) async {
      await _handleUri(uri);
    });
  }

  void _queueSnackBar(String message) {
    _pendingSnackBarMessage = message;
    _flushPendingSnackBar();
  }

  void _flushPendingSnackBar() {
    final messenger = _scaffoldMessengerKey.currentState;
    final message = _pendingSnackBarMessage;

    if (messenger == null || message == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );

    _pendingSnackBarMessage = null;
  }

  Future<bool> _shouldIgnoreAuthCallback(Uri uri) async {
    final prefs = await SharedPreferences.getInstance();

    final lastUri = prefs.getString(_handledAuthCallbackKey);
    final lastAtMs = prefs.getInt(_handledAuthCallbackAtKey);

    if (lastUri == uri.toString()) {
      return true;
    }

    if (lastAtMs != null) {
      final lastAt = DateTime.fromMillisecondsSinceEpoch(lastAtMs);
      final age = DateTime.now().difference(lastAt);

      if (age < const Duration(seconds: 15) &&
          lastUri == uri.toString()) {
        return true;
      }
    }

    return false;
  }

  Future<void> _markAuthCallbackHandled(Uri uri) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_handledAuthCallbackKey, uri.toString());
    await prefs.setInt(
      _handledAuthCallbackAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _completeEmailConfirmationFlow() async {
    const timeout = Duration(seconds: 4);
    const step = Duration(milliseconds: 150);

    final auth = Supabase.instance.client.auth;
    final started = DateTime.now();

    while (auth.currentSession == null &&
        DateTime.now().difference(started) < timeout) {
      await Future.delayed(step);
    }

    try {
      await auth.signOut();
    } catch (_) {
      // Ignore if already signed out.
    }

    if (!mounted) return;

    setState(() {
      _forcePasswordRecovery = false;
      _isHandlingAuthCallback = false;
      _suppressSignedInUi = false;
    });

    _queueSnackBar('Email confirmed. You can now log in.');
  }

  // ADDED:
  // Helper to also support params that may be placed in the URL fragment.
  Map<String, String> _fragmentParams(Uri uri) {
    final fragment = uri.fragment;
    if (fragment.isEmpty) return {};

    // Supports fragments like:
    // #token_hash=...&type=recovery
    // or even nested URLs that leave key=value pairs in the fragment.
    return Uri.splitQueryString(fragment);
  }

  Future<void> _handleUri(Uri uri) async {
    if (uri.scheme != 'aligna') return;

    // ✅ EMAIL CONFIRMATION CALLBACK
    if (uri.host == 'auth-callback') {
      if (_isHandlingAuthCallback) return;
      if (!mounted) return;

      final shouldIgnore = await _shouldIgnoreAuthCallback(uri);
      if (shouldIgnore) return;

      await _markAuthCallbackHandled(uri);

      setState(() {
        _isHandlingAuthCallback = true;
        _suppressSignedInUi = true;
        _forcePasswordRecovery = false;
      });

      await _completeEmailConfirmationFlow();
      return;
    }

    // ✅ SESSION INVITES
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

    // ✅ PASSWORD RESET
    if (uri.host == 'reset-password') {
      if (!mounted) return;

      // ADDED:
      // Read token_hash + type from either normal query params
      // or the fragment, depending on how the website forwards the link.
      final fragmentParams = _fragmentParams(uri);

      final tokenHash =
          uri.queryParameters['token_hash'] ?? fragmentParams['token_hash'];

      final type =
          uri.queryParameters['type'] ?? fragmentParams['type'];

      // Optional debug logs while testing:
      debugPrint('Reset password URI: $uri');
      debugPrint('Reset password token_hash: $tokenHash');
      debugPrint('Reset password type: $type');

      setState(() {
        _forcePasswordRecovery = true;
        _passwordRecoveryTokenHash = tokenHash;
      });

      // ADDED:
      // Helpful guard message if the link reached the app but the token_hash
      // was not preserved by the website redirect/deep link.
      if (tokenHash == null || tokenHash.isEmpty) {
        _queueSnackBar(
          'Reset link is missing its recovery token. Please use the password reset email link again.',
        );
      }

      return;
    }
  }

  void _onPasswordResetCompleted() {
    if (!mounted) return;

    setState(() {
      _forcePasswordRecovery = false;
      _passwordRecoveryTokenHash = null; // ADDED
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
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Aligna',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: _RootGate(
        forcePasswordRecovery: _forcePasswordRecovery,
        suppressSignedInUi: _suppressSignedInUi,
        onPasswordResetCompleted: _onPasswordResetCompleted,

        // ADDED:
        recoveryTokenHash: _passwordRecoveryTokenHash,
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  final bool forcePasswordRecovery;
  final bool suppressSignedInUi;
  final VoidCallback onPasswordResetCompleted;

  // ADDED:
  final String? recoveryTokenHash;

  const _RootGate({
    required this.forcePasswordRecovery,
    required this.suppressSignedInUi,
    required this.onPasswordResetCompleted,
    this.recoveryTokenHash, // ADDED
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

    if (!widget.suppressSignedInUi && !_seenOnboarding!) {
      return const OnboardingPage();
    }

    if (widget.forcePasswordRecovery || _isInPasswordRecovery) {
      return ResetPasswordPage(
        onPasswordUpdated: _handlePasswordResetCompleted,

        // ADDED:
        recoveryTokenHash: widget.recoveryTokenHash,
      );
    }

    if (widget.suppressSignedInUi) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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