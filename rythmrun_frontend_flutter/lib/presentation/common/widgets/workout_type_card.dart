import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

Widget buildWorkoutTypeCard({
  required BuildContext context,
  required IconData icon,
  required String title,
  required WorkoutType type,
  required VoidCallback onTap,
}) {
  return Card(
    color: Theme.of(context).colorScheme.primary,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusMd),
      child: Padding(
        padding: const EdgeInsets.all(spacingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: iconSizeLg,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            const SizedBox(height: spacingSm),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
