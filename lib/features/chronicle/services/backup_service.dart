import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';
import '../models/event_item.dart';
import 'chronicle_repository.dart';

/// Výsledek importu zálohy.
class BackupImportResult {
  const BackupImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.message,
    required this.success,
  });

  final int importedCount;
  final int skippedCount;
  final String message;
  final bool success;
}

/// Robustní služba pro automatické a ruční zálohování dat kroniky.
///
/// Klíčové vlastnosti:
/// 1. Zrcadlí data do veřejné složky Download/FlyLog na Androidu, která PŘEŽIJE
///    i kompletní odinstalaci aplikace.
/// 2. Při čisté instalaci automaticky detekuje existující zálohu v Download
///    a obnoví data bez nutnosti ručního zásahu.
/// 3. Poskytuje možnost zkopírovat kompletní JSON do schránky (pro bezpečné
///    uložení do poznámek či emailu bez závislosti na souborech).
/// 4. Sdílení provádí z trvalého souboru v Download (nikoliv z dočasné cache)
///    a do textu zprávy vkládá i celý JSON pro případ výpadku přílohy.
class BackupService {
  const BackupService();

  static const String _module = LogModule.chronicle;
  static const String autoBackupFileName = 'flylog_auto_backup.json';

  static List<String> get _persistentPathCandidates {
    if (Platform.isAndroid) {
      return const [
        '/storage/emulated/0/Download/FlyLog',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents/FlyLog',
        '/storage/emulated/0/Documents',
      ];
    }
    return const [];
  }

  /// Vrátí seznam dostupných a zapisovatelných adresářů, které přežijí odinstalaci.
  Future<List<Directory>> getPersistentDirectories() async {
    final list = <Directory>[];

    for (final path in _persistentPathCandidates) {
      try {
        final d = Directory(path);
        if (!await d.exists()) {
          await d.create(recursive: true);
        }
        // Test zápisu pro ověření oprávnění
        final testFile = File('${d.path}${Platform.pathSeparator}.test_perm');
        await testFile.writeAsString('ok');
        await testFile.delete();
        list.add(d);
      } catch (_) {}
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      final appBackups = Directory('${docs.path}${Platform.pathSeparator}FlyLog_Backups');
      if (!await appBackups.exists()) {
        await appBackups.create(recursive: true);
      }
      list.add(appBackups);
    } catch (_) {}

    return list;
  }

  /// Automatické tiché zrcadlení databáze do trvalého úložiště.
  /// Volá se automaticky při každé změně v [MockChronicleRepository].
  Future<void> autoBackup(List<EventItem> events) async {
    if (events.isEmpty) return;
    try {
      final jsonStr = _buildJsonString(events);
      final dirs = await getPersistentDirectories();
      for (final dir in dirs) {
        try {
          final file = File('${dir.path}${Platform.pathSeparator}$autoBackupFileName');
          await file.writeAsString(jsonStr, encoding: utf8);
        } catch (_) {}
      }
    } catch (e) {
      AppLogger.I.warn(_module, 'auto_backup_failed', error: e);
    }
  }

