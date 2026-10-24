import 'package:flutter/material.dart';

class RefreshIndicatorBox extends StatelessWidget {
  const RefreshIndicatorBox({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(24)),
    padding: const EdgeInsets.all(12),
    child: Icon(icon, color: Theme.of(context).colorScheme.primary),
  );
}
