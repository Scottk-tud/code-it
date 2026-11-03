import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../konstanten.dart';

/// Artemis hat geantwortet, aber nicht mit 2xx.
class ArtemisFehler implements Exception {
  ArtemisFehler(this.status, this.meldung, {this.schluessel});
  final int status;
  final String meldung;

  /// `errorKey` aus der Problem-JSON von Artemis, z. B. `exerciseDueDateOver`.
  final String? schluessel;

  @override
  String toString() => 'Artemis $status: $meldung';
}

/// Artemis war gar nicht zu erreichen — meistens fehlt eduVPN.
class NetzFehler implements Exception {
  NetzFehler(this.grund);
  final String grund;
  @override
  String toString() => grund;
}

/// Dünne Schicht über `http`: Basis-URL, Bearer-Token, JSON, Fehler.
///
/// Artemis nimmt das JWT als Cookie oder als `Authorization: Bearer`. Bearer ist
/// für eine App die richtige Wahl; beides gleichzeitig weist der Server ab.
class ArtemisKlient {
  ArtemisKlient({this.basis = artemisBasis, http.Client? http})
    : _http = http ?? _neuerKlient();

  final String basis;
  final http.Client _http;
  String? token;

  /// Wird bei 401 gerufen; darf sich neu anmelden und `true` liefern, dann wird
  /// die Anfrage einmal wiederholt.
  Future<bool> Function()? beiAbgelaufen;

  static http.Client _neuerKlient() => http.Client();

  Uri _uri(String pfad, [Map<String, String>? abfrage]) {
    final u = Uri.parse('$basis/$pfad');
    return abfrage == null ? u : u.replace(queryParameters: abfrage);
  }

  Map<String, String> _kopf({bool json = true}) => {
    'User-Agent': nutzerAgent,
    'Accept': 'application/json, text/plain, */*',
    if (json) 'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<http.Response> roh(
    String methode,
    String pfad, {
    Map<String, String>? abfrage,
    Object? koerper,
    bool alsText = false,
    bool wiederholt = false,
  }) async {
    final anfrage = http.Request(methode, _uri(pfad, abfrage))
      ..headers.addAll(_kopf(json: !alsText));
    if (koerper != null) {
      if (alsText) {
        anfrage.headers['Content-Type'] = 'text/plain; charset=utf-8';
        anfrage.body = koerper as String;
      } else {
        anfrage.body = jsonEncode(koerper);
      }
    }
    http.Response antwort;
    final uhr = Stopwatch()..start();
    try {
      antwort = await http.Response.fromStream(
        await _http.send(anfrage).timeout(anfrageFrist),
      );
      unawaited(
        _protokoll(
          '$methode $pfad → ${antwort.statusCode} in ${uhr.elapsedMilliseconds} ms, '
          '${antwort.bodyBytes.length} B',
        ),
      );
      if (_protokollAn) unawaited(_antwortAblegen(pfad, antwort.bodyBytes));
    } on SocketException catch (e) {
      unawaited(
        _protokoll(
          '$methode $pfad → ${e.message} nach ${uhr.elapsedMilliseconds} ms',
        ),
      );
      throw NetzFehler(_netzGrund(e));
    } on TimeoutException {
      unawaited(
        _protokoll(
          '$methode $pfad → Zeitüberschreitung nach ${uhr.elapsedMilliseconds} ms',
        ),
      );
      throw NetzFehler('Artemis antwortet nicht.');
    } on http.ClientException catch (e) {
      unawaited(
        _protokoll(
          '$methode $pfad → ${e.message} nach ${uhr.elapsedMilliseconds} ms',
        ),
      );
      throw NetzFehler(e.message);
    } on HandshakeException {
      throw NetzFehler('TLS-Verbindung zu Artemis gescheitert.');
    }

    if (antwort.statusCode == 401 && !wiederholt && beiAbgelaufen != null) {
      if (await beiAbgelaufen!()) {
        return roh(
          methode,
          pfad,
          abfrage: abfrage,
          koerper: koerper,
          alsText: alsText,
          wiederholt: true,
        );
      }
    }
    if (antwort.statusCode >= 400) throw _fehlerAus(antwort);
    return antwort;
  }

