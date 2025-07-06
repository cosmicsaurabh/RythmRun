import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

Widget buildMapControlButton({
  required IconData icon,
  required VoidCallback onPressed,
  required String tooltip,
}) {
  return Container(
    decoration: BoxDecoration(
      color: CustomAppColors.black,
      borderRadius: BorderRadius.circular(radiusSm),
      boxShadow: [
        // First shadow layer (e.g. black-100 token)
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          offset: const Offset(0, 4),
          blurRadius: 4, // same token for blur
          spreadRadius: -1,
        ),

        BoxShadow(
          color: Colors.black.withOpacity(
            0.2,
          ), // adjust for --sds-color-black-200
          offset: const Offset(0, 4),
          blurRadius: 4,
          spreadRadius: -1,
        ),
      ],
    ),
    child: IconButton(
      icon: Icon(icon, size: 24, color: CustomAppColors.white),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(spacingMd),
    ),
  );
}
