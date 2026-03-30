import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sinait/core/constants/app_routes.dart';
import 'package:sinait/core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;
  bool _termsAccepted = false;

  final List<_OnboardingPageData> _pages = const [
    _OnboardingPageData(
      icon: Icons.navigation_rounded,
      title: 'Navega con tu voz',
      description: 'Llega a cualquier edificio o laboratorio del campus sin mirar la pantalla. SINAIT te guía paso a paso.',
    ),
    _OnboardingPageData(
      icon: Icons.qr_code_scanner_rounded,
      title: 'Posicionamiento indoor',
      description: 'Escanea los códigos QR del campus para confirmar tu posición exacta. Sin GPS limitado.',
    ),
    _OnboardingPageData(
      icon: Icons.settings_input_component_rounded,
      title: 'Permisos Necesarios',
      description: 'Para funcionar, requerimos acceso a tu Cámara (para el escáner) y Micrófono (para el asistente de voz).',
    ),
    _OnboardingPageData(
      icon: Icons.gavel_rounded,
      title: 'Legal y Privacidad',
      description: 'Tus datos están protegidos bajo los lineamientos del TecNM. Al continuar, aceptas el uso ético.',
    ),
  ];

  // Pedir permisos al sistema de forma segura
  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
    ].request();
    // Quitamos el print para evitar el aviso 'avoid_print'
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showOnboarding', false);
    if (!mounted) return; // Verificación de seguridad
    Navigator.pushReplacementNamed(context, AppRoutes.home);
  }

  void _handleNext() async {
    // Si estamos en la página de permisos, los solicitamos
    if (_currentPage == 2) {
      await _requestPermissions();
      // Después de un 'await', siempre checamos si la pantalla sigue ahí
      if (!mounted) return; 
    }

    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      if (_termsAccepted) {
        _completeOnboarding();
      } else {
        // Validación de seguridad antes de usar el context
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes aceptar los términos para continuar'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: const Text('Omitir'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) => _PageContent(
                  page: _pages[i],
                  extraContent: i == _pages.length - 1
                      ? _TermsCheckbox(
                          value: _termsAccepted,
                          onChanged: (val) => setState(() => _termsAccepted = val!),
                        )
                      : null,
                ),
              ),
            ),
            _DotsIndicator(count: _pages.length, current: _currentPage),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ElevatedButton(
                onPressed: (isLastPage && !_termsAccepted) ? null : _handleNext,
                child: Text(isLastPage ? 'Comenzar' : 'Siguiente'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// --- SUB-WIDGETS Y CLASES DE APOYO ---

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _PageContent extends StatelessWidget {
  final _OnboardingPageData page;
  final Widget? extraContent;
  const _PageContent({required this.page, this.extraContent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 60, color: AppTheme.accent),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          if (extraContent != null) ...[
            const SizedBox(height: 30),
            extraContent!,
          ],
        ],
      ),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  const _TermsCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.accent,
            checkColor: Colors.black,
          ),
          const Expanded(
            child: Text(
              'Acepto los términos, condiciones y reglamentos internos del TecNM Campus Colima.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;
  const _DotsIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppTheme.accent : AppTheme.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}