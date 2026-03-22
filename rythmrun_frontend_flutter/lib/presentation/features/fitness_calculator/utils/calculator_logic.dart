class CalculatorLogic {
  // BMI Calculator
  static double calculateBMI(double weightKg, double heightCm) {
    if (heightCm <= 0) return 0;
    double heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }

  static String getBMICategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal weight';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  // BMR Calculator (Mifflin-St Jeor Equation)
  static double calculateBMR({
    required double weightKg,
    required double heightCm,
    required int age,
    required bool isMale,
  }) {
    // BMR = 10W + 6.25H - 5A + S
    // S is +5 for men and -161 for women
    double s = isMale ? 5 : -161;
    return (10 * weightKg) + (6.25 * heightCm) - (5 * age) + s;
  }

  // Heart Rate Calculator
  static int calculateMaxHeartRate(int age) {
    return 220 - age;
  }

  static Map<String, String> getHeartRateZones(int age) {
    int maxHr = calculateMaxHeartRate(age);
    return {
      'Moderate (50-70%)':
          '${(maxHr * 0.5).round()} - ${(maxHr * 0.7).round()} bpm',
      'Vigorous (70-85%)':
          '${(maxHr * 0.7).round()} - ${(maxHr * 0.85).round()} bpm',
      'Maximum (85-100%)': '${(maxHr * 0.85).round()} - $maxHr bpm',
    };
  }

  // Healthy Weight Calculator (based on BMI 18.5 - 24.9)
  static String calculateHealthyWeightRange(double heightCm) {
    double heightM = heightCm / 100;
    double minWeight = 18.5 * (heightM * heightM);
    double maxWeight = 24.9 * (heightM * heightM);
    return '${minWeight.toStringAsFixed(1)} - ${maxWeight.toStringAsFixed(1)} kg';
  }

  // TDEE Calculator
  static double calculateTDEE(double bmr, ActivityLevel activityLevel) {
    switch (activityLevel) {
      case ActivityLevel.sedentary:
        return bmr * 1.2;
      case ActivityLevel.lightlyActive:
        return bmr * 1.375;
      case ActivityLevel.moderatelyActive:
        return bmr * 1.55;
      case ActivityLevel.veryActive:
        return bmr * 1.725;
      case ActivityLevel.extraActive:
        return bmr * 1.9;
    }
  }
}

enum ActivityLevel {
  sedentary, // Little or no exercise
  lightlyActive, // Light exercise/sports 1-3 days/week
  moderatelyActive, // Moderate exercise/sports 3-5 days/week
  veryActive, // Hard exercise/sports 6-7 days/week
  extraActive, // Very hard exercise/sports & physical job or 2x training
}

extension ActivityLevelExtension on ActivityLevel {
  String get displayName {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Sedentary (little or no exercise)';
      case ActivityLevel.lightlyActive:
        return 'Lightly active (1-3 days/week)';
      case ActivityLevel.moderatelyActive:
        return 'Moderately active (3-5 days/week)';
      case ActivityLevel.veryActive:
        return 'Very active (6-7 days/week)';
      case ActivityLevel.extraActive:
        return 'Extra active (physical job or 2x training)';
    }
  }
}
