import 'package:flutter/material.dart';
import 'package:sinait/core/theme/app_theme.dart';

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('CRÉDITOS'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
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
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4), width: 2),
                  ),
                  child: const Icon(Icons.school_rounded, color: AppTheme.accent, size: 36),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SINAIT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'InnovaTecNM 2026 · Campus Colima',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // Lead developer
          const _SectionLabel('DESARROLLO & ARQUITECTURA'),
          const _CreditCard(
            name: 'Santiago G. García',
            role: 'Arquitecto de Software · Lead Developer',
            contributions: [
              'Diseño de la arquitectura completa de la aplicación (Clean Architecture + Riverpod)',
              'Motor de navegación geoespacial: algoritmo Dijkstra y grafo topológico del campus',
              'Sistema GPS en tiempo real con snap-to-node y posicionamiento indoor',
              'Cartografía digital: mapeo milimétrico de TecNM, Plaza Sendera y Plaza Zentralia',
              'Diseño UI/UX premium: sistema visual, tema oscuro, animaciones y micro-interacciones',
              'Integración de accesibilidad: Text-to-Speech, Speech-to-Text y modo alto contraste',
              'Credencial digital dinámica con generación de QR y efecto Flip Card',
              'Backend Node.js/Express con autenticación Firebase y validación de dominio institucional',
            ],
            accentColor: AppTheme.accent,
            icon: Icons.code_rounded,
          ),
          const SizedBox(height: 16),

          const _SectionLabel('EQUIPO DE INGENIERÍA'),
          const _CreditCard(
            name: 'Juanpablo E. Gómez D.',
            role: 'Ingeniería de Sistemas · Arquitectura en Nube',
            contributions: [
              'Configuración e integración del ecosistema Firebase',
              'Gestión técnica y coordinación de infraestructura cloud',
            ],
            accentColor: Color(0xFF64B5F6),
            icon: Icons.cloud_rounded,
          ),
          const SizedBox(height: 12),
          const _CreditCard(
            name: 'Juan J. Rosales C.',
            role: 'Ingeniería de Sistemas · Interfaces y APIs',
            contributions: [
              'Apoyo en lógica de interfaces de usuario',
              'Gestión e integración de APIs externas',
            ],
            accentColor: Color(0xFF81C784),
            icon: Icons.api_rounded,
          ),
          const SizedBox(height: 12),
          const _CreditCard(
            name: 'Brisa A. Rosas O.',
            role: 'Ingeniería de Sistemas · QA & Seguridad',
            contributions: [
              'Aseguramiento de calidad y pruebas funcionales',
              'Revisión de seguridad y cumplimiento de datos',
            ],
            accentColor: Color(0xFFFFB74D),
            icon: Icons.shield_rounded,
          ),
          const SizedBox(height: 16),

          const _SectionLabel('GESTIÓN EMPRESARIAL'),
          const _CreditCard(
            name: 'Aylen Y. González C.',
            role: 'Gestión Empresarial · Estrategia y Legal',
            contributions: [
              'Modelo de negocio y análisis de viabilidad del proyecto',
              'Marco legal, ético y de privacidad de datos',
            ],
            accentColor: Color(0xFFCE93D8),
            icon: Icons.business_center_rounded,
          ),
          const SizedBox(height: 32),

          // Footer institucional
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                Text(
                  'TecNM Campus Colima',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
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
                    color: Colors.white.withValues(alpha: 0.25),
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
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 14),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.accent,
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                  borderRadius: BorderRadius.circular(12),
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
                      style: const TextStyle(
                        color: Colors.white,
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
            Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
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
                          color: Colors.white.withValues(alpha: 0.55),
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
