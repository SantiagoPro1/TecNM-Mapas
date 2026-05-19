const axios = require('axios');

/**
 * Decodifica un polyline encoded (formato Google) a array de {lat, lng}.
 * @param {string} encoded
 * @returns {{lat: number, lng: number}[]}
 */
function decodePolyline(encoded) {
  const points = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let byte;

    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    const deltaLat = result & 1 ? ~(result >> 1) : result >> 1;
    lat += deltaLat;

    shift = 0;
    result = 0;

    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    const deltaLng = result & 1 ? ~(result >> 1) : result >> 1;
    lng += deltaLng;

    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }

  return points;
}

/**
 * GET /api/directions
 * Proxy hacia Google Routes API v2 (computeRoutes).
 * Query params: origin, destination, mode (walking|driving|bicycling|transit)
 */
const getDirections = async (req, res) => {
  try {
    const { origin, destination, mode = 'walking' } = req.query;

    if (!origin || !destination) {
      return res.status(400).json({
        success: false,
        error: 'origin y destination son requeridos',
      });
    }

    const apiKey = process.env.GOOGLE_MAPS_API_KEY;
    if (!apiKey) {
      return res.status(500).json({
        success: false,
        error: 'GOOGLE_MAPS_API_KEY no configurada en el servidor',
      });
    }

    // Parsear coordenadas "lat,lng"
    const [originLat, originLng] = origin.split(',').map(Number);
    const [destLat, destLng] = destination.split(',').map(Number);

    if (isNaN(originLat) || isNaN(originLng) || isNaN(destLat) || isNaN(destLng)) {
      return res.status(400).json({
        success: false,
        error: 'Formato de coordenadas inválido. Use "lat,lng"',
      });
    }

    // Mapear modo de transporte al formato Routes API
    const travelModeMap = {
      walking: 'WALK',
      driving: 'DRIVE',
      bicycling: 'BICYCLE',
      transit: 'TRANSIT',
    };
    const travelMode = travelModeMap[mode.toLowerCase()] ?? 'WALK';

    const requestBody = {
      origin: {
        location: {
          latLng: { latitude: originLat, longitude: originLng },
        },
      },
      destination: {
        location: {
          latLng: { latitude: destLat, longitude: destLng },
        },
      },
      travelMode,
      polylineEncoding: 'ENCODED_POLYLINE',
      routingPreference: travelMode === 'DRIVE' ? 'TRAFFIC_AWARE' : undefined,
    };

    const response = await axios.post(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
      requestBody,
      {
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask':
            'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.legs',
        },
      }
    );

    const routes = response.data.routes;
    if (!routes || routes.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'No se encontró ninguna ruta entre los puntos indicados',
      });
    }

    const route = routes[0];
    const encodedPolyline = route.polyline?.encodedPolyline ?? '';
    const points = decodePolyline(encodedPolyline);

    // Duración viene como "123s" en Routes API v2
    const durationSeconds = route.duration
      ? parseInt(route.duration.replace('s', ''), 10)
      : 0;

    res.json({
      success: true,
      data: {
        points,
        distance: route.distanceMeters ?? 0,
        duration: durationSeconds,
        summary: `Ruta de ${Math.round((route.distanceMeters ?? 0))} m · ${Math.round(durationSeconds / 60)} min`,
      },
    });
  } catch (error) {
    console.error('[ROUTES API ERROR]:', error.response?.data ?? error.message);
    res.status(500).json({
      success: false,
      error: 'Error interno al obtener direcciones',
      details:
        process.env.NODE_ENV === 'development'
          ? (error.response?.data ?? error.message)
          : undefined,
    });
  }
};

module.exports = { getDirections };
