import 'package:flutter/material.dart';

/// Calm editorial palette: neutral canvas, borderless white cards, ink
/// primary actions, a pastel tint for the hero card and a lime highlight.
abstract final class Palette {
  static const canvas = Color(0xFFF3F3F1),
      ink = Color(0xFF17201C),
      green = Color(0xFF2F6B52),
      muted = Color(0xFF6C726E),
      line = Color(0xFFE8E9E5),
      lime = Color(0xFFD9F27C),
      soft = Color(0xFFE9EAE6),
      tint = Color(0xFFDCE3F2),
      tintDeep = Color(0xFFC7D2EC),
      rose = Color(0xFFFFEDE7),
      roseInk = Color(0xFF95452D);
}

const _pill = StadiumBorder();

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.green,
    brightness: Brightness.light,
    primary: Palette.green,
    surface: Colors.white,
    onSurface: Palette.ink,
    outline: Palette.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.canvas,
    fontFamily: 'NotoSansKR',
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w500,
        letterSpacing: -1.4,
        height: 1.25,
        color: Palette.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        letterSpacing: -1.1,
        height: 1.3,
        color: Palette.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -.5,
        color: Palette.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -.3,
        color: Palette.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.6, letterSpacing: -.3),
      bodyMedium: TextStyle(fontSize: 14, height: 1.6, letterSpacing: -.2),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: Palette.muted),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
          fontFamily: 'NotoSansKR',
          fontWeight: FontWeight.w600,
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
          fontFamily: 'NotoSansKR',
          fontWeight: FontWeight.w600,
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
          fontFamily: 'NotoSansKR',
          fontWeight: FontWeight.w600,
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
      floatingLabelStyle: const TextStyle(color: Palette.ink),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.ink, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.roseInk),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.roseInk, width: 1.5),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: _pill,
      side: BorderSide.none,
      backgroundColor: Palette.canvas,
      disabledColor: Palette.canvas,
      selectedColor: Palette.ink,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      labelStyle: TextStyle(
        fontFamily: 'NotoSansKR',
        color: Palette.ink,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: 'NotoSansKR',
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Palette.lime,
      indicatorShape: _pill,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => const IconThemeData(color: Palette.ink, size: 24),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: 11.5,
          color: Palette.ink,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
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
            ? Palette.green
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
        fontFamily: 'NotoSansKR',
        fontSize: 21,
        fontWeight: FontWeight.w600,
        letterSpacing: -.6,
        color: Palette.ink,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: 14,
        height: 1.65,
        color: Palette.ink,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.ink,
      linearTrackColor: Palette.soft,
    ),
  );
}
