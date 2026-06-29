import 'package:flutter/material.dart';

class RecentActivity extends StatelessWidget {
  const RecentActivity({super.key});

  @override
  Widget build(BuildContext context) {
    // Activity data with proper types
    final List<Map<String, dynamic>> activities = [
      {
        'title': 'Attendance marked',
        'subtitle': 'Mathematics session (9:00-9:49)',
        'time': '2 hours ago',
        'icon': Icons.check_circle,
        'color': Colors.green,
      },
      {
        'title': 'Voice command processed',
        'subtitle': '"Hey IGRIS, what\'s my schedule?"',
        'time': '5 hours ago',
        'icon': Icons.mic,
        'color': Colors.blue,
      },
      {
        'title': 'Message sent',
        'subtitle': 'WhatsApp to Mom: "In class"',
        'time': '1 day ago',
        'icon': Icons.message,
        'color': Colors.orange,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton(
              onPressed: () {
                // Navigate to full activity log
              },
              child: Text(
                'See All',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemCount: activities.length,
          itemBuilder: (context, index) {
            final activity = activities[index];
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (activity['color'] as Color).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  activity['icon'] as IconData,
                  color: activity['color'] as Color,
                  size: 20,
                ),
              ),
              title: Text(
                activity['title'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                activity['subtitle'] as String,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Text(
                activity['time'] as String,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
              ),
            );
          },
        ),
      ],
    );
  }
}