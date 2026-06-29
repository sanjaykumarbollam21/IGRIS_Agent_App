import 'package:flutter/material.dart';

class LogoWidget extends StatelessWidget {
  final double size;
  final String text;

  const LogoWidget({
    super.key,
    this.size = 80,
    this.text = 'IGRIS',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.android,
            size: 48,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
        ),
      ],
    );
  }
}