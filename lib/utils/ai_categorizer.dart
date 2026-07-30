import 'package:flutter/foundation.dart';
import '../services/gemini_api_service.dart';

class AiCategorizer {
  static Future<String?> categorize({
    required String taskTitle,
    required List<String> availableCategories,
    required String apiKey,
  }) async {
    try {
      final prompt = '''
Analyze this task: "$taskTitle"

Available categories: ${availableCategories.isEmpty ? "None" : availableCategories.join(', ')}

Choose the single best category.

Rules:
- Return exactly ONE short category name.
- Prefer an existing category if it fits.
- If none fit, create a simple new category like Work, Home, Fitness, Finance, Study, Travel.
- Output only the category name.
- No punctuation, no quotes, no explanation.
''';

      final model = await GeminiApiService.resolveWorkingModel(apiKey);
      final response = await GeminiApiService.generateText(
        apiKey: apiKey,
        model: model  ,
        prompt: prompt,
        temperature: 0.1,
        maxOutputTokens: 10,
      );

      final result = response
          ?.replaceAll('`', '')
          .replaceAll('"', '')
          .replaceAll("'", '')
          .trim();

      if (result != null &&
          result.isNotEmpty &&
          result.toLowerCase() != 'none') {
        return result;
      }

      return 'None';
    } catch (e) {
      debugPrint('⚠️ AI Categorizer Failed: $e');
      return null;
    }
  }
}