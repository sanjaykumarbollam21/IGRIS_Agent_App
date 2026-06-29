import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppBarWidget extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;

  const AppBarWidget({
    super.key,
    this.title = '',
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      automaticallyImplyLeading: automaticallyImplyLeading,
      actions: actions,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      elevation: 0,
      iconTheme: IconThemeData(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}