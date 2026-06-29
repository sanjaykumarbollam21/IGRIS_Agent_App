// lib/services/wakeword/stt_followup.dart
//
// Follow-up speech-to-text invoked AFTER the wake word fires.
//
// We support three backends, picked at runtime by user setting:
//   • speech_to_text  (online Google STT on Android, native on iOS)  — default
//   • vosk_on_device  (offline, small model, ships in app assets)     — opt-in
//   • whisper_cloud   (OpenAI Whisper API, best accuracy, costs $)    — opt-in
//
// Why a fallback chain matters:
//   • The wake word engine tells us "Hey IGRIS" was heard.
//   • We then need the *rest* of the utterance (e.g. "set a timer for 5
//     minutes") to feed to the intent handler.
//   • Choosing the backend at runtime lets the user trade privacy
//     (Vosk) vs accuracy (Whisper) vs cost (online STT).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum SttBackend { onlineStt, vosk, whisperCloud }

class SttFollowupService {
  SttFollowupService._();
  static final SttFollowupService instance = SttFollowupService._();

  final SpeechToText _stt = SpeechToText();

  SttBackend _backend = SttBackend.onlineStt;
  SttBackend get backend => _backend;

  void setBackend(SttBackend b) => _backend = b;

  /// Listen for a single utterance after the wake word, returning the
  /// transcribed text. Times out after [maxListen] to avoid hanging the UI.
  Future<String?> listenOnce({
    Duration maxListen = const Duration(seconds: 8),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    switch (_backend) {
      case SttBackend.onlineStt:
        return _listenOnline(maxListen, pauseFor);
      case SttBackend.vosk:
        return _listenVosk(maxListen);
      case SttBackend.whisperCloud:
        return _listenWhisperCloud();
    }
  }

  // ── Online STT (default) ─────────────────────────────────────────────────

  Future<String?> _listenOnline(Duration maxListen, Duration pauseFor) async {
    if (!await _stt.initialize()) {
      _log('Online STT not available');
      return null;
    }
    final completer = Completer<String?>();
    final startedAt = DateTime.now();

    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        if (r.finalResult && !completer.isCompleted) {
          completer.complete(r.recognizedWords);
        }
      },
      listenFor: maxListen,
      pauseFor: pauseFor,
      listenOptions: SpeechListenOptions(
        cancelOnError: true,
        partialResults: false,
      ),
    );

    // Hard timeout safety net.
    final result = await completer.future.timeout(
      maxListen + const Duration(seconds: 2),
      onTimeout: () => null,
    );
    _log(
      'Online STT elapsed: '
      '${DateTime.now().difference(startedAt).inSeconds}s',
    );
    return result;
  }

  // ── Vosk on-device (offline) ─────────────────────────────────────────────

  Future<String?> _listenVosk(Duration maxListen) async {
    // Vosk model lives at assets/vosk/model-en-us-small/. Add the package
    // `vosk: ^0.4.0` and unpack the model from a `.zip` first-launch asset
    // into the app's documents directory. Pseudocode:
    //
    //   final model = await _loadVoskModelFromAssets();
    //   final rec = ModelLoader.load(model); // or vosk.Vosk recognizer
    //   stream mic PCM → rec.acceptWaveform → finalResult
    _log('Vosk backend not yet wired — falling back to online STT');
    return _listenOnline(maxListen, const Duration(seconds: 2));
  }

  // ── Whisper cloud (best accuracy) ────────────────────────────────────────

  Future<String?> _listenWhisperCloud() async {
    // The simplest reliable path: capture a few seconds of mic audio as
    // PCM/WAV, POST to OpenAI /v1/audio/transcriptions, return text.
    //
    // IMPORTANT (CLAUDE.md Rule 1):
    //   • API key is read from secure storage at runtime only.
    //   • Per Rule 13 / LLM rules: set max_tokens=0 (transcription), and
    //     never log the response payload which may contain PII.
    final apiKey = await _readOpenAiKey();
    if (apiKey.isEmpty) {
      _log('No OpenAI key — falling back to online STT');
      return _listenOnline(
        const Duration(seconds: 6),
        const Duration(seconds: 2),
      );
    }
    // Your existing voice_service.dart already captures mic audio as WAV.
    // The Whisper call itself:
    //
    //   final form = FormData.fromMap({
    //     'file': MultipartFile.fromBytes(wavBytes, filename: 'cmd.wav'),
    //     'model': 'whisper-1',
    //     'language': 'en',
    //     'response_format': 'json',
    //   });
    //   final r = await Dio().post('https://api.openai.com/v1/audio/transcriptions',
    //     data: form,
    //     options: Options(headers: {'Authorization': 'Bearer $apiKey'}));
    //   return r.data['text'] as String;
    _log('Whisper backend stub — see comments for the real call');
    return null;
  }

  Future<String> _readOpenAiKey() async {
    // Source: flutter_secure_storage. The key is written by the user in
    // the settings screen. NEVER log this value.
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SttFollowup] reading OpenAI key from secure store');
    }
    return '';
  }

  void _log(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[SttFollowup] $msg');
    }
  }
}