  Future<dynamic> json(
    String methode,
    String pfad, {
    Map<String, String>? abfrage,
    Object? koerper,
  }) async {
    final a = await roh(methode, pfad, abfrage: abfrage, koerper: koerper);
    if (a.bodyBytes.isEmpty) return null;
    final text = utf8.decode(a.bodyBytes);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  Future<dynamic> get(String pfad, {Map<String, String>? abfrage}) =>
      json('GET', pfad, abfrage: abfrage);
  Future<dynamic> post(
    String pfad, {
    Object? koerper,
    Map<String, String>? abfrage,
  }) => json('POST', pfad, koerper: koerper ?? const {}, abfrage: abfrage);
  Future<dynamic> put(
    String pfad, {
    Object? koerper,
    Map<String, String>? abfrage,
  }) => json('PUT', pfad, koerper: koerper, abfrage: abfrage);
  Future<dynamic> delete(String pfad, {Map<String, String>? abfrage}) =>
      json('DELETE', pfad, abfrage: abfrage);

  Future<String> text(String pfad, {Map<String, String>? abfrage}) async {
    final a = await roh('GET', pfad, abfrage: abfrage);
    return utf8.decode(a.bodyBytes, allowMalformed: true);
  }

  /// Mit `--dart-define=PROTOKOLL=true` landet jede Anfrage samt Dauer in
  /// `Documents/protokoll.txt`. Ein Release-Build auf iOS gibt `print` nicht an
  /// `devicectl --console` weiter; die Datei holt
  /// `devicectl device copy from --domain-type appDataContainer` ab.
  static const _protokollAn = bool.fromEnvironment('PROTOKOLL');
  static File? _protokollDatei;

  /// Antworten im Protokoll-Build zum Nachstellen in Tests. Bleiben auf dem
  /// Gerät, bis sie jemand per devicectl abholt.
  static Future<void> _antwortAblegen(String pfad, List<int> koerper) async {
    final ordner = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/antworten',
    );
    await ordner.create(recursive: true);
    await File(
      '${ordner.path}/${pfad.replaceAll('/', '_')}.json',
    ).writeAsBytes(koerper);
  }

  /// Auch für Fehler außerhalb des Netzes, z. B. beim Lesen einer Antwort.
  static Future<void> protokolliere(String zeile) => _protokoll(zeile);

  static Future<void> _protokoll(String zeile) async {
    if (!_protokollAn) return;
    _protokollDatei ??= File(
      '${(await getApplicationDocumentsDirectory()).path}/protokoll.txt',
    );
    final jetzt = DateTime.now().toIso8601String().substring(11, 23);
    await _protokollDatei!.writeAsString(
      '$jetzt $zeile\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static String _netzGrund(SocketException e) {
    final m =
        e.message.toLowerCase() + (e.osError?.message.toLowerCase() ?? '');
    if (m.contains('host lookup') ||
        m.contains('nodename') ||
        m.contains('no address')) {
      return 'Artemis nicht gefunden. Ist eduVPN verbunden?';
    }
    return 'Keine Verbindung zu Artemis. Ist eduVPN verbunden?';
  }

  static ArtemisFehler _fehlerAus(http.Response a) {
    String meldung = switch (a.statusCode) {
      401 => 'Nicht angemeldet.',
      403 => 'Keine Berechtigung.',
      404 => 'Nicht gefunden.',
      409 => 'Konflikt mit dem Stand auf dem Server.',
      429 => 'Zu viele Anfragen. Kurz warten.',
      >= 500 => 'Artemis hat einen Fehler gemeldet.',
      _ => 'Anfrage abgelehnt.',
    };
    String? schluessel;
    try {
      final d = jsonDecode(utf8.decode(a.bodyBytes));
      if (d is Map) {
        schluessel = d['errorKey'] as String? ?? d['message'] as String?;
        final t = d['title'] ?? d['detail'];
        if (t is String && t.isNotEmpty) meldung = t;
      }
    } catch (_) {}
    return ArtemisFehler(a.statusCode, meldung, schluessel: schluessel);
  }
}
