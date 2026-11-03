/// Die Teile der Artemis-JSON, die die App braucht.
///
/// Absichtlich nachsichtig gelesen: Artemis lässt leere Felder weg
/// (`@JsonInclude(NON_EMPTY)`), und zwischen Versionen wandern Felder. Ein
/// fehlendes Feld darf keine Ansicht abstürzen lassen.
library;

DateTime? _zeit(dynamic v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;
double? _zahl(dynamic v) => v is num ? v.toDouble() : null;
int? _ganz(dynamic v) => v is num ? v.toInt() : null;
List<Map<String, dynamic>> _liste(dynamic v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class Nutzer {
  const Nutzer({required this.login, required this.name, this.email});
  final String login;
  final String name;
  final String? email;

  factory Nutzer.aus(Map<String, dynamic> j) => Nutzer(
    login: j['login'] as String? ?? '',
    name:
        j['name'] as String? ??
        [j['firstName'], j['lastName']].whereType<String>().join(' '),
    email: j['email'] as String?,
  );
}

class Kurs {
  const Kurs({
    required this.id,
    required this.titel,
    this.kurzname,
    this.farbe,
    this.aufgaben = const [],
  });
  final int id;
  final String titel;
  final String? kurzname;
  final String? farbe;
  final List<Aufgabe> aufgaben;

  factory Kurs.aus(Map<String, dynamic> j, {List<Aufgabe>? aufgaben}) => Kurs(
    id: _ganz(j['id']) ?? 0,
    titel: j['title'] as String? ?? 'Kurs',
    kurzname: j['shortName'] as String?,
    farbe: j['color'] as String?,
    aufgaben: aufgaben ?? _liste(j['exercises']).map(Aufgabe.aus).toList(),
  );

  Kurs mitAufgaben(List<Aufgabe> a) =>
      Kurs(id: id, titel: titel, kurzname: kurzname, farbe: farbe, aufgaben: a);
}

enum Aufgabentyp { programmierung, text, modellierung, quiz, datei, sonstige }

Aufgabentyp _typ(dynamic v) => switch (v) {
  'programming' => Aufgabentyp.programmierung,
  'text' => Aufgabentyp.text,
  'modeling' => Aufgabentyp.modellierung,
  'quiz' => Aufgabentyp.quiz,
  'file-upload' => Aufgabentyp.datei,
  _ => Aufgabentyp.sonstige,
};

class Aufgabe {
  const Aufgabe({
    required this.id,
    required this.titel,
    required this.typ,
    this.kursId,
    this.kurzname,
    this.start,
    this.faellig,
    this.punkte,
    this.bonus,
    this.aufgabenstellung,
    this.sprache,
    this.onlineEditor = true,
    this.teilnahme,
  });

  final int id;
  final String titel;
  final Aufgabentyp typ;
  final int? kursId;
  final String? kurzname;
  final DateTime? start;
  final DateTime? faellig;
  final double? punkte;
  final double? bonus;
  final String? aufgabenstellung;
  final String? sprache;
  final bool onlineEditor;
  final Teilnahme? teilnahme;

  bool get istProgrammierung => typ == Aufgabentyp.programmierung;
  bool get vorbei => faellig != null && faellig!.isBefore(DateTime.now());
  bool get nochNichtOffen => start != null && start!.isAfter(DateTime.now());

  factory Aufgabe.aus(Map<String, dynamic> j) {
    // Mit Übungsmodus gibt es zwei Teilnahmen; die bewertete (testRun: false) zählt.
    final teilnahmen = [..._liste(j['studentParticipations'])]
      ..sort(
        (a, b) => (a['testRun'] == true ? 1 : 0).compareTo(
          b['testRun'] == true ? 1 : 0,
        ),
      );
    return Aufgabe(
      id: _ganz(j['id']) ?? 0,
      titel: j['title'] as String? ?? 'Aufgabe',
      typ: _typ(j['type']),
      kursId: _ganz((j['course'] as Map?)?['id']),
      kurzname: j['shortName'] as String?,
      start: _zeit(j['startDate']) ?? _zeit(j['releaseDate']),
      faellig: _zeit(j['dueDate']),
      punkte: _zahl(j['maxPoints']),
      bonus: _zahl(j['bonusPoints']),
      aufgabenstellung: j['problemStatement'] as String?,
      sprache: j['programmingLanguage'] as String?,
      onlineEditor: j['allowOnlineEditor'] as bool? ?? true,
      teilnahme: teilnahmen.isEmpty ? null : Teilnahme.aus(teilnahmen.first),
    );
  }

  Aufgabe mit({Teilnahme? teilnahme, String? aufgabenstellung}) => Aufgabe(
    id: id,
    titel: titel,
    typ: typ,
    kursId: kursId,
    kurzname: kurzname,
    start: start,
    faellig: faellig,
    punkte: punkte,
    bonus: bonus,
    aufgabenstellung: aufgabenstellung ?? this.aufgabenstellung,
    sprache: sprache,
    onlineEditor: onlineEditor,
    teilnahme: teilnahme ?? this.teilnahme,
  );
}

class Teilnahme {
  const Teilnahme({
    required this.id,
    this.zustand,
    this.repoUrl,
    this.ergebnisse = const [],
  });
  final int id;

  /// `initializationState`: UNINITIALIZED, REPO_COPIED, …, INITIALIZED, INACTIVE, FINISHED.
  final String? zustand;
  final String? repoUrl;
  final List<Ergebnis> ergebnisse;

  bool get inaktiv => zustand == 'INACTIVE' || zustand == 'FINISHED';

  Ergebnis? get letztes {
    if (ergebnisse.isEmpty) return null;
    final s = [...ergebnisse]
      ..sort(
        (a, b) => (a.fertig ?? DateTime(0)).compareTo(b.fertig ?? DateTime(0)),
      );
    return s.last;
  }

  factory Teilnahme.aus(Map<String, dynamic> j) {
    final ergebnisse = <Ergebnis>[
      ..._liste(j['results']).map(Ergebnis.aus),
      for (final s in _liste(j['submissions']))
        ..._liste(s['results']).map((r) => Ergebnis.aus(r, abgabe: s)),
    ];
    final eindeutig = {for (final e in ergebnisse) e.id: e}.values.toList();
    return Teilnahme(
      id: _ganz(j['id']) ?? 0,
      zustand: j['initializationState'] as String?,
      repoUrl: j['repositoryUri'] as String? ?? j['repositoryUrl'] as String?,
      ergebnisse: eindeutig,
    );
  }
}

class Ergebnis {
  const Ergebnis({
    required this.id,
    this.prozent,
    this.erfolgreich,
    this.fertig,
    this.tests,
    this.bestanden,
    this.buildFehlgeschlagen = false,
    this.rueckmeldungen = const [],
    this.commit,
  });

  final int id;
  final double? prozent;
  final bool? erfolgreich;
  final DateTime? fertig;
  final int? tests;
  final int? bestanden;
  final bool buildFehlgeschlagen;
  final List<Rueckmeldung> rueckmeldungen;
  final String? commit;

  factory Ergebnis.aus(Map<String, dynamic> j, {Map<String, dynamic>? abgabe}) {
    final s = (j['submission'] as Map<String, dynamic>?) ?? abgabe;
    return Ergebnis(
      id: _ganz(j['id']) ?? 0,
      prozent: _zahl(j['score']),
      erfolgreich: j['successful'] as bool?,
      fertig: _zeit(j['completionDate']),
      tests: _ganz(j['testCaseCount']),
      bestanden: _ganz(j['passedTestCaseCount']),
      buildFehlgeschlagen: s?['buildFailed'] as bool? ?? false,
      rueckmeldungen: _liste(j['feedbacks']).map(Rueckmeldung.aus).toList(),
      commit: s?['commitHash'] as String?,
    );
  }

  Ergebnis mitRueckmeldungen(List<Rueckmeldung> r) => Ergebnis(
    id: id,
    prozent: prozent,
    erfolgreich: erfolgreich,
    fertig: fertig,
    tests: tests,
    bestanden: bestanden,
    buildFehlgeschlagen: buildFehlgeschlagen,
    rueckmeldungen: r,
    commit: commit,
  );
}

class Rueckmeldung {
  const Rueckmeldung({
    this.id,
    this.langerText = false,
    this.testId,
    this.test,
    this.text,
    this.detail,
    this.positiv,
    this.punkte,
    this.art,
  });

  /// Testfall, über den die `[task]`-Marker der Aufgabenstellung ihre Häkchen
  /// bekommen. Gespeicherte Aufgabenstellungen verweisen per `<testid>`, ältere
  /// per Name.
  final int? testId;
  final String? test;

  /// Automatische Rückmeldungen haben negative, synthetische ids.
  final int? id;

  /// Über 1000 Zeichen liefert Artemis in [detail] nur den Anfang.
  final bool langerText;
  final String? text;
  final String? detail;
  final bool? positiv;
  final double? punkte;

  /// AUTOMATIC, MANUAL, MANUAL_UNREFERENCED, AUTOMATIC_ADAPTED.
  final String? art;

  String get titel => test ?? text ?? 'Rückmeldung';

  Rueckmeldung mitDetail(String d) => Rueckmeldung(
    id: id,
    testId: testId,
    test: test,
    text: text,
    detail: d,
    positiv: positiv,
    punkte: punkte,
    art: art,
  );

  factory Rueckmeldung.aus(Map<String, dynamic> j) => Rueckmeldung(
    id: _ganz(j['id']),
    langerText: j['hasLongFeedbackText'] as bool? ?? false,
    testId: _ganz((j['testCase'] as Map?)?['id']),
    test: (j['testCase'] as Map?)?['testName'] as String?,
    text: j['text'] as String?,
    detail: j['detailText'] as String?,
    positiv: j['positive'] as bool?,
    punkte: _zahl(j['credits']),
    art: j['type'] as String?,
  );
}

class BuildZeile {
  const BuildZeile(this.zeit, this.text);
  final DateTime? zeit;
  final String text;

  factory BuildZeile.aus(Map<String, dynamic> j) =>
      BuildZeile(_zeit(j['time']), j['log'] as String? ?? '');
}

enum Eintragsart { datei, ordner }

/// Antwort von PUT …/repository/files: was gespeichert wurde und ob es klappte.
class Speicherstand {
  const Speicherstand({
    this.fehler,
    this.fehlerDateien = const {},
    this.konflikt = false,
  });
  final String? fehler;
  final Map<String, String> fehlerDateien;
  final bool konflikt;
  bool get ok => fehler == null && fehlerDateien.isEmpty && !konflikt;
}

class Commit {
  const Commit({required this.hash, this.nachricht, this.autor, this.zeit});
  final String hash;
  final String? nachricht;
  final String? autor;
  final DateTime? zeit;
}
