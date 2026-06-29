# IGRIS Mobile Application

This is the Flutter-based mobile application for the IGRIS (Intelligent General-purpose Robotic Intelligence System) personal AI agent.

## Features

- Voice-first interface with wake word detection ("Hey IGRIS")
- Attendance automation for MyNiat college system
- Natural language processing with Gemini AI
- Text-to-speech with Murf.ai

---

## "Hey IGRIS" — On-Device Wake Word

Always-listening wake word powered by **Picovoice Porcupine**. Audio is
processed entirely on the device — nothing leaves the phone until the user
actually invokes the assistant. Mirrors the UX of "Hey Google" / "Hey Siri"
while keeping the model customisable.

### 1. Train the custom keyword (free tier)

1. Sign up at <https://console.picovoice.ai/> (free tier includes
   several custom keywords per month).
2. **Porcupine** → **Create Keyword**.
3. Fill in:
   - **Keyword name:** `Hey IGRIS`
   - **Phrase (English):** `Hey IGRIS`
   - **Platform:** Android (and iOS if needed — you get a separate file
     per platform; the model itself is the same).
4. Train (usually <2 min). Download the resulting `Hey-IGRIS_android.ppn`
   and `Hey-IGRIS_ios.ppn`.
5. Drop them into `assets/wake_word/`. They are **gitignored** — they are
   bound to your Picovoice AccessKey.

> **Naming tip:** Porcupine works best with 2–3 syllables, distinct from
> common words. "Hey IGRIS" is fine, but if you see false positives on
> TV/radio, consider "Hey Igris" with different capitalisation or a
> totally distinct phrase.

### 2. Get an AccessKey

- The same Picovoice Console gives you an AccessKey under
  **Profile → AccessKey**.
- **Never** hardcode it in source. Pass it at build time:

```bash
flutter build apk --release \
  --dart-define=IGRIS_BACKEND_URL=https://api.igris.app/api \
  --dart-define=PICOVOICE_ACCESS_KEY=YOUR_KEY_HERE
```

- On first launch the key is copied to `flutter_secure_storage`
  (encrypted shared prefs on Android, Keychain on iOS) and the build-time
  constant is no longer referenced.
- See `.env.example` for the full list of build-time flags.

### 3. Permissions

- **Android** — runtime permissions are requested in the Wake Word
  settings screen:
  - `RECORD_AUDIO` — required, no fallback.
  - `POST_NOTIFICATIONS` — required on Android 13+ to show the
    foreground-service notification.
  - `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — recommended; on Doze-strict
    OEMs (Xiaomi, Huawei) the FGS gets killed within minutes without
    this. The settings screen can deep-link the user to the OS page.
- **iOS** — `NSMicrophoneUsageDescription` is set in `Info.plist`. The
  OS will prompt on first STT attempt; for always-listening the user
  must also keep the app un-restricted in *Settings → IGRIS →
  Microphone*.

### 4. Background behaviour

- **Android** — runs inside a `flutter_foreground_task` service with
  `foregroundServiceType=microphone`. A persistent low-priority
  notification ("IGRIS is listening") is mandatory; on Android 14+ the
  FGS type must be declared in the service itself (the plugin handles
  this).
- **iOS** — `UIBackgroundModes` includes `audio`. The shared
  `AVAudioSession` is set to `.playAndRecord / .measurement` in
  `AppDelegate.swift`. iOS will only keep the session alive if the
  app has been launched in the foreground at least once after
  install — be sure to surface an "Open the app once" tip in the
  onboarding flow.

### 5. Architecture

```
                ┌──────────────────────────────┐
  mic PCM 16kHz │  PorcupineWakeWordService    │  onDetect
  ─────────────▶│  (Porcupine + pvrecorder)    │──────────┐
                └──────────────────────────────┘          │
                                                           ▼
                                            ForegroundBridge
                                            (UI isolate)
                                                           │
                                                           ▼
                                       VoiceService.processWakeWordTrigger
                                                           │
                                                           ▼
                                          STT → intent → TTS reply
