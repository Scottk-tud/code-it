import 'dart:async';
import 'dart:typed_data';

import 'artemis.dart';
import 'modelle.dart';

/// Ein Kurs mit einer Java-Aufgabe, ganz ohne Server.
///
/// Gestartet mit `--dart-define=DEMO=true`. Dient den Bildschirmfotos und dem
/// Durchklicken, ohne dass jemand sein Artemis-Passwort eintippen muss. Die
/// „Tests" prüfen grob, ob die Methoden noch `return 0` bzw. `null` liefern.
class DemoArtemis implements Artemis {
  final Map<String, String> _repo = {
    'src/de/tud/inf/Bruch.java': _bruch,
    'src/de/tud/inf/Main.java': _main,
    'test/de/tud/inf/BruchTest.java': '// Die Tests liegen auf dem Server.\n',
    'README.md': '# Brüche\n\nSiehe Aufgabenstellung.\n',
  };
  late Map<String, String> _commit = Map.of(_repo);
  final List<Ergebnis> _ergebnisse = [];
  final List<Commit> _verlauf = [
    Commit(
      hash: 'a3f9c2e1d0',
      nachricht: 'Initial commit',
      autor: 'Artemis',
      zeit: DateTime(2026, 10, 13, 9),
    ),
  ];

  /// `--dart-define=DEMO_NEU=true` zeigt die Aufgabe noch nicht gestartet.
  Teilnahme? _teilnahme = const bool.fromEnvironment('DEMO_NEU')
      ? null
      : const Teilnahme(id: 110, zustand: 'INITIALIZED');
  DateTime? _bautBis;

  Future<void> _kurz() => Future.delayed(const Duration(milliseconds: 250));

  @override
  Future<String> anmelden(String name, String passwort) async => 'demo';

  @override
  Future<Nutzer?> konto() async => const Nutzer(
    login: 'demo',
    name: 'Demo Studentin',
    email: 'demo@mailbox.tu-dresden.de',
  );

  @override
  Future<List<Kurs>> kurse() async {
    await _kurz();
    return [
      Kurs(
        id: 1,
        titel: 'Softwaretechnologie WS 26/27',
        kurzname: 'ST1WS2627',
        farbe: '#2F6F62',
        aufgaben: _aufgaben(),
      ),
      Kurs(
        id: 2,
        titel: 'Algorithmen und Datenstrukturen',
        kurzname: 'AUDWS2627',
        farbe: '#8A5A2B',
        aufgaben: [
          Aufgabe(
            id: 21,
            titel: 'Sortieren durch Einfügen',
            typ: Aufgabentyp.programmierung,
            start: DateTime.now().add(const Duration(days: 3)),
            faellig: DateTime.now().add(const Duration(days: 17)),
            punkte: 10,
            sprache: 'JAVA',
          ),
        ],
      ),
    ];
  }

  List<Aufgabe> _aufgaben() => [
    _aufgabeBruch(),
    Aufgabe(
      id: 12,
      titel: 'Hallo Welt',
      typ: Aufgabentyp.programmierung,
      faellig: DateTime.now().subtract(const Duration(days: 9)),
      punkte: 2,
      sprache: 'JAVA',
      teilnahme: Teilnahme(
        id: 120,
        zustand: 'FINISHED',
        ergebnisse: [
          Ergebnis(
            id: 1200,
            prozent: 100,
            erfolgreich: true,
            tests: 2,
            bestanden: 2,
            fertig: DateTime.now().subtract(const Duration(days: 10)),
          ),
        ],
      ),
    ),
    Aufgabe(
      id: 13,
      titel: 'Klassendiagramm Taxi',
      typ: Aufgabentyp.modellierung,
      faellig: DateTime.now().add(const Duration(days: 12)),
      punkte: 5,
    ),
  ];

