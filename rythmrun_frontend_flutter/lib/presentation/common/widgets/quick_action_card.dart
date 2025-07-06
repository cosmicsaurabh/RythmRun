import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

Widget buildQuickActionCard({
  required BuildContext context,
  String? value,
  required String title,
  String? description,
  required IconData icon,
  required Color color,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusLg),
      child: Container(
        padding: const EdgeInsets.all(spacingLg),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(radiusLg),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(spacingSm),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(radiusSm),
              ),
              child: Icon(icon, color: color, size: iconSizeMd),
            ),
            const SizedBox(height: spacingSm),
            if (value != null)
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null)
              Text(
                description,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: spacingSm),
          ],
        ),
      ),
    ),
  );
}
