import 'package:flutter/material.dart';
import 'package:navia/presentation/widgets/app_notice.dart';
export 'package:navia/presentation/widgets/app_notice.dart' show NoticeTone;

/// Keeps map notices on the map instead of forwarding them to other routes.
class MapNoticeScope extends StatelessWidget {
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;

  const MapNoticeScope({
    super.key,
    required this.messengerKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    return Theme(
      data: theme.copyWith(
        snackBarTheme: theme.snackBarTheme.copyWith(
          behavior: SnackBarBehavior.floating,
          width: availableWidth.clamp(0.0, 560.0),
          showCloseIcon: true,
        ),
      ),
      child: ScaffoldMessenger(key: messengerKey, child: child),
    );
  }
}

/// Map notices use the shared palette and remain in the local messenger.
class MapNotice extends AppNotice {
  MapNotice({
    super.key,
    required super.content,
    super.tone,
    super.backgroundColor,
    super.duration,
    super.behavior,
  });
}
