import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';
import '../../../core/utils/formatters.dart';
import '../models/event_day.dart';
import '../models/event_item.dart';
import '../models/moment_item.dart';
import 'chronicle_repository.dart';

/// Výchozí lokální implementace [ChronicleRepository].
///
/// * data drží v paměti (rychlé čtení, živý stream),
/// * každou změnu persistuje jako JSON do [SharedPreferences],
/// * při prvním spuštění naplní kroniku ukázkovými daty.
class MockChronicleRepository implements ChronicleRepository {
  MockChronicleRepository({SharedPreferences? preferences, this.seedSampleData = true}) : _prefs = preferences;

  static const String storageKey = 'flylog.chronicle.events.v1';

  final bool seedSampleData;
  SharedPreferences? _prefs;

  final Map<String, EventItem> _events = {};
  final StreamController<List<EventItem>> _controller = StreamController<List<EventItem>>.broadcast();
  bool _initialized = false;

  @override
  String get backendName => 'local';

  @override
  Future<void> init() async {
    if (_initialized) return;
    final sw = Stopwatch()..start();
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(storageKey);
    var source = 'storage';
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list.whereType<Map>()) {
          final event = EventItem.fromJson(item.cast<String, dynamic>());
          _events[event.id] = event;
        }
      } catch (e, st) {
        AppLogger.I.error(LogModule.chronicle, 'storage_parse_failed',
            error: e, stackTrace: st, metrics: {'raw_length': raw.length});
        _events.clear();
      }
    }
    if (_events.isEmpty && seedSampleData && raw == null) {
      for (final e in buildSampleEvents()) {
        _events[e.id] = e;
      }
      source = 'sample_data';
      await _persist();
    }
    _initialized = true;
    AppLogger.I.info(LogModule.chronicle, 'repository_init', metrics: {
      'backend': backendName,
      'source': source,
      'events': _events.length,
      'moments': _events.values.fold<int>(0, (s, e) => s + e.momentCount),
      'duration_ms': sw.elapsedMilliseconds,
    });
    _emit();
  }

  @override
  Stream<List<EventItem>> watchEvents() async* {
    yield _sorted();
    yield* _controller.stream;
  }

  @override
  Future<List<EventItem>> getEvents() async => _sorted();

  @override
  Future<EventItem?> getEvent(String id) async => _events[id];

  @override
  Future<EventItem> saveEvent(EventItem event) async {
    final isNew = !_events.containsKey(event.id);
    final saved = event.copyWith(updatedAt: DateTime.now());
    _events[saved.id] = saved;
    await _commit(isNew ? 'event_created' : 'event_updated', {
      'event_id': saved.id,
      'category': saved.category.name,
      'days': saved.days.length,
      'retro': saved.isInPast,
    });
    return saved;
  }

  @override
  Future<void> deleteEvent(String id) async {
    final removed = _events.remove(id);
    if (removed == null) {
      AppLogger.I.warn(LogModule.chronicle, 'event_delete_missing', metrics: {'event_id': id});
      return;
    }
    await _commit('event_deleted', {'event_id': id, 'moments': removed.momentCount});
  }

  @override
  Future<EventItem> addMoments(String eventId, List<MomentItem> moments, {String? dayId}) async {
    final event = _require(eventId);
    EventItem updated;
    if (dayId != null) {
      final day = event.dayById(dayId);
      if (day == null) throw ChronicleRepositoryException('Den $dayId neexistuje');
      final merged = [...day.moments, ...moments]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      updated = event.replaceDay(day.copyWith(moments: merged));
    } else {
      final merged = [...event.moments, ...moments]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      updated = event.copyWith(moments: merged);
    }
    return _store(updated, 'moments_added', {
      'event_id': eventId,
      'day_id': dayId,
      'count': moments.length,
      'total_kb': moments.fold<int>(0, (s, m) => s + (m.sizeKb ?? 0)),
    });
  }

  @override
  Future<EventItem> updateMoment(String eventId, MomentItem moment) async {
    final event = _require(eventId);
    List<MomentItem> replace(List<MomentItem> list) => [for (final m in list) m.id == moment.id ? moment : m];
    final updated = event.copyWith(
      moments: replace(event.moments),
      days: [for (final d in event.days) d.copyWith(moments: replace(d.moments))],
    );
    return _store(updated, 'moment_updated', {'event_id': eventId, 'moment_id': moment.id});
  }

  @override
  Future<EventItem> removeMoment(String eventId, String momentId) async {
    final event = _require(eventId);
    final targetMoment = event.allMoments.where((m) => m.id == momentId).firstOrNull;

    // Smazání lokálního souboru z mezipaměti / úložiště
    if (targetMoment != null && !targetMoment.isRemote) {
      try {
        final f = File(targetMoment.path);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (e, st) {
        AppLogger.I.warn(_module, 'moment_file_delete_failed', error: e, metrics: {'path': targetMoment.path});
      }
    }

    final isEventCover = targetMoment != null && event.coverPhotoPath == targetMoment.path;
    List<MomentItem> without(List<MomentItem> list) => list.where((m) => m.id != momentId).toList();

    final updated = event.copyWith(
      clearCoverPhoto: isEventCover,
      coverPhotoPath: isEventCover ? null : event.coverPhotoPath,
      moments: without(event.moments),
      days: [
        for (final d in event.days)
          d.copyWith(
            clearCoverPhoto: targetMoment != null && d.coverPhotoPath == targetMoment.path,
            coverPhotoPath: (targetMoment != null && d.coverPhotoPath == targetMoment.path) ? null : d.coverPhotoPath,
            moments: without(d.moments),
          )
      ],
    );
    return _store(updated, 'moment_removed', {'event_id': eventId, 'moment_id': momentId});
  }

  @override
  Future<EventItem> saveDay(String eventId, EventDay day) async {
    final event = _require(eventId);
    final exists = event.days.any((d) => d.id == day.id);
    final days = exists ? [for (final d in event.days) d.id == day.id ? day : d] : [...event.days, day];
    days.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
    return _store(event.copyWith(days: days), exists ? 'day_updated' : 'day_added', {
      'event_id': eventId,
      'day_number': day.dayNumber,
    });
  }

  @override
  Future<EventItem> removeDay(String eventId, String dayId) async {
    final event = _require(eventId);
    final remaining = event.days.where((d) => d.id != dayId).toList()
      ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
    final renumbered = [
      for (var i = 0; i < remaining.length; i++) remaining[i].copyWith(dayNumber: i + 1),
    ];
    return _store(event.copyWith(days: renumbered), 'day_removed', {'event_id': eventId, 'day_id': dayId});
  }

  @override
  Future<int> importEventsJson(List<dynamic> jsonList) async {
    int imported = 0;
    for (final item in jsonList) {
      if (item is Map) {
        try {
          final event = EventItem.fromJson(item.cast<String, dynamic>());
          _events[event.id] = event;
          imported++;
        } catch (e, st) {
          AppLogger.I.error(LogModule.chronicle, 'import_single_event_failed', error: e, stackTrace: st);
        }
      }
    }
    if (imported > 0) {
      await _commit('events_imported', {'count': imported});
    }
    return imported;
  }

  /// Smaže uložená data a znovu nahraje ukázkovou kroniku.
  Future<void> resetToSampleData() async {
    _events
      ..clear()
      ..addEntries(buildSampleEvents().map((e) => MapEntry(e.id, e)));
    await _commit('reset_to_sample', {'events': _events.length});
  }

  /// Smaže všechna data (prázdná kronika).
  Future<void> clearAll() async {
    _events.clear();
    await _commit('clear_all', {});
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  // ---------------------------------------------------------------------------

  EventItem _require(String id) {
    final e = _events[id];
    if (e == null) throw ChronicleRepositoryException('Událost $id neexistuje');
    return e;
  }

  Future<EventItem> _store(EventItem event, String action, Map<String, Object?> metrics) async {
    final saved = event.copyWith(updatedAt: DateTime.now());
    _events[saved.id] = saved;
    await _commit(action, metrics);
    return saved;
  }

  Future<void> _commit(String action, Map<String, Object?> metrics) async {
    final sw = Stopwatch()..start();
    final bytes = await _persist();
    AppLogger.I.info(LogModule.chronicle, action, metrics: {
      ...metrics,
      'storage_kb': (bytes / 1024).toStringAsFixed(1),
      'persist_ms': sw.elapsedMilliseconds,
    });
    _emit();
  }

  Future<int> _persist() async {
    try {
      final json = jsonEncode(_events.values.map((e) => e.toJson()).toList());
      await _prefs?.setString(storageKey, json);
      return json.length;
    } catch (e, st) {
      AppLogger.I.error(LogModule.chronicle, 'persist_failed', error: e, stackTrace: st);
      return 0;
    }
  }

  List<EventItem> _sorted() => _events.values.toList()..sort((a, b) => b.startDate.compareTo(a.startDate));

  void _emit() {
    if (!_controller.isClosed) _controller.add(_sorted());
  }

  // ---------------------------------------------------------------------------
  // Ukázková data
  // ---------------------------------------------------------------------------

  /// Ukázková kronika – data jsou relativní k dnešku, aby byla vždy „nedávná“.
  static List<EventItem> buildSampleEvents() {
    final today = Fmt.dateOnly(DateTime.now());
    DateTime ago(int days, [int hour = 10, int minute = 0]) =>
        today.subtract(Duration(days: days)).add(Duration(hours: hour, minutes: minute));
    String pic(String seed) => 'https://picsum.photos/seed/$seed/1200/800';

    MomentItem m(String id, DateTime at, String seed, String note, [double? lat, double? lng]) => MomentItem(
          id: id,
          takenAt: at,
          path: pic(seed),
          note: note,
          latitude: lat,
          longitude: lng,
          sizeKb: 180,
          originalSizeKb: 3400,
          width: 1200,
          height: 800,
        );

    // 1) Výlet na Paprsek ------------------------------------------------------
    final paprsekDate = ago(18);
    final paprsek = EventItem(
      id: 'sample-paprsek',
      title: 'Výlet na Paprsek',
      category: EventCategory.trip,
      startDate: paprsekDate,
      location: 'Paprsek, Rychlebské hory',
      latitude: 50.2156,
      longitude: 17.0153,
      description: 'Pěší túra ze Starého Města přes rozhlednu až na chatu Paprsek. '
          'Na chatě borůvkové knedlíky, cestou zpátky houby.',
      weather: '⛅ 14 °C, polojasno, slabý vítr',
      participants: const ['Táta', 'Máma', 'Ema', 'Vojta'],
      aiStory: 'Sobotní ráno nás přivítalo mlhou nad Starým Městem, ale jakmile jsme vyrazili do kopce, '
          'slunce se prodralo mezi smrky. Ema vedla výpravu s mapou v ruce a Vojta sbíral šišky do kapes, '
          'dokud nebyly plné. Na chatě Paprsek jsme si zasloužili borůvkové knedlíky – a kdo dojedl první, '
          'ten si vybral cestu zpátky. Domů jsme se vraceli unavení, s košíkem hub a s pocitem, '
          'že nejlepší výlety jsou ty, na které se nikam nespěchá.',
      moments: [
        m('sample-paprsek-1', ago(18, 9, 12), 'paprsek-start', 'Start ve Starém Městě', 50.1620, 16.9476),
        m('sample-paprsek-2', ago(18, 11, 40), 'paprsek-forest', 'Lesní pěšina plná kořenů', 50.1950, 16.9900),
        m('sample-paprsek-3', ago(18, 13, 5), 'paprsek-chata', 'Borůvkové knedlíky na chatě', 50.2156, 17.0153),
        m('sample-paprsek-4', ago(18, 15, 30), 'paprsek-houby', 'Úlovek hub na zpáteční cestě', 50.2010, 17.0011),
      ],
      createdAt: ago(18, 20),
      updatedAt: ago(17, 9),
    );

    // 2) Divadlo ---------------------------------------------------------------
    final divadlo = EventItem(
      id: 'sample-divadlo',
      title: 'Divadlo: Malý princ',
      category: EventCategory.culture,
      startDate: ago(9, 17),
      location: 'Moravské divadlo Olomouc',
      latitude: 49.5938,
      longitude: 17.2509,
      description: 'Odpolední rodinné představení. Děti nejvíc zaujala liška a růže.',
      weather: '🌧️ 9 °C, přeháňky',
      participants: const ['Máma', 'Ema', 'Vojta', 'Babička'],
      moments: [
        m('sample-divadlo-1', ago(9, 16, 40), 'divadlo-foyer', 'Ve foyer před představením', 49.5938, 17.2509),
        m('sample-divadlo-2', ago(9, 18, 50), 'divadlo-opona', 'Děkovačka', 49.5938, 17.2509),
      ],
      createdAt: ago(9, 21),
      updatedAt: ago(9, 21),
    );

    // 3) Besídka ---------------------------------------------------------------
    final besidka = EventItem(
      id: 'sample-besidka',
      title: 'Vánoční besídka ve školce',
      category: EventCategory.school,
      startDate: ago(40, 15),
      location: 'MŠ Sluníčko',
      description: 'Vojta byl sněhulák a zazpíval celou básničku bez zaváhání.',
      participants: const ['Táta', 'Máma', 'Vojta'],
      moments: [
        m('sample-besidka-1', ago(40, 15, 20), 'besidka-snehulak', 'Vojta jako sněhulák'),
      ],
      createdAt: ago(40, 19),
      updatedAt: ago(40, 19),
    );

    // 4) Aquapark --------------------------------------------------------------
    final aquapark = EventItem(
      id: 'sample-aquapark',
      title: 'Aquapark a wellness',
      category: EventCategory.fun,
      startDate: ago(3, 13),
      location: 'Aquapark Olomouc',
      latitude: 49.5733,
      longitude: 17.2860,
      description: 'Tobogány pro děti, sauna pro rodiče. Ema poprvé sjela černý tobogán.',
      weather: '❄️ 3 °C venku, 30 °C uvnitř',
      participants: const ['Táta', 'Máma', 'Ema', 'Vojta'],
      moments: [
        m('sample-aquapark-1', ago(3, 13, 30), 'aquapark-tobogan', 'Černý tobogán – pokořen!', 49.5733, 17.2860),
      ],
      createdAt: ago(3, 20),
      updatedAt: ago(3, 20),
    );

    // 5) Víkendový pobyt (vícedenní) ------------------------------------------
    final weekendStart = ago(31, 9);
    final weekend = EventItem(
      id: 'sample-vikend',
      title: 'Víkend v Jeseníkách',
      category: EventCategory.vacation,
      startDate: weekendStart,
      endDate: ago(29, 18),
      location: 'Karlova Studánka',
      latitude: 50.0717,
      longitude: 17.3044,
      description: 'Prodloužený podzimní víkend v penzionu pod Pradědem.',
      weather: '🍂 8–12 °C, podzimní slunce',
      participants: const ['Táta', 'Máma', 'Ema', 'Vojta'],
      aiStory: 'Tři dny v Jeseníkách byly jako z pohádky – první den jsme se ubytovali a prozkoumali '
          'lázeňské kolonády, druhý den jsme vystoupali až na Praděd a třetí den nám počasí dopřálo '
          'pohodový návrat přes Bílou Opavu. Nejvíc se nám líbily dřevěné lávky nad vodopády.',
      days: [
        EventDay(
          id: 'sample-vikend-d1',
          dayNumber: 1,
          date: ago(31),
          title: 'Příjezd a kolonády',
          note: 'Ubytování v penzionu, procházka lázněmi, večer deskovky.',
          weather: '☀️ 12 °C',
          moments: [
            m('sample-vikend-d1-1', ago(31, 14, 10), 'vikend-kolonada', 'Lázeňská kolonáda', 50.0717, 17.3044),
            m('sample-vikend-d1-2', ago(31, 20, 30), 'vikend-hry', 'Večerní deskovky', 50.0717, 17.3044),
          ],
        ),
        EventDay(
          id: 'sample-vikend-d2',
          dayNumber: 2,
          date: ago(30),
          title: 'Výstup na Praděd',
          note: 'Z Ovčárny pěšky nahoru, rozhledna, horká čokoláda.',
          weather: '🌬️ 4 °C na vrcholu, silný vítr',
          aiStory: 'Na Pradědu foukalo tak, že Vojta tvrdil, že ho vítr odnese až do Polska. '
              'Horká čokoláda na vrcholu ale všechno spravila.',
          moments: [
            m('sample-vikend-d2-1', ago(30, 10, 45), 'vikend-ovcarna', 'Start na Ovčárně', 50.0631, 17.2328),
            m('sample-vikend-d2-2', ago(30, 12, 20), 'vikend-praded', 'Vrchol Pradědu', 50.0832, 17.2310),
          ],
        ),
        EventDay(
          id: 'sample-vikend-d3',
          dayNumber: 3,
          date: ago(29),
          title: 'Bílá Opava',
          note: 'Lávky a žebříky podél vodopádů, cestou domů oběd v Malé Morávce.',
          weather: '⛅ 10 °C',
          moments: [
            m('sample-vikend-d3-1', ago(29, 11, 0), 'vikend-opava', 'Lávky nad Bílou Opavou', 50.0790, 17.2700),
          ],
        ),
      ],
      createdAt: ago(29, 21),
      updatedAt: ago(28, 9),
    );

    // 6) Letní dovolená ------------------------------------------------------
    final summerStart = ago(120, 6);
    final summer = EventItem(
      id: 'sample-chorvatsko',
      title: 'Letní dovolená v Chorvatsku',
      category: EventCategory.vacation,
      startDate: summerStart,
      endDate: ago(116, 20),
      location: 'Makarska, Chorvatsko',
      latitude: 43.2969,
      longitude: 17.0178,
      description: 'Týden u moře – šnorchlování, výlet lodí a zmrzlina každý večer.',
      weather: '☀️ 31 °C, moře 25 °C',
      participants: const ['Táta', 'Máma', 'Ema', 'Vojta'],
      days: [
        EventDay(
          id: 'sample-chorvatsko-d1',
          dayNumber: 1,
          date: ago(120),
          title: 'Cesta k moři',
          note: 'Celodenní cesta autem, první koupání při západu slunce.',
          moments: [
            m('sample-chorvatsko-d1-1', ago(120, 19, 50), 'chorvatsko-zapad', 'První západ slunce', 43.2969, 17.0178),
          ],
        ),
        EventDay(
          id: 'sample-chorvatsko-d2',
          dayNumber: 2,
          date: ago(119),
          title: 'Šnorchlování',
          moments: [
            m('sample-chorvatsko-d2-1', ago(119, 10, 15), 'chorvatsko-more', 'Ryby u útesu', 43.2950, 17.0100),
          ],
        ),
        EventDay(id: 'sample-chorvatsko-d3', dayNumber: 3, date: ago(118), title: 'Výlet lodí na Brač'),
        EventDay(id: 'sample-chorvatsko-d4', dayNumber: 4, date: ago(117), title: 'Odpočinek na pláži'),
        EventDay(id: 'sample-chorvatsko-d5', dayNumber: 5, date: ago(116), title: 'Cesta domů'),
      ],
      createdAt: ago(116, 22),
      updatedAt: ago(115, 10),
    );

    return [paprsek, divadlo, besidka, aquapark, weekend, summer];
  }
}

