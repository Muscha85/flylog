import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';
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

/// Služba pro bezpečný export a obnovu databáze kroniky ve formátu JSON.
class BackupService {
  const BackupService();

  static const String _module = LogModule.chronicle;

  /// Exportuje kompletní databázi kroniky do JSON souboru a nabídne sdílení / uložení.
  Future<String?> exportBackup([ChronicleRepository? repository]) async {
    final repo = repository ?? ServiceLocator.chronicle;
    final sw = Stopwatch()..start();
    try {
      final events = await repo.getEvents();
      final backupData = {
        'version': 1,
        'app': 'FlyLog',
        'exportedAt': DateTime.now().toIso8601String(),
        'count': events.length,
        'events': events.map((e) => e.toJson()).toList(),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(backupData);
      final timeStamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'flylog_backup_$timeStamp.json';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}${Platform.pathSeparator}$fileName');
      await tempFile.writeAsString(jsonStr, encoding: utf8);

      // Zkusíme uložit i kopii do složky Dokumenty/Download, pokud je dostupná
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final backupFolder = Directory('${docsDir.path}${Platform.pathSeparator}FlyLog_Backup');
        if (!await backupFolder.exists()) {
          await backupFolder.create(recursive: true);
        }
        final persistentFile = File('${backupFolder.path}${Platform.pathSeparator}$fileName');
        await persistentFile.writeAsString(jsonStr, encoding: utf8);
      } catch (_) {}

      // Vyvoláme systémový dialog pro sdílení / uložení souboru
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path, mimeType: 'application/json')],
          title: 'Záloha FlyLog ($fileName)',
          text: 'Záloha rodinné kroniky FlyLog (${events.length} událostí)',
        ),
      );

      AppLogger.I.info(_module, 'backup_exported', metrics: {
        'events': events.length,
        'size_kb': (jsonStr.length / 1024).toStringAsFixed(1),
        'duration_ms': sw.elapsedMilliseconds,
      });

      return tempFile.path;
    } catch (e, st) {
      AppLogger.I.error(_module, 'backup_export_failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Otevře souborový dialog, načte JSON zálohu a integruje události do repository.
  Future<BackupImportResult> importBackup([ChronicleRepository? repository]) async {
    final repo = repository ?? ServiceLocator.chronicle;
    final sw = Stopwatch()..start();
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.isEmpty || result.first.path == null) {
        return const BackupImportResult(
          importedCount: 0,
          skippedCount: 0,
          message: 'Výběr souboru byl zrušen.',
          success: false,
        );
      }

      final file = File(result.first.path!);
      final content = await file.readAsString(encoding: utf8);
      final Map<String, dynamic> json = jsonDecode(content);

      final eventsList = json['events'] as List?;
      if (eventsList == null) {
        throw const FormatException('Neplatný formát zálohy: chybí seznam "events".');
      }

      final count = await repo.importEventsJson(eventsList);

      AppLogger.I.info(_module, 'backup_imported', metrics: {
        'imported_count': count,
        'total_found': eventsList.length,
        'duration_ms': sw.elapsedMilliseconds,
      });

      return BackupImportResult(
        importedCount: count,
        skippedCount: eventsList.length - count,
        message: 'Úspěšně importováno $count událostí ze zálohy.',
        success: true,
      );
    } catch (e, st) {
      AppLogger.I.error(_module, 'backup_import_failed', error: e, stackTrace: st);
      return BackupImportResult(
        importedCount: 0,
        skippedCount: 0,
        message: 'Chyba při obnově: $e',
        success: false,
      );
    }
  }
}
