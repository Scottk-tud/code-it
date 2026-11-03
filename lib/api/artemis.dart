import 'dart:typed_data';

import 'modelle.dart';

export 'artemis_http.dart';

/// Alles, was die App von Artemis will. Zwei Umsetzungen: [HttpArtemis] für
/// den echten Server, `DemoArtemis` für Bildschirmfotos und Tests ohne Konto.
abstract class Artemis {
  /// Liefert das JWT.
  Future<String> anmelden(String name, String passwort);
  Future<Nutzer?> konto();

  Future<List<Kurs>> kurse();
  Future<List<Aufgabe>> aufgabenVon(Kurs kurs);

  /// Aufgabe mit Aufgabenstellung und eigener Teilnahme.
  Future<Aufgabe> aufgabe(int id);

  /// Legt das eigene Repository an (erster Klick auf „Aufgabe starten").
  Future<Teilnahme> starten(Aufgabe aufgabe);
  Future<Teilnahme> fortsetzen(Aufgabe aufgabe, Teilnahme teilnahme);

  Future<Map<String, Eintragsart>> dateien(int teilnahme);
  Future<Map<String, String>> inhalte(int teilnahme);

  /// Schreibt Dateien in die Arbeitskopie auf dem Server. Mit [abgeben] folgt
  /// Commit und Push — das ist eine bewertete Abgabe.
  Future<Speicherstand> speichern(
    int teilnahme,
    Map<String, String> dateien, {
    required bool abgeben,
  });

  Future<void> neueDatei(int teilnahme, String pfad);
  Future<void> neuerOrdner(int teilnahme, String pfad);
  Future<void> umbenennen(int teilnahme, String pfad, String neuerName);
  Future<void> loeschen(int teilnahme, String pfad);

  Future<void> holen(int teilnahme);
  Future<void> zuruecksetzen(int teilnahme);

  Future<Ergebnis?> letztesErgebnis(int teilnahme);
  Future<List<BuildZeile>> buildLog(int teilnahme);

  /// `true`, solange eine Abgabe auf ihr Ergebnis wartet.
  Future<bool> wirdGebaut(int teilnahme);

  Future<List<Commit>> verlauf(int teilnahme);

  /// UML-Diagramme der Aufgabenstellung rendert der Server (`@startuml`).
  Future<Uint8List?> plantUml(String quelle, {required bool dunkel});
}
