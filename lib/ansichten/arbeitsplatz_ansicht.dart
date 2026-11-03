import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/modelle.dart';
import '../konstanten.dart';
import '../zustand/arbeitsplatz.dart';
import '../zustand/konsole.dart';
import '../zustand/sitzung.dart';
import '../zustand/tastatur.dart';
import 'aufgabenstellung.dart';
import 'dateibaum.dart';
import 'editor_bereich.dart';
import 'ergebnis_ansicht.dart';
import 'konsole_ansicht.dart';
import 'thema.dart';

class ArbeitsplatzAnsicht extends StatelessWidget {
  const ArbeitsplatzAnsicht({super.key, required this.aufgabe, this.ablage});
  final Aufgabe aufgabe;

  /// Für Tests; sonst der Application-Support-Ordner.
  final Future<Directory> Function()? ablage;

  @override
  Widget build(BuildContext context) {
    final artemis = context.read<Sitzung>().artemis;
    return ChangeNotifierProvider(
      create: (_) =>
          Arbeitsplatz(artemis: artemis, aufgabe: aufgabe, ablage: ablage)
            ..laden(),
      child: Builder(
        builder: (context) => ChangeNotifierProvider(
          create: (_) => Konsole(context.read<Arbeitsplatz>()),
          child: const _Rahmen(),
        ),
      ),
    );
  }
}

enum _Seite { aufgabe, ergebnis }

enum _Bereich { aufgabe, dateien, code, ergebnis }

class _Rahmen extends StatefulWidget {
  const _Rahmen();

  @override
  State<_Rahmen> createState() => _RahmenState();
}

class _RahmenState extends State<_Rahmen> {
  bool _baumSichtbar = true;
  bool _seiteSichtbar = true;
  bool _konsoleSichtbar = const String.fromEnvironment(
    'DEMO_BEFEHLE',
  ).isNotEmpty;
  double _konsolenHoehe = hoeheKonsoleStandard;
  _Seite _seite = _Seite.aufgabe;
  _Bereich _bereich = _Bereich.code;
  Bauzustand? _letzterBau;

