import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

const analyzerBaselineSchemaVersion = 1;

void main(List<String> arguments) {
  try {
    exitCode = runAnalyzerBaselineCli(arguments);
  } on FormatException catch (error) {
    stderr.writeln('Analyzer baseline error: ${error.message}');
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('Analyzer baseline file error: ${error.message}');
    exitCode = 66;
  }
}

int runAnalyzerBaselineCli(List<String> arguments) {
  if (arguments.isEmpty ||
      !const {'check', 'render'}.contains(arguments.first)) {
    throw const FormatException(
      'Usage: analyzer_baseline.dart <check|render> --input <file> '
      '--repository-root <directory> --package-root <directory> '
      '[--baseline <file>]',
    );
  }

  final command = arguments.first;
  final options = _parseOptions(arguments.skip(1).toList());
  final allowedOptions =
      command == 'check'
          ? const {'input', 'baseline', 'repository-root', 'package-root'}
          : const {'input', 'repository-root', 'package-root'};
  final unknownOptions = options.keys.toSet().difference(allowedOptions);
  if (unknownOptions.isNotEmpty) {
    throw FormatException(
      'Unknown option(s): ${unknownOptions.map((name) => '--$name').join(', ')}',
    );
  }

  final inputPath = _requiredOption(options, 'input');
  final repositoryRoot = _requiredOption(options, 'repository-root');
  final packageRoot = _requiredOption(options, 'package-root');
  final report = parseAnalyzerMachineOutput(
    File(inputPath).readAsStringSync(),
    repositoryRoot: repositoryRoot,
    packageRoot: packageRoot,
  );

  if (command == 'render') {
    _rejectFatalDiagnostics(report);
    final baseline = AnalyzerBaseline.fromReport(
      report,
      flutterVersion: _readFlutterVersion(packageRoot),
      dartVersion: currentDartVersion,
    );
    stdout.write(baseline.toPrettyJson());
    return 0;
  }

  final baselinePath = _requiredOption(options, 'baseline');
  final baseline = AnalyzerBaseline.fromJson(
    jsonDecode(File(baselinePath).readAsStringSync()),
  );
  _verifyToolchain(baseline, packageRoot);
  _rejectFatalDiagnostics(report);

  final comparison = compareAnalyzerBaseline(baseline, report);
  if (comparison.additions.isNotEmpty) {
    stderr.writeln(
      'Analyzer baseline rejected ${comparison.additionCount} new '
      'informational finding(s):',
    );
    for (final addition in comparison.additions) {
      stderr.writeln('  +${addition.count} ${addition.entry.description}');
    }
    return 1;
  }

  stdout.writeln(
    'Analyzer baseline accepted ${report.informationCount} informational '
    'finding(s); ${comparison.removalCount} baseline finding(s) were removed.',
  );
  return 0;
}

String get currentDartVersion => Platform.version.split(' ').first;

class AnalyzerFinding {
  const AnalyzerFinding({
    required this.severity,
    required this.code,
    required this.repositoryPath,
    required this.message,
    required this.messageSha256,
    required this.line,
    required this.column,
  });

  final String severity;
  final String code;
  final String repositoryPath;
  final String message;
  final String messageSha256;
  final int line;
  final int column;

  AnalyzerBaselineEntry get baselineEntry => AnalyzerBaselineEntry(
    code: code,
    repositoryPath: repositoryPath,
    messageSha256: messageSha256,
  );
}

class AnalyzerReport {
  const AnalyzerReport(this.findings);

  final List<AnalyzerFinding> findings;

  Iterable<AnalyzerFinding> get informationFindings =>
      findings.where((finding) => finding.severity == 'INFO');

  Iterable<AnalyzerFinding> get fatalFindings =>
      findings.where((finding) => finding.severity != 'INFO');

  int get informationCount => informationFindings.length;

  Map<String, AnalyzerBaselineCount> get informationCounts {
    final counts = <String, AnalyzerBaselineCount>{};
    for (final finding in informationFindings) {
      final entry = finding.baselineEntry;
      final existing = counts[entry.key];
      counts[entry.key] = AnalyzerBaselineCount(
        entry: entry,
        count: (existing?.count ?? 0) + 1,
      );
    }
    return counts;
  }
}

class AnalyzerBaselineEntry {
  const AnalyzerBaselineEntry({
    required this.code,
    required this.repositoryPath,
    required this.messageSha256,
  });

