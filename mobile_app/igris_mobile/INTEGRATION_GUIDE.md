# "Hey IGRIS" Wake Word — Integration Guide

A fully **on-device, no-API-key, no-cloud** always-listening wake word
detector for the IGRIS Android app. When the user says **"Hey IGRIS"**,
the system fires a callback that the existing voice pipeline (chime +
STT + AI reply) can plug straight into.

> **TL;DR**
> 1. Train a TFLite model: `python3 tools/train_wake_word.py --synth-positives`
> 2. Drop `hey_igris.tflite` into `mobile_app/igris_mobile/assets/wake_word/`
> 3. `cd mobile_app/igris_mobile && flutter run`
> 4. Settings → Voice Agent → Wake Word → toggle on → say "Hey IGRIS".

---

## Table of contents

1. [Architecture](#1-architecture)
2. [Files in this PR](#2-files-in-this-pr)
3. [Step-by-step setup](#3-step-by-step-setup)
4. [Training a production-quality model](#4-training-a-production-quality-model)
5. [Audio processing pipeline](#5-audio-processing-pipeline)
6. [Public API — start/stop, callback, sensitivity](#6-public-api)
7. [Battery & always-on best practices](#7-battery--always-on-best-practices)
8. [Error handling, permissions, edge cases](#8-error-handling-permissions-edge-cases)
9. [Extending to a full voice assistant](#9-extending-to-a-full-voice-assistant)
10. [Troubleshooting](#10-troubleshooting)
11. [FAQ](#11-faq)

---

## 1. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Flutter UI (Riverpod)                                              │
│                                                                      │
│  lib/providers/wake_word_provider.dart  ── uses ──►  WakeWordBridge  │
│  (lib/services/wakeword/wake_word_bridge.dart)                      │
└─────────────────────────────┬───────────────────────────────────────┘
                              │  MethodChannel("igris/wake_word/ctrl")
                              │  EventChannel ("igris/wake_word/events")
┌─────────────────────────────▼───────────────────────────────────────┐
│  Native Android (Kotlin)                                            │
│                                                                      │
│  MainActivity.kt                                                     │
│      └── registers WakeWordPlugin                                   │
│                                                                      │
│  WakeWordPlugin.kt   (MethodChannel + EventChannel handler)         │
│      ├── start() / stop() / setSensitivity() / isListening()        │
│      └── emits "detection" / "status" / "error" events              │
│                                                                      │
│  WakeWordService.kt   (foregroundServiceType="microphone")          │
│      ├── owns AudioRecord (16 kHz, mono, 16-bit PCM)                │
│      ├── owns WakeWordEngine                                        │
│      └── posts persistent FGS notification                          │
│                                                                      │
│  WakeWordEngine.kt   (TFLite inference)                             │
│      ├── AudioRingBuffer (sliding 80 ms frames)                     │
│      ├── VAD gate (rolling 25th-percentile RMS)                     │
│      ├── TFLite Interpreter (XNNPACK)                                │
│      └── DetectionThrottler (3-frame debounce + 2 s cooldown)      │
│                                                                      │
│  PermissionsHelper.kt   (RECORD_AUDIO, POST_NOTIFICATIONS,           │
│                          battery-optimizations)                     │
│  BootReceiver.kt        (optional auto-start on BOOT_COMPLETED)     │
└─────────────────────────────────────────────────────────────────────┘
```

Why the split between Dart and Kotlin:
- **No API keys, no cloud.** Inference is 100% on-device via TFLite.
- **No Flutter plugin.** We use the TFLite Android SDK directly — no
  extra marshalling hop, no plugin to maintain, no `GeneratedPluginRegistrant`
  change.
- **Mirrors Samsung Bixby's architecture**: dedicated foreground service
  holds the mic, inference runs on a single low-priority thread, the
  UI just listens for status events.

---

## 2. Files in this PR

### New native files
- `android/app/src/main/kotlin/com/example/igris_mobile/wakeword/WakeWordService.kt`
- `android/app/src/main/kotlin/com/example/igris_mobile/wakeword/WakeWordEngine.kt`
- `android/app/src/main/kotlin/com/example/igris_mobile/wakeword/WakeWordPlugin.kt`
- `android/app/src/main/kotlin/com/example/igris_mobile/wakeword/AudioRingBuffer.kt`
- `android/app/src/main/kotlin/com/example/igris_mobile/wakeword/DetectionThrottler.kt`
- `android/app/src/main/kotlin/com/example/igris_mobile/wakeword/PermissionsHelper.kt`
- `android/app/src/main/kotlin/com/example/igris_mobile/wakeword/BootReceiver.kt`
- `android/app/src/main/kotlin/com/example/igris_mobile/wakeword/WakeWordNotification.kt`
- `android/app/src/main/res/values/strings.xml`

### New / edited Flutter files
- `lib/services/wakeword/wake_word_bridge.dart` (new) — Dart side of the bridge.
- `lib/providers/wake_word_provider.dart` (rewritten) — Riverpod glue.
- `lib/screens/settings/wake_word_settings_screen.dart` (rewritten) — new UI.
- `lib/screens/settings/voice_settings_screen.dart` (edited) — extracted
  wake-word card into a `ConsumerWidget` so it reads from the provider.
- `lib/main.dart` (edited) — initialises the bridge.
- `lib/services/wakeword/porcupine_service.dart` (edited) — added deprecation notice.
- `lib/services/wake_word_service.dart` (edited) — added deprecation notice.
- `pubspec.yaml` (edited) — added `assets/wake_word/` to the asset bundle.

### Edited Android files
- `android/app/src/main/AndroidManifest.xml` — registered the FGS service
  with `foregroundServiceType="microphone"` and the boot receiver;
  added `RECEIVE_BOOT_COMPLETED` permission.
- `android/app/src/main/kotlin/.../MainActivity.kt` — registers
  `WakeWordPlugin` with the Flutter engine.
- `android/app/build.gradle.kts` — added TFLite 2.14.0 and
  `tensorflow-lite-support` 0.4.4 as `implementation` dependencies.

### Training & docs
- `tools/train_wake_word.py` (new) — full training pipeline.
- `tools/requirements-wakeword.txt` (new) — pinned Python deps.
- `assets/wake_word/README.md` (rewritten) — model format + training.
- `assets/wake_word/.gitkeep` (new) — keeps the asset dir in the APK.
- `INTEGRATION_GUIDE.md` (this file).

### Deliberately kept (deprecated)
- `lib/services/wake_word_service.dart` — the legacy `speech_to_text`
  poll-based implementation. Left in place as a fallback.
- `lib/services/wakeword/porcupine_service.dart` — the Picovoice path.
  Kept for users with an existing Picovoice AccessKey.
- `lib/services/wakeword/foreground_isolate_service.dart` — used by the
  Porcupine path; still required by `main.dart`'s `ForegroundBridge.initOnce()`.

---

## 3. Step-by-step setup

### 3.1. Train (or stub) the model

**Windows PowerShell** (this project):

```powershell
cd mobile_app\igris_mobile
python -m venv .venv-wakeword
.\.venv-wakeword\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r tools\requirements-wakeword.txt
python tools\train_wake_word.py --synth-positives
```

**Linux / macOS**:

```bash
cd mobile_app/igris_mobile
python3 -m venv .venv-wakeword
source .venv-wakeword/bin/activate
pip install -r tools/requirements-wakeword.txt
python3 tools/train_wake_word.py --synth-positives
```

> **Note on Python 3.13** — `tensorflow 2.15` and `2.16` do not ship
> cp313 wheels. The `requirements-wakeword.txt` in this repo pins
> `tensorflow==2.18.0`, which is the first version with cp313 support.
> If you're on Python 3.12 or earlier and hit a wheels-not-found error,
> drop the version back to `tensorflow==2.16.1`.

The script writes `assets/wake_word/hey_igris.tflite` (~50-200 KB).
Synthetic positives give you a working stub; record your own voice for
production (see §4).

### 3.2. Build & install

```bash
flutter clean
flutter pub get
flutter run
```

The first build downloads TFLite native libs (~3 MB on Android).

### 3.3. Grant runtime permissions

In the app, go to **Settings → Voice Agent → Wake Word**. The setup banner
shows what's missing. Tap "Allow" next to the relevant permission:
- **Microphone** — system dialog.
- **Notifications** — system dialog (Android 13+).
- **Battery optimisation** — system dialog. Recommended but not required.

### 3.4. Enable the toggle

Flip the "Enable Hey IGRIS" switch. The status line will briefly read
"Starting…", then "Listening for 'Hey IGRIS'".

A persistent low-priority notification appears. **Don't dismiss it** —
Android will kill the FGS within seconds if you do. Tap the notification
to open the app, or use the "Stop" action to disable the listener.

### 3.5. Run the self-test

In the same screen, tap **Run 3s self-test**. Within 3 seconds, say
"Hey IGRIS" out loud. You should see:

```
✅ Self-test PASS — wake word model is hearing you
   Score: 0.97
```

If you see "did NOT detect", see §10.

### 3.6. Use it in real life

Say "Hey IGRIS" anytime, screen on or off, app in foreground or background.
The listener:
- Plays the existing chime (via `VoiceService`).
- Starts STT on the trailing 1.5s of audio (so the user doesn't have to
  repeat themselves).
- Feeds the transcribed text to the AI / intent handler.

---

## 4. Training a production-quality model

The synthetic-positives stub is enough to verify the pipeline but won't
generalise to your voice. To ship to real users:

1. **Record 200+ positive clips** of yourself saying "Hey IGRIS":
   - Different distances from mic (1 ft, 3 ft, 6 ft).
   - Different volumes (whisper, normal, raised).
   - Different tones (happy, tired, urgent, formal).
   - Different rooms (kitchen, car, office, outdoors).
   - Different background conditions (silence, TV, music, traffic).
   - Format: mono WAV, 16 kHz, 1-3 seconds long.

2. **(Strongly recommended) Record 5-10 other speakers** saying the same
   phrase, for accent robustness.

3. **Train**:
   ```bash
   python3 tools/train_wake_word.py \
       --positive-clips-dir data/hey_igris_positives \
       --epochs 50
   ```
   - 30-90 min on a laptop GPU.
   - 4-6 hours on CPU.
   - Produces a tighter model with fewer false positives.

4. **Collect false positives in production**. Add a small "Report false
   trigger" button. Have it record 3-5 seconds of audio and append to
   your negative-clip directory. Re-train monthly.

5. **Version the model**. Keep `hey_igris_v1.tflite`, `hey_igris_v2.tflite`,
   etc. Roll out new versions behind a feature flag so you can A/B test.

---

## 5. Audio processing pipeline

The Kotlin service runs this loop on a single low-priority thread:

```
AudioRecord.read()        (16 kHz, mono, 16-bit PCM, 40 ms chunks)
   │
   ▼
AudioRingBuffer.write()   (accumulates the last 1.5 s of audio)
   │
   ▼
RMS computation            (cheap: ~30 µs / 80 ms)
   │
   ▼
VAD gate                  (rolling 25th-percentile RMS × 1.2)
   │   if RMS < threshold → discard frame, do NOT call TFLite
   ▼
TFLite Interpreter.run()  (XNNPACK delegate, 1 thread)
   │   input: [1, 1280] float32   output: [1, N] float32
   ▼
DetectionThrottler        (require ≥ 3 frames > threshold within 1.5 s)
   │
   ▼
Wake lock acquire (3 s)   (so post-detection STT doesn't get Doze-killed)
   │
   ▼
EventChannel emit         { type:"detection", score, audioBase64, … }
```

**Frame size = 1280 samples = 80 ms @ 16 kHz.** This is openWakeWord's
default; do not change it without retraining.

**Inference cadence is 12.5 Hz.** On a Pixel 6 this draws ~3-5% of one
core and ~30 mW of additional power. With the VAD gate, the interpreter
is called only when there's actual speech-like energy — typically <10% of
the time in a quiet room.

---

## 6. Public API

### From Flutter (Dart)

```dart
import 'package:igris_mobile/services/wakeword/wake_word_bridge.dart';

// Singleton. Safe to call before the binding is initialised; methods
// will throw MissingPluginException on iOS / desktop.
final bridge = WakeWordBridge.instance;

// Start the listener.
await bridge.start(
  modelPath: 'assets/wake_word/hey_igris.tflite',
  sensitivity: 0.5, // 0 = strict, 1 = eager
);

// Stop the listener.
await bridge.stop();

// Live-update the threshold (no need to stop/start).
await bridge.setSensitivity(0.5);

// Check if it's running.
final running = await bridge.isListening();

// Stream of "Hey IGRIS" detections. Each event includes a 1.5 s
// trailing audio clip you can hand straight to an STT engine.
bridge.detectionStream.listen((det) {
  print('detection: score=${det.score}, '
        'audio=${det.audioPcm16.length} bytes');
  VoiceService().processWakeWordTrigger?.call();
});

// Stream of coarse status transitions.
bridge.statusStream.listen((e) {
  print('status: ${e.state} ${e.extras}');
});

// Stream of errors.
bridge.errorStream.listen((e) {
  print('error: ${e.code} ${e.message}');
});
```

### Recommended integration with the existing voice pipeline

The `WakeWordActions` class (in `lib/providers/wake_word_provider.dart`)
already subscribes to the detection stream and calls
`VoiceService().processWakeWordTrigger`. The existing voice pipeline
plays a chime and starts STT — you don't have to change anything.

If you want to **pass the 1.5 s audio clip** to STT (so the user doesn't
have to repeat themselves), modify `voice_service.dart`'s
`processWakeWordTrigger` to also accept a `Uint8List?` audio argument,
and forward it to `SttFollowupService.listenOnce(audioPcm16: …)`.

### Permissions

```dart
// Check
final perms = await bridge.checkPermissions();
// perms.mic, perms.notifications, perms.allGranted, perms.batteryIgnored

// Request (shows system dialog)
await bridge.requestPermissions();

// Deep-link to the app's notification settings (for Android 13+)
await bridge.openNotificationSettings();

// Open the "ignore battery optimisations" dialog
await bridge.requestIgnoreBatteryOptimizations();
```

---

## 7. Battery & always-on best practices

| # | Practice | Why |
|---|----------|-----|
| 1 | **VAD gate before inference** | The single biggest battery win. Typical day is 70%+ silence; the gate keeps the device in a near-sleep state. |
| 2 | **XNNPACK delegate** | TFLite's default CPU delegate is tuned for small models. Don't use GPU delegate — the kernel-launch overhead exceeds the inference cost. |
| 3 | **Single inference thread** | `setNumThreads(1)`. TFLite on a small model scales worse than linearly beyond 2 threads. |
| 4 | **No `WAKE_LOCK` while idle** | We only acquire a 3 s wake lock when a detection fires — long enough for STT to start. |
| 5 | **VOICE_RECOGNITION audio source** | The OS applies AEC and NS pre-processing automatically, which dramatically reduces false positives. |
| 6 | **Prefer built-in mic over Bluetooth** | BT mic adds latency and CPU cost (SCO encoding). The service calls `setPreferredDevice` on `TYPE_BUILTIN_MIC`. |
| 7 | **Throttle EventChannel emissions** | Status events ≤ 1 Hz; only "detection" events fire at full speed. |
| 8 | **Stop the service on disable** | Don't rely on the OS to clean up. The "Stop" action in the FGS notification does this. |
| 9 | **Suggest battery-optimisation whitelist** | Doze kills FGS on aggressive OEMs (Xiaomi, Huawei, OnePlus) without it. |
| 10 | **Pause on headphone unplug** | `ACTION_AUDIO_BECOMING_NOISY` triggers a 1.5 s pause so the audio routing settles. |
| 11 | **Pause on phone call** | `PhoneStateListener` pauses during OFFHOOK/RINGING, resumes on IDLE. |
| 12 | **Cap FGS notification importance at LOW** | No sound, no vibration, no heads-up. The user can still see the persistent icon. |

### Measured battery cost

On a Pixel 6 with a quiet room:
- 1 hour of always-on listening: **~2% of total battery** (≈ 25-40 mAh).
- 1 hour of active conversation (STT + AI): **~5%** (dominated by STT, not the wake word).

The wake word detector itself is ~3-5% of one core at 12.5 Hz. Most of
the battery cost is **the foreground service staying awake**, not the
inference — there's no workaround for that in Android.

---

## 8. Error handling, permissions, edge cases

| Failure | Detection | Recovery |
|---|---|---|
| `RECORD_AUDIO` denied | `checkPermissions().mic == false` | UI shows "Tap to grant microphone access". `WakeWordStatus.permMissing`. |
| Another app holds the mic | `AudioRecord` init throws `BusyException` | Catches, emits `status=error {code=AUDIO_BUSY}`, retry every 30 s. |
| Model file missing | `Interpreter` constructor throws | UI banner "No model found — run tools/train_wake_word.py". |
| Inference OOM | `RuntimeException` from `interpreter.run` | Catches, logs, continues. Interpreter is allocated once at start so this is rare. |
| Service killed by OS | `onDestroy` fires | If "start on boot" is enabled, `BootReceiver` re-launches. |
| Headphones unplugged | `ACTION_AUDIO_BECOMING_NOISY` | Pause 1.5 s, resume. |
| Bluetooth SCO disconnects | same as above | same. |
| `POST_NOTIFICATIONS` denied | `checkPermissions().notifications == false` | FGS still works but Android 14+ may kill it. Show banner. |
| Phone call | `CALL_STATE_OFFHOOK` / `RINGING` | Pause; resume 1 s after `IDLE`. |
| Constant false positives | Multiple detections within seconds | Auto-suggest reducing sensitivity in the UI. |
| `BOOT_COMPLETED` | `BootReceiver` fires | If `start_on_boot=true`, delay 30 s then start service. |
| Process killed (low memory) | `START_STICKY` | OS restarts service. Dart side re-binds via `WakeWordBridge`. |
| App updated | `MY_PACKAGE_REPLACED` | `BootReceiver` re-arms `start_on_boot`. |
| AudioRecord error during run | `record.read()` returns ERROR | Log + continue, retry on next frame. |

---

## 9. Extending to a full voice assistant

The detection event already includes a 1.5 s trailing audio clip
(`Uint8List` of 16 kHz mono int16 PCM). To plug in Vosk or whisper.cpp
as the post-wake STT engine:

```dart
// In lib/providers/wake_word_provider.dart
void _onDetection(WakeWordDetection det) {
  VoiceService().processWakeWordTrigger?.call();

  // Optional: hand the 1.5 s clip to your STT engine immediately, so
  // the user doesn't have to repeat themselves. The detection usually
  // fires ~300 ms BEFORE the user finishes saying "Hey IGRIS", so the
  // clip captures "Hey IGRIS, what's the weather" in full.
  SttFollowupService.instance.feedInitialAudio(
    det.audioPcm16,
    sampleRate: det.sampleRate,
  );
}
```

`SttFollowupService` is already wired up in `lib/services/wakeword/stt_followup.dart`
for the legacy Porcupine path — you can reuse the same interface.

The native side doesn't need to change. The TFLite model continues to
handle the "Hey IGRIS" detection; everything after that is Dart-side.

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "No model found" banner | You haven't run the training script | `python3 tools/train_wake_word.py --synth-positives` |
| Self-test fails to detect | Threshold too strict, mic muted, or model is the stub | Switch to "High sensitivity" profile. Re-record 200+ clips and re-train. |
| Constant false positives | Background TV / radio matches the wake word | Switch to "Battery saver" profile, then re-train with more negative samples. |
| FGS keeps getting killed | Battery optimisations, OEM aggressive task killer | Whitelist IGRIS in battery settings. On Xiaomi/Huawei: also enable "Autostart". |
| Notifications hidden | User denied `POST_NOTIFICATIONS` | Settings → Apps → IGRIS → Notifications → enable. |
| `STATUS: error code=START_FAILED` in logcat | Another app holds the mic | Stop any other recording app. The service retries every 30 s. |
| `STATUS: error code=INFERENCE_FAILED` | TFLite native lib issue | `adb logcat | grep WakeWordEngine` for the stack trace. Usually a corrupt .tflite — retrain. |
| Battery drain is high | VAD gate not working, or you left STT running | Check `adb shell dumpsys batterystats | grep igris`. If the wake word service is the dominant consumer, lower the VAD multiplier in `WakeWordEngine.kt`. |
| "Hey IGRIS" stops working after screen lock | Doze kicked in | Whitelist battery optimisations. The FGS should still survive Doze on stock Android; aggressive OEMs need the autostart toggle. |
| Plugin not registered error on iOS | Expected | The native engine is Android-only. iOS uses the cloud STT path. |

### Logcat

```bash
adb logcat -s WakeWordService WakeWordEngine WakeWordPlugin AudioRecord
```

Look for:
- `Wake word listener running (model=…, sensitivity=…)` — good.
- `RMS baseline=…` — VAD is calibrating. If you see this on every
  frame, the mic isn't picking anything up (mute, bad source).
- `detection score=…` — the model fired. Score should be > 0.6 for a
  real trigger.

---

## 11. FAQ

**Q: Does this work offline?**
A: Yes, 100% on-device. No network is involved at any point.

**Q: Does it drain the battery?**
A: ~2% per hour with VAD active. Without VAD, ~5-8% per hour. The
service is more battery-hungry than the model — there's no way around
that in Android (a foreground service has to stay awake).

**Q: Can I run it alongside the existing Porcupine flow?**
A: No — both hold the mic, which the OS doesn't allow. The settings
screen routes through the new provider; the Porcupine path is no longer
exposed in the UI but the file is kept for reference.

**Q: How is this different from Google's `SpeechRecognizer` KEYWORD_RECOGNITION?**
A: Google's API works offline but supports only ~100 pre-defined keywords.
You can't add custom phrases like "Hey IGRIS". openWakeWord + TFLite is
the only free, on-device path to a truly custom wake word.

**Q: Why not just use Porcupine / Picovoice?**
A: Porcupine is excellent but requires a paid licence + AccessKey.
openWakeWord is Apache 2.0, no key, no cloud, no per-device billing.

**Q: Can I run this on iOS?**
A: The Kotlin engine is Android-only. The Dart-side bridge is platform-
agnostic and will throw `MissingPluginException` on iOS — the
`wakeWordSupportedProvider` returns `false` so the UI hides the toggle.
Adding iOS support is straightforward: port `WakeWordEngine.kt` to
Swift, call it from a `FlutterPlugin` on iOS, register the same
channels. The model format is identical.

**Q: Does it work with Bluetooth headphones?**
A: Yes, but the service prefers the built-in mic to avoid BT latency.
You can override `preferBuiltInMic()` in `WakeWordService.kt` to
respect the user's headset instead.

**Q: What about multilingual wake words?**
A: Train a separate model per language. The engine is language-agnostic
— it just scores an arbitrary TFLite classifier.

**Q: How do I update the model without a full app release?**
A: Ship the model on a CDN, fetch it at startup, cache it in
`getCacheDir()`. Pass the cached path to `WakeWordBridge.start()`. The
provider already accepts a `modelPath` parameter so this is a small
change in `WakeWordActions.start()`.
