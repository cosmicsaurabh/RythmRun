import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/registration_request_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/login_user_usecase.dart';
import 'package:rythmrun_frontend_flutter/domain/usecases/register_user_usecase.dart';
import 'package:rythmrun_frontend_flutter/main.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/session/user_scope_teardown.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/providers/login_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/screens/login_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/registration/providers/registration_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/registration/screens/registration_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/home/screens/home_screen.dart';

void main() {
  group('SessionRouteGate', () {
    testWidgets(
      'never constructs the protected route while session is unresolved or signed out',
      (tester) async {
        final session = _TestSessionNotifier(SessionState.checking);
        final testSessionProvider =
            StateNotifierProvider<_TestSessionNotifier, SessionData>(
              (ref) => session,
            );
        var protectedBuilds = 0;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: SessionRouteGate(
                sessionListenable: testSessionProvider,
                authenticatedBuilder: (context) {
                  protectedBuilds += 1;
                  return const Text('protected');
                },
                unauthenticatedBuilder: (context) => const Text('signed out'),
                loadingBuilder: (context) => const Text('checking'),
              ),
            ),
          ),
        );

        expect(find.text('checking'), findsOneWidget);
        expect(protectedBuilds, 0);

        session.setState(SessionState.unauthenticated);
        await tester.pump();

        expect(find.text('signed out'), findsOneWidget);
        expect(protectedBuilds, 0);

        session.setState(SessionState.authenticated);
        await tester.pump();

        expect(find.text('protected'), findsOneWidget);
        expect(protectedBuilds, 1);
      },
    );

    testWidgets('guards a directly pushed home route before building it', (
      tester,
    ) async {
      final session = _TestSessionNotifier(SessionState.unauthenticated);
      final testSessionProvider =
          StateNotifierProvider<_TestSessionNotifier, SessionData>(
            (ref) => session,
          );
      final navigatorKey = GlobalKey<NavigatorState>();
      var protectedBuilds = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Text('public root'),
            routes: {
              '/home':
                  (context) => SessionRouteGate(
                    sessionListenable: testSessionProvider,
                    authenticatedBuilder: (context) {
                      protectedBuilds += 1;
                      return const Text('protected home');
                    },
                    unauthenticatedBuilder:
                        (context) => const Text('guest fallback'),
                    loadingBuilder: (context) => const Text('checking'),
                  ),
            },
          ),
        ),
      );

      navigatorKey.currentState!.pushNamed('/home');
      await tester.pumpAndSettle();

      expect(find.text('guest fallback'), findsOneWidget);
      expect(find.text('protected home'), findsNothing);
      expect(protectedBuilds, 0);

      session.setState(SessionState.checking);
      await tester.pump();

      expect(find.text('checking'), findsOneWidget);
      expect(protectedBuilds, 0);
    });

    testWidgets(
      'unverified session with unavailable network never builds protected UI',
      (tester) async {
        final session = SessionNotifier(
          _UnavailableUnverifiedAuthRepository(),
          _NoopUserScopeTeardown(),
        );
        final testSessionProvider =
            StateNotifierProvider<SessionNotifier, SessionData>(
              (ref) => session,
            );
        var protectedBuilds = 0;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: SessionRouteGate(
                sessionListenable: testSessionProvider,
                authenticatedBuilder: (context) {
                  protectedBuilds++;
                  return const Text('protected');
                },
                unauthenticatedBuilder: (context) => const Text('guest'),
                loadingBuilder:
                    (context) => const Text('verification required'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('verification required'), findsOneWidget);
        expect(session.state.state, SessionState.checking);
        expect(protectedBuilds, 0);
      },
    );

    testWidgets('the production /home route is guarded', (tester) async {
      final session = _TestSessionNotifier(SessionState.unauthenticated);
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionProvider.overrideWith((ref) => session)],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Text('public root'),
            routes: buildAppRoutes(),
          ),
        ),
      );

      navigatorKey.currentState!.pushNamed('/home');
      await tester.pump();
      expect(find.byType(HomeScreen), findsNothing);

      session.setState(SessionState.checking);
      await tester.pump();
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });
  });

  group('SessionStackNormalizer', () {
    testWidgets('normalizes login and registration success to one root', (
      tester,
    ) async {
      final session = _TestSessionNotifier(SessionState.unauthenticated);
      final testSessionProvider =
          StateNotifierProvider<_TestSessionNotifier, SessionData>(
            (ref) => session,
          );
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          child: SessionStackNormalizer(
            navigatorKey: navigatorKey,
            sessionListenable: testSessionProvider,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: SessionRouteGate(
                sessionListenable: testSessionProvider,
                authenticatedBuilder:
                    (context) => const Text('authenticated root'),
                unauthenticatedBuilder: (context) => const Text('guest root'),
                loadingBuilder: (context) => const Text('checking root'),
              ),
              routes: {
                '/auth-form':
                    (context) => const Scaffold(body: Text('auth form')),
              },
            ),
          ),
        ),
      );

      navigatorKey.currentState!.pushNamed('/auth-form');
      await tester.pumpAndSettle();
      expect(find.text('auth form'), findsOneWidget);

      session.setState(SessionState.checking);
      await tester.pump();
      expect(find.text('auth form'), findsOneWidget);

      session.setState(SessionState.authenticated);
      await tester.pumpAndSettle();

      expect(find.text('auth form'), findsNothing);
      expect(find.text('authenticated root'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isFalse);
    });

    testWidgets('does not close a route for a same-account token refresh', (
      tester,
    ) async {
      final session = _TestSessionNotifier(SessionState.authenticated);
      final testSessionProvider =
          StateNotifierProvider<_TestSessionNotifier, SessionData>(
            (ref) => session,
          );
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          child: SessionStackNormalizer(
            navigatorKey: navigatorKey,
            sessionListenable: testSessionProvider,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: const Text('authenticated root'),
              routes: {
                '/details':
                    (context) => const Scaffold(body: Text('workout details')),
              },
            ),
          ),
        ),
      );

      navigatorKey.currentState!.pushNamed('/details');
      await tester.pumpAndSettle();

      session.setState(SessionState.refreshing);
      await tester.pump();
      session.setState(SessionState.authenticated);
      await tester.pumpAndSettle();

      expect(find.text('workout details'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isTrue);
    });
  });

  group('authentication screen success ownership', () {
    testWidgets(
      'login and registration both normalize to the authenticated root',
      (tester) async {
        for (final path in <String>['/login', '/registration']) {
          final repository = _SuccessfulAuthRepository();
          final session = _TestSessionNotifier(SessionState.unauthenticated);
          final testSessionProvider =
              StateNotifierProvider<_TestSessionNotifier, SessionData>(
                (ref) => session,
              );
          final loginNotifier = LoginNotifier(
            LoginUserUsecase(repository),
            beginAuthentication: () => 0,
            completeAuthentication: (user, _) {
              session.setState(SessionState.authenticated);
              return user == _SuccessfulAuthRepository.user;
            },
          );
          final registrationNotifier = RegistrationNotifier(
            RegisterUserUsecase(repository),
            beginAuthentication: () => 0,
            completeAuthentication: (user, _) {
              session.setState(SessionState.authenticated);
              return user == _SuccessfulAuthRepository.user;
            },
          );
          final navigatorKey = GlobalKey<NavigatorState>();

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                loginProvider.overrideWith((ref) => loginNotifier),
                registrationProvider.overrideWith(
                  (ref) => registrationNotifier,
                ),
              ],
              child: SessionStackNormalizer(
                navigatorKey: navigatorKey,
                sessionListenable: testSessionProvider,
                child: MaterialApp(
                  navigatorKey: navigatorKey,
                  home: SessionRouteGate(
                    sessionListenable: testSessionProvider,
                    authenticatedBuilder:
                        (context) => const Text('authenticated root'),
                    unauthenticatedBuilder:
                        (context) => const Text('guest root'),
                    loadingBuilder: (context) => const Text('checking root'),
                  ),
                  routes: {
                    '/login': (context) => const LoginScreen(),
                    '/registration': (context) => const RegistrationScreen(),
                  },
                ),
              ),
            ),
          );
          navigatorKey.currentState!.pushNamed(path);
          await tester.pumpAndSettle();

          if (path == '/login') {
            await loginNotifier.loginUser();
          } else {
            await registrationNotifier.registerUser();
          }
          await tester.pumpAndSettle();

          expect(find.text('authenticated root'), findsOneWidget);
          expect(navigatorKey.currentState!.canPop(), isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets('login reports success without popping its own route', (
      tester,
    ) async {
      final repository = _SuccessfulAuthRepository();
      final notifier = LoginNotifier(
        LoginUserUsecase(repository),
        beginAuthentication: () => 0,
        completeAuthentication: (_, _) => true,
      );
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [loginProvider.overrideWith((ref) => notifier)],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Text('guest root'),
            routes: {'/login': (context) => const LoginScreen()},
          ),
        ),
      );
      navigatorKey.currentState!.pushNamed('/login');
      await tester.pumpAndSettle();

      await notifier.loginUser();
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isTrue);
      expect(find.text('Welcome Back!'), findsOneWidget);
    });

    testWidgets('registration reports signed-in success without a dialog', (
      tester,
    ) async {
      final repository = _SuccessfulAuthRepository();
      final notifier = RegistrationNotifier(
        RegisterUserUsecase(repository),
        beginAuthentication: () => 0,
        completeAuthentication: (_, _) => true,
      );
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [registrationProvider.overrideWith((ref) => notifier)],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Text('guest root'),
            routes: {'/registration': (context) => const RegistrationScreen()},
          ),
        ),
      );
      navigatorKey.currentState!.pushNamed('/registration');
      await tester.pumpAndSettle();

      await notifier.registerUser();
      await tester.pump();

      expect(find.byType(RegistrationScreen), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Continue to Sign In'), findsNothing);
      expect(find.text("Account created. You're signed in!"), findsOneWidget);
    });
  });
}

