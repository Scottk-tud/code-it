import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:re_editor/re_editor.dart';

import '../api/artemis.dart';
import '../api/klient.dart';
import '../api/modelle.dart';
import '../konstanten.dart';

enum Verbindung { online, offline }

enum Bauzustand { ruhe, speichert, gibtAb, baut, fertig, fehler }

/// Eine geöffnete Aufgabe: Dateien, Puffer, Speichern, Abgeben, Ergebnis.
///
/// Drei Stände pro Datei, damit nichts verloren geht, wenn das VPN wegbricht:
/// - `server`: was zuletzt vom Server kam oder dort gespeichert wurde,
/// - der Puffer im Editor,
/// - der lokale Entwurf auf der Platte (Puffer, sobald er vom Server abweicht).
///
/// Speichern schreibt in die Arbeitskopie auf dem Server und ist folgenlos.
/// Abgeben committet und pusht – erst das startet die Tests und zählt.
class Arbeitsplatz extends ChangeNotifier {
  Arbeitsplatz({
    required this.artemis,
    required Aufgabe aufgabe,
    Future<Directory> Function()? ablage,
  }) : _aufgabe = aufgabe,
       _ablage = ablage ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _ablage;

  final Artemis artemis;
  Aufgabe _aufgabe;
  Aufgabe get aufgabe => _aufgabe;
  Teilnahme? get teilnahme => _aufgabe.teilnahme;

  Map<String, Eintragsart> eintraege = {};
  final Map<String, String> _server = {};
  final Map<String, CodeLineEditingController> _puffer = {};
  final List<String> offen = [];
  String? aktiv;

  Verbindung verbindung = Verbindung.online;
  Bauzustand bau = Bauzustand.ruhe;
  String? meldung;
  bool laedt = true;
  String? ladefehler;

  Ergebnis? ergebnis;
  List<BuildZeile> buildLog = const [];
  DateTime? zuletztGespeichert;

  Timer? _entwurfTimer, _serverTimer, _abfrageTimer;
  bool _verworfen = false;

  // ── Laden ────────────────────────────────────────────────────────────

  Future<void> laden() async {
    laedt = true;
    ladefehler = null;
    notifyListeners();
    try {
      _aufgabe = await artemis.aufgabe(_aufgabe.id);
      if (teilnahme == null) {
        laedt = false;
        notifyListeners();
        return;
      }
      if (teilnahme!.inaktiv) {
        final t = await artemis.fortsetzen(_aufgabe, teilnahme!);
        _aufgabe = _aufgabe.mit(teilnahme: t);
      }
      await _vomServer();
      verbindung = Verbindung.online;
      unawaited(_ergebnisLaden());
    } on NetzFehler {
      verbindung = Verbindung.offline;
      if (!await _ausCache()) {
        ladefehler = 'Offline, und diese Aufgabe war noch nie geöffnet.';
      }
    } on ArtemisFehler catch (e) {
      ladefehler = e.meldung;
    }
    await _entwuerfeAnwenden();
    if (aktiv == null && eintraege.isNotEmpty) {
      final erste = _ersteSinnvolleDatei();
      if (erste != null) oeffnen(erste);
    }
    laedt = false;
    notifyListeners();
  }

  Future<void> starten() async {
    laedt = true;
    notifyListeners();
    try {
      final t = await artemis.starten(_aufgabe);
      _aufgabe = _aufgabe.mit(teilnahme: t);
      await laden();
    } on Exception catch (e) {
      ladefehler = _text(e);
      laedt = false;
      notifyListeners();
    }
  }

  Future<void> _vomServer() async {
    final id = teilnahme!.id;
    final r = await Future.wait([artemis.dateien(id), artemis.inhalte(id)]);
    eintraege = Map.of(r[0] as Map<String, Eintragsart>);
    final inhalte = r[1] as Map<String, String>;
    _server
      ..clear()
      ..addAll(inhalte);
    for (final e in inhalte.entries) {
      final p = _puffer[e.key];
      if (p != null && !istGeaendert(e.key)) p.text = e.value;
    }
    await _cacheSchreiben();
  }

  String? _ersteSinnvolleDatei() {
    final dateien =
        eintraege.entries
            .where((e) => e.value == Eintragsart.datei)
            .map((e) => e.key)
            .toList()
          ..sort();
    const bevorzugt = [
      '.java',
      '.py',
      '.c',
      '.kt',
      '.swift',
      '.rs',
      '.hs',
      '.js',
      '.ts',
      '.dart',
    ];
    for (final p in dateien) {
      if (!p.contains('/test/') && bevorzugt.any(p.endsWith)) return p;
    }
    return dateien.isEmpty ? null : dateien.first;
  }

