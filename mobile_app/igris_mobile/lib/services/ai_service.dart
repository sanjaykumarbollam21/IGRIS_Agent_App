import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:igris_mobile/services/configuration_service.dart';

/// IGRIS AI Service — Direct Gemini SDK integration for on-device AI features
class AiService {
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;
  AiService._internal();

  final _storage = const FlutterSecureStorage();

  // ── Get API key ────────────────────────────────────────────────────────────
  Future<String?> _getApiKey() async {
    // User's own key takes priority
    final userKey = await _storage.read(key: 'gemini_api_key');
    if (userKey != null && userKey.isNotEmpty) return userKey;
    return null; // Falls back to backend
  }

  Future<GenerativeModel?> _getModel(String modelName) async {
    final key = await _getApiKey();
    if (key == null) return null;
    return GenerativeModel(model: modelName, apiKey: key);
  }

  Future<String> chat(String message,
      {List<({String role, String text})> history = const [], String? sessionId}) async {
    try {
      final model = await _getModel('gemini-2.0-flash');
      if (model == null) {
        // No user key — fall back to backend
        return await _chatViaBackend(message, sessionId: sessionId);
      }

      final contents = [
        ...history.map((h) => Content(h.role, [TextPart(h.text)])),
        Content.text(message),
      ];

      final response = await model.generateContent(contents,
          generationConfig: GenerationConfig(maxOutputTokens: 2048));
      return response.text ?? 'No response from IGRIS.';
    } catch (e) {
      debugPrint('[AiService] chat() failed: $e');
      // Re-throw so callers that have their own fallback (e.g. busy-mode handler)
      // can catch and use their hardcoded fallback text.
      rethrow;
    }
  }

