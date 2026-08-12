import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/splash_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  ConnectivityService().startMonitoring();

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
        if (sessionState == SessionState.authenticatedOffline ||
            (sessionState == SessionState.checking &&
                session.errorMessage != null)) {
          ref.read(sessionProvider.notifier).refreshSession();
        }
        return;
      }

      _syncIfAvailable('reconnect');
    });

    final settings = ref.watch(settingsProvider);
    ref.watch(connectivityStatusProvider);

    return SessionStackNormalizer(
      navigatorKey: _navigatorKey,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'RythmRun',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: settings.flutterThemeMode,
        home: const AuthWrapper(),
        routes: buildAppRoutes(),
      ),
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

Widget _buildHomeScreen(BuildContext context) => const HomeScreen();

Widget _buildLandingScreen(BuildContext context) => const LandingScreen();

Widget _buildLoginScreen(BuildContext context) => const LoginScreen();

Widget _buildRegistrationScreen(BuildContext context) =>
    const RegistrationScreen();

Widget _buildSplashScreen(BuildContext context) => const SplashScreen();

/// The production named-route table. Exposing the table as a pure builder keeps
/// the direct-navigation authentication boundary covered by widget tests.
Map<String, WidgetBuilder> buildAppRoutes() {
  return <String, WidgetBuilder>{
    '/registration':
        (context) => SessionRouteGate(
          authenticatedBuilder: _buildHomeScreen,
          unauthenticatedBuilder: _buildRegistrationScreen,
          loadingBuilder: _buildSplashScreen,
        ),
    '/login':
        (context) => SessionRouteGate(
          authenticatedBuilder: _buildHomeScreen,
          unauthenticatedBuilder: _buildLoginScreen,
          loadingBuilder: _buildSplashScreen,
        ),
    '/home':
        (context) => SessionRouteGate(
          authenticatedBuilder: _buildHomeScreen,
          unauthenticatedBuilder: _buildLandingScreen,
          loadingBuilder: _buildSplashScreen,
        ),
    '/landing':
        (context) => SessionRouteGate(
          authenticatedBuilder: _buildHomeScreen,
          unauthenticatedBuilder: _buildLandingScreen,
          loadingBuilder: _buildSplashScreen,
        ),
  };
}

enum _SessionRoot { authenticated, unauthenticated }

_SessionRoot? _stableRootFor(SessionState state) {
  switch (state) {
    case SessionState.authenticated:
    case SessionState.authenticatedOffline:
      return _SessionRoot.authenticated;
    case SessionState.unauthenticated:
      return _SessionRoot.unauthenticated;
    case SessionState.initial:
    case SessionState.checking:
    case SessionState.refreshing:
      return null;
  }
}

/// Keeps route-owned screens from surviving an account-root transition.
///
/// Loading and refresh states are deliberately ignored. This means a token
/// refresh does not unexpectedly close an in-progress screen, while a genuine
/// signed-out -> signed-in (or signed-in -> signed-out) transition always
/// returns to the first route where [AuthWrapper] selects the new root.
class SessionStackNormalizer extends ConsumerStatefulWidget {
  const SessionStackNormalizer({
    required this.navigatorKey,
    required this.child,
    this.sessionListenable,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final ProviderListenable<SessionData>? sessionListenable;

  @override
  ConsumerState<SessionStackNormalizer> createState() =>
      _SessionStackNormalizerState();
}

class _SessionStackNormalizerState
    extends ConsumerState<SessionStackNormalizer> {
  _SessionRoot? _lastStableRoot;

  ProviderListenable<SessionData> get _sessionListenable =>
      widget.sessionListenable ?? sessionProvider;

  @override
  void initState() {
    super.initState();
    _lastStableRoot = _stableRootFor(ref.read(_sessionListenable).state);
  }

  @override
  void didUpdateWidget(SessionStackNormalizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionListenable != widget.sessionListenable) {
      _lastStableRoot = _stableRootFor(ref.read(_sessionListenable).state);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionData>(_sessionListenable, (previous, next) {
      final nextRoot = _stableRootFor(next.state);
      if (nextRoot == null) return;

      final previousRoot = _lastStableRoot;
      _lastStableRoot = nextRoot;
      if (previousRoot == null || previousRoot == nextRoot) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
      });
    });
    return widget.child;
  }
}

/// Lazily builds exactly one subtree for the current session state.
///
/// Keeping protected builders behind this gate prevents direct named-route
/// navigation from constructing authenticated UI before admission is known.
class SessionRouteGate extends ConsumerWidget {
  const SessionRouteGate({
    required this.authenticatedBuilder,
    required this.unauthenticatedBuilder,
    required this.loadingBuilder,
    this.sessionListenable,
    super.key,
  });

  final WidgetBuilder authenticatedBuilder;
  final WidgetBuilder unauthenticatedBuilder;
  final WidgetBuilder loadingBuilder;
  final ProviderListenable<SessionData>? sessionListenable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionData = ref.watch(sessionListenable ?? sessionProvider);

    switch (sessionData.state) {
      case SessionState.authenticated:
      case SessionState.authenticatedOffline:
        return authenticatedBuilder(context);
      case SessionState.unauthenticated:
        return unauthenticatedBuilder(context);
      case SessionState.initial:
      case SessionState.checking:
      case SessionState.refreshing:
        return loadingBuilder(context);
    }
  }
}

/// Wrapper widget that handles authentication state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({
    this.authenticatedBuilder = _buildHomeScreen,
    this.unauthenticatedBuilder = _buildLandingScreen,
    this.loadingBuilder = _buildSplashScreen,
    this.sessionListenable,
    super.key,
  });

  final WidgetBuilder authenticatedBuilder;
  final WidgetBuilder unauthenticatedBuilder;
  final WidgetBuilder loadingBuilder;
  final ProviderListenable<SessionData>? sessionListenable;

  @override
  Widget build(BuildContext context) {
    return SessionRouteGate(
      authenticatedBuilder: authenticatedBuilder,
      unauthenticatedBuilder: unauthenticatedBuilder,
      loadingBuilder: loadingBuilder,
      sessionListenable: sessionListenable,
    );
  }
}

// Debug menu function removed as it's not currently used
// Can be re-added if needed for debugging purposes