  // ── Puffer ───────────────────────────────────────────────────────────

  CodeLineEditingController puffer(String pfad) =>
      _puffer.putIfAbsent(pfad, () {
        final c = CodeLineEditingController.fromText(_server[pfad] ?? '');
        c.addListener(() => _geaendert(pfad));
        return c;
      });

  String inhalt(String pfad) => _puffer[pfad]?.text ?? _server[pfad] ?? '';
  String? serverInhalt(String pfad) => _server[pfad];

  bool istGeaendert(String pfad) {
    final p = _puffer[pfad];
    return p != null && p.text != (_server[pfad] ?? '');
  }

  List<String> get geaenderte =>
      _puffer.keys.where(istGeaendert).toList()..sort();

  bool get hatUngesichertes => geaenderte.isNotEmpty;

  final Set<String> _zuletztGeaendert = {};

  void _geaendert(String pfad) {
    // Auch das Freigeben der Puffer meldet sich hier; danach darf kein Timer
    // mehr anspringen, sonst überschreibt er den Entwurf mit einem leeren Stand.
    if (_verworfen) return;
    final jetzt = istGeaendert(pfad);
    final vorher = _zuletztGeaendert.contains(pfad);
    if (jetzt != vorher) {
      jetzt ? _zuletztGeaendert.add(pfad) : _zuletztGeaendert.remove(pfad);
      notifyListeners();
    }
    _entwurfTimer?.cancel();
    _entwurfTimer = Timer(entwurfVerzoegerung, _entwuerfeSchreiben);
    _serverTimer?.cancel();
    if (jetzt) {
      _serverTimer = Timer(
        serverSpeichernNachRuhe,
        () => speichern(still: true),
      );
    }
  }

  void oeffnen(String pfad) {
    if (eintraege[pfad] != Eintragsart.datei) return;
    if (!offen.contains(pfad)) offen.add(pfad);
    aktiv = pfad;
    puffer(pfad);
    notifyListeners();
  }

  void schliessen(String pfad) {
    final i = offen.indexOf(pfad);
    if (i < 0) return;
    offen.removeAt(i);
    if (aktiv == pfad) {
      aktiv = offen.isEmpty ? null : offen[i.clamp(0, offen.length - 1)];
    }
    notifyListeners();
  }

  void verwerfen(String pfad) {
    final p = _puffer[pfad];
    if (p != null) p.text = _server[pfad] ?? '';
    notifyListeners();
  }

  // ── Speichern und Abgeben ────────────────────────────────────────────

  /// Ungesicherte Dateien in die Arbeitskopie auf dem Server. Kein Commit.
  Future<bool> speichern({bool still = false}) async {
    final t = teilnahme;
    if (t == null) return false;
    final dateien = {for (final p in geaenderte) p: inhalt(p)};
    if (dateien.isEmpty) return true;
    if (!still) _zustand(Bauzustand.speichert, null);
    try {
      final s = await artemis.speichern(t.id, dateien, abgeben: false);
      if (!s.ok) {
        _zustand(Bauzustand.fehler, _speicherfehler(s));
        return false;
      }
      _server.addAll(dateien);
      _zuletztGeaendert.removeAll(dateien.keys);
      zuletztGespeichert = DateTime.now();
      verbindung = Verbindung.online;
      await _cacheSchreiben();
      await _entwuerfeSchreiben();
      if (!still) _zustand(Bauzustand.ruhe, null);
      notifyListeners();
      return true;
    } on NetzFehler catch (e) {
      verbindung = Verbindung.offline;
      if (!still) {
        _zustand(Bauzustand.fehler, '${e.grund} Lokal ist alles gesichert.');
      }
      notifyListeners();
      return false;
    } on ArtemisFehler catch (e) {
      _zustand(Bauzustand.fehler, e.meldung);
      return false;
    }
  }

