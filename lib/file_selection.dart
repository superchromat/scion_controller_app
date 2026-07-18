import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'app_alert.dart';
import 'osc_registry.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'app_button.dart';

final GlobalKey<FileManagementSectionState> fileManagementKey = GlobalKey<FileManagementSectionState>();

/// Stateful widget to manage config file I/O and currentFile state.
class FileManagementSection extends StatefulWidget {
  const FileManagementSection({super.key});

  @override
  State<FileManagementSection> createState() => FileManagementSectionState();
}

class FileManagementSectionState extends State<FileManagementSection> {
  String? _currentFile;

  String _displayNameForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'configuration';
    final name = parts.last;
    return name.isEmpty ? 'configuration' : name;
  }

  Rect? _shareOriginRect(BuildContext context) {
    RenderBox? box;
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize && ro.size.width > 0 && ro.size.height > 0) {
      box = ro;
    } else {
      final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
      if (overlay is RenderBox &&
          overlay.hasSize &&
          overlay.size.width > 0 &&
          overlay.size.height > 0) {
        box = overlay;
      }
    }
    if (box == null) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  bool _isClearlyBadPath(String path) {
    return path.trim().isEmpty || path == '/' || path.startsWith('//');
  }

  Future<Directory?> _fallbackWritableDirectory() async {
    final candidates = <Directory>[];

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidates.add(Directory('$home/Documents'));
      candidates.add(Directory('$home/tmp'));
      candidates.add(Directory('$home/Library/Caches'));
      candidates.add(Directory(home));
    }

    candidates.add(Directory.systemTemp);

    for (final dir in candidates) {
      try {
        if (await dir.exists()) return dir;
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _fallbackSavePath(String fileName) async {
    final dir = await _fallbackWritableDirectory();
    if (dir == null) return null;
    return '${dir.path}/$fileName';
  }

  Future<String?> _promptSavePath({
    required String dialogTitle,
    required String fileName,
  }) async {
    try {
      return await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
      );
    } on UnimplementedError {
      // iOS/native platforms may not implement save dialogs in file_picker.
      return _fallbackSavePath(fileName);
    } on UnsupportedError {
      return _fallbackSavePath(fileName);
    }
  }

  Future<void> _save(BuildContext context) async {
    try {
      String? path = _currentFile;
      if (path == null || _isClearlyBadPath(path)) {
        path =
            await _promptSavePath(
              dialogTitle: 'Save Configuration',
              fileName: 'default.config',
            );
      }
      if (path == null) return;

      try {
        await OscRegistry().saveToFile(path);
      } on FileSystemException catch (_) {
        path = await _fallbackSavePath('default.config');
        if (path == null || _isClearlyBadPath(path)) {
          path = await _promptSavePath(
          dialogTitle: 'Save Configuration',
          fileName: 'default.config',
        );
        }
        if (path == null) return;
        await OscRegistry().saveToFile(path);
      }
      setState(() => _currentFile = path);
      showAppAlert(
        context,
        'Configuration saved: ${_displayNameForPath(path)}',
      );
    } catch (e) {
      showAppAlert(context, 'Save failed: $e', tone: AppAlertTone.error);
    }
  }

  Future<void> _export(BuildContext context) async {
    try {
      final dir = await _fallbackWritableDirectory();
      if (dir == null) {
        throw const FileSystemException('No writable export directory found');
      }
      final fileName = _currentFile != null && _currentFile!.trim().isNotEmpty
          ? _currentFile!.split(Platform.pathSeparator).last
          : 'scion_config_export.config';
      final path = '${dir.path}/$fileName';

      await OscRegistry().saveToFile(path);
      await Share.shareXFiles(
        [XFile(path)],
        text: 'SCION configuration export',
        subject: fileName,
        sharePositionOrigin: _shareOriginRect(context),
      );

      showAppAlert(context, 'Exported $fileName');
    } catch (e) {
      showAppAlert(context, 'Export failed: $e', tone: AppAlertTone.error);
    }
  }

  Future<void> _load(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Load Configuration',
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    await OscRegistry().loadFromFile(path);
    setState(() => _currentFile = path);
    showAppAlert(
      context,
      'Configuration loaded: ${_displayNameForPath(path)}',
    );
  }

  void _reset(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Restore'),
        content: const Text('Are you sure you want to restore all settings?'),
        actions: [
          AppButton(
            label: 'Cancel',
            dense: true,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          AppButton(
            label: 'Confirm',
            dense: true,
            accentColor: const Color(0xFFB56A77),
            onPressed: () {
              // Send OSC message to reset configuration to defaults, and echo it
              // locally so client-side overlay state (sprites, etc.) clears too.
              try {
                context.read<Network>().sendOscMessage('/config/reset', const []);
                OscRegistry()
                  ..registerAddress('/config/reset')
                  ..dispatchLocal('/config/reset', const []);
              } catch (_) {}
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = Platform.isIOS;
    return TooltipTheme(
      data: TooltipTheme.of(context).copyWith(
        waitDuration: const Duration(milliseconds: 350),
        showDuration: const Duration(milliseconds: 1200),
        preferBelow: false,
        verticalOffset: 14,
        textStyle: const TextStyle(
          fontFamily: 'DINPro',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.08,
          color: Color(0xFFF0F0F3),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D31),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      child: Row(
        children: [
          if (!isIos)
            AppButton(
              label: 'Save',
              icon: Icons.save,
              onPressed: () => _save(context),
            )
          else
            AppButton(
              label: 'Export',
              icon: Icons.ios_share,
              onPressed: () => _export(context),
            ),
          const SizedBox(width: 10),
          AppButton(
            label: 'Load',
            icon: Icons.folder_open,
            onPressed: () => _load(context),
          ),
          const Spacer(),
          AppButton(
            label: 'Restore to Defaults',
            icon: Icons.restore,
            accentColor: const Color(0xFFB56A77),
            onPressed: () => _reset(context),
          ),
        ],
      ),
    );
  }
}

