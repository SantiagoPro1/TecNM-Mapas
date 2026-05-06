const express = require('express');
const router = express.Router();
const authController = require('../controllers/auth.controller');
const { verifyFirebaseToken } = require('../middleware/auth.middleware');

// POST /api/auth/verify-credential
// Valida un JWT de credencial digital escaneado
router.post('/verify-credential', authController.verifyCredential);

// POST /api/auth/verify-firebase
// Valida un token de Firebase Auth (para sincronización)
router.post('/verify-firebase', verifyFirebaseToken, authController.verifyFirebaseUser);

module.exports = router;
