import 'package:flutter/material.dart';

/// Brand colours and gradients that sit outside Material's ColorScheme.
@immutable
class CycleColors extends ThemeExtension<CycleColors> {
  const CycleColors({
    required this.period,
    required this.periodSoft,
    required this.fertile,
    required this.fertileSoft,
    required this.todayFill,
    required this.onTodayFill,
    required this.heading,
    required this.muted,
    required this.cardBorder,
    required this.pageGradient,
    required this.heroGradient,
    required this.buttonGradient,
    required this.softPinkCard,
    required this.softLavenderCard,
  });

  final Color period;
  final Color periodSoft;
  final Color fertile;
  final Color fertileSoft;
  final Color todayFill;
  final Color onTodayFill;
  final Color heading;
  final Color muted;
  final Color cardBorder;
  final Gradient pageGradient;
  final Gradient heroGradient;
  final Gradient buttonGradient;
  final Color softPinkCard;
  final Color softLavenderCard;

  static const light = CycleColors(
    // Dark enough for white day numbers (about 5.4:1).
    period: Color(0xFFC2266F),
    periodSoft: Color(0xFFFCE1EE),
    fertile: Color(0xFF9C7FEA),
    fertileSoft: Color(0xFFEDE6FD),
    todayFill: Color(0xFF4A2378),
    onTodayFill: Colors.white,
    heading: Color(0xFF3F1F5C),
    muted: Color(0xFF7A6483),
    cardBorder: Color(0xFFF3E3EE),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFDE8F2), Color(0xFFFBF3FA), Color(0xFFF3EEFD)],
    ),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFCD5E7), Color(0xFFF9E3F1), Color(0xFFEDE4FC)],
    ),
    buttonGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFFD9378A), Color(0xFFB0379F)],
    ),
    softPinkCard: Color(0xFFFDEBF3),
    softLavenderCard: Color(0xFFF1EBFD),
  );

  static const dark = CycleColors(
    period: Color(0xFFC2266F),
    periodSoft: Color(0xFF4A2338),
    fertile: Color(0xFFB9A2F5),
    fertileSoft: Color(0xFF34284D),
    todayFill: Color(0xFFE8D7FF),
    onTodayFill: Color(0xFF2A1440),
    heading: Color(0xFFF6E3F0),
    muted: Color(0xFFC7B2CD),
    cardBorder: Color(0xFF3A2A3E),
    pageGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF2A1726), Color(0xFF1F1622), Color(0xFF1C1828)],
    ),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF4B2240), Color(0xFF3E2244), Color(0xFF30274B)],
    ),
    buttonGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFFD9378A), Color(0xFFA9399E)],
    ),
    softPinkCard: Color(0xFF3A2131),
    softLavenderCard: Color(0xFF2D2640),
  );

  @override
  CycleColors copyWith() => this;

  @override
  CycleColors lerp(ThemeExtension<CycleColors>? other, double t) =>
      (other is CycleColors && t >= 0.5) ? other : this;
}

extension CycleThemeX on BuildContext {
  CycleColors get cycle => Theme.of(this).extension<CycleColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

/// Soft rose / magenta / lavender theme with light and dark variants.
class AppTheme {
  const AppTheme._();

  static const Color magenta = Color(0xFFC92F80);
  static const Color plum = Color(0xFF6B2C91);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final cycle = isLight ? CycleColors.light : CycleColors.dark;

    final base = ColorScheme.fromSeed(
      seedColor: magenta,
      brightness: brightness,
    );
    final scheme = base.copyWith(
      primary: isLight ? magenta : const Color(0xFFF48BC0),
      onPrimary: isLight ? Colors.white : const Color(0xFF4A0E2E),
      primaryContainer:
          isLight ? const Color(0xFFFDDDEC) : const Color(0xFF5E1F44),
      onPrimaryContainer:
          isLight ? const Color(0xFF5A0F37) : const Color(0xFFFFD8EA),
      secondary: isLight ? plum : const Color(0xFFD7B8F5),
      secondaryContainer:
          isLight ? const Color(0xFFEDE4FC) : const Color(0xFF45305F),
      tertiary: cycle.fertile,
      surface: isLight ? const Color(0xFFFFFAFC) : const Color(0xFF1E1620),
      onSurface: cycle.heading,
      onSurfaceVariant: cycle.muted,
      surfaceContainerLowest:
          isLight ? Colors.white : const Color(0xFF241A27),
      surfaceContainerLow:
          isLight ? const Color(0xFFFFF7FB) : const Color(0xFF2A1F2D),
      surfaceContainer:
          isLight ? const Color(0xFFFCF1F7) : const Color(0xFF302433),
      outline: isLight ? const Color(0xFFD9C3D3) : const Color(0xFF6E5A72),
      outlineVariant: cycle.cardBorder,
    );

    final textTheme = (isLight
            ? Typography.material2021().black
            : Typography.material2021().white)
        .apply(
          fontFamily: 'Poppins',
          bodyColor: cycle.heading,
          displayColor: cycle.heading,
        );

    final radius16 = BorderRadius.circular(16);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Poppins',
      textTheme: textTheme.copyWith(
        headlineMedium: textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
        headlineSmall:
            textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium:
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      scaffoldBackgroundColor: scheme.surface,
      extensions: [cycle],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: cycle.heading,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: cycle.heading,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: cycle.cardBorder),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const StadiumBorder(),
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary, width: 1.5),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: cycle.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: cycle.cardBorder),
        backgroundColor: scheme.surfaceContainerLowest,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(
          fontFamily: 'Poppins',
          color: cycle.heading,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : cycle.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : cycle.muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: cycle.muted),
        selectedLabelTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: 'Poppins',
          color: cycle.muted,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: cycle.heading,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: cycle.muted,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: DividerThemeData(color: cycle.cardBorder, space: 1),
    );
  }
}
