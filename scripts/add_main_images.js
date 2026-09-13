const fs = require('fs');
const path = require('path');

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');

const MAIN_VENUE_IMAGES = {
    'tec_colima': 'https://colima.tecnm.mx/wp-content/uploads/2022/10/DJI_0047-scaled.jpg',
    'unidad_morelos': 'https://upload.wikimedia.org/wikipedia/commons/e/ea/Unidad_Deportiva_Morelos.jpg',
    'gil_cabrera': 'https://scontent.fcyw1-1.fna.fbcdn.net/v/t1.6435-9/46141315_2142279146039572_4476657929497739264_n.jpg?_nc_cat=101&ccb=1-7&_nc_sid=7f8c78&_nc_ohc=W7R-gN&_nc_ht=scontent.fcyw1-1.fna&oh=00_AYBq&oe=66E',
    'imss': 'https://scontent.fcyw1-1.fna.fbcdn.net/v/t39.30808-6/289063228_395914619238472_4531818296715699106_n.jpg?_nc_cat=104&ccb=1-7&_nc_sid=cc71e4',
    // Fallback for others
    'default': 'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?auto=format&fit=crop&w=800&q=80'
};

const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));

for (const [zoneId, venue] of Object.entries(bundle.venues)) {
    if (!venue.places) continue;
    
    // First, clear all images to be safe
    for (const place of venue.places) {
        delete place.imageUrl;
    }
    
    // Then find the "main" place to add the image to
    let mainPlace = venue.places.find(p => p.name.toLowerCase().includes('acceso principal') || p.name.toLowerCase().includes('entrada principal'));
    
    // If no explicit main entrance, just use the first place as the "cover" (or maybe we don't add one)
    // Actually, it's better to find the most representative place. If there's no "Acceso", we pick the first one that is a "Parque" or "Estadio".
    if (!mainPlace) {
        mainPlace = venue.places.find(p => p.type === 'Parque' || p.type === 'Edificio');
    }
    if (!mainPlace && venue.places.length > 0) {
        mainPlace = venue.places[0];
    }
    
    if (mainPlace) {
        mainPlace.imageUrl = MAIN_VENUE_IMAGES[zoneId] || MAIN_VENUE_IMAGES['default'];
        console.log(`✅ Set main image for [${zoneId}] on place: ${mainPlace.name}`);
    }
}

fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');
console.log('Main images applied correctly!');
