import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatMessageList extends StatelessWidget {
  final List<Map<String, dynamic>> messages;

  const ChatMessageList({
    super.key,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic_none,
              size: 48,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Start a conversation with IGRIS',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final bool isUser = message['isUser'] as bool;
        final String text = message['text'] as String;
        final DateTime timestamp =
            message['timestamp'] as DateTime;

        return Align(
          alignment: isUser
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(
              vertical: 4.0,
              horizontal: 8.0,
            ),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: isUser
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isUser ? 16 : 0),
                topRight: Radius.circular(isUser ? 0 : 16),
                bottomLeft: const Radius.circular(16),
                bottomRight: const Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isUser
                            ? Colors.white
                            : Theme.of(context)
                                .colorScheme
                                .onSurface,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('hh:mm a').format(timestamp),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isUser
                            ? Colors.white70
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}