import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/profile_stat_card.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/providers/calculator_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/screens/fitness_calculator_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/utils/calculator_logic.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class CalculatorResultsWidget extends ConsumerWidget {
  final CalculatorType type;

  const CalculatorResultsWidget({super.key, this.type = CalculatorType.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calculatorProvider);

    // Basic validation to ensure we have data before calculating
    // Note: The form validation in the parent screen handles most of this,
    // but we check here to be safe and avoid null errors.
    if (state.heightCm == null &&
        (type == CalculatorType.bmi || type == CalculatorType.healthyWeight)) {
      return const SizedBox.shrink();
    }

    // Calculate values based on available data
    double? bmi;
    String? bmiCategory;
    double? bmr;
    double? tdee;
    String? healthyWeightRange;
    Map<String, String>? heartRateZones;
    int? maxHeartRate;

    if (state.weightKg != null && state.heightCm != null) {
      bmi = CalculatorLogic.calculateBMI(state.weightKg!, state.heightCm!);
      bmiCategory = CalculatorLogic.getBMICategory(bmi);
    }

    if (state.weightKg != null && state.heightCm != null && state.age != null) {
      bmr = CalculatorLogic.calculateBMR(
        weightKg: state.weightKg!,
        heightCm: state.heightCm!,
        age: state.age!,
        isMale: state.isMale,
      );
      tdee = CalculatorLogic.calculateTDEE(bmr, state.activityLevel);
    }

    if (state.heightCm != null) {
      healthyWeightRange = CalculatorLogic.calculateHealthyWeightRange(
        state.heightCm!,
      );
    }

    if (state.age != null) {
      maxHeartRate = CalculatorLogic.calculateMaxHeartRate(state.age!);
      heartRateZones = CalculatorLogic.getHeartRateZones(state.age!);
    }

    final showBMI =
        (type == CalculatorType.all || type == CalculatorType.bmi) &&
        bmi != null;
    final showBMR =
        (type == CalculatorType.all || type == CalculatorType.bmr) &&
        bmr != null;
    final showTDEE =
        (type == CalculatorType.all || type == CalculatorType.tdee) &&
        tdee != null;
    final showHealthyWeight =
        (type == CalculatorType.all || type == CalculatorType.healthyWeight) &&
        healthyWeightRange != null;
    final showHeartRate =
        (type == CalculatorType.all || type == CalculatorType.heartRate) &&
        heartRateZones != null;

    return Column(
      children: [
        if (showBMI) ...[
          _buildEnhancedResultCard(
            context,
            title: 'BMI Score',
            value: bmi!.toStringAsFixed(1),
            subtitle: bmiCategory ?? '',
            color: _getBMIColor(bmi),
            icon: Icons.monitor_weight_outlined,
            content: _buildBMIScale(bmi),
          ),
          const SizedBox(height: spacingMd),
        ],

        if (showBMR || showTDEE) ...[
          Row(
            children: [
              if (showBMR)
                Expanded(
                  child: ProfileStatCard(
                    title: 'BMR (Calories/day)',
                    value: bmr!.round().toString(),
                    icon: Icons.local_fire_department_outlined,
                    color: CustomAppColors.colorA,
                  ),
                ),
              if (showBMR && showTDEE) const SizedBox(width: spacingMd),
              if (showTDEE)
                Expanded(
                  child: ProfileStatCard(
                    title: 'TDEE (Maintenance)',
                    value: tdee!.round().toString(),
                    icon: Icons.directions_run,
                    color: CustomAppColors.colorB,
                  ),
                ),
            ],
          ),
          const SizedBox(height: spacingMd),
        ],

        if (showHealthyWeight) ...[
          ProfileStatCard(
            title: 'Healthy Weight Range',
            value: healthyWeightRange!,
            icon: Icons.accessibility_new,
            color: CustomAppColors.statusSuccess,
          ),
          const SizedBox(height: spacingMd),
        ],

        if (showHeartRate) ...[
          _buildEnhancedResultCard(
            context,
            title: 'Heart Rate Zones',
            value: '$maxHeartRate bpm',
            subtitle: 'Max Heart Rate',
            color: CustomAppColors.colorC,
            icon: Icons.favorite,
            content: Column(
              children:
                  heartRateZones!.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              color: CustomAppColors.secondaryText,
                            ),
                          ),
                          Text(
                            entry.value,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Color _getBMIColor(double bmi) {
    if (bmi < 18.5) return CustomAppColors.statusInfo;
    if (bmi < 25) return CustomAppColors.statusSuccess;
    if (bmi < 30) return CustomAppColors.statusWarning;
    return CustomAppColors.statusDanger;
  }

  // Custom enhanced card for complex results like BMI and Heart Rate
  // Reuses the style of ProfileStatCard but allows custom content
  Widget _buildEnhancedResultCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    Widget? content,
  }) {
    return Container(
      padding: const EdgeInsets.all(spacingLg),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(spacingSm),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color.withOpacity(0.2), color.withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(radiusSm),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
            ],
          ),
          const SizedBox(height: spacingSm),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 24,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: CustomAppColors.secondaryText,
            ),
          ),
          if (content != null) ...[
            const SizedBox(height: spacingMd),
            const Divider(),
            const SizedBox(height: spacingSm),
            content,
          ],
        ],
      ),
    );
  }

  Widget _buildBMIScale(double bmi) {
    return Column(
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(
              colors: [
                CustomAppColors.statusInfo,
                CustomAppColors.statusSuccess,
                CustomAppColors.statusWarning,
                CustomAppColors.statusDanger,
              ],
              stops: [0.185, 0.25, 0.30, 1.0],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              '18.5',
              style: TextStyle(
                fontSize: 10,
                color: CustomAppColors.secondaryText,
              ),
            ),
            Text(
              '25',
              style: TextStyle(
                fontSize: 10,
                color: CustomAppColors.secondaryText,
              ),
            ),
            Text(
              '30',
              style: TextStyle(
                fontSize: 10,
                color: CustomAppColors.secondaryText,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
