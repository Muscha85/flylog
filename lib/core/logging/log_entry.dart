import 'dart:convert';

/// Úroveň závažnosti logovacího záznamu.
enum LogLevel {
  info('INFO'),
  warn('WARN'),
  error('ERROR');

  const LogLevel(this.label);

  final String label;

  static LogLevel fromLabel(String value) {
    return LogLevel.values.firstWhere(
      (l) => l.label == value.toUpperCase(),
      orElse: () => LogLevel.info,
    );
  }
}

/// Standardní názvy modulů, které logují do [AppLogger].
///
/// Modul je obyčejný řetězec, aby šlo snadno přidávat nové moduly,
/// ale tyto konstanty drží konzistentní pojmenování napříč aplikací.
abstract final class LogModule {
  static const String app = 'app';
  static const String chronicle = 'chronicle';
  static const String media = 'media';
  static const String ai = 'ai';
  static const String web = 'web';
  static const String config = 'config';
  static const String system = 'system';

  static const List<String> all = [app, chronicle, media, ai, web, config, system];
}

/// Jeden strukturovaný záznam systémového logu.
///
/// Struktura je záměrně strojově čitelná (JSON), aby se dala jednoduše
/// předat AI asistentovi k analýze problémů.
class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.module,
    required this.level,
    required this.action,
    Map<String, Object?>? metrics,
    this.error,
    this.stackTrace,
  }) : metrics = Map.unmodifiable(metrics ?? const <String, Object?>{});

  /// Čas vzniku záznamu (lokální čas zařízení).
  final DateTime timestamp;

  /// Modul, který záznam vytvořil (chronicle, media, ai, web …).
  final String module;

  /// Závažnost záznamu.
  final LogLevel level;

  /// Krátký popis akce, např. `compress_image` nebo `generate_story`.
  final String action;

  /// Libovolné metriky – doba trvání v ms, velikost souboru v kB, počty …
  final Map<String, Object?> metrics;

  /// Volitelný text chyby.
  final String? error;

  /// Volitelný stack trace (zkrácený).
  final String? stackTrace;

  /// ISO 8601 reprezentace časové značky včetně offsetu časové zóny.
  String get isoTimestamp {
    final offset = timestamp.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${timestamp.toIso8601String()}$sign$hours:$minutes';
  }

  /// Čas ve formátu HH:mm:ss.SSS pro kompaktní zobrazení v konzoli.
  String get shortTime {
    String two(int v) => v.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}.$ms';
  }

  bool get hasError => error != null && error!.isNotEmpty;

  Map<String, Object?> toJson() => {
        'timestamp': isoTimestamp,
        'module': module,
        'level': level.label,
        'action': action,
        if (metrics.isNotEmpty) 'metrics': metrics,
        if (hasError) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      module: json['module'] as String? ?? LogModule.app,
      level: LogLevel.fromLabel(json['level'] as String? ?? 'INFO'),
      action: json['action'] as String? ?? '',
      metrics: (json['metrics'] as Map?)?.cast<String, Object?>(),
      error: json['error'] as String?,
      stackTrace: json['stackTrace'] as String?,
    );
  }

  /// Kompaktní jednořádkový JSON.
  String toJsonLine() => jsonEncode(toJson());

  /// Lidsky čitelný řádek pro konzoli / debugPrint.
  String toConsoleLine() {
    final buffer = StringBuffer()
      ..write('[$shortTime] ')
      ..write(level.label.padRight(5))
      ..write(' ')
      ..write(module)
      ..write(' › ')
      ..write(action);
    if (metrics.isNotEmpty) {
      buffer.write(' ');
      buffer.write(metricsText);
    }
    if (hasError) {
      buffer.write(' ✖ ');
      buffer.write(error);
    }
    return buffer.toString();
  }

  /// Metriky jako text `klíč=hodnota, …`.
  String get metricsText => metrics.entries.map((e) => '${e.key}=${e.value}').join(', ');

  /// Řádek tabulky pro Markdown export.
  String toMarkdownRow() {
    String esc(String v) => v.replaceAll('|', r'\|').replaceAll('\n', ' ');
    return '| ${esc(isoTimestamp)} | ${level.label} | ${esc(module)} | ${esc(action)} | '
        '${esc(metricsText)} | ${esc(error ?? '')} |';
  }
}

