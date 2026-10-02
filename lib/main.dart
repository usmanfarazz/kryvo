import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'disguise/disguise_host.dart';
import 'l10n/strings.dart';
import 'screens/home_screen.dart';
import 'services/motion_lock.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/setup_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const SecureVaultApp(),
    ),
  );
}

class SecureVaultApp extends StatefulWidget {
  const SecureVaultApp({super.key});

  @override
  State<SecureVaultApp> createState() => _SecureVaultAppState();
}

class _SecureVaultAppState extends State<SecureVaultApp>
    with WidgetsBindingObserver {
  final _nav = GlobalKey<NavigatorState>();
  String? _lastScreen;

  static String _rootScreen(AppState app) =>
      app.status == VaultStatus.locked && app.disguised && !app.disguiseRevealed
          ? 'disguise'
          : app.status.name;

  late final _motion = MotionLock(() => context.read<AppState>().lock(force: true));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock the moment the app leaves the foreground. `inactive` is NOT a
    // reason to lock: it also fires when the notification shade is pulled
    // down or a system dialog shows over the app, while the user is still in
    // it. Recents/home/other apps always go on to `hidden`/`paused`.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      context.read<AppState>().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        // Whenever the root screen changes (vault locks or unlocks, or a
        // disguise hands over to the lock screen) close every screen that was
        // opened on top (folders, viewer, settings, a disguise's dialogs…)
        // so nothing stays visible over the new root.
        final screen = _rootScreen(app);
        if (_lastScreen != null && _lastScreen != screen) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _nav.currentState?.popUntil((r) => r.isFirst));
        }
        _lastScreen = screen;
        _motion.update(
            unlocked: app.isUnlocked,
            shake: app.shakeLock,
            faceDown: app.faceDownLock);
        // Any touch anywhere in the app counts as activity, so the auto-lock
        // timer only fires after real inactivity — not while the user is on
        // Settings, App info, Feedback, etc.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => app.registerActivity(),
          child: MaterialApp(
          navigatorKey: _nav,
          title: 'Kryvo',
          debugShowCheckedModeBanner: false,
          // Language + right-to-left layout for Urdu / Arabic.
          locale: Locale(app.lang),
          supportedLocales: [for (final l in kLanguages) Locale(l.code)],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(),
          home: Builder(
            builder: (context) {
              switch (app.status) {
                case VaultStatus.loading:
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                case VaultStatus.needsSetup:
                  return SetupScreen();
                case VaultStatus.locked:
                  if (app.disguised && !app.disguiseRevealed) {
                    return DisguiseHost(id: app.appIcon);
                  }
                  return const LockScreen();
                case VaultStatus.unlocked:
                  if (!app.onboarded && !app.decoy) {
                    return const OnboardingScreen();
                  }
                  return const HomeScreen();
              }
            },
          ),
          ),
        );
      },
    );
  }
}
