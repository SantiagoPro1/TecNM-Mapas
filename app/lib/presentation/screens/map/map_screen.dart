import 'package:flutter/material.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  String? _selectedBuilding;

  final List<_Building> _buildings = const [
    _Building('Edificio A', 'Aulas generales', Icons.school_rounded, 0.2, 0.3),
    _Building('Lab. Cómputo', 'Laboratorios', Icons.computer_rounded, 0.6, 0.4),
    _Building('Biblioteca', 'Servicios', Icons.local_library_rounded, 0.4, 0.65),
    _Building('Cafetería', 'Servicios', Icons.restaurant_rounded, 0.7, 0.7),
    _Building('Dirección', 'Administración', Icons.business_rounded, 0.3, 0.5),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      appBar: AppBar(
        title: const Text('Mapa del Campus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_rounded, color: AppTheme.accent),
            onPressed: () {},
            tooltip: 'Mi ubicación',
          ),
        ],
      ),
      body: Column(
        children: [
          _SearchBar(
            onChanged: (v) => setState(() => _selectedBuilding = v.isEmpty ? null : v),
          ),
          Expanded(child: _CampusMap(buildings: _buildings, selected: _selectedBuilding)),
          if (_selectedBuilding != null)
            _DestinationPanel(
              building: _buildings.firstWhere(
                (b) => b.name == _selectedBuilding,
                orElse: () => _buildings.first,
              ),
              onDismiss: () => setState(() => _selectedBuilding = null),
            ),
        ],
      ),
    );
  }
}

class _Building {
  final String name;
  final String category;
  final IconData icon;
  final double relX;
  final double relY;
  const _Building(
      this.name, this.category, this.icon, this.relX, this.relY);
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Buscar edificio o servicio...',
          hintStyle: const TextStyle(color: AppTheme.textSecondary),
          prefixIcon:
              const Icon(Icons.search_rounded, color: AppTheme.accent),
          filled: true,
          fillColor: AppTheme.cardBackground,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF333333)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF333333)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppTheme.accent, width: 2),
          ),
        ),
      ),
    );
  }
}

class _CampusMap extends StatelessWidget {
  final List<_Building> buildings;
  final String? selected;
  const _CampusMap({required this.buildings, required this.selected});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Stack(
        children: [
          // Fondo del mapa
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: Center(
              child: Text(
                'Campus TecNM Colima',
                style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.4),
                    fontSize: 14),
              ),
            ),
          ),
          // Marcadores
          ...buildings.map((b) {
            final isSelected = b.name == selected;
            final x = 16 +
                (constraints.maxWidth - 32) * b.relX;
            final y = constraints.maxHeight * b.relY;
            return Positioned(
              left: x - 20,
              top: y - 20,
              child: GestureDetector(
                onTap: () {},
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: isSelected ? 52 : 40,
                  height: isSelected ? 52 : 40,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.accent : AppTheme.cardBackground,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.accent
                          : const Color(0xFF555555),
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: Icon(
                    b.icon,
                    size: isSelected ? 28 : 22,
                    color: isSelected ? Colors.black : AppTheme.accent,
                  ),
                ),
              ),
            );
          }),
        ],
      );
    });
  }
}

class _DestinationPanel extends StatelessWidget {
  final _Building building;
  final VoidCallback onDismiss;
  const _DestinationPanel(
      {required this.building, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF333333))),
      ),
      child: Row(
        children: [
          Icon(building.icon, color: AppTheme.accent, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(building.name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text(building.category,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 14)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.navigation_rounded, size: 18),
            label: const Text('Ir'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(80, 44),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded,
                color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}