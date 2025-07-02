import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';

// ICON SIZES
const double iconSizeSm = 20;
const double iconSizeMd = 24;
const double iconSizeLg = 32; // Optional for future-proofing

// RADIUS
const double radiusSm = 8;
const double radiusMd = 12;
const double radiusLg = 16;
const double radiusXl = 24;

// SPACING / PADDING (You can use this for both padding/margin if consistent)
const double spacingXs = 4;
const double spacingSm = 8;
const double spacingMd = 12;
const double spacingLg = 16;
const double spacingXl = 24;
const double spacing2xl = 32;

// ELEVATION / EFFECTS
const double blurSm = 4; // for shadows, frosted glass, etc.

final ColorScheme colorSchemeLight = ColorScheme.light(
  primary:
      CustomAppColors
          .primaryButtonLight, // Primary accent color for interactive elements
  onPrimary: CustomAppColors.primaryButtonDark, // Text/icons on primary color
  secondary: CustomAppColors.secondaryText, // Secondary accent color
  onSecondary:
      CustomAppColors.primaryTextLight, // Text/icons on secondary color
  surface:
      CustomAppColors
          .surfaceBackgroundLight, // Main background for components like cards, sheets
  onSurface: CustomAppColors.primaryTextLight, // Text/icons on surfaces
  background: CustomAppColors.surfaceBackgroundLight, // General app background
  onBackground:
      CustomAppColors.primaryTextLight, // Text/icons on general app background
  error: CustomAppColors.statusDanger, // For error states
  onError: CustomAppColors.white, // Text/icons on error color
);

final lightTextTheme = TextTheme(
  // DISPLAY – Big, prominent text (e.g., welcome screens, titles)
  displayLarge: TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  displayMedium: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  displaySmall: TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),

  // HEADLINE – Section titles
  headlineLarge: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  headlineMedium: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  headlineSmall: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),

  // TITLE – Card headers, emphasized content
  titleLarge: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  titleMedium: TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  titleSmall: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),

  // BODY – Paragraph text
  bodyLarge: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  bodyMedium: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  bodySmall: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),

  // LABELS – Buttons, small UI text
  labelLarge: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  labelMedium: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
  labelSmall: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextLight, // Use primaryTextLight
  ),
);

final ThemeData lightTheme = ThemeData(
  useMaterial3: false,
  fontFamily: 'SF Pro Rounded',
  scaffoldBackgroundColor:
      CustomAppColors.surfaceBackgroundLight, // Use custom background
  colorScheme: colorSchemeLight,
  textTheme: lightTextTheme,
  appBarTheme: AppBarTheme(
    elevation: 0,
    color:
        colorSchemeLight.surface, // AppBar background from ColorScheme surface
    iconTheme: IconThemeData(
      color: colorSchemeLight.onSurface,
    ), // Icons on AppBar surface
    titleTextStyle: TextStyle(
      color: colorSchemeLight.onSurface, // Title text on AppBar surface
      fontSize: 20,
      fontWeight: FontWeight.w500,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      padding: EdgeInsets.all(spacingMd),
      backgroundColor:
          CustomAppColors
              .primaryButtonLight, // Light mode primary button background
      foregroundColor:
          CustomAppColors
              .primaryButtonDark, // Light mode primary button text/icon color (white)
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      textStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color:
            CustomAppColors
                .primaryButtonDark, // Light mode primary button text color (white)
      ),
      disabledBackgroundColor:
          CustomAppColors.disabledButtonLight, // Light mode disabled background
      disabledForegroundColor:
          CustomAppColors.secondaryText, // Light mode disabled text color
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: EdgeInsets.all(spacingMd),
      backgroundColor:
          CustomAppColors
              .transparentButtonLight, // Transparent button background for light mode
      foregroundColor:
          CustomAppColors
              .primaryTextLight, // Outlined button text/icon color for light mode
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      side: BorderSide(
        color: CustomAppColors.primaryTextLight,
        width: 1.0,
      ), // Border color for light mode
      textStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color:
            CustomAppColors
                .primaryTextLight, // Outlined button text color for light mode
      ),
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor:
        CustomAppColors.primaryButtonLight, // FAB background for light mode
    foregroundColor:
        CustomAppColors
            .primaryButtonDark, // FAB text/icon color for light mode (white)
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSm),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      backgroundColor:
          CustomAppColors
              .black, // Assuming a dark background for light mode icon buttons
      foregroundColor:
          CustomAppColors
              .white, // Assuming white icon for light mode icon buttons
    ),
  ),
  cardTheme: CardTheme(
    // Changed CardThemeData to CardTheme
    elevation: 4,
    color: CustomAppColors.surfaceCardLight, // Card background for light mode
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusXl),
    ),
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor:
        CustomAppColors
            .surfaceBackgroundLight, // Bottom sheet background for light mode
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(radiusXl),
        topRight: Radius.circular(radiusXl),
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: CustomAppColors.white, // Input field fill color for light mode
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm),
      borderSide: BorderSide(
        color: CustomAppColors.surfaceBorder,
        width: 1.0,
      ), // Border color for light mode
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm),
      borderSide: BorderSide(
        color: CustomAppColors.black,
        width: 1.0,
      ), // Focused border color for light mode
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm),
      borderSide: BorderSide(
        color: CustomAppColors.surfaceBorder,
        width: 1.0,
      ), // Enabled border color for light mode
    ),
    hintStyle: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: CustomAppColors.secondaryText, // Hint text color
    ),
    contentPadding: EdgeInsets.all(spacingLg),
  ),
);

