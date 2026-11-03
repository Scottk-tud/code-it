import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:werkbank/api/demo.dart';
import 'package:werkbank/zustand/arbeitsplatz.dart';
import 'package:werkbank/zustand/konsole.dart';

void main() {
  late Directory ablage;
  late DemoArtemis artemis;
  late Arbeitsplatz platz;
  late Konsole konsole;

  const bruch = 'src/de/tud/inf/Bruch.java';

  setUp(() async {
    ablage = await Directory.systemTemp.createTemp('werkbank');
    artemis = DemoArtemis();
    final aufgabe = (await artemis.kurse()).first.aufgaben.first;
    final ordner = ablage;
    platz = Arbeitsplatz(
      artemis: artemis,
      aufgabe: aufgabe,
      ablage: () async => ordner,
    );
    await platz.laden();
    konsole = Konsole(platz);
  });

  tearDown(() async {
    platz.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await ablage.delete(recursive: true);
  });

  Iterable<String> ausgabe() => konsole.zeilen.map((z) => z.text);

  test('status und diff zeigen eine Änderung im Puffer', () async {
    platz.puffer(bruch).text = platz
        .inhalt(bruch)
        .replaceFirst('return 0;', 'return b == 0 ? a : ggT(b, a % b);');
    await konsole.eingeben('git status');
    expect(ausgabe(), contains('  geändert: $bruch'));

    await konsole.eingeben('git diff Bruch.java');
    expect(ausgabe(), contains('-        return 0;'));
    expect(ausgabe(), contains('+        return b == 0 ? a : ggT(b, a % b);'));
  });

  test('commit speichert auf dem Server, gibt aber nicht ab', () async {
    platz.puffer(bruch).text = '${platz.inhalt(bruch)}\n// neu';
    await konsole.eingeben('git commit -m "x"');
    expect(platz.hatUngesichertes, isFalse);
    expect(await artemis.wirdGebaut(110), isFalse);
    expect((await artemis.verlauf(110)).length, 1);
  });

  test('push fragt nach und gibt erst mit j ab', () async {
    await konsole.eingeben('git push');
    expect(konsole.rueckfrage, isNotNull);
    expect((await artemis.verlauf(110)).length, 1);

    await konsole.eingeben('j');
    expect(platz.bau, Bauzustand.baut);
    expect((await artemis.verlauf(110)).length, 2);
  });

  test('push mit n bricht ab', () async {
    await konsole.eingeben('git push');
    await konsole.eingeben('n');
    expect(ausgabe().last, 'Abgebrochen.');
    expect((await artemis.verlauf(110)).length, 1);
  });

  test('restore verwirft die eigene Änderung', () async {
    final vorher = platz.inhalt(bruch);
    platz.puffer(bruch).text = 'kaputt';
    await konsole.eingeben('git restore Bruch.java');
    expect(platz.inhalt(bruch), vorher);
  });

  test('Entwürfe überleben einen Neustart der Ansicht', () async {
    platz.puffer(bruch).text = 'Entwurf';
    // Sofort wieder öffnen, ohne zu warten: genau der Fall, in dem der
    // Entwurf noch unterwegs zur Platte ist.
    platz.dispose();

    final ordner = ablage;
    final neu = Arbeitsplatz(
      artemis: artemis,
      aufgabe: (await artemis.kurse()).first.aufgaben.first,
      ablage: () async => ordner,
    );
    await neu.laden();
    expect(neu.inhalt(bruch), 'Entwurf');
    expect(neu.istGeaendert(bruch), isTrue);
    // Länger als die Entwurfsverzögerung warten: der alte Arbeitsplatz darf
    // den Entwurf auch nachträglich nicht löschen.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(File('${ablage.path}/entwuerfe/110.json').existsSync(), isTrue);
    platz = neu;
  });

  test('unbekannte Befehle und mehrdeutige Namen melden sich', () async {
    await konsole.eingeben('git rebase');
    expect(konsole.zeilen.last.art, Zeilenart.fehler);
    await konsole.eingeben('cat Gibtsnicht.java');
    expect(ausgabe().last, 'Nicht gefunden: Gibtsnicht.java');
  });
}