  /// Speichern, committen, pushen. Danach laufen die Tests auf dem Server.
  Future<void> abgeben() async {
    final t = teilnahme;
    if (t == null) return;
    _serverTimer?.cancel();
    _zustand(Bauzustand.gibtAb, null);
    final vorher = ergebnis?.id;
    final dateien = {for (final p in geaenderte) p: inhalt(p)};
    try {
      final s = await artemis.speichern(t.id, dateien, abgeben: true);
      if (!s.ok) {
        _zustand(Bauzustand.fehler, _speicherfehler(s));
        return;
      }
      _server.addAll(dateien);
      _zuletztGeaendert.removeAll(dateien.keys);
      zuletztGespeichert = DateTime.now();
      await _cacheSchreiben();
      await _entwuerfeSchreiben();
      _zustand(Bauzustand.baut, null);
      _aufErgebnisWarten(vorher);
    } on NetzFehler catch (e) {
      verbindung = Verbindung.offline;
      _zustand(Bauzustand.fehler, '${e.grund} Nicht abgegeben.');
    } on ArtemisFehler catch (e) {
      _zustand(Bauzustand.fehler, switch (e.schluessel) {
        'exerciseDueDateOver' || 'dueDateOver' => 'Die Abgabefrist ist vorbei.',
        _ => e.meldung,
      });
    }
  }

  void _aufErgebnisWarten(int? vorherigesErgebnis) {
    _abfrageTimer?.cancel();
    final ende = DateTime.now().add(ergebnisAbfrageFrist);
    _abfrageTimer = Timer.periodic(ergebnisAbfrageTakt, (timer) async {
      if (_verworfen) return timer.cancel();
      if (DateTime.now().isAfter(ende)) {
        timer.cancel();
        _zustand(
          Bauzustand.fehler,
          'Kein Ergebnis nach ${ergebnisAbfrageFrist.inMinutes} Minuten.',
        );
        return;
      }
      try {
        final neu = await artemis.letztesErgebnis(teilnahme!.id);
        if (neu != null && neu.id != vorherigesErgebnis) {
          timer.cancel();
          ergebnis = neu;
          if (neu.buildFehlgeschlagen) {
            buildLog = await artemis.buildLog(teilnahme!.id);
          }
          _zustand(Bauzustand.fertig, null);
        }
      } on Exception {
        // Einzelne Aussetzer während des Wartens sind kein Grund aufzugeben.
      }
    });
  }

  Future<void> _ergebnisLaden() async {
    try {
      ergebnis = await artemis.letztesErgebnis(teilnahme!.id);
      if (ergebnis?.buildFehlgeschlagen ?? false) {
        buildLog = await artemis.buildLog(teilnahme!.id);
      }
      if (await artemis.wirdGebaut(teilnahme!.id)) {
        bau = Bauzustand.baut;
        _aufErgebnisWarten(ergebnis?.id);
      }
      notifyListeners();
    } on Exception {
      // Das Ergebnis ist Beiwerk; ohne es lässt sich trotzdem arbeiten.
    }
  }

  Future<void> ergebnisNeuLaden() => _ergebnisLaden();

  String _speicherfehler(Speicherstand s) {
    if (s.konflikt) {
      return 'Konflikt im Repository auf dem Server. „git reset --hard" in der Konsole setzt es zurück.';
    }
    if (s.fehlerDateien.isNotEmpty) {
      return 'Nicht gespeichert: ${s.fehlerDateien.keys.join(', ')}';
    }
    return s.fehler ?? 'Speichern fehlgeschlagen.';
  }

  void _zustand(Bauzustand z, String? m) {
    bau = z;
    meldung = m;
    notifyListeners();
  }

  // ── Repository ───────────────────────────────────────────────────────

  /// `git pull` auf dem Server, dann neu einlesen. Eigene, ungesicherte
  /// Änderungen bleiben im Puffer stehen.
  Future<List<String>> holen() async {
    await artemis.holen(teilnahme!.id);
    final vorher = Map.of(_server);
    await _vomServer();
    return [
      for (final p in _server.keys)
        if (vorher[p] != _server[p]) p,
      for (final p in vorher.keys)
        if (!_server.containsKey(p)) p,
    ];
  }

  Future<void> zuruecksetzen() async {
    await artemis.zuruecksetzen(teilnahme!.id);
    await _vomServer();
    for (final p in _puffer.keys.toList()) {
      _puffer[p]!.text = _server[p] ?? '';
    }
    await _entwuerfeSchreiben();
    notifyListeners();
  }

  Future<void> neueDatei(String pfad) async {
    await artemis.neueDatei(teilnahme!.id, pfad);
    eintraege[pfad] = Eintragsart.datei;
    _server[pfad] = '';
    oeffnen(pfad);
  }

  Future<void> neuerOrdner(String pfad) async {
    await artemis.neuerOrdner(teilnahme!.id, pfad);
    eintraege[pfad] = Eintragsart.ordner;
    notifyListeners();
  }

