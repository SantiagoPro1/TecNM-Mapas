const jwt = require('jsonwebtoken');
const crypto = require('crypto');

// Clave compartida con la app (credential_service.dart lee CREDENTIAL_SECRET
// de su propio .env). Antes este archivo usaba JWT_SECRET, que valía
// 'SINAIT_TecNM_2026_SecretKey', mientras la app firmaba con
// 'NAVIA_TecNM_2026_SecretKey': ninguna credencial escaneada podía verificar.
const CREDENTIAL_SECRET =
  process.env.CREDENTIAL_SECRET || 'NAVIA_TecNM_2026_SecretKey';

/**
 * Controlador de autenticación.
 *
 * Maneja la verificación de credenciales digitales JWT
 * y la validación de tokens de Firebase.
 */
const authController = {

  /**
   * POST /api/auth/verify-credential
   *
   * Verifica un JWT de credencial digital del alumno.
   * El QR de la app genera tokens con TTL de 60 segundos.
   *
   * Body: { token: "eyJhbGciOi..." }
   */
  verifyCredential: (req, res) => {
    try {
      const { token } = req.body;

      if (!token) {
        return res.status(400).json({
          success: false,
          error: 'Token de credencial requerido',
        });
      }

      // Decodificar y verificar el JWT
      const parts = token.split('.');
      if (parts.length !== 3) {
        return res.status(400).json({
          success: false,
          error: 'Formato de token inválido',
        });
      }

      // Decodificar payload
      const payloadStr = Buffer.from(parts[1], 'base64url').toString('utf-8');
      const payload = JSON.parse(payloadStr);

      // Verificar expiración
      const now = Math.floor(Date.now() / 1000);
      if (payload.exp && now > payload.exp) {
        return res.status(401).json({
          success: false,
          error: 'Credencial expirada',
          expired: true,
        });
      }

      // Verificar que es un token de tipo student_credential
      if (payload.type !== 'student_credential') {
        return res.status(400).json({
          success: false,
          error: 'Tipo de token no válido',
        });
      }

      // Verificar la firma (recalcular y comparar)
      const dataToSign = `${parts[0]}.${parts[1]}`;
      const expectedSig = _simpleSign(dataToSign);

      if (!_firmasIguales(parts[2], expectedSig)) {
        return res.status(401).json({
          success: false,
          error: 'Firma de credencial inválida',
        });
      }

      // Token válido
      return res.json({
        success: true,
        student: {
          matricula: payload.sub,
          name: payload.name,
          campus: payload.campus,
          issuedAt: new Date(payload.iat * 1000).toISOString(),
          expiresAt: new Date(payload.exp * 1000).toISOString(),
        },
      });
    } catch (err) {
      return res.status(500).json({
        success: false,
        error: 'Error verificando credencial',
      });
    }
  },

  /**
   * POST /api/auth/verify-firebase
   *
   * Verifica un usuario autenticado con Firebase.
   * El middleware verifyFirebaseToken ya validó el token.
   *
   * Retorna los datos del usuario.
   */
  verifyFirebaseUser: (req, res) => {
    // req.firebaseUser fue establecido por el middleware
    const user = req.firebaseUser;

    return res.json({
      success: true,
      user: {
        uid: user.uid,
        email: user.email,
        name: user.name || user.display_name || 'Estudiante TecNM',
        emailVerified: user.email_verified,
        campus: 'TecNM Colima',
      },
    });
  },
};

/**
 * Firma simplificada compatible con el CredentialService de Flutter.
 * Debe producir el mismo resultado que _sign() en credential_service.dart.
 */
function _simpleSign(data) {
  return crypto
    .createHmac('sha256', CREDENTIAL_SECRET)
    .update(data)
    .digest('base64url')
    .replace(/=/g, '');
}

/**
 * Compara dos firmas sin filtrar información por el tiempo de ejecución.
 *
 * Un `===` normal corta en el primer byte distinto, así que el tiempo de
 * respuesta revela cuántos bytes acertó quien lo intenta — con suficientes
 * escaneos se puede reconstruir una firma byte por byte. `timingSafeEqual`
 * siempre tarda lo mismo.
 */
function _firmasIguales(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

module.exports = authController;
