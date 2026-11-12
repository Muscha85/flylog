import 'dart:async';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../../../core/config/app_config.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';
import '../../../core/utils/formatters.dart';
import '../../chronicle/models/event_day.dart';
import '../../chronicle/models/event_item.dart';
import '../../chronicle/models/moment_item.dart';

/// Výsledek generování příběhu.
class AiStoryResult {
  const AiStoryResult({
    required this.text,
    required this.fromMock,
    required this.durationMs,
    this.model,
    this.fallbackReason,
  });

  final String text;

  /// `true`, pokud text vytvořil lokální generátor (offline / bez klíče / po chybě).
  final bool fromMock;

  final int durationMs;
  final String? model;

  /// Důvod přepnutí na mock, pokud k němu došlo kvůli chybě.
  final String? fallbackReason;

  String get sourceLabel => fromMock ? 'Offline generátor' : 'Google Gemini (${model ?? ''})';
}

/// AI průvodce – generuje rodinné příběhy z událostí kroniky.
///
/// Pokud je v [AppConfig] zapnutý režim Gemini a je zadán API klíč, volá
/// Google Gemini. Jinak (nebo při jakékoli chybě) použije lokální
/// šablonový generátor, takže aplikace funguje vždy i bez sítě.
class AiService {
  AiService({AppConfig? config, this.timeout = const Duration(seconds: 45)})
      : _config = config ?? AppConfig.instance;

  final AppConfig _config;
  final Duration timeout;

  static const String _module = LogModule.ai;

