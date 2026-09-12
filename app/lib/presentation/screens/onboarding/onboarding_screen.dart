import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/core/theme/app_theme.dart';

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
      icon: Icons.map_rounded,
      title: 'Todas las sedes, un solo mapa',
      description:
          'Encuentra cada sede del Evento Nacional Deportivo del TecNM 2026 y llega sin perderte.',
    ),
    _OnboardingPageData(
      icon: Icons.alt_route_rounded,
      title: 'Ruta paso a paso',
      description:
          'Sigue la ruta en el mapa con indicaciones claras hacia tu destino.',
    ),
    _OnboardingPageData(
      icon: Icons.badge_rounded,
      title: 'Tu credencial digital',
      description:
          'Presenta tu credencial NAVIA con código QR para identificarte durante el evento.',
    ),
    _OnboardingPageData(
      icon: Icons.gavel_rounded,
      title: 'Legal y Privacidad',
      description:
          'Tus datos están protegidos bajo los lineamientos del TecNM. Al continuar, aceptas el uso ético.',
    ),
  ];

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showOnboarding', false);
    if (!mounted) return;
    // Elegir Invitado/Iniciar sesión es un paso aparte (ver login_screen.dart),
    // no algo que "Omitir" también deba saltarse.
    Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  void _handleNext() async {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      if (_termsAccepted) {
        _completeOnboarding();
      } else {
        if (!mounted) return;
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Debes aceptar los términos para continuar',
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: cs.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16, top: 8),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: const Text('Omitir',
                      style: TextStyle(letterSpacing: 1.0)),
                ),
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
                          onChanged: (val) =>
                              setState(() => _termsAccepted = val!),
                        )
                      : null,
                ),
              ),
            ),
            _DotsIndicator(count: _pages.length, current: _currentPage),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ElevatedButton(
                onPressed:
                    (isLastPage && !_termsAccepted) ? null : _handleNext,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                child: Text(isLastPage ? 'COMENZAR' : 'SIGUIENTE'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                  color: cs.primary.withValues(alpha: 0.2), width: 2),
            ),
            child: Icon(page.icon, size: 70, color: cs.primary),
          ),
          const SizedBox(height: 48),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: cs.onSurface.withValues(alpha: 0.55),
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (extraContent != null) ...[
            const SizedBox(height: 40),
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
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: value ? cs.primary.withValues(alpha: 0.05) : cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
            color: value
                ? cs.primary.withValues(alpha: 0.3)
                : cs.onSurface.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: cs.primary,
            checkColor: cs.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          Expanded(
            child: Text(
              'Acepto los términos, condiciones y reglamentos internos del TecNM Campus Colima.',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500),
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
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: active ? 32 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: active ? cs.primary : cs.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }
}
