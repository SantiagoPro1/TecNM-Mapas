require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');

const authRoutes = require('./src/routes/auth.routes');
const healthRoutes = require('./src/routes/health.routes');
const directionsRoutes = require('./src/routes/directions.routes');

const app = express();
const PORT = process.env.PORT || 3000;

// ─── Middleware Global ────────────────────────────────────────
app.use(cors()); // Permitir todo en desarrollo
app.use(helmet({
  crossOriginResourcePolicy: { policy: "cross-origin" }
}));
app.use(express.json({ limit: '1mb' }));

// ─── Rutas ────────────────────────────────────────────────────
app.use('/api/health', healthRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/directions', directionsRoutes);

// ─── Error Handler Global ─────────────────────────────────────
app.use((err, req, res, next) => {
  console.error(`[ERROR] ${err.message}`);
  res.status(err.status || 500).json({
    success: false,
    error: process.env.NODE_ENV === 'production'
      ? 'Error interno del servidor'
      : err.message,
  });
});

// ─── Iniciar Servidor ─────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`🚀 SINAIT Backend corriendo en puerto ${PORT}`);
  console.log(`📍 Entorno: ${process.env.NODE_ENV || 'development'}`);
});

module.exports = app;
