import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/klient.dart';
import '../api/modelle.dart';
import '../zustand/sitzung.dart';
import 'arbeitsplatz_ansicht.dart';
import 'thema.dart';

class Kursuebersicht extends StatefulWidget {
  const Kursuebersicht({super.key});

  @override
  State<Kursuebersicht> createState() => _KursuebersichtState();
}

class _KursuebersichtState extends State<Kursuebersicht> {
  List<Kurs>? _kurse;
  String? _fehler;
  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    final artemis = context.read<Sitzung>().artemis;
    try {
      final kurse = await artemis.kurse();
      final mitAufgaben = await Future.wait(
        kurse.map(
          (k) async => k.aufgaben.isNotEmpty
              ? k
              : k.mitAufgaben(await artemis.aufgabenVon(k)),
        ),
      );
      if (mounted) setState(() => _kurse = mitAufgaben);
      _demoOeffnen(mitAufgaben);
    } on NetzFehler catch (e) {
      if (mounted) setState(() => _fehler = e.grund);
    } on ArtemisFehler catch (e) {
      if (mounted) setState(() => _fehler = e.meldung);
    } catch (e, stapel) {
      // Eine Antwort, die anders aussieht als erwartet, darf nicht in einem
      // endlosen Ladekreis enden.
      unawaited(ArtemisKlient.protokolliere('Kurse lesen: $e\n$stapel'));
      if (mounted) {
        setState(() => _fehler = 'Antwort von Artemis nicht lesbar: $e');
      }
    }
    if (mounted) setState(() => _laedt = false);
  }

  /// Nur für Bildschirmfotos im Demo-Modus: `--dart-define=DEMO_AUFGABE=11`.
  static const _demoAufgabe = int.fromEnvironment('DEMO_AUFGABE');
  bool _demoGeoeffnet = false;

  void _demoOeffnen(List<Kurs> kurse) {
    if (_demoAufgabe == 0 || _demoGeoeffnet) return;
    _demoGeoeffnet = true;
    final a = kurse
        .expand((k) => k.aufgaben)
        .where((a) => a.id == _demoAufgabe);
    if (a.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _oeffnen(a.first));
    }
  }

  void _oeffnen(Aufgabe a) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => ArbeitsplatzAnsicht(aufgabe: a)),
        )
        .then((_) => _laden());
  }

  @override
  Widget build(BuildContext context) {
    final sitzung = context.watch<Sitzung>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurse'),
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _laedt ? null : _laden,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: sitzung.nutzer?.name ?? 'Konto',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (w) {
              if (w == 'ab') sitzung.abmelden();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  sitzung.nutzer?.name ?? sitzung.nutzer?.login ?? '',
                ),
              ),
              const PopupMenuItem(value: 'ab', child: Text('Abmelden')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _laden, child: _inhalt(context)),
    );
  }

  Widget _inhalt(BuildContext context) {
    if (_kurse == null && _laedt) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_kurse == null) {
      return _Hinweis(
        symbol: Icons.wifi_off_rounded,
        text: _fehler ?? 'Keine Kurse.',
        knopf: FilledButton.tonal(
          onPressed: _laden,
          child: const Text('Erneut versuchen'),
        ),
      );
    }
    if (_kurse!.isEmpty) {
      return const _Hinweis(
        symbol: Icons.school_outlined,
        text: 'Keine Kurse.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        if (_fehler != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _fehler!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        for (final k in _kurse!) _KursAbschnitt(kurs: k, onOeffnen: _oeffnen),
      ],
    );
  }
}

class _KursAbschnitt extends StatefulWidget {
  const _KursAbschnitt({required this.kurs, required this.onOeffnen});
  final Kurs kurs;
  final ValueChanged<Aufgabe> onOeffnen;

  @override
  State<_KursAbschnitt> createState() => _KursAbschnittState();
}

class _KursAbschnittState extends State<_KursAbschnitt> {
  bool _vorbeiOffen = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final aufgaben = [...widget.kurs.aufgaben]..sort(_reihenfolge);
    final aktuell = aufgaben.where((a) => !a.vorbei).toList();
    final vorbei = aufgaben.where((a) => a.vorbei).toList().reversed.toList();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _farbe(widget.kurs.farbe) ?? t.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.kurs.titel,
                  style: t.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (aktuell.isEmpty && vorbei.isEmpty)
            Text(
              'Keine Aufgaben.',
              style: TextStyle(color: t.colorScheme.onSurfaceVariant),
            ),
          _Raster(aufgaben: aktuell, onOeffnen: widget.onOeffnen),
          if (vorbei.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => setState(() => _vorbeiOffen = !_vorbeiOffen),
              icon: Icon(_vorbeiOffen ? Icons.expand_less : Icons.expand_more),
              label: Text('Vorbei (${vorbei.length})'),
            ),
            if (_vorbeiOffen)
              _Raster(aufgaben: vorbei, onOeffnen: widget.onOeffnen),
          ],
        ],
      ),
    );
  }

  static int _reihenfolge(Aufgabe a, Aufgabe b) {
    final fa = a.faellig ?? DateTime(9999), fb = b.faellig ?? DateTime(9999);
    return fa.compareTo(fb);
  }

  static Color? _farbe(String? hex) {
    if (hex == null || !hex.startsWith('#') || hex.length != 7) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
}

