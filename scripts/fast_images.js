const fs = require('fs');
const path = require('path');

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');

const VENUE_IMAGES = {
    'tec_colima': 'https://colima.tecnm.mx/wp-content/uploads/2022/10/DJI_0047-scaled.jpg',
    'unidad_morelos': 'https://upload.wikimedia.org/wikipedia/commons/e/ea/Unidad_Deportiva_Morelos.jpg', // Placeholder real
    'gil_cabrera': 'https://scontent.fcyw1-1.fna.fbcdn.net/v/t1.6435-9/46141315_2142279146039572_4476657929497739264_n.jpg?_nc_cat=101&ccb=1-7&_nc_sid=7f8c78&_nc_ohc=W7R-gN&_nc_ht=scontent.fcyw1-1.fna&oh=00_AYBq&oe=66E', // Villa de alvarez sport
    'imss': 'https://scontent.fcyw1-1.fna.fbcdn.net/v/t39.30808-6/289063228_395914619238472_4531818296715699106_n.jpg?_nc_cat=104&ccb=1-7&_nc_sid=cc71e4', 
};

// Fallback contextual if venue image is missing
function getContextual(name) {
    name = name.toLowerCase();
    if (name.includes('futbol') || name.includes('fútbol')) return 'https://images.unsplash.com/photo-1518605368461-1ee12523f2f0?auto=format&fit=crop&w=800&q=80';
    if (name.includes('basquetbol') || name.includes('básquetbol')) return 'https://images.unsplash.com/photo-1505322022379-7c3353ee6291?auto=format&fit=crop&w=800&q=80';
    if (name.includes('voleibol')) return 'https://images.unsplash.com/photo-1612872087720-bb876e2e67d1?auto=format&fit=crop&w=800&q=80';
    if (name.includes('atletismo')) return 'https://images.unsplash.com/photo-1461896836934-ffe607ba8211?auto=format&fit=crop&w=800&q=80';
    return 'https://colima.tecnm.mx/wp-content/uploads/2022/10/DJI_0047-scaled.jpg'; // Default to TecNM
}

const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));

for (const [zoneId, venue] of Object.entries(bundle.venues)) {
    if (!venue.places) continue;
    
    // For TecNM, we use the real drone shot of the campus for all buildings
    // For other sports venues, we use their specific real images
    const baseImg = VENUE_IMAGES[zoneId];
    
    for (const place of venue.places) {
        if (place.type === 'Corredor' || place.name.includes('Corredor')) continue;
        
        if (baseImg) {
            place.imageUrl = baseImg;
        } else {
            place.imageUrl = getContextual(place.name);
        }
    }
}

fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');
console.log('Done!');
