const fs = require('fs');
const path = require('path');

function haversineDistance(coords1, coords2) {
  function toRad(x) {
    return x * Math.PI / 180;
  }
  const lon1 = coords1.lng;
  const lat1 = coords1.lat;
  const lon2 = coords2.lng;
  const lat2 = coords2.lat;
  const R = 6371; // km
  const x1 = lat2 - lat1;
  const dLat = toRad(x1);
  const x2 = lon2 - lon1;
  const dLon = toRad(x2);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const d = R * c;
  return d * 1000; // metros
}

const bundlePath = path.join(__dirname, '../app/assets/maps/venues_bundle.json');
const bundle = JSON.parse(fs.readFileSync(bundlePath, 'utf8'));

let edgesFixed = 0;

for (const venue of Object.values(bundle.venues)) {
  const nodesMap = {};
  for (const node of venue.nodes) {
    nodesMap[node.id] = node;
  }
  
  for (const edge of venue.edges) {
    const fromNode = nodesMap[edge.from];
    const toNode = nodesMap[edge.to];
    if (fromNode && toNode) {
      const correctDist = haversineDistance(fromNode, toNode);
      if (Math.abs(edge.distance - correctDist) > 1.0) { // si la diferencia es mayor a 1 metro
        edge.distance = Number(correctDist.toFixed(2));
        edgesFixed++;
      }
    }
  }
}

fs.writeFileSync(bundlePath, JSON.stringify(bundle, null, 2));
console.log(`Fijadas ${edgesFixed} aristas con la distancia real.`);
