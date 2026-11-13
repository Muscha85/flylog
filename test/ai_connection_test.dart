import 'package:flutter_test/flutter_test.dart';
import 'package:flylog/core/config/app_config.dart';
import 'package:flylog/features/ai_companion/services/ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AiService.testConnection succeeds with configured default Gemini key and models', () async {
    final aiService = AiService();
    final result = await aiService.testConnection(
      modelOverride: 'gemini-flash-lite-latest',
      apiKeyOverride: AppConfig.defaultGeminiApiKey,
      timeout: const Duration(seconds: 15),
    );

    // Musí vrátit pozitivní potvrzení spojení
    expect(result.contains('Spojení OK') || result.contains('Spojení aktivní'), isTrue);
    expect(result.contains('Chyba'), isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

