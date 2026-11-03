import 'package:flutter/foundation.dart';

import '../api/klient.dart';
import '../api/modelle.dart';
import '../werkzeuge/diff.dart';
import 'arbeitsplatz.dart';

enum Zeilenart { eingabe, normal, leise, erfolg, fehler, hinzu, weg, kopf }

class Konsolenzeile {
  const Konsolenzeile(this.text, [this.art = Zeilenart.normal]);
  final String text;
  final Zeilenart art;
}

/// Eine kleine Shell über dem Repository auf dem Server.
///
/// Auf dem Tablet gibt es kein `git`-Programm. Die Befehle hier sprechen
/// deshalb die Repository-Schnittstelle von Artemis an, die auf dem Server
/// echtes git ausführt. Daraus folgt eine Abweichung, die `help` auch nennt:
/// Artemis kennt keinen lokalen Commit. `git commit` speichert in die
/// Arbeitskopie, erst `git push` committet und gibt ab.
class Konsole extends ChangeNotifier {
  Konsole(this.platz) {
    _aus('Code It! Konsole – „help" zeigt die Befehle.', Zeilenart.leise);
    if (_demoBefehle.isNotEmpty) _demoAbspielen();
  }

  /// Nur für Bildschirmfotos: `--dart-define=DEMO_BEFEHLE="git status;git diff"`.
  static const _demoBefehle = String.fromEnvironment('DEMO_BEFEHLE');

  Future<void> _demoAbspielen() async {
    while (platz.laedt) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    for (final b in _demoBefehle.split(';')) {
      await eingeben(b);
    }
  }

  final Arbeitsplatz platz;
  final List<Konsolenzeile> zeilen = [];
  final List<String> verlauf = [];
  bool beschaeftigt = false;

  /// Wartet auf „j" oder „n".
  Future<void> Function()? _rueckfrage;
  String? get rueckfrage => _rueckfrage == null ? null : '[j/n]';

  void _aus(String text, [Zeilenart art = Zeilenart.normal]) {
    for (final z in text.split('\n')) {
      zeilen.add(Konsolenzeile(z, art));
    }
    if (zeilen.length > 4000) zeilen.removeRange(0, zeilen.length - 4000);
  }

  Future<void> eingeben(String roh) async {
    final eingabe = roh.trim();
    if (_rueckfrage != null) {
      final weiter = _rueckfrage!;
      _rueckfrage = null;
      _aus(eingabe, Zeilenart.eingabe);
      if (const ['j', 'ja', 'y', 'yes'].contains(eingabe.toLowerCase())) {
        await _ausfuehren(weiter);
      } else {
        _aus('Abgebrochen.', Zeilenart.leise);
      }
      notifyListeners();
      return;
    }
    if (eingabe.isEmpty) return;
    verlauf.add(eingabe);
    _aus('\$ $eingabe', Zeilenart.eingabe);
    notifyListeners();
    await _ausfuehren(() => _befehl(_zerlegen(eingabe)));
    notifyListeners();
  }

  Future<void> _ausfuehren(Future<void> Function() f) async {
    beschaeftigt = true;
    notifyListeners();
    try {
      await f();
    } on NetzFehler catch (e) {
      _aus(e.grund, Zeilenart.fehler);
    } on ArtemisFehler catch (e) {
      _aus('${e.status}: ${e.meldung}', Zeilenart.fehler);
    } catch (e) {
      _aus('$e', Zeilenart.fehler);
    }
    beschaeftigt = false;
  }

  void leeren() {
    zeilen.clear();
    notifyListeners();
  }

  /// Leerzeichen trennen, Anführungszeichen halten zusammen.
  static List<String> _zerlegen(String s) {
    final teile = <String>[];
    final b = StringBuffer();
    String? quote;
    for (final c in s.split('')) {
      if (quote != null) {
        if (c == quote) {
          quote = null;
        } else {
          b.write(c);
        }
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == ' ') {
        if (b.isNotEmpty) teile.add(b.toString());
        b.clear();
      } else {
        b.write(c);
      }
    }
    if (b.isNotEmpty) teile.add(b.toString());
    return teile;
  }

