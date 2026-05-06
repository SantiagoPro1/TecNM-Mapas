const express = require('express');
const router = express.Router();

// GET /api/health
// Health check para verificar que el servidor está activo
router.get('/', (req, res) => {
  res.json({
    success: true,
    service: 'SINAIT Backend',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

module.exports = router;
