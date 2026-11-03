import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import '../konstanten.dart';
import '../werkzeuge/sprache.dart';
import '../zustand/arbeitsplatz.dart';
import '../zustand/tastatur.dart';
import 'tastenleiste.dart';
import 'thema.dart';

/// Reiter über dem Editor, der Editor selbst und – ohne Hardware-Tastatur –
/// die Zeichenleiste über der Bildschirmtastatur.
class EditorBereich extends StatefulWidget {
  const EditorBereich({super.key});

  @override
  State<EditorBereich> createState() => _EditorBereichState();
}

class _EditorBereichState extends State<EditorBereich>
    with WidgetsBindingObserver {
  final _fokus = FocusNode();
  final Map<String, CodeScrollController> _rollen = {};

  @override
  void initState() {
    super.initState();
    _fokus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addObserver(this);
  }

  // Die Tastatur fährt ein paar Frames nach dem Fokus hoch; erst dann stimmt
  // [bildschirmtastaturOffen].
  @override
  void didChangeMetrics() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fokus.dispose();
    for (final r in _rollen.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platz = context.watch<Arbeitsplatz>();
    final pfad = platz.aktiv;
    final h = Theme.of(context).brightness;
    final f = Theme.of(context).colorScheme;
    final t = context.watch<TastaturWaechter>();
    final leiste =
        t.manuell == false ||
        (t.manuell == null && bildschirmtastaturOffen(context));

    return ColoredBox(
      color: editorHintergrund(h),
      child: Column(
        children: [
          _Reiter(platz: platz),
          const Divider(),
          Expanded(
            child: pfad == null
                ? Center(
                    child: Text(
                      'Links eine Datei wählen.',
                      style: TextStyle(color: f.onSurfaceVariant),
                    ),
                  )
                : CodeEditor(
                    key: ValueKey(pfad),
                    controller: platz.puffer(pfad),
                    scrollController: _rollen.putIfAbsent(
                      pfad,
                      CodeScrollController.new,
                    ),
                    focusNode: _fokus,
                    autofocus: false,
                    wordWrap: false,
                    autocompleteSymbols: true,
                    commentFormatter: DefaultCodeCommentFormatter(
                      singleLinePrefix: kommentarZeichen(pfad),
                      multiLinePrefix: '/*',
                      multiLineSuffix: '*/',
                    ),
                    padding: const EdgeInsets.only(
                      left: 4,
                      right: 12,
                      top: 8,
                      bottom: 80,
                    ),
                    style: CodeEditorStyle(
                      fontSize: schriftEditor,
                      fontFamily: 'Menlo',
                      fontFamilyFallback: monoSchriften,
                      fontHeight: 1.45,
                      backgroundColor: editorHintergrund(h),
                      cursorColor: f.primary,
                      cursorLineColor: f.primary.withValues(alpha: 0.06),
                      selectionColor: f.primary.withValues(alpha: 0.25),
                      codeTheme: hervorhebung(pfad, codeThema(h)),
                    ),
                    indicatorBuilder: (context, controller, chunks, notifier) =>
                        Row(
                          children: [
                            DefaultCodeLineNumber(
                              controller: controller,
                              notifier: notifier,
                              textStyle: TextStyle(
                                fontFamilyFallback: monoSchriften,
                                fontSize: schriftEditor - 2,
                                color: f.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              focusedTextStyle: TextStyle(
                                fontFamilyFallback: monoSchriften,
                                fontSize: schriftEditor - 2,
                                color: f.onSurface,
                              ),
                            ),
                            DefaultCodeChunkIndicator(
                              width: 16,
                              controller: chunks,
                              notifier: notifier,
                            ),
                          ],
                        ),
                  ),
          ),
          if (pfad != null && leiste && _fokus.hasFocus)
            Tastenleiste(
              controller: platz.puffer(pfad),
              onEinklappen: () => _fokus.unfocus(),
            ),
        ],
      ),
    );
  }
}

/// Die volle Bildschirmtastatur ist offen. Mit Hardware-Tastatur zeigt iPadOS
/// nur die schmale Kürzelleiste (~55 pt), Android gar nichts.
///
/// Gelesen am View, nicht am MediaQuery des Kontexts: Scaffold zieht den
/// unteren Einzug für seinen Körper ab, darunter steht dort immer 0.
bool bildschirmtastaturOffen(BuildContext context) {
  final v = View.of(context);
  return v.viewInsets.bottom / v.devicePixelRatio > 150;
}

class _Reiter extends StatelessWidget {
  const _Reiter({required this.platz});
  final Arbeitsplatz platz;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    if (platz.offen.isEmpty) return const SizedBox(height: 40);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final p in platz.offen)
            _EinReiter(
              name: p.split('/').last,
              voll: p,
              aktiv: p == platz.aktiv,
              geaendert: platz.istGeaendert(p),
              onTap: () => platz.oeffnen(p),
              onZu: () => platz.schliessen(p),
              farben: f,
            ),
        ],
      ),
    );
  }
}

class _EinReiter extends StatelessWidget {
  const _EinReiter({
    required this.name,
    required this.voll,
    required this.aktiv,
    required this.geaendert,
    required this.onTap,
    required this.onZu,
    required this.farben,
  });
  final String name, voll;
  final bool aktiv, geaendert;
  final VoidCallback onTap, onZu;
  final ColorScheme farben;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: voll,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(left: 14, right: 4),
          decoration: BoxDecoration(
            color: aktiv ? farben.primary.withValues(alpha: 0.08) : null,
            border: Border(
              bottom: BorderSide(
                color: aktiv ? farben.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: aktiv ? FontWeight.w600 : FontWeight.w400,
                  color: aktiv ? farben.onSurface : farben.onSurfaceVariant,
                ),
              ),
              SizedBox(
                width: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  tooltip: geaendert ? 'Ungesichert – schließen' : 'Schließen',
                  onPressed: onZu,
                  icon: geaendert
                      ? Icon(Icons.circle, size: 9, color: farben.primary)
                      : const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
