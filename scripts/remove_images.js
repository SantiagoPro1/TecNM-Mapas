const fs = require('fs');
const path = require('path');

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');
const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));

for (const venue of Object.values(bundle.venues)) {
    if (!venue.places) continue;
    for (const place of venue.places) {
        if (place.imageUrl) {
            delete place.imageUrl;
        }
    }
}

fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');
console.log('Images removed from places!');
