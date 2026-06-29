import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ToolCategory extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> tools;

  const ToolCategory({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.tools,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tools.length,
          itemBuilder: (context, index) {
            final tool = tools[index];
            return _buildToolItem(context, tool);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildToolItem(BuildContext context, Map<String, dynamic> tool) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.1),
          ),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            tool['icon'] as IconData,
            color: color,
            size: 24,
          ),
        ),
        title: Text(
          tool['name'] as String,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          tool['description'] as String,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => _handleToolAction(context, tool),
      ),
    );
  }

  void _handleToolAction(BuildContext context, Map<String, dynamic> tool) {
    final action = tool['action'] as String;

    switch (action) {
      case 'send_message':
        _showSendMessageDialog(context);
        break;
      case 'make_call':
        _showMakeCallDialog(context);
        break;
      case 'web_search':
        _showWebSearchDialog(context);
        break;
      case 'open_app':
        _showInfoSnack(context, 'Use voice command to open apps: "Open YouTube"');
        break;
      case 'file_operation':
        _showInfoSnack(context, 'File operations available via voice commands');
        break;
      case 'attendance_automation':
        _showInfoSnack(context, 'Go to the Attendance tab to mark attendance');
        break;
      case 'set_reminder':
        _showSetReminderDialog(context);
        break;
      default:
        _showInfoSnack(context, '${tool['name']} — Feature coming soon!');
    }
  }

  void _showInfoSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSendMessageDialog(BuildContext context) {
    final recipientCtrl = TextEditingController();
    final messageCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: recipientCtrl,
              decoration: InputDecoration(
                labelText: 'Recipient (phone number)',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageCtrl,
              decoration: InputDecoration(
                labelText: 'Message',
                prefixIcon: const Icon(Icons.message),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final phone = recipientCtrl.text.trim();
              final body = messageCtrl.text.trim();
              if (phone.isNotEmpty) {
                final uri = Uri(
                  scheme: 'sms',
                  path: phone,
                  queryParameters: body.isNotEmpty ? {'body': body} : null,
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showMakeCallDialog(BuildContext context) {
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make Call'),
        content: TextField(
          controller: phoneCtrl,
          decoration: InputDecoration(
            labelText: 'Phone Number',
            prefixIcon: const Icon(Icons.phone),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          keyboardType: TextInputType.phone,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final phone = phoneCtrl.text.trim();
              if (phone.isNotEmpty) {
                final uri = Uri(scheme: 'tel', path: phone);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              }
            },
            child: const Text('Call'),
          ),
        ],
      ),
    );
  }

  void _showWebSearchDialog(BuildContext context) {
    final queryCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Web Search'),
        content: TextField(
          controller: queryCtrl,
          decoration: InputDecoration(
            labelText: 'Search query',
            prefixIcon: const Icon(Icons.search),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) async {
            Navigator.pop(ctx);
            final q = queryCtrl.text.trim();
            if (q.isNotEmpty) {
              final uri = Uri.parse(
                  'https://www.google.com/search?q=${Uri.encodeComponent(q)}');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final q = queryCtrl.text.trim();
              if (q.isNotEmpty) {
                final uri = Uri.parse(
                    'https://www.google.com/search?q=${Uri.encodeComponent(q)}');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  void _showSetReminderDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Set Reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Reminder title',
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(selectedTime.format(ctx)),
                subtitle: const Text('Tap to change time'),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: selectedTime,
                  );
                  if (picked != null) {
                    setDialogState(() => selectedTime = picked);
                  }
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                final title = titleCtrl.text.trim();
                if (title.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Reminder set: "$title" at ${selectedTime.format(context)}'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
  }
}