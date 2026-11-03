import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:werkbank/api/artemis.dart';
import 'package:werkbank/api/klient.dart';

/// Prüft Pfade, Köpfe und Körper gegen das, was Artemis 10.2 erwartet.
/// Ohne Konto ist das der einzige Beweis für die echte Schnittstelle.
void main() {
  late List<http.Request> anfragen;
  late Map<String, http.Response Function(http.Request)> antworten;

  HttpArtemis artemis() {
    anfragen = [];
    final k = ArtemisKlient(
      basis: 'https://artemis.test',
      http: MockClient((r) async {
        anfragen.add(r);
        final schluessel = '${r.method} ${r.url.path}';
        final a = antworten[schluessel];
        if (a == null) return http.Response('', 404);
        return a(r);
      }),
    );
    return HttpArtemis(k);
  }

  setUp(() => antworten = {});

  test('Anmeldung schickt JSON, User-Agent und liest access_token', () async {
    antworten['POST /api/core/public/authenticate'] = (_) => http.Response(
      jsonEncode({'access_token': 'abc'}),
      200,
      headers: {'set-cookie': 'jwt=abc; HttpOnly'},
    );
    final a = artemis();
    expect(await a.anmelden('max.muster', 'geheim'), 'abc');
    final r = anfragen.single;
    expect(jsonDecode(r.body), {
      'username': 'max.muster',
      'password': 'geheim',
      'rememberMe': true,
    });
    expect(r.headers['User-Agent'], isNotEmpty);
    expect(r.headers.containsKey('Authorization'), isFalse);
  });

  test('danach Bearer, nie zusätzlich ein Cookie', () async {
    antworten['GET /api/core/public/account'] = (_) =>
        http.Response(jsonEncode({'login': 'max', 'name': 'Max Muster'}), 200);
    final a = artemis();
    a.k.token = 'abc';
    final n = await a.konto();
    expect(n?.name, 'Max Muster');
    expect(anfragen.single.headers['Authorization'], 'Bearer abc');
    expect(anfragen.single.headers.containsKey('cookie'), isFalse);
  });

  test('204 beim Konto heißt nicht angemeldet', () async {
    antworten['GET /api/core/public/account'] = (_) => http.Response('', 204);
    expect(await artemis().konto(), isNull);
  });

  test('Dateien werden einzeln geholt, Binärdateien übersprungen', () async {
    antworten['GET /api/programming/participations/7/repository/files'] = (_) =>
        http.Response(
          jsonEncode({
            'src': 'FOLDER',
            'src/A.java': 'FILE',
            'lib/x.jar': 'FILE',
          }),
          200,
        );
    antworten['GET /api/programming/participations/7/repository/file'] = (r) =>
        http.Response.bytes(
          utf8.encode('// ${r.url.queryParameters['file']} äö'),
          200,
        );
    final inhalte = await artemis().inhalte(7);
    expect(inhalte, {'src/A.java': '// src/A.java äö'});
    expect(anfragen.where((r) => r.url.path.endsWith('/file')).length, 1);
  });

  test('Speichern ohne und mit Abgabe', () async {
    antworten['PUT /api/programming/participations/7/repository/files'] = (_) =>
        http.Response(jsonEncode({'src/A.java': null}), 200);
    final a = artemis();
    final s = await a.speichern(7, {'src/A.java': 'x'}, abgeben: false);
    expect(s.ok, isTrue);
    expect(anfragen.last.url.queryParameters['commit'], 'false');
    expect(jsonDecode(anfragen.last.body), [
      {'fileName': 'src/A.java', 'fileContent': 'x'},
    ]);
    await a.speichern(7, {}, abgeben: true);
    expect(anfragen.last.url.queryParameters['commit'], 'true');
  });

  test('Dateifehler und Konflikt kommen als Speicherstand zurück', () async {
    antworten['PUT /api/programming/participations/7/repository/files'] = (_) =>
        http.Response(
          jsonEncode({'src/B.java': 'File could not be found.'}),
          200,
        );
    final a = artemis();
    final s = await a.speichern(7, {'src/B.java': 'x'}, abgeben: false);
    expect(s.fehlerDateien.keys, ['src/B.java']);

    antworten['PUT /api/programming/participations/7/repository/files'] = (_) =>
        http.Response(jsonEncode({'detail': 'checkoutConflict'}), 409);
    expect(
      (await a.speichern(7, {'src/A.java': 'x'}, abgeben: false)).konflikt,
      isTrue,
    );
  });

  test('Ergebnis: leerer Körper ist kein Ergebnis, Tests über testCase', () async {
    antworten['GET /api/programming/programming-exercise-participations/7/latest-result-with-feedbacks'] =
        (_) => http.Response('', 200);
    final a = artemis();
    expect(await a.letztesErgebnis(7), isNull);

    antworten['GET /api/programming/programming-exercise-participations/7/latest-result-with-feedbacks'] =
        (_) => http.Response(
          jsonEncode({
            'id': 5,
            'score': 50.0,
            'successful': false,
            'testCaseCount': 2,
            'passedTestCaseCount': 1,
            'submission': {'buildFailed': false, 'commitHash': 'abc'},
            'feedbacks': [
              {
                'id': -2,
                'positive': true,
                'hasLongFeedbackText': false,
                'testCase': {'id': 11, 'testName': 'testA'},
              },
              {
                'id': -4,
                'positive': false,
                'detailText': 'kurz [...]',
                'hasLongFeedbackText': true,
                'testCase': {'id': 12, 'testName': 'testB'},
              },
            ],
          }),
          200,
        );
    antworten['GET /api/assessment/feedbacks/-4/long-feedback'] = (_) =>
        http.Response(
          'ganz langer Text',
          200,
          headers: {'content-type': 'text/plain'},
        );
    final e = (await a.letztesErgebnis(7))!;
    expect(e.prozent, 50);
    expect(e.rueckmeldungen.map((r) => r.testId), [11, 12]);
    expect(e.rueckmeldungen.last.detail, 'ganz langer Text');
  });

  test('Netzfehler wird zu NetzFehler', () async {
    final k = ArtemisKlient(
      basis: 'https://artemis.test',
      http: MockClient(
        (_) async => throw http.ClientException('Failed host lookup'),
      ),
    );
    expect(() => HttpArtemis(k).kurse(), throwsA(isA<NetzFehler>()));
  });

  test('Kurse aus for-dashboard mit Aufgaben und Teilnahme', () async {
    antworten['GET /api/course/courses/for-dashboard'] = (_) => http.Response(
      jsonEncode({
        'courses': [
          {
            'course': {
              'id': 3,
              'title': 'ST1',
              'exercises': [
                {
                  'type': 'programming',
                  'id': 9,
                  'title': 'Taxi',
                  'dueDate': '2026-10-20T21:59:00Z',
                  'programmingLanguage': 'JAVA',
                  'studentParticipations': [
                    {'id': 40, 'testRun': true},
                    {
                      'id': 41,
                      'testRun': false,
                      'submissions': [
                        {
                          'buildFailed': false,
                          'results': [
                            {'id': 1, 'score': 80.0},
                          ],
                        },
                      ],
                    },
                  ],
                },
                // Noch nicht gestartet: Artemis lässt die Liste dann ganz weg.
                {'type': 'programming', 'id': 10, 'title': 'Neu'},
              ],
            },
          },
        ],
      }),
      200,
    );
    final kurse = await artemis().kurse();
    expect(kurse.single.aufgaben.last.teilnahme, isNull);
    final a = kurse.single.aufgaben.first;
    expect(a.sprache, 'JAVA');
    expect(a.teilnahme?.id, 41);
    expect(a.teilnahme?.letztes?.prozent, 80);
  });
}
