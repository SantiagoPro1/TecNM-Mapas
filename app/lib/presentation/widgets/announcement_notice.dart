import 'package:flutter/material.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/data/models/announcement.dart';
import 'package:navia/presentation/widgets/app_notice.dart';

class AnnouncementNotice extends StatelessWidget {
  final Announcement announcement;
  const AnnouncementNotice({super.key, required this.announcement});

  static NoticeTone toneFor(AnnouncementType type) => switch (type) {
        AnnouncementType.warning => NoticeTone.warning,
        AnnouncementType.closure => NoticeTone.error,
        AnnouncementType.service => NoticeTone.success,
        AnnouncementType.info || AnnouncementType.event => NoticeTone.info,
      };

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(announcement.type);
    final icon = switch (announcement.type) {
      AnnouncementType.closure => Icons.block_rounded,
      AnnouncementType.event => Icons.event_rounded,
      _ => tone.icon,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(announcement.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(announcement.body,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, height: 1.3)),
        ])),
      ]),
    );
  }
}
