import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/core/models/app_settings.dart';
import 'package:rythmrun_frontend_flutter/core/services/connectivity_service.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/settings_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/connectivity_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/settings/screens/settings_screen.dart';

void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    required bool hasPassword,
    Future<bool> Function(Uri uri)? externalUrlLauncher,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _MemorySettingsRepository(),
          ),
          currentConnectivityStatusProvider.overrideWithValue(
            ConnectivityStatus.connected,
          ),
          currentUserProvider.overrideWithValue(
            UserEntity(
              id: '7',
              firstName: 'A',
              lastName: 'Runner',
              email: 'runner@example.test',
              hasPassword: hasPassword,
            ),
          ),
        ],
        child: MaterialApp(
          home: SettingsScreen(externalUrlLauncher: externalUrlLauncher),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows change password for password-capable accounts', (
    tester,
  ) async {
    await pumpSettings(tester, hasPassword: true);

    expect(find.text('Change Password'), findsOneWidget);
  });

  testWidgets('hides change password for Google-only accounts', (tester) async {
    await pumpSettings(tester, hasPassword: false);

    expect(find.text('Change Password'), findsNothing);
  });

  testWidgets('opens the public account deletion request page', (tester) async {
    Uri? launchedUri;
    await pumpSettings(
      tester,
      hasPassword: true,
      externalUrlLauncher: (uri) async {
        launchedUri = uri;
        return true;
      },
    );

    await tester.ensureVisible(find.text('Delete Account').first);
    await tester.tap(find.text('Delete Account').first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('RythmRun account deletion page'),
      findsOneWidget,
    );
    expect(find.text('Account deletion feature coming soon!'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      launchedUri,
      Uri.parse('https://cosmicsaurabh.github.io/RythmRun/delete-account'),
    );
  });
}

class _MemorySettingsRepository implements SettingsRepository {
  AppSettings settings = const AppSettings();

  @override
  Future<void> clearSettings() async {
    settings = const AppSettings();
  }

  @override
  Future<AppSettings> getSettings() async => settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    this.settings = settings;
  }

  @override
  Future<void> updateMeasurementUnit(MeasurementUnit measurementUnit) async {
    settings = settings.copyWith(measurementUnit: measurementUnit);
  }

  @override
  Future<void> updateThemeMode(AppThemeMode themeMode) async {
    settings = settings.copyWith(themeMode: themeMode);
  }
}
