import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'field_session.dart';

class MeshCorePairingPrompt extends StatefulWidget {
  const MeshCorePairingPrompt({required this.session, super.key});
  final MeshCoreFieldSession session;

  @override
  State<MeshCorePairingPrompt> createState() => _MeshCorePairingPromptState();
}

class _MeshCorePairingPromptState extends State<MeshCorePairingPrompt> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.clear();
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pin.text;
    _pin.clear();
    widget.session.submitPairingPin(pin);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('meshcore-pairing-pin'),
          controller: _pin,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(
            labelText: 'MeshCore Bluetooth PIN',
            helperText: 'Use the six-digit PIN displayed by your radio or configured in MeshCore.',
            helperMaxLines: 3,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_pin.text.length == 6) _submit();
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _pin.text.length == 6 ? _submit : null,
              child: const Text('Submit MeshCore PIN'),
            ),
            TextButton(
              onPressed: () => unawaited(widget.session.disconnect()),
              child: const Text('Cancel pairing'),
            ),
          ],
        ),
      ],
    ),
  );
}
