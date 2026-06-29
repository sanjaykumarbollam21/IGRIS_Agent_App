import 'package:flutter/material.dart';

class VoiceInputWidget extends StatelessWidget {
  final bool isListening;
  final bool isProcessing;
  final VoidCallback? onTap;
  final String transcription;
  final String response;

  const VoiceInputWidget({
    super.key,
    required this.isListening,
    required this.isProcessing,
    this.onTap,
    this.transcription = '',
    this.response = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status indicator
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isListening
                  ? Theme.of(context).colorScheme.error
                  : isProcessing
                  ? Colors.orange
                  : Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          // Mic icon
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            transform: Matrix4.rotationZ(
              isListening ? 0.5 : 0,
            ),
            child: Icon(
              isListening ? Icons.mic_none : Icons.mic,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          // Status text
          Text(
            isListening
                ? 'Listening...'
                : isProcessing
                ? 'Processing...'
                : 'Tap to speak',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          // Transcription
          if (transcription.isNotEmpty) ...[
            Text(
              'You said:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                transcription,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Response
          if (response.isNotEmpty) ...[
            Text(
              'IGRIS:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                response,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}