  final String code;
  final String repositoryPath;
  final String messageSha256;

  String get key => '$code\u0000$repositoryPath\u0000$messageSha256';

  String get description => '$code $repositoryPath [$messageSha256]';
}

class AnalyzerBaselineCount {
  const AnalyzerBaselineCount({required this.entry, required this.count});

  final AnalyzerBaselineEntry entry;
  final int count;
}

class AnalyzerBaseline {
  AnalyzerBaseline({
    required this.flutterVersion,
    required this.dartVersion,
    required Iterable<AnalyzerBaselineCount> findings,
  }) : findings = List.unmodifiable(_sortedCounts(findings));

  factory AnalyzerBaseline.fromReport(
    AnalyzerReport report, {
    required String flutterVersion,
    required String dartVersion,
  }) {
    return AnalyzerBaseline(
      flutterVersion: flutterVersion,
      dartVersion: dartVersion,
      findings: report.informationCounts.values,
    );
  }

  factory AnalyzerBaseline.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Baseline root must be a JSON object.');
    }
    if (value['schemaVersion'] != analyzerBaselineSchemaVersion) {
      throw FormatException(
        'Unsupported baseline schemaVersion: ${value['schemaVersion']}.',
      );
    }

    final toolchain = value['toolchain'];
    if (toolchain is! Map<String, dynamic>) {
      throw const FormatException('Baseline toolchain must be a JSON object.');
    }
    final flutterVersion = _nonEmptyString(
      toolchain['flutter'],
      'toolchain.flutter',
    );
    final dartVersion = _nonEmptyString(toolchain['dart'], 'toolchain.dart');

    final rawFindings = value['findings'];
    if (rawFindings is! List) {
      throw const FormatException('Baseline findings must be a JSON array.');
    }

    final findings = <AnalyzerBaselineCount>[];
    final keys = <String>{};
    String? previousKey;
    for (var index = 0; index < rawFindings.length; index++) {
      final rawFinding = rawFindings[index];
      if (rawFinding is! Map<String, dynamic>) {
        throw FormatException('Baseline finding $index must be an object.');
      }
      final code = _nonEmptyString(rawFinding['code'], 'findings[$index].code');
      final repositoryPath = _nonEmptyString(
        rawFinding['path'],
        'findings[$index].path',
      );
      final messageSha256 = _nonEmptyString(
        rawFinding['messageSha256'],
        'findings[$index].messageSha256',
      );
      final count = rawFinding['count'];
      final portableRepositoryPath = repositoryPath.replaceAll('\\', '/');
      final normalizedRepositoryPath = path.posix.normalize(
        portableRepositoryPath,
      );

      if (!RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(code)) {
        throw FormatException('Invalid analyzer code at findings[$index].');
      }
      if (path.posix.isAbsolute(portableRepositoryPath) ||
          normalizedRepositoryPath == '..' ||
          normalizedRepositoryPath.startsWith('../') ||
          normalizedRepositoryPath != portableRepositoryPath) {
        throw FormatException(
          'Baseline path must be normalized and repository-relative at '
          'findings[$index].',
        );
      }
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(messageSha256)) {
        throw FormatException(
          'Invalid SHA-256 fingerprint at findings[$index].',
        );
      }
      if (count is! int || count <= 0) {
        throw FormatException('Invalid count at findings[$index].');
      }

      final entry = AnalyzerBaselineEntry(
        code: code,
        repositoryPath: portableRepositoryPath,
        messageSha256: messageSha256,
      );
      if (!keys.add(entry.key)) {
        throw FormatException(
          'Duplicate baseline finding: ${entry.description}.',
        );
      }
      if (previousKey != null && previousKey.compareTo(entry.key) > 0) {
        throw const FormatException(
          'Baseline findings must be sorted by code, path, and fingerprint.',
        );
      }
      previousKey = entry.key;
      findings.add(AnalyzerBaselineCount(entry: entry, count: count));
    }

    return AnalyzerBaseline(
      flutterVersion: flutterVersion,
      dartVersion: dartVersion,
      findings: findings,
    );
  }

  final String flutterVersion;
  final String dartVersion;
  final List<AnalyzerBaselineCount> findings;

  Map<String, AnalyzerBaselineCount> get findingsByKey => {
    for (final finding in findings) finding.entry.key: finding,
  };

  int get findingCount =>
      findings.fold(0, (sum, finding) => sum + finding.count);

  String toPrettyJson() {
    final value = <String, Object>{
      'schemaVersion': analyzerBaselineSchemaVersion,
      'toolchain': <String, String>{
        'flutter': flutterVersion,
        'dart': dartVersion,
      },
      'findings': [
        for (final finding in findings)
          <String, Object>{
            'code': finding.entry.code,
            'path': finding.entry.repositoryPath,
            'messageSha256': finding.entry.messageSha256,
            'count': finding.count,
          },
      ],
    };
    return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
  }
}

