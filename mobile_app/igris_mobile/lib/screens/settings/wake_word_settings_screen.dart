// lib/screens/settings/wake_word_settings_screen.dart
//
// User-facing controls for the always-listening wake word.
// Exposes:
//   • Master enable/disable switch
//   • Sensitivity profile picker (Battery / Balanced / High)
//   • Permission status indicator + deep-link to OS settings
//   • Test button (records 3s, runs the model, shows result)
//   • Start-on-boot toggle (off by default)
//   • Privacy disclosure required by Play Store / App Store
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/wake_word_provider.dart';
import '../../services/wakeword/porcupine_service.dart';
import '../../services/wakeword/wake_word_bridge.dart';

class WakeWordSettingsScreen extends ConsumerStatefulWidget {
  const WakeWordSettingsScreen({super.key});

  @override
  ConsumerState<WakeWordSettingsScreen> createState() =>
      _WakeWordSettingsScreenState();
}

class _WakeWordSettingsScreenState
    extends ConsumerState<WakeWordSettingsScreen> {
  PermissionStatus _micStatus = PermissionStatus.denied;
  PermissionStatus _notifStatus = PermissionStatus.denied;
  bool _testing = false;
  String? _testResult;
  bool _modelBundled = false;
  bool _startOnBoot = false;
  bool _batteryIgnored = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final mic = await Permission.microphone.status;
    final notif = await Permission.notification.status;
    final prefs = await SharedPreferences.getInstance();
    bool bundled = false;
    try {
      // Probe whether the model asset is actually shipped with the APK.
      await rootBundle.load('assets/wake_word/hey_igris.tflite');
      bundled = true;
    } catch (_) {
      bundled = false;
    }
    bool batteryIgnored = false;
    try {
      batteryIgnored = await WakeWordBridge.instance.isIgnoringBatteryOptimizations();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _micStatus = mic;
      _notifStatus = notif;
      _modelBundled = bundled;
      _startOnBoot = prefs.getBool('start_on_boot') ?? false;
      _batteryIgnored = batteryIgnored;
    });
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.notification.request();
    await _refresh();
  }

  Future<void> _runSelfTest() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final bridge = WakeWordBridge.instance;
    // The self-test piggybacks on the live detection stream so we don't have
    // to keep two engines running. We start the listener, wait 3s, and
    // count how many detections fire.
    var detected = false;
    var score = 0.0;
    final sub = bridge.detectionStream.listen((d) {
      detected = true;
      score = d.score;
    });
    try {
      await bridge.start(
        modelPath: 'assets/wake_word/hey_igris.tflite',
        sensitivity: ref.read(wakeWordProfileProvider).sensitivity,
      );
    } catch (e) {
      await sub.cancel();
      if (!mounted) return;
      setState(() {
        _testResult = '❌ Self-test failed to start: $e';
        _testing = false;
      });
      return;
    }
    await Future.delayed(const Duration(seconds: 3));
    await bridge.stop();
    await sub.cancel();
    if (!mounted) return;
    setState(() {
      _testResult = detected
          ? '✅ Self-test PASS — wake word model is hearing you\n'
              '   Score: ${score.toStringAsFixed(3)}'
          : '⚠️ Self-test did NOT detect "Hey IGRIS" in 3s.\n'
              '• Try the "High sensitivity" profile.\n'
              '• Speak clearly, 6–12 inches from the mic.\n'
              '• Make sure no other app is using the microphone.';
      _testing = false;
    });
  }

  Future<void> _toggleStartOnBoot(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('start_on_boot', v);
    setState(() => _startOnBoot = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(wakeWordEnabledProvider);
    final profile = ref.watch(wakeWordProfileProvider);
    final status = ref.watch(wakeWordStatusProvider);
    final supported = ref.watch(wakeWordSupportedProvider);
    final actions = ref.read(wakeWordActionsProvider);
    final setupBanner = _buildSetupBanner(supported);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wake Word Activation'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!supported)
            const Card(
              color: Colors.amber,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'The native wake word engine currently supports Android only. '
                  'iOS / desktop builds use the cloud STT path instead.',
                ),
              ),
            ),

          if (setupBanner != null) ...[
            setupBanner,
            const SizedBox(height: 16),
          ],

          // ── Privacy disclosure (App Store / Play Store requirement) ─────
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined),
                      SizedBox(width: 8),
                      Text(
                        'On-device only',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Audio is processed on this device using an on-device '
                    'TFLite model (openWakeWord). No audio leaves the device '
                    'until you say "Hey IGRIS" or "IGRIS" and the assistant activates. '
                    'You can disable this at any time.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Master switch ───────────────────────────────────────────────
          SwitchListTile(
            title: const Text('Enable Wake Word ("Hey Igris" / "Igris")'),
            subtitle: Text(_statusLabel(status)),
            value: enabled && supported,
            onChanged: supported
                ? (v) async {
                    if (v) {
                      if (!_hasAllPermissions()) {
                        await _requestPermissions();
                      }
                      await actions.enable();
                    } else {
                      await actions.disable();
                    }
                  }
                : null,
          ),
          const Divider(),

          // ── Permissions ─────────────────────────────────────────────────
          ListTile(
            leading: Icon(
              _micStatus.isGranted ? Icons.check_circle : Icons.error_outline,
              color: _micStatus.isGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('Microphone permission'),
            subtitle: Text(_micStatus.toString()),
            trailing: TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('Settings'),
            ),
          ),
          ListTile(
            leading: Icon(
              _notifStatus.isGranted ? Icons.check_circle : Icons.error_outline,
              color: _notifStatus.isGranted ? Colors.green : Colors.orange,
            ),
            title: const Text('Notification permission (Android 13+)'),
            subtitle: Text(_notifStatus.toString()),
            trailing: TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('Settings'),
            ),
          ),
          ListTile(
            leading: Icon(
              _batteryIgnored ? Icons.check_circle : Icons.warning_amber,
              color: _batteryIgnored ? Colors.green : Colors.orange,
            ),
            title: const Text('Battery optimisation whitelist'),
            subtitle: Text(_batteryIgnored
                ? 'IGRIS can run in the background without restrictions'
                : 'Tap to allow — keeps the listener alive in Doze'),
            trailing: TextButton(
              onPressed: () async {
                await WakeWordBridge.instance.requestIgnoreBatteryOptimizations();
                await _refresh();
              },
              child: const Text('Allow'),
            ),
          ),
          const SizedBox(height: 16),

          // ── Profile picker ──────────────────────────────────────────────
          Text('Sensitivity profile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<WakeWordProfile>(
            segments: WakeWordProfile.values
                .map((p) => ButtonSegment(value: p, label: Text(p.label)))
                .toList(),
            selected: {profile},
            onSelectionChanged: (s) => actions.setProfile(s.first),
          ),
          const SizedBox(height: 8),
          Text(
            _profileHelp(profile),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),

          // ── Start on boot ───────────────────────────────────────────────
          SwitchListTile(
            title: const Text('Start on boot'),
            subtitle: const Text(
              'Automatically start listening for "Hey Igris" or "Igris" after the phone reboots',
            ),
            value: _startOnBoot,
            onChanged: _toggleStartOnBoot,
          ),
          const SizedBox(height: 16),

          // ── Self-test ───────────────────────────────────────────────────
          FilledButton.icon(
            onPressed: (_testing || !supported) ? null : _runSelfTest,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mic),
            label: Text(_testing ? 'Listening for 3s…' : 'Run 3s self-test'),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Text(_testResult!),
          ],
          const SizedBox(height: 24),

          const _TipsCard(),
        ],
      ),
    );
  }

  String _statusLabel(WakeWordStatus s) {
    switch (s) {
      case WakeWordStatus.idle:
        return 'Off';
      case WakeWordStatus.starting:
        return 'Starting…';
      case WakeWordStatus.listening:
        return 'Listening for "Hey Igris" or "Igris"';
      case WakeWordStatus.error:
        return 'Error — see logs';
      case WakeWordStatus.permMissing:
        return 'Microphone permission required';
    }
  }

  String _profileHelp(WakeWordProfile p) {
    switch (p) {
      case WakeWordProfile.lowPower:
        return 'Lowest battery drain. May miss the wake word in noisy rooms or '
            'if you speak softly.';
      case WakeWordProfile.balanced:
        return 'Recommended. Good accuracy on most phones, modest battery cost '
            'while the app is in background.';
      case WakeWordProfile.highSensitivity:
        return 'Picks up quieter speech and works at greater distance. May '
            'trigger on TV dialogue or radio. Best with a tight custom model.';
    }
  }

  bool _hasAllPermissions() =>
      _micStatus.isGranted && _notifStatus.isGranted;

  /// Inspects runtime state and returns a banner explaining what's missing —
  /// model, permissions, or platform support. Returns null when everything
  /// looks set up correctly.
  Widget? _buildSetupBanner(bool supported) {
    final issues = <String>[];
    if (!_modelBundled) {
      issues.add(
        'No model found at assets/wake_word/hey_igris.tflite.\n'
        '→ Run tools/train_wake_word.py to train and export one.\n'
        '→ Drop the resulting hey_igris.tflite into '
        'mobile_app/igris_mobile/assets/wake_word/.\n'
        '→ Run `flutter clean && flutter pub get && flutter run`.',
      );
    }
    if (!supported) {
      issues.add('Native wake word engine is Android-only in this build.');
    }

    final perms = <String>[];
    if (!_micStatus.isGranted) perms.add('Microphone');
    if (!_notifStatus.isGranted) perms.add('Notifications');

    if (issues.isEmpty && perms.isEmpty) return null;

    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Setup incomplete',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final i in issues) ...[
              Text('• $i'),
              const SizedBox(height: 4),
            ],
            if (perms.isNotEmpty)
              Text('Missing permission(s): ${perms.join(", ")}. Grant them in Settings.'),
          ],
        ),
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Tips for best results',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• Say "Hey Igris" or "Igris" with a brief pause, then your command.\n'
                '• Avoid saying it back-to-back within 3 seconds (built-in cooldown).\n'
                '• If triggers happen on TV/radio, lower sensitivity or train a '
                'tighter model with more negative samples.\n'
                '• Always-listening costs ~5-10% battery per hour of background use.\n'
                '• Headphones-unplug pauses inference for 1.5s automatically.'),
          ],
        ),
      ),
    );
  }
}