final ColorScheme colorSchemeDark = ColorScheme.dark(
  primary:
      CustomAppColors.primaryButtonDark, // Primary accent color for dark mode
  onPrimary:
      CustomAppColors
          .primaryTextLight, // Text/icons on primary color (black for dark mode buttons)
  secondary: CustomAppColors.secondaryText, // Secondary accent color
  onSecondary: CustomAppColors.primaryTextDark, // Text/icons on secondary color
  surface:
      CustomAppColors
          .surfaceBackgroundDark, // Main background for components like cards, sheets in dark mode
  onSurface:
      CustomAppColors.primaryTextDark, // Text/icons on surfaces in dark mode
  background:
      CustomAppColors
          .surfaceBackgroundDark, // General app background for dark mode
  onBackground:
      CustomAppColors
          .primaryTextDark, // Text/icons on general app background for dark mode
  error: CustomAppColors.statusDanger, // For error states
  onError: CustomAppColors.white, // Text/icons on error color
);

final darkTextTheme = TextTheme(
  // DISPLAY – Big, prominent text (e.g., welcome screens, titles)
  displayLarge: TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  displayMedium: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  displaySmall: TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),

  // HEADLINE – Section titles
  headlineLarge: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  headlineMedium: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  headlineSmall: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),

  // TITLE – Card headers, emphasized content
  titleLarge: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  titleMedium: TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  titleSmall: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),

  // BODY – Paragraph text
  bodyLarge: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  bodyMedium: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  bodySmall: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),

  // LABELS – Buttons, small UI text
  labelLarge: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  labelMedium: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
  labelSmall: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: CustomAppColors.primaryTextDark, // Use primaryTextDark
  ),
);

final ThemeData darkTheme = ThemeData(
  useMaterial3: false,
  fontFamily: 'SF Pro Rounded',
  scaffoldBackgroundColor:
      CustomAppColors
          .surfaceBackgroundDark, // Use custom background for dark mode
  colorScheme: colorSchemeDark,
  textTheme: darkTextTheme,
  appBarTheme: AppBarTheme(
    elevation: 0,
    color:
        colorSchemeDark.surface, // AppBar background from ColorScheme surface
    iconTheme: IconThemeData(
      color: colorSchemeDark.onSurface,
    ), // Icons on AppBar surface
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w500,
      color: colorSchemeDark.onSurface, // Title text on AppBar surface
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      padding: EdgeInsets.all(spacingMd),
      backgroundColor:
          CustomAppColors
              .primaryButtonDark, // Dark mode primary button background
      foregroundColor:
          CustomAppColors
              .primaryTextLight, // Dark mode primary button text/icon color (black)
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      textStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color:
            CustomAppColors
                .primaryTextLight, // Dark mode primary button text color (black)
      ),
      disabledBackgroundColor:
          CustomAppColors.disabledButtonDark, // Dark mode disabled background
      disabledForegroundColor:
          CustomAppColors.secondaryText, // Dark mode disabled text color
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: EdgeInsets.all(spacingMd),
      backgroundColor:
          CustomAppColors
              .transparentButtonDark, // Transparent button background for dark mode
      foregroundColor:
          CustomAppColors
              .primaryTextDark, // Outlined button text/icon color for dark mode
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
      textStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color:
            CustomAppColors
                .primaryTextDark, // Outlined button text color for dark mode
      ),
      side: BorderSide(
        color: CustomAppColors.primaryButtonDark,
        width: 1.0,
      ), // Border color for dark mode
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor:
        CustomAppColors.primaryButtonDark, // FAB background for dark mode
    foregroundColor:
        CustomAppColors
            .primaryTextLight, // FAB text/icon color for dark mode (black)
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSm),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      backgroundColor:
          CustomAppColors
              .white, // Assuming a light background for dark mode icon buttons
      foregroundColor:
          CustomAppColors
              .black, // Assuming black icon for dark mode icon buttons
    ),
  ),
  cardTheme: CardTheme(
    // Changed CardThemeData to CardTheme
    elevation: 0,
    color: CustomAppColors.surfaceCardDark, // Card background for dark mode
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusXl),
    ),
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor:
        CustomAppColors
            .surfaceBackgroundDark, // Bottom sheet background for dark mode
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(radiusXl),
        topRight: Radius.circular(radiusXl),
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: CustomAppColors.black, // Input field fill color for dark mode
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm),
      borderSide: BorderSide(
        color: CustomAppColors.surfaceBorder,
        width: 1.0,
      ), // Border color for dark mode
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm),
      borderSide: BorderSide(
        color: CustomAppColors.white,
        width: 1.0,
      ), // Focused border color for dark mode
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSm),
      borderSide: BorderSide(
        color: CustomAppColors.surfaceBorder,
        width: 1.0,
      ), // Enabled border color for dark mode
    ),
    hintStyle: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: CustomAppColors.secondaryText, // Hint text color
    ),
    contentPadding: EdgeInsets.all(spacingLg),
  ),
);
