import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure the shared audio session so Porcupine / pvrecorder can keep
    // grabbing microphone samples while the app is in the background.
    //
    // iOS will only honour this if Info.plist declares:
    //   • NSMicrophoneUsageDescription
    //   • UIBackgroundModes → audio
    //
    // Failure to set the category here results in the engine stopping
    // within ~5 seconds of the app being backgrounded.
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .measurement, // disables signal processing that hurts keyword spotting
        options: [.mixWithOthers, .duckOthers, .defaultToSpeaker]
      )
      try session.setActive(true, options: [])
    } catch {
      // Don't crash — the wake word just won't run in background.
      NSLog("[IGRIS] AVAudioSession config failed: \(error.localizedDescription)")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
