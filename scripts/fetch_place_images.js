/**
 * Script para buscar imágenes de lugares deportivos usando Google Places API
 * y actualizar el bundle con las URLs de las imágenes.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
require('dotenv').config();

// Tu API key de Google Maps (también funciona para Places API)
const GOOGLE_API_KEY = process.env.GOOGLE_MAPS_API_KEY || '';

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');

/**
 * Busca un lugar en Google Places API y devuelve la URL de la primera foto
 */
async function buscarImagenLugar(nombre, lat, lng) {
  return new Promise((resolve, reject) => {
    // Primero buscar el place_id
    const searchUrl = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&radius=100&keyword=${encodeURIComponent(nombre)}&key=${GOOGLE_API_KEY}`;

    https.get(searchUrl, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);

          if (json.status !== 'OK' || !json.results || json.results.length === 0) {
            console.log(`⚠️  No se encontró: ${nombre}`);
            resolve(null);
            return;
          }

          const place = json.results[0];

          // Si tiene fotos, construir la URL
          if (place.photos && place.photos.length > 0) {
            const photoReference = place.photos[0].photo_reference;
            const photoUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photo_reference=${photoReference}&key=${GOOGLE_API_KEY}`;
            console.log(`✅ Encontrado: ${nombre}`);
            resolve(photoUrl);
          } else {
            console.log(`⚠️  Sin fotos: ${nombre}`);
            resolve(null);
          }
        } catch (error) {
          console.error(`❌ Error parseando: ${nombre}`, error);
          resolve(null);
        }
      });
    }).on('error', (error) => {
      console.error(`❌ Error de red: ${nombre}`, error);
      resolve(null);
    });
  });
}

/**
 * Procesa el bundle y agrega imágenes a los lugares
 */
async function procesarBundle() {
  console.log('📦 Cargando bundle...');
  const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));

  let procesados = 0;
  let conImagen = 0;

  for (const [zoneId, venue] of Object.entries(bundle.venues)) {
    console.log(`\n🏟️  Procesando sede: ${zoneId}`);

    if (!venue.places) continue;

    for (const place of venue.places) {
      procesados++;

      // Saltar corredores y puntos genéricos
      if (place.type === 'Corredor' || place.name.includes('Corredor')) {
        continue;
      }

      // Buscar imagen
      const imageUrl = await buscarImagenLugar(place.name, place.latitude, place.longitude);

      if (imageUrl) {
        place.imageUrl = imageUrl;
        conImagen++;
      }

      // Delay para no saturar la API
      await new Promise(resolve => setTimeout(resolve, 500));
    }
  }

  // Guardar bundle actualizado
  fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');

  console.log(`\n✨ Completado!`);
  console.log(`   Lugares procesados: ${procesados}`);
  console.log(`   Con imagen: ${conImagen}`);
  console.log(`   Sin imagen: ${procesados - conImagen}`);
}

// Ejecutar
procesarBundle().catch(console.error);
