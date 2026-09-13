const fs = require('fs');
const path = require('path');

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');

const MAIN_VENUE_IMAGES = {
    'tec_colima': 'https://colima.tecnm.mx/wp-content/uploads/2022/10/DJI_0047-scaled.jpg',
    'unidad_morelos': 'https://upload.wikimedia.org/wikipedia/commons/e/ea/Unidad_Deportiva_Morelos.jpg',
    'gil_cabrera': 'https://scontent.fcyw1-1.fna.fbcdn.net/v/t1.6435-9/46141315_2142279146039572_4476657929497739264_n.jpg?_nc_cat=101&ccb=1-7&_nc_sid=7f8c78&_nc_ohc=W7R-gN&_nc_ht=scontent.fcyw1-1.fna&oh=00_AYBq&oe=66E',
    'imss': 'https://scontent.fcyw1-1.fna.fbcdn.net/v/t39.30808-6/289063228_395914619238472_4531818296715699106_n.jpg?_nc_cat=104&ccb=1-7&_nc_sid=cc71e4'
    // NO default fallback! Only real images.
};

const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));
bundle.dataVersion = 999999; // ensure version is high

for (const [zoneId, venue] of Object.entries(bundle.venues)) {
    if (!venue.places) continue;
    
    // Clear all images
    for (const place of venue.places) {
        delete place.imageUrl;
    }
    
    // Check if we have a real image for this venue
    const realImage = MAIN_VENUE_IMAGES[zoneId];
    if (realImage) {
        let mainPlace = venue.places.find(p => p.name.toLowerCase().includes('acceso principal') || p.name.toLowerCase().includes('entrada principal'));
        if (!mainPlace) {
            mainPlace = venue.places.find(p => p.type === 'Parque' || p.type === 'Edificio');
        }
        if (!mainPlace && venue.places.length > 0) {
            mainPlace = venue.places[0];
        }
        
        if (mainPlace) {
            mainPlace.imageUrl = realImage;
            console.log(`✅ Set real image for [${zoneId}] on place: ${mainPlace.name}`);
        }
    } else {
        console.log(`❌ No real image for [${zoneId}], stripped all images.`);
    }
}

fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');
console.log('Fixed images!');
