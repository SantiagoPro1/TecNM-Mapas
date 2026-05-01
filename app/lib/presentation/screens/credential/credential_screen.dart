import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flip_card/flip_card.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/data/providers/auth_provider.dart';
import 'package:sinait/services/auth/credential_service.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';

class CredentialScreen extends ConsumerStatefulWidget {
  const CredentialScreen({super.key});

  @override
  ConsumerState<CredentialScreen> createState() => _CredentialScreenState();
}

class _CredentialScreenState extends ConsumerState<CredentialScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // JWT dinámico
  String? _currentToken;
  int _remainingSeconds = 0;
  Timer? _refreshTimer;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Genera un token JWT nuevo y programa la renovación automática.
  void _generateToken(AuthState authState) {
    if (!authState.isAuthenticated) return;

    _currentToken = CredentialService.generateCredentialToken(
      matricula: authState.matricula,
      fullName: authState.displayName,
    );
    _remainingSeconds = CredentialService.tokenTtlSeconds;

    // Programar renovación automática antes de que expire
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(seconds: CredentialService.tokenTtlSeconds - 3),
      () => _generateToken(authState),
    );

    // Countdown visual cada segundo
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _remainingSeconds = _currentToken != null
              ? CredentialService.remainingSeconds(_currentToken!)
              : 0;
        });
      }
    });

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Generar token al tener usuario autenticado
    if (authState.isAuthenticated && _currentToken == null) {
      Future.microtask(() => _generateToken(authState));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Credencial Digital'),
        centerTitle: true,
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      body: SafeArea(
        child: !authState.isAuthenticated
            ? _buildLoginRequired()
            : _buildCredentialView(authState),
      ),
    );
  }

  Widget _buildLoginRequired() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, size: 80,
              color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text('Inicia sesión para generar tu credencial',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildCredentialView(AuthState authState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text('Toca la tarjeta para ver el reverso',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          
          FlipCard(
            direction: FlipDirection.HORIZONTAL,
            front: _CredentialFront(authState: authState),
            back: _CredentialBack(
              authState: authState,
              pulse: _pulseAnimation,
              token: _currentToken,
              remainingSeconds: _remainingSeconds,
              onRefresh: () => _generateToken(authState),
            ),
          ),

          const SizedBox(height: 20),

          // Indicador de token dinámico
          if (_currentToken != null)
            _TokenTimer(
              remainingSeconds: _remainingSeconds,
              onRefresh: () => _generateToken(authState),
            ),

          const SizedBox(height: 24),
          _buildStatusList(),
        ],
      ),
    );
  }

  Widget _buildStatusList() {
    final items = [
      (Icons.calendar_today_rounded, 'Vigencia', '2024 - 2027'),
      (Icons.verified_user_rounded, 'Estado', 'Alumno Regular'),
      (Icons.local_hospital_rounded, 'Servicio Médico', 'Vigente IMSS'),
    ];
    return Column(
      children: items.map((item) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Row(
          children: [
            Icon(item.$1, color: AppTheme.accent, size: 22),
            const SizedBox(width: 12),
            Text(item.$2, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const Spacer(),
            Text(item.$3, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
      )).toList(),
    );
  }
}

// ─── Timer del token ──────────────────────────────────────────

class _TokenTimer extends StatelessWidget {
  final int remainingSeconds;
  final VoidCallback onRefresh;

  const _TokenTimer({required this.remainingSeconds, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isLow = remainingSeconds <= 10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isLow
            ? AppTheme.error.withValues(alpha: 0.1)
            : AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLow
              ? AppTheme.error.withValues(alpha: 0.3)
              : AppTheme.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isLow ? Icons.timer_off_rounded : Icons.timer_rounded,
            color: isLow ? AppTheme.error : AppTheme.accent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'QR dinámico: ${remainingSeconds}s',
            style: TextStyle(
              color: isLow ? AppTheme.error : AppTheme.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onRefresh,
            child: Icon(
              Icons.refresh_rounded,
              color: isLow ? AppTheme.error : AppTheme.accent,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// --- VISTA FRONTAL ---
class _CredentialFront extends StatelessWidget {
  final AuthState authState;
  const _CredentialFront({required this.authState});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 230,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 15)],
      ),
      child: Stack(
        children: [
          // Banda azul inferior
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF005696),
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16)),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // FOTO
                Container(
                  width: 110,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    border: Border.all(color: Colors.grey[300]!, width: 1.5),
                  ),
                  child: authState.photoUrl != null 
                    ? Image.network(authState.photoUrl!, fit: BoxFit.cover)
                    : const Icon(Icons.person, size: 50, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                
                // DATOS
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ESTUDIANTE', 
                        style: TextStyle(color: Color(0xFF005696), fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      // Logo TecNM
                      Image.asset('assets/images/logo_tecnm.png', height: 45, fit: BoxFit.contain),
                      const SizedBox(height: 12),
                      _labelValue('Nombre:', authState.displayName.toUpperCase()),
                      _labelValue('Carrera:', 'INGENIERIA EN SISTEMAS COMPUTACIONALES'),
                      _labelValue('Control:', authState.matricula),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 9, fontWeight: FontWeight.bold)),
          Text(value, 
            style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900, height: 1.1),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// --- VISTA TRASERA (con QR dinámico JWT) ---
class _CredentialBack extends StatelessWidget {
  final AuthState authState;
  final Animation<double> pulse;
  final String? token;
  final int remainingSeconds;
  final VoidCallback onRefresh;

  const _CredentialBack({
    required this.authState,
    required this.pulse,
    this.token,
    required this.remainingSeconds,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // El QR muestra el JWT dinámico (si existe), o la matrícula estática
    final qrData = token ?? authState.matricula;

    return Container(
      width: double.infinity,
      height: 230,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 15)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // PARTE IZQUIERDA: LOGOS, QR Y BARRAS
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fila de logos superior
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Image.asset('assets/images/logo_educacion.png', fit: BoxFit.contain, height: 25),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: Row(
                          children: [
                            Image.asset('assets/images/logo_itcolima.png', height: 22),
                            const SizedBox(width: 4),
                            const Expanded(
                              child: Text('INSTITUTO TECNOLÓGICO DE COLIMA', 
                                style: TextStyle(color: Colors.black, fontSize: 5, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Firma centrada
                  Center(
                    child: Column(
                      children: [
                        Text(authState.displayName.split(' ').first, 
                          style: const TextStyle(fontFamily: 'cursive', fontSize: 18, color: Colors.black)),
                        Container(width: 80, height: 0.5, color: Colors.black),
                        const Text('FIRMA', style: TextStyle(fontSize: 6, color: Colors.black)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // QR dinámico y Código de barras
                  Center(
                    child: Column(
                      children: [
                        ScaleTransition(
                          scale: pulse,
                          child: QrImageView(data: qrData, size: 75, padding: EdgeInsets.zero),
                        ),
                        const SizedBox(height: 8),
                        BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: authState.matricula,
                          width: 140,
                          height: 35,
                          drawText: true,
                          style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // PARTE DERECHA: TEXTO VERTICAL (DIRECCIÓN)
            Container(
              width: 35,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const RotatedBox(
                quarterTurns: 3,
                child: Text(
                  "Av. Tecnológico No. 1, Villa de Álvarez, Col., C.P. 2976, Tel(312) 312-9920, 312-6393, 314-0933, 314-0683",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 6.5, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}