import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'meshtastic_session.dart';

class MeshtasticConnectionPanel extends StatefulWidget {
  const MeshtasticConnectionPanel({super.key, required this.session});
  final MeshtasticSession session;

  @override
  State<MeshtasticConnectionPanel> createState() =>
      _MeshtasticConnectionPanelState();
}

class _MeshtasticConnectionPanelState extends State<MeshtasticConnectionPanel> {
  final _pin = TextEditingController();
  bool _wasAwaitingPin = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_update);
  }

  void _update() {
    if (!widget.session.awaitingPin) _pin.clear();
    if (widget.session.awaitingPin && !_wasAwaitingPin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 200),
            ),
          );
        }
      });
    }
    _wasAwaitingPin = widget.session.awaitingPin;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_update);
    widget.session.cancelPin();
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pin.text;
    _pin.clear();
    widget.session.submitPin(pin);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(session.status, key: const Key('meshtastic-status')),
        const SizedBox(height: 8),
        const Text(
          'Connect and pair here; no prior desktop pairing is needed. '
          'Disconnect your phone app first. This version reads device information; '
          'Meshtastic chats and settings editing are not implemented yet.',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: session.active || session.scanning
                  ? null
                  : () => unawaited(session.discover()),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Discover Meshtastic radios'),
            ),
            if (session.active)
              OutlinedButton(
                onPressed: () => unawaited(session.disconnect()),
                child: Text(
                  session.connecting
                      ? 'Cancel connection'
                      : 'Disconnect Meshtastic',
                ),
              ),
          ],
        ),
        if (session.scanning || session.connecting) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        if (session.awaitingPin) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('meshtastic-pairing-pin'),
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
              labelText: 'Six-digit Bluetooth PIN',
              helperText: 'Read the PIN from your node screen. It is not saved by MeshHub.',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_pin.text.length == 6) _submit();
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _pin.text.length == 6 ? _submit : null,
            child: const Text('Submit pairing PIN'),
          ),
        ],
        if (session.error != null) ...[
          const SizedBox(height: 10),
          Text(
            session.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        for (final candidate in session.candidates) ...[
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              candidate.name.isEmpty
                  ? 'Unnamed Meshtastic radio'
                  : candidate.name,
            ),
            subtitle: Text(
              'Meshtastic service · ${candidate.isFresh ? 'seen during scan' : 'cached; availability unverified'}',
            ),
            trailing: TextButton(
              onPressed: session.active || session.scanning
                  ? null
                  : () => unawaited(session.connect(candidate)),
              child: const Text('Pair & connect'),
            ),
          ),
        ],
        if (session.connected) ...[
          const Divider(),
          Text(
            'Node: !${session.nodeNumber!.toRadixString(16).padLeft(8, '0')}',
          ),
          Text('Firmware: ${session.firmwareVersion ?? 'Not reported'}'),
          Text(
            'Hardware: ${session.hardwareModel == 43
                ? 'Heltec V3'
                : session.hardwareModel == null
                ? 'Not reported'
                : 'Meshtastic model ${session.hardwareModel}'}',
          ),
          const Text(
            'Device-reported information · local Bluetooth link verified. '
            'No RF message or settings write performed by MeshHub.',
          ),
        ],
      ],
    );
  }
}