  @override
  Widget build(BuildContext context) {
    final platz = context.watch<Arbeitsplatz>();
    // Abhängigkeit, damit die Navigationsleiste beim Tastatur-Ein/Aus neu baut.
    MediaQuery.viewInsetsOf(context);
    _aufBauHoeren(platz);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (weg, _) {
        if (weg && platz.hatUngesichertes) platz.speichern(still: true);
      },
      child: CallbackShortcuts(
        bindings: _kuerzel(platz),
        child: Scaffold(
          appBar: _leiste(context, platz),
          body: _koerper(context, platz),
        ),
      ),
    );
  }

  /// Nach einer Abgabe von selbst zum Ergebnis wechseln.
  void _aufBauHoeren(Arbeitsplatz platz) {
    if (_letzterBau == Bauzustand.baut && platz.bau == Bauzustand.fertig) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() {
          _seite = _Seite.ergebnis;
          _seiteSichtbar = true;
          if (_bereich != _Bereich.code) _bereich = _Bereich.ergebnis;
        }),
      );
    }
    if (platz.bau == Bauzustand.fehler &&
        _letzterBau != Bauzustand.fehler &&
        platz.meldung != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(platz.meldung!)));
      });
    }
    _letzterBau = platz.bau;
  }

  Map<ShortcutActivator, VoidCallback> _kuerzel(Arbeitsplatz platz) {
    final k = <ShortcutActivator, VoidCallback>{};
    void beide(LogicalKeyboardKey taste, VoidCallback f, {bool shift = false}) {
      k[SingleActivator(taste, meta: true, shift: shift)] = f;
      k[SingleActivator(taste, control: true, shift: shift)] = f;
    }

    beide(LogicalKeyboardKey.keyS, () => platz.speichern());
    beide(LogicalKeyboardKey.enter, () => _abgeben(context, platz));
    beide(
      LogicalKeyboardKey.keyJ,
      () => setState(() => _konsoleSichtbar = !_konsoleSichtbar),
    );
    beide(
      LogicalKeyboardKey.backquote,
      () => setState(() => _konsoleSichtbar = !_konsoleSichtbar),
    );
    beide(
      LogicalKeyboardKey.keyB,
      () => setState(() => _baumSichtbar = !_baumSichtbar),
    );
    beide(
      LogicalKeyboardKey.keyI,
      () => setState(() => _seiteSichtbar = !_seiteSichtbar),
    );
    beide(LogicalKeyboardKey.keyP, () => _schnellOeffnen(context, platz));
    beide(LogicalKeyboardKey.keyW, () {
      if (platz.aktiv != null) platz.schliessen(platz.aktiv!);
    });
    beide(
      LogicalKeyboardKey.bracketRight,
      () => _reiterWechseln(platz, 1),
      shift: true,
    );
    beide(
      LogicalKeyboardKey.bracketLeft,
      () => _reiterWechseln(platz, -1),
      shift: true,
    );
    return k;
  }

  void _reiterWechseln(Arbeitsplatz platz, int richtung) {
    if (platz.offen.length < 2 || platz.aktiv == null) return;
    final i = platz.offen.indexOf(platz.aktiv!);
    platz.oeffnen(platz.offen[(i + richtung) % platz.offen.length]);
  }

  PreferredSizeWidget _leiste(BuildContext context, Arbeitsplatz platz) {
    final breit = MediaQuery.sizeOf(context).width >= breiteNebeneinander;
    final hatRepo = platz.teilnahme != null && !platz.laedt;
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          Flexible(
            child: Text(platz.aufgabe.titel, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          if (hatRepo) _Stand(platz: platz),
        ],
      ),
      actions: [
        if (hatRepo && breit)
          _Umschalter(
            symbol: Icons.vertical_split_outlined,
            hinweis: 'Dateien (⌘B)',
            an: _baumSichtbar,
            onTap: () => setState(() => _baumSichtbar = !_baumSichtbar),
          ),
        if (hatRepo)
          _Umschalter(
            symbol: Icons.terminal_rounded,
            hinweis: 'Konsole (⌘J)',
            an: _konsoleSichtbar,
            onTap: () => setState(() {
              _konsoleSichtbar = !_konsoleSichtbar;
              if (_konsoleSichtbar && !breit) _bereich = _Bereich.code;
            }),
          ),
        if (hatRepo && breit) ...[
          _Umschalter(
            symbol: Icons.menu_book_outlined,
            hinweis: 'Aufgabe und Ergebnis (⌘I)',
            an: _seiteSichtbar,
            onTap: () => setState(() => _seiteSichtbar = !_seiteSichtbar),
          ),
          const SizedBox(width: 8),
        ],
        if (hatRepo) ...[
          IconButton(
            tooltip: 'Speichern (⌘S)',
            onPressed:
                platz.hatUngesichertes && platz.bau != Bauzustand.speichert
                ? () => platz.speichern()
                : null,
            icon: const Icon(Icons.save_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: FilledButton.icon(
              onPressed:
                  platz.bau == Bauzustand.gibtAb || platz.bau == Bauzustand.baut
                  ? null
                  : () => _abgeben(context, platz),
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: const Text('Abgeben'),
            ),
          ),
        ],
        _Menue(platz: platz, onKuerzel: () => _kuerzelZeigen(context)),
      ],
    );
  }

  Widget _koerper(BuildContext context, Arbeitsplatz platz) {
    if (platz.laedt && platz.eintraege.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (platz.ladefehler != null && platz.eintraege.isEmpty) {
      return _Fehler(text: platz.ladefehler!, onNochmal: platz.laden);
    }
    if (platz.teilnahme == null) return _NichtGestartet(platz: platz);

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= breiteNebeneinander) return _breit(context, platz, c);
        return _kompakt(context, platz, c);
      },
    );
  }

  Widget _breit(BuildContext context, Arbeitsplatz platz, BoxConstraints c) {
    final seitenbreite = (c.maxWidth * anteilSeitenleiste).clamp(
      breiteSeitenleisteMin,
      560.0,
    );
    return Column(
      children: [
        if (platz.verbindung == Verbindung.offline) const _OfflineBalken(),
        Expanded(
          child: Row(
            children: [
              if (_baumSichtbar) ...[
                SizedBox(width: breiteDateibaum, child: const Dateibaum()),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: Column(
                  children: [
                    const Expanded(child: EditorBereich()),
                    if (_konsoleSichtbar) ..._konsole(c),
                  ],
                ),
              ),
              if (_seiteSichtbar) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: seitenbreite,
                  child: _Seitenleiste(
                    seite: _seite,
                    onSeite: (s) => setState(() => _seite = s),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _konsole(BoxConstraints c) => [
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => setState(() {
        _konsolenHoehe = (_konsolenHoehe - d.delta.dy).clamp(
          hoeheKonsoleMin,
          c.maxHeight * 0.7,
        );
      }),
      child: const SizedBox(
        height: 10,
        child: Center(child: Divider(height: 1)),
      ),
    ),
    SizedBox(
      height: _konsolenHoehe,
      child: KonsoleAnsicht(
        onSchliessen: () => setState(() => _konsoleSichtbar = false),
      ),
    ),
  ];

  Widget _kompakt(BuildContext context, Arbeitsplatz platz, BoxConstraints c) {
    final tastatur = bildschirmtastaturOffen(context);
    final inhalt = switch (_bereich) {
      _Bereich.aufgabe => _AufgabeSeite(platz: platz),
      _Bereich.dateien => Dateibaum(
        nachAuswahl: () => setState(() => _bereich = _Bereich.code),
      ),
      _Bereich.code => Column(
        children: [
          const Expanded(child: EditorBereich()),
          if (_konsoleSichtbar) ..._konsole(c),
        ],
      ),
      _Bereich.ergebnis => const ErgebnisAnsicht(),
    };
    return Column(
      children: [
        if (platz.verbindung == Verbindung.offline) const _OfflineBalken(),
        Expanded(child: inhalt),
        if (!tastatur)
          NavigationBar(
            height: 64,
            selectedIndex: _bereich.index,
            onDestinationSelected: (i) =>
                setState(() => _bereich = _Bereich.values[i]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                label: 'Aufgabe',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                label: 'Dateien',
              ),
              NavigationDestination(
                icon: Icon(Icons.code_rounded),
                label: 'Code',
              ),
              NavigationDestination(
                icon: Icon(Icons.fact_check_outlined),
                label: 'Ergebnis',
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _abgeben(BuildContext context, Arbeitsplatz platz) async {
    final frist = platz.aufgabe.faellig;
    final spaet = frist != null && frist.isBefore(DateTime.now());
    final n = platz.geaenderte.length;
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Abgeben?'),
        content: Text(
          [
            if (spaet) 'Die Abgabefrist ist vorbei.',
            if (n > 0)
              '$n ungesicherte Datei${n == 1 ? '' : 'en'} werden mit abgegeben.',
            'Die Tests laufen danach auf dem Server.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Abgeben'),
          ),
        ],
      ),
    );
    if (ja == true) await platz.abgeben();
  }

  Future<void> _schnellOeffnen(BuildContext context, Arbeitsplatz platz) async {
    final dateien =
        platz.eintraege.entries
            .where((e) => e.value == Eintragsart.datei)
            .map((e) => e.key)
            .toList()
          ..sort();
    final wahl = await showDialog<String>(
      context: context,
      builder: (_) => _Schnellauswahl(dateien: dateien),
    );
    if (wahl != null) platz.oeffnen(wahl);
  }

  void _kuerzelZeigen(BuildContext context) {
    const liste = [
      ('⌘ S', 'Speichern'),
      ('⌘ ↩', 'Abgeben'),
      ('⌘ P', 'Datei öffnen'),
      ('⌘ W', 'Reiter schließen'),
      ('⌘ ⇧ [  ]', 'Reiter wechseln'),
      ('⌘ B', 'Dateien ein/aus'),
      ('⌘ J', 'Konsole ein/aus'),
      ('⌘ I', 'Aufgabe ein/aus'),
      ('⌘ /', 'Zeile auskommentieren'),
      ('⌘ F', 'Suchen'),
      ('⌘ Z  /  ⌘ ⇧ Z', 'Rückgängig / Wiederholen'),
      ('Tab  /  ⇧ Tab', 'Einrücken / Ausrücken'),
    ];
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tastenkürzel'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (taste, was) in liste)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          taste,
                          style: const TextStyle(
                            fontFamilyFallback: monoSchriften,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(child: Text(was)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _Seitenleiste extends StatelessWidget {
  const _Seitenleiste({required this.seite, required this.onSeite});
  final _Seite seite;
  final ValueChanged<_Seite> onSeite;

  @override
  Widget build(BuildContext context) {
    final platz = context.watch<Arbeitsplatz>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SegmentedButton<_Seite>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: _Seite.aufgabe,
                label: Text('Aufgabe'),
              ),
              ButtonSegment(
                value: _Seite.ergebnis,
                label: Text(
                  platz.ergebnis?.prozent != null
                      ? 'Ergebnis · ${platz.ergebnis!.prozent!.toStringAsFixed(0)} %'
                      : 'Ergebnis',
                ),
              ),
            ],
            selected: {seite},
            onSelectionChanged: (s) => onSeite(s.first),
          ),
        ),
        const Divider(),
        Expanded(
          child: seite == _Seite.aufgabe
              ? _AufgabeSeite(platz: platz)
              : const ErgebnisAnsicht(),
        ),
      ],
    );
  }
}

class _AufgabeSeite extends StatelessWidget {
  const _AufgabeSeite({required this.platz});
  final Arbeitsplatz platz;

  @override
  Widget build(BuildContext context) {
    final text = platz.aufgabe.aufgabenstellung;
    if (text == null || text.trim().isEmpty) {
      return Center(
        child: Text(
          'Keine Aufgabenstellung.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      child: Aufgabenstellung(
        text: text,
        ergebnis: platz.ergebnis,
        artemis: platz.artemis,
      ),
    );
  }
}

class _Stand extends StatelessWidget {
  const _Stand({required this.platz});
  final Arbeitsplatz platz;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final (text, farbe, laeuft) = switch (platz.bau) {
      Bauzustand.speichert => ('speichert …', f.onSurfaceVariant, true),
      Bauzustand.gibtAb => ('gibt ab …', f.primary, true),
      Bauzustand.baut => ('Tests laufen …', f.primary, true),
      _ when platz.verbindung == Verbindung.offline => (
        'offline',
        f.error,
        false,
      ),
      _ when platz.hatUngesichertes => ('ungesichert', f.tertiary, false),
      _ => ('gespeichert', f.onSurfaceVariant, false),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (laeuft)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: farbe),
            ),
          ),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: farbe,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _Umschalter extends StatelessWidget {
  const _Umschalter({
    required this.symbol,
    required this.hinweis,
    required this.an,
    required this.onTap,
  });
  final IconData symbol;
  final String hinweis;
  final bool an;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: hinweis,
    isSelected: an,
    onPressed: onTap,
    icon: Icon(symbol),
  );
}

class _Menue extends StatelessWidget {
  const _Menue({required this.platz, required this.onKuerzel});
  final Arbeitsplatz platz;
  final VoidCallback onKuerzel;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TastaturWaechter>();
    return PopupMenuButton<String>(
      tooltip: 'Mehr',
      onSelected: (w) {
        switch (w) {
          case 'auto':
            t.manuell = null;
          case 'an':
            t.manuell = true;
          case 'aus':
            t.manuell = false;
          case 'kuerzel':
            onKuerzel();
          case 'neu':
            platz.laden();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'neu', child: Text('Vom Server neu laden')),
        const PopupMenuItem(value: 'kuerzel', child: Text('Tastenkürzel')),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: 'auto',
          checked: t.manuell == null,
          child: Text(
            'Tastatur erkennen (${t.vorhanden ? 'erkannt' : 'keine'})',
          ),
        ),
        CheckedPopupMenuItem(
          value: 'an',
          checked: t.manuell == true,
          child: const Text('Mit Tastatur arbeiten'),
        ),
        CheckedPopupMenuItem(
          value: 'aus',
          checked: t.manuell == false,
          child: const Text('Zeichenleiste zeigen'),
        ),
      ],
    );
  }
}

class _OfflineBalken extends StatelessWidget {
  const _OfflineBalken();

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: f.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        'Offline – Änderungen werden auf dem Gerät gesichert. eduVPN verbinden zum Speichern.',
        style: TextStyle(color: f.onErrorContainer, fontSize: 13),
      ),
    );
  }
}

