import 'dart:convert';
import 'dart:io';

class GeminiApiException implements Exception {
  final int? statusCode;
  final String message;

  GeminiApiException(this.message, {this.statusCode});

  @override
  String toString() => 'GeminiApiException($statusCode): $message';
}

class GeminiApiService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  static Future<List<String>> listGenerateModels(String apiKey) async {
    final client = HttpClient();

    try {
      final uri = Uri.parse('$_baseUrl/models?pageSize=100');
      final request = await client.getUrl(uri);
      request.headers.set('x-goog-api-key', apiKey);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeminiApiException(
          'List models failed: $responseBody',
          statusCode: response.statusCode,
        );
      }

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final models = (decoded['models'] as List? ?? []);

      final results = <String>[];
      for (final item in models) {
        if (item is! Map<String, dynamic>) continue;
        final name = item['name']?.toString();
        final methods =
            (item['supportedGenerationMethods'] as List? ?? []).cast<dynamic>();

        if (name != null && methods.contains('generateContent')) {
          results.add(name.replaceFirst('models/', ''));
        }
      }

      return results;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> resolveWorkingModel(String apiKey) async {
    final models = await listGenerateModels(apiKey);

    if (models.contains('gemini-2.5-flash')) return 'gemini-2.5-flash';
    if (models.contains('gemini-2.5-flash-lite')) return 'gemini-2.5-flash-lite';
    if (models.contains('gemini-2.5-pro')) return 'gemini-2.5-pro';
    if (models.contains('gemini-2.0-flash')) return 'gemini-2.0-flash';

    if (models.isNotEmpty) return models.first;

    throw GeminiApiException(
      'No supported Gemini text model found for this API key.',
    );
  }

  static Future<String?> generateText({
    required String apiKey,
    required String prompt,
    String model = 'gemini-2.5-flash',
    double temperature = 0.2,
    int maxOutputTokens = 128,
    String? responseMimeType,
  }) async {
    final client = HttpClient();

    try {
      final uri = Uri.parse('$_baseUrl/models/$model:generateContent');
      final request = await client.postUrl(uri);

      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set('x-goog-api-key', apiKey);

      request.write(jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': temperature,
          'maxOutputTokens': maxOutputTokens,
          if (responseMimeType != null) 'responseMimeType': responseMimeType,
        }
      }));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = responseBody;
        try {
          final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
          final error = decoded['error'] as Map<String, dynamic>?;
          if (error != null) {
            message = error['message']?.toString() ?? responseBody;
          }
        } catch (_) {}

        throw GeminiApiException(message, statusCode: response.statusCode);
      }

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;

      return parts.first['text']?.toString().trim();
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> validateApiKeyOrThrow(String apiKey) async {
    final model = await resolveWorkingModel(apiKey);

    final result = await generateText(
      apiKey: apiKey,
      model: model,
      prompt: 'Reply with exactly OK',
      temperature: 0,
      maxOutputTokens: 8,
    );

    if (result == null || result.trim().isEmpty) {
      throw GeminiApiException('The API returned an empty response.');
    }
  }
}