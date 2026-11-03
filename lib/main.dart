import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'api/klient.dart';
import 'ansichten/anmeldung.dart';
import 'ansichten/kurse.dart';
import 'ansichten/statusleiste.dart';
import 'ansichten/thema.dart';
import 'zustand/sitzung.dart';
import 'zustand/tastatur.dart';

const _demo = bool.fromEnvironment('DEMO');
const _protokoll = bool.fromEnvironment('PROTOKOLL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Sitzung(demo: _demo)..starten()),
        ChangeNotifierProvider(create: (_) => TastaturWaechter()),
      ],
      child: const CodeIt(),
    ),
  );
}

class CodeIt extends StatelessWidget {
  const CodeIt({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Code It!',
      debugShowCheckedModeBanner: false,
      theme: thema(Brightness.light),
      darkTheme: thema(Brightness.dark),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Eingang(),
      navigatorObservers: [if (_protokoll) _Wegprotokoll()],
      builder: (context, kind) => OhneStatusleistenTipp(
        child: _protokoll ? _Eingabeprotokoll(child: kind!) : kind!,
      ),
    );
  }
}

/// Im Protokoll-Build: wer welche Route öffnet und schließt, mit Aufrufer.
class _Wegprotokoll extends NavigatorObserver {
  String _name(Route<dynamic>? r) => '${r.runtimeType}';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      ArtemisKlient.protokolliere('Route auf: ${_name(route)}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final stapel = StackTrace.current
        .toString()
        .split('\n')
        .take(14)
        .join('\n');
    ArtemisKlient.protokolliere('Route zu: ${_name(route)}\n$stapel');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      ArtemisKlient.protokolliere('Route entfernt: ${_name(route)}');
}

/// Im Protokoll-Build: Berührungen, Tasten, Fokus und Tastatureinzug mit
/// Zeitstempel, um Ereignisse zu finden, die Dialoge schließen.
class _Eingabeprotokoll extends StatefulWidget {
  const _Eingabeprotokoll({required this.child});
  final Widget child;

  @override
  State<_Eingabeprotokoll> createState() => _EingabeprotokollState();
}

class _EingabeprotokollState extends State<_Eingabeprotokoll>
    with WidgetsBindingObserver {
  void _log(String s) => ArtemisKlient.protokolliere(s);

  bool _taste(KeyEvent e) {
    _log(
      'Taste ${e.runtimeType} ${e.logicalKey.debugName} (${e.deviceType.name})',
    );
    return false;
  }

  void _fokus() => _log(
    'Fokus: ${FocusManager.instance.primaryFocus?.debugLabel ?? FocusManager.instance.primaryFocus?.context?.widget.runtimeType}',
  );

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_taste);
    FocusManager.instance.addListener(_fokus);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    final v = View.of(context);
    _log(
      'Einzug unten ${(v.viewInsets.bottom / v.devicePixelRatio).round()} pt, '
      'Fläche ${(v.physicalSize.width / v.devicePixelRatio).round()}×${(v.physicalSize.height / v.devicePixelRatio).round()}',
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_taste);
    FocusManager.instance.removeListener(_fokus);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) => _log(
      'Finger ab ${e.kind.name} #${e.pointer} bei ${e.position.dx.round()},${e.position.dy.round()}',
    ),
    onPointerUp: (e) => _log('Finger auf ${e.kind.name} #${e.pointer}'),
    onPointerCancel: (e) =>
        _log('Finger abgebrochen ${e.kind.name} #${e.pointer}'),
    child: widget.child,
  );
}

class _Eingang extends StatelessWidget {
  const _Eingang();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Sitzung>();
    return switch (s.stand) {
      Anmeldestand.pruefe => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      Anmeldestand.abgemeldet => const Anmeldung(),
      Anmeldestand.angemeldet => const Kursuebersicht(),
    };
  }
}