```

- `lib/services/wakeword/porcupine_service.dart` — pure Dart wrapper
  around the Porcupine engine. Singleton, owns the mic.
- `lib/services/wakeword/foreground_isolate_service.dart` — Android
  FGS bridge (separate isolate, cross-isolate `SendPort`).
- `lib/services/wakeword/stt_followup.dart` — follow-up STT backends
  (online / Vosk / Whisper).
- `lib/providers/wake_word_provider.dart` — Riverpod glue.
- `lib/screens/settings/wake_word_settings_screen.dart` — user UI.

### 6. Battery & accuracy tuning

- **Sensitivity** — 3 profiles (battery / balanced / high). These map
  to Porcupine `sensitivity` 0.35 / 0.55 / 0.75. Tune further by
  editing `WakeWordProfile.sensitivity`.
- **False positives** — usually triggered by TV/radio dialogue.
  - Train a *negative* keyword on the console and bump its sensitivity
    up while keeping the wake word moderate. Porcupine supports up to
    multiple keywords per engine.
  - Gate the engine on a coarse voice-activity detector (e.g. `voice_processor`
    RMS threshold) so it only processes frames with likely speech.
- **Battery** — expect ~5–10% per hour of background listening on a
  modern phone. Profile `lowPower` halves that at the cost of missing
  soft-spoken wake words.

### 7. Testing

1. Open the app, **Settings → Wake Word**.
2. Tap **Run 3s self-test** and say "Hey IGRIS" out loud.
3. The screen should report ✅. If not:
   - Try the **High sensitivity** profile.
   - Verify the .ppn asset was bundled (`flutter build apk` and
     `unzip -l build/app/outputs/flutter-apk/app.apk | grep ppn`).
   - Check `adb logcat | grep PorcupineWakeWord` for engine errors.

### 8. Limitations & trade-offs

- **Battery** — always-listening always costs power. We cannot make
  this zero. Provide an easy off switch and an opt-in onboarding.
- **iOS background** — iOS aggressively suspends apps. The wake word
  will not run if the user has force-killed IGRIS or if the OS has
  decided to terminate it. The only way to *guarantee* 24/7 listening
  on iOS is to use a "Push to Talk" voice trigger (Siri shortcut,
  Action button) — see [Apple's background execution limits](https://developer.apple.com/documentation/backgroundtasks).
- **Custom keyword drift** — Porcupine models are tied to a single
  phrase. Changing the phrase requires re-training on the console
  and re-shipping the .ppn.
- **No wake word when device is locked & app is terminated** on iOS.
  This is an Apple platform restriction, not a Porcupine limitation.
- **OEM battery savers** — some Android OEMs (Xiaomi, Huawei, OPPO)
  kill FGS even with `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. Document
  the OEM whitelist in your user-facing FAQ.

### 9. App Store / Play Store compliance

- **Play Store Data safety** — declare that audio is collected
  *only when the wake word fires*, processed on-device, and that no
  audio is sent to your servers unless the user invokes the
  assistant. This matches the disclosure in the settings screen.
- **Play Store foreground service declaration** — when submitting,
  choose the "Microphone" FGS type and provide a video showing why
  it is required (always-listening wake word).
- **App Store privacy** — declare `NSMicrophoneUsageDescription` in
  the privacy label. The string in `Info.plist` is shown to users
  verbatim when iOS prompts.
- **App Store 4.0 / "Always-Listening" apps** — Apple does not
  publish a fixed rule, but reviewers look for:
  1. A clearly visible opt-in toggle.
  2. A persistent visual indicator (the foreground notification
     satisfies this on Android; on iOS, the live activity / status
     bar state is the equivalent).
  3. The app does not record audio without an *active* user gesture
     immediately after the wake word — i.e. listening stops if the
     user doesn't speak within a few seconds (Porcupine does this by
     design; the follow-up STT has a 8s timeout).
- **GDPR / CCPA** — because all audio is on-device until the user
  speaks, you collect far less personal data than cloud-based
  assistants. Still: log only *counts* of wake-word triggers, never
  the audio itself.

### 10. Optional: upgrading the follow-up STT

The default follow-up STT is whatever your existing `speech_to_text`
package uses (Google online on Android, native on iOS). To go fully
offline:

1. Download a Vosk model (`vosk-model-small-en-us-0.15`, ~50MB) from
   <https://alphacephei.com/vosk/models>.
2. Drop the unzipped folder into `assets/vosk/`.
3. Add `vosk: ^0.4.0` (or `vosk_flutter: ^0.4.0`) to `pubspec.yaml` and
   wire it into `SttFollowupService._listenVosk()` — the function is
   already stubbed in this PR.

For best accuracy at the cost of latency, switch the backend to
`SttBackend.whisperCloud` and supply an OpenAI key in the API Keys
settings screen. The Whisper call itself is wired but commented for
brevity — fill in the multipart upload in
`SttFollowupService._listenWhisperCloud()`.

### 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Self-test never detects | Mic muted / wrong sample rate | Check OS mic, try `High sensitivity` |
| Works in fg, dies in bg (Android) | OEM battery killer | Ask user to whitelist IGRIS in OEM settings |
| Works in fg, dies in bg (iOS) | App force-killed or audio session inactive | Reopen app once after install |
| `PorcupineException: INVALID_ACCESS_KEY` | Wrong key | Re-check `--dart-define`, rebuild |
| `PvRecorderException: permission denied` | Mic permission not granted | Re-request via settings screen |
| `PorcupineException: model not found` | .ppn not bundled | Run `flutter clean && flutter pub get && flutter build apk` |

