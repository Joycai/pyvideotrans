import 'package:flutter/material.dart';

import 'app_extensions.dart';
import 'tokens.dart';

/// 颜色令牌来自设计项目 tokens/colors.css —— 命名与 Flutter ColorScheme 一一对应。
/// 深色主题是单独调校的，不是浅色的反色。
const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF2A63F5),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFE3E9FF),
  onPrimaryContainer: Color(0xFF12306E),
  secondary: Color(0xFF5E5E68),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE0E2F5),
  onSecondaryContainer: Color(0xFF1E1E24),
  // tertiary = 字幕黄。只用于「当前播放字幕」与「待校对」两种状态。
  tertiary: Color(0xFF7A5C00),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFE58A),
  onTertiaryContainer: Color(0xFF3D2E00),
  error: Color(0xFFB3261E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Color(0xFFF5F5F7),
  onSurface: Color(0xFF1C1C1E),
  surfaceDim: Color(0xFFD4D4DA),
  surfaceBright: Color(0xFFFFFFFF),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFEDEDF0),
  surfaceContainer: Color(0xFFE6E6EA),
  surfaceContainerHigh: Color(0xFFDFDFE4),
  surfaceContainerHighest: Color(0xFFD8D8DE),
  onSurfaceVariant: Color(0xFF50505A),
  outline: Color(0xFF7A7A85),
  outlineVariant: Color(0xFFCFCFD6),
  inverseSurface: Color(0xFF24243A),
  onInverseSurface: Color(0xFFF2F2F5),
  inversePrimary: Color(0xFF6E8CFF),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF6E8CFF),
  onPrimary: Color(0xFF08205C),
  primaryContainer: Color(0xFF3556C8),
  onPrimaryContainer: Color(0xFFE3E9FF),
  secondary: Color(0xFFC3C5DC),
  onSecondary: Color(0xFF262840),
  secondaryContainer: Color(0xFF2E2E4A),
  onSecondaryContainer: Color(0xFFE0E2F5),
  tertiary: Color(0xFFF2CE4E),
  onTertiary: Color(0xFF3D2E00),
  tertiaryContainer: Color(0xFF5C4700),
  onTertiaryContainer: Color(0xFFFFE58A),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF16152A),
  onSurface: Color(0xFFE6E6F2),
  surfaceDim: Color(0xFF0E0D1F),
  surfaceBright: Color(0xFF3E3D5C),
  surfaceContainerLowest: Color(0xFF100F22),
  surfaceContainerLow: Color(0xFF1C1B31),
  surfaceContainer: Color(0xFF232238),
  surfaceContainerHigh: Color(0xFF2B2A43),
  surfaceContainerHighest: Color(0xFF34334E),
  onSurfaceVariant: Color(0xFFA9AAC4),
  outline: Color(0xFF7A7B98),
  outlineVariant: Color(0xFF3A3A55),
  inverseSurface: Color(0xFFE6E6F2),
  onInverseSurface: Color(0xFF24243A),
  inversePrimary: Color(0xFF2A63F5),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

TextTheme _textTheme(Color c) => TextTheme(
  displaySmall: TextStyle(
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w500,
    color: c,
  ),
  headlineSmall: TextStyle(
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w500,
    color: c,
  ),
  titleLarge: TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w500,
    color: c,
  ),
  titleMedium: TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    color: c,
  ),
  titleSmall: TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    color: c,
  ),
  bodyLarge: TextStyle(fontSize: 16, height: 24 / 16, color: c),
  bodyMedium: TextStyle(fontSize: 14, height: 20 / 14, color: c),
  bodySmall: TextStyle(fontSize: 12, height: 16 / 12, color: c),
  labelLarge: TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    color: c,
  ),
  labelMedium: TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    color: c,
  ),
  labelSmall: TextStyle(
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w500,
    color: c,
  ),
).apply(fontFamilyFallback: AppFonts.sansFallback);

ThemeData _build(ColorScheme cs, AppColors ext, AppGlass glass, AppElevation e) {
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    fontFamilyFallback: AppFonts.sansFallback,
    textTheme: _textTheme(cs.onSurface),
    scaffoldBackgroundColor: cs.surface,
    extensions: [ext, glass, e],
    visualDensity: VisualDensity.compact,
    // 内容区不靠阴影分层，靠 surface 阶梯 + 1px outlineVariant。
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: glass.glassStrong,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: glass.glassBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: cs.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        shape: controlShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        side: BorderSide(color: cs.outlineVariant),
        shape: controlShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        shape: controlShape,
      ),
    ),
    // Rail 的玻璃底由外层 Container 提供，主题本身保持透明。
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: cs.secondaryContainer,
      labelType: NavigationRailLabelType.all,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: cs.inverseSurface,
      contentTextStyle: TextStyle(color: cs.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: controlShape,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.surfaceContainerHighest,
      linearMinHeight: 4,
    ),
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(AppRadius.xs),
      thumbColor: WidgetStatePropertyAll(cs.outline.withValues(alpha: 0.5)),
    ),
  );
}

final lightTheme = _build(
  _lightScheme,
  AppColors.light,
  AppGlass.light,
  AppElevation.light,
);

final darkTheme = _build(
  _darkScheme,
  AppColors.dark,
  AppGlass.dark,
  AppElevation.dark,
);
