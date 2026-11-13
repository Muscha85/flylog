import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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

/// AI průvodce – generuje rodinné příběhy z událostí kroniky a tipy k lokalitě.
class AiService {
  AiService({AppConfig? config, this.timeout = const Duration(seconds: 45), http.Client? client})
      : _config = config ?? AppConfig.instance,
        _client = client ?? http.Client();

  final AppConfig _config;
  final Duration timeout;
  final http.Client _client;

  static const String _module = LogModule.ai;

  /// Záložní modely ověřené v Google API pro tento klíč.
  static const List<String> fallbackModels = [
    'gemini-flash-lite-latest',
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'gemini-3-flash-preview',
    'gemini-3.6-flash',
  ];

  /// Fáze A: Vygeneruje strukturované tipy o lokalitě (historie, současnost, tipy v okolí, nápady pro děti).
  Future<AiStoryResult> generateLocationGuide({
    required String location,
    double? latitude,
    double? longitude,
  }) async {
    final sw = Stopwatch()..start();
    final prompt = '''
Jsi laskavý a vzdělaný rodinný průvodce.
Připrav stručný, přehledný a praktický přehled zajímavostí o tomto místě pro rodinný výlet:
Místo: $location ${latitude != null && longitude != null ? '(GPS: ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})' : ''}

Struktura výstupu (použij přehledné odrážky):
🏛️ **Zajímavosti a historie:** (2-3 věty o tom, čím je místo výjimečné)
🌲 **Co neminout v okolí:** (2-3 konkrétní tipy na zajímavá místa v pěší nebo krátké dojezdové vzdálenosti)
🧒 **Zábava a tipy pro děti:** (co zaujme děti – hřiště, pověsti, dobrodružství, občerstvení)
💡 **Praktická rada:** (parkování, terén, kočárky...)
''';

    AppLogger.I.info(_module, 'generate_location_guide_start', metrics: {
      'location': location,
      'mode': _config.useRealAi ? 'gemini' : 'mock',
    });

    if (!_config.useRealAi) {
      final mock = '''
🏛️ **Zajímavosti a historie:** $location je krásná lokalita s bohatou historií a čistou přírodou v okolí.
🌲 **Co neminout v okolí:** Vyhlídková místa, místní lesní stezky a historické centrum.
🧒 **Zábava a tipy pro děti:** Hledání přírodních pokladů a sběr šišek podél stezky.
💡 **Praktická rada:** Pohodlná turistická obuv a svačina do batohu se vždy hodí!
''';
      return AiStoryResult(text: mock, fromMock: true, durationMs: sw.elapsedMilliseconds);
    }

    try {
      final (text, usedModel, _, _) = await _generateWithRetry(
        prompt: prompt,
        initialModel: _config.geminiModel,
        apiKey: _config.geminiApiKey,
        callTimeout: timeout,
        temperature: 0.6,
        maxTokens: 800,
      );

      return AiStoryResult(
        text: text,
        fromMock: false,
        durationMs: sw.elapsedMilliseconds,
        model: usedModel,
      );
    } catch (e, st) {
      AppLogger.I.error(_module, 'generate_location_guide_failed', error: e, stackTrace: st);
      final fallback = 'Tipy k lokalitě $location se nepodařilo načíst online: ${_humanError(e)}';
      return AiStoryResult(text: fallback, fromMock: true, durationMs: sw.elapsedMilliseconds);
    }
  }

  /// Fáze B: Vygeneruje finální čtivý příběh celé akce nebo jednoho dne.
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

