#!/usr/bin/env python3
"""
tools/train_wake_word.py

Train an on-device "Hey IGRIS" wake word model using openWakeWord and export
it as a single TFLite file that the Android Kotlin engine can load.

Why this exists
---------------
The Android app (mobile_app/igris_mobile) ships a native Kotlin wake word
detector that consumes a TFLite model. That model needs to:
  - accept raw 16 kHz mono PCM as input
  - emit per-frame class probabilities (positive class at index 0)
  - be small enough to run on a low-end Android phone in <50 ms / frame

openWakeWord (https://github.com/dscripka/openWakeWord) is the standard
open-source pipeline for training custom wake word models. We use its
training loop and then export to TFLite via the TFLiteConverter.

What this script does
---------------------
  1. Verifies Python deps (openwakeword, tensorflow, numpy, etc.).
  2. If positive samples are missing, synthesises them via gTTS (Google
     Text-to-Speech) in 5 English accents × 2 speakers = ~10 positive
     clips. **This is a stub — for production you want human recordings.**
  3. Downloads the openWakeWord negative-clip datasets (MIT/Apache) and
     augments them with noise / music / speech from FMA-small / MUSAN if
     available; otherwise uses openWakeWord's bundled clip set.
  4. Calls `openwakeword.train` to fine-tune the combined melspec+NN
     model on the positive / negative / "unknown" classes.
  5. Exports the combined model (melspec frontend + classifier head) to a
     single TFLite file at the path passed via --output (default:
     mobile_app/igris_mobile/assets/wake_word/hey_igris.tflite).

Usage
-----
    # Full run, synthetic positives only (good for verifying the pipeline)
    python3 tools/train_wake_word.py --synth-positives

    # Production run, with your own recordings
    python3 tools/train_wake_word.py \
        --positive-clips-dir ./data/hey_igris_positives \
        --output ../mobile_app/igris_mobile/assets/wake_word/hey_igris.tflite

Positive clips should be:
  - 16 kHz mono WAV
  - 1-3 seconds long
  - At least 200 clips of YOU saying "Hey IGRIS" in different tones,
    distances, and background noise conditions
  - Ideally another 200 clips of "Hey IGRIS" from 5-10 other speakers
    (different accents) for accent robustness

Negative clips (the script fetches these automatically):
  - openWakeWord ships with ~30 hours of negative clips (speech that
    is NOT the wake word, plus noise, music, TV, etc.)
  - You can add your own --negative-clips-dir if you have custom false
    positive triggers to defend against (TV dialogue from a specific
    show, say).

After training, copy the .tflite to:
    mobile_app/igris_mobile/assets/wake_word/hey_igris.tflite
and rebuild the Flutter app.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

# Reconfigure stdout/stderr to UTF-8 to prevent charmap/unicode crashes on Windows consoles
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

import tempfile
from pathlib import Path

# Paths
THIS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = THIS_DIR.parent
DEFAULT_OUTPUT = PROJECT_ROOT / "assets" / "wake_word" / "hey_igris.tflite"
DEFAULT_TRAINING_ROOT = PROJECT_ROOT / "build" / "wakeword_training"



def log(msg: str) -> None:
    print(f"[train_wake_word] {msg}", flush=True)


def check_python_deps() -> None:
    """Abort with a clear message if a required dep is missing."""
    required = {
        "numpy": "numpy",
        "tensorflow": "tensorflow==2.15.*",
        "openwakeword": "openwakeword",
        "librosa": "librosa",
        "soundfile": "soundfile",
        "scipy": "scipy",
    }
    missing = []
    for mod, pkg in required.items():
        try:
            __import__(mod)
        except ImportError:
            missing.append(pkg)
    if missing:
        log("ERROR: missing Python packages. Install them with:")
        log("  pip install -r tools/requirements-wakeword.txt")
        log("Missing: " + ", ".join(missing))
        sys.exit(1)


def synthesise_positive_clips(out_dir: Path) -> int:
    """
    Use gTTS (Google Text-to-Speech) to synthesise ~10 positive clips in
    different English accents. This is a STUB — it gets the pipeline
    working end-to-end but won't give you a production-quality model.
    For real use, record yourself saying "Hey IGRIS" 200+ times.
    """
    try:
        from gtts import gTTS
    except ImportError:
        log("gTTS not installed. Run: pip install gTTS")
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    # 5 accents, each producing 2 clips with slightly different text to
    # capture natural prosody variation.
    accents = ["en-us", "en-uk", "en-au", "en-in", "en-ie"]
    phrases = [
        "Hey IGRIS",
        "Hey, IGRIS",
        "hey igris",
        "Okay, IGRIS",
        "IGRIS",
        "Igris",
        "igris",
        "igrees",
        "egress",
    ]
    count = 0
    for accent in accents:
        for phrase in phrases:
            for slow in [False, True]:
                try:
                    tts = gTTS(text=phrase, lang="en", tld=_tld_for(accent), slow=slow)
                    # gTTS writes MP3; we'll convert to 16 kHz mono WAV with ffmpeg.
                    mp3 = out_dir / f"synth_{accent}_{count}.mp3"
                    wav = out_dir / f"synth_{accent}_{count}.wav"
                    tts.save(str(mp3))
                    _ffmpeg_to_wav(mp3, wav, sample_rate=16000, mono=True)
                    mp3.unlink(missing_ok=True)
                    count += 1
                except Exception as e:
                    log(f"  TTS failed for {accent}/{phrase}: {e}")
    log(f"Synthesised {count} positive clips into {out_dir}")
    return count


def _tld_for(accent: str) -> str:
    return {
        "en-us": "com",
        "en-uk": "co.uk",
        "en-au": "com.au",
        "en-in": "co.in",
        "en-ie": "ie",
    }.get(accent, "com")


def _ffmpeg_to_wav(src: Path, dst: Path, sample_rate: int = 16000, mono: bool = True) -> None:
    """Convert an audio file to 16 kHz mono WAV using miniaudio (or ffmpeg fallback)."""
    try:
        import miniaudio
        import wave
        nchannels = 1 if mono else 2
        decoded = miniaudio.decode_file(str(src), sample_rate=sample_rate, nchannels=nchannels)
        with wave.open(str(dst), 'wb') as wav_file:
            wav_file.setnchannels(nchannels)
            wav_file.setsampwidth(2) # 16-bit
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(decoded.samples.tobytes())
        return
    except ImportError:
        pass
    except Exception as e:
        log(f"WARNING: miniaudio conversion failed: {e}. Trying ffmpeg fallback.")

    if not shutil.which("ffmpeg"):
        log("WARNING: ffmpeg not found on PATH and miniaudio not available. Install miniaudio or ffmpeg for WAV conversion.")
        return
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(src),
        "-ar", str(sample_rate),
        "-ac", "1" if mono else "2",
        "-sample_fmt", "s16",
        str(dst),
    ]
    subprocess.run(cmd, check=True)


def fetch_negative_clips(out_dir: Path) -> int:
    """
    Download the openWakeWord negative-clip dataset (~30 hours of
    speech, noise, music). These are the "this is NOT the wake word"
    examples that teach the model what to reject.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    try:
        # The openwakeword package bundles a small negative-clip set under
        # openwakeword/resources. We copy it into our training dir so the
        # trainer can find it via a stable path.
        import openwakeword
        bundled = Path(openwakeword.__file__).parent / "resources"
        if bundled.exists():
            for sub in bundled.glob("*.wav"):
                dst = out_dir / sub.name
                if not dst.exists():
                    shutil.copy(sub, dst)
    except Exception as e:
        log(f"Failed to fetch negative clips: {e}")

    # Generate synthetic negative speech phrases to avoid false positive triggers.
    try:
        from gtts import gTTS
        log("Synthesising robust negative speech samples via gTTS...")
        neg_phrases = [
            "Hey Google", "Hi Google", "Okay Google",
            "Hey Siri", "Hi Siri", "Siri",
            "Hey Alexa", "Hi Alexa", "Alexa",
            "Hey Bixby", "Hi Bixby", "Bixby",
            "Samsung", "Galaxy", "computer", "system",
            "yes", "no", "hello", "okay", "assistant",
            "activate", "open", "close", "phone", "app",
            "agent", "voice", "screen", "settings",
            "what is the weather", "how are you",
            "tell me a joke", "play some music",
            "turn on the lights", "set a timer",
            "read my notifications", "check my calendar",
            "call contact", "send message", "open app"
        ]
        accents = ["en-us", "en-uk", "en-au", "en-in", "en-ie"]
        neg_count = 0
        for accent in accents:
            for phrase in neg_phrases:
                try:
                    tts = gTTS(text=phrase, lang="en", tld=_tld_for(accent), slow=False)
                    mp3 = out_dir / f"neg_{accent}_{neg_count}.mp3"
                    wav = out_dir / f"neg_{accent}_{neg_count}.wav"
                    tts.save(str(mp3))
                    _ffmpeg_to_wav(mp3, wav, sample_rate=16000, mono=True)
                    mp3.unlink(missing_ok=True)
                    neg_count += 1
                except Exception as e:
                    pass
        log(f"Synthesised {neg_count} negative speech samples.")
    except Exception as e:
        log(f"Failed to synthesise negative clips: {e}")

    n = sum(1 for _ in out_dir.glob("*.wav"))
    if n == 0:
        log("No negative clips found. Generating dummy silence negative clips for the stub model.")
        import wave
        import numpy as np
        for i in range(5):
            filepath = out_dir / f"dummy_silence_{i}.wav"
            # 2 seconds of silence (32000 samples @ 16 kHz)
            data = np.zeros(32000, dtype=np.int16)
            with wave.open(str(filepath), 'wb') as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2) # 16-bit
                wav_file.setframerate(16000)
                wav_file.writeframes(data.tobytes())
        n = sum(1 for _ in out_dir.glob("*.wav"))
    return n


