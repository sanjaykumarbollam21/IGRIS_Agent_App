# Wake Word Model — "Hey IGRIS"

This directory holds the on-device wake word model. The native Kotlin engine
in `android/app/src/main/kotlin/.../wakeword/` loads a TFLite model from
`assets/wake_word/hey_igris.tflite` and runs it on 16 kHz mono PCM frames
(80 ms each, 12.5 inferences/second).

## Do I need to do anything?

**Yes — the model is not committed to the repo.** It's a binary trained
from your own voice samples, so it has to be generated per-deployment.
The settings screen will show a "Setup incomplete" banner with a "No
model found" message until you drop a `.tflite` here.

## How to generate the model

The fastest path is the bundled training script:

```bash
# 1. Set up a fresh venv (so we don't pollute your main Python env)
python3 -m venv .venv-wakeword
source .venv-wakeword/bin/activate        # Linux / macOS
# or:  .venv-wakeword\Scripts\activate   # Windows

# 2. Install training deps (~5 min, pulls TensorFlow)
pip install -r tools/requirements-wakeword.txt

# 3. Quick start: synthesise ~10 positive clips via gTTS and train
#    a stub model. Verifies the pipeline works end-to-end.
python3 tools/train_wake_word.py --synth-positives
```

For a **production-quality model**, you need your own recordings:

```bash
# 1. Record yourself saying "Hey IGRIS" 200+ times.
#    Vary your tone, distance from mic, and background noise.
#    Each recording should be 1-3 seconds, mono, 16 kHz WAV.
#    Put them in a directory, e.g. data/hey_igris_positives/.

# 2. (Recommended) Record 5-10 other speakers saying the same phrase,
#    for accent robustness. Add them to the same directory.

# 3. Train. This typically takes 30-90 minutes on a laptop GPU,
#    or 4-6 hours on CPU. Use --epochs 50 for a tighter model.
python3 tools/train_wake_word.py \
    --positive-clips-dir data/hey_igris_positives \
    --output assets/wake_word/hey_igris.tflite \
    --epochs 50
```

The script will:
1. Run openWakeWord's training loop with the openWakeWord bundled
   negative-clip dataset (~30 hours of speech, noise, music, TV).
2. Export the trained model to ONNX.
3. Convert ONNX → TensorFlow SavedModel → TFLite with
   `tf.lite.Optimize.DEFAULT` (weight quantisation).
4. Drop the result in `assets/wake_word/hey_igris.tflite` (typically
   50-200 KB) and a sidecar `hey_igris.tflite.json` with metadata.

## Model format

The TFLite model must satisfy:
- **Input shape**: `[1, 1280]` float32 (raw 16 kHz PCM, 80 ms frame)
- **Output shape**: `[1, N]` float32
  - index 0 = positive class ("hey_igris")
  - index 1..N-1 = negative / spotter classes (for false-positive rejection)
- **Sample rate**: 16 000 Hz
- **Encoding**: 16-bit signed little-endian PCM (the Kotlin engine
  reads this and converts to float32 in `[-1, 1]`)

## Why a sidecar `.json`?

The Kotlin engine reads tensor shapes from the model itself, so the
JSON isn't strictly required at runtime. It's there as a sanity check
during deployment — if you re-train with a different frame size or
class count, the JSON will catch a mismatch before it ships.

## How the app uses it

```
Microphone (16 kHz, mono, 16-bit PCM)
   │
   ▼
WakeWordService.start()  ── copies assets/wake_word/hey_igris.tflite
   │                        to cacheDir/ on first launch (one-time cost)
   ▼
WakeWordEngine.processFrame()  ── 80 ms per call
   │
   ▼
TFLite Interpreter.run()  ── runs on XNNPACK (CPU, low power)
   │
   ▼
DetectionThrottler  ── debounce 3 frames + 2 s cooldown
   │
   ▼
EventChannel emit → Dart: WakeWordActions._onDetection()
   │
   ▼
VoiceService.processWakeWordTrigger()
```

## Verifying after install

In the app:
1. Settings → Voice Agent → Wake Word.
2. The "Setup incomplete" banner should be gone.
3. Tap "Run 3s self-test", say "Hey IGRIS" out loud.
4. You should see: "✅ Self-test PASS — wake word model is hearing you".
5. If you see "⚠️ Self-test did NOT detect", try the "High sensitivity"
   profile, move closer to the mic, or re-train with more epochs.

## License

The `hey_igris.tflite` you generate is yours to ship. openWakeWord
and TensorFlow are Apache 2.0; no API keys, no per-device licensing,
no cloud dependency.
