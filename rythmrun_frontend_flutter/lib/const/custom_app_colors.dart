import 'dart:ui';

class CustomAppColors {
  // Core colors
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  // Brand colors
  static const colorA = Color(0xFF6C63FF);
  static const colorB = Color(0xFF4ECDC4);
  static const colorC = Color(0xFFFF6B6B);

  // Backgrounds / Surfaces
  static const surfaceBackgroundLight = Color(0xFFF7F7F7);
  static const surfaceBackgroundDark = Color(0xFF0D0B10);

  static const surfaceCardLight = Color(0xFFFFFFFF);
  static const surfaceCardDark = Color(0xFF161616);
  static const cardDark = Color(0xFF161616);

  static const surfaceBorder = Color(0xFFEEEEEE);
  static const border = Color(0xFFEEEEEE);
  static const surfaceShadow = Color.fromRGBO(0, 0, 0, 0.5);

  static const surfaceBottomBarLight = Color(0xFFF5F5F5);
  static const surfaceBottomBarDark = Color(0xFF0D0B10);

  // Text colors
  static const primaryTextLight = Color(0xFF000000);
  static const primaryTextDark = Color(0xFFFFFFFF);

  static const secondaryText = Color(0xFF898989);

  // Buttons
  static const primaryButtonLight = Color(0xFF000000);
  static const primaryButtonDark = Color(0xFFFFFFFF);

  static const transparentButtonLight = Color(0xFFF5F5F5);
  static const transparentButtonDark = Color(0xFF0D0B10);

  static const disabledButtonLight = Color(0xFFE5E5E5);
  static const disabledButtonDark = Color(0xFF2D2D2D);

  // Status indicators
  static const statusWarning = Color(0xFFE68E4A);
  static const statusDanger = Color(0xFFE6624A);
  static const statusError = Color(0xFFE6624A); // Same as statusDanger
  static const statusSuccess = Color(0xFFB1CF5C);
  static const statusInfo = Color(0xFF73A7E0);

  // Progress indicators (for charts or bars)
  static const progressSky = Color(0xFFB4DAFF);
  static const walking = Color(0xFFFFCE8F);
  static const cycling = Color(0xFFB5E1A1);
  static const hiking = Color(0xFFEAB4FF);
  static const running = Color(0xFFB9BBFF);
  static const distance = Color(0xFFFFB4B4);
  static const time = Color(0xFFD0B4FF);
}
