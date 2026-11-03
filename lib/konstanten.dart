/// Maße, Fristen und Adressen an einer Stelle.
library;

/// Die TU-Dresden-Instanz. Nur im Uninetz oder mit eduVPN erreichbar.
const artemisBasis = 'https://artemis-app.inf.tu-dresden.de';

/// Artemis verlangt einen User-Agent beim Login (`@RequestHeader` ohne Default).
const nutzerAgent = 'CodeIt/1.0 (Flutter; Tablet)';

// ── Layout ──────────────────────────────────────────────────────────────

/// Ab dieser Breite stehen Aufgabe, Dateien und Editor nebeneinander.
/// Ein 11-Zoll-iPad hat quer 1180–1210 pt, hoch 820–834 pt.
const breiteNebeneinander = 1000.0;

/// Darunter wird ein Bereich nach dem anderen gezeigt (Telefon, Split View).
const breiteKompakt = 700.0;

const breiteDateibaum = 240.0;
const breiteSeitenleisteMin = 320.0;
const anteilSeitenleiste = 0.36;

const hoeheTastenleiste = 46.0;
const hoeheKonsoleStandard = 260.0;
const hoeheKonsoleMin = 120.0;

const schriftEditor = 15.0;
const schriftKonsole = 14.0;

// ── Zeiten ──────────────────────────────────────────────────────────────

/// Lokaler Entwurf landet so kurz nach dem letzten Tastendruck auf der Platte.
const entwurfVerzoegerung = Duration(milliseconds: 600);

/// Ungesicherte Änderungen gehen nach so viel Ruhe an den Server (ohne Abgabe).
/// Gespeichert wird ohne Commit, also ohne Bewertung — abgegeben wird nur auf Knopfdruck.
const serverSpeichernNachRuhe = Duration(seconds: 30);

/// Takt, in dem nach einer Abgabe nach dem Ergebnis gefragt wird.
const ergebnisAbfrageTakt = Duration(seconds: 4);
const ergebnisAbfrageFrist = Duration(minutes: 6);

const anfrageFrist = Duration(seconds: 20);