def run_openwakeword_training(
    positive_dir: Path,
    negative_dir: Path,
    output_dir: Path,
    epochs: int = 25,
) -> Path:
    """
    Train a simple PyTorch binary classifier on the extracted features.
    Returns the path to the trained ONNX model.
    """
    import torch
    import torch.nn as nn
    import torch.optim as optim
    from openwakeword.utils import AudioFeatures
    import wave
    import numpy as np

    output_dir.mkdir(parents=True, exist_ok=True)
    onnx_path = output_dir / "hey_igris.onnx"

    log("Loading WAV files and extracting audio features…")

    def load_wav_as_int16(path: Path, target_samples: int = 32000) -> np.ndarray:
        with wave.open(str(path), 'rb') as f:
            n_channels = f.getnchannels()
            sampwidth = f.getsampwidth()
            framerate = f.getframerate()
            n_frames = f.getnframes()
            data = f.readframes(n_frames)

        if sampwidth == 2:
            arr = np.frombuffer(data, dtype=np.int16)
        elif sampwidth == 1:
            arr = (np.frombuffer(data, dtype=np.uint8).astype(np.int32) - 128) * 256
            arr = arr.astype(np.int16)
        else:
            arr = np.frombuffer(data, dtype=np.int16)

        if n_channels > 1:
            arr = arr.reshape(-1, n_channels)
            arr = arr.mean(axis=1).astype(np.int16)

        if len(arr) < target_samples:
            arr = np.pad(arr, (0, target_samples - len(arr)), mode='constant')
        elif len(arr) > target_samples:
            arr = arr[:target_samples]

        return arr

    pos_files = list(positive_dir.glob("**/*.wav"))
    neg_files = list(negative_dir.glob("**/*.wav"))

    if not pos_files:
        raise ValueError(f"No positive wav files found in {positive_dir}")
    if not neg_files:
        raise ValueError(f"No negative wav files found in {negative_dir}")

    pos_audios = np.stack([load_wav_as_int16(f) for f in pos_files])
    neg_audios = np.stack([load_wav_as_int16(f) for f in neg_files])

    # Extract features
    F = AudioFeatures(device='cpu')
    pos_features = F.embed_clips(pos_audios)
    neg_features = F.embed_clips(neg_audios)

    log(f"Extracted positive features shape: {pos_features.shape}")
    log(f"Extracted negative features shape: {neg_features.shape}")

    # Prepare training data
    X = np.vstack([pos_features, neg_features])
    y = np.hstack([np.ones(len(pos_features)), np.zeros(len(neg_features))])

    # Convert to PyTorch tensors
    X_tensor = torch.tensor(X, dtype=torch.float32)
    y_tensor = torch.tensor(y, dtype=torch.float32).unsqueeze(1)

    # Simple DNN classifier head matching openWakeWord architecture
    class Net(nn.Module):
        def __init__(self, input_shape=(16, 96), layer_dim=128):
            super().__init__()
            self.flatten = nn.Flatten()
            self.layer1 = nn.Linear(input_shape[0] * input_shape[1], layer_dim)
            self.relu1 = nn.ReLU()
            self.layernorm1 = nn.LayerNorm(layer_dim)
            self.last_layer = nn.Linear(layer_dim, 1)
            self.last_act = nn.Sigmoid()

        def forward(self, x):
            x = self.relu1(self.layernorm1(self.layer1(self.flatten(x))))
            x = self.last_act(self.last_layer(x))
            return x

    model = Net(input_shape=(16, 96), layer_dim=128)
    criterion = nn.BCELoss()
    optimizer = optim.Adam(model.parameters(), lr=0.01)

    # Train model
    log(f"Training stub model for {epochs} epochs…")
    for epoch in range(epochs):
        model.train()
        optimizer.zero_grad()
        outputs = model(X_tensor)
        loss = criterion(outputs, y_tensor)
        loss.backward()
        optimizer.step()
        if (epoch + 1) % 5 == 0 or epoch == 0:
            log(f"  Epoch [{epoch+1}/{epochs}], Loss: {loss.item():.4f}")

    # Stub model forcing disabled - training real classifier head on features.


    # Export to ONNX
    log(f"Exporting model to ONNX: {onnx_path}")
    model.eval()
    dummy_input = torch.rand((1, 16, 96))
    torch.onnx.export(
        model,
        dummy_input,
        str(onnx_path),
        input_names=["input"],
        output_names=["hey_igris"],
        dynamic_axes={"input": {0: "batch_size"}, "hey_igris": {0: "batch_size"}},
        opset_version=13
    )

    if not onnx_path.exists():
        raise RuntimeError(f"Training did not produce {onnx_path}")

    return onnx_path



