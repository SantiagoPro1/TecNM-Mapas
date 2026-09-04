const admin = require('firebase-admin');

// Acepta cualquier subdominio de tecnm.mx (ej. colima.tecnm.mx,
// leon.tecnm.mx, o tecnm.mx a secas) para el Evento Nacional Deportivo,
// donde asisten estudiantes de otros campus del pais.
const TECNM_DOMAIN_PATTERN = /^[^@\s]+@([a-z0-9-]+\.)*tecnm\.mx$/i;

// Inicializar Firebase Admin SDK
// En producción, usar un service account JSON
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID || 'exemplary-datum-397601',
  });
}

/**
 * Middleware que verifica tokens de Firebase Auth.
 *
 * Extrae el token Bearer del header Authorization,
 * lo verifica con Firebase Admin SDK, y adjunta
 * los datos del usuario decodificados a req.firebaseUser.
 */
const verifyFirebaseToken = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        error: 'Token de autorización requerido',
      });
    }

    const token = authHeader.split('Bearer ')[1];

    // Verificar el token con Firebase Admin
    const decodedToken = await admin.auth().verifyIdToken(token);

    // Validar dominio institucional
    if (!TECNM_DOMAIN_PATTERN.test(decodedToken.email || '')) {
      return res.status(403).json({
        success: false,
        error: 'Solo se permiten cuentas institucionales @*.tecnm.mx',
      });
    }

    // Adjuntar datos del usuario al request
    req.firebaseUser = decodedToken;
    next();
  } catch (err) {
    console.error('[AUTH MIDDLEWARE]', err.message);

    if (err.code === 'auth/id-token-expired') {
      return res.status(401).json({
        success: false,
        error: 'Token expirado, inicia sesión de nuevo',
      });
    }

    return res.status(401).json({
      success: false,
      error: 'Token inválido',
    });
  }
};

module.exports = { verifyFirebaseToken };
