import 'moment_item.dart';

/// Jeden den vícedenní akce (typicky dovolené) – „Den 1“, „Den 2“ …
class EventDay {
  const EventDay({
    required this.id,
    required this.dayNumber,
    required this.date,
    this.title = '',
    this.note = '',
    this.weather,
    this.coverPhotoPath,
    this.aiStory,
    this.moments = const [],
  });

  final String id;

  /// Pořadí dne v rámci akce (od 1).
  final int dayNumber;

  final DateTime date;

  /// Volitelný název dne, např. „Výstup na Sněžku“.
  final String title;

  final String note;

  final String? weather;

  /// Cesta nebo URL k vybrané úvodní fotce dne.
  final String? coverPhotoPath;

  /// AI vygenerovaný příběh dne.
  final String? aiStory;

  final List<MomentItem> moments;

  /// Zobrazovaný název – „Den 2 · Výstup na Sněžku“.
  String get displayTitle => title.isEmpty ? 'Den $dayNumber' : 'Den $dayNumber · $title';

  bool get hasStory => aiStory != null && aiStory!.trim().isNotEmpty;

  /// Vybraná úvodní fotka dne, případně první fotka v pořadí.
  MomentItem? get effectiveCoverMoment {
    if (coverPhotoPath != null) {
      final found = moments.where((m) => m.path == coverPhotoPath).firstOrNull;
      if (found != null) return found;
    }
    return moments.isEmpty ? null : moments.first;
  }

  /// Cesta k efektivní úvodní fotce dne.
  String? get effectiveCoverPhoto => effectiveCoverMoment?.path ?? coverPhotoPath;

  EventDay copyWith({
    String? id,
    int? dayNumber,
    DateTime? date,
    String? title,
    String? note,
    String? weather,
    String? coverPhotoPath,
    bool clearCoverPhoto = false,
    String? aiStory,
    List<MomentItem>? moments,
  }) {
    return EventDay(
      id: id ?? this.id,
      dayNumber: dayNumber ?? this.dayNumber,
      date: date ?? this.date,
      title: title ?? this.title,
      note: note ?? this.note,
      weather: weather ?? this.weather,
      coverPhotoPath: clearCoverPhoto ? null : (coverPhotoPath ?? this.coverPhotoPath),
      aiStory: aiStory ?? this.aiStory,
      moments: moments ?? this.moments,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'dayNumber': dayNumber,
        'date': date.toIso8601String(),
        'title': title,
        'note': note,
        'weather': weather,
        'coverPhotoPath': coverPhotoPath,
        'aiStory': aiStory,
        'moments': moments.map((m) => m.toJson()).toList(),
      };

  factory EventDay.fromJson(Map<String, dynamic> json) {
    return EventDay(
      id: json['id'] as String,
      dayNumber: (json['dayNumber'] as num?)?.toInt() ?? 1,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      title: json['title'] as String? ?? '',
      note: json['note'] as String? ?? '',
      weather: json['weather'] as String?,
      coverPhotoPath: json['coverPhotoPath'] as String?,
      aiStory: json['aiStory'] as String?,
      moments: ((json['moments'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => MomentItem.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }
}

