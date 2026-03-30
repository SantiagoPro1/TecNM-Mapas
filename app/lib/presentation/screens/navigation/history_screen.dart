import 'package:flutter/material.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';

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
      destination: 'Biblioteca',
      from: 'Edificio A',
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
    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 4),
      appBar: AppBar(
        title: const Text('Historial de rutas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppTheme.textSecondary),
            onPressed: () {},
            tooltip: 'Limpiar historial',
          ),
        ],
      ),
      body: _history.isEmpty
          ? _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: AppTheme.accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.destination,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.arrow_upward_rounded,
                        size: 12, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text('Desde: ${item.from}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 13, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(item.date,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('~${item.duration}',
                          style: const TextStyle(
                              color: AppTheme.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.replay_rounded,
                color: AppTheme.textSecondary, size: 20),
            onPressed: () {},
            tooltip: 'Repetir ruta',
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded,
              size: 80,
              color: AppTheme.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('Sin rutas recientes',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 18)),
        ],
      ),
    );
  }
}