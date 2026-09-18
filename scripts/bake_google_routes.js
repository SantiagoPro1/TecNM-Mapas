const fs = require('fs');
const path = require('path');
const https = require('https');
require('dotenv').config();

const API_KEY = process.env.GOOGLE_MAPS_API_KEY;

if (!API_KEY) {
  console.error('Falta GOOGLE_MAPS_API_KEY. Copia .env.example a .env y pon tu clave.');
  process.exit(1);
}
const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');

const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));

// Decode Google polyline to array of [lat, lng]
function decodePolyline(encoded) {
  let points = [];
  let index = 0, len = encoded.length;
  let lat = 0, lng = 0;
  while (index < len) {
    let b, shift = 0, result = 0;
    do { b = encoded.charAt(index++).charCodeAt(0) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    let dlat = ((result & 1) ? ~(result >> 1) : (result >> 1));
    lat += dlat;
    shift = 0; result = 0;
    do { b = encoded.charAt(index++).charCodeAt(0) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    let dlng = ((result & 1) ? ~(result >> 1) : (result >> 1));
    lng += dlng;
    points.push([lat / 1e5, lng / 1e5]);
  }
  return points;
}

function fetchGoogleRoute(lat1, lng1, lat2, lng2) {
  return new Promise((resolve) => {
    const data = JSON.stringify({
      origin: { location: { latLng: { latitude: lat1, longitude: lng1 } } },
      destination: { location: { latLng: { latitude: lat2, longitude: lng2 } } },
      travelMode: "WALK"
    });
    
    const options = {
      hostname: 'routes.googleapis.com',
      port: 443,
      path: '/directions/v2:computeRoutes',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': API_KEY,
        'X-Goog-FieldMask': 'routes.polyline.encodedPolyline'
      }
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          if (json.routes && json.routes.length > 0 && json.routes[0].polyline) {
            resolve(decodePolyline(json.routes[0].polyline.encodedPolyline));
          } else {
            resolve(null);
          }
        } catch(e) { resolve(null); }
      });
    });
    req.on('error', () => resolve(null));
    req.write(data);
    req.end();
  });
}

async function main() {
  let nodesMap = {};
  for (let v of Object.values(bundle.venues)) {
    for (let node of v.nodes) {
      nodesMap[node.id] = node;
    }
  }

  let totalEdges = 0;
  for (let v of Object.values(bundle.venues)) {
    totalEdges += v.edges.length;
  }
  
  console.log(`Baking Google Routes for ${totalEdges} edges...`);
  
  let routeCache = {}; // "id1-id2" -> points

  let edgesProcessed = 0;
  let edgesUpdated = 0;

  for (let v of Object.values(bundle.venues)) {
    for (let i = 0; i < v.edges.length; i++) {
      let edge = v.edges[i];
      let n1 = nodesMap[edge.from];
      let n2 = nodesMap[edge.to];
      if (!n1 || !n2) continue;

      // Skip very short edges (< 8 meters), straight line is fine
      if (edge.distance < 8) continue;

      let key = [edge.from, edge.to].sort().join('-');
      
      let points = routeCache[key];
      if (points === undefined) {
        points = await fetchGoogleRoute(n1.lat, n1.lng, n2.lat, n2.lng);
        routeCache[key] = points;
        
        // Sleep 5ms to avoid spamming too hard
        await new Promise(r => setTimeout(r, 5));
      }

      edgesProcessed++;
      if (edgesProcessed % 100 === 0) console.log(`Processed ${edgesProcessed}/${totalEdges}`);

      if (points) {
        // If the direction is reversed compared to the fetch, reverse the points
        // Actually, Google might give points that don't match exactly the start/end,
        // but for drawing, reversing the array if edge.from was not the fetch origin is correct.
        // Wait, the cache key sorted them. So n1.id might be first or second.
        let isReversed = [edge.from, edge.to].sort()[0] !== edge.from;
        
        edge.polylinePoints = isReversed ? [...points].reverse() : points;
        edgesUpdated++;
      }
    }
  }

  fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2));
  console.log(`Done! Updated ${edgesUpdated} edges with Google Maps polylines.`);
}

main();
