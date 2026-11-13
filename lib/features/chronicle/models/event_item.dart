import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import 'event_day.dart';
import 'moment_item.dart';
import 'quick_note.dart';

/// Stav záznamu v kronice.
enum EventStatus {
  draft('Rozpracováno', Icons.edit_note, Colors.orange),
  published('Publikováno', Icons.check_circle_outline, Colors.green);

  const EventStatus(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  static EventStatus fromName(String? name) {
    return EventStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => EventStatus.published, // starší záznamy jsou published
    );
  }
}

/// Kategorie rodinné události.
enum EventCategory {
  diary('Deník / Běžný den', '📖', Icons.menu_book, 0xFF546E7A),
  trip('Výlet & Příroda', '🥾', Icons.hiking, 0xFF2E7D32),
  culture('Divadlo & Koncert', '🎭', Icons.theater_comedy, 0xFF6A1B9A),
  school('Besídka & Kroužky', '🎒', Icons.school, 0xFFEF6C00),
  fun('Aquapark & Relax', '🏊', Icons.pool, 0xFF0277BD),
  vacation('Dovolená', '🏖️', Icons.beach_access, 0xFFC62828);

  const EventCategory(this.label, this.emoji, this.icon, this.colorValue);

  final String label;
  final String emoji;
  final IconData icon;
  final int colorValue;

  Color get color => Color(colorValue);

  /// Hex barva pro HTML export (`#2E7D32`).
  String get colorHex => '#${(colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Zda kategorie standardně podporuje správu po dnech.
  bool get supportsDays => this == EventCategory.vacation;

  static EventCategory fromName(String? name) {
    return EventCategory.values.firstWhere((c) => c.name == name, orElse: () => EventCategory.trip);
  }
}

/// Událost v rodinné kronice – deník, výlet, divadlo, besídka, relax nebo dovolená.
class EventItem {
  const EventItem({
    required this.id,
    required this.title,
    required this.category,
    required this.startDate,
    this.endDate,
    this.status = EventStatus.draft,
    this.location = '',
    this.latitude,
    this.longitude,
    this.description = '',
    this.weather,
    this.weatherTempC,
    this.weatherWindMs,
    this.weatherDescription,
    this.distanceKm,
    this.durationMinutes,
    this.extraNotes = '',
    this.coverPhotoPath,
    this.locationGuideText,
    this.aiStory,
    this.participants = const [],
    this.moments = const [],
    this.days = const [],
    this.quickNotes = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final EventCategory category;
  final DateTime startDate;
  final DateTime? endDate;
  final EventStatus status;

  final String location;
  final double? latitude;
  final double? longitude;
  final String description;

  /// Souhrnný popis počasí (např. „☀️ 24 °C, slunečno“)
  final String? weather;

  /// Parametrické počasí (Open-Meteo & ruční úprava)
  final double? weatherTempC;
  final double? weatherWindMs;
  final String? weatherDescription;

  /// Trasa a trvání
  final double? distanceKm;
  final int? durationMinutes;

  /// Doplňující podrobnosti a tipy
  final String extraNotes;

  /// Cesta nebo URL k vybrané úvodní / titulní fotce události.
  final String? coverPhotoPath;

  /// Fáze A AI: Průvodce lokalitou a zajímavosti
  final String? locationGuideText;

  /// Fáze B AI: Vygenerovaný (a uživatelem editovatelný) příběh
  final String? aiStory;

  final List<String> participants;
  final List<MomentItem> moments;
  final List<EventDay> days;

  /// Průběžné časové poznámky v draftu
  final List<QuickNote> quickNotes;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDraft => status == EventStatus.draft;
  bool get isPublished => status == EventStatus.published;
  bool get isMultiDay => endDate != null && !Fmt.isSameDay(startDate, endDate!);
  bool get hasDays => days.isNotEmpty;
  int get durationDays => endDate == null ? 1 : Fmt.daysInclusive(startDate, endDate!);
  bool get hasStory => aiStory != null && aiStory!.trim().isNotEmpty;
  bool get hasLocationGuide => locationGuideText != null && locationGuideText!.trim().isNotEmpty;
  bool get hasLocation => latitude != null && longitude != null;
  bool get isInPast => (endDate ?? startDate).isBefore(Fmt.dateOnly(DateTime.now()));

  List<MomentItem> get allMoments {
    final list = <MomentItem>[...moments, for (final d in days) ...d.moments];
    list.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    return list;
  }

  int get momentCount => moments.length + days.fold<int>(0, (sum, d) => sum + d.moments.length);

  /// Efektivní vybraná úvodní momentka (podle [coverPhotoPath]), případně první v pořadí.
  MomentItem? get effectiveCoverMoment {
    final all = allMoments;
    if (coverPhotoPath != null) {
      final found = all.where((m) => m.path == coverPhotoPath).firstOrNull;
      if (found != null) return found;
    }
    return all.isEmpty ? null : all.first;
  }

  /// Cesta k efektivní úvodní fotce události.
  String? get effectiveCoverPhoto => effectiveCoverMoment?.path ?? coverPhotoPath;

  /// Zpětně kompatibilní zástupce pro úvodní momentku.
  MomentItem? get coverMoment => effectiveCoverMoment;

  String get dateLabel => Fmt.dateRange(startDate, endDate);

  List<EventDay> get sortedDays => [...days]..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));

