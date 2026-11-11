import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';
import '../../../core/utils/id_generator.dart';
import '../../chronicle/models/moment_item.dart';

/// Metadata vytažená z EXIF hlavičky fotografie.
class PhotoMetadata {
  const PhotoMetadata({this.takenAt, this.latitude, this.longitude, this.cameraModel, this.tagCount = 0});

  final DateTime? takenAt;
  final double? latitude;
  final double? longitude;
  final String? cameraModel;
  final int tagCount;

  bool get hasLocation => latitude != null && longitude != null;

  static const PhotoMetadata empty = PhotoMetadata();
}

/// Výsledek komprese jedné fotky.
class CompressionResult {
  const CompressionResult({
    required this.path,
    required this.originalKb,
    required this.compressedKb,
    required this.width,
    required this.height,
    required this.durationMs,
  });

  final String path;
  final int originalKb;
  final int compressedKb;
  final int width;
  final int height;
  final int durationMs;

  int get savedKb => originalKb - compressedKb;

  double get savedPercent => originalKb == 0 ? 0 : (savedKb / originalKb) * 100;
}

/// Souhrn hromadného importu.
class MediaImportResult {
  const MediaImportResult({required this.moments, required this.failed, required this.durationMs});

  final List<MomentItem> moments;
  final int failed;
  final int durationMs;

  int get originalKb => moments.fold<int>(0, (s, m) => s + (m.originalSizeKb ?? 0));
  int get compressedKb => moments.fold<int>(0, (s, m) => s + (m.sizeKb ?? 0));
  int get savedKb => originalKb - compressedKb;
}

/// Služba pro práci s fotkami:
/// výběr z galerie / fotoaparátu → EXIF (datum, GPS) → komprese do WebP → [MomentItem].
class MediaService {
  MediaService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Maximální délka delší strany výsledné fotky.
  static const int maxLongSide = 1600;

  /// Kvalita WebP komprese (0–100).
  static const int webpQuality = 80;

  static const String _module = LogModule.media;

  // ---------------------------------------------------------------------------
  // Výběr fotek
  // ---------------------------------------------------------------------------

  /// Hromadný výběr fotek z galerie a jejich kompletní zpracování.
  Future<MediaImportResult> pickAndProcessPhotos({void Function(int done, int total)? onProgress}) async {
    final sw = Stopwatch()..start();
    List<XFile> files;
    try {
      files = await _picker.pickMultiImage();
    } catch (e, st) {
      AppLogger.I.error(_module, 'pick_multi_failed', error: e, stackTrace: st);
      rethrow;
    }
    AppLogger.I.info(_module, 'pick_multi', metrics: {
      'selected': files.length,
      'duration_ms': sw.elapsedMilliseconds,
    });
    if (files.isEmpty) {
      return MediaImportResult(moments: const [], failed: 0, durationMs: sw.elapsedMilliseconds);
    }
    return _processAll(files, sw, onProgress: onProgress);
  }

  /// Pořízení jedné fotky fotoaparátem. Poloha se doplní z GPS zařízení,
  /// pokud ji fotka v EXIF nemá.
  Future<MediaImportResult> capturePhoto() async {
    final sw = Stopwatch()..start();
    XFile? file;
    try {
      file = await _picker.pickImage(source: ImageSource.camera);
    } catch (e, st) {
      AppLogger.I.error(_module, 'camera_failed', error: e, stackTrace: st);
      rethrow;
    }
    AppLogger.I.info(_module, 'camera_capture', metrics: {
      'captured': file != null,
      'duration_ms': sw.elapsedMilliseconds,
    });
    if (file == null) {
      return MediaImportResult(moments: const [], failed: 0, durationMs: sw.elapsedMilliseconds);
    }
    final result = await _processAll([file], sw);
    if (result.moments.isNotEmpty && !result.moments.first.hasLocation) {
      final pos = await currentPosition();
      if (pos != null) {
        final withGps = result.moments.first.copyWith(latitude: pos.latitude, longitude: pos.longitude);
        return MediaImportResult(moments: [withGps], failed: result.failed, durationMs: result.durationMs);
      }
    }
    return result;
  }

  Future<MediaImportResult> _processAll(
    List<XFile> files,
    Stopwatch sw, {
    void Function(int done, int total)? onProgress,
  }) async {
    final moments = <MomentItem>[];
    var failed = 0;
    for (var i = 0; i < files.length; i++) {
      try {
        final moment = await processFile(files[i]);
        moments.add(moment);
      } catch (e, st) {
        failed++;
        AppLogger.I.error(_module, 'process_file_failed',
            error: e, stackTrace: st, metrics: {'file': files[i].name, 'index': i});
      }
      onProgress?.call(i + 1, files.length);
    }
    final result = MediaImportResult(moments: moments, failed: failed, durationMs: sw.elapsedMilliseconds);
    AppLogger.I.log(
      module: _module,
      level: failed == 0 ? LogLevel.info : LogLevel.warn,
      action: 'batch_import_done',
      metrics: {
        'processed': moments.length,
        'failed': failed,
        'original_kb': result.originalKb,
        'compressed_kb': result.compressedKb,
        'saved_kb': result.savedKb,
        'duration_ms': result.durationMs,
      },
    );
    return result;
  }

