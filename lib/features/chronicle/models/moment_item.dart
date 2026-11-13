/// Jedna momentka (fotka) zachycená během události.
///
/// [path] může být lokální cesta k souboru (zkomprimované WebP v adresáři
/// aplikace) nebo vzdálená URL (ukázková data, budoucí Firebase Storage).
class MomentItem {
  const MomentItem({
    required this.id,
    required this.takenAt,
    required this.path,
    this.note = '',
    this.latitude,
    this.longitude,
    this.sizeKb,
    this.originalSizeKb,
    this.width,
    this.height,
  });

  final String id;

  /// Datum a čas pořízení (z EXIF, jinak čas importu).
  final DateTime takenAt;

  /// Lokální cesta nebo URL fotografie.
  final String path;

  /// Popisek / poznámka k fotce.
  final String note;

  /// Alias pro popisek fotky.
  String get caption => note;

  /// GPS souřadnice pořízení (z EXIF nebo z aktuální polohy).
  final double? latitude;
  final double? longitude;

  /// Velikost uloženého (zkomprimovaného) souboru v kB.
  final int? sizeKb;

  /// Velikost původního souboru v kB (pro statistiku úspory).
  final int? originalSizeKb;

  final int? width;
  final int? height;

  bool get isRemote => path.startsWith('http://') || path.startsWith('https://');

  bool get hasLocation => latitude != null && longitude != null;

  String get locationLabel =>
      hasLocation ? '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}' : '';

  /// Název souboru (pro export na web).
  String get fileName {
    final cleaned = path.split('?').first;
    final parts = cleaned.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? '$id.webp' : parts.last;
  }

  MomentItem copyWith({
    String? id,
    DateTime? takenAt,
    String? path,
    String? note,
    double? latitude,
    double? longitude,
    int? sizeKb,
    int? originalSizeKb,
    int? width,
    int? height,
  }) {
    return MomentItem(
      id: id ?? this.id,
      takenAt: takenAt ?? this.takenAt,
      path: path ?? this.path,
      note: note ?? this.note,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      sizeKb: sizeKb ?? this.sizeKb,
      originalSizeKb: originalSizeKb ?? this.originalSizeKb,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'takenAt': takenAt.toIso8601String(),
        'path': path,
        'note': note,
        'latitude': latitude,
        'longitude': longitude,
        'sizeKb': sizeKb,
        'originalSizeKb': originalSizeKb,
        'width': width,
        'height': height,
      };

  factory MomentItem.fromJson(Map<String, dynamic> json) {
    return MomentItem(
      id: json['id'] as String,
      takenAt: DateTime.tryParse(json['takenAt'] as String? ?? '') ?? DateTime.now(),
      path: json['path'] as String? ?? '',
      note: json['note'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      sizeKb: (json['sizeKb'] as num?)?.toInt(),
      originalSizeKb: (json['originalSizeKb'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
    );
  }
}

