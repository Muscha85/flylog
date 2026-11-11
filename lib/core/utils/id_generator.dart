import 'dart:math';

/// Jednoduchý generátor unikátních ID (časová značka + náhodná část).
///
/// Formát je kompatibilní s ID dokumentů ve Firestore (alfanumerický řetězec).
abstract final class IdGen {
  static final Random _random = Random.secure();
  static const String _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  static String next([String prefix = '']) {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = List.generate(6, (_) => _chars[_random.nextInt(_chars.length)]).join();
    return '$prefix$ts$rnd';
  }
}

