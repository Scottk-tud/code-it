import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../konstanten.dart';
import 'thema.dart';

/// Die Zeichen, die auf der Bildschirmtastatur hinter zwei Ebenen liegen.
///
/// Nur sichtbar ohne Hardware-Tastatur. Klammern setzen das Paar und den Cursor
/// dazwischen, weil das auf dem Glas der häufigste Weg ist, sie zu tippen.
class Tastenleiste extends StatelessWidget {
  const Tastenleiste({super.key, required this.controller, this.onEinklappen});

  final CodeLineEditingController controller;
  final VoidCallback? onEinklappen;

  static const _zeichen = [
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    ';',
    '=',
    '"',
    "'",
    '<',
    '>',
    '+',
    '-',
    '*',
    '/',
    '!',
    '&',
    '|',
    '%',
    '.',
    ',',
    ':',
    '_',
    '\\',
    '#',
    '@',
  ];

  static const _paare = {'{': '}', '(': ')', '[': ']', '"': '"'};

  void _einfuegen(String z) {
    HapticFeedback.selectionClick();
    final zu = _paare[z];
    if (zu != null && controller.selection.isCollapsed) {
      controller.replaceSelection('$z$zu');
      controller.moveCursor(AxisDirection.left);
    } else {
      controller.replaceSelection(z);
    }
    controller.makeCursorVisible();
  }

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    return Material(
      color: f.surfaceContainerHigh,
      child: SizedBox(
        height: hoeheTastenleiste,
        child: Row(
          children: [
            _Taste(
              symbol: Icons.keyboard_tab,
              hinweis: 'Einrücken',
              onTap: () {
                HapticFeedback.selectionClick();
                controller.applyIndent();
              },
            ),
            _Taste(
              symbol: Icons.format_indent_decrease,
              hinweis: 'Ausrücken',
              onTap: controller.applyOutdent,
            ),
            const VerticalDivider(width: 1, indent: 10, endIndent: 10),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: [
                  for (final z in _zeichen)
                    _Zeichen(z, onTap: () => _einfuegen(z)),
                ],
              ),
            ),
            const VerticalDivider(width: 1, indent: 10, endIndent: 10),
            _Taste(
              symbol: Icons.chevron_left,
              hinweis: 'Links',
              onTap: () => controller.moveCursor(AxisDirection.left),
            ),
            _Taste(
              symbol: Icons.chevron_right,
              hinweis: 'Rechts',
              onTap: () => controller.moveCursor(AxisDirection.right),
            ),
            _Taste(
              symbol: Icons.undo,
              hinweis: 'Rückgängig',
              onTap: controller.undo,
            ),
            _Taste(
              symbol: Icons.redo,
              hinweis: 'Wiederholen',
              onTap: controller.redo,
            ),
            if (onEinklappen != null)
              _Taste(
                symbol: Icons.keyboard_hide_outlined,
                hinweis: 'Tastatur ausblenden',
                onTap: onEinklappen!,
              ),
          ],
        ),
      ),
    );
  }
}

class _Zeichen extends StatelessWidget {
  const _Zeichen(this.zeichen, {required this.onTap});
  final String zeichen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Material(
        color: f.surface,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            child: Center(
              child: Text(
                zeichen,
                style: TextStyle(
                  fontFamilyFallback: monoSchriften,
                  fontSize: 18,
                  color: f.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Taste extends StatelessWidget {
  const _Taste({
    required this.symbol,
    required this.hinweis,
    required this.onTap,
  });
  final IconData symbol;
  final String hinweis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(symbol, size: 20),
    tooltip: hinweis,
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
  );
}
