/**
 * Script para buscar imágenes de lugares deportivos usando Places API (New)
 * de Google y actualizar el bundle con las URLs de las imágenes.
 *
 * Usa Text Search (New) — la legacy Places API (Nearby Search) fue
 * reemplazada por Google y ya no acepta proyectos nuevos.
 * Docs: https://developers.google.com/maps/documentation/places/web-service/text-search
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
require('dotenv').config();

const GOOGLE_API_KEY = process.env.GOOGLE_MAPS_API_KEY || '';

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');

/**
 * Hace una petición POST JSON y devuelve la respuesta parseada.
 */
function postJson(url, headers, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = https.request(
      url,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
          ...headers,
        },
      },
      (res) => {
        let chunks = '';
        res.on('data', (c) => (chunks += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, json: JSON.parse(chunks) });
          } catch (e) {
            reject(e);
          }
        });
      },
    );
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

/**
 * Busca un lugar con Text Search (New) y devuelve el "name" de su primera
 * foto (formato "places/PLACE_ID/photos/PHOTO_ID"), o null si no hay match
 * o no tiene fotos.
 */
async function buscarFotoLugar(nombre, lat, lng) {
  const url = 'https://places.googleapis.com/v1/places:searchText';
  const body = {
    textQuery: nombre,
    locationBias: {
      circle: {
        center: { latitude: lat, longitude: lng },
        radius: 150.0,
      },
    },
    maxResultCount: 1,
  };

  try {
    const { status, json } = await postJson(
      url,
      {
        'X-Goog-Api-Key': GOOGLE_API_KEY,
        'X-Goog-FieldMask': 'places.displayName,places.photos',
      },
      body,
    );

    if (status !== 200) {
      console.log(`❌ Error API (${status}) en "${nombre}": ${JSON.stringify(json)}`);
      return null;
    }

    const place = json.places?.[0];
    if (!place) {
      console.log(`⚠️  No se encontró: ${nombre}`);
      return null;
    }

    const photo = place.photos?.[0];
    if (!photo) {
      console.log(`⚠️  Sin fotos: ${nombre}`);
      return null;
    }

    console.log(`✅ Encontrado: ${nombre}`);
    return photo.name; // "places/.../photos/..."
  } catch (error) {
    console.error(`❌ Error de red en "${nombre}":`, error.message);
    return null;
  }
}

/**
 * Convierte el "name" de una foto en la URL pública que sirve la imagen.
 */
function urlDeFoto(photoName) {
  return `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=800&key=${GOOGLE_API_KEY}`;
}

/**
 * Procesa el bundle y agrega imágenes a los lugares.
 */
async function procesarBundle() {
  if (!GOOGLE_API_KEY) {
    console.error('❌ Falta GOOGLE_MAPS_API_KEY en scripts/.env');
    process.exit(1);
  }

  console.log('📦 Cargando bundle...');
  const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));

  let procesados = 0;
  let conImagen = 0;

  for (const [zoneId, venue] of Object.entries(bundle.venues)) {
    console.log(`\n🏟️  Procesando sede: ${zoneId}`);

    if (!venue.places) continue;

    for (const place of venue.places) {
      procesados++;

      // Saltar corredores y puntos genéricos: no son lugares reales que
      // Google pueda encontrar, y no tiene sentido mostrarles imagen.
      if (place.type === 'Corredor' || place.name.includes('Corredor')) {
        continue;
      }

      const photoName = await buscarFotoLugar(place.name, place.latitude, place.longitude);

      if (photoName) {
        place.imageUrl = urlDeFoto(photoName);
        conImagen++;
      }

      // Delay para no saturar la API.
      await new Promise((resolve) => setTimeout(resolve, 300));
    }
  }

  fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');

  console.log(`\n✨ Completado!`);
  console.log(`   Lugares procesados: ${procesados}`);
  console.log(`   Con imagen: ${conImagen}`);
  console.log(`   Sin imagen: ${procesados - conImagen}`);
}

procesarBundle().catch(console.error);