  Future<void> _befehl(List<String> a) async {
    switch (a.first) {
      case 'help' || 'hilfe' || '?':
        _hilfe();
      case 'clear' || 'cls':
        zeilen.clear();
      case 'ls':
        _ls(a.length > 1 ? a[1] : '');
      case 'tree':
        _baum();
      case 'cat':
        _brauche(a, 2, 'cat <datei>');
        _aus(platz.inhalt(_pfad(a[1])));
      case 'open' || 'code':
        _brauche(a, 2, 'open <datei>');
        platz.oeffnen(_pfad(a[1]));
      case 'touch':
        _brauche(a, 2, 'touch <datei>');
        await platz.neueDatei(a[1]);
        _aus('angelegt: ${a[1]}', Zeilenart.erfolg);
      case 'mkdir':
        _brauche(a, 2, 'mkdir <ordner>');
        await platz.neuerOrdner(a[1]);
        _aus('angelegt: ${a[1]}/', Zeilenart.erfolg);
      case 'rm':
        _brauche(a, 2, 'rm <pfad>');
        final p = _pfad(a.last);
        _fragen('$p löschen?', () async {
          await platz.loeschen(p);
          _aus('gelöscht: $p', Zeilenart.erfolg);
        });
      case 'mv':
        _brauche(a, 3, 'mv <pfad> <neuer name>');
        await platz.umbenennen(_pfad(a[1]), a[2].split('/').last);
        _aus('umbenannt', Zeilenart.erfolg);
      case 'test' || 'tests' || 'ergebnis':
        await platz.ergebnisNeuLaden();
        _ergebnis();
      case 'build' || 'log':
        _buildLog();
      case 'abgeben' || 'submit':
        await _git(['push']);
      case 'git':
        await _git(a.skip(1).toList());
      default:
        _aus(
          'Unbekannter Befehl: ${a.first}. „help" zeigt, was es gibt.',
          Zeilenart.fehler,
        );
    }
  }

  Future<void> _git(List<String> a) async {
    if (a.isEmpty) return _hilfe();
    switch (a.first) {
      case 'status' || 'st':
        _status();
      case 'diff':
        _diff(a.length > 1 ? _pfad(a.last) : null);
      case 'add':
        _aus(
          'Nicht nötig: Artemis nimmt beim Abgeben alle geänderten Dateien mit.',
          Zeilenart.leise,
        );
      case 'commit':
        final n = platz.geaenderte.length;
        if (n == 0) return _aus('Nichts zu speichern.', Zeilenart.leise);
        if (a.contains('-m')) {
          _aus(
            'Artemis setzt die Commit-Nachricht selbst; -m wird ignoriert.',
            Zeilenart.leise,
          );
        }
        if (await platz.speichern()) {
          _aus(
            '$n Datei${n == 1 ? '' : 'en'} auf dem Server gespeichert. '
            'Abgegeben ist erst nach „git push".',
            Zeilenart.erfolg,
          );
        } else {
          _aus(platz.meldung ?? 'Speichern fehlgeschlagen.', Zeilenart.fehler);
        }
      case 'push':
        final frist = platz.aufgabe.faellig;
        final spaet = frist != null && frist.isBefore(DateTime.now());
        _fragen(
          spaet
              ? 'Die Frist ist vorbei. Trotzdem abgeben?'
              : 'Abgeben? Das committet, pusht und startet die Tests.',
          () async {
            await platz.abgeben();
            if (platz.bau == Bauzustand.fehler) {
              _aus(platz.meldung ?? 'Abgabe fehlgeschlagen.', Zeilenart.fehler);
            } else {
              _aus(
                'Abgegeben. Die Tests laufen; „test" zeigt danach das Ergebnis.',
                Zeilenart.erfolg,
              );
            }
          },
        );
      case 'pull':
        final geaendert = await platz.holen();
        if (geaendert.isEmpty) {
          _aus('Schon aktuell.', Zeilenart.leise);
        } else {
          _aus('Geholt: ${geaendert.join(', ')}', Zeilenart.erfolg);
          final eigene = geaendert.where(platz.istGeaendert).toList();
          if (eigene.isNotEmpty) {
            _aus(
              'Achtung, lokal ungesichert und auf dem Server geändert: ${eigene.join(', ')}',
              Zeilenart.fehler,
            );
          }
        }
      case 'log':
        final c = await platz.artemis.verlauf(platz.teilnahme!.id);
        if (c.isEmpty) return _aus('Kein Verlauf.', Zeilenart.leise);
        for (final k in c.take(30)) {
          final kurz = k.hash.length > 7 ? k.hash.substring(0, 7) : k.hash;
          _aus('$kurz  ${_datum(k.zeit)}  ${k.nachricht ?? ''}');
        }
      case 'restore' || 'checkout':
        final ziele = a
            .skip(1)
            .where((x) => x != '--' && !x.startsWith('-'))
            .toList();
        if (ziele.isEmpty) {
          return _aus('Nutzung: git restore <datei>', Zeilenart.fehler);
        }
        for (final z in ziele) {
          platz.verwerfen(_pfad(z));
          _aus('verworfen: ${_pfad(z)}', Zeilenart.erfolg);
        }
      case 'reset':
        if (!a.contains('--hard')) {
          return _aus(
            'Nur „git reset --hard" wird unterstützt.',
            Zeilenart.fehler,
          );
        }
        _fragen(
          'Alle Änderungen seit der letzten Abgabe verwerfen, auch auf dem Server?',
          () async {
            await platz.zuruecksetzen();
            _aus('Zurückgesetzt auf den letzten Commit.', Zeilenart.erfolg);
          },
        );
      default:
        _aus(
          'git ${a.first} gibt es hier nicht. „help" zeigt die unterstützten Befehle.',
          Zeilenart.fehler,
        );
    }
  }

