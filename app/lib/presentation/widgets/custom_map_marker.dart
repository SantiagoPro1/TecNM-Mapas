import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Widget marcador vectorial para el mapa, optimizado para rendimiento.
///
/// Reemplaza los marcadores basados en `Text(emoji)` e `Icon()` con SVGs
/// escalables y accesibles. Características:
///
///  • SVG vectorial que no pixela al hacer zoom.
///  • [ColorFilter] para adaptar el color al tema oscuro/claro.
///  • Envuelto en [Semantics] para lectores de pantalla.
///  • Glow sutil sin usar `BoxShadow` de alto costo (usa color plano con opacidad).
///
/// ## Optimización de rendimiento
///
/// Este widget usa `RepaintBoundary` para aislar el repaint de cada marcador.
/// Se evitan `BoxShadow` con `blurRadius` > 0 porque Flutter los rasteriza
/// por software y cada marcador se repinta en cada frame del mapa.
class CustomMapMarker extends StatelessWidget {
  /// Ruta al asset SVG (e.g. `'assets/icons/svg/building.svg'`).
  final String svgAsset;

  /// Color principal del icono SVG (se aplica mediante [ColorFilter]).
  final Color iconColor;

  /// Color de fondo del círculo contenedor.
  final Color backgroundColor;

  /// Color del borde exterior.
  final Color borderColor;

  /// Tamaño total del marcador (ancho y alto del contenedor externo).
  final double size;

  /// Tamaño del ícono SVG dentro del círculo.
  final double iconSize;

  /// Texto de letra opcional que se muestra EN LUGAR del SVG
  /// (para edificios con letra de identificación: A, B, P, etc.).
  /// Cuando es no-nulo y no-vacío, muestra la letra centrada.
  final String? buildingLetter;

  /// Etiqueta semántica para accesibilidad (lectura de pantalla).
  final String semanticLabel;

  /// Callback al presionar el marcador.
  final VoidCallback? onTap;

  const CustomMapMarker({
    super.key,
    required this.svgAsset,
    required this.semanticLabel,
    this.iconColor = const Color(0xFF38BDF8),
    this.backgroundColor = const Color(0xFF1E293B),
    this.borderColor = const Color(0xFF38BDF8),
    this.size = 45,
    this.iconSize = 16,
    this.buildingLetter,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasLetter = buildingLetter != null && buildingLetter!.isNotEmpty;

    return RepaintBoundary(
      child: Semantics(
        label: semanticLabel,
        button: onTap != null,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ── Halo suave (sin BoxShadow — usa un Container con opacidad)
                Container(
                  width: size - 7,
                  height: size - 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withValues(alpha: 0.08),
                  ),
                ),
                // ── Círculo principal ──────────────────────────────────────
                Container(
                  width: size - 13,
                  height: size - 13,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: borderColor.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: hasLetter
                        ? Text(
                            buildingLetter!,
                            style: TextStyle(
                              color: iconColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : SvgPicture.asset(
                            svgAsset,
                            width: iconSize,
                            height: iconSize,
                            colorFilter: ColorFilter.mode(
                              iconColor,
                              BlendMode.srcIn,
                            ),
                          ),
                  ),
                ),
                // ── Pequeño indicador debajo ───────────────────────────────
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
