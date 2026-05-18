import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
  });

  /// Matrícula extraída del correo institucional.
  String get matricula {
    if (user?.email == null) return '';
    return user!.email!.split('@')[0];
  }

  /// Nombre del usuario o fallback.
  String get displayName => user?.displayName ?? 'Estudiante TecNM';

  /// URL de la foto de perfil (alta resolución).
  String? get photoUrl => user?.photoURL?.replaceFirst('s96-c', 's400-c');

  /// ¿Está autenticado?
  bool get isAuthenticated => status == AuthStatus.authenticated;

  /// ¿Está cargando?
  bool get isLoading => status == AuthStatus.loading;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
    );
  }
}

// ─── StateNotifier ────────────────────────────────────────────

/// Notifier de Riverpod que gestiona todo el ciclo de autenticación.
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(const AuthState()) {
    _checkCurrentUser();
  }

  /// Verifica si hay una sesión previa activa.
  void _checkCurrentUser() {
    final user = _authService.currentUser;
    if (user != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
      );
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Inicia sesión con Google (solo @colima.tecnm.mx).
  Future<void> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final user = await _authService.signInWithGoogle();

      if (user != null) {
        state = AuthState(
          status: AuthStatus.authenticated,
          user: user,
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
