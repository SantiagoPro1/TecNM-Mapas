/**
 * Busca fotos REALES de Google Maps para cada punto del venues_bundle.json.
 * 
 * Estrategia:
 * 1. Para las sedes principales (unidades deportivas), busca por nombre en Google Places
 * 2. Verifica que el resultado esté cerca de las coordenadas del punto (<500m)
 * 3. Solo descarga la foto si el lugar coincide geográficamente
 * 4. Si no hay coincidencia verificada, NO pone foto (queda limpio)
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const API_KEY = 'AIzaSyDTt0U-8LaagPsho1M8Qf4Br3cMAQgIUmQ';
const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');
const PLACES_DIR = path.join(__dirname, '../app/assets/places');

// Haversine distance in meters
function haversineM(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180) * Math.cos(lat2*Math.PI/180) * Math.sin(dLon/2)**2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

function httpGet(url) {
    return new Promise((resolve, reject) => {
        https.get(url, (res) => {
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                return httpGet(res.headers.location).then(resolve).catch(reject);
            }
            const chunks = [];
            res.on('data', c => chunks.push(c));
            res.on('end', () => resolve({ status: res.statusCode, data: Buffer.concat(chunks), headers: res.headers }));
            res.on('error', reject);
        }).on('error', reject);
    });
}

async function httpGetJson(url) {
    const res = await httpGet(url);
    return JSON.parse(res.data.toString());
}

async function findPlace(query, lat, lng) {
    const encoded = encodeURIComponent(query);
    const url = `https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=${encoded}&inputtype=textquery&locationbias=circle:2000@${lat},${lng}&fields=place_id,name,geometry,photos&key=${API_KEY}`;
    const data = await httpGetJson(url);
    if (data.status !== 'OK' || !data.candidates || data.candidates.length === 0) {
        return null;
    }
    return data.candidates[0];
}

async function nearbySearch(lat, lng, keyword, radius = 500) {
    const encoded = encodeURIComponent(keyword);
    const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lng}&radius=${radius}&keyword=${encoded}&key=${API_KEY}`;
    const data = await httpGetJson(url);
    if (data.status !== 'OK' || !data.results || data.results.length === 0) {
        return null;
    }
    return data.results[0];
}

function getPhotoUrl(photoRef, maxWidth = 800) {
    return `https://maps.googleapis.com/maps/api/place/photo?maxwidth=${maxWidth}&photo_reference=${photoRef}&key=${API_KEY}`;
}

async function downloadPhoto(photoRef, destPath) {
    const url = getPhotoUrl(photoRef);
    const res = await httpGet(url);
    if (res.status === 200) {
        fs.writeFileSync(destPath, res.data);
        return true;
    }
    return false;
}

// Sleep to avoid rate limiting
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function main() {
    const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));
    
    // First, clean ALL imageUrl from bundle
    for (const [zoneId, venue] of Object.entries(bundle.venues)) {
        if (!venue.places) continue;
        for (const place of venue.places) {
            delete place.imageUrl;
        }
    }
    
    // Clean existing photos
    const existingPhotos = fs.readdirSync(PLACES_DIR).filter(f => f.endsWith('.jpg'));
    for (const f of existingPhotos) {
        fs.unlinkSync(path.join(PLACES_DIR, f));
    }
    console.log(`🗑️  Limpiadas ${existingPhotos.length} fotos anteriores`);

    let found = 0;
    let notFound = 0;
    let skippedTooFar = 0;
    
    for (const [zoneId, venue] of Object.entries(bundle.venues)) {
        if (!venue.places) continue;
        console.log(`\n=== ${zoneId} (${venue.places.length} places) ===`);
        
        for (const place of venue.places) {
            const placeId = place.id;
            const placeName = place.name;
            const lat = place.latitude;
            const lng = place.longitude;
            
            // Build search queries - try specific name first, then with city context
            const queries = [
                `${placeName} Colima`,
                placeName,
            ];
            
            let bestResult = null;
            let bestDistance = Infinity;
            
            for (const query of queries) {
                try {
                    // Try findPlace first
                    let result = await findPlace(query, lat, lng);
                    
                    if (result && result.geometry) {
                        const rLat = result.geometry.location.lat;
                        const rLng = result.geometry.location.lng;
                        const dist = haversineM(lat, lng, rLat, rLng);
                        
                        if (dist < 1000 && dist < bestDistance && result.photos && result.photos.length > 0) {
                            bestResult = result;
                            bestDistance = dist;
                        }
                    }
                    
                    // Also try nearby search
                    result = await nearbySearch(lat, lng, placeName, 500);
                    if (result && result.geometry) {
                        const rLat = result.geometry.location.lat;
                        const rLng = result.geometry.location.lng;
                        const dist = haversineM(lat, lng, rLat, rLng);
                        
                        if (dist < 500 && dist < bestDistance && result.photos && result.photos.length > 0) {
                            bestResult = result;
                            bestDistance = dist;
                        }
                    }
                    
                    await sleep(200); // Rate limit
                } catch (e) {
                    console.log(`  ⚠️  Error buscando "${query}": ${e.message}`);
                }
            }
            
            if (bestResult && bestResult.photos && bestResult.photos.length > 0) {
                const photoRef = bestResult.photos[0].photo_reference;
                const destFile = path.join(PLACES_DIR, `${placeId}.jpg`);
                
                try {
                    const ok = await downloadPhoto(photoRef, destFile);
                    if (ok) {
                        const fileSize = fs.statSync(destFile).size;
                        if (fileSize > 1000) { // Valid image (>1KB)
                            console.log(`  ✅ ${placeName} → "${bestResult.name}" (${Math.round(bestDistance)}m) [${(fileSize/1024).toFixed(0)}KB]`);
                            found++;
                        } else {
                            fs.unlinkSync(destFile);
                            console.log(`  ❌ ${placeName} → foto inválida (${fileSize}B), eliminada`);
                            notFound++;
                        }
                    } else {
                        console.log(`  ❌ ${placeName} → no se pudo descargar`);
                        notFound++;
                    }
                } catch (e) {
                    console.log(`  ❌ ${placeName} → error descargando: ${e.message}`);
                    notFound++;
                }
            } else if (bestDistance < Infinity) {
                console.log(`  ⏭️  ${placeName} → encontrado pero a ${Math.round(bestDistance)}m (muy lejos), omitido`);
                skippedTooFar++;
            } else {
                console.log(`  ➖ ${placeName} → no encontrado en Google Maps`);
                notFound++;
            }
            
            await sleep(300);
        }
    }
    
    // Save cleaned bundle (no imageUrl fields)
    fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');
    
    console.log(`\n========== RESUMEN ==========`);
    console.log(`✅ Fotos reales encontradas: ${found}`);
    console.log(`➖ Sin foto (queda limpio): ${notFound}`);
    console.log(`⏭️  Omitidos (muy lejos): ${skippedTooFar}`);
    console.log(`📁 Fotos guardadas en: ${PLACES_DIR}`);
}

main().catch(console.error);
