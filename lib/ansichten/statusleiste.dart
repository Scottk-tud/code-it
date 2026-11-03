import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../api/klient.dart';

/// Schluckt die künstlichen Berührungen bei (0, 0).
///
/// Flutters iOS-Engine bis 3.41.2 schickt bei einem Tipp auf die Statusleiste
/// ein erfundenes Ab/Auf an (0, 0), damit Scaffold nach oben scrollt. Seit
/// iPadOS 26.1 zählt auch ein Tipp oben in der App-Leiste als Statusleiste:
/// Der erfundene Tipp trifft dann den Hintergrund des gerade geöffneten Menüs
/// oder Dialogs und schließt ihn nach ~330 ms (gemessen am iPad, 16.10.2026;
/// flutter/flutter#177992, behoben in 3.41.3). Ein echter Finger landet nie
/// exakt auf dem Pixel in der Ecke. Kann weg, sobald Flutter ≥ 3.41.3 baut.
class OhneStatusleistenTipp extends SingleChildRenderObjectWidget {
  const OhneStatusleistenTipp({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _OhneEckTreffer();
}

class _OhneEckTreffer extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (position.dx < 1 && position.dy < 1) {
      ArtemisKlient.protokolliere('Eck-Tipp verworfen');
      return false;
    }
    return super.hitTest(result, position: position);
  }
}
