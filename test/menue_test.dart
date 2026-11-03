import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:werkbank/ansichten/arbeitsplatz_ansicht.dart';
import 'package:werkbank/ansichten/statusleiste.dart';
import 'package:werkbank/zustand/sitzung.dart';
import 'package:werkbank/zustand/tastatur.dart';

void main() {
  testWidgets('Mehr-Menü bleibt offen', (t) async {
    t.binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('werkbank/tastatur'),
      MockStreamHandler.inline(onListen: (_, senke) => senke.success(false)),
    );
    t.view.physicalSize = const Size(1180 * 2, 820 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final sitzung = Sitzung(demo: true);
    final aufgabe = await t.runAsync(
      () async => (await sitzung.artemis.kurse()).first.aufgaben.first,
    );
    final ordner = (await t.runAsync(
      () => Directory.systemTemp.createTemp('werkbank'),
    ))!;
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: sitzung),
          ChangeNotifierProvider(create: (_) => TastaturWaechter()),
        ],
        child: MaterialApp(
          builder: (_, kind) => OhneStatusleistenTipp(child: kind!),
          home: ArbeitsplatzAnsicht(
            aufgabe: aufgabe!,
            ablage: () async => ordner,
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    // Wie auf dem iPad: Editor hat den Fokus, die Bildschirmtastatur ist offen.
    await t.tap(find.byType(CodeEditor));
    await t.pump();
    t.view.viewInsets = FakeViewPadding(bottom: 320 * 2);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byTooltip('Mehr'));
    await t.pump();
    // Das Menü nimmt dem Editor den Fokus, die Tastatur fährt herunter.
    t.view.viewInsets = FakeViewPadding.zero;
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Tastenkürzel'),
      findsOneWidget,
      reason: 'direkt nach dem Öffnen',
    );
    // Der erfundene Statusleisten-Tipp der iOS-Engine (flutter#177992).
    await t.tapAt(Offset.zero);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Tastenkürzel'), findsOneWidget, reason: 'nach dem Tipp bei (0, 0)');
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('Tastenkürzel'),
      findsOneWidget,
      reason: 'zwei Sekunden später',
    );
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
