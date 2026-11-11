import '../../features/ai_companion/services/ai_service.dart';
import '../../features/chronicle/services/chronicle_repository.dart';
import '../../features/chronicle/services/mock_chronicle_repository.dart';
import '../../features/media_vault/services/media_service.dart';
import '../../features/web_publisher/services/static_html_builder.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../logging/log_entry.dart';

/// Minimalistický service locator – jediné místo, kde se rozhoduje,
/// která implementace služeb se použije.
///
/// Přechod na Firebase: v [init] podle `AppConfig.storageBackend`
/// vytvořit `FirestoreChronicleRepository` místo [MockChronicleRepository].
abstract final class ServiceLocator {
  static ChronicleRepository? _chronicle;
  static MediaService? _media;
  static AiService? _ai;
  static StaticHtmlBuilder? _html;

  static ChronicleRepository get chronicle => _chronicle ?? (throw StateError('ServiceLocator.init() nebyl zavolán'));
  static MediaService get media => _media ??= MediaService();
  static AiService get ai => _ai ??= AiService();
  static StaticHtmlBuilder get html => _html ??= const StaticHtmlBuilder();

  static Future<void> init({ChronicleRepository? chronicleOverride}) async {
    final sw = Stopwatch()..start();
    final config = AppConfig.instance;

    _chronicle = chronicleOverride ?? _createRepository(config.storageBackend);
    await _chronicle!.init();

    AppLogger.I.info(LogModule.app, 'services_ready', metrics: {
      'chronicle_backend': _chronicle!.backendName,
      'ai_mode': config.aiMode.name,
      'duration_ms': sw.elapsedMilliseconds,
    });
  }

  static ChronicleRepository _createRepository(StorageBackend backend) {
    switch (backend) {
      case StorageBackend.local:
        return MockChronicleRepository();
      case StorageBackend.firestore:
        // Firestore zatím není nakonfigurován – bezpečný fallback na lokální úložiště.
        AppLogger.I.warn(LogModule.app, 'firestore_not_configured_fallback_local');
        return MockChronicleRepository();
    }
  }
}

