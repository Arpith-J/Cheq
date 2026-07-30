import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AiCategorizer {
  static String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(RegExp(r'\s+')).map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  static String _sanitize(String? raw) {
    if (raw == null) return '';
    return raw
        .replaceAll('**', '')
        .replaceAll('*', '')
        .replaceAll('_', '')
        .replaceAll('`', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\t', ' ')
        .trim();
  }

  static Future<String?> categorize({
    required String taskTitle,
    required List<String> availableCategories,
    required String apiKey,
  }) async {
    try {
      final prompt = '''
You are an intelligent task categorizer for a daily planner app.

Task to categorize: "$taskTitle"
User's existing categories: ${availableCategories.isEmpty ? "None" : availableCategories.join(', ')}

INSTRUCTIONS:
1. Try to map the task to one of the user's "Existing Categories" if it makes logical sense (e.g., map "Study" to "Academics" if "Academics" exists).
2. If no existing category fits, invent a new, broad, single-word category (e.g., Work, Health, Errands, Finance, Home, Social).
3. Output EXACTLY ONE WORD. No quotes, no markdown, no punctuation, no explanations.
''';

      final response = await _generateText(apiKey, prompt);

      debugPrint('🤖 AI CATEGORIZER — RAW RESPONSE: "${response}"');

      final sanitized = _sanitize(response);
      final titled = _toTitleCase(sanitized);

      debugPrint('🤖 AI CATEGORIZER — SANITIZED + TITLE CASED: "$titled"');

      if (titled.isNotEmpty &&
          titled.toLowerCase() != 'none' &&
          titled.toLowerCase() != 'null') {
        return titled;
      }

      return 'Miscellaneous';
    } catch (e) {
      debugPrint('⚠️ AI Categorizer Failed: $e');
      return 'Miscellaneous';
    }
  }

  static Future<String?> _generateText(String apiKey, String prompt) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$apiKey');
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
          'temperature': 0.1,
          'maxOutputTokens': 500,
          'responseMimeType': 'text/plain',
        }
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      debugPrint('🚨 GOOGLE RAW JSON: $body');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = body;
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final error = decoded['error'] as Map<String, dynamic>?;
          if (error != null) {
            message = error['message']?.toString() ?? body;
          }
        } catch (_) {}
        debugPrint('⚠️ AI Generation Error ($response.statusCode): $message');
        return null;
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;

      return parts.first['text']?.toString().trim();
    } on SocketException catch (e) {
      debugPrint('⚠️ AI Network Error: ${e.message}');
      return null;
    } on HttpException catch (e) {
      debugPrint('⚠️ AI HTTP Error: ${e.message}');
      return null;
    } on FormatException catch (e) {
      debugPrint('⚠️ AI Parse Error: ${e.message}');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
