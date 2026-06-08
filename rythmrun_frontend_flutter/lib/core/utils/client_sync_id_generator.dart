import 'dart:math';

final class ClientSyncIdGenerator {
  ClientSyncIdGenerator._();

  static final Random _random = Random.secure();

  static String generate({DateTime? startTime, int? userId}) {
    final timestamp = (startTime ?? DateTime.now()).microsecondsSinceEpoch;
    final timestampHex = timestamp.toRadixString(16).padLeft(16, '0');
    final userHex = _segmentFromInt(userId ?? _random.nextInt(0x10000), 4);

    return 'rr-'
        '${timestampHex.substring(0, 8)}-'
        '${timestampHex.substring(8, 12)}-'
        '$userHex-'
        '${_randomHex(4)}-'
        '${_randomHex(12)}';
  }

  static String legacyFromLocalRow({
    required int localWorkoutId,
    required int userId,
    DateTime? startTime,
  }) {
    final timestamp =
        (startTime ?? DateTime.fromMillisecondsSinceEpoch(0))
            .microsecondsSinceEpoch;

    return 'rr-legacy-'
        '${_segmentFromInt(userId, 4)}-'
        '${_segmentFromInt(localWorkoutId, 8)}-'
        '${timestamp.toRadixString(16)}';
  }

  static String _segmentFromInt(int value, int width) {
    return value.toRadixString(16).padLeft(width, '0').substring(0, width);
  }

  static String _randomHex(int length) {
    final buffer = StringBuffer();

    while (buffer.length < length) {
      buffer.write(
        _random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
      );
    }

    return buffer.toString().substring(0, length);
  }
}
