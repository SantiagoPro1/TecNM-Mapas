import 'package:flutter/material.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const _history = [
    _HistoryItem(
      destination: 'Laboratorio de Cómputo 1',
      from: 'Entrada principal',
      date: 'Hoy, 09:14',
      duration: '3 min',
      icon: Icons.computer_rounded,
    ),
    _HistoryItem(
      destination: 'Centro de Información',
      from: 'Administrativo',
      date: 'Hoy, 08:50',
      duration: '5 min',
      icon: Icons.local_library_rounded,
    ),
    _HistoryItem(
      destination: 'Cafetería',
      from: 'Laboratorio de Cómputo 1',
      date: 'Ayer, 13:02',
      duration: '4 min',
      icon: Icons.restaurant_rounded,
    ),
    _HistoryItem(
      destination: 'Dirección General',
      from: 'Cafetería',
      date: 'Ayer, 11:30',
      duration: '6 min',
      icon: Icons.business_rounded,
    ),
    _HistoryItem(
      destination: 'Cancha deportiva',
      from: 'Entrada sur',
      date: '28 mar, 16:20',
      duration: '7 min',
      icon: Icons.sports_soccer_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: const BottomNav(currentIndex: -1),
      appBar: AppBar(
        title: const Text('HISTORIAL'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: cs.onSurface.withValues(alpha: 0.24)),
            onPressed: () {},
            tooltip: 'Limpiar historial',
          ),
        ],
      ),
      body: _history.isEmpty
          ? _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              itemCount: _history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _HistoryTile(item: _history[i]),
            ),
    );
  }
}

class _HistoryItem {
  final String destination;
  final String from;
  final String date;
  final String duration;
  final IconData icon;

  const _HistoryItem({
    required this.destination,
    required this.from,
    required this.date,
    required this.duration,
    required this.icon,
  });
}

class _HistoryTile extends StatelessWidget {
  final _HistoryItem item;
  const _HistoryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(item.icon, color: cs.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.destination,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.trip_origin_rounded,
                        size: 10, color: cs.onSurface.withValues(alpha: 0.3)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Desde: ${item.from}',
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.4),
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.access_time_filled_rounded,
                        size: 14, color: cs.onSurface.withValues(alpha: 0.2)),
                    const SizedBox(width: 6),
                    Text(item.date,
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.3),
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(item.duration,
                          style: TextStyle(
                              color: cs.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.03),
                shape: BoxShape.circle),
            child: Icon(Icons.history_rounded,
                size: 64, color: cs.onSurface.withValues(alpha: 0.15)),
          ),
          const SizedBox(height: 24),
          Text('Sin rutas recientes',
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
