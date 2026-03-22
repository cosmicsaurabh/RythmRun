import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/screens/calculator_option_card.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/screens/fitness_calculator_screen.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

class FitnessToolsScreen extends StatelessWidget {
  const FitnessToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CustomAppColors.surfaceBackgroundLight,
      appBar: AppBar(
        title: const Text(
          'Fitness Tools',
          style: TextStyle(
            color: CustomAppColors.primaryTextLight,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: CustomAppColors.surfaceBackgroundLight,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calculators',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: CustomAppColors.primaryTextLight,
              ),
            ),
            const SizedBox(height: spacingLg),
            CalculatorOptionCard(
              title: 'All-in-One Calculator',
              description:
                  'Get a comprehensive health overview including BMI, BMR, TDEE, and more.',
              icon: Icons.analytics_outlined,
              color: CustomAppColors.colorA,
              onTap: () => _navigateToCalculator(context, CalculatorType.all),
            ),
            const SizedBox(height: spacingMd),
            CalculatorOptionCard(
              title: 'BMI Calculator',
              description:
                  'Calculate your Body Mass Index to check if you are in a healthy weight range.',
              icon: Icons.monitor_weight_outlined,
              color: CustomAppColors.statusInfo,
              onTap: () => _navigateToCalculator(context, CalculatorType.bmi),
            ),
            const SizedBox(height: spacingMd),
            CalculatorOptionCard(
              title: 'BMR Calculator',
              description:
                  'Find out your Basal Metabolic Rate - calories you burn at rest.',
              icon: Icons.local_fire_department_outlined,
              color: CustomAppColors.statusWarning,
              onTap: () => _navigateToCalculator(context, CalculatorType.bmr),
            ),
            const SizedBox(height: spacingMd),
            CalculatorOptionCard(
              title: 'TDEE Calculator',
              description:
                  'Total Daily Energy Expenditure - calories needed to maintain weight.',
              icon: Icons.directions_run,
              color: CustomAppColors.statusSuccess,
              onTap: () => _navigateToCalculator(context, CalculatorType.tdee),
            ),
            const SizedBox(height: spacingMd),
            CalculatorOptionCard(
              title: 'Heart Rate Zones',
              description:
                  'Calculate your maximum heart rate and training zones.',
              icon: Icons.favorite_outline,
              color: CustomAppColors.statusDanger,
              onTap:
                  () =>
                      _navigateToCalculator(context, CalculatorType.heartRate),
            ),
            const SizedBox(height: spacingMd),
            CalculatorOptionCard(
              title: 'Healthy Weight',
              description: 'Discover the ideal weight range for your height.',
              icon: Icons.accessibility_new_outlined,
              color: CustomAppColors.colorB,
              onTap:
                  () => _navigateToCalculator(
                    context,
                    CalculatorType.healthyWeight,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToCalculator(BuildContext context, CalculatorType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FitnessCalculatorScreen(initialType: type),
      ),
    );
  }
}
