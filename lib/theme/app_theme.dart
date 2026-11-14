import 'package:flutter/material.dart';

/// Automotive instrument neutrals with restrained RedAlert accents.
/// POI colours remain semantic; chrome stays neutral in both light and dark.
class AppTheme {
  AppTheme._();

  // ------------------------------------------------------------ Crimson Radar

  static const crimson = Color(0xFF8F1734);
  static const deepBurgundy = Color(0xFF3B0716);
  static const radarRose = Color(0xFFFF9BAA);
  static const softRose = Color(0xFFFFD9E1);
  static const porcelain = Color(0xFFF5F4F0);
  static const nightRadar = Color(0xFF14191F);

  /// Crimson, straight from the charte.
  static const seed = crimson;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Pin neutral surfaces and accent pairs so the map chrome stays consistent.
  static ColorScheme _branded(ColorScheme generated) {
    final dark = generated.brightness == Brightness.dark;
    return generated.copyWith(
      primary: dark ? radarRose : crimson,
      onPrimary: dark ? deepBurgundy : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF552B35) : const Color(0xFFF0E3E3),
      onPrimaryContainer:
          dark ? const Color(0xFFFFE7EB) : const Color(0xFF4C1023),
      secondary: dark ? const Color(0xFFB8C9D7) : const Color(0xFF536572),
      onSecondary: dark ? const Color(0xFF1E303E) : Colors.white,
      secondaryContainer:
          dark ? const Color(0xFF2F3D48) : const Color(0xFFE1E7EA),
      onSecondaryContainer:
          dark ? const Color(0xFFDCE7EF) : const Color(0xFF273640),
      tertiary: dark ? const Color(0xFFA0A8B3) : const Color(0xFF5B6673),
      onTertiary: dark ? const Color(0xFF161F26) : Colors.white,
      tertiaryContainer:
          dark ? const Color(0xFF343B46) : const Color(0xFFE5E8EC),
      onTertiaryContainer:
          dark ? const Color(0xFFE8EAF0) : const Color(0xFF27303C),
      error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
      onError: dark ? const Color(0xFF690005) : Colors.white,
      surface: dark ? const Color(0xFF14191F) : const Color(0xFFF5F4F0),
      onSurface: dark ? const Color(0xFFE9EDF0) : const Color(0xFF202830),
      onSurfaceVariant:
          dark ? const Color(0xFFB2BDC6) : const Color(0xFF56616B),
      surfaceContainerLowest: dark ? const Color(0xFF0E1318) : Colors.white,
      surfaceContainerLow:
          dark ? const Color(0xFF1B222A) : const Color(0xFFFCFCFA),
      surfaceContainer:
          dark ? const Color(0xFF222B34) : const Color(0xFFEFEEE9),
      surfaceContainerHigh:
          dark ? const Color(0xFF2B3540) : const Color(0xFFE8E9E6),
      surfaceContainerHighest:
          dark ? const Color(0xFF35414D) : const Color(0xFFDEE2E1),
      outline: dark ? const Color(0xFF7D8B98) : const Color(0xFF78838B),
      outlineVariant: dark ? const Color(0xFF394550) : const Color(0xFFD0D6D8),
      surfaceTint: Colors.transparent,
    );
  }

  /// The type scale, exactly as the charte states it. Roboto stays the
  /// system face: no download, no network, and the character comes from the
  /// composition rather than from a decorative font. The condensé of the
  /// logo is deliberately not imported — it is a wordmark, not a reading face.
  ///
  /// `height` is a multiplier in Flutter, hence the divisions: the charte
  /// gives line heights in logical pixels.
  static TextTheme _type(TextTheme base) => base.copyWith(
        headlineSmall: base.headlineSmall?.copyWith(
          fontSize: 26,
          height: 32 / 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontSize: 20,
          height: 26 / 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: base.titleMedium?.copyWith(
          fontSize: 16,
          height: 23 / 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: base.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: base.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.5,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: base.labelLarge?.copyWith(
          fontSize: 16,
          height: 21 / 16,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        labelSmall: base.labelSmall?.copyWith(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      );

  /// For a distance or a radius: the column must not jitter when a digit
  /// changes from 9 to 1 while driving.
  static TextStyle numeric(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = _branded(ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    ));
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _type(ThemeData(brightness: brightness).textTheme),
      extensions: <ThemeExtension<dynamic>>[
        dark ? RedAlertSemantics.dark : RedAlertSemantics.light,
      ],
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
      ),
      iconButtonTheme: const IconButtonThemeData(
          style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(48, 48)),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      )),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        foregroundColor: scheme.onSurface,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          // An outlined button is the secondary action, but it is still an
          // action: tinting the label and icon keeps the accent doing the
          // "this is tappable" work instead of leaving a grey ghost button.
          foregroundColor: scheme.primary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            side:
                BorderSide(color: scheme.outlineVariant.withValues(alpha: .55)),
            borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        // An invalid field is text first: the error colour alone must not be
        // the only thing saying what is wrong.
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
      ),
      // Crimson with a white glyph, which is what makes "Ajouter un lieu"
      // read as the one primary action on the map. The two small utility
      // buttons above it deliberately invert that — see `_buildMapControls`.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      // On is crimson carrying a white thumb; off is a neutral track with an
      // outline, so "off" reads as a switch at rest rather than as a disabled
      // control. These are Material 3's own roles, pinned rather than
      // inherited: this switch arms and disarms a place, and it is the one
      // control in the app whose colour is load-bearing.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            if (states.contains(WidgetState.selected)) return scheme.surface;
            return scheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return scheme.outline;
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.onPrimary;
            return scheme.onSurfaceVariant;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.onPrimary;
            return scheme.onSurfaceVariant;
          }),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(fontSize: 12, color: scheme.onInverseSurface),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Colours that carry a meaning, not a decoration.
