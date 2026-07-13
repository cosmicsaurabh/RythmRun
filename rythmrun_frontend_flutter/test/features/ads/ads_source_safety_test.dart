import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const googleSamplePublisherId = '3940256099942544';

  test('shipping ads sources contain only Google sample publisher IDs', () {
    final paths = <String>{
      ..._filesUnder('lib', const {'.dart'}).map((file) => file.path),
      ..._filesUnder('android/app/src', const {
        'AndroidManifest.xml',
      }).map((file) => file.path),
      ..._filesUnder('ios/Runner', const {
        '.plist',
        '.swift',
        '.m',
        '.mm',
        '.h',
      }).map((file) => file.path),
      ..._filesUnder('ios/Flutter', const {
        '.xcconfig',
      }).map((file) => file.path),
      ..._filesUnder('ios/Runner.xcodeproj', const {
        '.pbxproj',
        '.xcconfig',
      }).map((file) => file.path),
      ..._filesUnder('scripts', const {
        '.sh',
        '.dart',
        '.gradle',
      }).map((file) => file.path),
      ..._filesUnder('../.github/workflows', const {
        '.yml',
        '.yaml',
      }).map((file) => file.path),
      ..._filesUnder('../docs', const {'.md'}).map((file) => file.path),
      'CONFIGURATION.md',
      'android/app/build.gradle',
      'android/build.gradle',
      'android/build.gradle.kts',
      'android/settings.gradle',
      'android/settings.gradle.kts',
      'android/gradle.properties',
      'android/gradle/wrapper/gradle-wrapper.properties',
    }..removeWhere((path) => !File(path).existsSync());
    final files =
        paths.map(File.new).toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final committedId = RegExp(r'ca-app-pub-([0-9]{16})(?:[~/][0-9]{10})?');
    final violations = <String>[];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in committedId.allMatches(source)) {
        if (match.group(1) != googleSamplePublisherId) {
          violations.add(file.path);
          break;
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Production AdMob identifiers must be supplied by --dart-define, '
          'never committed to source.',
    );
  });

  test('Android manifest obtains its AdMob app ID from a placeholder', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains(r'android:value="${admobApplicationId}"'));
    expect(manifest, isNot(contains('ca-app-pub-')));
    expect(
      manifest,
      contains('com.google.android.gms.ads.DELAY_APP_MEASUREMENT_INIT'),
    );
    expect(manifest, contains('android:value="true"'));
    for (final permission in [
      'com.google.android.gms.permission.AD_ID',
      'android.permission.ACCESS_ADSERVICES_AD_ID',
      'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
      'android.permission.ACCESS_ADSERVICES_TOPICS',
    ]) {
      expect(manifest, contains(permission));
    }
    expect('tools:node="remove"'.allMatches(manifest), hasLength(4));
  });

  test('Gradle validates release ad settings before native injection', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();

    for (final key in [
      'ADS_ENV',
      'ADS_ENABLED',
      'ADMOB_ANDROID_APP_ID',
      'ADMOB_POST_ACTIVITY_UNIT_ID',
    ]) {
      expect(gradle, contains(key), reason: 'Missing Gradle contract for $key');
    }

    expect(gradle, contains("project.hasProperty('dart-defines')"));
    expect(gradle, contains('decodeBase64()'));
    expect(gradle, contains("dartDefines.containsKey('ADS_ENV')"));
    expect(gradle, contains("dartDefines.containsKey('ADS_ENABLED')"));
    expect(
      gradle,
      contains('if (adsConfigurationError == null && productionAdsRequested)'),
    );
    expect(gradle, isNot(contains('gradle.startParameter')));
    expect(gradle, isNot(contains('releaseBuildRequested')));
    expect(gradle, contains("missingKeys.add('ADMOB_ANDROID_APP_ID')"));
    expect(gradle, contains("missingKeys.add('ADMOB_POST_ACTIVITY_UNIT_ID')"));
    expect(gradle, contains('usesGoogleSampleId'));
    expect(gradle, contains('appPublisher != unitPublisher'));
    expect(
      gradle,
      contains('throw new GradleException(adsConfigurationError)'),
    );
    expect(
      gradle,
      contains(
        'manifestPlaceholders += [admobApplicationId: googleSampleAppId]',
      ),
    );
    expect(
      gradle,
      contains(
        'manifestPlaceholders += [admobApplicationId: releaseAdmobAppId]',
      ),
    );
    expect(
      gradle,
      contains('productionAdsRequested && adsConfigurationError == null'),
    );
  });
}

Iterable<File> _filesUnder(String path, Set<String> allowedSuffixes) {
  final directory = Directory(path);
  if (!directory.existsSync()) return const <File>[];
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => allowedSuffixes.any(file.path.endsWith));
}
