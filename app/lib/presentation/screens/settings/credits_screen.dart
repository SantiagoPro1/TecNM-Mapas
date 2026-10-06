import 'package:flutter/material.dart';
import 'package:navia/core/theme/app_theme.dart';

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('CRÉDITOS'),
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: cs.primary.withValues(alpha: 0.4), width: 2),
                  ),
                  child:
                      Icon(Icons.school_rounded, color: cs.primary, size: 36),
                ),
                const SizedBox(height: 16),
                Text(
                  'TecNM Mapas',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'InnovaTecNM 2026 · Campus Colima',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // Lead developer
          _SectionLabel('DIRECCIÓN & LIDERAZGO', accentColor: cs.primary),
          _CreditCard(
            name: 'Juanpablo E. Gómez D.',
            role: 'Lead Developer · Backend Lead · Líder del Equipo',
            contributions: const [
              'Liderazgo estratégico del proyecto desde la conceptualización hasta la implementación',
              'Diseño y documentación de la arquitectura técnica de 4 capas',
              'Mentoría técnica del equipo: code review, decisiones de diseño, resolución de bloques',
              'Gestión de repositorios, integración continua y control de versiones',
              'Diseño de la arquitectura completa de la aplicación (Clean Architecture + Riverpod)',
              'Implementación de módulos de visión artificial y realidad aumentada (AR)',
              'Diseño UI/UX premium: sistema visual, tema oscuro, animaciones y micro-interacciones',
              'Diseño de las 8 pantallas de la app en Figma bajo principios WCAG 2.1',
              'Integración de Google ML Kit para reconocimiento visual de edificios',
              'Implementación del sistema de códigos QR dinámicos con validación en tiempo real',
              'Validación de accesibilidad: API de Semantics de Flutter para TalkBack/VoiceOver',
              'Desarrollo del módulo de credencial digital con QR dinámico y Firebase Authentication',
              'Backend Node.js/Express con autenticación Firebase y validación de dominio institucional',
            ],
            accentColor: cs.primary,
            icon: Icons.star_rounded,
          ),
          const SizedBox(height: 16),

          _SectionLabel('EQUIPO DE INGENIERÍA Y SISTEMAS',
              accentColor: cs.primary),
          _CreditCard(
            name: 'Santiago G. García',
            role: 'Ingeniería de Sistemas · Desarrollo y Arquitectura',
            contributions: const [
              'Motor de navegación geoespacial: algoritmo Dijkstra y grafo topológico del campus',
              'Sistema GPS en tiempo real con snap-to-node y posicionamiento indoor',
              'Integración de Google ML Kit Image Labeling para validación cruzada',
              'Cartografía digital: mapeo milimétrico de TecNM, Plaza Sendera y Plaza Zentralia',
              'Optimización de rendimiento en el renderizado de mapas interactivos',
              'Documentación de la pipeline de ML: data → training → optimization → deployment',
              'Pruebas de robustez del modelo: diferentes ángulos, iluminación, distancia',
              'Análisis de errores: matrices de confusión y casos mal clasificados',
              'Integración de accesibilidad: Text-to-Speech, Speech-to-Text y modo alto contraste',
            ],
            accentColor: cs.primary,
            icon: Icons.code_rounded,
          ),
          const SizedBox(height: 12),
          _CreditCard(
            name: 'Juan J. Rosales C.',
            role: 'Ingeniería de Sistemas · Interfaces y APIs',
            contributions: const [
              'Desarrollo de lógica en las interfaces de usuario interactivas',
              'Gestión, integración y consumo de APIs de geolocalización',
              'Documentación de patrones de UI y guía de estilos (Design System)',
              'Implementación de dark mode / light mode respetando WCAG en ambos',
              'Desarrollo del flujo de credencial digital con pantalla de QR dinámico',
              'Implementación de la pantalla de configuración de preferencias de accesibilidad',
              'Creación de animaciones suaves y transiciones respetando curvas de easing estándar',
              'Integración de Hive para caché local de mapas y rutas sin conexión',
              'Implementación de navegación por pestañas (bottom navigation) accesible',
              'Creación de formularios interactivos con validación en tiempo real',
              'Soporte técnico en la integración de accesibilidad y VoiceOver',
            ],
            accentColor: cs.primary,
            icon: Icons.api_rounded,
          ),
          const SizedBox(height: 12),
          _CreditCard(
            name: 'Brisa A. Rosas O.',
            role: 'Ingeniería de Sistemas · QA & Seguridad',
            contributions: const [
              'Diseño de la estrategia de testing para toda la app',
              'Implementación de pruebas unitarias para módulos críticos (algoritmo Dijkstra, STT, TTS)',
              'Implementación de pruebas de integración: Backend ↔ Frontend ↔ Firebase',
              'Creación de pruebas end-to-end simulando flujos de usuario reales',
              'Configuración de GitHub Actions para ejecutar tests en cada commit',
              'Análisis de seguridad de Firebase Rules: validación de acceso por rol',
              'Auditoría de vulnerabilidades: dependencias, inyección SQL, XSS (N/A aquí pero verificado)',
              'Implementación de encriptación de datos sensibles (historial de rutas, ubicación)',
              'Aseguramiento de calidad, testing automatizado y pruebas funcionales',
              'Revisión de vulnerabilidades y cumplimiento en protección de datos',
              'Despliegue y configuración de servicios en el ecosistema Firebase',
            ],
            accentColor: cs.primary,
            icon: Icons.shield_rounded,
          ),
          const SizedBox(height: 16),

          _SectionLabel('GESTIÓN EMPRESARIAL', accentColor: cs.primary),
          _CreditCard(
            name: 'Aylen Y. González C.',
            role: 'Gestión Empresarial · Estrategia y Legal',
            contributions: const [
              'Diseño del modelo de negocio y análisis de viabilidad técnica-financiera',
              'Estructuración del marco legal, ético y de privacidad de datos',
              'Planificación estratégica, gestión de recursos y cronograma del proyecto',
              'Investigación de mercado inicial: identificación de 3 segmentos de clientes',
              'Diseño del Business Model Canvas (Value Proposition, Customer Segments, Revenue Streams)',
              'Estructuración del modelo de ingresos B2B2C con 5 fuentes',
              'Análisis de viabilidad financiera: inversión inicial, costos operacionales, punto de equilibrio',
              'Identificación de clientes potenciales en TecNM y segmento de recintos comerciales',
              'Análisis de competencia: comparativa con Google Maps, apps de campus existentes',
              'Estructura de costos detallada: Firebase, servidor, soporte técnico, dominio',
              'Documento de Propiedad Intelectual: plan de registro INDAUTOR y IMPI',
            ],
            accentColor: cs.primary,
            icon: Icons.business_center_rounded,
          ),
          const SizedBox(height: 32),

          // Footer institucional
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: cs.outline),
            ),
            child: Column(
              children: [
                Text(
                  'TecNM Campus Colima',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tecnología con sentido humano.\nMovilidad accesible para todos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.25),
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color accentColor;
  const _SectionLabel(this.text, {required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 14),
      child: Text(
        text,
        style: TextStyle(
          color: accentColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
    );
  }
}

class _CreditCard extends StatelessWidget {
  final String name;
  final String role;
  final List<String> contributions;
  final Color accentColor;
  final IconData icon;

  const _CreditCard({
    required this.name,
    required this.role,
    required this.contributions,
    required this.accentColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      role,
                      style: TextStyle(
                        color: accentColor.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (contributions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: cs.onSurface.withValues(alpha: 0.05)),
            const SizedBox(height: 14),
            ...contributions.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.55),
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
