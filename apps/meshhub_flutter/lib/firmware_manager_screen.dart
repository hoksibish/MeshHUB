import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'firmware_manager_service.dart';
import 'firmware_hardware_catalog.dart';
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
  FirmwareFamily selectedFamily = FirmwareFamily.meshCore;
  bool eraseFirst = false;
  FirmwareBoardCatalog? catalog;
  String? selectedBoardId;
  String boardSearch = '';

  @override
  void initState() {
    super.initState();
    service = widget.service ?? FirmwareManagerService();
    unawaited(_loadCatalog());
    unawaited(_loadSaved());
  }

  @override
  void dispose() {
    filePath.dispose();
    portPath.dispose();
    publishedDigest.dispose();
    super.dispose();
  }

  FirmwareBoard? get selectedBoard => catalog?.byId(selectedBoardId);

  List<FirmwareBoard> get currentBoards =>
      catalog?.forFamily(selectedFamily.name) ?? <FirmwareBoard>[];

  Future<void> _loadCatalog() async {
    try {
      final loaded = await FirmwareBoardCatalog.load();
      if (!mounted) return;
      setState(() {
        catalog = loaded;
        selectedBoardId = selectedFamily == FirmwareFamily.meshCore
            ? 'meshcore-heltec-v3'
            : 'meshtastic-heltec-v3';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Offline board catalog could not be loaded. USB flashing disabled.',
        );
      }
    }
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
        '--title=Select offline firmware for the selected board',
        '--file-filter=Firmware files | *.bin *.uf2 *.zip',
      ]);
      if (result.exitCode != 0) return;
      final path = result.stdout.toString().trim();
      if (path.isEmpty || !mounted) return;
      filePath.text = path;
      await _inspect();
    } on ProcessException {
      if (mounted) {
        setState(
          () => status =
              'File picker not installed. Paste the full .bin path instead.',
        );
      }
    }
  }

  Future<void> _inspect() async {
    setState(() {
      selectedImage = null;
      checkedPort = null;
    });
    await _run(
      'Inspecting firmware file and computing SHA-256...',
      () async {
        final board = selectedBoard;
        if (board == null) {
          throw StateError('Choose a supported board before importing.');
        }
        final image = await service.inspectFile(
          filePath.text,
          expectedSha256: publishedDigest.text,
          expectedFamily: selectedFamily,
          board: board,
        );
        if (!mounted) return;
        setState(() {
          selectedImage = image;
          checkedPort = null;
        });
      },
      completedStatus:
          'Image inspected locally; publisher authenticity is not verified.',
    );
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
      setState(
        () => status =
            'Disconnect MeshHub Bluetooth radio session before USB flashing.',
      );
      return;
    }
    final board = selectedBoard;
    if (board == null || !board.supportsUsbFlash) {
      setState(
        () => status = 'This board needs the guided UF2/DFU method; USB esptool is disabled.',
      );
      return;
    }
    await _run(
      'Checking USB chip (read-only)...',
      () async {
        checkedPort = null;
        await service.checkUsb(portPath.text.trim(), chip: board.chip!);
        if (mounted) setState(() => checkedPort = portPath.text.trim());
      },
      completedStatus: 'USB preflight confirmed ESP32-S3. No flash performed.',
    );
  }

  Future<bool> _confirmFlash() async {
    final image = selectedImage;
    if (image == null) return false;
    final typed = TextEditingController();
    bool backup = false;
    bool device = false;
    final phrase = eraseFirst ? 'ERASE' : 'FLASH';
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, changeDialog) => AlertDialog(
                title: Text(
                  eraseFirst
                      ? 'Confirm FULL ERASE and firmware installation'
                      : 'Confirm firmware installation',
                ),
                content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target: ${selectedBoard?.name ?? image.package.boardId} / '
                          '${selectedBoard?.architecture ?? 'unknown'}\n'
                          'Firmware: ${image.package.displayName}\n'
                          'Image: ${image.package.format} @ ${image.package.flashOffset}',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          eraseFirst
                              ? 'A FULL CHIP ERASE permanently deletes '
                                    'identity, keys, Bluetooth pairing, channels '
                                    'and settings before the new firmware is written. '
                                    'MeshHub does not create a backup.'
                              : 'Writing a full factory/merged image can overwrite '
                                    'the bootloader and partitions, affect '
                                    'Bluetooth pairing and settings, or leave a '
                                    'node unbootable. No backup is made by MeshHub.',
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
                            'I verified this is my Heltec V3, the firmware '
                            'family, version, role and source, and stable USB power.',
                          ),
                          onChanged: (v) =>
                              changeDialog(() => device = v ?? false),
                        ),
                        TextField(
                          controller: typed,
                          decoration: InputDecoration(
                            labelText: 'Type $phrase to confirm',
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
                    onPressed: backup && device && typed.text == phrase
                        ? () => Navigator.pop(dialogContext, true)
                        : null,
                    child: Text(
                      eraseFirst ? 'Erase and flash device' : 'Flash device',
                    ),
                  ),
                ],
              ),
            ),
          ) ??
          false;
    } finally {
      typed.dispose();
    }
  }

  Future<void> _flash() async {
    final image = selectedImage;
    if (image == null ||
        !image.package.supportsDirectUsb ||
        selectedBoard?.id != image.package.boardId ||
        widget.radioConnected() ||
        checkedPort != portPath.text.trim() ||
        busy) {
      return;
    }
    final confirmed = await _confirmFlash();
    if (!confirmed || !mounted || widget.radioConnected()) return;
    await _run(
      'Flashing over USB; do not unplug or close MeshHub...',
      () async {
        await service.flashMergedImage(
          image: image,
          port: portPath.text.trim(),
          userConfirmed: true,
          eraseFirst: eraseFirst,
          eraseConfirmed: eraseFirst,
          mayWrite: () => !widget.radioConnected(),
        );
        if (mounted) {
          setState(() {
            checkedPort = null;
            eraseFirst = false;
          });
        }
      },
      completedStatus: selectedFamily == FirmwareFamily.meshtastic
          ? 'USB flash command completed. Verify boot and configure in the '
                'Meshtastic app; MeshHub Meshtastic messaging is not yet supported.'
          : 'USB flash command completed. Verify device boot, identity, '
                'role and radio settings before transmitting.',
    );
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
              Icon(
                icon,
                size: 19,
                color: Theme.of(context).colorScheme.primary,
              ),
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
      return TacticalHudPanel(padding: EdgeInsets.zero, child: content);
    }
    return Card(child: content);
  }

  Widget _imageDetails(BuildContext context, OfflineFirmwareImage image) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          image.sourceName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '${(image.bytes / (1024 * 1024)).toStringAsFixed(2)} MiB · ${image.package.format}',
        ),
        const SizedBox(height: 3),
        Text(image.package.displayName),
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
    final canFlash =
        Platform.isLinux &&
        !busy &&
        !widget.radioConnected() &&
        selectedImage?.package.supportsDirectUsb == true &&
        selectedImage?.package.boardId == selectedBoardId &&
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
        const Text(
          'Local firmware library · manual USB flashing · no internet required',
        ),
        const SizedBox(height: 14),
        _section(
          context,
          title: 'Hardware and firmware',
          icon: Icons.memory_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final family in FirmwareFamily.values)
                    ChoiceChip(
                      label: Text(family.label),
                      selected: selectedFamily == family,
                      onSelected: busy
                          ? null
                          : (_) => setState(() {
                              selectedFamily = family;
                              selectedBoardId =
                                  family == FirmwareFamily.meshCore
                                  ? 'meshcore-heltec-v3'
                                  : 'meshtastic-heltec-v3';
                              selectedImage = null;
                              checkedPort = null;
                              boardSearch = '';
                              eraseFirst = false;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Filter supported hardware',
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Heltec, T-Beam, RAK, T114…',
                ),
                onChanged: (text) => setState(() => boardSearch = text),
              ),
              const SizedBox(height: 8),
              if (catalog == null)
                const Text('Loading offline hardware catalog…')
              else
                DropdownButton<String>(
                  isExpanded: true,
                  value: currentBoards.any((b) => b.id == selectedBoardId)
                      ? selectedBoardId
                      : null,
                  hint: const Text('Choose an exact board model'),
                  items: currentBoards
                      .where(
                        (board) =>
                            board.id == selectedBoardId ||
                            boardSearch.isEmpty ||
                            board.name.toLowerCase().contains(
                              boardSearch.toLowerCase(),
                            ),
                      )
                      .map(
                        (board) => DropdownMenuItem<String>(
                          value: board.id,
                          child: Text(
                            board.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (id) => setState(() {
                          selectedBoardId = id;
                          selectedImage = null;
                          checkedPort = null;
                          eraseFirst = false;
                        }),
                ),
              const SizedBox(height: 6),
              if (selectedBoard != null) ...[
                Text(
                  '${selectedBoard!.architecture.toUpperCase()} · '
                  '${selectedBoard!.supportsUsbFlash ? 'USB esptool supported' : 'Guided UF2 / DFU or vendor installation'}',
                ),
                const SizedBox(height: 5),
                Text(
                  'Select the exact hardware revision and a firmware image '
                  'published for it. Chip detection alone cannot distinguish '
                  'boards with different pins or radio modules.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Catalog snapshot: official MeshCore and Meshtastic flasher '
                'targets; works offline. Additional hardware/flash methods '
                'require independent verification.',
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
                onChanged: (_) => setState(() {
                  selectedImage = null;
                  checkedPort = null;
                }),
                decoration: InputDecoration(
                  labelText: 'Local firmware file (.bin / .uf2 / .zip)',
                  hintText: '/home/user/Downloads/board-specific-firmware.bin',
                  helperText:
                      'Use official board-matched release; no online downloads',
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
                        subtitle: Text(
                          '${image.package.displayName}\n'
                          '${image.sha256.substring(0, 16)}… · cached offline',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: busy
                            ? null
                            : () => setState(() {
                                selectedImage = image;
                                selectedFamily = image.package.family;
                                selectedBoardId = image.package.boardId;
                                filePath.text = image.path;
                                publishedDigest.clear();
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
                  helperText:
                      '/dev/ttyACM*, /dev/ttyUSB* or /dev/serial/by-id/*',
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
              if (selectedBoard?.supportsUsbFlash == true) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('firmware-erase-first'),
                  contentPadding: EdgeInsets.zero,
                  value: eraseFirst,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => eraseFirst = value ?? false),
                  title: const Text(
                    'Erase all flash before installation (optional)',
                  ),
                  subtitle: const Text(
                    'Required for some MeshCore ⇄ Meshtastic migrations. '
                    'Deletes device identity, keys, channels and all settings. '
                    'Requires separate ERASE confirmation.',
                  ),
                ),
                const SizedBox(height: 9),
              ],
              if (selectedBoard != null &&
                  !selectedBoard!.supportsUsbFlash) ...[
                const SizedBox(height: 10),
                Text(
                  'GUIDED OFFLINE INSTALL · No automatic write for this board.',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  selectedBoard!.offersUf2
                      ? 'Select a board-matched UF2 file. Enter the board\'s '
                            'documented USB bootloader mode, then copy the UF2 '
                            'file to its BOOT volume using your file manager. '
                            'The board may restart and unmount automatically.'
                      : 'This target requires its vendor-specific bootloader, '
                            'DFU ZIP utility or recovery instructions. A full '
                            'esptool flash is not safe for this board. Use the '
                            'project\'s published offline procedure.',
                ),
                if (selectedImage != null) ...[
                  const SizedBox(height: 6),
                  const Text('Selected offline image path:'),
                  SelectableText(selectedImage!.path),
                ],
              ],
              const SizedBox(height: 9),
              Text(
                'Requires the esptool CLI on this Linux computer. '
                'A full image may overwrite bootloader and partitions. '
                'Erasing is never automatic; no backup or retry is performed.',
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
