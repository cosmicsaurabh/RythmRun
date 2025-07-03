import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/landing/screens/landing_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/login/screens/login_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/registration/screens/registration_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/home/screens/home_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/settings_provider.dart';
import 'package:rythmrun_frontend_flutter/core/config/app_config.dart';
import 'package:rythmrun_frontend_flutter/core/services/settings_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await SettingsService.initialize();

  // Print configuration on app startup
  AppConfig.printConfig();

  runApp(const ProviderScope(child: RythmRunApp()));
}

class RythmRunApp extends ConsumerWidget {
  const RythmRunApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
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
            Icon(
              Icons.fitness_center,
              size: 80,
              color: Theme.of(context).primaryColor,
            ),
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
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
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

void _showDebugMenu(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('Debug Menu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Environment Info
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Environment: ${AppConfig.environment}'),
                    Text('Base URL: ${AppConfig.baseUrl}'),
                    Text('Timeout: ${AppConfig.timeout.inSeconds}s'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Session Management
              ListTile(
                title: const Text('Force Reinitialize Session'),
                onTap: () {
                  ref.read(sessionProvider.notifier).forceReinitialize();
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Clear Session'),
                onTap: () {
                  ref.read(sessionProvider.notifier).logout();
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Refresh Session'),
                onTap: () {
                  ref.read(sessionProvider.notifier).refreshSession();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
  );
}