class AnalyzerBaselineComparison {
  const AnalyzerBaselineComparison({
    required this.additions,
    required this.removals,
  });

  final List<AnalyzerBaselineCount> additions;
  final List<AnalyzerBaselineCount> removals;

  int get additionCount => additions.fold(0, (sum, item) => sum + item.count);
  int get removalCount => removals.fold(0, (sum, item) => sum + item.count);
}

AnalyzerReport parseAnalyzerMachineOutput(
  String output, {
  required String repositoryRoot,
  required String packageRoot,
}) {
  final normalizedRepositoryRoot = path.normalize(
    path.absolute(repositoryRoot),
  );
  final normalizedPackageRoot = path.normalize(path.absolute(packageRoot));
  if (normalizedPackageRoot != normalizedRepositoryRoot &&
      !path.isWithin(normalizedRepositoryRoot, normalizedPackageRoot)) {
    throw const FormatException('Package root must be inside repository root.');
  }

  final findings = <AnalyzerFinding>[];
  final lines = const LineSplitter().convert(output);
  for (var index = 0; index < lines.length; index++) {
    final rawLine = lines[index];
    if (rawLine.trim().isEmpty) {
      continue;
    }
    final fields = _splitMachineLine(rawLine);
    if (fields.length != 8) {
      throw FormatException(
        'Malformed analyzer record on input line ${index + 1}: '
        'expected 8 fields, found ${fields.length}.',
      );
    }

    final severity = fields[0].toUpperCase();
    if (!const {'INFO', 'WARNING', 'ERROR'}.contains(severity)) {
      throw FormatException(
        'Unsupported analyzer severity on input line ${index + 1}: '
        '${fields[0]}.',
      );
    }
    if (!RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(fields[1])) {
      throw FormatException(
        'Invalid analyzer type on input line ${index + 1}: ${fields[1]}.',
      );
    }
    final code = fields[2].toUpperCase();
    if (!RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(code)) {
      throw FormatException(
        'Invalid analyzer code on input line ${index + 1}: ${fields[2]}.',
      );
    }
    final line = int.tryParse(fields[4]);
    final column = int.tryParse(fields[5]);
    final length = int.tryParse(fields[6]);
    if (line == null ||
        line < 1 ||
        column == null ||
        column < 1 ||
        length == null ||
        length < 0) {
      throw FormatException(
        'Invalid analyzer position on input line ${index + 1}.',
      );
    }

    final rawFilePath = fields[3];
    final absoluteFilePath = path.normalize(
      path.isAbsolute(rawFilePath)
          ? rawFilePath
          : path.join(normalizedPackageRoot, rawFilePath),
    );
    if (absoluteFilePath != normalizedPackageRoot &&
        !path.isWithin(normalizedPackageRoot, absoluteFilePath)) {
      throw FormatException(
        'Analyzer path escapes the package on input line ${index + 1}: '
        '$rawFilePath.',
      );
    }
    final repositoryPath = path
        .relative(absoluteFilePath, from: normalizedRepositoryRoot)
        .replaceAll('\\', '/');
    final message = fields[7].trim().replaceAll(RegExp(r'\s+'), ' ');
    if (message.isEmpty) {
      throw FormatException(
        'Analyzer message is empty on input line ${index + 1}.',
      );
    }

    findings.add(
      AnalyzerFinding(
        severity: severity,
        code: code,
        repositoryPath: repositoryPath,
        message: message,
        messageSha256: sha256.convert(utf8.encode(message)).toString(),
        line: line,
        column: column,
      ),
    );
  }
  return AnalyzerReport(List.unmodifiable(findings));
}

