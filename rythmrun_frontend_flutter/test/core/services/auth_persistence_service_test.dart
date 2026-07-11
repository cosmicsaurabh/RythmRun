import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_persistence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearAuthData removes every persisted account value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'access_token': 'access-a',
      'refresh_token': 'refresh-a',
      'user_data': '{"id":"7"}',
      'last_backend_sync': '2026-07-11T00:00:00.000Z',
    });

    await AuthPersistenceService.markAuthCleanupPending();
    expect(await AuthPersistenceService.hasPendingAuthCleanup(), isTrue);

    await AuthPersistenceService.clearAuthData();
    await AuthPersistenceService.clearAuthData();

    final stored = await AuthPersistenceService.getAllStoredData();
    expect(stored.values, everyElement(isNull));
    expect(await AuthPersistenceService.hasPendingAuthCleanup(), isFalse);
  });
}
