import 'package:flutter/material.dart';

/// Uses only the buttons' height so floating notices stay inside the map.
class MapActionButtons extends StatelessWidget {
  final List<Widget> children;

  const MapActionButtons({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: children,
        ),
      );
}
