import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/providers/calculator_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/screens/calculator_results_widget.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/fitness_calculator/utils/calculator_logic.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

enum CalculatorType { all, bmi, bmr, tdee, heartRate, healthyWeight }

class FitnessCalculatorScreen extends ConsumerStatefulWidget {
  final CalculatorType initialType;

  const FitnessCalculatorScreen({
    super.key,
    this.initialType = CalculatorType.all,
  });

  @override
  ConsumerState<FitnessCalculatorScreen> createState() =>
      _FitnessCalculatorScreenState();
}

class _FitnessCalculatorScreenState
    extends ConsumerState<FitnessCalculatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  late CalculatorType _currentType;

  @override
  void initState() {
    super.initState();
    _currentType = widget.initialType;
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  String get _title {
    switch (_currentType) {
      case CalculatorType.all:
        return 'All-in-One Calculator';
      case CalculatorType.bmi:
        return 'BMI Calculator';
      case CalculatorType.bmr:
        return 'BMR Calculator';
      case CalculatorType.tdee:
        return 'TDEE Calculator';
      case CalculatorType.heartRate:
        return 'Heart Rate Zones';
      case CalculatorType.healthyWeight:
        return 'Healthy Weight';
    }
  }

  @override
  Widget build(BuildContext context) {
    final calculatorState = ref.watch(calculatorProvider);
    final notifier = ref.read(calculatorProvider.notifier);

    return Scaffold(
      backgroundColor: CustomAppColors.surfaceBackgroundLight,
      appBar: AppBar(
        title: Text(
          _title,
          style: const TextStyle(
            color: CustomAppColors.primaryTextLight,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: CustomAppColors.surfaceBackgroundLight,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: CustomAppColors.primaryTextLight,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInputCard(context, calculatorState, notifier),
            const SizedBox(height: spacingLg),
            if (calculatorState.hasCalculated)
              CalculatorResultsWidget(type: _currentType),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard(
    BuildContext context,
    CalculatorData state,
    CalculatorNotifier notifier,
  ) {
    // Determine visibility based on type
    final showAge =
        _currentType == CalculatorType.all ||
        _currentType == CalculatorType.bmr ||
        _currentType == CalculatorType.tdee ||
        _currentType == CalculatorType.heartRate;

    final showHeight =
        _currentType == CalculatorType.all ||
        _currentType == CalculatorType.bmi ||
        _currentType == CalculatorType.bmr ||
        _currentType == CalculatorType.tdee ||
        _currentType == CalculatorType.healthyWeight;

    final showWeight =
        _currentType == CalculatorType.all ||
        _currentType == CalculatorType.bmi ||
        _currentType == CalculatorType.bmr ||
        _currentType == CalculatorType.tdee;

    final showGender =
        _currentType == CalculatorType.all ||
        _currentType == CalculatorType.bmr ||
        _currentType == CalculatorType.tdee;

    final showActivity =
        _currentType == CalculatorType.all ||
        _currentType == CalculatorType.tdee;

    return Container(
      padding: const EdgeInsets.all(spacingLg),
      decoration: BoxDecoration(
        color: CustomAppColors.surfaceCardLight,
        borderRadius: BorderRadius.circular(radiusLg),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Stats',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: CustomAppColors.primaryTextLight,
              ),
            ),
            const SizedBox(height: spacingLg),

            if (showGender) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildGenderButton(
                      context,
                      'Male',
                      Icons.male,
                      state.isMale,
                      () => notifier.updateData(isMale: true),
                    ),
                  ),
                  const SizedBox(width: spacingMd),
                  Expanded(
                    child: _buildGenderButton(
                      context,
                      'Female',
                      Icons.female,
                      !state.isMale,
                      () => notifier.updateData(isMale: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: spacingLg),
            ],

            Row(
              children: [
                if (showAge)
                  Expanded(
                    child: _buildNumberInput(
                      controller: _ageController,
                      label: 'Age',
                      suffix: 'yrs',
                      onChanged:
                          (val) => notifier.updateData(age: int.tryParse(val)),
                    ),
                  ),
                if (showAge && showHeight) const SizedBox(width: spacingMd),
                if (showHeight)
                  Expanded(
                    child: _buildNumberInput(
                      controller: _heightController,
                      label: 'Height',
                      suffix: 'cm',
                      onChanged:
                          (val) => notifier.updateData(
                            heightCm: double.tryParse(val),
                          ),
                    ),
                  ),
              ],
            ),

            if (showWeight) ...[
              const SizedBox(height: spacingLg),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput(
                      controller: _weightController,
                      label: 'Weight',
                      suffix: 'kg',
                      onChanged:
                          (val) => notifier.updateData(
                            weightKg: double.tryParse(val),
                          ),
                    ),
                  ),
                ],
              ),
            ],

            if (showActivity) ...[
              const SizedBox(height: spacingLg),
              DropdownButtonFormField<ActivityLevel>(
                value: state.activityLevel,
                decoration: InputDecoration(
                  labelText: 'Activity Level',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radiusMd),
                    borderSide: const BorderSide(color: CustomAppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radiusMd),
                    borderSide: const BorderSide(color: CustomAppColors.border),
                  ),
                  filled: true,
                  fillColor: CustomAppColors.surfaceBackgroundLight,
                ),
                items:
                    ActivityLevel.values.map((level) {
                      return DropdownMenuItem(
                        value: level,
                        child: Text(
                          level.displayName,
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                onChanged: (val) {
                  if (val != null) notifier.updateData(activityLevel: val);
                },
                isExpanded: true,
              ),
            ],

            const SizedBox(height: spacingXl),

            // Calculate Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    FocusScope.of(context).unfocus();
                    notifier.calculate();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: CustomAppColors.primaryButtonLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radiusMd),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Calculate',
                  style: TextStyle(
                    color: CustomAppColors.primaryTextDark,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderButton(
    BuildContext context,
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: spacingMd),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? CustomAppColors.primaryButtonLight
                  : CustomAppColors.surfaceBackgroundLight,
          borderRadius: BorderRadius.circular(radiusMd),
          border: Border.all(
            color:
                isSelected
                    ? CustomAppColors.primaryButtonLight
                    : CustomAppColors.border,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color:
                  isSelected
                      ? CustomAppColors.primaryTextDark
                      : CustomAppColors.secondaryText,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected
                        ? CustomAppColors.primaryTextDark
                        : CustomAppColors.secondaryText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberInput({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required Function(String) onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: CustomAppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: CustomAppColors.border),
        ),
        filled: true,
        fillColor: CustomAppColors.surfaceBackgroundLight,
      ),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Required';
        }
        if (double.tryParse(value) == null) {
          return 'Invalid';
        }
        return null;
      },
    );
  }
}
