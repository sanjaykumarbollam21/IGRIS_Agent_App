import 'package:flutter/material.dart';

class SettingTile extends StatelessWidget {
  final String title;
  final IconData leadingIcon;
  final String? trailingValue;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  const SettingTile({
    super.key,
    required this.title,
    required this.leadingIcon,
    this.trailingValue,
    this.trailingIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          leadingIcon,
          color: Theme.of(context).colorScheme.primary,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      trailing: trailingValue != null
          ? Text(
              trailingValue!,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : trailingIcon != null
              ? Icon(
                  trailingIcon,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                )
              : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}