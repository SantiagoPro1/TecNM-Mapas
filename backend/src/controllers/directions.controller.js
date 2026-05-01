const axios = require('axios');

/**
 * Controlador para obtener rutas de direcciones desde Google Maps API
 * Maneja las peticiones server-to-server para evitar problemas CORS en el cliente web
 */

const getDirections = async (req, res) => {
  try {
    const { origin, destination, mode = 'walking', key } = req.query;

    if (!origin || !destination) {
      return res.status(400).json({
        success: false,
        error: 'origin y destination son requeridos',
      });
    }

    const googleMapsApiKey = key || process.env.GOOGLE_MAPS_API_KEY;
    if (!googleMapsApiKey) {
      return res.status(500).json({
        success: false,
        error: 'GOOGLE_MAPS_API_KEY no configurada en el servidor',
      });
    }

    const url = 'https://maps.googleapis.com/maps/api/directions/json';
    const params = {
      origin,
      destination,
      mode,
      key: googleMapsApiKey,
      alternatives: false,
      avoid: ['highways', 'ferries', 'tolls'],
    };

    const response = await axios.get(url, { params });
    console.log('[GOOGLE MAPS RESPONSE STATUS]:', response.data.status);

    if (response.data.status !== 'OK') {
      console.error('[GOOGLE MAPS ERROR]:', response.data.error_message);
      return res.status(400).json({
        success: false,
        error: response.data.status,
        message: response.data.error_message || 'Error al obtener direcciones',
      });
    }

    // Extraer los puntos de la ruta del primer resultado
    const route = response.data.routes[0];
    const points = [];

    if (route.legs) {
      route.legs.forEach((leg) => {
        leg.steps.forEach((step) => {
          // Decodificar polyline si es necesario, o usar los puntos finales
          const endLocation = step.end_location;
          points.push({
            lat: endLocation.lat,
            lng: endLocation.lng,
          });
        });
      });
    }

    res.json({
      success: true,
      data: {
        points,
        distance: route.legs.reduce((sum, leg) => sum + leg.distance.value, 0), // en metros
        duration: route.legs.reduce((sum, leg) => sum + leg.duration.value, 0), // en segundos
        summary: route.summary,
      },
    });
  } catch (error) {
    console.error('[DIRECTIONS ERROR]:', error.message);
    res.status(500).json({
      success: false,
      error: 'Error interno al obtener direcciones',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined,
    });
  }
};

module.exports = {
  getDirections,
};