- Tool integration (messaging, calling, app control, web search, file operations)
- Telegram bot synchronization
- Dark/light theme support
- Offline capabilities with local data caching
- Biometric authentication
- Background services for automated attendance marking

## Setup Instructions

### Prerequisites

- Flutter SDK (v3.0.0 or higher)
- Dart SDK (v3.0.0 or higher)
- Android Studio / Xcode (for platform-specific tools)
- Physical device or emulator/simulator for testing
- Backend server running (see backend README)

### Installation

1. Clone the repository
2. Navigate to the mobile app directory:
   ```bash
   cd mobile_app/igris_mobile
   ```

3. Get Flutter dependencies:
   ```bash
   flutter pub get
   ```

4. Configure platform-specific settings:
   - **Android**: Update `android/app/src/main/AndroidManifest.xml` with necessary permissions
   - **iOS**: Update `ios/Runner/Info.plist` with necessary permissions

5. Create a `.env` file in the root directory (optional):
   ```
   BACKEND_URL=http://10.0.2.2:5000
   ```

### Running the Application

To run on an Android emulator or physical device:
```bash
flutter run
```

To run on iOS simulator or physical device:
```bash
flutter run
```

To build an APK for release:
```bash
flutter build apk --release
```

To build an iOS IPA for release:
```bash
flutter build ios --release
```

### Permissions Required

The application requires the following permissions for full functionality:

#### Android
- INTERNET
- ACCESS_NETWORK_STATE
- WAKE_LOCK
- FOREGROUND_SERVICE
- RECORD_AUDIO
- MODIFY_AUDIO_SETTINGS
- READ_PHONE_STATE
- CALL_PHONE
- SEND_SMS
- READ_SMS
- RECEIVE_SMS
- READ_CONTACTS
- WRITE_CONTACTS
- ACCESS_FINE_LOCATION
- ACCESS_COARSE_LOCATION
- BODY_SENSORS
- ACTIVITY_RECOGNITION

#### iOS
- Microphone usage
- Speech recognition
- Phone call initiation
- Contacts access
- Location access
- Notifications
- Background modes (audio, location, remote notifications)

### Project Structure

```
lib/
├── main.dart                 # Application entry point
├── screens/                  # UI screens
│   ├── auth/                 # Authentication screens
│   └── home/                 # Main app screens
├── widgets/                  # Reusable UI components
│   └── common/               # Shared widgets
├── services/                 # Service layers (API, voice, etc.)
├── models/                   # Data models
├── providers/                # State management providers
└── utils/                    # Utility functions
```

### Backend Integration

The mobile app communicates with the IGRIS backend REST API. Make sure the backend is running and accessible from your device/network.

Default API base URL: `http://10.0.2.2:5000/api` (Android emulator)
For physical devices, replace `10.0.2.2` with your computer's IP address.

### Features Overview

#### Voice Interface
- Wake word detection ("Hey IGRIS")
- Speech-to-text using device-native or Whisper
- Natural language processing with Gemini AI
- Text-to-speech with Murf.ai
- Conversational interface with context retention

#### Attendance Automation
- Automatic WiFi detection for college networks
- Scheduled attendance marking during class times
- Auto-login to MyNiat with saved credentials
- OTP auto-fill from SMS notifications
- Holiday and weekend skipping
- Manual override and "Mark Now" voice command
- Daily/weekly attendance reports

#### Tool Integration
- Messaging: WhatsApp, SMS, Telegram, Email
- Calling: Make, answer, reject calls
- App control: Open any application, perform actions inside apps
- Web search: Search the internet for information
- File operations: Read, write, manage files
- Device controls: Change settings (volume, brightness, etc.)

#### Telegram Integration
- Full mirror of voice assistant via Telegram bot
- Voice note support
- Command-based interface
- Attendance notifications via Telegram

### Customization

To customize the application for your needs:

1. **Colors and Theme**: Modify `lib/services/theme_service.dart`
2. **API Endpoints**: Update service classes in `lib/services/`
3. **Supported Languages**: Add translations in localization service
4. **Features**: Enable/disable features in respective service classes
5. **Branding**: Update assets in `assets/` folder

### Troubleshooting

Common issues and solutions:

1. **Dependencies not resolving**: Run `flutter pub get` again
2. **Build failures**: Try `flutter clean` then `flutter pub get`
3. **Runtime errors**: Check device logs with `flutter logs`
4. **Permission denied**: Ensure all required permissions are granted
5. **Backend connection issues**: Verify backend is running and accessible

### Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a pull request

### License

This project is proprietary and confidential. All rights reserved.