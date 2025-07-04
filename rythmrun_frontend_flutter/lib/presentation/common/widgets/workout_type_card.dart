import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

Widget buildWorkoutTypeCard({
  required IconData icon,
  required String title,
  required WorkoutType type,
  required VoidCallback onTap,
}) {
  return Card(
    color: CustomAppColors.primaryButtonLight,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusMd),
      child: Padding(
        padding: const EdgeInsets.all(spacingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: CustomAppColors.white),
            const SizedBox(height: spacingSm),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: CustomAppColors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
