import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/landing/screens/landing_screen.dart';
import 'theme/app_theme.dart';
import 'presentation/features/registration/screens/registration_screen.dart';

void main() {
  runApp(const ProviderScope(child: RythmRunApp()));
}

class RythmRunApp extends StatelessWidget {
  const RythmRunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RythmRun',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const LandingScreen(),
      routes: {'/registration': (context) => const RegistrationScreen()},
    );
  }
}