class _TestSessionNotifier extends SessionNotifier {
  _TestSessionNotifier(SessionState initialState)
    : super(
        _UnavailableUnverifiedAuthRepository(),
        _NoopUserScopeTeardown(),
        autoInitialize: false,
      ) {
    state = SessionData(state: initialState);
  }

  void setState(SessionState next) {
    state = SessionData(state: next);
  }
}

class _SuccessfulAuthRepository implements AuthRepository {
  static const user = UserEntity(
    id: '7',
    firstName: 'A',
    lastName: 'Runner',
    email: 'runner@example.com',
  );

  @override
  Future<UserEntity> login(LoginRequestEntity request) async => user;

  @override
  Future<UserEntity> register(RegistrationRequestEntity request) async => user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnavailableUnverifiedAuthRepository implements AuthRepository {
  @override
  Future<bool> hasPendingAuthCleanup() async => false;

  @override
  Future<UserEntity?> getCurrentUser() async => _SuccessfulAuthRepository.user;

  @override
  Future<bool> needsTokenRefresh() async => false;

  @override
  Future<bool> canStayLoggedInOffline() async => false;

  @override
  Future<SessionValidationStatus> validateSession() async {
    return SessionValidationStatus.unavailable;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopUserScopeTeardown implements UserScopeTeardown {
  @override
  void activateUserScope(String userId) {}

  @override
  UserScopeExitRequirement requirementFor(UserScopeExitReason reason) {
    return UserScopeExitRequirement.none;
  }

  @override
  Future<UserScopeTeardownResult> teardown({
    required UserScopeExitReason reason,
    UserScopeExitDecision? decision,
  }) async {
    return const UserScopeTeardownResult.completed();
  }
}