    final primaryModel = _config.geminiModel;
    try {
      final (text, usedModel, promptTokens, candidatesTokens) = await _generateWithRetry(
        prompt: prompt,
        initialModel: primaryModel,
        apiKey: _config.geminiApiKey,
        callTimeout: timeout,
        temperature: 0.8,
        maxTokens: 1024,
      );

      final result = AiStoryResult(
        text: text,
        fromMock: false,
        durationMs: sw.elapsedMilliseconds,
        model: usedModel,
      );

      AppLogger.I.info(_module, 'generate_story_gemini', metrics: {
        'event_id': event.id,
        'scope': scope,
        'model': usedModel,
        'chars': text.length,
        if (promptTokens != null) 'prompt_tokens': promptTokens,
        if (candidatesTokens != null) 'output_tokens': candidatesTokens,
        'duration_ms': result.durationMs,
      });
      return result;
    } catch (e, st) {
      AppLogger.I.error(_module, 'generate_story_gemini_failed', error: e, stackTrace: st, metrics: {
        'event_id': event.id,
        'model': primaryModel,
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

  /// Volá Gemini REST API přímo přes HTTP s retry logikou a okamžitým fallbackem.
  Future<(String text, String usedModel, int? promptTokens, int? candidatesTokens)> _generateWithRetry({
    required String prompt,
    required String initialModel,
    required String apiKey,
    Duration? callTimeout,
    double temperature = 0.7,
    int maxTokens = 1024,
    int maxRetries = 2,
  }) async {
    final effectiveTimeout = callTimeout ?? timeout;
    final candidateModels = [
      initialModel,
      ...fallbackModels.where((m) => m != initialModel),
    ];

    Object? lastError;
    StackTrace? lastStackTrace;

    for (int mIdx = 0; mIdx < candidateModels.length; mIdx++) {
      final currentModelName = candidateModels[mIdx];
      final isFallback = mIdx > 0;

      if (isFallback) {
        AppLogger.I.warn(_module, 'gemini_fallback_attempt', metrics: {
          'previous_model': candidateModels[mIdx - 1],
          'new_model': currentModelName,
          'reason': '$lastError',
        });
      }

      int delaySeconds = 2;

      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$currentModelName:generateContent?key=$apiKey',
          );

          final requestPayload = {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {
                    'text': prompt,
                  }
                ],
              }
            ],
            'generationConfig': {
              'temperature': temperature,
              'maxOutputTokens': maxTokens,
            },
          };

          final response = await _client
              .post(
                url,
                headers: {'Content-Type': 'application/json; charset=utf-8'},
                body: jsonEncode(requestPayload),
              )
              .timeout(effectiveTimeout);

          if (response.statusCode == 200) {
            final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
            final candidates = data['candidates'] as List?;
            if (candidates == null || candidates.isEmpty) {
              throw StateError('Gemini vrátil prázdný seznam kandidátů.');
            }
            final firstCandidate = candidates.first as Map;
            final content = firstCandidate['content'] as Map?;
            final parts = (content?['parts'] as List?)?.whereType<Map>().toList();
            final text = parts?.map((p) => p['text']?.toString() ?? '').join().trim() ?? '';

            if (text.isEmpty) {
              throw StateError('Odpověď z modelu je prázdná.');
            }

            final usage = data['usageMetadata'] as Map?;
            final pTokens = (usage?['promptTokenCount'] as num?)?.toInt();
            final cTokens = (usage?['candidatesTokenCount'] as num?)?.toInt();

            if (isFallback) {
              AppLogger.I.info(_module, 'gemini_fallback_success', metrics: {
                'fallback_model': currentModelName,
                'original_model': initialModel,
                'attempt': attempt,
              });
            }

            return (text, currentModelName, pTokens, cTokens);
          }

          final code = response.statusCode;
          final errorBody = utf8.decode(response.bodyBytes);

          if (code == 503 || code == 404) {
            throw HttpException('HTTP $code: $errorBody');
          }

          if (code == 429) {
            if (attempt < maxRetries) {
              AppLogger.I.warn(_module, 'gemini_429_rate_limit_retry', metrics: {
                'model': currentModelName,
                'retry_in': delaySeconds,
              });
              await Future<void>.delayed(Duration(seconds: delaySeconds));
              delaySeconds *= 2;
              continue;
            }
            throw HttpException('HTTP 429 Rate Limit: $errorBody');
          }

          throw HttpException('HTTP $code: $errorBody');
        } catch (e, st) {
          lastError = e;
          lastStackTrace = st;

          final isTimeout = e is TimeoutException;
          final isHttp503or404 = e is HttpException && (e.message.contains('503') || e.message.contains('404'));

          if ((isTimeout || isHttp503or404) && mIdx < candidateModels.length - 1) {
            AppLogger.I.warn(_module, 'gemini_switching_to_next_model', metrics: {
              'failed_model': currentModelName,
              'reason': e.toString(),
            });
            break;
          }

          if (attempt < maxRetries && !isTimeout && !isHttp503or404) {
            await Future<void>.delayed(Duration(seconds: delaySeconds));
            delaySeconds *= 2;
            continue;
          }

          if (mIdx < candidateModels.length - 1) {
            break;
          }

          rethrow;
        }
      }
    }

    if (lastError != null) {
      if (lastStackTrace != null) {
        Error.throwWithStackTrace(lastError, lastStackTrace);
      }
      throw lastError;
    }
    throw StateError('Nepodařilo se vygenerovat příběh.');
  }

  /// Ověří spojení s Gemini API krátkým dotazem.
  Future<String> testConnection({
    String? modelOverride,
    String? apiKeyOverride,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final sw = Stopwatch()..start();
    final key = apiKeyOverride ?? _config.geminiApiKey;
    final modelName = modelOverride ?? _config.geminiModel;

    if (key.trim().isEmpty) {
      AppLogger.I.warn(_module, 'test_connection_no_key');
      return 'Není zadán Gemini API klíč – AI běží v offline režimu.';
    }

    try {
      final (text, usedModel, _, _) = await _generateWithRetry(
        prompt: 'Odpověz jedním slovem česky: funguješ?',
        initialModel: modelName,
        apiKey: key,
        callTimeout: timeout,
        temperature: 0.2,
        maxTokens: 50,
        maxRetries: 1,
      );

      final isFallback = usedModel != modelName;
      AppLogger.I.info(_module, 'test_connection_ok', metrics: {
        'model': usedModel,
        'requested_model': modelName,
        'is_fallback': isFallback,
        'duration_ms': sw.elapsedMilliseconds,
      });

      if (isFallback) {
        return 'Spojení aktivní přes záložní model $usedModel (${sw.elapsedMilliseconds} ms): $text\n'
            '(Původní model $modelName je dočasně pomalý nebo nedostupný)';
      }

      return 'Spojení OK ($usedModel, ${sw.elapsedMilliseconds} ms): $text';
    } catch (e, st) {
      AppLogger.I.error(_module, 'test_connection_failed', error: e, stackTrace: st, metrics: {
        'model': modelName,
        'duration_ms': sw.elapsedMilliseconds,
      });
      return 'Chyba spojení ($modelName): ${_humanError(e)}';
    }
  }

  /// Sestaví prompt z dat události včetně průběžných poznámek a tipů průvodce.
  String buildPrompt(EventItem event, {EventDay? day}) {
    final b = StringBuffer()
      ..writeln('Jsi laskavý rodinný kronikář. Napiš čtivý, vřelý a humorný zápis do kroniky rodiny ${_config.familyName}.')
      ..writeln()
      ..writeln('Akce: ${event.title}')
      ..writeln('Kategorie: ${event.category.label}')
      ..writeln('Datum: ${event.dateLabel}');
    if (event.location.isNotEmpty) b.writeln('Místo: ${event.location}');
    if (event.weather != null && event.weather!.isNotEmpty) b.writeln('Počasí: ${event.weather}');
    if (event.distanceKm != null) b.writeln('Ujitá trasa: ${event.distanceKm} km');
    if (event.durationMinutes != null) b.writeln('Doba trvání: ${event.durationMinutes} minut');
    if (event.participants.isNotEmpty) b.writeln('Účastníci: ${event.participants.join(', ')}');
    if (event.description.isNotEmpty) b.writeln('Hlavní popis: ${event.description}');
    if (event.extraNotes.isNotEmpty) b.writeln('Praktické tipy / postřehy: ${event.extraNotes}');

    // Průvodce lokalitou
    if (event.hasLocationGuide) {
      b
        ..writeln()
        ..writeln('Kontext o navštíveném místě z průvodce:')
        ..writeln(event.locationGuideText);
    }

    // Rychlé průběžné poznámky
    if (event.quickNotes.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Průběžné časové poznámky rodiny během dne:');
      for (final q in event.sortedQuickNotes) {
        b.writeln('- ${Fmt.time(q.timestamp)}: ${q.text}');
      }
    }

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
        ..writeln('Popisky pořízených fotografií v časovém sledu:');
      for (final m in notes.take(30)) {
        b.writeln('- ${Fmt.time(m.takenAt)}: ${m.note}');
      }
    }

    b
      ..writeln()
      ..writeln('Požadavky na styl zápisu:')
      ..writeln('- Napiš 2 až 4 plynulé odstavce.')
      ..writeln('- V textu propoj to, co rodina reálně zažila a zapsala do poznámek, se zajímavostmi o místě.')
      ..writeln('- Piš laskavě, živě, s citem pro rodinné vzpomínky.');

    return b.toString();
  }

  // ---------------------------------------------------------------------------
  // Mock generátor
  // ---------------------------------------------------------------------------

  Future<String> _mockStory(EventItem event, {EventDay? day, bool quick = false}) async {
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
      EventCategory.diary => 'Dnešní obyčejně neobyčejný den v kruhu rodiny. ',
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
      b.write('Počasí: ${event.weather}. ');
    }
    if (event.distanceKm != null) {
      b.write('V nohách máme pěkných ${event.distanceKm} km. ');
    }
    if (event.description.isNotEmpty) b.write('${_sentence(event.description)} ');

    if (event.quickNotes.isNotEmpty) {
      b.write('\n\nBěhem dne jsme si poznamenali: ');
      b.write(event.quickNotes.map((q) => q.text).join('; '));
      b.write('. ');
    }

    if (event.hasDays) {
      b.write('\n\nAkce trvala ${Fmt.plural(event.durationDays, 'den', 'dny', 'dní')}. ');
      for (final d in event.sortedDays) {
        b.write('${d.displayTitle}${d.note.isNotEmpty ? ' – ${_lowerFirst(d.note)}' : ''}. ');
      }
    }

    final notes = event.allMoments.where((m) => m.note.isNotEmpty).map((m) => m.note.toLowerCase()).toList();
    if (notes.isNotEmpty) {
      b.write('\n\nNejhezčí zachycené chvíle: ${_capitalize(_joinCz(notes.take(5).toList()))}. ');
    }
    final count = event.momentCount;
    if (count > 0) {
      b.write('Do kroniky ukládáme ${Fmt.plural(count, 'fotku', 'fotky', 'fotek')} a spoustu zážitků.');
    }
    b.write('\n\n(Text vytvořil offline generátor FlyLog – pro reálný AI příběh zadejte API klíč.)');
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
    if (e is TimeoutException) return 'Vypršel časový limit odpovědi (timeout).';
    if (msg.contains('API key') || msg.contains('API_KEY')) return 'Neplatný API klíč.';
    if (msg.contains('SocketException') || msg.contains('Failed host lookup')) return 'Bez připojení k internetu.';
    if (msg.contains('quota') || msg.contains('429')) return 'Vyčerpaná kvóta Gemini API.';
    if (msg.contains('503') || msg.contains('high demand')) return 'Servery Gemini jsou momentálně přetížené (503).';
    return msg.length > 160 ? '${msg.substring(0, 160)}…' : msg;
  }
}
