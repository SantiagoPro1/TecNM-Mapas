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
    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
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

  void _generateToken(AuthState authState) {
    if (!authState.isAuthenticated) return;

    _currentToken = CredentialService.generateCredentialToken(
      matricula: authState.matricula,
      fullName: authState.displayName,
    );
    _remainingSeconds = CredentialService.tokenTtlSeconds;

    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(seconds: CredentialService.tokenTtlSeconds - 3),
      () => _generateToken(authState),
    );

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

    if (authState.isAuthenticated && _currentToken == null) {
      Future.microtask(() => _generateToken(authState));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('IDENTIDAD DIGITAL'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
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
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_rounded, size: 80, color: AppTheme.accent.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 24),
          const Text('Inicia sesión para generar tu credencial',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildCredentialView(AuthState authState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_rounded, size: 14, color: AppTheme.accent),
                SizedBox(width: 8),
                Text('TOCA PARA VOLTEAR',
                    style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
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

          const SizedBox(height: 32),

          if (_currentToken != null)
            _TokenTimer(
              remainingSeconds: _remainingSeconds,
              onRefresh: () => _generateToken(authState),
            ),

          const SizedBox(height: 32),
          _buildStatusList(),
        ],
      ),
    );
  }

  Widget _buildStatusList() {
    final items = [
      (Icons.calendar_today_rounded, 'VIGENCIA', '2024 - 2027', Colors.blueAccent),
      (Icons.verified_user_rounded, 'ESTADO', 'ALUMNO REGULAR', Colors.greenAccent),
      (Icons.local_hospital_rounded, 'SEGURO', 'VIGENTE IMSS', Colors.redAccent),
    ];
    return Column(
      children: items.map((item) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: item.$4.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.$1, color: item.$4, size: 20),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.$2, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                const SizedBox(height: 2),
                Text(item.$3, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      )).toList(),
    );
  }
}

class _TokenTimer extends StatelessWidget {
  final int remainingSeconds;
  final VoidCallback onRefresh;

  const _TokenTimer({required this.remainingSeconds, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isLow = remainingSeconds <= 10;
    final color = isLow ? AppTheme.error : AppTheme.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isLow ? Icons.timer_off_rounded : Icons.timer_rounded, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            'QR DINÁMICO: ${remainingSeconds}S',
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
          ),
          const Spacer(),
          IconButton(
            onPressed: onRefresh,
            icon: Icon(Icons.refresh_rounded, color: color, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _CredentialFront extends StatelessWidget {
  final AuthState authState;
  const _CredentialFront({required this.authState});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 240,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppTheme.accent.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)
        ],
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Decorative background
            Positioned(
              top: -50, right: -50,
              child: Container(
                width: 150, height: 150,
                decoration: BoxDecoration(
                  color: const Color(0xFF005696).withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: 48,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF005696), Color(0xFF004070)]),
                ),
                child: const Center(
                  child: Text('INSTITUTO TECNOLÓGICO DE COLIMA', 
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Container(
                    width: 110, height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: authState.photoUrl != null 
                        ? Image.network(authState.photoUrl!, fit: BoxFit.cover)
                        : Icon(Icons.person, size: 60, color: Colors.grey[300]),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ESTUDIANTE', 
                          style: TextStyle(color: Color(0xFF005696), fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
                        const SizedBox(height: 12),
                        _labelValue('NOMBRE:', authState.displayName.toUpperCase()),
                        _labelValue('CARRERA:', 'ING. SISTEMAS COMPUTACIONALES'),
                        _labelValue('CONTROL:', authState.matricula),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black38, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 1),
          Text(value, 
            style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800, height: 1.1),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

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
    final qrData = token ?? authState.matricula;

    return Container(
      width: double.infinity,
      height: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppTheme.accent.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)
        ],
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset('assets/images/logo_tecnm.png', height: 35, fit: BoxFit.contain),
                Image.asset('assets/images/logo_itcolima.png', height: 35),
              ],
            ),
            const Spacer(),
            ScaleTransition(
              scale: pulse,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                ),
                child: QrImageView(data: qrData, size: 100, padding: EdgeInsets.zero),
              ),
            ),
            const Spacer(),
            BarcodeWidget(
              barcode: Barcode.code128(),
              data: authState.matricula,
              width: 180, height: 40,
              drawText: true,
              style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}