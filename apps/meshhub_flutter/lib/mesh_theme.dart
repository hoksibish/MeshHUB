import 'package:material_ui/material_ui.dart';

enum MeshHubTheme {
  firesky('Firesky'),
  cyberpunk('Cyberpunk'),
  retro82('Retro 82'),
  bliss('Bliss');

  const MeshHubTheme(this.label);
  final String label;

  MeshPalette get palette => switch (this) {
    firesky => const MeshPalette(
      background: Color(0xff10110f),
      panel: Color(0xff1c201c),
      primary: Color(0xffffa15b),
      secondary: Color(0xff76b8ad),
      text: Color(0xffeee4cf),
      muted: Color(0xffb1b6a7),
      border: Color(0xff454c40),
      input: Color(0xff141813),
      radius: 22,
    ),
    cyberpunk => const MeshPalette(
      background: Color(0xff0d0b19),
      panel: Color(0xff201a38),
      primary: Color(0xffff70d9),
      secondary: Color(0xff54e8f3),
      text: Color(0xfff3e9ff),
      muted: Color(0xffbdb2d9),
      border: Color(0xff625078),
      input: Color(0xff141024),
      radius: 20,
      mono: true,
    ),
    retro82 => const MeshPalette(
      background: Color(0xff00172e),
      panel: Color(0xff08283b),
      primary: Color(0xfffaa968),
      secondary: Color(0xff8cbfb8),
      text: Color(0xfff6dcac),
      muted: Color(0xff9bb9b4),
      border: Color(0xff416c73),
      input: Color(0xff001c31),
      radius: 20,
      mono: true,
    ),
    bliss => const MeshPalette(
      background: Color(0xffe4e6e1),
      panel: Color(0xfff5f6f2),
      primary: Color(0xff286b59),
      secondary: Color(0xff5b586f),
      text: Color(0xff252c2a),
      muted: Color(0xff59645f),
      border: Color(0xffa5b4ab),
      input: Color(0xffe9ede7),
      radius: 20,
      brightness: Brightness.light,
    ),
  };
}

class MeshPalette {
  const MeshPalette({
    required this.background,
    required this.panel,
    required this.primary,
    required this.secondary,
    required this.text,
    required this.muted,
    required this.border,
    required this.input,
    required this.radius,
    this.brightness = Brightness.dark,
    this.mono = false,
    this.bevel = false,
  });
  final Color background, panel, primary, secondary, text, muted, border, input;
  final double radius;
  final Brightness brightness;
  final bool mono, bevel;

  ThemeData buildTheme() {
    final onAccent = brightness == Brightness.light ? Colors.white : background;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: onAccent,
          secondary: secondary,
          onSecondary: onAccent,
          surface: panel,
          onSurface: text,
          onSurfaceVariant: muted,
          outline: border,
          outlineVariant: border.withValues(alpha: 0.55),
          primaryContainer: primary.withValues(alpha: 0.14),
          onPrimaryContainer: text,
          secondaryContainer: secondary.withValues(alpha: 0.14),
          onSecondaryContainer: text,
          surfaceContainerLowest: background,
          surfaceContainerLow: panel,
          surfaceContainer: panel,
          surfaceContainerHigh: input,
          surfaceContainerHighest: input,
        );
    final shape = bevel
        ? BeveledRectangleBorder(borderRadius: BorderRadius.circular(7))
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,

      scaffoldBackgroundColor: background,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: panel,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: panel,
        indicatorColor: primary.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: primary, size: 22),
        unselectedIconTheme: IconThemeData(color: muted, size: 22),
        selectedLabelTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: primary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: muted,
          fontSize: 13,
          fontFamily: 'Roboto',
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: primary.withValues(alpha: 0.14),
        height: 72,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onAccent,
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: border),
          shape: shape,
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: shape.copyWith(
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: panel,
        shape: shape,
        textStyle: TextStyle(color: text),
      ),
    );
  }
}
