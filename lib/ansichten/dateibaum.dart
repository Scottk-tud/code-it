import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/klient.dart';
import '../api/modelle.dart';
import '../zustand/arbeitsplatz.dart';

/// Baum aus den flachen Pfaden, die Artemis liefert.
class Dateibaum extends StatefulWidget {
  const Dateibaum({super.key, this.nachAuswahl});

  /// Im kompakten Layout springt die Ansicht danach zum Editor.
  final VoidCallback? nachAuswahl;

  @override
  State<Dateibaum> createState() => _DateibaumState();
}

class _DateibaumState extends State<Dateibaum> {
  final Set<String> _zu = {};

  // Artemis legt Build-Dateien und Ordner wie `.idea` mit ins Repository.
  static bool _verborgen(String p) =>
      p.split('/').any((t) => t.startsWith('.') && t != '.') ||
      p.endsWith('.class');

  @override
  Widget build(BuildContext context) {
    final platz = context.watch<Arbeitsplatz>();
    final f = Theme.of(context).colorScheme;
    final zeilen = _zeilen(platz.eintraege);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Dateien',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: f.onSurfaceVariant),
                ),
              ),
              IconButton(
                tooltip: 'Neue Datei',
                iconSize: 20,
                onPressed: () => _anlegen(context, platz, ordner: false),
                icon: const Icon(Icons.note_add_outlined),
              ),
              IconButton(
                tooltip: 'Neuer Ordner',
                iconSize: 20,
                onPressed: () => _anlegen(context, platz, ordner: true),
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: zeilen.length,
            itemBuilder: (context, i) {
              final (pfad, tiefe, art) = zeilen[i];
              final ordner = art == Eintragsart.ordner;
              final aktiv = pfad == platz.aktiv;
              final geaendert = !ordner && platz.istGeaendert(pfad);
              return Material(
                color: aktiv
                    ? f.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (ordner) {
                      setState(
                        () => _zu.contains(pfad)
                            ? _zu.remove(pfad)
                            : _zu.add(pfad),
                      );
                    } else {
                      platz.oeffnen(pfad);
                      widget.nachAuswahl?.call();
                    }
                  },
                  onLongPress: () => _menue(context, platz, pfad),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 10.0 + tiefe * 16,
                      right: 10,
                    ),
                    child: SizedBox(
                      height: 38,
                      child: Row(
                        children: [
                          Icon(
                            ordner
                                ? (_zu.contains(pfad)
                                      ? Icons.folder_outlined
                                      : Icons.folder_open_outlined)
                                : _symbol(pfad),
                            size: 18,
                            color: ordner ? f.primary : f.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pfad.split('/').last,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: aktiv ? FontWeight.w600 : null,
                                color: geaendert ? f.primary : f.onSurface,
                              ),
                            ),
                          ),
                          if (geaendert)
                            Icon(Icons.circle, size: 8, color: f.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<(String, int, Eintragsart)> _zeilen(Map<String, Eintragsart> eintraege) {
    // Ordner, die nur implizit über Dateipfade existieren, ergänzen.
    final alle = Map.of(eintraege);
    for (final p in eintraege.keys) {
      final t = p.split('/');
      for (var i = 1; i < t.length; i++) {
        alle.putIfAbsent(t.take(i).join('/'), () => Eintragsart.ordner);
      }
    }
    final pfade = alle.keys.where((p) => !_verborgen(p)).toList()
      ..sort((a, b) {
        // Ordner vor Dateien auf jeder Ebene.
        final ta = a.split('/'), tb = b.split('/');
        for (var i = 0; i < ta.length && i < tb.length; i++) {
          if (ta[i] == tb[i]) continue;
          final oa = i < ta.length - 1 || alle[a] == Eintragsart.ordner;
          final ob = i < tb.length - 1 || alle[b] == Eintragsart.ordner;
          if (oa != ob) return oa ? -1 : 1;
          return ta[i].toLowerCase().compareTo(tb[i].toLowerCase());
        }
        return ta.length.compareTo(tb.length);
      });
    return [
      for (final p in pfade)
        if (!_zu.any((z) => p.startsWith('$z/')))
          (p, '/'.allMatches(p).length, alle[p]!),
    ];
  }

  static IconData _symbol(String p) {
    if (p.endsWith('.md')) return Icons.article_outlined;
    if (p.contains('/test/') || p.contains('Test.')) {
      return Icons.science_outlined;
    }
    return Icons.description_outlined;
  }

  Future<void> _anlegen(
    BuildContext context,
    Arbeitsplatz platz, {
    required bool ordner,
  }) async {
    final basis = platz.aktiv?.contains('/') == true
        ? '${platz.aktiv!.substring(0, platz.aktiv!.lastIndexOf('/'))}/'
        : '';
    final name = await _eingabe(
      context,
      ordner ? 'Neuer Ordner' : 'Neue Datei',
      basis,
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    await _versuchen(
      context,
      () => ordner ? platz.neuerOrdner(name) : platz.neueDatei(name),
    );
  }

  Future<void> _menue(
    BuildContext context,
    Arbeitsplatz platz,
    String pfad,
  ) async {
    final wahl = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                pfad,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (platz.istGeaendert(pfad))
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Änderungen verwerfen'),
                onTap: () => Navigator.pop(context, 'verwerfen'),
              ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Umbenennen'),
              onTap: () => Navigator.pop(context, 'umbenennen'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Löschen'),
              onTap: () => Navigator.pop(context, 'loeschen'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (wahl) {
      case 'verwerfen':
        platz.verwerfen(pfad);
      case 'umbenennen':
        final neu = await _eingabe(context, 'Umbenennen', pfad.split('/').last);
        if (neu != null && neu.isNotEmpty && context.mounted) {
          await _versuchen(context, () => platz.umbenennen(pfad, neu));
        }
      case 'loeschen':
        final ja = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('„${pfad.split('/').last}" löschen?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Löschen'),
              ),
            ],
          ),
        );
        if (ja == true && context.mounted) {
          await _versuchen(context, () => platz.loeschen(pfad));
        }
    }
  }

  Future<String?> _eingabe(BuildContext context, String titel, String vorgabe) {
    final c = TextEditingController(text: vorgabe);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titel),
        content: TextField(
          controller: c,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _versuchen(
    BuildContext context,
    Future<void> Function() f,
  ) async {
    try {
      await f();
    } on Exception catch (e) {
      if (!context.mounted) return;
      final text = switch (e) {
        ArtemisFehler a => a.meldung,
        NetzFehler n => n.grund,
        _ => '$e',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}
