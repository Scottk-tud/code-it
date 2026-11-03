import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:werkbank/ansichten/aufgabenstellung.dart';
import 'package:werkbank/ansichten/editor_bereich.dart';
import 'package:werkbank/ansichten/tastenleiste.dart';
import 'package:werkbank/api/demo.dart';
import 'package:werkbank/api/modelle.dart';
import 'package:werkbank/zustand/arbeitsplatz.dart';
import 'package:werkbank/zustand/tastatur.dart';

void main() {
  testWidgets('task-Marker bekommen Häkchen über <testid>', (t) async {
    const text =
        '1. [task][Euklid](<testid>11</testid>) a\n'
        '2. [task][Kürzen](<testid>12</testid>,<testid>13</testid>) b\n'
        '3. [task][Offen](<testid>99</testid>) c\n';
    const e = Ergebnis(
      id: 1,
      rueckmeldungen: [
        Rueckmeldung(testId: 11, positiv: true),
        Rueckmeldung(testId: 12, positiv: true),
        Rueckmeldung(testId: 13, positiv: false),
      ],
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Aufgabenstellung(
            text: text,
            ergebnis: e,
            artemis: DemoArtemis(),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.textContaining('Euklid'), findsOneWidget);
  });

  test('TeX wird lesbarer Text', () {
    expect(texAlsText('n'), 'n');
    expect(texAlsText(r'a \le b'), 'a ≤ b');
    expect(texAlsText(r'x^2 + y_{i}'), 'x² + yᵢ');
    expect(texAlsText(r'\{1, \ldots, n\}'), '{1, …, n}');
    expect(texAlsText(r'\left( x \right)'), r'\left( x \right)');
    expect(texAlsText(r'2^{x+y}'), '2^(x+y)');
  });

  testWidgets('Formeln erscheinen ohne Dollarzeichen', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Aufgabenstellung(
            text: r'Lesen Sie $$ n $$ ein und geben Sie die $$n$$-te Zahl aus.',
            ergebnis: null,
            artemis: DemoArtemis(),
          ),
        ),
      ),
    );
    final text = t
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText())
        .join();
    expect(text, isNot(contains(r'$')));
    expect(text, contains('Lesen Sie n ein'));
  });

  group('Zeichenleiste', () {
    late Directory ablage;
    late Arbeitsplatz platz;

    Future<void> aufbauen(WidgetTester t) async {
      t.binding.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('werkbank/tastatur'),
        MockStreamHandler.inline(onListen: (_, senke) => senke.success(false)),
      );
      await t.runAsync(() async {
        ablage = await Directory.systemTemp.createTemp('werkbank');
        final artemis = DemoArtemis();
        final aufgabe = (await artemis.kurse()).first.aufgaben.first;
        final ordner = ablage;
        platz = Arbeitsplatz(
          artemis: artemis,
          aufgabe: aufgabe,
          ablage: () async => ordner,
        );
        await platz.laden();
      });
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: platz),
            ChangeNotifierProvider(create: (_) => TastaturWaechter()),
          ],
          child: const MaterialApp(home: Scaffold(body: EditorBereich())),
        ),
      );
      await t.pump();
    }

    Future<void> fokussieren(WidgetTester t) async {
      // Der Editor malt selbst, es gibt keine Text-Widgets zum Antippen.
      await t.tap(find.byType(CodeEditor));
      await t.pump();
    }

    // Im Testkörper statt in tearDown: der Prüfer meckert über offene Timer
    // (Cursor, Entwurf) schon vor tearDown.
    Future<void> abbauen(WidgetTester t) async {
      // Erst den Fokus weg: der Cursor-Blinker von re_editor feuert sonst noch
      // einmal nach dem Abbau.
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump(const Duration(seconds: 1));
      await t.pumpWidget(const SizedBox());
      platz.dispose();
      await t.pump(const Duration(seconds: 1));
      await t.runAsync(() => ablage.delete(recursive: true));
    }

    testWidgets('erscheint mit Bildschirmtastatur', (t) async {
      await aufbauen(t);
      await fokussieren(t);
      t.view.viewInsets = FakeViewPadding(
        bottom: 320 * t.view.devicePixelRatio,
      );
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      expect(find.byType(Tastenleiste), findsOneWidget);
      await abbauen(t);
    });

    testWidgets('fehlt bei der schmalen Kürzelleiste einer Hardware-Tastatur', (
      t,
    ) async {
      await aufbauen(t);
      await fokussieren(t);
      t.view.viewInsets = FakeViewPadding(bottom: 55 * t.view.devicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      expect(find.byType(Tastenleiste), findsNothing);
      await abbauen(t);
    });

    testWidgets('Klammer setzt das Paar und den Cursor dazwischen', (t) async {
      await aufbauen(t);
      await fokussieren(t);
      t.view.viewInsets = FakeViewPadding(
        bottom: 320 * t.view.devicePixelRatio,
      );
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      final c = platz.puffer(platz.aktiv!);
      final vorher = c.text.length;
      await t.tap(
        find.descendant(
          of: find.byType(Tastenleiste),
          matching: find.text('('),
        ),
      );
      await t.pump();
      expect(c.text.length, vorher + 2);
      final s = c.selection;
      final zeile = c.codeLines[s.extentIndex].text;
      expect(zeile.substring(s.extentOffset - 1, s.extentOffset + 1), '()');
      await abbauen(t);
    });
  });
}