  /// Pokusí se najít a načíst nejnovější automatickou zálohu na zařízení
  /// (využívá se při novém startu po odinstalaci nebo obnově).
  Future<List<EventItem>?> findAutoBackupEvents() async {
    final files = await getAvailableBackupFiles();
    if (files.isEmpty) return null;

    for (final file in files) {
      try {
        final content = await file.readAsString(encoding: utf8);
        final Map<String, dynamic> decoded = jsonDecode(content);
        final eventsList = decoded['events'] as List?;
        if (eventsList != null && eventsList.isNotEmpty) {
          final events = <EventItem>[];
          for (final item in eventsList.whereType<Map>()) {
            events.add(EventItem.fromJson(item.cast<String, dynamic>()));
          }
          if (events.isNotEmpty) {
            AppLogger.I.info(_module, 'auto_backup_recovered', metrics: {
              'file': file.path,
              'events_count': events.length,
            });
            return events;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Vrátí všechny nalezené záložní JSON soubory na zařízení seřazené od nejnovějšího.
  Future<List<File>> getAvailableBackupFiles() async {
    final results = <File>[];
    final seenPaths = <String>{};

    final dirs = await getPersistentDirectories();
    for (final dir in dirs) {
      try {
        if (!await dir.exists()) continue;
        final list = dir.listSync().whereType<File>();
        for (final f in list) {
          final name = f.path.split(Platform.pathSeparator).last.toLowerCase();
          if (name.endsWith('.json') && (name.contains('flylog') || name.contains('backup'))) {
            if (seenPaths.add(f.path)) {
              results.add(f);
            }
          }
        }
      } catch (_) {}
    }

    results.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });

    return results;
  }

  /// Uloží zálohu přímo do veřejné složky Download/FlyLog na Androidu.
  Future<String> saveBackupToDownloads(List<EventItem> events) async {
    final jsonStr = _buildJsonString(events);
    final now = DateTime.now();
    final timeStamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = 'flylog_backup_$timeStamp.json';

    final dirs = await getPersistentDirectories();
    String? savedPath;

    for (final dir in dirs) {
      try {
        final targetFile = File('${dir.path}${Platform.pathSeparator}$fileName');
        await targetFile.writeAsString(jsonStr, encoding: utf8);
        savedPath ??= targetFile.path;
      } catch (_) {}
    }

    if (savedPath == null) {
      final temp = await getTemporaryDirectory();
      final targetFile = File('${temp.path}${Platform.pathSeparator}$fileName');
      await targetFile.writeAsString(jsonStr, encoding: utf8);
      savedPath = targetFile.path;
    }

    return savedPath;
  }

  /// Zkopíruje kompletní JSON zálohu do schránky pro snadné vložení kamkoliv.
  Future<String> copyBackupToClipboard(List<EventItem> events) async {
    final jsonStr = _buildJsonString(events);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    return jsonStr;
  }

  /// Otevře systémové sdílení – soubor vytvoří v trvalém úložišti a do textu
  /// zprávy vloží celý JSON jako záchrannou síť pro případ selhání přílohy.
  Future<String> shareBackup(List<EventItem> events) async {
    final filePath = await saveBackupToDownloads(events);
    final jsonStr = _buildJsonString(events);
    final file = File(filePath);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        title: 'Záloha FlyLog (${events.length} událostí)',
        text: 'Záloha rodinné kroniky FlyLog (${events.length} událostí)\n\n'
            '--- KÓD ZÁLOHY (lze přímo vložit v aplikaci přes "Obnovit ze schránky") ---\n$jsonStr',
      ),
    );

    return filePath;
  }

  /// Obnoví data ze zadaného JSON řetězce (např. vloženého ze schránky).
  Future<BackupImportResult> importFromJsonString(String rawJson, [ChronicleRepository? repository]) async {
    final repo = repository ?? ServiceLocator.chronicle;
    try {
      final trimmed = rawJson.trim();
      final Map<String, dynamic> decoded = jsonDecode(trimmed);
      final eventsList = decoded['events'] as List?;
      if (eventsList == null) {
        throw const FormatException('Neplatný formát: chybí seznam "events".');
      }

      final count = await repo.importEventsJson(eventsList);
      return BackupImportResult(
        importedCount: count,
        skippedCount: eventsList.length - count,
        message: 'Úspěšně importováno $count událostí.',
        success: true,
      );
    } catch (e, st) {
      AppLogger.I.error(_module, 'import_string_failed', error: e, stackTrace: st);
      return BackupImportResult(
        importedCount: 0,
        skippedCount: 0,
        message: 'Chyba formátu zálohy: $e',
        success: false,
      );
    }
  }

  /// Obnoví data z vybraného souboru na disku.
  Future<BackupImportResult> importFromFile(File file, [ChronicleRepository? repository]) async {
    try {
      final content = await file.readAsString(encoding: utf8);
      return await importFromJsonString(content, repository);
    } catch (e) {
      return BackupImportResult(
        importedCount: 0,
        skippedCount: 0,
        message: 'Chyba při čtení souboru: $e',
        success: false,
      );
    }
  }

  /// Otevře systémový výběr souborů (.json) a obnoví kroniku.
  Future<BackupImportResult> importBackupWithPicker([ChronicleRepository? repository]) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result.isEmpty || result.first.path == null) {
        return const BackupImportResult(
          importedCount: 0,
          skippedCount: 0,
          message: 'Výběr souboru byl zrušen.',
          success: false,
        );
      }

      return await importFromFile(File(result.first.path!), repository);
    } catch (e, st) {
      AppLogger.I.error(_module, 'backup_picker_failed', error: e, stackTrace: st);
      return BackupImportResult(
        importedCount: 0,
        skippedCount: 0,
        message: 'Chyba při výběru souboru: $e',
        success: false,
      );
    }
  }

  String _buildJsonString(List<EventItem> events) {
    final backupData = {
      'version': 1,
      'app': 'FlyLog',
      'exportedAt': DateTime.now().toIso8601String(),
      'count': events.length,
      'events': events.map((e) => e.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(backupData);
  }
}
