import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/utils/calculator_logic.dart';

final calculatorProvider =
    StateNotifierProvider<CalculatorNotifier, CalculatorData>((ref) {
      return CalculatorNotifier();
    });

class CalculatorNotifier extends StateNotifier<CalculatorData> {
  CalculatorNotifier() : super(CalculatorData());

  void updateData({
    int? age,
    double? heightCm,
    double? weightKg,
    bool? isMale,
    ActivityLevel? activityLevel,
  }) {
    state = state.copyWith(
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      isMale: isMale,
      activityLevel: activityLevel,
    );
  }

  void calculate() {
    state = state.copyWith(hasCalculated: true);
  }

  void reset() {
    state = CalculatorData();
  }
}

class CalculatorData {
  final int? age;
  final double? heightCm;
  final double? weightKg;
  final bool isMale;
  final ActivityLevel activityLevel;
  final bool hasCalculated;

  CalculatorData({
    this.age,
    this.heightCm,
    this.weightKg,
    this.isMale = true,
    this.activityLevel = ActivityLevel.moderatelyActive,
    this.hasCalculated = false,
  });

  CalculatorData copyWith({
    int? age,
    double? heightCm,
    double? weightKg,
    bool? isMale,
    ActivityLevel? activityLevel,
    bool? hasCalculated,
  }) {
    return CalculatorData(
      age: age ?? this.age,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      isMale: isMale ?? this.isMale,
      activityLevel: activityLevel ?? this.activityLevel,
      hasCalculated: hasCalculated ?? this.hasCalculated,
    );
  }
}
