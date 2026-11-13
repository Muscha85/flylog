import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import '../../../core/logging/log_entry.dart';

/// Výsledek dotazu na počasí z Open-Meteo.
class WeatherInfo {
  const WeatherInfo({
    required this.temperatureC,
    required this.windSpeedMs,
    required this.weatherCode,
    required this.description,
  });

  final double temperatureC;
  final double windSpeedMs;
  final int weatherCode;
  final String description;

  /// Formátovaný popis s ikonou pro událost
  String toSummaryString() {
    return '$description, ${temperatureC.toStringAsFixed(1)} °C, vítr ${windSpeedMs.toStringAsFixed(1)} m/s';
  }

  static String codeToDescription(int code) {
    switch (code) {
      case 0:
        return '☀️ Jasno';
      case 1:
        return '🌤️ Převážně jasno';
      case 2:
        return '⛅ Polojasno';
      case 3:
        return '☁️ Zataženo';
      case 45:
      case 48:
        return '🌫️ Mlha';
      case 51:
      case 53:
      case 55:
        return '🌦️ Mrholení';
      case 61:
      case 63:
      case 65:
        return '🌧️ Déšť';
      case 71:
      case 73:
      case 75:
        return '🌨️ Sněžení';
      case 80:
      case 81:
      case 82:
        return '🌦️ Přeháňky';
      case 95:
      case 96:
      case 99:
        return '⛈️ Bouřka';
      default:
        return '⛅ Proměnlivo';
    }
  }
}

/// Služba pro získávání bezplatného počasí z Open-Meteo API bez nutnosti API klíče.
class WeatherService {
  const WeatherService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const String _module = LogModule.app;

  /// Získá počasí pro dané souřadnice a volitelné datum.
  /// Pokud je datum dnes nebo v budoucnosti, volá standardní předpovědní endpoint.
  /// Pokud je datum v minulosti, použije archive API.
  Future<WeatherInfo?> fetchWeather({
    required double latitude,
    required double longitude,
    DateTime? date,
  }) async {
    final client = _client ?? http.Client();
    final targetDate = date ?? DateTime.now();
    final now = DateTime.now();
    final isHistorical = targetDate.isBefore(DateTime(now.year, now.month, now.day));

    final dateStr =
        '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    final uri = isHistorical
        ? Uri.parse(
            'https://archive-api.open-meteo.com/v1/archive?latitude=$latitude&longitude=$longitude&start_date=$dateStr&end_date=$dateStr&daily=weathercode,temperature_2m_mean,windspeed_10m_max&timezone=auto',
          )
        : Uri.parse(
            'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&current=temperature_2m,wind_speed_10m,weather_code&timezone=auto',
          );

    try {
      final response = await client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (isHistorical) {
          final daily = data['daily'] as Map<String, dynamic>?;
          if (daily != null) {
            final temps = daily['temperature_2m_mean'] as List?;
            final winds = daily['windspeed_10m_max'] as List?;
            final codes = daily['weathercode'] as List?;

            final temp = temps != null && temps.isNotEmpty ? (temps[0] as num).toDouble() : 18.0;
            // km/h to m/s
            final windKmh = winds != null && winds.isNotEmpty ? (winds[0] as num).toDouble() : 10.0;
            final windMs = windKmh / 3.6;
            final code = codes != null && codes.isNotEmpty ? (codes[0] as num).toInt() : 0;

            final info = WeatherInfo(
              temperatureC: temp,
              windSpeedMs: windMs,
              weatherCode: code,
              description: WeatherInfo.codeToDescription(code),
            );

            AppLogger.I.info(_module, 'weather_fetched_history', metrics: {
              'lat': latitude,
              'lon': longitude,
              'date': dateStr,
              'temp': temp,
            });
            return info;
          }
        } else {
          final current = data['current'] as Map<String, dynamic>?;
          if (current != null) {
            final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 20.0;
            final windMs = (current['wind_speed_10m'] as num?)?.toDouble() ?? 2.5;
            final code = (current['weather_code'] as num?)?.toInt() ?? 0;

            final info = WeatherInfo(
              temperatureC: temp,
              windSpeedMs: windMs,
              weatherCode: code,
              description: WeatherInfo.codeToDescription(code),
            );

            AppLogger.I.info(_module, 'weather_fetched_current', metrics: {
              'lat': latitude,
              'lon': longitude,
              'temp': temp,
            });
            return info;
          }
        }
      }
      AppLogger.I.warn(_module, 'weather_fetch_failed', metrics: {
        'status': response.statusCode,
        'body': response.body,
      });
      return null;
    } catch (e, st) {
      AppLogger.I.warn(_module, 'weather_fetch_error', error: e, metrics: {
        'lat': latitude,
        'lon': longitude,
      });
      AppLogger.I.error(_module, 'weather_fetch_exception', error: e, stackTrace: st);
      return null;
    }
  }
}
