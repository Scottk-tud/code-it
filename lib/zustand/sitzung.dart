import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/artemis.dart';
import '../api/demo.dart';
import '../api/klient.dart';
import '../api/modelle.dart';

enum Anmeldestand { pruefe, abgemeldet, angemeldet }

/// Anmeldung und das eine [Artemis]-Objekt, über das alle Ansichten reden.
///
/// Token und – nur mit „Angemeldet bleiben" – Zugangsdaten liegen im
/// Schlüsselbund bzw. Android-Keystore. Mit gespeicherten Zugangsdaten meldet
/// sich die App bei einem abgelaufenen Token still neu an, statt mitten in der
/// Arbeit auf den Anmeldebildschirm zu springen.
class Sitzung extends ChangeNotifier {
  Sitzung({FlutterSecureStorage? speicher, bool demo = false})
    : _speicher = speicher ?? const FlutterSecureStorage(),
      _demo = demo {
    _klient.beiAbgelaufen = _stillNeuAnmelden;
  }

  final FlutterSecureStorage _speicher;
  final bool _demo;
  final _klient = ArtemisKlient();

  late Artemis artemis = _demo ? DemoArtemis() : HttpArtemis(_klient);

  Anmeldestand stand = Anmeldestand.pruefe;
  Nutzer? nutzer;
  String? fehler;

  static const _kToken = 'token',
      _kName = 'nutzername',
      _kPasswort = 'passwort';

  Future<void> starten() async {
    if (_demo) {
      nutzer = await artemis.konto();
      stand = Anmeldestand.angemeldet;
      notifyListeners();
      return;
    }
    _klient.token = await _lesen(_kToken);
    if (_klient.token == null) {
      stand = Anmeldestand.abgemeldet;
      notifyListeners();
      return;
    }
    try {
      nutzer = await artemis.konto();
      stand = nutzer == null
          ? Anmeldestand.abgemeldet
          : Anmeldestand.angemeldet;
    } on NetzFehler {
      // Offline mit gültigem Token: weiterarbeiten, die Entwürfe liegen lokal.
      final name = await _lesen(_kName);
      nutzer = Nutzer(login: name ?? '', name: name ?? '');
      stand = Anmeldestand.angemeldet;
    } on ArtemisFehler {
      stand = Anmeldestand.abgemeldet;
    }
    notifyListeners();
  }

  Future<bool> anmelden(
    String name,
    String passwort, {
    required bool merken,
  }) async {
    fehler = null;
    notifyListeners();
    try {
      _klient.token = await artemis.anmelden(name.trim(), passwort);
      await _speicher.write(key: _kToken, value: _klient.token);
      await _speicher.write(key: _kName, value: name.trim());
      if (merken) {
        await _speicher.write(key: _kPasswort, value: passwort);
      } else {
        await _speicher.delete(key: _kPasswort);
      }
      nutzer = await artemis.konto();
      stand = Anmeldestand.angemeldet;
      notifyListeners();
      return true;
    } on ArtemisFehler catch (e) {
      fehler = switch (e.status) {
        401 => 'Benutzername oder Passwort falsch.',
        400 => 'Benutzername oder Passwort zu kurz.',
        429 => 'Zu viele Versuche. Eine Minute warten.',
        _ => e.meldung,
      };
    } on NetzFehler catch (e) {
      fehler = e.grund;
    }
    notifyListeners();
    return false;
  }

  Future<bool> _stillNeuAnmelden() async {
    final name = await _lesen(_kName), passwort = await _lesen(_kPasswort);
    if (name == null || passwort == null) {
      _abmeldenLokal();
      return false;
    }
    try {
      _klient.token = await artemis.anmelden(name, passwort);
      await _speicher.write(key: _kToken, value: _klient.token);
      return true;
    } catch (_) {
      _abmeldenLokal();
      return false;
    }
  }

  void _abmeldenLokal() {
    _klient.token = null;
    stand = Anmeldestand.abgemeldet;
    notifyListeners();
  }

  Future<void> abmelden() async {
    await _speicher.deleteAll();
    nutzer = null;
    _abmeldenLokal();
  }

  Future<String?> _lesen(String k) async {
    try {
      return await _speicher.read(key: k);
    } catch (_) {
      return null;
    }
  }
}
