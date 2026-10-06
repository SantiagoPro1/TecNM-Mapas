import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navia/data/repositories/admin_repository.dart';
import 'package:navia/services/auth/auth_service.dart';

// ─── Estado de autenticación ──────────────────────────────────

/// Estados posibles de la autenticación.
enum AuthStatus {
  initial, // Estado inicial, verificando sesión previa
  authenticated, // Usuario autenticado con @colima.tecnm.mx
  unauthenticated, // Sin sesión activa
  loading, // Proceso de login/logout en curso
  error, // Error de autenticación
}

/// Estado inmutable del módulo de autenticación.
class AuthState {
  final AuthStatus status;
  final User? user;
  final String? cachedPhotoUrl;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.cachedPhotoUrl,
    this.errorMessage,
  });

  /// Matrícula extraída del correo institucional.
  String get matricula {
    if (user?.email == null) return '';
    return user!.email!.split('@')[0];
  }

  /// Nombre del usuario o fallback.
  String get displayName => user?.displayName ?? 'Estudiante TecNM';

  /// URL de la foto de perfil (respeta la foto original y usa caché local persistente).
  String? get photoUrl {
    final url = cachedPhotoUrl ?? user?.photoURL;
    if (url == null || url.trim().isEmpty) return null;
    return url;
  }

  /// Campus TecNM derivado del dominio del correo (ej. "colima.tecnm.mx" →
  /// "TecNM Colima"). Ya no se puede asumir Colima: el dominio permitido se
  /// amplió a cualquier `@*.tecnm.mx` para el Evento Nacional Deportivo.
  String get campusLabel {
    final email = user?.email;
    if (email == null || !email.contains('@')) return 'TecNM';
    final domain = email.split('@').last.toLowerCase();
    if (domain == 'tecnm.mx') return 'TecNM (Nacional)';
    final sub = domain.replaceAll('.tecnm.mx', '');
    if (sub.isEmpty) return 'TecNM';
    final words = sub.split('-').map((w) =>
        w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}');
    return 'TecNM ${words.join(' ')}';
  }

  /// ¿Está autenticado?
  bool get isAuthenticated => status == AuthStatus.authenticated;

  /// ¿Está cargando?
  bool get isLoading => status == AuthStatus.loading;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? cachedPhotoUrl,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      cachedPhotoUrl: cachedPhotoUrl ?? this.cachedPhotoUrl,
      errorMessage: errorMessage,
    );
  }
}

// ─── StateNotifier ────────────────────────────────────────────

/// Notifier de Riverpod que gestiona todo el ciclo de autenticación.
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  static const String _photoKeyPrefix = 'user_photo_url_';

  AuthNotifier(this._authService) : super(const AuthState()) {
    _checkCurrentUser();
  }

  /// Verifica si hay una sesión previa activa y restaura foto guardada.
  Future<void> _checkCurrentUser() async {
    final user = _authService.currentUser;
    if (user != null) {
      String? cached;
      try {
        final prefs = await SharedPreferences.getInstance();
        cached = prefs.getString('$_photoKeyPrefix${user.uid}');
      } catch (_) {}

      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        cachedPhotoUrl: cached ?? user.photoURL,
      );

      // Sincronización silenciosa en segundo plano
      _syncPhotoInBackground(user);
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> _syncPhotoInBackground(User user) async {
    try {
      final photoUrl = await _authService.fetchPhotoUrl(forceSilentSignIn: true);
      if (photoUrl != null && photoUrl.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('$_photoKeyPrefix${user.uid}', photoUrl);
        } catch (_) {}

        if (user.photoURL != photoUrl) {
          try {
            await user.updatePhotoURL(photoUrl);
            await user.reload();
          } catch (_) {}
        }

        if (state.user?.uid == user.uid) {
          state = state.copyWith(
            user: _authService.currentUser,
            cachedPhotoUrl: photoUrl,
          );
        }
      }
    } catch (e) {
      debugPrint('AuthNotifier: error sincronizando foto: $e');
    }
  }

  /// Inicia sesión con Google (solo @colima.tecnm.mx).
  Future<void> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final user = await _authService.signInWithGoogle();

      if (user != null) {
        String? photoUrl = user.photoURL;
        if (photoUrl == null || photoUrl.isEmpty) {
          photoUrl = await _authService.fetchPhotoUrl();
        }
        if (photoUrl != null && photoUrl.isNotEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('$_photoKeyPrefix${user.uid}', photoUrl);
          } catch (_) {}
        }

        state = AuthState(
          status: AuthStatus.authenticated,
          user: user,
          cachedPhotoUrl: photoUrl ?? user.photoURL,
        );
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );

      // Después de mostrar error, regresar a unauthenticated
      await Future.delayed(const Duration(seconds: 3));
      if (state.status == AuthStatus.error) {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    }
  }

  /// Cierra sesión.
  Future<void> signOut() async {
    state = state.copyWith(status: AuthStatus.loading);
    await _authService.signOut();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Limpia el error actual.
  void clearError() {
    if (state.status == AuthStatus.error) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }
}

// ─── Providers ────────────────────────────────────────────────

/// Provider del servicio de autenticación (singleton).
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Provider principal de autenticación.
/// Expone el estado reactivo a toda la app.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

/// Provider de conveniencia: ¿está autenticado?
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

/// Provider de conveniencia: matrícula del usuario.
final matriculaProvider = Provider<String>((ref) {
  return ref.watch(authProvider).matricula;
});

/// Provider del repositorio de administradores (singleton).
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository();
});

/// `true` en tiempo real si el usuario actual es administrador
/// (existe un documento `admins/{uid}` en Firestore). `false` sin sesión.
final isAdminProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(authProvider).user?.uid;
  return ref.watch(adminRepositoryProvider).watchIsAdmin(uid);
});
