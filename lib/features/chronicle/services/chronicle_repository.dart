import '../models/event_day.dart';
import '../models/event_item.dart';
import '../models/moment_item.dart';

/// Rozhraní úložiště rodinné kroniky (Repository pattern).
///
/// Výchozí implementací je [MockChronicleRepository] (in-memory + JSON
/// v SharedPreferences). Pro přechod na Firebase stačí vytvořit
/// `FirestoreChronicleRepository implements ChronicleRepository`
/// a zaregistrovat ji v `ServiceLocator` podle `AppConfig.storageBackend`.
/// Prezentační vrstva pracuje výhradně s tímto rozhraním.
abstract interface class ChronicleRepository {
  /// Identifikátor implementace pro logy (`local`, `firestore` …).
  String get backendName;

  /// Inicializace úložiště (načtení dat, připojení k backendu).
  Future<void> init();

  /// Živý stream všech událostí seřazených od nejnovější.
  Stream<List<EventItem>> watchEvents();

  /// Aktuální snímek všech událostí seřazených od nejnovější.
  Future<List<EventItem>> getEvents();

  Future<EventItem?> getEvent(String id);

  /// Vloží novou nebo aktualizuje existující událost (upsert podle `id`).
  Future<EventItem> saveEvent(EventItem event);

  Future<void> deleteEvent(String id);

  /// Přidá momentky k události, případně ke konkrétnímu dni ([dayId]).
  Future<EventItem> addMoments(String eventId, List<MomentItem> moments, {String? dayId});

  /// Upraví existující momentku (poznámka, poloha …) kdekoli v události.
  Future<EventItem> updateMoment(String eventId, MomentItem moment);

  Future<EventItem> removeMoment(String eventId, String momentId);

  /// Vloží nebo aktualizuje den vícedenní akce.
  Future<EventItem> saveDay(String eventId, EventDay day);

  Future<EventItem> removeDay(String eventId, String dayId);

  /// Uvolnění prostředků.
  Future<void> dispose();
}

/// Výjimka úložiště.
class ChronicleRepositoryException implements Exception {
  ChronicleRepositoryException(this.message);

  final String message;

  @override
  String toString() => 'ChronicleRepositoryException: $message';
}