  Aufgabe _aufgabeBruch() => Aufgabe(
    id: 11,
    titel: 'Brüche',
    typ: Aufgabentyp.programmierung,
    kursId: 1,
    start: DateTime.now().subtract(const Duration(days: 3)),
    faellig: DateTime.now().add(const Duration(days: 4, hours: 5)),
    punkte: 8,
    sprache: 'JAVA',
    aufgabenstellung: _aufgabenstellung,
    teilnahme: _teilnahme == null
        ? null
        : Teilnahme(
            id: _teilnahme!.id,
            zustand: 'INITIALIZED',
            ergebnisse: _ergebnisse,
          ),
  );

  @override
  Future<List<Aufgabe>> aufgabenVon(Kurs kurs) async => kurs.aufgaben;

  @override
  Future<Aufgabe> aufgabe(int id) async {
    await _kurz();
    if (id == 11) return _aufgabeBruch();
    return (await kurse())
        .expand((k) => k.aufgaben)
        .firstWhere((a) => a.id == id);
  }

  @override
  Future<Teilnahme> starten(Aufgabe aufgabe) async {
    await _kurz();
    return _teilnahme = const Teilnahme(id: 110, zustand: 'INITIALIZED');
  }

  @override
  Future<Teilnahme> fortsetzen(Aufgabe aufgabe, Teilnahme teilnahme) async =>
      teilnahme;

  @override
  Future<Map<String, Eintragsart>> dateien(int teilnahme) async {
    final e = <String, Eintragsart>{};
    for (final p in _repo.keys) {
      final teile = p.split('/');
      for (var i = 1; i < teile.length; i++) {
        e[teile.take(i).join('/')] = Eintragsart.ordner;
      }
      e[p] = Eintragsart.datei;
    }
    return e;
  }

  @override
  Future<Map<String, String>> inhalte(int teilnahme) async => Map.of(_repo);

  @override
  Future<Speicherstand> speichern(
    int teilnahme,
    Map<String, String> dateien, {
    required bool abgeben,
  }) async {
    await _kurz();
    _repo.addAll(dateien);
    if (abgeben) {
      _commit = Map.of(_repo);
      _verlauf.insert(
        0,
        Commit(
          hash: DateTime.now().millisecondsSinceEpoch.toRadixString(16),
          nachricht: 'Changes by Online Editor',
          autor: 'demo',
          zeit: DateTime.now(),
        ),
      );
      _bautBis = DateTime.now().add(const Duration(seconds: 6));
    }
    return const Speicherstand();
  }

  @override
  Future<void> neueDatei(int teilnahme, String pfad) async => _repo[pfad] = '';
  @override
  Future<void> neuerOrdner(int teilnahme, String pfad) async {}
  @override
  Future<void> umbenennen(int teilnahme, String pfad, String neuerName) async {
    final neu = pfad.contains('/')
        ? '${pfad.substring(0, pfad.lastIndexOf('/'))}/$neuerName'
        : neuerName;
    _repo[neu] = _repo.remove(pfad) ?? '';
  }

  @override
  Future<void> loeschen(int teilnahme, String pfad) async =>
      _repo.removeWhere((p, _) => p == pfad || p.startsWith('$pfad/'));

  @override
  Future<void> holen(int teilnahme) async => _kurz();

  @override
  Future<void> zuruecksetzen(int teilnahme) async {
    _repo
      ..clear()
      ..addAll(_commit);
  }

  @override
  Future<bool> wirdGebaut(int teilnahme) async =>
      _bautBis != null && DateTime.now().isBefore(_bautBis!);

  @override
  Future<Ergebnis?> letztesErgebnis(int teilnahme) async {
    if (_bautBis != null && !DateTime.now().isBefore(_bautBis!)) {
      _bautBis = null;
      _ergebnisse.add(_bewerten());
    }
    return _ergebnisse.isEmpty ? null : _ergebnisse.last;
  }

