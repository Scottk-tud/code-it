import 'package:flutter/material.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/xcode.dart';

const _akzent = Color(0xFF2F6F62);

const monoSchriften = ['Menlo', 'SF Mono', 'Roboto Mono', 'monospace'];

ThemeData thema(Brightness helligkeit) {
  final farben = ColorScheme.fromSeed(
    seedColor: _akzent,
    brightness: helligkeit,
  );
  return ThemeData(
    colorScheme: farben,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(
      color: farben.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: farben.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: farben.onSurface,
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 600),
    ),
  );
}

/// Farben für Bestanden/Nicht bestanden, in beiden Modi lesbar.
extension ErgebnisFarben on ColorScheme {
  Color get bestanden => brightness == Brightness.dark
      ? const Color(0xFF7BD88F)
      : const Color(0xFF1E7B3A);
  Color get durchgefallen => error;
  Color get hinzugefuegt => brightness == Brightness.dark
      ? const Color(0x3348C774)
      : const Color(0x2248C774);
  Color get entfernt => brightness == Brightness.dark
      ? const Color(0x33F2545B)
      : const Color(0x22F2545B);
}

Map<String, TextStyle> codeThema(Brightness helligkeit) =>
    helligkeit == Brightness.dark ? atomOneDarkTheme : xcodeTheme;

Color editorHintergrund(Brightness helligkeit) =>
    helligkeit == Brightness.dark ? const Color(0xFF1F232A) : Colors.white;
