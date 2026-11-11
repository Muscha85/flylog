import 'package:intl/intl.dart';

/// Formátovací pomůcky v češtině, nezávislé na inicializaci locale dat.
abstract final class Fmt {
  static const List<String> _weekdays = [
    'pondělí',
    'úterý',
    'středa',
    'čtvrtek',
    'pátek',
    'sobota',
    'neděle',
  ];

  static const List<String> _monthsGenitive = [
    'ledna',
    'února',
    'března',
    'dubna',
    'května',
    'června',
    'července',
    'srpna',
    'září',
    'října',
    'listopadu',
    'prosince',
  ];

  static const List<String> monthsNominative = [
    'leden',
    'únor',
    'březen',
    'duben',
    'květen',
    'červen',
    'červenec',
    'srpen',
    'září',
    'říjen',
    'listopad',
    'prosinec',
  ];

  static final DateFormat _numeric = DateFormat('d. M. yyyy');
  static final DateFormat _time = DateFormat('HH:mm');
  static final DateFormat _dateTime = DateFormat('d. M. yyyy HH:mm');

  /// `12. 5. 2025`
  static String date(DateTime d) => _numeric.format(d);

  /// `14:35`
  static String time(DateTime d) => _time.format(d);

  /// `12. 5. 2025 14:35`
  static String dateTime(DateTime d) => _dateTime.format(d);

  /// `sobota 12. května 2025`
  static String longDate(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day}. ${_monthsGenitive[d.month - 1]} ${d.year}';

  /// `sobota`
  static String weekday(DateTime d) => _weekdays[d.weekday - 1];

  /// `12. května`
  static String dayMonth(DateTime d) => '${d.day}. ${_monthsGenitive[d.month - 1]}';

  /// Rozsah dat – `12.–14. 7. 2025`, `30. 6. – 2. 7. 2025` …
  static String dateRange(DateTime start, DateTime? end) {
    if (end == null || isSameDay(start, end)) return date(start);
    if (start.year == end.year && start.month == end.month) {
      return '${start.day}.–${end.day}. ${end.month}. ${end.year}';
    }
    if (start.year == end.year) {
      return '${start.day}. ${start.month}. – ${end.day}. ${end.month}. ${end.year}';
    }
    return '${date(start)} – ${date(end)}';
  }

  static bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Počet kalendářních dní mezi daty včetně obou krajních.
  static int daysInclusive(DateTime start, DateTime end) {
    final s = DateTime.utc(start.year, start.month, start.day);
    final e = DateTime.utc(end.year, end.month, end.day);
    return e.difference(s).inDays + 1;
  }

  /// Správné skloňování – `1 fotka`, `3 fotky`, `5 fotek`.
  static String plural(int count, String one, String few, String many) {
    if (count == 1) return '$count $one';
    if (count >= 2 && count <= 4) return '$count $few';
    return '$count $many';
  }

  /// Velikost v kB/MB.
  static String sizeKb(int kb) => kb >= 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '$kb kB';
}

