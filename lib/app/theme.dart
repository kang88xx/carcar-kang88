import 'package:flutter/material.dart';

/// Calm editorial palette: neutral canvas, borderless white cards, ink
/// primary actions, a blue tint for the hero card and a pale blue highlight.
/// Only Regular (400) and Bold (700) NotoSansKR ship, so styles use those two.
abstract final class Palette {
  static const canvas = Color(0xFFF5F7FA),
      ink = Color(0xFF1E293B),
      accent = Color(0xFF2563EB),
      muted = Color(0xFF526176),
      line = Color(0xFFE2E8F0),
      highlight = Color(0xFFDBEAFE),
      soft = Color(0xFFEEF2F6),
      tint = Color(0xFFE8EFFB),
      tintDeep = Color(0xFFCBDCF8),
      info = Color(0xFFEFF6FF),
      rose = Color(0xFFFFEDE7),
      roseInk = Color(0xFF95452D);
}

/// Width from which the shell shows the sidebar and dialogs open centered.
const wideLayoutBreakpoint = 760.0;

/// Headlines and tab labels keep scaling for accessibility but stop here so
/// Korean words do not break syllable by syllable on narrow phones.
const headlineMaxTextScale = 1.3;

const _pill = StadiumBorder();
const _font = 'NotoSansKR';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Brightness.light,
    primary: Palette.ink,
    surface: Colors.white,
    onSurface: Palette.ink,
    outline: Palette.line,
  );
  OutlineInputBorder field([Color? color, double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: color == null
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.canvas,
    fontFamily: _font,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w400,
        letterSpacing: -1.4,
        height: 1.25,
        color: Palette.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        letterSpacing: -1.1,
        height: 1.3,
        color: Palette.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
        color: Palette.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -.3,
        color: Palette.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.6, letterSpacing: -.3),
      bodyMedium: TextStyle(fontSize: 14, height: 1.6, letterSpacing: -.2),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: Palette.muted),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Palette.soft,
        disabledForegroundColor: Palette.muted,
        minimumSize: const Size(48, 56),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: _pill,
        textStyle: const TextStyle(
          fontFamily: _font,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: Palette.soft,
        foregroundColor: Palette.ink,
        disabledForegroundColor: Palette.muted,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: BorderSide.none,
        shape: _pill,
        textStyle: const TextStyle(
          fontFamily: _font,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.ink,
        minimumSize: const Size(48, 44),
        shape: _pill,
        textStyle: const TextStyle(
          fontFamily: _font,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: Palette.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      hintStyle: const TextStyle(color: Palette.muted),
      labelStyle: const TextStyle(color: Palette.muted),
      floatingLabelStyle: const TextStyle(color: Palette.ink),
      border: field(),
      enabledBorder: field(),
      disabledBorder: field(),
      focusedBorder: field(Palette.ink, 1.5),
      errorBorder: field(Palette.roseInk),
      focusedErrorBorder: field(Palette.roseInk, 1.5),
    ),
    chipTheme: ChipThemeData(
      shape: _pill,
      side: BorderSide.none,
      color: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Palette.ink : Palette.soft,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      labelStyle: const TextStyle(
        fontFamily: _font,
        color: Palette.ink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: _font,
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Palette.highlight,
      indicatorShape: _pill,
      height: 72,
      iconTheme: const WidgetStatePropertyAll(
        IconThemeData(color: Palette.ink, size: 22),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: _font,
          fontSize: 11,
          height: 1.2,
          letterSpacing: -.1,
          color: Palette.ink,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : Palette.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Palette.accent
            : Palette.soft,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Palette.ink,
      textColor: Palette.ink,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: const TextStyle(
        fontFamily: _font,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
        color: Palette.ink,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: _font,
        fontSize: 14,
        height: 1.65,
        color: Palette.ink,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.ink,
      linearTrackColor: Palette.soft,
    ),
  );
}
