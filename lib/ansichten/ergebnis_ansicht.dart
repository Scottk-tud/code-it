import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/modelle.dart';
import '../zustand/arbeitsplatz.dart';
import 'aufgabenstellung.dart';
import 'thema.dart';

/// Letzte Bewertung: Tests, Rückmeldungen, bei gescheitertem Build das Log.
class ErgebnisAnsicht extends StatelessWidget {
  const ErgebnisAnsicht({super.key});

  @override
  Widget build(BuildContext context) {
    final platz = context.watch<Arbeitsplatz>();
    final t = Theme.of(context);
    final f = t.colorScheme;
    final e = platz.ergebnis;

    if (platz.bau == Bauzustand.gibtAb || platz.bau == Bauzustand.baut) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              platz.bau == Bauzustand.gibtAb
                  ? 'Wird abgegeben …'
                  : 'Tests laufen …',
              style: t.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
    if (e == null) {
      return Center(
        child: Text(
          'Noch nicht abgegeben.',
          style: TextStyle(color: f.onSurfaceVariant),
        ),
      );
    }

    final namen = teilaufgabeNachTest(platz.aufgabe.aufgabenstellung);
    var unbenannt = 0;
    String titel(Rueckmeldung r) =>
        r.test ?? namen[r.testId] ?? r.text ?? 'Test ${++unbenannt}';
    final fehlgeschlagen = e.rueckmeldungen
        .where((r) => r.positiv == false)
        .toList();
    final bestanden = e.rueckmeldungen.where((r) => r.positiv == true).toList();
    final sonstige = e.rueckmeldungen.where((r) => r.positiv == null).toList();

    return RefreshIndicator(
      onRefresh: platz.ergebnisNeuLaden,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _Kopf(ergebnis: e),
          const SizedBox(height: 16),
          if (e.buildFehlgeschlagen) ...[
            Text('Build-Log', style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            _BuildLog(zeilen: platz.buildLog),
          ],
          for (final r in [...fehlgeschlagen, ...sonstige, ...bestanden])
            _Test(r: r, titel: titel(r)),
        ],
      ),
    );
  }
}

class _Kopf extends StatelessWidget {
  const _Kopf({required this.ergebnis});
  final Ergebnis ergebnis;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = t.colorScheme;
    final e = ergebnis;
    final p = e.prozent ?? 0;
    final farbe = e.buildFehlgeschlagen || p == 0
        ? f.durchgefallen
        : p >= 100
        ? f.bestanden
        : f.tertiary;
    return Row(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: e.buildFehlgeschlagen ? 1 : (p / 100).clamp(0, 1),
                strokeWidth: 6,
                color: farbe,
                backgroundColor: f.surfaceContainerHighest,
              ),
              Center(
                child: Text(
                  e.buildFehlgeschlagen ? '✗' : '${p.toStringAsFixed(0)}%',
                  style: t.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: farbe,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.buildFehlgeschlagen
                    ? 'Build fehlgeschlagen'
                    : '${e.bestanden ?? '?'} von ${e.tests ?? '?'} Tests bestanden',
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (e.fertig != null)
                Text(
                  DateFormat('E d. MMM, HH:mm', 'de').format(e.fertig!),
                  style: t.textTheme.bodySmall?.copyWith(
                    color: f.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Test extends StatelessWidget {
  const _Test({required this.r, required this.titel});
  final Rueckmeldung r;
  final String titel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = t.colorScheme;
    final (symbol, farbe) = switch (r.positiv) {
      true => (Icons.check_circle_rounded, f.bestanden),
      false => (Icons.cancel_rounded, f.durchgefallen),
      null => (Icons.info_outline_rounded, f.secondary),
    };
    final detail = r.detail?.trim();
    final kopf = Row(
      children: [
        Icon(symbol, size: 20, color: farbe),
        const SizedBox(width: 10),
        Expanded(child: Text(titel, style: t.textTheme.bodyLarge)),
        if (r.punkte != null && r.punkte != 0)
          Text(
            '${r.punkte! > 0 ? '+' : ''}${r.punkte}',
            style: t.textTheme.bodySmall?.copyWith(color: f.onSurfaceVariant),
          ),
      ],
    );
    if (detail == null || detail.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: kopf,
      );
    }
    return Theme(
      data: t.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 30, bottom: 8),
        initiallyExpanded: r.positiv == false,
        title: kopf,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              detail,
              style: TextStyle(
                fontFamilyFallback: monoSchriften,
                fontSize: 13,
                color: f.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildLog extends StatelessWidget {
  const _BuildLog({required this.zeilen});
  final List<BuildZeile> zeilen;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    if (zeilen.isEmpty) {
      return Text(
        'Kein Log verfügbar.',
        style: TextStyle(color: f.onSurfaceVariant),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: f.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText.rich(
        TextSpan(
          children: [
            for (final z in zeilen)
              TextSpan(
                text: '${z.text}\n',
                style: TextStyle(
                  fontFamilyFallback: monoSchriften,
                  fontSize: 12.5,
                  color: z.text.contains('ERROR') || z.text.contains('error')
                      ? f.error
                      : f.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
