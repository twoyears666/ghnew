import 'package:flutter/material.dart';
import 'settings.dart';

/// PCL-style palette copied from the SwiftUI ghnew theme (light + dark).
class Palette {
  final Color pageBackground;
  final Color columnBackground;
  final Color repoRowSelected;
  final Color repoRowNormal;
  final Color cardFill;
  final Color cardBorder;
  final Color cardShadow;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accentBlue;
  final Color branchBlueBg;
  final Color branchBlueText;
  final Color codeBackground;
  final Color codeText;
  final Color successGreen;
  final Color failRed;
  final Color releaseGreen;
  final Color prereleaseBrown;

  Palette({
    required this.pageBackground,
    required this.columnBackground,
    required this.repoRowSelected,
    required this.repoRowNormal,
    required this.cardFill,
    required this.cardBorder,
    required this.cardShadow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accentBlue,
    required this.branchBlueBg,
    required this.branchBlueText,
    required this.codeBackground,
    required this.codeText,
    required this.successGreen,
    required this.failRed,
    required this.releaseGreen,
    required this.prereleaseBrown,
  });
}

const lightPalette = Palette(
  pageBackground: Color(0xFFEEF1F6),
  columnBackground: Color(0xFFE9EDF3),
  repoRowSelected: Color(0xFFC7D0DC),
  repoRowNormal: Color(0xFFE9EDF3),
  cardFill: Color(0xFFFFFFFF),
  cardBorder: Color(0xFFD9E4F0),
  cardShadow: Color(0x14000000),
  textPrimary: Color(0xFF26292E),
  textSecondary: Color(0xFF747B86),
  textMuted: Color(0xFF9AA1AB),
  accentBlue: Color(0xFF3B82F6),
  branchBlueBg: Color(0xFFDDECFF),
  branchBlueText: Color(0xFF1F6FEB),
  codeBackground: Color(0xFFE8EDF2),
  codeText: Color(0xFF9B1C4B),
  successGreen: Color(0xFF1B9C5E),
  failRed: Color(0xFFD3453A),
  releaseGreen: Color(0xFF2EA44F),
  prereleaseBrown: Color(0xFF9A6700),
);

const darkPalette = Palette(
  pageBackground: Color(0xFF14161B),
  columnBackground: Color(0xFF1A1D24),
  repoRowSelected: Color(0xFF35404F),
  repoRowNormal: Color(0xFF1A1D24),
  cardFill: Color(0xFF21262D),
  cardBorder: Color(0xFF3A4150),
  cardShadow: Color(0x66000000),
  textPrimary: Color(0xFFEEF0F4),
  textSecondary: Color(0xFFA8B0BD),
  textMuted: Color(0xFF7A838F),
  accentBlue: Color(0xFF58A6FF),
  branchBlueBg: Color(0xFF1F3A5F),
  branchBlueText: Color(0xFF6CB6FF),
  codeBackground: Color(0xFF1A1F29),
  codeText: Color(0xFFE3988B),
  successGreen: Color(0xFF3FB950),
  failRed: Color(0xFFF85149),
  releaseGreen: Color(0xFF3FB950),
  prereleaseBrown: Color(0xFFD29922),
);

/// Dynamic theme colors. Reads the active palette each time it is accessed.
class T {
  static Palette get p => SettingsStore.i.isDark ? darkPalette : lightPalette;
  static Color get bg => p.pageBackground;
  static Color get column => p.columnBackground;
  static Color get rowSelected => p.repoRowSelected;
  static Color get rowNormal => p.repoRowNormal;
  static Color get card => p.cardFill;
  static Color get border => p.cardBorder;
  static Color get shadow => p.cardShadow;
  static Color get text => p.textPrimary;
  static Color get text2 => p.textSecondary;
  static Color get textMuted => p.textMuted;
  static Color get blue => p.accentBlue;
  static Color get branchBg => p.branchBlueBg;
  static Color get branchText => p.branchBlueText;
  static Color get codeBg => p.codeBackground;
  static Color get codeText => p.codeText;
  static Color get green => p.successGreen;
  static Color get red => p.failRed;
  static Color get release => p.releaseGreen;
  static Color get brown => p.prereleaseBrown;
}

/// Builds the app ThemeData from the current palette.
ThemeData buildAppTheme() {
  final dark = SettingsStore.i.isDark;
  final palette = SettingsStore.i.isDark ? darkPalette : lightPalette;
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accentBlue,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.pageBackground,
    dividerTheme: DividerThemeData(
      color: palette.cardBorder,
      thickness: 1,
      space: 1,
    ),
  );
}