  Future<void> umbenennen(String pfad, String neuerName) async {
    await artemis.umbenennen(teilnahme!.id, pfad, neuerName);
    await _vomServer();
    final neu = pfad.contains('/')
        ? '${pfad.substring(0, pfad.lastIndexOf('/'))}/$neuerName'
        : neuerName;
    final i = offen.indexOf(pfad);
    if (i >= 0) offen[i] = neu;
    if (aktiv == pfad) aktiv = neu;
    final c = _puffer.remove(pfad);
    if (c != null) {
      c.dispose();
      puffer(neu);
    }
    notifyListeners();
  }

  Future<void> loeschen(String pfad) async {
    await artemis.loeschen(teilnahme!.id, pfad);
    eintraege.removeWhere((p, _) => p == pfad || p.startsWith('$pfad/'));
    _server.removeWhere((p, _) => p == pfad || p.startsWith('$pfad/'));
    for (final p
        in offen.where((p) => p == pfad || p.startsWith('$pfad/')).toList()) {
      schliessen(p);
      _puffer.remove(p)?.dispose();
    }
    await _entwuerfeSchreiben();
    notifyListeners();
  }

  // ── Platte ───────────────────────────────────────────────────────────

  Future<File> _datei(String art) async {
    final d = await _ablage();
    final ordner = Directory('${d.path}/$art');
    if (!await ordner.exists()) await ordner.create(recursive: true);
    return File('${ordner.path}/${teilnahme?.id ?? 'a${aufgabe.id}'}.json');
  }

  Future<void> _cacheSchreiben() async {
    if (teilnahme == null) return;
    final f = await _datei('server');
    await f.writeAsString(
      jsonEncode({
        'eintraege': eintraege.map((k, v) => MapEntry(k, v.name)),
        'inhalte': _server,
      }),
    );
  }

  Future<bool> _ausCache() async {
    if (teilnahme == null) return false;
    final f = await _datei('server');
    if (!await f.exists()) return false;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    eintraege = (j['eintraege'] as Map<String, dynamic>).map(
      (k, v) =>
          MapEntry(k, v == 'ordner' ? Eintragsart.ordner : Eintragsart.datei),
    );
    _server
      ..clear()
      ..addAll((j['inhalte'] as Map<String, dynamic>).cast<String, String>());
    return true;
  }

  /// Laufende Schreibvorgänge je Datei. Eine Ansicht, die geschlossen und sofort
  /// wieder geöffnet wird, liest sonst den Entwurf, bevor er auf der Platte ist.
  static final Map<String, Future<void>> _schreibt = {};

  Future<void> _entwuerfeSchreiben([Map<String, String>? stand]) async {
    if (teilnahme == null) return;
    final g = stand ?? {for (final p in geaenderte) p: inhalt(p)};
    final f = await _datei('entwuerfe');
    final vorher = _schreibt[f.path] ?? Future<void>.value();
    final jetzt = vorher.then((_) async {
      if (g.isEmpty) {
        if (await f.exists()) await f.delete();
      } else {
        await f.writeAsString(jsonEncode(g));
      }
    });
    _schreibt[f.path] = jetzt;
    await jetzt;
    if (identical(_schreibt[f.path], jetzt)) _schreibt.remove(f.path);
  }

  Future<void> _entwuerfeAnwenden() async {
    if (teilnahme == null) return;
    final f = await _datei('entwuerfe');
    await _schreibt[f.path];
    if (!await f.exists()) return;
    final j = (jsonDecode(await f.readAsString()) as Map<String, dynamic>)
        .cast<String, String>();
    for (final e in j.entries) {
      eintraege.putIfAbsent(e.key, () => Eintragsart.datei);
      puffer(e.key).text = e.value;
      if (istGeaendert(e.key)) _zuletztGeaendert.add(e.key);
    }
  }

  String _text(Object e) => switch (e) {
    ArtemisFehler f => f.meldung,
    NetzFehler n => n.grund,
    _ => e.toString(),
  };

  @override
  void dispose() {
    _verworfen = true;
    _entwurfTimer?.cancel();
    _serverTimer?.cancel();
    _abfrageTimer?.cancel();
    // Was noch ungesichert ist, landet wenigstens auf der Platte. Der Stand wird
    // vor dem Freigeben der Puffer abgegriffen, geschrieben wird danach.
    unawaited(_entwuerfeSchreiben({for (final p in geaenderte) p: inhalt(p)}));
    for (final c in _puffer.values) {
      c.dispose();
    }
    super.dispose();
  }
}
