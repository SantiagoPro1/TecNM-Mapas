/**
 * Descarga UNA VEZ las fotos de Google Places (New) referenciadas en
 * `imageUrl` dentro de venues_bundle.json, y las guarda como archivos JPG
 * locales en app/assets/places/<placeId>.jpg.
 *
 * Por qué: Places Photos es un endpoint facturable por cada carga. La app
 * nunca debe llamarlo en vivo desde miles de celulares durante el evento.
 * Descargando una vez y empaquetando el JPG en el APK, el costo es fijo (una
 * sola descarga aquí) y el punto queda disponible sin internet — igual que
 * el resto de los assets del proyecto (ver place_visuals.dart).
 *
 * Después de correr esto, el campo `imageUrl` se elimina del bundle: ya no
 * hace falta (y no debe quedar apuntando a un endpoint facturable que la app
 * jamás debe llamar directamente).
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
require('dotenv').config();

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');
const DEST_DIR = path.join(__dirname, '../app/assets/places');

function download(url, destPath) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      // La API de fotos responde con un 302 hacia la imagen real.
      if (res.statusCode === 302 || res.statusCode === 301) {
        res.resume();
        return download(res.headers.location, destPath).then(resolve, reject);
      }
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      const file = fs.createWriteStream(destPath);
      res.pipe(file);
      file.on('finish', () => file.close(() => resolve()));
      file.on('error', reject);
    }).on('error', reject);
  });
}

async function main() {
  if (!fs.existsSync(DEST_DIR)) fs.mkdirSync(DEST_DIR, { recursive: true });

  const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));

  let total = 0;
  let ok = 0;
  let fail = 0;

  for (const [zoneId, venue] of Object.entries(bundle.venues)) {
    if (!venue.places) continue;
    for (const place of venue.places) {
      if (!place.imageUrl) continue;
      total++;
      const destPath = path.join(DEST_DIR, `${place.id}.jpg`);
      try {
        await download(place.imageUrl, destPath);
        console.log(`✅ [${zoneId}] ${place.name} -> ${place.id}.jpg`);
        ok++;
      } catch (e) {
        console.log(`❌ [${zoneId}] ${place.name}: ${e.message}`);
        fail++;
      }
      // Quitar el campo: ya no debe apuntar a un endpoint facturable.
      delete place.imageUrl;
      await new Promise((r) => setTimeout(r, 150));
    }
  }

  fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');

  console.log(`\n✨ Completado. Total: ${total}, OK: ${ok}, Fallidas: ${fail}`);
}

main().catch(console.error);
