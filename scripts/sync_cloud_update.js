/**
 * sync_cloud_update.js
 * Sincroniza los metadatos de versión en Firestore (app_meta/app_update)
 * para que todos los dispositivos con la app instalada reciban
 * la notificación de actualización automática in-app.
 */

const path = require('path');
const admin = require(path.join(__dirname, '../backend/node_modules/firebase-admin'));

// Argumentos CLI
const args = process.argv.slice(2);
function getArg(flag, defaultValue = '') {
  const index = args.indexOf(flag);
  if (index !== -1 && index + 1 < args.length) {
    return args[index + 1];
  }
  return defaultValue;
}

const version = getArg('--version');
const build = parseInt(getArg('--build'), 10);
const notes = getArg('--notes', 'Mejoras continuas de rendimiento, interfaz y mapas.');
const apkUrl = getArg('--apkUrl', 'https://storage.googleapis.com/tecnm-mapas-updates/TecNM_Mapas.apk');
const mandatory = args.includes('--mandatory');

if (!version || isNaN(build)) {
  console.error('Uso: node sync_cloud_update.js --version <X.Y.Z> --build <N> [--notes "<texto>"] [--apkUrl "<url>"] [--mandatory]');
  process.exit(1);
}

const projectId = process.env.FIREBASE_PROJECT_ID || 'exemplary-datum-397601';

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();

async function syncUpdate() {
  console.log(`[Cloud Sync] Conectando a Firestore proyecto: ${projectId}...`);
  console.log(`[Cloud Sync] Sincronizando versión ${version} (Build ${build})...`);

  const docRef = db.collection('app_meta').doc('app_update');
  const payload = {
    latestVersion: version,
    latestBuildNumber: build,
    apkUrl: apkUrl,
    releaseNotes: notes,
    mandatory: mandatory,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await docRef.set(payload, { merge: true });

  const updatedDoc = await docRef.get();
  console.log('[Cloud Sync] ¡Metadatos actualizados exitosamente en Firestore!');
  console.log(JSON.stringify(updatedDoc.data(), null, 2));
}

syncUpdate().catch((err) => {
  console.error('[Cloud Sync ERROR]:', err.message);
  process.exit(1);
});
