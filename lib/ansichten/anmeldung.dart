import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../zustand/sitzung.dart';

class Anmeldung extends StatefulWidget {
  const Anmeldung({super.key});

  @override
  State<Anmeldung> createState() => _AnmeldungState();
}

class _AnmeldungState extends State<Anmeldung> {
  final _name = TextEditingController();
  final _passwort = TextEditingController();
  final _passwortFokus = FocusNode();
  bool _merken = true;
  bool _laeuft = false;
  bool _zeigen = false;

  Future<void> _los() async {
    if (_name.text.trim().isEmpty || _passwort.text.isEmpty) return;
    setState(() => _laeuft = true);
    await context.read<Sitzung>().anmelden(
      _name.text,
      _passwort.text,
      merken: _merken,
    );
    if (mounted) setState(() => _laeuft = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _passwort.dispose();
    _passwortFokus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final fehler = context.watch<Sitzung>().fehler;
    return Scaffold(
      backgroundColor: f.surfaceContainerLow,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.terminal_rounded, size: 48, color: f.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Code It!',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _name,
                    autofillHints: const [AutofillHints.username],
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _passwortFokus.requestFocus(),
                    decoration: const InputDecoration(
                      labelText: 'Artemis-Benutzername',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwort,
                    focusNode: _passwortFokus,
                    obscureText: !_zeigen,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _los(),
                    decoration: InputDecoration(
                      labelText: 'Artemis-Passwort',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _zeigen ? 'Verbergen' : 'Zeigen',
                        icon: Icon(
                          _zeigen ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _zeigen = !_zeigen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Angemeldet bleiben'),
                    value: _merken,
                    onChanged: (v) => setState(() => _merken = v),
                  ),
                  if (fehler != null) ...[
                    const SizedBox(height: 4),
                    Text(fehler, style: TextStyle(color: f.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _laeuft ? null : _los,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: _laeuft
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Anmelden'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