  void _fragen(String frage, Future<void> Function() dann) {
    _aus('$frage [j/n]', Zeilenart.kopf);
    _rueckfrage = dann;
  }

  void _brauche(List<String> a, int n, String nutzung) {
    if (a.length < n) throw 'Nutzung: $nutzung';
  }

  /// Nimmt auch nur den Dateinamen, wenn er eindeutig ist.
  String _pfad(String eingabe) {
    if (platz.eintraege.containsKey(eingabe)) return eingabe;
    final treffer = platz.eintraege.keys
        .where((p) => p.split('/').last == eingabe)
        .toList();
    if (treffer.length == 1) return treffer.first;
    if (treffer.length > 1) throw 'Mehrdeutig: ${treffer.join(', ')}';
    throw 'Nicht gefunden: $eingabe';
  }

  void _hilfe() {
    _aus('''
Dateien
  ls [ordner]          Inhalt auflisten
  tree                 alle Dateien
  cat <datei>          Datei ausgeben
  open <datei>         im Editor öffnen
  touch / mkdir        Datei / Ordner anlegen
  mv <pfad> <name>     umbenennen
  rm <pfad>            löschen

git (läuft auf dem Artemis-Server)
  git status           was geändert ist
  git diff [datei]     Änderungen zeilenweise
  git commit           auf dem Server speichern, ohne abzugeben
  git push             abgeben: commit + push, startet die Tests
  git pull             Stand vom Server holen
  git log              Verlauf
  git restore <datei>  eigene Änderung verwerfen
  git reset --hard     alles auf den letzten Commit zurück

Sonst
  test                 letztes Testergebnis
  build                Build-Log der letzten Abgabe
  clear                Konsole leeren''', Zeilenart.leise);
  }

