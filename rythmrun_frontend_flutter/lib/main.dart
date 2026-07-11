import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/features/ads/service/ads_providers.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/connectivity_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/landing/screens/landing_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/screens/login_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/registration/screens/registration_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/home/screens/home_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/session/user_scope_teardown.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/settings_provider.dart';
import 'package:rythmrun_frontend_flutter/core/config/app_config.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/core/services/connectivity_service.dart';
import 'package:rythmrun_frontend_flutter/core/services/settings_service.dart';
import 'package:rythmrun_frontend_flutter/core/utils/feature_gate.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await SettingsService.initialize();

  // Print configuration on app startup
  AppConfig.printConfig();

  runApp(const ProviderScope(child: RythmRunApp()));
}

class RythmRunApp extends ConsumerStatefulWidget {
  const RythmRunApp({super.key});

  @override
  ConsumerState<RythmRunApp> createState() => _RythmRunAppState();
}

class _RythmRunAppState extends ConsumerState<RythmRunApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _isShowingExitResolutionDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncIfAvailable('app resume');
    }
  }

  void _syncIfAvailable(String reason) {
    final session = ref.read(sessionProvider);
    if (session.pendingExitReason != null) return;
    final sessionState = session.state;
    final hasSyncAccess = FeatureGate.isFeatureAvailable(
      'sync_workouts',
      sessionState,
    );
    if (!hasSyncAccess) {
      return;
    }

    ref.read(syncCoordinatorProvider).syncAll().catchError((error) {
      debugPrint('Sync on $reason failed: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.read(adsServiceProvider).initialize();
    ref.listen<SessionData>(sessionProvider, (previous, next) {
      final hadSyncAccess = FeatureGate.isFeatureAvailable(
        'sync_workouts',
        previous?.state ?? SessionState.initial,
      );
      final hasSyncAccess = FeatureGate.isFeatureAvailable(
        'sync_workouts',
        next.state,
      );

      if (!hadSyncAccess && hasSyncAccess && next.pendingExitReason == null) {
        _syncIfAvailable('session restore');
      }

      if (next.state == SessionState.checking &&
          next.pendingExitReason != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        });
      }

      final needsExitResolution =
          next.pendingExitReason != null &&
          next.exitRequirement != UserScopeExitRequirement.none;
      if (needsExitResolution) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showExitResolution();
        });
      }
    });
    ref.listen<AsyncValue<ConnectivityStatus>>(connectivityStatusProvider, (
      previous,
      next,
    ) {
      final previousStatus = previous?.valueOrNull;
      final nextStatus = next.valueOrNull;

      if (previousStatus == ConnectivityStatus.connected ||
          nextStatus != ConnectivityStatus.connected) {
        return;
      }

      final session = ref.read(sessionProvider);
      if (session.pendingExitReason != null) return;
      final sessionState = session.state;
      final hasSyncAccess = FeatureGate.isFeatureAvailable(
        'sync_workouts',
        sessionState,
      );
      if (!hasSyncAccess) {
        if (sessionState == SessionState.authenticatedOffline) {
          ref.read(sessionProvider.notifier).refreshSession();
        }
        return;
      }

      _syncIfAvailable('reconnect');
    });

    final settings = ref.watch(settingsProvider);
    ref.watch(connectivityStatusProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'RythmRun',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: settings.flutterThemeMode,
      home: const AuthWrapper(),
      routes: {
        '/registration': (context) => const RegistrationScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/landing': (context) => const LandingScreen(),
      },
    );
  }

  Future<void> _showExitResolution() async {
    if (_isShowingExitResolutionDialog || !mounted) return;
    final session = ref.read(sessionProvider);
    final reason = session.pendingExitReason;
    final requirement = session.exitRequirement;
    if (reason == null || requirement == UserScopeExitRequirement.none) return;

    late final String title;
    late final String content;
    late final String retryLabel;
    late final UserScopeExitDecision retryDecision;
    var canDiscard = false;
    var canStaySignedIn = false;

    switch (requirement) {
      case UserScopeExitRequirement.activeWorkout:
        title = 'Workout in progress';
        content =
            'Finish and save the active workout, or explicitly discard it before account cleanup.';
        retryLabel = 'Finish & continue';
        retryDecision = UserScopeExitDecision.finishWorkout;
        canDiscard = true;
        canStaySignedIn =
            reason == UserScopeExitReason.voluntaryLogout ||
            reason == UserScopeExitReason.accountSwitch;
        break;
      case UserScopeExitRequirement.unsavedWorkout:
        title = 'Workout not saved';
        content =
            'Retry the local save or explicitly discard the workout before account cleanup can continue.';
        retryLabel = 'Retry save';
        retryDecision = UserScopeExitDecision.retrySave;
        canDiscard = true;
        canStaySignedIn = reason == UserScopeExitReason.voluntaryLogout;
        break;
      case UserScopeExitRequirement.trackingCleanup:
        title = 'Tracking cleanup incomplete';
        content =
            'Location tracking is still shutting down. Retry cleanup before account exit can continue.';
        retryLabel = 'Retry tracking cleanup';
        retryDecision = UserScopeExitDecision.retryTrackingCleanup;
        break;
      case UserScopeExitRequirement.localCredentialCleanup:
        title = 'Sign-out cleanup incomplete';
        content =
            'Local credentials could not be cleared. Retry cleanup before another account can sign in.';
        retryLabel = 'Retry credential cleanup';
        retryDecision = UserScopeExitDecision.retryCredentialCleanup;
        break;
      case UserScopeExitRequirement.accountCleanup:
        title = 'Account cleanup incomplete';
        content =
            'Account cleanup could not finish safely. Retry before another account can sign in.';
        retryLabel = 'Retry account cleanup';
        retryDecision = UserScopeExitDecision.retryAccountCleanup;
        break;
      case UserScopeExitRequirement.none:
        return;
    }

    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) return;

    _isShowingExitResolutionDialog = true;
    try {
      final decision = await showDialog<UserScopeExitDecision>(
        context: dialogContext,
        barrierDismissible: false,
        builder:
            (context) => PopScope(
              canPop: false,
              child: AlertDialog(
                title: Text(title),
                content: Text(content),
                actions: [
                  if (canStaySignedIn)
                    TextButton(
                      onPressed: () {
                        ref.read(sessionProvider.notifier).cancelPendingExit();
                        Navigator.pop(context);
                      },
                      child: const Text('Stay signed in'),
                    ),
                  if (canDiscard)
                    TextButton(
                      onPressed:
                          () => Navigator.pop(
                            context,
                            UserScopeExitDecision.discardWorkout,
                          ),
                      child: const Text('Discard workout'),
                    ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, retryDecision),
                    child: Text(retryLabel),
                  ),
                ],
              ),
            ),
      );
      if (decision == null || !mounted) return;

      final result = await ref
          .read(sessionProvider.notifier)
          .resolvePendingExit(decision);
      if (!mounted || result.isCompleted) return;

      final currentContext = _navigatorKey.currentContext;
      if (currentContext != null && currentContext.mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'The workout is still not saved.'),
          ),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showExitResolution();
      });
    } finally {
      _isShowingExitResolutionDialog = false;
    }
  }
}

/// Wrapper widget that handles authentication state
class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionData = ref.watch(sessionProvider);

    switch (sessionData.state) {
      case SessionState.initial:
      case SessionState.checking:
      case SessionState.refreshing:
        return const SplashScreen();

      case SessionState.authenticated:
      case SessionState.authenticatedOffline:
        return const HomeScreen();

      case SessionState.unauthenticated:
        return const LandingScreen();
    }
  }
}

/// Simple splash screen shown while checking authentication
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo or icon
            Icon(fitnessIcon, size: 80, color: Theme.of(context).primaryColor),
            const SizedBox(height: 24),
            Text(
              'RythmRun',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 48),
            // Loading indicator
            CupertinoActivityIndicator(),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// Debug menu function removed as it's not currently used
// Can be re-added if needed for debugging purposes