class _NichtGestartet extends StatelessWidget {
  const _NichtGestartet({required this.platz});
  final Arbeitsplatz platz;

  @override
  Widget build(BuildContext context) {
    final a = platz.aufgabe;
    return LayoutBuilder(
      builder: (context, c) {
        final knopf = Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton.icon(
            onPressed: a.nochNichtOffen || platz.laedt ? null : platz.starten,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Aufgabe starten'),
            style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
          ),
        );
        final text = a.aufgabenstellung;
        return Column(
          children: [
            if (platz.ladefehler != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  platz.ladefehler!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            knopf,
            if (text != null)
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                      child: Aufgabenstellung(
                        text: text,
                        ergebnis: null,
                        artemis: platz.artemis,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Fehler extends StatelessWidget {
  const _Fehler({required this.text, required this.onNochmal});
  final String text;
  final VoidCallback onNochmal;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 44, color: f.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onNochmal,
            child: const Text('Erneut versuchen'),
          ),
        ],
      ),
    );
  }
}

class _Schnellauswahl extends StatefulWidget {
  const _Schnellauswahl({required this.dateien});
  final List<String> dateien;

  @override
  State<_Schnellauswahl> createState() => _SchnellauswahlState();
}

class _SchnellauswahlState extends State<_Schnellauswahl> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final f = _filter.toLowerCase();
    final treffer = widget.dateien
        .where((d) => _passt(d.toLowerCase(), f))
        .take(30)
        .toList();
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 80, left: 24, right: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Datei',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _filter = v),
                onSubmitted: (_) {
                  if (treffer.isNotEmpty) Navigator.pop(context, treffer.first);
                },
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in treffer)
                    ListTile(
                      dense: true,
                      title: Text(d.split('/').last),
                      subtitle: Text(d),
                      onTap: () => Navigator.pop(context, d),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Buchstaben in Reihenfolge, nicht zusammenhängend – wie in Xcode oder VS Code.
  static bool _passt(String text, String muster) {
    var i = 0;
    for (final c in muster.split('')) {
      i = text.indexOf(c, i);
      if (i < 0) return false;
      i++;
    }
    return true;
  }
}