  List<QuickNote> get sortedQuickNotes => [...quickNotes]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  EventDay? dayById(String id) {
    for (final d in days) {
      if (d.id == id) return d;
    }
    return null;
  }

  EventItem copyWith({
    String? id,
    String? title,
    EventCategory? category,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    EventStatus? status,
    String? location,
    double? latitude,
    double? longitude,
    bool clearCoordinates = false,
    String? description,
    String? weather,
    double? weatherTempC,
    double? weatherWindMs,
    String? weatherDescription,
    double? distanceKm,
    int? durationMinutes,
    String? extraNotes,
    String? coverPhotoPath,
    bool clearCoverPhoto = false,
    String? locationGuideText,
    String? aiStory,
    List<String>? participants,
    List<MomentItem>? moments,
    List<EventDay>? days,
    List<QuickNote>? quickNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EventItem(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      status: status ?? this.status,
      location: location ?? this.location,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      description: description ?? this.description,
      weather: weather ?? this.weather,
      weatherTempC: weatherTempC ?? this.weatherTempC,
      weatherWindMs: weatherWindMs ?? this.weatherWindMs,
      weatherDescription: weatherDescription ?? this.weatherDescription,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      extraNotes: extraNotes ?? this.extraNotes,
      coverPhotoPath: clearCoverPhoto ? null : (coverPhotoPath ?? this.coverPhotoPath),
      locationGuideText: locationGuideText ?? this.locationGuideText,
      aiStory: aiStory ?? this.aiStory,
      participants: participants ?? this.participants,
      moments: moments ?? this.moments,
      days: days ?? this.days,
      quickNotes: quickNotes ?? this.quickNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  EventItem replaceDay(EventDay day) {
    return copyWith(days: [for (final d in days) d.id == day.id ? day : d]);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category.name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'status': status.name,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'description': description,
        'weather': weather,
        'weatherTempC': weatherTempC,
        'weatherWindMs': weatherWindMs,
        'weatherDescription': weatherDescription,
        'distanceKm': distanceKm,
        'durationMinutes': durationMinutes,
        'extraNotes': extraNotes,
        'coverPhotoPath': coverPhotoPath,
        'locationGuideText': locationGuideText,
        'aiStory': aiStory,
        'participants': participants,
        'moments': moments.map((m) => m.toJson()).toList(),
        'days': days.map((d) => d.toJson()).toList(),
        'quickNotes': quickNotes.map((q) => q.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory EventItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return EventItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Bez názvu',
      category: EventCategory.fromName(json['category'] as String?),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '') ?? now,
      endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
      status: EventStatus.fromName(json['status'] as String?),
      location: json['location'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      description: json['description'] as String? ?? '',
      weather: json['weather'] as String?,
      weatherTempC: (json['weatherTempC'] as num?)?.toDouble(),
      weatherWindMs: (json['weatherWindMs'] as num?)?.toDouble(),
      weatherDescription: json['weatherDescription'] as String?,
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      extraNotes: json['extraNotes'] as String? ?? '',
      coverPhotoPath: json['coverPhotoPath'] as String?,
      locationGuideText: json['locationGuideText'] as String?,
      aiStory: json['aiStory'] as String?,
      participants: ((json['participants'] as List?) ?? const []).map((e) => e.toString()).toList(),
      moments: ((json['moments'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => MomentItem.fromJson(m.cast<String, dynamic>()))
          .toList(),
      days: ((json['days'] as List?) ?? const [])
          .whereType<Map>()
          .map((d) => EventDay.fromJson(d.cast<String, dynamic>()))
          .toList(),
      quickNotes: ((json['quickNotes'] as List?) ?? const [])
          .whereType<Map>()
          .map((q) => QuickNote.fromJson(q.cast<String, dynamic>()))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }
}
