class EnsureTypeHelper {
  static double formatAndEnsureDouble(dynamic value, {int uptoDecimal = 2}) {
    double parsedValue;
    if (value is double) {
      parsedValue = value;
    } else if (value is int) {
      parsedValue = value.toDouble();
    } else if (value is String) {
      parsedValue = double.tryParse(value) ?? 0.0;
    } else {
      parsedValue = 0.0;
    }
    return double.parse(parsedValue.toStringAsFixed(uptoDecimal));
  }

  static int ensureInt(dynamic value, {int radix = 10}) {
    if (value is double) {
      return int.parse(value.toStringAsFixed(0));
    } else if (value is int) {
      return value;
    } else if (value is String) {
      return int.tryParse(value, radix: radix) ?? 0;
    }
    return 0;
  }

  static bool ensureBool(dynamic value) {
    if (value is bool) {
      return value;
    } else if (value is String) {
      return value.toLowerCase() == "true" ||
          value.toLowerCase() == "yes" ||
          value.toLowerCase() == "t" ||
          value == "1";
    } else if (value is num) {
      return value != 0;
    }
    return false;
  }
}
