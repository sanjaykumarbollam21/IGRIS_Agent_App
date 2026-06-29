import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:igris_mobile/services/voice_service.dart';
import 'package:igris_mobile/screens/ai/image_gen_screen.dart';

/// Display the Bixby-style floating assistant overlay.
void showBixbyAssistantOverlay(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (context) => const BixbyAssistantOverlay(),
  );
}

class BixbyAssistantOverlay extends StatefulWidget {
  const BixbyAssistantOverlay({super.key});

  @override
  State<BixbyAssistantOverlay> createState() => _BixbyAssistantOverlayState();
}

class _BixbyAssistantOverlayState extends State<BixbyAssistantOverlay> {
  final VoiceService _voice = VoiceService();
  String _state = 'listening'; // listening | processing | speaking | error
  String _transcription = '';
  String _response = '';
  String _errorMsg = '';
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _startInteraction();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _voice.stopListening();
    _voice.stopSpeaking();
    super.dispose();
  }

  Future<void> _startInteraction() async {
    setState(() {
      _state = 'listening';
      _transcription = '';
      _response = '';
      _errorMsg = '';
    });

    try {
      // 1. Alert Chime (simulated via TTS or quick tone if required, we use visual indicator + listening start)
      final captured = await _voice.startListening(
        onPartialResult: (text) {
          if (mounted) {
            setState(() {
              _transcription = text;
            });
          }
        },
      );

      if (!mounted) return;

      final text = (captured['transcription'] as String?)?.trim() ?? '';
      if (text.isEmpty) {
        setState(() {
          _state = 'error';
          _errorMsg = captured['error'] ?? "I didn't catch that.";
        });
        _scheduleDismiss(const Duration(seconds: 3));
        return;
      }

      // 2. Transition to processing
      setState(() {
        _state = 'processing';
        _transcription = text;
      });

      // 3. Process request
      final result = await _voice.processCommand(text);

      if (!mounted) return;

      // Handle navigation redirects
      if (result['navigate'] == 'image_gen') {
        final prompt = result['prompt'] as String? ?? '';
        Navigator.of(context).pop(); // Dismiss bottom sheet
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageGenScreen(initialPrompt: prompt),
          ),
        );
        return;
      }

      final responseText = (result['response'] as String?)?.trim() ?? 'No response.';

      setState(() {
        _state = 'speaking';
        _response = responseText;
      });

      // 4. Speak response
      await _voice.speakResponse(responseText);

      // Estimate speaking duration based on response length (average 400ms per word, min 4s)
      final wordsCount = responseText.split(' ').length;
      final speakDuration = Duration(milliseconds: (wordsCount * 400).clamp(4000, 15000));
      _scheduleDismiss(speakDuration + const Duration(seconds: 2));

    } catch (e) {
      if (mounted) {
        setState(() {
          _state = 'error';
          _errorMsg = 'Something went wrong. Please try again.';
        });
        _scheduleDismiss(const Duration(seconds: 3));
      }
    }
  }

  void _scheduleDismiss(Duration delay) {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(delay, () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Close Button
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ),

                // Central Animated Orb Visualizer
                BixbyVisualizerOrb(state: _state),
                const SizedBox(height: 28),

                // Status text label
                Text(
                  _statusLabel.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor(cs),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),

                // Context text
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: _buildContentText(cs),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _statusLabel {
    switch (_state) {
      case 'listening':
        return 'Listening';
      case 'processing':
        return 'Analyzing';
      case 'speaking':
        return 'Speaking';
      case 'error':
        return 'Notice';
      default:
        return 'Ready';
    }
  }

  Color _statusColor(ColorScheme cs) {
    switch (_state) {
      case 'listening':
        return Colors.cyanAccent;
      case 'processing':
        return Colors.purpleAccent;
      case 'speaking':
        return Colors.blueAccent;
      case 'error':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  Widget _buildContentText(ColorScheme cs) {
    if (_state == 'error') {
      return Text(
        _errorMsg,
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      );
    }

    if (_state == 'listening' || _state == 'processing') {
      return Text(
        _transcription.isEmpty ? 'Say something...' : '"$_transcription"',
        style: TextStyle(
          color: _transcription.isEmpty ? Colors.white38 : Colors.white70,
          fontSize: 18,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      );
    }

    // Speaking state shows response
    return Column(
      children: [
        if (_transcription.isNotEmpty) ...[
          Text(
            '"$_transcription"',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
        ],
        Text(
          _response,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The glowing sphere that pulses and spins.
class BixbyVisualizerOrb extends StatefulWidget {
  final String state;
  const BixbyVisualizerOrb({super.key, required this.state});

  @override
  State<BixbyVisualizerOrb> createState() => _BixbyVisualizerOrbState();
}

class _BixbyVisualizerOrbState extends State<BixbyVisualizerOrb>
    with TickerProviderStateMixin {
  late AnimationController _rotationCtrl;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _rotationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double pulseScale;
    if (widget.state == 'processing') {
      pulseScale = 0.92 + _pulseCtrl.value * 0.15; // tighter, faster breath
    } else if (widget.state == 'speaking') {
      pulseScale = 0.95 + _pulseCtrl.value * 0.10;
    } else if (widget.state == 'error') {
      pulseScale = 0.90; // flat
    } else {
      pulseScale = 0.85 + _pulseCtrl.value * 0.25; // wide breathing pulse
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_rotationCtrl, _pulseCtrl]),
      builder: (context, child) {
        return Transform.scale(
          scale: pulseScale,
          child: Transform.rotate(
            angle: widget.state == 'error' ? 0 : _rotationCtrl.value * 2 * 3.14159,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glowing background aura
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _orbAccentColor.withValues(alpha: 0.4),
                        _orbSecondaryColor.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Mid gradient shield
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        _orbAccentColor,
                        _orbSecondaryColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Central bright reflective core
                Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Colors.white,
                        Colors.white70,
                        Colors.transparent,
                      ],
                      radius: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _orbAccentColor.withValues(alpha: 0.8),
                        blurRadius: 15,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color get _orbAccentColor {
    switch (widget.state) {
      case 'listening':
        return Colors.cyan;
      case 'processing':
        return Colors.purpleAccent;
      case 'speaking':
        return Colors.blue;
      case 'error':
        return Colors.red.shade400;
      default:
        return Colors.cyan;
    }
  }

  Color get _orbSecondaryColor {
    switch (widget.state) {
      case 'listening':
        return Colors.blue.shade800;
      case 'processing':
        return Colors.deepPurple.shade700;
      case 'speaking':
        return Colors.indigo.shade900;
      case 'error':
        return Colors.red.shade900;
      default:
        return Colors.blue.shade800;
    }
  }
}
