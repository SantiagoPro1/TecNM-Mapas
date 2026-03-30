import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flip_card/flip_card.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:sinait/core/theme/app_theme.dart';
import 'package:sinait/services/auth/auth_service.dart';
import 'package:sinait/presentation/widgets/bottom_nav.dart';

class CredentialScreen extends StatefulWidget {
  const CredentialScreen({super.key});

  @override
  State<CredentialScreen> createState() => _CredentialScreenState();
}

class _CredentialScreenState extends State<CredentialScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final AuthService _authService = AuthService();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final User? user = _authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Credencial Digital'),
        centerTitle: true,
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      body: SafeArea(
        child: user == null ? _buildLoginRequired() : _buildCredentialView(user),
      ),
    );
  }

  Widget _buildLoginRequired() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, size: 80, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text('Inicia sesión para generar tu credencial',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildCredentialView(User user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text('Toca la tarjeta para ver el reverso',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          
          FlipCard(
            direction: FlipDirection.HORIZONTAL,
            front: _CredentialFront(user: user, authService: _authService),
            back: _CredentialBack(user: user, authService: _authService, pulse: _pulseAnimation),
          ),

          const SizedBox(height: 32),
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

// --- VISTA FRONTAL ---
class _CredentialFront extends StatelessWidget {
  final User user;
  final AuthService authService;
  const _CredentialFront({required this.user, required this.authService});

  @override
  Widget build(BuildContext context) {
    final matricula = authService.getMatricula(user.email);

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
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
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
                  child: user.photoURL != null 
                    ? Image.network(user.photoURL!.replaceFirst('s96-c', 's400-c'), fit: BoxFit.cover)
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
                      _labelValue('Nombre:', user.displayName?.toUpperCase() ?? 'N/A'),
                      _labelValue('Carrera:', 'INGENIERIA EN SISTEMAS COMPUTACIONALES'),
                      _labelValue('Control:', matricula),
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

// --- VISTA TRASERA ---
class _CredentialBack extends StatelessWidget {
  final User user;
  final AuthService authService;
  final Animation<double> pulse;
  const _CredentialBack({required this.user, required this.authService, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final matricula = authService.getMatricula(user.email);

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
                        Text(user.displayName?.split(' ').first ?? 'Firma', 
                          style: const TextStyle(fontFamily: 'cursive', fontSize: 18, color: Colors.black)),
                        Container(width: 80, height: 0.5, color: Colors.black),
                        const Text('FIRMA', style: TextStyle(fontSize: 6, color: Colors.black)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // QR y Barras en la misma sección
                  Center(
                    child: Column(
                      children: [
                        ScaleTransition(
                          scale: pulse,
                          child: QrImageView(data: matricula, size: 75, padding: EdgeInsets.zero),
                        ),
                        const SizedBox(height: 8),
                        BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: matricula,
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