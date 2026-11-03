import 'package:flutter_test/flutter_test.dart';
import 'package:werkbank/werkzeuge/diff.dart';

void main() {
  test('gleiche Texte ergeben keine Hunks', () {
    expect(alsHunks(zeilenDiff('a\nb\nc', 'a\nb\nc')), isEmpty);
  });

  test('geänderte Zeile wird als - und + mit Kopf gezeigt', () {
    final h = alsHunks(zeilenDiff('a\nb\nc', 'a\nB\nc'));
    expect(h, ['@@ -1,3 +1,3 @@', ' a', '-b', '+B', ' c']);
  });

  test('angehängte Zeilen zählen nur auf der neuen Seite', () {
    final h = alsHunks(zeilenDiff('a', 'a\nb\nc'));
    expect(h.first, '@@ -1,1 +1,3 @@');
    expect(h.where((z) => z.startsWith('+')), ['+b', '+c']);
  });

  test('weit auseinanderliegende Änderungen ergeben zwei Hunks', () {
    final alt = List.generate(30, (i) => 'z$i').join('\n');
    final neu = alt.replaceFirst('z2\n', 'X\n').replaceFirst('z27', 'Y');
    final kopf = alsHunks(
      zeilenDiff(alt, neu),
    ).where((z) => z.startsWith('@@'));
    expect(kopf.length, 2);
  });
}
