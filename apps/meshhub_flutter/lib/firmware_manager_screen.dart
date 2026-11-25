import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'firmware_manager_service.dart';
import 'tactical_hud.dart';

/// Offline-first, Linux-only firmware manager. No firmware is downloaded, and
/// no USB write is triggered by opening this screen, selecting, or inspecting.
class FirmwareManagerScreen extends StatefulWidget {
  const FirmwareManagerScreen({
    required this.tactical,
    required this.radioConnected,
    this.service,
    super.key,
  });

  final bool tactical;
  final bool Function() radioConnected;
  final FirmwareManagerService? service;

  @override
  State<FirmwareManagerScreen> createState() => _FirmwareManagerScreenState();
}

class _FirmwareManagerScreenState extends State<FirmwareManagerScreen> {
  final filePath = TextEditingController();
  final portPath = TextEditingController(text: '/dev/ttyACM0');
  final publishedDigest = TextEditingController();
  late final FirmwareManagerService service;
  OfflineFirmwareImage? selectedImage;
  List<OfflineFirmwareImage> saved = [];
  String? checkedPort;
  bool busy = false;
  String status = 'Choose a supported firmware image to begin.';
  bool success = false;

  @override
  void initState() {
    super.initState();
    service = widget.service ?? FirmwareManagerService();
    unawaited(_loadSaved());
  }

  @override
  void dispose() {
    filePath.dispose();
    portPath.dispose();
    publishedDigest.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    try {
      final images = await service.savedImages();
      if (mounted) setState(() => saved = images);
    } catch (_) {
      if (mounted) {
        setState(() => status = 'Could not read the offline firmware library.');
      }
    }
  }