  Ergebnis _bewerten() {
    final code = _commit['src/de/tud/inf/Bruch.java'] ?? '';
    final kompiliert =
        '{'.allMatches(code).length == '}'.allMatches(code).length;
    if (!kompiliert) {
      return Ergebnis(
        id: _ergebnisse.length + 1,
        prozent: 0,
        erfolgreich: false,
        buildFehlgeschlagen: true,
        fertig: DateTime.now(),
      );
    }
    final ggt = !RegExp(r'int ggT\([^)]*\)\s*\{\s*return 0;').hasMatch(code);
    final kuerzen = !RegExp(
      r'Bruch gekuerzt\(\)\s*\{\s*return null;',
    ).hasMatch(code);
    final plus = !RegExp(
      r'Bruch plus\([^)]*\)\s*\{\s*return null;',
    ).hasMatch(code);
    final r = [
      Rueckmeldung(
        test: 'testGgT',
        positiv: ggt,
        detail: ggt ? null : 'expected: <6> but was: <0>',
        art: 'AUTOMATIC',
      ),
      Rueckmeldung(
        test: 'testKuerzen',
        positiv: kuerzen,
        detail: kuerzen ? null : 'NullPointerException',
        art: 'AUTOMATIC',
      ),
      Rueckmeldung(
        test: 'testPlus',
        positiv: plus,
        detail: plus ? null : 'NullPointerException',
        art: 'AUTOMATIC',
      ),
      Rueckmeldung(test: 'testToString', positiv: true, art: 'AUTOMATIC'),
    ];
    final ok = r.where((x) => x.positiv == true).length;
    return Ergebnis(
      id: _ergebnisse.length + 1,
      prozent: ok / r.length * 100,
      erfolgreich: ok == r.length,
      tests: r.length,
      bestanden: ok,
      fertig: DateTime.now(),
      rueckmeldungen: r,
    );
  }

  @override
  Future<List<BuildZeile>> buildLog(int teilnahme) async => [
    BuildZeile(DateTime.now(), '[INFO] Compiling 2 source files'),
    BuildZeile(
      DateTime.now(),
      '[ERROR] src/de/tud/inf/Bruch.java:[41,2] reached end of file while parsing',
    ),
    BuildZeile(DateTime.now(), '[INFO] BUILD FAILURE'),
  ];

  @override
  Future<List<Commit>> verlauf(int teilnahme) async => _verlauf;

  @override
  Future<Uint8List?> plantUml(String quelle, {required bool dunkel}) async =>
      null;
}

const _aufgabenstellung = r'''
# Brüche

Implementieren Sie die Klasse `Bruch`, die einen gekürzten Bruch mit ganzzahligem Zähler und Nenner darstellt.

## Teil 1: Größter gemeinsamer Teiler

1. [task][Euklid](testGgT) Implementieren Sie `ggT(int a, int b)` mit dem euklidischen Algorithmus.

## Teil 2: Rechnen

2. [task][Kürzen](testKuerzen) `gekuerzt()` liefert einen neuen, vollständig gekürzten Bruch.
3. [task][Addieren](testPlus) `plus(Bruch b)` addiert zwei Brüche und kürzt das Ergebnis.
4. [task][Ausgabe](testToString) `toString()` gibt `3/4` aus, ganze Zahlen ohne Nenner.

> **Hinweis:** Der Nenner ist nie `0`. Ein negatives Vorzeichen steht immer im Zähler.
''';

const _bruch = '''package de.tud.inf;

public class Bruch {
    private final int zaehler;
    private final int nenner;

    public Bruch(int zaehler, int nenner) {
        if (nenner == 0) {
            throw new IllegalArgumentException("Nenner darf nicht 0 sein");
        }
        this.zaehler = zaehler;
        this.nenner = nenner;
    }

    static int ggT(int a, int b) {
        return 0;
    }

    public Bruch gekuerzt() {
        return null;
    }

    public Bruch plus(Bruch b) {
        return null;
    }

    @Override
    public String toString() {
        return nenner == 1 ? String.valueOf(zaehler) : zaehler + "/" + nenner;
    }
}
''';

const _main = '''package de.tud.inf;

public class Main {
    public static void main(String[] args) {
        Bruch a = new Bruch(1, 2);
        Bruch b = new Bruch(1, 3);
        System.out.println(a.plus(b));
    }
}
''';
