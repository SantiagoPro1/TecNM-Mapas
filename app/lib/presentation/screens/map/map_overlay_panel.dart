import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A centered, bounded stack of map controls and notices.
/// Long content scrolls rather than covering the entire map.
class MapOverlayPanel extends StatelessWidget {
  final Widget child;

  const MapOverlayPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SafeArea(
          bottom: false,
          minimum: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).height < 480
                    ? math.min(560, math.max(0, constraints.maxWidth - 192))
                    : 560,
                maxHeight: math.min(
                  constraints.maxHeight * 0.45,
                  MediaQuery.sizeOf(context).height < 480
                      ? constraints.maxHeight * 0.45
                      : math.max(48, constraints.maxHeight - 240),
                ),
              ),
              child: SingleChildScrollView(primary: false, child: child),
            ),
          ),
        ),
      );
}

/// Gives Scaffold the real navigation panel height so notices and floating
/// buttons are positioned above it instead of covering it.
class MapBottomPanel extends StatelessWidget {
  final Widget child;

  const MapBottomPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: math.max(
                      0,
                      MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom -
                          MediaQuery.paddingOf(context).vertical) *
                  0.4,
            ),
            child: SingleChildScrollView(primary: false, child: child),
          ),
        ),
      );
}