  Future<void> _run(
    String activeStatus,
    Future<void> Function() task, {
    String? completedStatus,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      success = false;
      status = activeStatus;
    });
    try {
      await task();
      if (mounted) {
        setState(() {
          success = true;
          status = completedStatus ?? 'Operation completed.';
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => status = error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _browse() async {
    if (!Platform.isLinux || busy) return;
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--title=Select offline Heltec V3 firmware',
        '--file-filter=Firmware images | *.bin',
      ]);
      if (result.exitCode != 0) return;
      final path = result.stdout.toString().trim();
      if (path.isEmpty || !mounted) return;
      filePath.text = path;
      await _inspect();
    } on ProcessException {
      if (mounted) {
        setState(() => status =
            'File picker not installed. Paste the full .bin path instead.');
      }
    }
  }

  Future<void> _inspect() async {
    await _run('Inspecting firmware file and computing SHA-256...', () async {
      final image = await service.inspectFile(
        filePath.text,
        expectedSha256: publishedDigest.text,
      );
      if (!mounted) return;
      setState(() {
        selectedImage = image;
        checkedPort = null;
      });
    }, completedStatus: 'Image inspected locally; publisher authenticity is not verified.');
  }

  Future<void> _save() async {
    final image = selectedImage;
    if (image == null) return;
    await _run('Copying firmware into the offline library...', () async {
      final stored = await service.saveOffline(image);
      if (!mounted) return;
      setState(() {
        selectedImage = stored;
        checkedPort = null;
      });
      await _loadSaved();
    }, completedStatus: 'Firmware saved for offline use.');
  }

  Future<void> _checkPort() async {
    if (widget.radioConnected()) {
      setState(() => status =
          'Disconnect MeshHub Bluetooth radio session before USB flashing.');
      return;
    }
    await _run('Checking USB chip (read-only)...', () async {
      checkedPort = null;
      await service.checkUsb(portPath.text.trim());
      if (mounted) setState(() => checkedPort = portPath.text.trim());
    }, completedStatus: 'USB preflight confirmed ESP32-S3. No flash performed.');
  }

  Future<bool> _confirmFlash() async {
    final typed = TextEditingController();
    bool backup = false;
    bool device = false;
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, changeDialog) => AlertDialog(
                title: const Text('Confirm irreversible flash operation'),
                content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'A merged image writes from 0x0 and may overwrite '
                          'bootloader, partitions, stored identity, pairing '
                          'and settings. No backup is made by MeshHub. '
                          'Incorrect firmware can make the node unbootable.',
                        ),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: backup,
                          title: const Text(
                            'I made and verified appropriate backups and accept possible data loss.',
                          ),
                          onChanged: (v) =>
                              changeDialog(() => backup = v ?? false),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: device,
                          title: const Text(
                            'I verified this is my Heltec V3, the firmware source '
                            'and role, and stable USB power.',
                          ),
                          onChanged: (v) =>
                              changeDialog(() => device = v ?? false),
                        ),
                        TextField(
                          controller: typed,
                          decoration: const InputDecoration(
                            labelText: 'Type FLASH to confirm',
                          ),
                          onChanged: (_) => changeDialog(() {}),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: backup && device && typed.text == 'FLASH'
                        ? () => Navigator.pop(dialogContext, true)
                        : null,
                    child: const Text('Flash connected device'),
                  ),
                ],
              ),
            ),
          ) ??
          false;
    } finally {
      // The dialog owns the controller only while it is visible.
      typed.dispose();
    }
  }

  Future<void> _flash() async {
    final image = selectedImage;
    if (image == null ||
        widget.radioConnected() ||
        checkedPort != portPath.text.trim() ||
        busy) {
      return;
    }
    final confirmed = await _confirmFlash();
    if (!confirmed || !mounted || widget.radioConnected()) return;
    await _run('Flashing over USB; do not unplug or close MeshHub...', () async {
      await service.flashMergedImage(
        image: image,
        port: portPath.text.trim(),
        userConfirmed: true,
        mayWrite: () => !widget.radioConnected(),
      );
      if (mounted) setState(() => checkedPort = null);
    }, completedStatus:
        'Flashing command completed. Reconnect and verify firmware, identity and settings.');
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.tactical ? title.toUpperCase() : title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: widget.tactical ? 13 : 16,
                    letterSpacing: widget.tactical ? 0.7 : 0,
                    fontFamily: widget.tactical ? 'monospace' : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
    if (widget.tactical) {
      return TacticalHudPanel(
        padding: EdgeInsets.zero,
        child: content,
      );
    }
    return Card(
      child: content,
    );
  }

  Widget _imageDetails(BuildContext context, OfflineFirmwareImage image) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(image.sourceName, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${(image.bytes / (1024 * 1024)).toStringAsFixed(2)} MiB · ESP32-S3 merged BIN'),
        const SizedBox(height: 5),
        SelectableText(
          'SHA-256: ${image.sha256}',
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canFlash = Platform.isLinux &&
        !busy &&
        !widget.radioConnected() &&
        selectedImage != null &&
        checkedPort == portPath.text.trim();
    final page = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.tactical ? 'FIRMWARE / OFFLINE USB' : 'Firmware Manager',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: widget.tactical ? TacticalHudColors.cyan : null,
          ),
        ),
        const SizedBox(height: 5),
        const Text('Local firmware library · manual USB flashing · no internet required'),
        const SizedBox(height: 14),
        _section(
          context,
          title: 'Target device',
          icon: Icons.memory_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Heltec WiFi LoRa 32 V3 · ESP32-S3'),
              const SizedBox(height: 4),
              const Text('MeshCore Companion · merged .bin image only'),
              const SizedBox(height: 8),
              Text(
                'Other Heltec revisions, Meshtastic, nRF52 and OTA flashing '
                'are not supported by this workflow yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: 'Import firmware file',
          icon: Icons.file_open_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: filePath,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Local firmware .bin path',
                  hintText: '/home/user/Downloads/Heltec_v3_companion...-merged.bin',
                  helperText: 'Official source recommended · no online downloads',
                ),
              ),
              const SizedBox(height: 9),
              TextField(
                controller: publishedDigest,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Published SHA-256 checksum (optional)',
                  helperText: 'Compare with independent publisher checksum when available',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => unawaited(_browse()),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Browse'),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : () => unawaited(_inspect()),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Inspect image'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || selectedImage == null
                        ? null
                        : () => unawaited(_save()),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save for offline use'),
                  ),
                ],
              ),
              if (selectedImage != null) ...[
                const SizedBox(height: 12),
                _imageDetails(context, selectedImage!),
              ],
              const SizedBox(height: 8),
              Text(
                'File name, ESP32 header and calculated SHA-256 are safeguards, '
                'not proof that a firmware file came from an official publisher.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: 'Offline firmware library',
          icon: Icons.inventory_2_outlined,
          child: saved.isEmpty
              ? const Text('No verified firmware files saved locally yet.')
              : Column(
                  children: [
                    for (final image in saved)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.offline_pin_outlined),
                        title: Text(image.sourceName),
                        subtitle: Text('${image.sha256.substring(0, 16)}… · cached offline'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: busy
                            ? null
                            : () => setState(() {
                                  selectedImage = image;
                                  filePath.text = image.path;
                                  checkedPort = null;
                                  status = 'Offline image selected; confirm source before flashing.';
                                }),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: 'USB preflight and flash',
          icon: Icons.usb,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.radioConnected())
                Text(
                  'Disconnect the current MeshHub Bluetooth radio session '
                  'before flashing over USB.',
                  style: TextStyle(color: colors.error),
                ),
              TextField(
                controller: portPath,
                enabled: !busy,
                onChanged: (_) => setState(() => checkedPort = null),
                decoration: const InputDecoration(
                  labelText: 'USB serial port',
                  hintText: '/dev/ttyACM0',
                  helperText: '/dev/ttyACM*, /dev/ttyUSB* or /dev/serial/by-id/*',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy || widget.radioConnected()
                        ? null
                        : () => unawaited(_checkPort()),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Check device (read-only)'),
                  ),
                  FilledButton.icon(
                    onPressed: canFlash ? () => unawaited(_flash()) : null,
                    icon: const Icon(Icons.system_update_alt),
                    label: const Text('Flash firmware'),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                'Requires the esptool CLI on this Linux computer. '
                'A merged flash may overwrite identity, pairing, partitions '
                'or settings. There is no automatic erase, backup or retry.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: 'Operation status',
          icon: success ? Icons.check_circle_outline : Icons.info_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (busy) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(status),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Firmware Manager')),
        body: widget.tactical ? TacticalHudBackdrop(child: page) : page,
      ),
    );
  }
}