AnalyzerBaselineComparison compareAnalyzerBaseline(
  AnalyzerBaseline baseline,
  AnalyzerReport report,
) {
  final expected = baseline.findingsByKey;
  final actual = report.informationCounts;
  final additions = <AnalyzerBaselineCount>[];
  final removals = <AnalyzerBaselineCount>[];

  for (final current in actual.values) {
    final allowedCount = expected[current.entry.key]?.count ?? 0;
    if (current.count > allowedCount) {
      additions.add(
        AnalyzerBaselineCount(
          entry: current.entry,
          count: current.count - allowedCount,
        ),
      );
    }
  }
  for (final prior in expected.values) {
    final currentCount = actual[prior.entry.key]?.count ?? 0;
    if (prior.count > currentCount) {
      removals.add(
        AnalyzerBaselineCount(
          entry: prior.entry,
          count: prior.count - currentCount,
        ),
      );
    }
  }

  return AnalyzerBaselineComparison(
    additions: List.unmodifiable(_sortedCounts(additions)),
    removals: List.unmodifiable(_sortedCounts(removals)),
  );
}

List<String> _splitMachineLine(String line) {
  final fields = <String>[];
  final field = StringBuffer();
  var escaped = false;
  for (final rune in line.runes) {
    final character = String.fromCharCode(rune);
    if (escaped) {
      if (character == '|' || character == '\\') {
        field.write(character);
      } else {
        field
          ..write('\\')
          ..write(character);
      }
      escaped = false;
    } else if (character == '\\') {
      escaped = true;
    } else if (character == '|') {
      fields.add(field.toString());
      field.clear();
    } else {
      field.write(character);
    }
  }
  if (escaped) {
    throw const FormatException(
      'Analyzer record ends with an escape character.',
    );
  }
  fields.add(field.toString());
  return fields;
}

List<AnalyzerBaselineCount> _sortedCounts(
  Iterable<AnalyzerBaselineCount> values,
) {
  return values.toList()
    ..sort((left, right) => left.entry.key.compareTo(right.entry.key));
}

Map<String, String> _parseOptions(List<String> arguments) {
  if (arguments.length.isOdd) {
    throw const FormatException('Every option must have a value.');
  }
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final option = arguments[index];
    if (!option.startsWith('--') || option.length == 2) {
      throw FormatException('Invalid option: $option.');
    }
    final name = option.substring(2);
    if (options.containsKey(name)) {
      throw FormatException('Duplicate option: $option.');
    }
    options[name] = arguments[index + 1];
  }
  return options;
}

String _requiredOption(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required option: --$name.');
  }
  return value;
}

String _nonEmptyString(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName must be a non-empty string.');
  }
  return value;
}

String _readFlutterVersion(String packageRoot) {
  final version =
      File(
        path.join(packageRoot, '.flutter-version'),
      ).readAsStringSync().trim();
  if (version.isEmpty) {
    throw const FormatException('.flutter-version must not be empty.');
  }
  return version;
}

void _verifyToolchain(AnalyzerBaseline baseline, String packageRoot) {
  final pinnedFlutterVersion = _readFlutterVersion(packageRoot);
  if (baseline.flutterVersion != pinnedFlutterVersion) {
    throw FormatException(
      'Baseline Flutter ${baseline.flutterVersion} does not match '
      '.flutter-version $pinnedFlutterVersion.',
    );
  }
  if (baseline.dartVersion != currentDartVersion) {
    throw FormatException(
      'Baseline Dart ${baseline.dartVersion} does not match the running Dart '
      '$currentDartVersion.',
    );
  }

  final normalizedPackageRoot = path.normalize(path.absolute(packageRoot));
  final repositoryRoot = path.dirname(normalizedPackageRoot);
  for (final finding in baseline.findings) {
    final absoluteFindingPath = path.normalize(
      path.join(repositoryRoot, finding.entry.repositoryPath),
    );
    if (!path.isWithin(normalizedPackageRoot, absoluteFindingPath)) {
      throw FormatException(
        'Baseline finding escapes the Flutter package: '
        '${finding.entry.repositoryPath}.',
      );
    }
  }
}

void _rejectFatalDiagnostics(AnalyzerReport report) {
  final fatalFindings = report.fatalFindings.toList();
  if (fatalFindings.isEmpty) {
    return;
  }
  for (final finding in fatalFindings) {
    stderr.writeln(
      '${finding.severity} ${finding.code} ${finding.repositoryPath}:'
      '${finding.line}:${finding.column} ${finding.message}',
    );
  }
  throw FormatException(
    'Analyzer emitted ${fatalFindings.length} warning/error finding(s).',
  );
}