class _Raster extends StatelessWidget {
  const _Raster({required this.aufgaben, required this.onOeffnen});
  final List<Aufgabe> aufgaben;
  final ValueChanged<Aufgabe> onOeffnen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final spalten = (c.maxWidth / 320).floor().clamp(1, 4);
        final breite = (c.maxWidth - (spalten - 1) * 12) / spalten;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final a in aufgaben)
              SizedBox(
                width: breite,
                child: _Karte(aufgabe: a, onTap: () => onOeffnen(a)),
              ),
          ],
        );
      },
    );
  }
}

class _Karte extends StatelessWidget {
  const _Karte({required this.aufgabe, required this.onTap});
  final Aufgabe aufgabe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = t.colorScheme;
    final a = aufgabe;
    final geht = a.istProgrammierung && !a.nochNichtOffen;
    final e = a.teilnahme?.letztes;

    return Opacity(
      opacity: geht ? 1 : 0.55,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: f.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: geht ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_symbol(a.typ), size: 20, color: f.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.titel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (e != null) _Punkte(ergebnis: e),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _frist(a),
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: _bald(a) ? f.error : f.onSurfaceVariant,
                    fontWeight: _bald(a) ? FontWeight.w600 : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (a.punkte != null) '${_zahl(a.punkte!)} Punkte',
                    if (a.sprache != null) _sprache(a.sprache!),
                    if (!a.istProgrammierung) 'nur im Browser',
                  ].join(' · '),
                  style: t.textTheme.bodySmall?.copyWith(
                    color: f.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _bald(Aufgabe a) =>
      a.faellig != null &&
      !a.vorbei &&
      a.faellig!.difference(DateTime.now()) < const Duration(hours: 48);

  static String _frist(Aufgabe a) {
    final jetzt = DateTime.now();
    if (a.nochNichtOffen) {
      return 'ab ${DateFormat('E d. MMM, HH:mm', 'de').format(a.start!)}';
    }
    if (a.faellig == null) return 'ohne Frist';
    final d = a.faellig!;
    final text = DateFormat('E d. MMM, HH:mm', 'de').format(d);
    if (d.isBefore(jetzt)) return 'war fällig $text';
    final rest = d.difference(jetzt);
    if (rest.inHours < 24) {
      return 'fällig in ${rest.inHours} h ${rest.inMinutes % 60} min';
    }
    if (rest.inDays < 7) {
      return 'fällig in ${rest.inDays} ${rest.inDays == 1 ? 'Tag' : 'Tagen'} · $text';
    }
    return 'fällig $text';
  }

  static String _zahl(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toString();

  static String _sprache(String s) => switch (s) {
    'JAVA' => 'Java',
    'PYTHON' => 'Python',
    'C' => 'C',
    'C_PLUS_PLUS' => 'C++',
    'C_SHARP' => 'C#',
    'KOTLIN' => 'Kotlin',
    'SWIFT' => 'Swift',
    'HASKELL' => 'Haskell',
    'JAVASCRIPT' => 'JavaScript',
    'TYPESCRIPT' => 'TypeScript',
    'RUST' => 'Rust',
    'GO' => 'Go',
    'BASH' => 'Bash',
    'RUBY' => 'Ruby',
    'DART' => 'Dart',
    'R' => 'R',
    _ => s,
  };

  static IconData _symbol(Aufgabentyp t) => switch (t) {
    Aufgabentyp.programmierung => Icons.code_rounded,
    Aufgabentyp.text => Icons.notes_rounded,
    Aufgabentyp.modellierung => Icons.account_tree_outlined,
    Aufgabentyp.quiz => Icons.quiz_outlined,
    Aufgabentyp.datei => Icons.upload_file_outlined,
    Aufgabentyp.sonstige => Icons.task_outlined,
  };
}

class _Punkte extends StatelessWidget {
  const _Punkte({required this.ergebnis});
  final Ergebnis ergebnis;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final p = ergebnis.prozent ?? 0;
    final farbe = ergebnis.buildFehlgeschlagen
        ? f.durchgefallen
        : p >= 100
        ? f.bestanden
        : p > 0
        ? f.tertiary
        : f.durchgefallen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ergebnis.buildFehlgeschlagen ? 'Build ✗' : '${p.toStringAsFixed(0)} %',
        style: TextStyle(
          color: farbe,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _Hinweis extends StatelessWidget {
  const _Hinweis({required this.symbol, required this.text, this.knopf});
  final IconData symbol;
  final String text;
  final Widget? knopf;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(symbol, size: 44, color: f.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: f.onSurfaceVariant),
        ),
        if (knopf != null) ...[
          const SizedBox(height: 16),
          Center(child: knopf),
        ],
      ],
    );
  }
}
