/// Zeilenweiser Vergleich für `git diff` in der Konsole.
library;

enum DiffArt { gleich, weg, neu }

class DiffZeile {
  const DiffZeile(this.art, this.text, {this.alt, this.neu});
  final DiffArt art;
  final String text;
  final int? alt;
  final int? neu;
}

/// LCS über Zeilen. Quadratisch, aber Aufgabendateien haben selten mehr als
/// ein paar hundert Zeilen; über [_grenze] wird nur Anfang und Ende gekürzt.
List<DiffZeile> zeilenDiff(String vorher, String nachher) {
  final a = vorher.split('\n');
  final b = nachher.split('\n');

  // Gemeinsamen Anfang und Ende abschneiden, das macht den Rest klein.
  var anfang = 0;
  while (anfang < a.length && anfang < b.length && a[anfang] == b[anfang]) {
    anfang++;
  }
  var ende = 0;
  while (ende < a.length - anfang &&
      ende < b.length - anfang &&
      a[a.length - 1 - ende] == b[b.length - 1 - ende]) {
    ende++;
  }
  final mitteA = a.sublist(anfang, a.length - ende);
  final mitteB = b.sublist(anfang, b.length - ende);

  final ergebnis = <DiffZeile>[
    for (var i = 0; i < anfang; i++)
      DiffZeile(DiffArt.gleich, a[i], alt: i + 1, neu: i + 1),
  ];

  if (mitteA.length * mitteB.length > _grenze) {
    for (var i = 0; i < mitteA.length; i++) {
      ergebnis.add(DiffZeile(DiffArt.weg, mitteA[i], alt: anfang + i + 1));
    }
    for (var j = 0; j < mitteB.length; j++) {
      ergebnis.add(DiffZeile(DiffArt.neu, mitteB[j], neu: anfang + j + 1));
    }
  } else {
    final n = mitteA.length, m = mitteB.length;
    final l = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        l[i][j] = mitteA[i] == mitteB[j]
            ? l[i + 1][j + 1] + 1
            : (l[i + 1][j] >= l[i][j + 1] ? l[i + 1][j] : l[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (mitteA[i] == mitteB[j]) {
        ergebnis.add(
          DiffZeile(
            DiffArt.gleich,
            mitteA[i],
            alt: anfang + i + 1,
            neu: anfang + j + 1,
          ),
        );
        i++;
        j++;
      } else if (l[i + 1][j] >= l[i][j + 1]) {
        ergebnis.add(DiffZeile(DiffArt.weg, mitteA[i], alt: anfang + i + 1));
        i++;
      } else {
        ergebnis.add(DiffZeile(DiffArt.neu, mitteB[j], neu: anfang + j + 1));
        j++;
      }
    }
    for (; i < n; i++) {
      ergebnis.add(DiffZeile(DiffArt.weg, mitteA[i], alt: anfang + i + 1));
    }
    for (; j < m; j++) {
      ergebnis.add(DiffZeile(DiffArt.neu, mitteB[j], neu: anfang + j + 1));
    }
  }

  for (var k = 0; k < ende; k++) {
    final ia = a.length - ende + k, ib = b.length - ende + k;
    ergebnis.add(DiffZeile(DiffArt.gleich, a[ia], alt: ia + 1, neu: ib + 1));
  }
  return ergebnis;
}

const _grenze = 4000000;

/// Fasst einen Diff zu Hunks mit [kontext] Zeilen Umgebung zusammen, wie `git diff`.
List<String> alsHunks(List<DiffZeile> diff, {int kontext = 3}) {
  final aenderungen = <int>[
    for (var i = 0; i < diff.length; i++)
      if (diff[i].art != DiffArt.gleich) i,
  ];
  if (aenderungen.isEmpty) return const [];

  final bloecke = <(int, int)>[];
  var start = aenderungen.first, ende = aenderungen.first;
  for (final i in aenderungen.skip(1)) {
    if (i - ende <= 2 * kontext) {
      ende = i;
    } else {
      bloecke.add((start, ende));
      start = ende = i;
    }
  }
  bloecke.add((start, ende));

  final zeilen = <String>[];
  for (final (s, e) in bloecke) {
    final von = (s - kontext).clamp(0, diff.length - 1);
    final bis = (e + kontext).clamp(0, diff.length - 1);
    final teil = diff.sublist(von, bis + 1);
    final altStart = teil
        .firstWhere(
          (z) => z.alt != null,
          orElse: () => const DiffZeile(DiffArt.gleich, '', alt: 0),
        )
        .alt!;
    final neuStart = teil
        .firstWhere(
          (z) => z.neu != null,
          orElse: () => const DiffZeile(DiffArt.gleich, '', neu: 0),
        )
        .neu!;
    final altAnzahl = teil.where((z) => z.art != DiffArt.neu).length;
    final neuAnzahl = teil.where((z) => z.art != DiffArt.weg).length;
    zeilen.add('@@ -$altStart,$altAnzahl +$neuStart,$neuAnzahl @@');
    for (final z in teil) {
      zeilen.add(switch (z.art) {
        DiffArt.gleich => ' ${z.text}',
        DiffArt.weg => '-${z.text}',
        DiffArt.neu => '+${z.text}',
      });
    }
  }
  return zeilen;
}
