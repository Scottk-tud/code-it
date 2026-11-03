import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../api/artemis.dart';
import '../api/modelle.dart';
import 'thema.dart';

enum _Teststand { bestanden, durchgefallen, offen }

/// Test-id → Name der Teilaufgabe. Viele Aufgaben verbergen die Testnamen
/// (`showTestNamesToStudents: false`); dann ist das der einzige lesbare Titel.
Map<int, String> teilaufgabeNachTest(String? text) {
  final namen = <int, String>{};
  if (text == null) return namen;
  for (final m in Aufgabenstellung._task.allMatches(text)) {
    for (final t in (m[2] ?? '').split(Aufgabenstellung._trenner)) {
      final id = int.tryParse(
        Aufgabenstellung._testId.firstMatch(t)?.group(1) ?? '',
      );
      if (id != null) namen[id] = m[1]!;
    }
  }
  return namen;
}

/// Die Aufgabenstellung mit Häkchen an den `[task]`-Markern.
///
/// Die Logik folgt `ProgrammingExerciseInstructionService` aus dem Web-Client:
/// Eine Teilaufgabe ist grün, wenn alle ihre Tests positiv sind, rot, sobald
/// einer negativ ist, sonst offen.
class Aufgabenstellung extends StatelessWidget {
  const Aufgabenstellung({
    super.key,
    required this.text,
    required this.ergebnis,
    required this.artemis,
  });

  final String text;
  final Ergebnis? ergebnis;
  final Artemis artemis;

  /// Aus dem Web-Client übernommen (`programming-exercise-task.extension.ts`).
  static final _task = RegExp(
    r'\[task]\[([^[\]]+)]\(((?:[^(),]+(?:\([^()]*\)[^(),]*)?(?:,[^(),]+(?:\([^()]*\)[^(),]*)?)*)?)\)',
  );
  static final _testId = RegExp(r'<testid>(\d+)</testid>');
  static final _trenner = RegExp(r',(?![^(]*?\))');
  static final _uml = RegExp(r'^@startuml[\s\S]*?^@enduml', multiLine: true);

  _Teststand _stand(String tests) {
    final e = ergebnis;
    if (e == null) return _Teststand.offen;
    final eintraege = tests
        .split(_trenner)
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty);
    if (e.erfolgreich == true && e.rueckmeldungen.isEmpty) {
      return _Teststand.bestanden;
    }
    var alleGut = eintraege.isNotEmpty;
    for (final t in eintraege) {
      final id = int.tryParse(_testId.firstMatch(t)?.group(1) ?? '');
      final r = e.rueckmeldungen.where(
        (r) => id != null ? r.testId == id : r.test == t,
      );
      if (r.isEmpty || r.first.positiv == null) {
        alleGut = false;
      } else if (r.first.positiv == false) {
        return _Teststand.durchgefallen;
      }
    }
    return alleGut ? _Teststand.bestanden : _Teststand.offen;
  }

  @override
  Widget build(BuildContext context) {
    final teile = <Widget>[];
    var rest = text;
    while (true) {
      final m = _uml.firstMatch(rest);
      if (m == null) break;
      teile.add(_markdown(context, rest.substring(0, m.start)));
      teile.add(_Uml(quelle: m.group(0)!, artemis: artemis));
      rest = rest.substring(m.end);
    }
    teile.add(_markdown(context, rest));
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: teile,
      ),
    );
  }

  Widget _markdown(BuildContext context, String quelle) {
    final t = Theme.of(context);
    return MarkdownBody(
      // Mehrzeilige $$…$$ auf eine Zeile ziehen, damit die Inline-Regel greift.
      data: quelle.replaceAllMapped(
        RegExp(r'\$\$([\s\S]+?)\$\$'),
        (m) => '\$\$${m[1]!.replaceAll('\n', ' ')}\$\$',
      ),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [_TaskSyntax(_task), _MatheSyntax()],
      builders: {
        'task': _TaskBuilder(_stand, t.colorScheme),
        'mathe': _MatheBuilder(),
      },
      onTapLink: (_, href, _) {
        if (href != null) {
          launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
        }
      },
      styleSheet: MarkdownStyleSheet.fromTheme(t).copyWith(
        p: t.textTheme.bodyLarge?.copyWith(height: 1.5),
        listBullet: t.textTheme.bodyLarge,
        h1: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        h2: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        h3: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        code: TextStyle(
          fontFamilyFallback: monoSchriften,
          fontSize: 14,
          backgroundColor: t.colorScheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: t.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          color: t.colorScheme.secondaryContainer.withValues(alpha: 0.4),
          border: Border(
            left: BorderSide(color: t.colorScheme.secondary, width: 3),
          ),
        ),
        blockSpacing: 12,
      ),
    );
  }
}

class _TaskSyntax extends md.InlineSyntax {
  _TaskSyntax(RegExp muster) : super(muster.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final e = md.Element.text('task', match[1]!)
      ..attributes['tests'] = match[2] ?? '';
    parser.addNode(e);
    return true;
  }
}

/// `$$…$$` ist bei Artemis KaTeX. Ohne eigene TeX-Engine wird daraus kursiver
/// Text mit den häufigsten Befehlen als Unicode – für $$n$$, $$a \le b$$ oder
/// $$x^2$$ reicht das, Brüche und Matrizen bleiben als Quelltext lesbar.
class _MatheSyntax extends md.InlineSyntax {
  _MatheSyntax() : super(r'\$\$(.+?)\$\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mathe', texAlsText(match[1]!.trim())));
    return true;
  }
}

class _MatheBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: (parentStyle ?? const TextStyle()).copyWith(
          fontStyle: FontStyle.italic,
          fontFamily: 'Times New Roman',
          fontFamilyFallback: const ['serif'],
        ),
      ),
    );
  }
}