///
/// Material's roles say how loud something is; these say what it *is*. They
/// are named after the thing they describe so a widget asks for "paused"
/// rather than for a hex value, and so the light and dark values of the same
/// meaning can never drift apart — the charte defines both columns.
///
/// The alarm screen lives in Kotlin and cannot read a Flutter extension; its
/// three colours are duplicated in `res/values/colors.xml` and referenced by
/// `activity_alarm.xml`. The two copies are kept in step by the charte, not by
/// code, which is why they are documented here.
@immutable
class RedAlertSemantics extends ThemeExtension<RedAlertSemantics> {
  const RedAlertSemantics({
    required this.markerActive,
    required this.markerPaused,
    required this.userLocation,
    required this.warning,
    required this.success,
    required this.alarmBackground,
    required this.alarmForeground,
    required this.alarmStopBackground,
    required this.alarmStopForeground,
  });

  /// A place that is armed.
  final Color markerActive;

  /// A place that exists but will not ring.
  final Color markerPaused;

  /// The user's own position. The only blue in the app, so the GPS dot can
  /// never be mistaken for one of the watched places.
  final Color userLocation;

  /// Something the user has to fix (a permission, a technical warning).
  final Color warning;

  /// Something confirmed working — a test that actually passed, not merely a
  /// permission that was granted.
  final Color success;

  final Color alarmBackground;
  final Color alarmForeground;
  final Color alarmStopBackground;
  final Color alarmStopForeground;

  static RedAlertSemantics of(BuildContext context) =>
      Theme.of(context).extension<RedAlertSemantics>() ?? light;

  static const light = RedAlertSemantics(
    markerActive: Color(0xFF8F1734),
    markerPaused: Color(0xFF78818D),
    userLocation: Color(0xFF2374C6),
    warning: Color(0xFF925400),
    success: Color(0xFF17694F),
    alarmBackground: Color(0xFF3B0716),
    alarmForeground: Colors.white,
    alarmStopBackground: Color(0xFFFFD9E1),
    alarmStopForeground: Color(0xFF3B0716),
  );

  static const dark = RedAlertSemantics(
    markerActive: Color(0xFFFF9BAA),
    markerPaused: Color(0xFFA0A8B3),
    userLocation: Color(0xFF79B8FF),
    warning: Color(0xFFFFC46B),
    success: Color(0xFF75D8AE),
    alarmBackground: Color(0xFF3B0716),
    alarmForeground: Colors.white,
    alarmStopBackground: Color(0xFFFFD9E1),
    alarmStopForeground: Color(0xFF3B0716),
  );

  @override
  RedAlertSemantics copyWith({
    Color? markerActive,
    Color? markerPaused,
    Color? userLocation,
    Color? warning,
    Color? success,
    Color? alarmBackground,
    Color? alarmForeground,
    Color? alarmStopBackground,
    Color? alarmStopForeground,
  }) =>
      RedAlertSemantics(
        markerActive: markerActive ?? this.markerActive,
        markerPaused: markerPaused ?? this.markerPaused,
        userLocation: userLocation ?? this.userLocation,
        warning: warning ?? this.warning,
        success: success ?? this.success,
        alarmBackground: alarmBackground ?? this.alarmBackground,
        alarmForeground: alarmForeground ?? this.alarmForeground,
        alarmStopBackground: alarmStopBackground ?? this.alarmStopBackground,
        alarmStopForeground: alarmStopForeground ?? this.alarmStopForeground,
      );

  @override
  RedAlertSemantics lerp(ThemeExtension<RedAlertSemantics>? other, double t) {
    if (other is! RedAlertSemantics) return this;
    return RedAlertSemantics(
      markerActive: Color.lerp(markerActive, other.markerActive, t)!,
      markerPaused: Color.lerp(markerPaused, other.markerPaused, t)!,
      userLocation: Color.lerp(userLocation, other.userLocation, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      alarmBackground: Color.lerp(alarmBackground, other.alarmBackground, t)!,
      alarmForeground: Color.lerp(alarmForeground, other.alarmForeground, t)!,
      alarmStopBackground:
          Color.lerp(alarmStopBackground, other.alarmStopBackground, t)!,
      alarmStopForeground:
          Color.lerp(alarmStopForeground, other.alarmStopForeground, t)!,
    );
  }
}
