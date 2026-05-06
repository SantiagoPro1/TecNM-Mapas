const express = require('express');
const { getDirections } = require('../controllers/directions.controller');

const router = express.Router();

/**
 * GET /api/directions
 * Obtiene las direcciones entre dos puntos
 * 
 * Query Parameters:
 * - origin: Coordenadas o dirección de origen (ej: "19.261914,-103.723674")
 * - destination: Coordenadas o dirección de destino
 * - mode: Modo de transporte (walking, driving, bicycling, transit)
 * - key: API Key de Google Maps (opcional, usa la del servidor si no se proporciona)
 */
router.get('/', getDirections);

module.exports = router;
