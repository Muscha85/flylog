import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import '../logging/log_entry.dart';

/// Režim AI průvodce.
enum AiMode {
  /// Lokální generátor – funguje bez sítě a bez API klíče.
  mock('Offline (mock)'),

  /// Skutečné volání Google Gemini API (vyžaduje API klíč).
  gemini('Google Gemini');

  const AiMode(this.label);
  final String label;
}

/// Datové úložiště kroniky.
enum StorageBackend {
  /// In-memory data + persistence do SharedPreferences (JSON). Výchozí.
  local('Lokální zařízení'),

  /// Připraveno pro budoucí `FirestoreChronicleRepository`.
  firestore('Firebase Firestore (připravujeme)');

  const StorageBackend(this.label);
  final String label;

  bool get isAvailable => this == StorageBackend.local;
}

/// Správa konfigurace aplikace a citlivých klíčů.
///
/// Konfigurace se ukládá do [SharedPreferences]. Gemini API klíč lze zadat
/// v obrazovce Nastavení, případně předat při buildu:
/// `flutter build apk --dart-define=GEMINI_API_KEY=...`.
class AppConfig extends ChangeNotifier {
  AppConfig._internal();

  static final AppConfig instance = AppConfig._internal();

  static const String appName = 'FlyLog';
  static const String appVersion = '0.1.0';
  static const String webPublishDomain = 'vylety.muchovi.com';
  static const String defaultGeminiModel = 'gemini-3.8-flash';

  /// Klíč dodaný při buildu (`--dart-define=GEMINI_API_KEY=...`).
  static const String _buildTimeApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const String _kApiKey = 'config.gemini_api_key';
  static const String _kModel = 'config.gemini_model';
  static const String _kAiMode = 'config.ai_mode';
  static const String _kTheme = 'config.theme_mode';
  static const String _kBackend = 'config.storage_backend';
  static const String _kFamily = 'config.family_name';

  SharedPreferences? _prefs;
  bool _loaded = false;

  String _geminiApiKey = '';
  String _geminiModel = defaultGeminiModel;
  AiMode _aiMode = AiMode.mock;
  ThemeMode _themeMode = ThemeMode.system;
  StorageBackend _storageBackend = StorageBackend.local;
  String _familyName = 'Muchovi';

  bool get isLoaded => _loaded;

  /// Efektivní API klíč – uživatelský má přednost před build-time klíčem.
  String get geminiApiKey => _geminiApiKey.isNotEmpty ? _geminiApiKey : _buildTimeApiKey;

  /// Klíč uložený uživatelem (bez build-time fallbacku) – pro editační pole.
  String get storedGeminiApiKey => _geminiApiKey;

  bool get hasGeminiKey => geminiApiKey.trim().isNotEmpty;

  String get geminiModel => _geminiModel;
  AiMode get aiMode => _aiMode;
  ThemeMode get themeMode => _themeMode;
  StorageBackend get storageBackend => _storageBackend;
  String get familyName => _familyName;

  /// Zda se má skutečně volat Gemini API.
  bool get useRealAi => _aiMode == AiMode.gemini && hasGeminiKey;

  /// Maskovaný klíč pro zobrazení / logy (nikdy nelogujeme celý klíč).
  String get maskedApiKey {
    final key = geminiApiKey;
    if (key.isEmpty) return '—';
    if (key.length <= 8) return '••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  Future<void> load() async {
    final sw = Stopwatch()..start();
    try {
      _prefs = await SharedPreferences.getInstance();
      final p = _prefs!;
      _geminiApiKey = p.getString(_kApiKey) ?? '';
      _geminiModel = p.getString(_kModel) ?? defaultGeminiModel;
      _aiMode = _enumByName(AiMode.values, p.getString(_kAiMode), AiMode.mock);
      _themeMode = _enumByName(ThemeMode.values, p.getString(_kTheme), ThemeMode.system);
      _storageBackend = _enumByName(StorageBackend.values, p.getString(_kBackend), StorageBackend.local);
      if (!_storageBackend.isAvailable) _storageBackend = StorageBackend.local;
      _familyName = p.getString(_kFamily) ?? 'Muchovi';
      _loaded = true;
      AppLogger.I.info(LogModule.config, 'config_loaded', metrics: {
        'duration_ms': sw.elapsedMilliseconds,
        'ai_mode': _aiMode.name,
        'has_api_key': hasGeminiKey,
        'storage': _storageBackend.name,
      });
    } catch (e, st) {
      AppLogger.I.error(LogModule.config, 'config_load_failed', error: e, stackTrace: st);
      _loaded = true;
    }
    notifyListeners();
  }

  Future<void> setGeminiApiKey(String value) async {
    _geminiApiKey = value.trim();
    await _prefs?.setString(_kApiKey, _geminiApiKey);
    if (_geminiApiKey.isNotEmpty && _aiMode == AiMode.mock) {
      // Uživatel zadal klíč – rovnou přepneme na skutečné AI.
      _aiMode = AiMode.gemini;
      await _prefs?.setString(_kAiMode, _aiMode.name);
    }
    AppLogger.I.info(LogModule.config, 'api_key_updated', metrics: {
      'has_api_key': hasGeminiKey,
      'key_masked': maskedApiKey,
      'ai_mode': _aiMode.name,
    });
    notifyListeners();
  }

  Future<void> setGeminiModel(String value) async {
    final v = value.trim();
    _geminiModel = v.isEmpty ? defaultGeminiModel : v;
    await _prefs?.setString(_kModel, _geminiModel);
    AppLogger.I.info(LogModule.config, 'gemini_model_updated', metrics: {'model': _geminiModel});
    notifyListeners();
  }

  Future<void> setAiMode(AiMode mode) async {
    _aiMode = mode;
    await _prefs?.setString(_kAiMode, mode.name);
    AppLogger.I.info(LogModule.config, 'ai_mode_changed', metrics: {
      'ai_mode': mode.name,
      'has_api_key': hasGeminiKey,
    });
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs?.setString(_kTheme, mode.name);
    AppLogger.I.info(LogModule.config, 'theme_changed', metrics: {'theme': mode.name});
    notifyListeners();
  }

  Future<void> setStorageBackend(StorageBackend backend) async {
    if (!backend.isAvailable) {
      AppLogger.I.warn(LogModule.config, 'storage_backend_unavailable', metrics: {'requested': backend.name});
      return;
    }
    _storageBackend = backend;
    await _prefs?.setString(_kBackend, backend.name);
    notifyListeners();
  }

  Future<void> setFamilyName(String value) async {
    _familyName = value.trim().isEmpty ? 'Muchovi' : value.trim();
    await _prefs?.setString(_kFamily, _familyName);
    notifyListeners();
  }

  /// Kontext pro AI log export (bez citlivých údajů).
  Map<String, String> diagnosticContext() => {
        'app_version': appVersion,
        'ai_mode': _aiMode.name,
        'ai_model': _geminiModel,
        'has_api_key': hasGeminiKey.toString(),
        'storage_backend': _storageBackend.name,
        'theme_mode': _themeMode.name,
      };

  static T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}