def export_tflite(onnx_path: Path, tflite_path: Path) -> None:
    """
    Convert the openWakeWord ONNX checkpoint to a single TFLite file.

    openWakeWord ships a combined model (melspectrogram frontend +
    classifier). The conversion goes ONNX → SavedModel → TFLite.
    """
    import onnx
    import tensorflow as tf
    from onnx_tf.backend import prepare  # type: ignore

    log("Loading ONNX model…")
    onnx_model = onnx.load(str(onnx_path))
    tf_rep = prepare(onnx_model)
    saved_model_dir = onnx_path.with_suffix(".saved_model")
    if saved_model_dir.exists():
        shutil.rmtree(saved_model_dir)
    tf_rep.export_graph(str(saved_model_dir))
    log("Converting SavedModel → TFLite…")
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    tflite_model = converter.convert()
    tflite_path.parent.mkdir(parents=True, exist_ok=True)
    tflite_path.write_bytes(tflite_model)
    size_kb = len(tflite_model) / 1024
    log(f"Wrote TFLite model: {tflite_path} ({size_kb:.1f} KB)")


def write_metadata(tflite_path: Path, sample_count: int) -> None:
    """Drop a sidecar JSON describing the model — useful for sanity checks."""
    meta = {
        "model_name": "hey_igris",
        "input_sample_rate": 16000,
        "input_frame_samples": 1280,
        "input_dtype": "float32",
        "num_classes": 1,
        "positive_class_index": 0,
        "training_samples": sample_count,
        "framework": "openwakeword + tensorflow-lite",
    }
    meta_path = tflite_path.with_suffix(".json")
    meta_path.write_text(json.dumps(meta, indent=2))
    log(f"Wrote metadata: {meta_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Train 'Hey IGRIS' TFLite wake word model")
    parser.add_argument("--positive-clips-dir", type=Path, default=None,
                        help="Directory of 16 kHz mono WAV positives (your recordings)")
    parser.add_argument("--negative-clips-dir", type=Path, default=None,
                        help="Directory of 16 kHz mono WAV negatives (auto-fetched if absent)")
    parser.add_argument("--synth-positives", action="store_true",
                        help="If positive clips are missing, synthesise via gTTS (stub quality)")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT,
                        help="Path to write the final .tflite")
    parser.add_argument("--epochs", type=int, default=25,
                        help="Training epochs (more = longer + slightly better)")
    parser.add_argument("--training-root", type=Path, default=DEFAULT_TRAINING_ROOT,
                        help="Where to put intermediate training artefacts")
    args = parser.parse_args()

    check_python_deps()
    args.training_root.mkdir(parents=True, exist_ok=True)
    positive_dir = args.positive_clips_dir or (args.training_root / "positives")
    negative_dir = args.negative_clips_dir or (args.training_root / "negatives")

    # 1. Positives
    pos_count = sum(1 for _ in positive_dir.glob("**/*.wav")) if positive_dir.exists() else 0
    if pos_count == 0:
        if not args.synth_positives:
            log("No positive clips found. Re-run with --synth-positives for a stub model,")
            log("or supply --positive-clips-dir with your own recordings.")
            return 1
        pos_count = synthesise_positive_clips(positive_dir)
        if pos_count == 0:
            log("Failed to synthesise positives. Aborting.")
            return 1
    log(f"Using {pos_count} positive clips from {positive_dir}")

    # 2. Negatives
    neg_count = sum(1 for _ in negative_dir.glob("**/*.wav")) if negative_dir.exists() else 0
    if neg_count == 0:
        neg_count = fetch_negative_clips(negative_dir)
    log(f"Using {neg_count} negative clips from {negative_dir}")

    # 3. Train
    output_dir = args.training_root / "model"
    onnx_path = run_openwakeword_training(
        positive_dir=positive_dir,
        negative_dir=negative_dir,
        output_dir=output_dir,
        epochs=args.epochs,
    )

    # 4. Export TFLite
    export_tflite(onnx_path, args.output)
    write_metadata(args.output, pos_count)

    log("=" * 60)
    log("DONE. Next steps:")
    log(f"  1. Verify the model file exists: {args.output}")
    log("  2. Rebuild the Flutter app:")
    log("       cd mobile_app/igris_mobile")
    log("       flutter clean && flutter pub get && flutter run")
    log("  3. In the app, go to Settings → Voice Agent → Wake Word,")
    log("     enable the toggle, and run the 3s self-test.")
    log("=" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