  /// Kompletní zpracování jednoho souboru – EXIF + komprese → [MomentItem].
  Future<MomentItem> processFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final meta = await readExif(bytes, fileName: file.name);
    final compressed = await compressToWebp(file.path, bytes: bytes);

    DateTime takenAt = meta.takenAt ?? DateTime.now();
    if (meta.takenAt == null) {
      try {
        takenAt = await file.lastModified();
      } catch (_) {
        // Některé zdroje (content://) neumí lastModified – ponecháme aktuální čas.
      }
    }

    return MomentItem(
      id: IdGen.next('m_'),
      takenAt: takenAt,
      path: compressed.path,
      latitude: meta.latitude,
      longitude: meta.longitude,
      sizeKb: compressed.compressedKb,
      originalSizeKb: compressed.originalKb,
      width: compressed.width,
      height: compressed.height,
    );
  }

  // ---------------------------------------------------------------------------
  // EXIF
  // ---------------------------------------------------------------------------

  /// Přečte z EXIF datum a čas pořízení a GPS souřadnice.
  Future<PhotoMetadata> readExif(Uint8List bytes, {String fileName = ''}) async {
    final sw = Stopwatch()..start();
    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) {
        AppLogger.I.warn(_module, 'exif_missing', metrics: {
          'file': fileName,
          'duration_ms': sw.elapsedMilliseconds,
        });
        return PhotoMetadata.empty;
      }

      final takenAt = parseExifDate(
        tags['EXIF DateTimeOriginal']?.printable ??
            tags['EXIF DateTimeDigitized']?.printable ??
            tags['Image DateTime']?.printable,
      );
      final lat = parseGpsCoordinate(tags['GPS GPSLatitude']?.printable, tags['GPS GPSLatitudeRef']?.printable);
      final lng = parseGpsCoordinate(tags['GPS GPSLongitude']?.printable, tags['GPS GPSLongitudeRef']?.printable);
      final model = tags['Image Model']?.printable.trim();

      final meta = PhotoMetadata(
        takenAt: takenAt,
        latitude: lat,
        longitude: lng,
        cameraModel: (model == null || model.isEmpty) ? null : model,
        tagCount: tags.length,
      );
      AppLogger.I.info(_module, 'exif_parsed', metrics: {
        'file': fileName,
        'tags': tags.length,
        'has_date': takenAt != null,
        'has_gps': meta.hasLocation,
        if (meta.hasLocation) 'gps': '${lat!.toStringAsFixed(5)},${lng!.toStringAsFixed(5)}',
        if (meta.cameraModel != null) 'camera': meta.cameraModel,
        'duration_ms': sw.elapsedMilliseconds,
      });
      return meta;
    } catch (e, st) {
      AppLogger.I.error(_module, 'exif_failed',
          error: e, stackTrace: st, metrics: {'file': fileName, 'duration_ms': sw.elapsedMilliseconds});
      return PhotoMetadata.empty;
    }
  }

  /// Parsuje EXIF datum ve formátu `2024:05:12 14:33:10`.
  static DateTime? parseExifDate(String? value) {
    if (value == null) return null;
    final match = RegExp(r'(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(value.trim());
    if (match == null) return null;
    final parts = List.generate(6, (i) => int.parse(match.group(i + 1)!));
    if (parts[0] < 1900 || parts[1] == 0 || parts[2] == 0) return null;
    return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }

  /// Převede EXIF GPS hodnotu (např. `[49, 35, 2817/100]`) a referenci (`N`/`S`/`E`/`W`)
  /// na desetinné stupně.
  static double? parseGpsCoordinate(String? value, String? ref) {
    if (value == null) return null;
    final cleaned = value.replaceAll('[', '').replaceAll(']', '').trim();
    if (cleaned.isEmpty) return null;
    final parts = cleaned.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    double? parsePart(String p) {
      if (p.contains('/')) {
        final nd = p.split('/');
        final n = double.tryParse(nd[0].trim());
        final d = double.tryParse(nd[1].trim());
        if (n == null || d == null || d == 0) return null;
        return n / d;
      }
      return double.tryParse(p);
    }

    final values = parts.map(parsePart).toList();
    if (values.any((v) => v == null)) return null;
    final deg = values[0]!;
    final min = values.length > 1 ? values[1]! : 0.0;
    final sec = values.length > 2 ? values[2]! : 0.0;
    var result = deg + min / 60 + sec / 3600;
    final r = (ref ?? '').trim().toUpperCase();
    if (r == 'S' || r == 'W') result = -result;
    if (result == 0) return null; // 0,0 = neplatná / vymazaná poloha
    return result;
  }

  // ---------------------------------------------------------------------------
  // Komprese
  // ---------------------------------------------------------------------------

  /// Zmenší fotku (max [maxLongSide] px na delší straně) a uloží ji jako WebP
  /// s kvalitou [webpQuality] do adresáře aplikace.
  Future<CompressionResult> compressToWebp(String sourcePath, {Uint8List? bytes}) async {
    final sw = Stopwatch()..start();
    final data = bytes ?? await File(sourcePath).readAsBytes();
    final originalKb = (data.lengthInBytes / 1024).round();

    final size = await _decodeSize(data);
    final srcW = size?.$1 ?? maxLongSide;
    final srcH = size?.$2 ?? maxLongSide;
    final longSide = srcW > srcH ? srcW : srcH;
    final scale = longSide > maxLongSide ? maxLongSide / longSide : 1.0;
    // flutter_image_compress zachovává poměr stran a zmenší obrázek tak, aby
    // nebyl menší než minWidth × minHeight – proto předáváme přesně cílové rozměry.
    final targetW = (srcW * scale).round();
    final targetH = (srcH * scale).round();

    final dir = await _photosDirectory();
    final targetPath = '${dir.path}${Platform.pathSeparator}${IdGen.next('p_')}.webp';

    final result = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      targetPath,
      minWidth: targetW,
      minHeight: targetH,
      quality: webpQuality,
      format: CompressFormat.webp,
      keepExif: false,
    );

    if (result == null) {
      AppLogger.I.error(_module, 'compress_failed', metrics: {
        'source': sourcePath.split(Platform.pathSeparator).last,
        'original_kb': originalKb,
        'duration_ms': sw.elapsedMilliseconds,
      }, error: 'FlutterImageCompress vrátil null');
      throw StateError('Kompresi fotky se nepodařilo dokončit.');
    }

    final compressedKb = ((await File(result.path).length()) / 1024).round();
    final out = CompressionResult(
      path: result.path,
      originalKb: originalKb,
      compressedKb: compressedKb,
      width: targetW,
      height: targetH,
      durationMs: sw.elapsedMilliseconds,
    );
    AppLogger.I.info(_module, 'compress_webp', metrics: {
      'source_px': '${srcW}x$srcH',
      'target_px': '${targetW}x$targetH',
      'quality': webpQuality,
      'original_kb': originalKb,
      'compressed_kb': compressedKb,
      'saved_kb': out.savedKb,
      'saved_pct': out.savedPercent.toStringAsFixed(1),
      'duration_ms': out.durationMs,
    });
    return out;
  }

  /// Zjistí rozměry obrázku z hlavičky bez plného dekódování.
  Future<(int, int)?> _decodeSize(Uint8List data) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (descriptor.width, descriptor.height);
      descriptor.dispose();
      buffer.dispose();
      return size;
    } catch (e) {
      AppLogger.I.warn(_module, 'decode_size_failed', error: e);
      return null;
    }
  }

  Future<Directory> _photosDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}flylog_photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Smaže lokální soubor fotky (vzdálené URL ignoruje).
  Future<void> deleteLocalFile(MomentItem moment) async {
    if (moment.isRemote) return;
    try {
      final f = File(moment.path);
      if (await f.exists()) {
        await f.delete();
        AppLogger.I.info(_module, 'file_deleted', metrics: {'moment_id': moment.id, 'size_kb': moment.sizeKb});
      }
    } catch (e) {
      AppLogger.I.warn(_module, 'file_delete_failed', error: e, metrics: {'moment_id': moment.id});
    }
  }

  // ---------------------------------------------------------------------------
  // Poloha
  // ---------------------------------------------------------------------------

  /// Aktuální poloha zařízení (nebo `null`, pokud není dostupná / povolená).
  Future<Position?> currentPosition() async {
    final sw = Stopwatch()..start();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        AppLogger.I.warn(_module, 'location_service_disabled');
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        AppLogger.I.warn(_module, 'location_permission_denied', metrics: {'permission': permission.name});
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      AppLogger.I.info(_module, 'location_fix', metrics: {
        'accuracy_m': pos.accuracy.toStringAsFixed(0),
        'duration_ms': sw.elapsedMilliseconds,
      });
      return pos;
    } catch (e, st) {
      AppLogger.I.error(_module, 'location_failed',
          error: e, stackTrace: st, metrics: {'duration_ms': sw.elapsedMilliseconds});
      return null;
    }
  }
}
