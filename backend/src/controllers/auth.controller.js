const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'SINAIT_TecNM_2026_SecretKey';

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

      if (parts[2] !== expectedSig) {
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
  const input = `${data}.${JWT_SECRET}`;
  let hash = 0;
  for (let i = 0; i < input.length; i++) {
    hash = ((hash << 5) - hash + input.charCodeAt(i)) & 0xFFFFFFFF;
  }
  // Convert to unsigned
  hash = hash >>> 0;

  const input2 = `${hash.toString(16)}.${JWT_SECRET}`;
  let hash2 = 0;
  for (let i = 0; i < input2.length; i++) {
    hash2 = ((hash2 << 5) - hash2 + input2.charCodeAt(i)) & 0xFFFFFFFF;
  }
  hash2 = hash2 >>> 0;

  return `${hash.toString(16)}${hash2.toString(16)}`;
}

module.exports = authController;
