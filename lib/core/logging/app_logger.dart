import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'log_entry.dart';

/// Centrální strukturovaný logger aplikace FlyLog (singleton).
///
/// * drží kruhový paměťový buffer posledních [maxEntries] záznamů,
/// * notifikuje posluchače (debug konzole se překresluje živě),
/// * umí měřit dobu trvání asynchronních operací ([measure]),
/// * exportuje Markdown report připravený pro AI analýzu ([exportForAi]).
class AppLogger extends ChangeNotifier {
  AppLogger._internal();

  static final AppLogger instance = AppLogger._internal();

  /// Zkratka – `AppLogger.I.info(...)`.
  static AppLogger get I => instance;

  /// Maximální počet záznamů v paměti.
  static const int maxEntries = 1000;

  final ListQueue<LogEntry> _buffer = ListQueue<LogEntry>();
  final DateTime _sessionStart = DateTime.now();

  /// Volitelný poskytovatel doplňkových informací (verze aplikace, režim AI …).
  Map<String, String> Function()? contextProvider;

  /// Všechny záznamy od nejstaršího po nejnovější.
  List<LogEntry> get entries => List.unmodifiable(_buffer);

  int get length => _buffer.length;

  DateTime get sessionStart => _sessionStart;

  int countOf(LogLevel level) => _buffer.where((e) => e.level == level).length;

  // ---------------------------------------------------------------------------
  // Zápis
  // ---------------------------------------------------------------------------

  LogEntry log({
    required String module,
    required LogLevel level,
    required String action,
    Map<String, Object?>? metrics,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      module: module,
      level: level,
      action: action,
      metrics: metrics,
      error: error?.toString(),
      stackTrace: stackTrace == null ? null : _trimStack(stackTrace),
    );
    _buffer.addLast(entry);
    while (_buffer.length > maxEntries) {
      _buffer.removeFirst();
    }

    developer.log(
      entry.toConsoleLine(),
      name: 'FlyLog.$module',
      level: switch (level) {
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      },
      error: error,
      stackTrace: stackTrace,
    );
    if (kDebugMode) {
      debugPrint(entry.toConsoleLine());
    }

    _scheduleNotify();
    return entry;
  }

  LogEntry info(String module, String action, {Map<String, Object?>? metrics}) =>
      log(module: module, level: LogLevel.info, action: action, metrics: metrics);

  LogEntry warn(String module, String action, {Map<String, Object?>? metrics, Object? error}) =>
      log(module: module, level: LogLevel.warn, action: action, metrics: metrics, error: error);

  LogEntry error(
    String module,
    String action, {
    Map<String, Object?>? metrics,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        module: module,
        level: LogLevel.error,
        action: action,
        metrics: metrics,
        error: error,
        stackTrace: stackTrace,
      );

  /// Změří dobu běhu [body] a zapíše výsledek (včetně `duration_ms`).
  ///
  /// Při výjimce zapíše ERROR záznam a výjimku propaguje dál.
  Future<T> measure<T>(
    String module,
    String action,
    Future<T> Function() body, {
    Map<String, Object?>? metrics,
    Map<String, Object?> Function(T result)? resultMetrics,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await body();
      sw.stop();
      info(module, action, metrics: {
        ...?metrics,
        ...?resultMetrics?.call(result),
        'duration_ms': sw.elapsedMilliseconds,
      });
      return result;
    } catch (e, st) {
      sw.stop();
      error(
        module,
        action,
        metrics: {...?metrics, 'duration_ms': sw.elapsedMilliseconds},
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  void clear() {
    _buffer.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Informace o platformě a běhu – součást AI reportu.
  Map<String, String> platformInfo() {
    final info = <String, String>{
      'app': 'FlyLog',
      'build_mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'session_start': _sessionStart.toIso8601String(),
      'session_uptime_s': DateTime.now().difference(_sessionStart).inSeconds.toString(),
      'buffer_entries': _buffer.length.toString(),
    };
    if (kIsWeb) {
      info['platform'] = 'web';
    } else {
      info['os'] = Platform.operatingSystem;
      info['os_version'] = Platform.operatingSystemVersion;
      info['dart_version'] = Platform.version.split(' ').first;
      info['locale'] = Platform.localeName;
      info['cpu_cores'] = Platform.numberOfProcessors.toString();
    }
    final display = PlatformDispatcher.instance.displays;
    if (display.isNotEmpty) {
      final d = display.first;
      info['display_px'] = '${d.size.width.round()}x${d.size.height.round()}';
      info['display_dpr'] = d.devicePixelRatio.toStringAsFixed(2);
      info['display_dp'] =
          '${(d.size.width / d.devicePixelRatio).round()}x${(d.size.height / d.devicePixelRatio).round()}';
    }
    final extra = contextProvider?.call();
    if (extra != null) info.addAll(extra);
    return info;
  }

  /// Vytvoří Markdown report z posledních [last] záznamů pro AI analýzu.
  String exportForAi({int last = 50, Iterable<LogEntry>? source}) {
    final all = (source ?? _buffer).toList();
    final slice = all.length > last ? all.sublist(all.length - last) : all;
    final errors = slice.where((e) => e.level == LogLevel.error).length;
    final warns = slice.where((e) => e.level == LogLevel.warn).length;

    final b = StringBuffer()
      ..writeln('# FlyLog – systémový log pro AI analýzu')
      ..writeln()
      ..writeln('Vygenerováno: ${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln('## Platforma')
      ..writeln();
    platformInfo().forEach((k, v) => b.writeln('- **$k**: $v'));
    b
      ..writeln()
      ..writeln('## Souhrn')
      ..writeln()
      ..writeln('- Záznamů v reportu: ${slice.length} (z ${all.length} v bufferu)')
      ..writeln('- ERROR: $errors, WARN: $warns, INFO: ${slice.length - errors - warns}')
      ..writeln()
      ..writeln('## Záznamy (nejstarší → nejnovější)')
      ..writeln()
      ..writeln('| timestamp | level | module | action | metrics | error |')
      ..writeln('|---|---|---|---|---|---|');
    for (final e in slice) {
      b.writeln(e.toMarkdownRow());
    }

    final withStack = slice.where((e) => e.stackTrace != null).toList();
    if (withStack.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Stack traces chyb');
      for (final e in withStack) {
        b
          ..writeln()
          ..writeln('### ${e.isoTimestamp} · ${e.module} › ${e.action}')
          ..writeln()
          ..writeln('```')
          ..writeln(e.stackTrace)
          ..writeln('```');
      }
    }

    b
      ..writeln()
      ..writeln('## Strojově čitelná data (JSON Lines)')
      ..writeln()
      ..writeln('```jsonl');
    for (final e in slice) {
      b.writeln(e.toJsonLine());
    }
    b
      ..writeln('```')
      ..writeln()
      ..writeln('> Prosím analyzuj tento log: najdi chyby, pomalé operace (duration_ms) '
          'a navrhni konkrétní opravy v kódu Flutter aplikace FlyLog.');
    return b.toString();
  }

  // ---------------------------------------------------------------------------
  // Interní
  // ---------------------------------------------------------------------------

  bool _notifyScheduled = false;

  /// Notifikace posluchačů se slučuje do jedné mikroúlohy – logování může
  /// probíhat i během buildu widgetů a nesmí vyvolat `setState` uprostřed buildu.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  String _trimStack(StackTrace st) {
    final lines = st.toString().split('\n').where((l) => l.trim().isNotEmpty).take(12);
    return lines.join('\n');
  }
}

