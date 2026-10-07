/**
 * sync_and_rebuild_routes.js
 * 
 * Sincroniza todas las modificaciones realizadas por el administrador en Firestore
 * con los archivos locales del bundle (venues_bundle.json y tec_colima_map.json).
 * 
 * Reglas de oro del grafo:
 * 1. Cada POI (destino) se conecta a su nodo de corredor más cercano (su acceso/puerta).
 * 2. Un POI NUNCA se conecta a otro POI, ni tiene múltiples conexiones que permitan
 *    usarlo como atajo o puente intermedio entre otros dos puntos.
 * 3. Los corredores forman una malla peatonal 100% conectada y densificada con
 *    curvas suaves para el motor de navegación estilo Google Maps.
 */

const fs = require('fs');
const path = require('path');
const admin = require(path.join(__dirname, '../backend/node_modules/firebase-admin'));

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'exemplary-datum-397601';
if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}
const db = admin.firestore();

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');
const TEC_MAP_PATH = path.join(__dirname, '../app/assets/maps/tec_colima_map.json');

function haversineMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000; // metros
  const toRad = x => (x * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// Genera puntos intermedios cada ~8-10 metros para curvas suaves
function densifyPolyline(p1, p2, maxStepMeters = 8) {
  const dist = haversineMeters(p1.lat, p1.lng, p2.lat, p2.lng);
  if (dist <= maxStepMeters) {
    return [
      [Number(p1.lat.toFixed(6)), Number(p1.lng.toFixed(6))],
      [Number(p2.lat.toFixed(6)), Number(p2.lng.toFixed(6))]
    ];
  }
  const steps = Math.ceil(dist / maxStepMeters);
  const points = [];
  for (let s = 0; s <= steps; s++) {
    const t = s / steps;
    const lat = p1.lat + t * (p2.lat - p1.lat);
    const lng = p1.lng + t * (p2.lng - p1.lng);
    points.push([Number(lat.toFixed(6)), Number(lng.toFixed(6))]);
  }
  return points;
}

async function run() {
  console.log('=== INICIANDO SINCRONIZACIÓN Y RECONSTRUCCIÓN DE RUTAS ===');
  const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));
  const tecMap = JSON.parse(fs.readFileSync(TEC_MAP_PATH, 'utf8'));

  const venueIds = Object.keys(bundle.venues);
  const currentVersion = bundle.dataVersion || 1000021;
  const newVersion = currentVersion + 1;
  console.log(`Versión actual del bundle: ${currentVersion} -> Nueva versión: ${newVersion}`);

  for (const vid of venueIds) {
    console.log(`\n------------------------------------------------------------`);
    console.log(`Procesando sede: [${vid}]`);
    const venueData = bundle.venues[vid];

    // 1. Obtener datos actuales de Firestore para esta sede
    const fsPlacesSnap = await db.collection('venues').doc(vid).collection('places').get();
    const fsNodesSnap = await db.collection('venues').doc(vid).collection('nodes').get();

    const deletedIds = new Set();
    const modifiedPlaces = new Map();
    const modifiedNodes = new Map();

    fsPlacesSnap.forEach(d => {
      const data = d.data();
      if (data.deleted === true) {
        deletedIds.add(d.id);
      } else if (data.latitude !== undefined || data.lat !== undefined) {
        modifiedPlaces.set(d.id, {
          id: d.id,
          name: data.name || '',
          latitude: data.latitude !== undefined ? data.latitude : data.lat,
          longitude: data.longitude !== undefined ? data.longitude : data.lng,
          type: data.type || 'Punto',
          accessibilityLevel: data.accessibilityLevel || 'alto',
          letter: data.letter || null,
          imageUrl: data.imageUrl || null
        });
      }
    });

    fsNodesSnap.forEach(d => {
      const data = d.data();
      if (data.deleted === true) {
        deletedIds.add(d.id);
      } else if (data.lat !== undefined || data.latitude !== undefined) {
        modifiedNodes.set(d.id, {
          id: d.id,
          name: data.name || '',
          lat: data.lat !== undefined ? data.lat : data.latitude,
          lng: data.lng !== undefined ? data.lng : data.longitude,
          type: data.type || 'building',
          accessible: data.accessible !== undefined ? data.accessible : true,
          aliases: data.aliases || [],
          floor: data.floor || 0,
          description: data.description || '',
          zoneId: vid
        });
      }
    });

    console.log(`  - Puntos eliminados: ${deletedIds.size} (${Array.from(deletedIds).join(', ') || 'ninguno'})`);
    console.log(`  - Puntos modificados/agregados en places: ${modifiedPlaces.size}`);
    console.log(`  - Puntos modificados/agregados en nodes: ${modifiedNodes.size}`);

    // 2. Limpiar lugares y nodos del bundle local
    let places = venueData.places.filter(p => !deletedIds.has(p.id));
    const placesMap = new Map();
    places.forEach(p => placesMap.set(p.id, p));
    for (const [id, mp] of modifiedPlaces.entries()) {
      placesMap.set(id, {
        id: mp.id,
        name: mp.name,
        latitude: mp.latitude,
        longitude: mp.longitude,
        type: mp.type,
        accessibilityLevel: mp.accessibilityLevel,
        letter: mp.letter,
        imageUrl: mp.imageUrl
      });
    }
    places = Array.from(placesMap.values());
    const poiIds = new Set(places.map(p => p.id));

    // Nodos
    let nodes = venueData.nodes.filter(n => !deletedIds.has(n.id));
    const nodesMap = new Map();
    nodes.forEach(n => nodesMap.set(n.id, n));
    for (const [id, mn] of modifiedNodes.entries()) {
      const existing = nodesMap.get(id) || {};
      nodesMap.set(id, {
        id: mn.id,
        zoneId: vid,
        name: mn.name || existing.name || '',
        aliases: mn.aliases || existing.aliases || [],
        type: mn.type || existing.type || (poiIds.has(id) ? 'building' : 'corridor'),
        lat: mn.lat,
        lng: mn.lng,
        floor: mn.floor || existing.floor || 0,
        accessible: mn.accessible !== undefined ? mn.accessible : (existing.accessible !== undefined ? existing.accessible : true),
        description: mn.description || existing.description || ''
      });
    }
    // Asegurar que cada place tenga su nodo correspondiente en el grafo
    for (const p of places) {
      if (!nodesMap.has(p.id)) {
        nodesMap.set(p.id, {
          id: p.id,
          zoneId: vid,
          name: p.name,
          aliases: [],
          type: 'building',
          lat: p.latitude,
          lng: p.longitude,
          floor: 0,
          accessible: true,
          description: ''
        });
      } else {
        const n = nodesMap.get(p.id);
        n.lat = p.latitude;
        n.lng = p.longitude;
        if (p.name) n.name = p.name;
        if (n.type === 'corridor') n.type = 'building';
      }
    }
    nodes = Array.from(nodesMap.values());

    const corridorNodes = nodes.filter(n => n.type === 'corridor' && !poiIds.has(n.id));
    console.log(`  - Nodos activos: ${nodes.length} (Corredores: ${corridorNodes.length}), Lugares activos: ${places.length}`);

    // 3. Aristas entre corredores exclusivamente
    let corridorEdges = venueData.edges.filter(e => {
      if (deletedIds.has(e.from) || deletedIds.has(e.to)) return false;
      if (poiIds.has(e.from) || poiIds.has(e.to)) return false; // Excluir aristas de POIs
      if (!nodesMap.has(e.from) || !nodesMap.has(e.to)) return false;
      return true;
    });

    // Enlaces de corredores críticos para evitar rodeos absurdos:
    if (vid === 'sur' && nodesMap.has('sur_w55') && nodesMap.has('sur_w72')) {
      const n1 = nodesMap.get('sur_w55');
      const n2 = nodesMap.get('sur_w72');
      const poly = densifyPolyline(n1, n2);
      const d = Number(haversineMeters(n1.lat, n1.lng, n2.lat, n2.lng).toFixed(2));
      corridorEdges.push({ from: n1.id, to: n2.id, distance: d, accessible: true, type: 'outdoor', polylinePoints: poly });
      corridorEdges.push({ from: n2.id, to: n1.id, distance: d, accessible: true, type: 'outdoor', polylinePoints: [...poly].reverse() });
    }
    if (vid === 'gil_cabrera' && nodesMap.has('gil_cabrera_w26') && nodesMap.has('gil_cabrera_w168')) {
      const n1 = nodesMap.get('gil_cabrera_w26');
      const n2 = nodesMap.get('gil_cabrera_w168');
      const poly = densifyPolyline(n1, n2);
      const d = Number(haversineMeters(n1.lat, n1.lng, n2.lat, n2.lng).toFixed(2));
      corridorEdges.push({ from: n1.id, to: n2.id, distance: d, accessible: true, type: 'outdoor', polylinePoints: poly });
      corridorEdges.push({ from: n2.id, to: n1.id, distance: d, accessible: true, type: 'outdoor', polylinePoints: [...poly].reverse() });
    }

    // Asegurar que los corredores estén 100% conectados entre sí
    const corrAdj = new Map();
    for (const c of corridorNodes) corrAdj.set(c.id, new Set());
    for (const e of corridorEdges) {
      if (corrAdj.has(e.from)) corrAdj.get(e.from).add(e.to);
    }

    if (corridorNodes.length > 0) {
      const visited = new Set();
      const queue = [corridorNodes[0].id];
      visited.add(corridorNodes[0].id);
      while (queue.length > 0) {
        const cur = queue.shift();
        const nbrs = corrAdj.get(cur) || new Set();
        for (const nxt of nbrs) {
          if (!visited.has(nxt)) {
            visited.add(nxt);
            queue.push(nxt);
          }
        }
      }

      for (const c of corridorNodes) {
        if (!visited.has(c.id)) {
          let bestVis = null, bestD = Infinity;
          for (const vId of visited) {
            const vNode = nodesMap.get(vId);
            if (!vNode) continue;
            const d = haversineMeters(c.lat, c.lng, vNode.lat, vNode.lng);
            if (d < bestD) { bestD = d; bestVis = vNode; }
          }
          if (bestVis) {
            const poly = densifyPolyline(c, bestVis);
            const dist = Number(bestD.toFixed(2));
            corridorEdges.push({
              from: c.id,
              to: bestVis.id,
              distance: dist,
              accessible: true,
              type: 'outdoor',
              polylinePoints: poly
            });
            corridorEdges.push({
              from: bestVis.id,
              to: c.id,
              distance: dist,
              accessible: true,
              type: 'outdoor',
              polylinePoints: [...poly].reverse()
            });
            visited.add(c.id);
            if (corrAdj.has(c.id)) corrAdj.get(c.id).add(bestVis.id);
            if (corrAdj.has(bestVis.id)) corrAdj.get(bestVis.id).add(c.id);
          }
        }
      }
    }

    // 4. Conectar CADA POI a EXACTAMENTE UN corredor más cercano (su puerta/acceso)
    const poiEdges = [];
    for (const place of places) {
      const pNode = nodesMap.get(place.id);
      if (!pNode) continue;

      let bestCorr = null, bestD = Infinity;
      for (const c of corridorNodes) {
        const d = haversineMeters(pNode.lat, pNode.lng, c.lat, c.lng);
        if (d < bestD) {
          bestD = d;
          bestCorr = c;
        }
      }

      if (bestCorr) {
        const poly = densifyPolyline(pNode, bestCorr);
        const dist = Number(bestD.toFixed(2));
        poiEdges.push({
          from: pNode.id,
          to: bestCorr.id,
          distance: dist,
          accessible: true,
          type: 'outdoor',
          polylinePoints: poly
        });
        poiEdges.push({
          from: bestCorr.id,
          to: pNode.id,
          distance: dist,
          accessible: true,
          type: 'outdoor',
          polylinePoints: [...poly].reverse()
        });
      }
    }

    // 5. Unir y normalizar todas las aristas
    const allEdges = [...corridorEdges, ...poiEdges];
    const edgeMap = new Map();
    for (const e of allEdges) {
      const key = `${e.from}__${e.to}`;
      edgeMap.set(key, e);
    }

    for (const e of Array.from(edgeMap.values())) {
      const revKey = `${e.to}__${e.from}`;
      const fromNode = nodesMap.get(e.from);
      const toNode = nodesMap.get(e.to);
      if (!fromNode || !toNode) {
        edgeMap.delete(`${e.from}__${e.to}`);
        continue;
      }

      const exactDist = Number(haversineMeters(fromNode.lat, fromNode.lng, toNode.lat, toNode.lng).toFixed(2));
      e.distance = exactDist;

      if (!e.polylinePoints || e.polylinePoints.length < 2) {
        e.polylinePoints = densifyPolyline(fromNode, toNode);
      } else {
        e.polylinePoints[0] = [Number(fromNode.lat.toFixed(6)), Number(fromNode.lng.toFixed(6))];
        e.polylinePoints[e.polylinePoints.length - 1] = [Number(toNode.lat.toFixed(6)), Number(toNode.lng.toFixed(6))];
      }

      if (!edgeMap.has(revKey)) {
        const revPoly = [...e.polylinePoints].reverse();
        edgeMap.set(revKey, {
          from: e.to,
          to: e.from,
          distance: exactDist,
          accessible: e.accessible !== undefined ? e.accessible : true,
          type: e.type || 'outdoor',
          polylinePoints: revPoly
        });
      }
    }

    const finalEdges = Array.from(edgeMap.values());
    console.log(`  - Aristas finales bidireccionales: ${finalEdges.length}`);

    // 6. Actualizar bundle y tec_colima_map
    venueData.places = places;
    venueData.nodes = nodes;
    venueData.edges = finalEdges;

    if (vid === 'tec_colima') {
      tecMap.nodes = nodes;
      tecMap.edges = finalEdges;
      fs.writeFileSync(TEC_MAP_PATH, JSON.stringify(tecMap, null, 2), 'utf8');
      console.log(`  -> tec_colima_map.json actualizado.`);
    }

    // 7. Sincronizar en Firestore
    const batch = db.batch();
    for (const delId of deletedIds) {
      batch.delete(db.collection('venues').doc(vid).collection('nodes').doc(delId));
      batch.delete(db.collection('venues').doc(vid).collection('places').doc(delId));
    }
    for (const p of places) {
      batch.set(db.collection('venues').doc(vid).collection('places').doc(p.id), p, { merge: true });
    }
    await batch.commit();

    console.log(`  [OK] Sede ${vid} sincronizada y optimizada.`);
  }

  // 8. Guardar bundle actualizado
  bundle.dataVersion = newVersion;
  fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');
  console.log(`\n¡venues_bundle.json actualizado con dataVersion ${newVersion}!`);

  // 9. Actualizar versión en Firestore
  await db.collection('app_meta').doc('venue_data').set({
    dataVersion: newVersion,
    actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    nota: `Sincronización completa sede por sede y andadores limpios (v${newVersion})`
  }, { merge: true });

  console.log('=== SINCRONIZACIÓN Y RECONSTRUCCIÓN FINALIZADA EXITOSAMENTE ===');
}

run().catch(err => {
  console.error('ERROR EN RECONSTRUCCIÓN:', err);
  process.exit(1);
});
