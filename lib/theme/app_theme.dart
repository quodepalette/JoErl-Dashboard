import 'package:flutter/material.dart';

/// Central place for the JoErl look — near-black background, neon accents,
/// same vibe as the FPS overlay / Dimmest / Borderless tools.
class AppColors {
  static const background = Color(0xFF0B0B0F);
  static const surface = Color(0xFF15151C);
  static const surfaceElevated = Color(0xFF1D1D26);
  static const border = Color(0xFF2A2A35);

  static const textPrimary = Color(0xFFF2F2F5);
  static const textSecondary = Color(0xFF9A9AA6);
  static const textMuted = Color(0xFF5C5C68);

  static const accentGreen = Color(0xFF39FF88);
  static const accentBlue = Color(0xFF4FC3FF);
  static const accentPurple = Color(0xFFB388FF);
  static const accentPink = Color(0xFFFF4FA3);
  static const accentAmber = Color(0xFFFFC24F);

  static const running = Color(0xFF39FF88);
  static const stopped = Color(0xFF5C5C68);

  static const error = Color(0xFFFF5C5C);
  static const success = Color(0xFF39FF88);
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accentGreen,
        secondary: AppColors.accentBlue,
        surface: AppColors.surface,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
        fontFamily: 'Montserrat',
      ),
      dividerColor: AppColors.border,
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.border),
      ),
      // Explicit contentTextStyle so toast text is always legible against our
      // dark surfaceElevated background — without this Material3 computes a
      // contrast color for its default (light) snackbar surface instead,
      // which reads as dull/near-invisible on our theme.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          height: 1.35,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
