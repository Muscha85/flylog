import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';
import '../models/favorite_place.dart';

/// Výsledek vyhledání místa v Open-Meteo Geocoding API.
class GeocodingResult {
  const GeocodingResult({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.country,
    this.admin1,
  });

  final String name;
  final double latitude;
  final double longitude;
  final String? country;
  final String? admin1;

  String get displayName => [name, admin1, country].where((s) => s != null && s.isNotEmpty).join(', ');

  FavoritePlace toFavoritePlace() => FavoritePlace(
        name: name,
        latitude: latitude,
        longitude: longitude,
        country: country ?? 'Česko',
      );
}

/// Bezplatná služba pro převod textového názvu místa na GPS souřadnice (Geocoding)
/// bez nutnosti registrace nebo API klíče (Open-Meteo).
class GeocodingService {
  const GeocodingService({http.Client? client}) : _client = client;

  final http.Client? _client;
  static const String _module = LogModule.app;

  /// Vyhledá GPS souřadnice pro zadaný textový název místa (např. „Olomouc“, „Chata Paprsek“, „Bouzov“).
  Future<GeocodingResult?> searchFirst(String query) async {
    final list = await search(query, count: 1);
    return list.isNotEmpty ? list.first : null;
  }

  /// Vyhledá až [count] možných shod pro daný dotaz.
  Future<List<GeocodingResult>> search(String query, {int count = 5}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final client = _client ?? http.Client();
    final uri = Uri.parse(
      'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(cleanQuery)}&count=$count&language=cs&format=json',
    );

    try {
      final response = await client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final parsed = results.whereType<Map>().map((m) {
            return GeocodingResult(
              name: m['name'] as String? ?? cleanQuery,
              latitude: (m['latitude'] as num).toDouble(),
              longitude: (m['longitude'] as num).toDouble(),
              country: m['country'] as String?,
              admin1: m['admin1'] as String?,
            );
          }).toList();

          AppLogger.I.info(_module, 'geocoding_success', metrics: {
            'query': cleanQuery,
            'found': parsed.length,
            'top_match': parsed.first.displayName,
          });
          return parsed;
        }
      }
      return const [];
    } catch (e, st) {
      AppLogger.I.warn(_module, 'geocoding_error', error: e, metrics: {'query': cleanQuery});
      AppLogger.I.error(_module, 'geocoding_exception', error: e, stackTrace: st);
      return const [];
    }
  }
}

