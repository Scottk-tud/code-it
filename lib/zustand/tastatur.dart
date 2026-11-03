import 'dart:async';
import 'dart:ui' show KeyEventDeviceType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Weiß, ob gerade eine Hardware-Tastatur da ist.
///
/// Zwei Quellen: Das Betriebssystem meldet das An- und Abstecken (iPadOS über
/// GCKeyboard, Android über die Configuration). Als Rückfall zählt jeder
/// Tastendruck, der nicht von der Bildschirmtastatur stammt — die schickt auf
/// beiden Systemen keine [KeyEvent]s, sondern Texteingaben.
class TastaturWaechter extends ChangeNotifier {
  TastaturWaechter() {
    _abo = const EventChannel(
      'werkbank/tastatur',
    ).receiveBroadcastStream().listen(_systemMeldung, onError: (_) {});
    HardwareKeyboard.instance.addHandler(_tastendruck);
  }

  StreamSubscription<dynamic>? _abo;
  bool _vomSystem = false;
  bool _vonTasten = false;

  /// Von Hand übersteuert: `null` heißt automatisch.
  bool? _manuell;

  bool get vorhanden => _manuell ?? (_vomSystem || _vonTasten);
  bool? get manuell => _manuell;

  set manuell(bool? wert) {
    _manuell = wert;
    notifyListeners();
  }

  void _systemMeldung(dynamic wert) {
    _vomSystem = wert == true;
    // Abgesteckt heißt abgesteckt, auch wenn vorher getippt wurde.
    if (!_vomSystem) _vonTasten = false;
    notifyListeners();
  }

  bool _tastendruck(KeyEvent e) {
    if (!_vonTasten && e is KeyDownEvent && _istEchteTaste(e)) {
      _vonTasten = true;
      notifyListeners();
    }
    return false;
  }

  /// Shift allein zählt nicht: manche Android-Bildschirmtastaturen schicken es.
  bool _istEchteTaste(KeyDownEvent e) {
    final k = e.logicalKey;
    return e.deviceType == KeyEventDeviceType.keyboard &&
        k != LogicalKeyboardKey.shiftLeft &&
        k != LogicalKeyboardKey.shiftRight;
  }

  @override
  void dispose() {
    _abo?.cancel();
    HardwareKeyboard.instance.removeHandler(_tastendruck);
    super.dispose();
  }
}