const _tex = {
  r'\le': '≤',
  r'\leq': '≤',
  r'\ge': '≥',
  r'\geq': '≥',
  r'\neq': '≠',
  r'\ne': '≠',
  r'\cdot': '·',
  r'\times': '×',
  r'\div': '÷',
  r'\pm': '±',
  r'\infty': '∞',
  r'\in': '∈',
  r'\notin': '∉',
  r'\subseteq': '⊆',
  r'\subset': '⊂',
  r'\cup': '∪',
  r'\cap': '∩',
  r'\emptyset': '∅',
  r'\to': '→',
  r'\rightarrow': '→',
  r'\Rightarrow': '⇒',
  r'\leftarrow': '←',
  r'\Leftrightarrow': '⇔',
  r'\forall': '∀',
  r'\exists': '∃',
  r'\neg': '¬',
  r'\land': '∧',
  r'\lor': '∨',
  r'\sum': 'Σ',
  r'\prod': 'Π',
  r'\sqrt': '√',
  r'\approx': '≈',
  r'\equiv': '≡',
  r'\ldots': '…',
  r'\dots': '…',
  r'\cdots': '⋯',
  r'\mathbb{N}': 'ℕ',
  r'\mathbb{Z}': 'ℤ',
  r'\mathbb{R}': 'ℝ',
  r'\alpha': 'α',
  r'\beta': 'β',
  r'\gamma': 'γ',
  r'\delta': 'δ',
  r'\epsilon': 'ε',
  r'\lambda': 'λ',
  r'\mu': 'μ',
  r'\pi': 'π',
  r'\sigma': 'σ',
  r'\phi': 'φ',
  r'\omega': 'ω',
  r'\Theta': 'Θ',
  r'\theta': 'θ',
  r'\Omega': 'Ω',
  r'\log': 'log',
  r'\ln': 'ln',
  r'\mod': 'mod',
  r'\bmod': 'mod',
  r'\{': '{',
  r'\}': '}',
  r'\,': ' ',
  r'\;': ' ',
  r'\ ': ' ',
};
const _hoch = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
  'n': 'ⁿ',
  'i': 'ⁱ',
  '+': '⁺',
  '-': '⁻',
};
const _tief = {
  '0': '₀',
  '1': '₁',
  '2': '₂',
  '3': '₃',
  '4': '₄',
  '5': '₅',
  '6': '₆',
  '7': '₇',
  '8': '₈',
  '9': '₉',
  'i': 'ᵢ',
  'j': 'ⱼ',
  'n': 'ₙ',
  'k': 'ₖ',
  '+': '₊',
  '-': '₋',
};

String texAlsText(String tex) {
  var s = tex;
  // Längere Befehle zuerst, sonst frisst \le das \leq.
  final befehle = _tex.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final b in befehle) {
    // Nur Buchstabenbefehle brauchen die Wortgrenze: \le darf nicht in \left greifen.
    final grenze = RegExp(r'[a-zA-Z]$').hasMatch(b) ? '(?![a-zA-Z])' : '';
    s = s.replaceAllMapped(
      RegExp('${RegExp.escape(b)}$grenze'),
      (_) => _tex[b]!,
    );
  }
  String ersetzen(String s, String zeichen, Map<String, String> tabelle) =>
      s.replaceAllMapped(RegExp('\\$zeichen(?:\\{([^{}]*)\\}|(\\S))'), (m) {
        final inhalt = m[1] ?? m[2]!;
        final umgesetzt = inhalt.split('').map((c) => tabelle[c]).toList();
        return umgesetzt.contains(null)
            ? '$zeichen($inhalt)'
            : umgesetzt.join();
      });
  s = ersetzen(s, '^', _hoch);
  s = ersetzen(s, '_', _tief);
  s = s.replaceAllMapped(
    RegExp(r'\\(?:text|mathrm|mathit|operatorname)\{([^{}]*)\}'),
    (m) => m[1]!,
  );
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

class _TaskBuilder extends MarkdownElementBuilder {
  _TaskBuilder(this.stand, this.farben);
  final _Teststand Function(String) stand;
  final ColorScheme farben;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final s = stand(element.attributes['tests'] ?? '');
    final (symbol, farbe) = switch (s) {
      _Teststand.bestanden => (Icons.check_circle_rounded, farben.bestanden),
      _Teststand.durchgefallen => (Icons.cancel_rounded, farben.durchgefallen),
      _Teststand.offen => (Icons.radio_button_unchecked, farben.outline),
    };
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(symbol, size: 18, color: farbe),
            ),
          ),
          TextSpan(
            text: element.textContent,
            style: (parentStyle ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Uml extends StatefulWidget {
  const _Uml({required this.quelle, required this.artemis});
  final String quelle;
  final Artemis artemis;

  @override
  State<_Uml> createState() => _UmlState();
}

class _UmlState extends State<_Uml> {
  Future<Uint8List?>? _bild;
  Brightness? _fuer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final h = Theme.of(context).brightness;
    if (h != _fuer) {
      _fuer = h;
      _bild = widget.artemis
          .plantUml(widget.quelle, dunkel: h == Brightness.dark)
          .catchError((_) => null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: FutureBuilder<Uint8List?>(
        future: _bild,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (s.data == null) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: f.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.quelle,
                style: const TextStyle(
                  fontFamilyFallback: monoSchriften,
                  fontSize: 13,
                ),
              ),
            );
          }
          return InteractiveViewer(
            maxScale: 4,
            child: Image.memory(s.data!, fit: BoxFit.contain),
          );
        },
      ),
    );
  }
}