  void _ls(String ordner) {
    final o = ordner.endsWith('/')
        ? ordner.substring(0, ordner.length - 1)
        : ordner;
    final vorne = o.isEmpty ? '' : '$o/';
    final kinder = <String>{};
    for (final e in platz.eintraege.entries) {
      if (!e.key.startsWith(vorne) || e.key == o) continue;
      final rest = e.key.substring(vorne.length);
      final teil = rest.split('/').first;
      final istOrdner = rest.contains('/') || e.value == Eintragsart.ordner;
      kinder.add(istOrdner ? '$teil/' : teil);
    }
    if (kinder.isEmpty) return _aus('leer', Zeilenart.leise);
    final s = kinder.toList()..sort();
    for (final k in s) {
      _aus(k, k.endsWith('/') ? Zeilenart.kopf : Zeilenart.normal);
    }
  }

  void _baum() {
    final dateien =
        platz.eintraege.entries
            .where((e) => e.value == Eintragsart.datei)
            .map((e) => e.key)
            .toList()
          ..sort();
    for (final d in dateien) {
      _aus(d, platz.istGeaendert(d) ? Zeilenart.hinzu : Zeilenart.normal);
    }
  }

  void _status() {
    final g = platz.geaenderte;
    if (g.isEmpty) {
      _aus('Nichts geändert seit dem letzten Speichern.', Zeilenart.leise);
    } else {
      _aus('Ungesicherte Änderungen:');
      for (final p in g) {
        final neu = platz.serverInhalt(p) == null;
        _aus('  ${neu ? 'neu:      ' : 'geändert: '}$p', Zeilenart.hinzu);
      }
      _aus(
        '„git commit" speichert auf dem Server, „git push" gibt ab.',
        Zeilenart.leise,
      );
    }
    if (platz.verbindung == Verbindung.offline) {
      _aus(
        'Offline – Änderungen liegen nur auf diesem Gerät.',
        Zeilenart.fehler,
      );
    }
  }

  void _diff(String? datei) {
    final ziele = datei == null ? platz.geaenderte : [datei];
    if (ziele.isEmpty) return _aus('Keine Änderungen.', Zeilenart.leise);
    for (final p in ziele) {
      final hunks = alsHunks(
        zeilenDiff(platz.serverInhalt(p) ?? '', platz.inhalt(p)),
      );
      if (hunks.isEmpty) continue;
      _aus('--- a/$p\n+++ b/$p', Zeilenart.kopf);
      for (final h in hunks) {
        _aus(
          h,
          h.startsWith('@@')
              ? Zeilenart.kopf
              : h.startsWith('+')
              ? Zeilenart.hinzu
              : h.startsWith('-')
              ? Zeilenart.weg
              : Zeilenart.normal,
        );
      }
    }
  }

  void _ergebnis() {
    final e = platz.ergebnis;
    if (e == null) return _aus('Noch kein Ergebnis.', Zeilenart.leise);
    if (e.buildFehlgeschlagen) {
      _aus('Build fehlgeschlagen. „build" zeigt das Log.', Zeilenart.fehler);
      return;
    }
    _aus(
      '${e.prozent?.toStringAsFixed(0) ?? '?'} %  ·  '
      '${e.bestanden ?? '?'} von ${e.tests ?? '?'} Tests bestanden  ·  ${_datum(e.fertig)}',
    );
    for (final r in e.rueckmeldungen) {
      _aus(
        '${r.positiv == true ? '✓' : '✗'} ${r.titel}',
        r.positiv == true ? Zeilenart.erfolg : Zeilenart.fehler,
      );
      if (r.positiv != true && r.detail != null) {
        _aus('    ${r.detail}', Zeilenart.leise);
      }
    }
  }

  void _buildLog() {
    if (platz.buildLog.isEmpty) return _aus('Kein Build-Log.', Zeilenart.leise);
    for (final z in platz.buildLog) {
      final fehler = z.text.contains('ERROR') || z.text.contains('error:');
      _aus(z.text, fehler ? Zeilenart.fehler : Zeilenart.normal);
    }
  }

  static String _datum(DateTime? d) {
    if (d == null) return '';
    String zwei(int n) => n.toString().padLeft(2, '0');
    return '${zwei(d.day)}.${zwei(d.month)}. ${zwei(d.hour)}:${zwei(d.minute)}';
  }
}
