import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import 'event_day.dart';
import 'moment_item.dart';

/// Kategorie rodinné události.
enum EventCategory {
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

/// Událost v rodinné kronice – výlet, divadlo, besídka, relax nebo dovolená.
class EventItem {
  const EventItem({
    required this.id,
    required this.title,
    required this.category,
    required this.startDate,
    this.endDate,
    this.location = '',
    this.latitude,
    this.longitude,
    this.description = '',
    this.weather,
    this.aiStory,
    this.participants = const [],
    this.moments = const [],
    this.days = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final EventCategory category;
  final DateTime startDate;

  /// Konec u vícedenních akcí (včetně). `null` = jednodenní akce.
  final DateTime? endDate;

  final String location;
  final double? latitude;
  final double? longitude;
  final String description;

  /// Textový popis počasí, např. „☀️ 24 °C, slunečno“.
  final String? weather;

  /// AI vygenerovaný rodinný příběh celé akce.
  final String? aiStory;

  final List<String> participants;

  /// Momentky patřící k celé akci (u vícedenních akcí ty, které nejsou přiřazeny ke dni).
  final List<MomentItem> moments;

  /// Jednotlivé dny vícedenní akce.
  final List<EventDay> days;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isMultiDay => endDate != null && !Fmt.isSameDay(startDate, endDate!);

  /// Zda se má akce spravovat po dnech.
  bool get hasDays => days.isNotEmpty;

  int get durationDays => endDate == null ? 1 : Fmt.daysInclusive(startDate, endDate!);

  bool get hasStory => aiStory != null && aiStory!.trim().isNotEmpty;

  bool get hasLocation => latitude != null && longitude != null;

  bool get isInPast => (endDate ?? startDate).isBefore(Fmt.dateOnly(DateTime.now()));

  /// Všechny momentky (akce + všechny dny) seřazené podle času.
  List<MomentItem> get allMoments {
    final list = <MomentItem>[...moments, for (final d in days) ...d.moments];
    list.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    return list;
  }

  int get momentCount => moments.length + days.fold<int>(0, (sum, d) => sum + d.moments.length);

  /// Úvodní fotka pro kartu v seznamu.
  MomentItem? get coverMoment {
    final all = allMoments;
    return all.isEmpty ? null : all.first;
  }

  String get dateLabel => Fmt.dateRange(startDate, endDate);

  List<EventDay> get sortedDays => [...days]..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));

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
    String? location,
    double? latitude,
    double? longitude,
    bool clearCoordinates = false,
    String? description,
    String? weather,
    String? aiStory,
    List<String>? participants,
    List<MomentItem>? moments,
    List<EventDay>? days,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EventItem(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      location: location ?? this.location,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      description: description ?? this.description,
      weather: weather ?? this.weather,
      aiStory: aiStory ?? this.aiStory,
      participants: participants ?? this.participants,
      moments: moments ?? this.moments,
      days: days ?? this.days,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Vrátí kopii s upraveným dnem (podle id).
  EventItem replaceDay(EventDay day) {
    return copyWith(days: [for (final d in days) d.id == day.id ? day : d]);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category.name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'description': description,
        'weather': weather,
        'aiStory': aiStory,
        'participants': participants,
        'moments': moments.map((m) => m.toJson()).toList(),
        'days': days.map((d) => d.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory EventItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return EventItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      category: EventCategory.fromName(json['category'] as String?),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '') ?? now,
      endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
      location: json['location'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      description: json['description'] as String? ?? '',
      weather: json['weather'] as String?,
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
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }
}

