import 'dart:typed_data';

import 'artemis.dart';
import 'klient.dart';
import 'modelle.dart';

/// Artemis 10.2 über REST. Die Pfade stammen aus dem Server-Quelltext
/// (Tag 10.2) und dem Web-Client derselben Instanz.
class HttpArtemis implements Artemis {
  HttpArtemis(this.k);
  final ArtemisKlient k;

  String _repo(int t) => 'api/programming/participations/$t/repository';

  @override
  Future<String> anmelden(String name, String passwort) async {
    final alt = k.token;
    k.token = null;
    try {
      final a = await k.post(
        'api/core/public/authenticate',
        koerper: {'username': name, 'password': passwort, 'rememberMe': true},
      );
      final token = (a as Map?)?['access_token'] as String?;
      if (token == null) throw ArtemisFehler(500, 'Kein Token in der Antwort.');
      return token;
    } catch (_) {
      k.token = alt;
      rethrow;
    }
  }

  @override
  Future<Nutzer?> konto() async {
    final j = await k.get('api/core/public/account');
    return j is Map<String, dynamic> ? Nutzer.aus(j) : null;
  }

  @override
  Future<List<Kurs>> kurse() async {
    final j =
        await k.get('api/course/courses/for-dashboard') as Map<String, dynamic>;
    final kurse = <Kurs>[];
    for (final e
        in (j['courses'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final c = (e['course'] as Map<String, dynamic>?) ?? e;
      kurse.add(Kurs.aus(c));
    }
    kurse.sort((a, b) => a.titel.compareTo(b.titel));
    return kurse;
  }

  @override
  Future<List<Aufgabe>> aufgabenVon(Kurs kurs) async {
    final j = await k.get(
      'api/course/courses/${kurs.id}/exercises-for-overview',
    );
    final liste = (j is Map ? j['exercises'] : j) as List? ?? const [];
    return liste
        .cast<Map<String, dynamic>>()
        .map(_aufgabeAusUebersicht)
        .toList();
  }

  Aufgabe _aufgabeAusUebersicht(Map<String, dynamic> j) {
    final e = (j['exercise'] as Map<String, dynamic>?) ?? j;
    return Aufgabe.aus(e);
  }

  @override
  Future<Aufgabe> aufgabe(int id) async {
    final j =
        await k.get('api/exercise/exercises/$id/details')
            as Map<String, dynamic>;
    return Aufgabe.aus((j['exercise'] as Map<String, dynamic>?) ?? j);
  }

  @override
  Future<Teilnahme> starten(Aufgabe aufgabe) async {
    final j = await k.post(
      'api/exercise/exercises/${aufgabe.id}/participations',
    );
    return Teilnahme.aus(j as Map<String, dynamic>);
  }

  @override
  Future<Teilnahme> fortsetzen(Aufgabe aufgabe, Teilnahme teilnahme) async {
    final j = await k.put(
      'api/exercise/exercises/${aufgabe.id}/participations/${teilnahme.id}/resume-programming-participation',
      koerper: const {},
    );
    return Teilnahme.aus(j as Map<String, dynamic>);
  }

  @override
  Future<Map<String, Eintragsart>> dateien(int teilnahme) async {
    final j = await k.get('${_repo(teilnahme)}/files') as Map<String, dynamic>;
    return j.map(
      (p, art) =>
          MapEntry(p, art == 'FOLDER' ? Eintragsart.ordner : Eintragsart.datei),
    );
  }

  /// `files-content` ist in 10.2 Tutoren vorbehalten. Studierende bekommen die
  /// Arbeitskopie nur Datei für Datei, deshalb hier in kleinen Wellen parallel.
  @override
  Future<Map<String, String>> inhalte(int teilnahme) async {
    final eintraege = await dateien(teilnahme);
    final pfade = [
      for (final e in eintraege.entries)
        if (e.value == Eintragsart.datei && !_binaer(e.key)) e.key,
    ];
    final inhalte = <String, String>{};
    for (var i = 0; i < pfade.length; i += _welle) {
      final teil = pfade.skip(i).take(_welle);
      await Future.wait(
        teil.map((p) async {
          inhalte[p] = await k.text(
            '${_repo(teilnahme)}/file',
            abfrage: {'file': p},
          );
        }),
      );
    }
    return inhalte;
  }

  static const _welle = 6;

  static bool _binaer(String p) {
    final n = p.toLowerCase();
    return const [
      '.jar',
      '.class',
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.pdf',
      '.zip',
      '.ico',
      '.bin',
      '.so',
      '.o',
    ].any(n.endsWith);
  }

  @override
  Future<Speicherstand> speichern(
    int teilnahme,
    Map<String, String> dateien, {
    required bool abgeben,
  }) async {
    try {
      final j = await k.put(
        '${_repo(teilnahme)}/files',
        abfrage: {'commit': abgeben ? 'true' : 'false'},
        koerper: [
          for (final e in dateien.entries)
            {'fileName': e.key, 'fileContent': e.value},
        ],
      );
      // Antwort: Dateiname → Fehler, leer heißt alles gut.
      final fehler = <String, String>{};
      if (j is Map) {
        j.forEach((p, v) {
          if (v != null && v.toString().isNotEmpty) fehler['$p'] = '$v';
        });
      }
      return Speicherstand(fehlerDateien: fehler);
    } on ArtemisFehler catch (e) {
      if (e.status == 409) return const Speicherstand(konflikt: true);
      rethrow;
    }
  }

  @override
  Future<void> neueDatei(int teilnahme, String pfad) =>
      k.post('${_repo(teilnahme)}/file', abfrage: {'file': pfad}, koerper: '');

  @override
  Future<void> neuerOrdner(int teilnahme, String pfad) => k.post(
    '${_repo(teilnahme)}/folder',
    abfrage: {'folder': pfad},
    koerper: '',
  );

  @override
  Future<void> umbenennen(int teilnahme, String pfad, String neuerName) =>
      k.post(
        '${_repo(teilnahme)}/rename-file',
        koerper: {'currentFilePath': pfad, 'newFilename': neuerName},
      );

  @override
  Future<void> loeschen(int teilnahme, String pfad) =>
      k.delete('${_repo(teilnahme)}/file', abfrage: {'file': pfad});

  @override
  Future<void> holen(int teilnahme) => k.post('${_repo(teilnahme)}/pull');

  @override
  Future<void> zuruecksetzen(int teilnahme) =>
      k.post('${_repo(teilnahme)}/reset');

  @override
  Future<Ergebnis?> letztesErgebnis(int teilnahme) async {
    final j = await k.get(
      'api/programming/programming-exercise-participations/$teilnahme/latest-result-with-feedbacks',
    );
    if (j is! Map<String, dynamic>) return null;
    final e = Ergebnis.aus(j);
    if (!e.rueckmeldungen.any((r) => r.langerText)) return e;
    return e.mitRueckmeldungen(
      await Future.wait(
        e.rueckmeldungen.map((r) async {
          if (!r.langerText || r.id == null) return r;
          try {
            return r.mitDetail(
              await k.text('api/assessment/feedbacks/${r.id}/long-feedback'),
            );
          } on Exception {
            return r;
          }
        }),
      ),
    );
  }

  @override
  Future<List<BuildZeile>> buildLog(int teilnahme) async {
    final j = await k.get(
      'api/programming/participations/$teilnahme/buildlogs',
    );
    return (j as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BuildZeile.aus)
        .toList();
  }

  @override
  Future<bool> wirdGebaut(int teilnahme) async {
    final j = await k.get(
      'api/programming/programming-exercise-participations/$teilnahme/latest-pending-submission',
    );
    // Leerer Körper heißt: nichts wartet auf ein Ergebnis.
    return j is Map && j.isNotEmpty;
  }

  @override
  Future<List<Commit>> verlauf(int teilnahme) async {
    final j = await k.get(
      'api/programming/programming-exercise-participations/$teilnahme/commit-history',
    );
    return [
      for (final c in (j as List? ?? const []).cast<Map<String, dynamic>>())
        Commit(
          hash: c['hash'] as String? ?? '',
          nachricht: (c['message'] as String?)?.split('\n').first,
          autor: c['author'] as String?,
          zeit: DateTime.tryParse(c['timestamp'] as String? ?? '')?.toLocal(),
        ),
    ];
  }

  @override
  Future<Uint8List?> plantUml(String quelle, {required bool dunkel}) async {
    final a = await k.roh(
      'GET',
      'api/programming/plantuml/png',
      abfrage: {'plantuml': quelle, 'useDarkTheme': '$dunkel'},
    );
    return a.bodyBytes;
  }
}
