import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/config/app_config.dart';

void main() {
  bool usable({
    TargetPlatform platform = TargetPlatform.android,
    bool isWeb = false,
    String baseUrl = 'https://api.example.test/api',
    String? serverClientId = 'server-client-id',
    String? clientId,
  }) {
    return AppConfig.isGoogleSignInConfigurationUsable(
      platform: platform,
      isWeb: isWeb,
      baseUrl: baseUrl,
      serverClientId: serverClientId,
      clientId: clientId,
    );
  }

  test('Android requires HTTPS and a nonempty server client ID', () {
    expect(usable(), isTrue);
    expect(usable(baseUrl: 'http://api.example.test/api'), isFalse);
    expect(usable(serverClientId: null), isFalse);
    expect(usable(serverClientId: '  '), isFalse);
  });

  test('iOS additionally requires a nonempty application client ID', () {
    expect(usable(platform: TargetPlatform.iOS), isFalse);
    expect(
      usable(platform: TargetPlatform.iOS, clientId: 'ios-client-id'),
      isTrue,
    );
    expect(usable(platform: TargetPlatform.iOS, clientId: '  '), isFalse);
  });

  test('web and unsupported desktop platforms stay hidden', () {
    expect(usable(isWeb: true), isFalse);
    expect(usable(platform: TargetPlatform.macOS), isFalse);
    expect(usable(platform: TargetPlatform.windows), isFalse);
  });
}
