import 'package:flutter/material.dart';

enum NoticeTone {
  success(Color(0xFF187447), Icons.check_circle_outline_rounded),
  deletion(Color(0xFFB42318), Icons.delete_outline_rounded),
  error(Color(0xFFB42318), Icons.error_outline_rounded),
  warning(Color(0xFF945900), Icons.warning_amber_rounded),
  info(Color(0xFF002E6D), Icons.info_outline_rounded);

  final Color background;
  final IconData icon;
  const NoticeTone(this.background, this.icon);
}

/// Shared notice colors and icons, independent of the app's accent theme.
class AppNotice extends SnackBar {
  AppNotice({
    super.key,
    required Widget content,
    NoticeTone tone = NoticeTone.info,
    Color? backgroundColor,
    super.duration,
    super.behavior = SnackBarBehavior.floating,
    super.shape,
  }) : super(
          backgroundColor: backgroundColor ?? tone.background,
          showCloseIcon: true,
          closeIconColor: foregroundFor(backgroundColor ?? tone.background),
          content: DefaultTextStyle.merge(
            style: TextStyle(
                color: foregroundFor(backgroundColor ?? tone.background)),
            child: IconTheme.merge(
              data: IconThemeData(
                  color: foregroundFor(backgroundColor ?? tone.background)),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(tone.icon, size: 22),
                const SizedBox(width: 10),
                Expanded(child: content),
              ]),
            ),
          ),
        );

  static Color foregroundFor(Color background) {
    final luminance = background.computeLuminance();
    final whiteContrast = 1.05 / (luminance + 0.05);
    final blackContrast = (luminance + 0.05) / 0.05;
    return whiteContrast >= blackContrast ? Colors.white : Colors.black;
  }
}
