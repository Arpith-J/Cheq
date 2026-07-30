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
  static const String _defaultModel = 'gemini-3.6-flash';

  static Future<String?> generateText({
    required String apiKey,
    required String prompt,
    String model = _defaultModel,
    double temperature = 0.2,
    int maxOutputTokens = 128,
    String? responseMimeType,
  }) async {
    final client = HttpClient();

    try {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');
      final request = await client.postUrl(uri);

      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

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
    } on SocketException catch (e) {
      throw GeminiApiException('Network error: ${e.message}');
    } on HttpException catch (e) {
      throw GeminiApiException('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      throw GeminiApiException('Response parse error: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

}