  /// Vygeneruje příběh celé akce, nebo jen jednoho dne ([day]).
  Future<AiStoryResult> generateStory(EventItem event, {EventDay? day}) async {
    final sw = Stopwatch()..start();
    final scope = day == null ? 'event' : 'day';
    final prompt = buildPrompt(event, day: day);

    AppLogger.I.info(_module, 'generate_story_start', metrics: {
      'event_id': event.id,
      'scope': scope,
      if (day != null) 'day': day.dayNumber,
      'mode': _config.useRealAi ? 'gemini' : 'mock',
      'prompt_chars': prompt.length,
    });

    if (!_config.useRealAi) {
      final text = await _mockStory(event, day: day);
      final result = AiStoryResult(text: text, fromMock: true, durationMs: sw.elapsedMilliseconds);
      AppLogger.I.info(_module, 'generate_story_mock', metrics: {
        'event_id': event.id,
        'scope': scope,
        'chars': text.length,
        'reason': _config.aiMode == AiMode.mock ? 'mode_mock' : 'missing_api_key',
        'duration_ms': result.durationMs,
      });
      return result;
    }

    try {
      final model = GenerativeModel(
        model: _config.geminiModel,
        apiKey: _config.geminiApiKey,
        generationConfig: GenerationConfig(temperature: 0.8, maxOutputTokens: 1024),
        systemInstruction: Content.system(
          'Jsi laskavý rodinný kronikář. Píšeš česky, vřele a s humorem, '
          'krátké příběhy pro rodinnou kroniku. Nevymýšlej si fakta, která nejsou v podkladech, '
          'drž se 1–3 odstavců a nepoužívej Markdown nadpisy.',
        ),
      );
      final response = await model.generateContent([Content.text(prompt)]).timeout(timeout);
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        throw StateError('Gemini vrátil prázdnou odpověď (finishReason: '
            '${response.candidates.isEmpty ? 'none' : response.candidates.first.finishReason?.name})');
      }
      final usage = response.usageMetadata;
      final result = AiStoryResult(
        text: text,
        fromMock: false,
        durationMs: sw.elapsedMilliseconds,
        model: _config.geminiModel,
      );
      AppLogger.I.info(_module, 'generate_story_gemini', metrics: {
        'event_id': event.id,
        'scope': scope,
        'model': _config.geminiModel,
        'chars': text.length,
        if (usage?.promptTokenCount != null) 'prompt_tokens': usage!.promptTokenCount,
        if (usage?.candidatesTokenCount != null) 'output_tokens': usage!.candidatesTokenCount,
        'duration_ms': result.durationMs,
      });
      return result;
    } catch (e, st) {
      AppLogger.I.error(_module, 'generate_story_gemini_failed', error: e, stackTrace: st, metrics: {
        'event_id': event.id,
        'model': _config.geminiModel,
        'key': _config.maskedApiKey,
        'duration_ms': sw.elapsedMilliseconds,
      });
      final text = await _mockStory(event, day: day, quick: true);
      AppLogger.I.warn(_module, 'generate_story_fallback_mock', metrics: {
        'event_id': event.id,
        'chars': text.length,
      });
      return AiStoryResult(
        text: text,
        fromMock: true,
        durationMs: sw.elapsedMilliseconds,
        fallbackReason: _humanError(e),
      );
    }
  }

  /// Ověří spojení s Gemini API krátkým dotazem.
  Future<String> testConnection({String? modelOverride, String? apiKeyOverride}) async {
    final sw = Stopwatch()..start();
    final key = apiKeyOverride ?? _config.geminiApiKey;
    final modelName = modelOverride ?? _config.geminiModel;

    if (key.trim().isEmpty) {
      AppLogger.I.warn(_module, 'test_connection_no_key');
      return 'Není zadán Gemini API klíč – AI běží v offline režimu.';
    }
    try {
      final model = GenerativeModel(model: modelName, apiKey: key);
      final response = await model
          .generateContent([Content.text('Odpověz jedním slovem česky: funguješ?')]).timeout(timeout);
      final text = response.text?.trim() ?? '';
      AppLogger.I.info(_module, 'test_connection_ok', metrics: {
        'model': modelName,
        'duration_ms': sw.elapsedMilliseconds,
      });
      return 'Spojení OK ($modelName, ${sw.elapsedMilliseconds} ms): $text';
    } catch (e, st) {
      AppLogger.I.error(_module, 'test_connection_failed', error: e, stackTrace: st, metrics: {
        'model': modelName,
        'duration_ms': sw.elapsedMilliseconds,
      });
      return 'Chyba spojení ($modelName): ${_humanError(e)}';
    }
  }

  /// Sestaví prompt z dat události.
  String buildPrompt(EventItem event, {EventDay? day}) {
    final b = StringBuffer()
      ..writeln('Napiš krátký rodinný příběh do kroniky rodiny ${_config.familyName}.')
      ..writeln()
      ..writeln('Akce: ${event.title}')
      ..writeln('Kategorie: ${event.category.label}')
      ..writeln('Datum: ${event.dateLabel}');
    if (event.location.isNotEmpty) b.writeln('Místo: ${event.location}');
    if (event.weather != null && event.weather!.isNotEmpty) b.writeln('Počasí: ${event.weather}');
    if (event.participants.isNotEmpty) b.writeln('Účastníci: ${event.participants.join(', ')}');
    if (event.description.isNotEmpty) b.writeln('Poznámky: ${event.description}');

    List<MomentItem> moments;
    if (day != null) {
      b
        ..writeln()
        ..writeln('Piš POUZE o tomto dni: ${day.displayTitle} (${Fmt.longDate(day.date)})');
      if (day.note.isNotEmpty) b.writeln('Poznámky ke dni: ${day.note}');
      if (day.weather != null && day.weather!.isNotEmpty) b.writeln('Počasí ve dni: ${day.weather}');
      moments = day.moments;
    } else {
      if (event.hasDays) {
        b
          ..writeln()
          ..writeln('Program po dnech:');
        for (final d in event.sortedDays) {
          b.writeln('- ${d.displayTitle}${d.note.isNotEmpty ? ': ${d.note}' : ''}');
        }
      }
      moments = event.allMoments;
    }

    final notes = moments.where((m) => m.note.isNotEmpty).toList();
    if (notes.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Popisky fotek v časovém pořadí:');
      for (final m in notes.take(30)) {
        b.writeln('- ${Fmt.time(m.takenAt)} ${m.note}');
      }
    }
    return b.toString();
  }

  // ---------------------------------------------------------------------------
  // Mock generátor
  // ---------------------------------------------------------------------------

  Future<String> _mockStory(EventItem event, {EventDay? day, bool quick = false}) async {
    // Simulace „přemýšlení“, aby se UI chovalo stejně jako se skutečným AI.
    await Future<void>.delayed(Duration(milliseconds: quick ? 150 : 900));

    final who = _joinCz(event.participants);
    final place = event.location.isEmpty ? '' : ' (${event.location})';

    if (day != null) {
      final notes = day.moments.where((m) => m.note.isNotEmpty).map((m) => m.note.toLowerCase()).toList();
      final b = StringBuffer()
        ..write('${_capitalize(Fmt.weekday(day.date))} ${Fmt.dayMonth(day.date)} – ${day.displayTitle}. ');
      if (day.note.isNotEmpty) b.write('${_sentence(day.note)} ');
      if (day.weather != null && day.weather!.isNotEmpty) b.write('Počasí: ${day.weather}. ');
      if (notes.isNotEmpty) {
        b.write('Ve fotkách jsme zachytili ${_joinCz(notes.take(4).toList())}. ');
      }
      b.write('Byl to den, na který budeme ještě dlouho vzpomínat.');
      return b.toString();
    }

    final opening = switch (event.category) {
      EventCategory.trip => 'Batohy na záda a hurá do přírody! ',
      EventCategory.culture => 'Tentokrát jsme vyměnili turistické boty za sváteční oblečení. ',
      EventCategory.school => 'Velký den pro naše malé umělce! ',
      EventCategory.fun => 'Den plný vody, smíchu a odpočinku. ',
      EventCategory.vacation => 'Dovolená, na kterou jsme se těšili celé týdny, konečně začala. ',
    };

    final b = StringBuffer()
      ..write(opening)
      ..write('${_capitalize(Fmt.longDate(event.startDate))} '
          '${event.participants.isEmpty ? 'jsme se' : 'se $who'} vydali na akci „${event.title}“$place. ');
    if (event.weather != null && event.weather!.isNotEmpty) {
      b.write('Počasí nám přálo po svém: ${event.weather}. ');
    }
    if (event.description.isNotEmpty) b.write('${_sentence(event.description)} ');

    if (event.hasDays) {
      b.write('\n\nAkce trvala ${Fmt.plural(event.durationDays, 'den', 'dny', 'dní')}. ');
      for (final d in event.sortedDays) {
        b.write('${d.displayTitle}${d.note.isNotEmpty ? ' – ${_lowerFirst(d.note)}' : ''}. ');
      }
    }

    final notes = event.allMoments.where((m) => m.note.isNotEmpty).map((m) => m.note.toLowerCase()).toList();
    if (notes.isNotEmpty) {
      b.write('\n\nNejhezčí chvíle? ${_capitalize(_joinCz(notes.take(5).toList()))}. ');
    }
    final count = event.momentCount;
    if (count > 0) {
      b.write('Domů jsme si odvezli ${Fmt.plural(count, 'fotku', 'fotky', 'fotek')} a spoustu zážitků.');
    } else {
      b.write('Fotky sice nemáme, ale zážitky zůstanou v srdci.');
    }
    b.write('\n\n(Text vytvořil offline generátor FlyLog – pro skutečný AI příběh zadejte '
        'Gemini API klíč v Nastavení.)');
    return b.toString();
  }

  static String _joinCz(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} a ${items.last}';
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _lowerFirst(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    final withoutDot = t.endsWith('.') ? t.substring(0, t.length - 1) : t;
    return withoutDot[0].toLowerCase() + withoutDot.substring(1);
  }

  static String _sentence(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return (t.endsWith('.') || t.endsWith('!') || t.endsWith('?')) ? t : '$t.';
  }

  static String _humanError(Object e) {
    final msg = e.toString();
    if (e is TimeoutException) return 'Vypršel časový limit odpovědi.';
    if (msg.contains('API key') || msg.contains('API_KEY')) return 'Neplatný API klíč.';
    if (msg.contains('SocketException') || msg.contains('Failed host lookup')) return 'Bez připojení k internetu.';
    if (msg.contains('quota') || msg.contains('429')) return 'Vyčerpaná kvóta Gemini API.';
    return msg.length > 160 ? '${msg.substring(0, 160)}…' : msg;
  }
}