  // ── Analyze image ──────────────────────────────────────────────────────────
  Future<String> analyzeImage(Uint8List imageBytes, String prompt) async {
    final model = await _getModel('gemini-2.0-flash');
    if (model == null) return 'API key not configured. Go to Settings → API Keys.';

    final response = await model.generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ])
    ], generationConfig: GenerationConfig(maxOutputTokens: 1024));

    return response.text ?? 'Could not analyze image.';
  }

  // ── Generate Image — Multi-Provider (checks user's keys in priority order) ─
  Future<Map<String, dynamic>> generateImage({
    required String prompt,
    String aspectRatio = '1:1',
    String style = 'photorealistic',
  }) async {
    final styleMap = {
      'photorealistic': 'photorealistic, highly detailed, professional photography, realistic lighting',
      'anime':          'anime style, manga, vibrant colors, studio quality, cel shaded',
      'painting':       'oil painting, artistic brushstrokes, fine art, masterpiece, canvas texture',
      'digital_art':    'digital art, concept art, vibrant, highly detailed, artstation trending',
      'sketch':         'pencil sketch, hand-drawn, detailed linework, black and white, crosshatching',
    };
    final enhanced = '$prompt, ${styleMap[style] ?? styleMap['photorealistic']}';

    // Read user's stored keys
    final geminiKey     = (await _storage.read(key: 'gemini_api_key'))    ?? '';
    final hfToken       = (await _storage.read(key: 'hf_api_token'))      ?? '';
    final openAiKey     = (await _storage.read(key: 'openai_api_key'))    ?? '';
    final stabilityKey  = (await _storage.read(key: 'stability_api_key')) ?? '';

    // ── 0. Google Gemini Imagen 3 (free/paid depending on key, extremely high quality) ──
    if (geminiKey.isNotEmpty) {
      final r = await _generateGeminiImagen(enhanced, aspectRatio, geminiKey);
      if (r['success'] == true) return r;
    }

    // ── 1. HuggingFace FLUX.1-schnell (free, high quality) ──────────────────
    if (hfToken.isNotEmpty) {
      final r = await _generateHuggingFace(enhanced, aspectRatio, hfToken);
      if (r['success'] == true) return r;
      // Fall through if network unreachable (DNS block etc.) or auth error
    }

    // ── 2. OpenAI DALL-E 3 (paid, highest quality) ──────────────────────────
    if (openAiKey.isNotEmpty) {
      final r = await _generateDallE3(enhanced, aspectRatio, openAiKey);
      if (r['success'] == true) return r;
    }

    // ── 3. Stability AI SDXL 1.0 (paid) ────────────────────────────────────
    if (stabilityKey.isNotEmpty) {
      final r = await _generateStabilityAI(enhanced, aspectRatio, stabilityKey);
      if (r['success'] == true) return r;
    }

    // ── 4. Pollinations.ai (free, no signup, no key) ─────────────────────────
    final pollinationsResult = await _generatePollinations(enhanced, aspectRatio);
    if (pollinationsResult['success'] == true) return pollinationsResult;

    // ── 5. Stable Horde (completely free, no key, crowd-sourced GPUs) ─────────
    return await _generateStableHorde(enhanced, aspectRatio);
  }


  // ── Provider: Pollinations.ai (free, default model) ──────────────────────
  Future<Map<String, dynamic>> _generatePollinations(String prompt, String ratio) async {
    try {
      final sizeMap = {
        '1:1':  {'w': 1024, 'h': 1024},
        '16:9': {'w': 1280, 'h': 720},
        '9:16': {'w': 720,  'h': 1280},
        '4:3':  {'w': 1024, 'h': 768},
        '3:4':  {'w': 768,  'h': 1024},
      };
      final size = sizeMap[ratio] ?? sizeMap['1:1']!;
      final safe = prompt.length > 200 ? prompt.substring(0, 200) : prompt;
      final seed = DateTime.now().millisecondsSinceEpoch % 999999;

      // Note: Omit model=turbo to avoid 402 Payment Required; uses the free default model
      final url = Uri.parse(
        'https://image.pollinations.ai/prompt/${Uri.encodeComponent(safe)}'
        '?width=${size['w']}&height=${size['h']}&seed=$seed&nologo=true',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        'Accept':     'image/webp,image/apng,image/*,*/*;q=0.8',
      }).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return {'success': true, 'imageData': base64Encode(response.bodyBytes),
                'mimeType': 'image/jpeg', 'prompt': prompt, 'provider': 'Pollinations.ai'};
      }
      return {'success': false, 'error': 'Pollinations ${response.statusCode}'};
    } catch (_) {
      return {'success': false, 'error': 'Pollinations unreachable'};
    }
  }

  // ── Provider: Google Gemini Imagen 3 ──────────────────────────────────────
  Future<Map<String, dynamic>> _generateGeminiImagen(String prompt, String ratio, String key) async {
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict?key=$key',
      );

      final ratioMap = {
        '1:1': '1:1',
        '16:9': '16:9',
        '9:16': '9:16',
        '4:3': '4:3',
        '3:4': '3:4',
      };
      final geminiRatio = ratioMap[ratio] ?? '1:1';

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'instances': [
            {'prompt': prompt}
          ],
          'parameters': {
            'sampleCount': 1,
            'aspectRatio': geminiRatio,
            'outputMimeType': 'image/jpeg',
          }
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final images = (data['generatedImages'] ?? data['generated_images']) as List?;
        if (images != null && images.isNotEmpty) {
          final imageObj = images[0] as Map;
          final img = imageObj['image'] as Map?;
          final imageBytesB64 = ((img?['imageBytes'] ?? img?['image_bytes']) ?? imageObj['imageBytes'] ?? imageObj['image_bytes']) as String?;
          if (imageBytesB64 != null) {
            return {
              'success': true,
              'imageData': imageBytesB64,
              'mimeType': 'image/jpeg',
              'prompt': prompt,
              'provider': 'Google Gemini Imagen 3',
            };
          }
        }
      }
      return {'success': false, 'error': 'Gemini Imagen error (${response.statusCode}): ${response.body}'};
    } catch (e) {
      return {'success': false, 'error': 'Gemini Imagen failed: $e'};
    }
  }

  // ── Provider: HuggingFace FLUX.1-schnell ──────────────────────────────────
  Future<Map<String, dynamic>> _generateHuggingFace(String prompt, String ratio, String token) async {
    try {
      final sizeMap = {
        '1:1': [1024, 1024], '16:9': [1280, 720], '9:16': [720, 1280],
        '4:3': [1024, 768],  '3:4':  [768, 1024],
      };
      final size = sizeMap[ratio] ?? [1024, 1024];

      final resp = await http.post(
        Uri.parse('https://api-inference.huggingface.co/models/black-forest-labs/FLUX.1-schnell'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'inputs': prompt,
          'parameters': {'width': size[0], 'height': size[1], 'num_inference_steps': 4},
        }),
      ).timeout(const Duration(seconds: 90));

      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        final b64 = base64Encode(resp.bodyBytes);
        return {'success': true, 'imageData': b64, 'mimeType': 'image/jpeg',
                'prompt': prompt, 'provider': 'HuggingFace FLUX.1-schnell'};
      }
      // Model loading (503) → retry once after delay
      if (resp.statusCode == 503) {
        await Future.delayed(const Duration(seconds: 20));
        final retry = await http.post(
          Uri.parse('https://api-inference.huggingface.co/models/black-forest-labs/FLUX.1-schnell'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'inputs': prompt, 'parameters': {'width': size[0], 'height': size[1]}}),
        ).timeout(const Duration(seconds: 90));
        if (retry.statusCode == 200 && retry.bodyBytes.isNotEmpty) {
          return {'success': true, 'imageData': base64Encode(retry.bodyBytes),
                  'mimeType': 'image/jpeg', 'prompt': prompt, 'provider': 'HuggingFace FLUX.1-schnell'};
        }
      }
      return {'success': false, 'error': 'HuggingFace error (${resp.statusCode}). Check your HF token.'};
    } catch (e) {
      return {'success': false, 'error': 'HuggingFace failed: $e'};
    }
  }

  // ── Provider: OpenAI DALL-E 3 ─────────────────────────────────────────────
  Future<Map<String, dynamic>> _generateDallE3(String prompt, String ratio, String key) async {
    try {
      final sizeMap = {'1:1': '1024x1024', '16:9': '1792x1024', '9:16': '1024x1792'};
      final size = sizeMap[ratio] ?? '1024x1024';

      final resp = await http.post(
        Uri.parse('https://api.openai.com/v1/images/generations'),
        headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'dall-e-3',
          'prompt': prompt,
          'n': 1,
          'size': size,
          'quality': 'standard',
          'response_format': 'b64_json',
        }),
      ).timeout(const Duration(seconds: 90));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final b64 = data['data']?[0]?['b64_json'] as String?;
        if (b64 != null) {
          return {'success': true, 'imageData': b64, 'mimeType': 'image/png',
                  'prompt': prompt, 'provider': 'OpenAI DALL-E 3'};
        }
      }
      final err = jsonDecode(resp.body);
      return {'success': false, 'error': 'DALL-E 3: ${err['error']?['message'] ?? resp.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': 'DALL-E 3 failed: $e'};
    }
  }

  // ── Provider: Stability AI SDXL 1.0 ──────────────────────────────────────
  Future<Map<String, dynamic>> _generateStabilityAI(String prompt, String ratio, String key) async {
    try {
      final sizeMap = {
        '1:1': [1024, 1024], '16:9': [1344, 768], '9:16': [768, 1344],
        '4:3': [1152, 896],  '3:4':  [896, 1152],
      };
      final size = sizeMap[ratio] ?? [1024, 1024];

      final resp = await http.post(
        Uri.parse('https://api.stability.ai/v1/generation/stable-diffusion-xl-1024-v1-0/text-to-image'),
        headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'text_prompts': [{'text': prompt, 'weight': 1}],
          'cfg_scale': 7, 'height': size[1], 'width': size[0],
          'steps': 30, 'samples': 1,
        }),
      ).timeout(const Duration(seconds: 90));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final b64 = data['artifacts']?[0]?['base64'] as String?;
        if (b64 != null) {
          return {'success': true, 'imageData': b64, 'mimeType': 'image/png',
                  'prompt': prompt, 'provider': 'Stability AI SDXL'};
        }
      }
      return {'success': false, 'error': 'Stability AI error (${resp.statusCode}).'};
    } catch (e) {
      return {'success': false, 'error': 'Stability AI failed: $e'};
    }
  }

  // ── Provider: Stable Horde (anonymous, crowd-sourced, free) ───────────────
  Future<Map<String, dynamic>> _generateStableHorde(String prompt, String ratio) async {
    try {
      final sizeMap = {
        '1:1': [512, 512], '16:9': [768, 448], '9:16': [448, 768],
        '4:3': [640, 512],  '3:4': [512, 640],
      };
      final size = sizeMap[ratio] ?? [512, 512];

      final submitResp = await http.post(
        Uri.parse('https://stablehorde.net/api/v2/generate/async'),
        headers: {'Content-Type': 'application/json', 'apikey': '0000000000'},
        body: jsonEncode({
          'prompt': prompt,
          'params': {
            'width': size[0], 'height': size[1],
            'steps': 20, 'n': 1, 'sampler_name': 'k_euler', 'cfg_scale': 7.5,
          },
          'r2': true, 'shared': false, 'models': ['stable_diffusion'],
        }),
      ).timeout(const Duration(seconds: 30));

      if (submitResp.statusCode != 202) {
        return {'success': false, 'error': 'Stable Horde unavailable. Add a HuggingFace token in Settings → API Keys for reliable free image generation.'};
      }
      final jobId = jsonDecode(submitResp.body)['id'] as String;

      // Poll up to 90 seconds
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 3));
        final check = jsonDecode(
          (await http.get(Uri.parse('https://stablehorde.net/api/v2/generate/check/$jobId'),
              headers: {'apikey': '0000000000'}).timeout(const Duration(seconds: 10))).body,
        ) as Map<String, dynamic>;

        if (check['done'] == true) {
          final status = jsonDecode(
            (await http.get(Uri.parse('https://stablehorde.net/api/v2/generate/status/$jobId'),
                headers: {'apikey': '0000000000'}).timeout(const Duration(seconds: 30))).body,
          ) as Map<String, dynamic>;

          final imgUrl = (status['generations'] as List?)?.firstOrNull?['img'] as String?;
          if (imgUrl != null) {
            final imgResp = await http.get(Uri.parse(imgUrl)).timeout(const Duration(seconds: 30));
            if (imgResp.statusCode == 200 && imgResp.bodyBytes.isNotEmpty) {
              return {'success': true, 'imageData': base64Encode(imgResp.bodyBytes),
                      'mimeType': 'image/webp', 'prompt': prompt, 'provider': 'Stable Horde'};
            }
          }
          return {'success': false, 'error': 'No image returned. Try again.'};
        }
      }
      return {'success': false, 'error': 'Timed out (90s). Add a HuggingFace token in Settings → API Keys for faster generation.'};
    } catch (e) {
      return {'success': false, 'error': 'Image generation failed: $e'};
    }
  }

  // ── Web search via backend ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> webSearch(String query) async {
    try {
      final baseUrl = ConfigurationService().backendUrl;
      final token = await _storage.read(key: 'auth_token');
      if (token == null) return {'success': false, 'error': 'Not authenticated'};

      final apiKey = await _getApiKey();
      final resp = await http.post(
        Uri.parse('$baseUrl/tools/web-search'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          if (apiKey != null) 'X-Gemini-API-Key': apiKey,
        },
        body: jsonEncode({'query': query}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        return {'success': true, ...jsonDecode(resp.body) as Map<String, dynamic>};
      }
      return {'success': false, 'error': 'Search failed ${resp.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ── Transcribe audio ───────────────────────────────────────────────────────
  Future<String> transcribeAudio(Uint8List audioBytes, {String mimeType = 'audio/m4a'}) async {
    final model = await _getModel('gemini-2.0-flash');
    if (model == null) return 'API key not configured.';

    final response = await model.generateContent([
      Content.multi([
        TextPart('Transcribe the following audio accurately. Return only the transcription text.'),
        DataPart(mimeType, audioBytes),
      ])
    ], generationConfig: GenerationConfig(maxOutputTokens: 2048));

    return response.text ?? 'Could not transcribe audio.';
  }

  // ── Fallback: route through backend ───────────────────────────────────────
  Future<String> _chatViaBackend(String message, {String? sessionId}) async {
    try {
      final baseUrl = ConfigurationService().backendUrl;
      final token = await _storage.read(key: 'auth_token');
      if (token == null) throw Exception('Not authenticated');

      final apiKey = await _getApiKey();
      final resp = await http.post(
        Uri.parse('$baseUrl/ai/chat'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          if (apiKey != null) 'X-Gemini-API-Key': apiKey,
        },
        body: jsonEncode({
          'message': message,
          if (sessionId != null) 'sessionId': sessionId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['response'] ?? 'No response.';
      }

      // 503 = no Gemini API key on the server. Throw so that callers
      // (e.g. the busy-mode notification handler) fall through to their
      // own hardcoded fallback instead of surfacing this error as the
      // reply text sent to the caller.
      if (resp.statusCode == 503) {
        throw Exception('AI service unavailable (no server key). '
            'Add a Gemini API key in Settings → API Keys.');
      }

      throw Exception('Backend error (${resp.statusCode})');
    } catch (e) {
      debugPrint('[AiService] _chatViaBackend failed: $e');
      rethrow; // Let AiService.chat() catch block handle it
    }
  }

  // ── Session History ─────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getSessions() async {
    try {
      final baseUrl = ConfigurationService().backendUrl;
      final token = await _storage.read(key: 'auth_token');
      final resp = await http.get(
        Uri.parse('$baseUrl/conversations/sessions'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return List<Map<String, dynamic>>.from(data['sessions'] ?? []);
      }
      return [];
    } catch (_) { return []; }
  }

  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId) async {
    try {
      final baseUrl = ConfigurationService().backendUrl;
      final token = await _storage.read(key: 'auth_token');
      final resp = await http.get(
        Uri.parse('$baseUrl/conversations/sessions/$sessionId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      }
      return [];
    } catch (_) { return []; }
  }

  Future<bool> deleteSession(String sessionId) async {
    try {
      final baseUrl = ConfigurationService().backendUrl;
      final token = await _storage.read(key: 'auth_token');
      final resp = await http.delete(
        Uri.parse('$baseUrl/conversations/sessions/$sessionId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }
}
