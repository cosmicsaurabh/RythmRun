import 'package:flutter/material.dart';
import '../../../core/utils/validation_helper.dart';
import '../../../const/custom_app_colors.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final PasswordStrength strength;
  final double height;

  const PasswordStrengthIndicator({
    super.key,
    required this.strength,
    this.height = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: _getColor(0),
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: _getColor(1),
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: _getColor(2),
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _getStrengthText(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _getTextColor(),
          ),
        ),
      ],
    );
  }

  Color _getColor(int index) {
    switch (strength) {
      case PasswordStrength.weak:
        return index == 0
            ? CustomAppColors.statusDanger
            : CustomAppColors.surfaceBorder;
      case PasswordStrength.medium:
        return index <= 1
            ? CustomAppColors.statusWarning
            : CustomAppColors.surfaceBorder;
      case PasswordStrength.strong:
        return CustomAppColors.statusSuccess;
    }
  }

  Color _getTextColor() {
    switch (strength) {
      case PasswordStrength.weak:
        return CustomAppColors.statusDanger;
      case PasswordStrength.medium:
        return CustomAppColors.statusWarning;
      case PasswordStrength.strong:
        return CustomAppColors.statusSuccess;
    }
  }

  String _getStrengthText() {
    switch (strength) {
      case PasswordStrength.weak:
        return 'Weak password';
      case PasswordStrength.medium:
        return 'Medium password';
      case PasswordStrength.strong:
        return 'Strong password';
    }
  }
}
