import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../../tool/ci/analyzer_baseline.dart';

void main() {
  late String repositoryRoot;
  late String packageRoot;
  late String sourcePath;

  setUp(() {
    repositoryRoot = path.join(path.separator, 'work', 'repository');
    packageRoot = path.join(repositoryRoot, 'rythmrun_frontend_flutter');
    sourcePath = path.join(packageRoot, 'lib', 'example.dart');
  });

  AnalyzerReport parse(String output) => parseAnalyzerMachineOutput(
    output,
    repositoryRoot: repositoryRoot,
    packageRoot: packageRoot,
  );

  group('machine analyzer parsing', () {
    test('normalizes paths and messages without using source positions', () {
      final report = parse(
        '${record(sourcePath, line: 3, message: 'Message with| a separator')}'
        '\n${record(sourcePath, line: 91, message: 'Message  with| a separator')}\n',
      );

      expect(report.informationCount, 2);
      expect(report.informationCounts, hasLength(1));
      final finding = report.findings.first;
      expect(
        finding.repositoryPath,
        'rythmrun_frontend_flutter/lib/example.dart',
      );
      expect(finding.message, 'Message with| a separator');
      expect(report.informationCounts.values.single.count, 2);
    });

    test('retains warnings and errors as fatal diagnostics', () {
      final report = parse(
        '${record(sourcePath, severity: 'WARNING')}\n'
        '${record(sourcePath, severity: 'ERROR', code: 'COMPILE_ERROR')}\n',
      );

      expect(report.informationCount, 0);
      expect(report.fatalFindings, hasLength(2));
    });

    test('rejects malformed records and paths outside the package', () {
      expect(
        () => parse('INFO|LINT|A_CODE|too-few-fields'),
        throwsFormatException,
      );
      expect(
        () => parse(record(path.join(repositoryRoot, 'outside.dart'))),
        throwsFormatException,
      );
      expect(() => parse('${record(sourcePath)}\\'), throwsFormatException);
    });
  });

  group('baseline comparison', () {
    test('allows removals but rejects new keys and increased counts', () {
      final twoFindings = parse(
        '${record(sourcePath, line: 1)}\n${record(sourcePath, line: 2)}\n',
      );
      final baseline = AnalyzerBaseline.fromReport(
        twoFindings,
        flutterVersion: '3.44.1',
        dartVersion: currentDartVersion,
      );

      final removal = compareAnalyzerBaseline(
        baseline,
        parse('${record(sourcePath)}\n'),
      );
      expect(removal.additionCount, 0);
      expect(removal.removalCount, 1);

      final increase = compareAnalyzerBaseline(
        baseline,
        parse(
          '${record(sourcePath, line: 1)}\n'
          '${record(sourcePath, line: 2)}\n'
          '${record(sourcePath, line: 3)}\n',
        ),
      );
      expect(increase.additionCount, 1);

      final changedMessage = compareAnalyzerBaseline(
        baseline,
        parse('${record(sourcePath, message: 'Different message')}\n'),
      );
      expect(changedMessage.additionCount, 1);
      expect(changedMessage.removalCount, 2);
    });

    test('renders stable sorted JSON and round-trips it', () {
      final report = parse(
        '${record(sourcePath, code: 'Z_RULE')}\n'
        '${record(sourcePath, code: 'A_RULE')}\n',
      );
      final baseline = AnalyzerBaseline.fromReport(
        report,
        flutterVersion: '3.44.1',
        dartVersion: currentDartVersion,
      );
      final rendered = baseline.toPrettyJson();
      final parsed = AnalyzerBaseline.fromJson(jsonDecode(rendered));

      expect(parsed.findingCount, 2);
      expect(parsed.findings.first.entry.code, 'A_RULE');
      expect(parsed.toPrettyJson(), rendered);
    });

    test('rejects unsupported, duplicate, and unsorted baseline data', () {
      final hash = List.filled(64, 'a').join();
      Map<String, Object> baselineWith(List<Map<String, Object>> findings) => {
        'schemaVersion': analyzerBaselineSchemaVersion,
        'toolchain': {'flutter': '3.44.1', 'dart': currentDartVersion},
        'findings': findings,
      };
      Map<String, Object> finding(String code) => {
        'code': code,
        'path': 'rythmrun_frontend_flutter/lib/example.dart',
        'messageSha256': hash,
        'count': 1,
      };

      expect(
        () => AnalyzerBaseline.fromJson({
          'schemaVersion': 999,
          'toolchain': {'flutter': '3.44.1', 'dart': currentDartVersion},
          'findings': <Object>[],
        }),
        throwsFormatException,
      );
      expect(
        () => AnalyzerBaseline.fromJson(
          baselineWith([finding('A_RULE'), finding('A_RULE')]),
        ),
        throwsFormatException,
      );
      expect(
        () => AnalyzerBaseline.fromJson(
          baselineWith([finding('Z_RULE'), finding('A_RULE')]),
        ),
        throwsFormatException,
      );
      expect(
        () => AnalyzerBaseline.fromJson(
          baselineWith([
            {
              ...finding('A_RULE'),
              'path': 'rythmrun_frontend_flutter/lib/../outside.dart',
            },
          ]),
        ),
        throwsFormatException,
      );
    });
  });

  test('CLI rejects warning diagnostics even if the baseline is empty', () {
    final temporaryRoot = Directory.systemTemp.createTempSync(
      'analyzer-baseline-test-',
    );
    addTearDown(() => temporaryRoot.deleteSync(recursive: true));
    final temporaryPackage = Directory(
      path.join(temporaryRoot.path, 'rythmrun_frontend_flutter'),
    )..createSync();
    File(
      path.join(temporaryPackage.path, '.flutter-version'),
    ).writeAsStringSync('3.44.1\n');
    final input = File(
      path.join(temporaryRoot.path, 'analyzer.machine'),
    )..writeAsStringSync(
      '${record(path.join(temporaryPackage.path, 'lib', 'file.dart'), severity: 'WARNING')}\n',
    );
    final baseline = File(path.join(temporaryRoot.path, 'baseline.json'))
      ..writeAsStringSync(
        AnalyzerBaseline(
          flutterVersion: '3.44.1',
          dartVersion: currentDartVersion,
          findings: const [],
        ).toPrettyJson(),
      );

    expect(
      () => runAnalyzerBaselineCli([
        'check',
        '--input',
        input.path,
        '--baseline',
        baseline.path,
        '--repository-root',
        temporaryRoot.path,
        '--package-root',
        temporaryPackage.path,
      ]),
      throwsFormatException,
    );
  });

  test('CLI allows removal and rejects an increased informational count', () {
    final temporaryRoot = Directory.systemTemp.createTempSync(
      'analyzer-baseline-count-test-',
    );
    addTearDown(() => temporaryRoot.deleteSync(recursive: true));
    final temporaryPackage = Directory(
      path.join(temporaryRoot.path, 'rythmrun_frontend_flutter'),
    )..createSync();
    File(
      path.join(temporaryPackage.path, '.flutter-version'),
    ).writeAsStringSync('3.44.1\n');
    final temporarySource = path.join(
      temporaryPackage.path,
      'lib',
      'file.dart',
    );
    final baselineReport = parseAnalyzerMachineOutput(
      '${record(temporarySource, line: 1)}\n'
      '${record(temporarySource, line: 2)}\n',
      repositoryRoot: temporaryRoot.path,
      packageRoot: temporaryPackage.path,
    );
    final baseline = File(path.join(temporaryRoot.path, 'baseline.json'))
      ..writeAsStringSync(
        AnalyzerBaseline.fromReport(
          baselineReport,
          flutterVersion: '3.44.1',
          dartVersion: currentDartVersion,
        ).toPrettyJson(),
      );
    final input = File(path.join(temporaryRoot.path, 'analyzer.machine'));

    input.writeAsStringSync('${record(temporarySource)}\n');
    expect(
      runAnalyzerBaselineCli(cliArguments(temporaryRoot, input, baseline)),
      0,
    );

    input.writeAsStringSync(
      '${record(temporarySource, line: 1)}\n'
      '${record(temporarySource, line: 2)}\n'
      '${record(temporarySource, line: 3)}\n',
    );
    expect(
      runAnalyzerBaselineCli(cliArguments(temporaryRoot, input, baseline)),
      1,
    );
  });
}

List<String> cliArguments(
  Directory repositoryRoot,
  File input,
  File baseline,
) => [
  'check',
  '--input',
  input.path,
  '--baseline',
  baseline.path,
  '--repository-root',
  repositoryRoot.path,
  '--package-root',
  path.join(repositoryRoot.path, 'rythmrun_frontend_flutter'),
];

String record(
  String filePath, {
  String severity = 'INFO',
  String code = 'A_RULE',
  int line = 1,
  String message = 'A message',
}) {
  final escapedPath = filePath.replaceAll('\\', r'\\');
  final escapedMessage = message.replaceAll('\\', r'\\').replaceAll('|', r'\|');
  return '$severity|LINT|$code|$escapedPath|$line|1|1|$escapedMessage';
}
