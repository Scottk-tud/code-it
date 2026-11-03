import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../konstanten.dart';
import '../zustand/konsole.dart';
import 'thema.dart';

class KonsoleAnsicht extends StatefulWidget {
  const KonsoleAnsicht({super.key, this.onSchliessen});
  final VoidCallback? onSchliessen;

  @override
  State<KonsoleAnsicht> createState() => _KonsoleAnsichtState();
}

class _KonsoleAnsichtState extends State<KonsoleAnsicht> {
  final _eingabe = TextEditingController();
  final _fokus = FocusNode();
  final _rolle = ScrollController();
  int? _verlaufIndex;

  @override
  void dispose() {
    _eingabe.dispose();
    _fokus.dispose();
    _rolle.dispose();
    super.dispose();
  }

  void _absenden(Konsole k) {
    final text = _eingabe.text;
    _eingabe.clear();
    _verlaufIndex = null;
    k.eingeben(text).then((_) => _ansEnde());
    _ansEnde();
    _fokus.requestFocus();
  }

  void _ansEnde() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_rolle.hasClients) _rolle.jumpTo(_rolle.position.maxScrollExtent);
    });
  }

  KeyEventResult _taste(Konsole k, KeyEvent e) {
    if (e is! KeyDownEvent || k.verlauf.isEmpty) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _verlaufIndex = ((_verlaufIndex ?? k.verlauf.length) - 1).clamp(
        0,
        k.verlauf.length - 1,
      );
    } else if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_verlaufIndex == null) return KeyEventResult.handled;
      _verlaufIndex = _verlaufIndex! + 1;
      if (_verlaufIndex! >= k.verlauf.length) {
        _verlaufIndex = null;
        _eingabe.clear();
        return KeyEventResult.handled;
      }
    } else {
      return KeyEventResult.ignored;
    }
    _eingabe.text = k.verlauf[_verlaufIndex!];
    _eingabe.selection = TextSelection.collapsed(offset: _eingabe.text.length);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final k = context.watch<Konsole>();
    final f = Theme.of(context).colorScheme;
    final dunkel = Theme.of(context).brightness == Brightness.dark;
    final hintergrund = dunkel
        ? const Color(0xFF15181D)
        : const Color(0xFFF6F7F8);
    final schrift = TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: monoSchriften,
      fontSize: schriftKonsole,
      height: 1.4,
      color: f.onSurface,
    );
    _ansEnde();

    Color farbe(Zeilenart a) => switch (a) {
      Zeilenart.eingabe => f.primary,
      Zeilenart.normal => f.onSurface,
      Zeilenart.leise => f.onSurfaceVariant,
      Zeilenart.erfolg || Zeilenart.hinzu => f.bestanden,
      Zeilenart.fehler || Zeilenart.weg => f.error,
      Zeilenart.kopf => f.tertiary,
    };

    return ColoredBox(
      color: hintergrund,
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  Icons.terminal_rounded,
                  size: 16,
                  color: f.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Konsole',
                  style: TextStyle(fontSize: 13, color: f.onSurfaceVariant),
                ),
                if (k.beschaeftigt) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Leeren',
                  iconSize: 18,
                  onPressed: k.leeren,
                  icon: const Icon(Icons.clear_all),
                ),
                if (widget.onSchliessen != null)
                  IconButton(
                    tooltip: 'Konsole schließen',
                    iconSize: 18,
                    onPressed: widget.onSchliessen,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _fokus.requestFocus(),
              child: SelectionArea(
                child: ListView.builder(
                  controller: _rolle,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: k.zeilen.length,
                  itemBuilder: (_, i) {
                    final z = k.zeilen[i];
                    final hinterlegt = z.art == Zeilenart.hinzu
                        ? f.hinzugefuegt
                        : z.art == Zeilenart.weg
                        ? f.entfernt
                        : null;
                    return Container(
                      color: hinterlegt,
                      child: Text(
                        z.text.isEmpty ? ' ' : z.text,
                        style: schrift.copyWith(color: farbe(z.art)),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
            child: Row(
              children: [
                Text(
                  k.rueckfrage ?? '\$',
                  style: schrift.copyWith(color: f.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    onKeyEvent: (_, e) => _taste(k, e),
                    child: TextField(
                      controller: _eingabe,
                      focusNode: _fokus,
                      style: schrift,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      textCapitalization: TextCapitalization.none,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _absenden(k),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
