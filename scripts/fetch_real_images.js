const fs = require('fs');
const path = require('path');
const { image_search } = require('duckduckgo-images-api');

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');

const VENUE_NAMES = {
    'tec_colima': 'TecNM Campus Colima',
    'unidad_morelos': 'Unidad Deportiva Morelos Colima',
    'gil_cabrera': 'Unidad Deportiva Gil Cabrera Gudiño Villa de Álvarez',
    'imss': 'Asegurada IMSS Colima',
    'coquimatlan': 'Unidad Deportiva Coquimatlán Colima',
    'gustavo_vazquez': 'Unidad Deportiva Gustavo Vázquez Montes Villa de Álvarez',
    'sur': 'Unidad Deportiva Sur Colima',
    'udif': 'UDIF Colima',
    'zona_militar': '20 Zona Militar Colima'
};

const DEFAULT_VENUE_IMAGE = {
    'tec_colima': 'https://colima.tecnm.mx/wp-content/uploads/2022/10/DJI_0047-scaled.jpg',
    'unidad_morelos': 'https://mapio.net/images-p/23126743.jpg'
};

async function getImageUrlForPlace(place, venueId) {
    const venueName = VENUE_NAMES[venueId] || venueId.replace('_', ' ');
    const query = `${place.name} ${venueName}`;
    
    try {
        console.log(`Buscando: ${query}`);
        const results = await image_search({ query, moderate: true });
        
        if (results && results.length > 0) {
            // Filter out SVG and tiny images
            const validImage = results.find(img => !img.image.endsWith('.svg'));
            if (validImage) {
                return validImage.image;
            }
        }
    } catch (e) {
        console.error(`Error buscando ${query}: ${e.message}`);
    }
    
    return DEFAULT_VENUE_IMAGE[venueId] || 'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?auto=format&fit=crop&w=800&q=80';
}

async function procesarBundle() {
    console.log('📦 Cargando bundle...');
    const bundle = JSON.parse(fs.readFileSync(BUNDLE_PATH, 'utf8'));

    let procesados = 0;
    let conImagen = 0;

    for (const [zoneId, venue] of Object.entries(bundle.venues)) {
        console.log(`\n🏟️  Procesando sede: ${zoneId}`);

        if (!venue.places) continue;

        for (const place of venue.places) {
            procesados++;

            if (place.type === 'Corredor' || place.name.includes('Corredor')) {
                continue;
            }

            // Real web search for the image based on contextual name
            const imgUrl = await getImageUrlForPlace(place, zoneId);
            place.imageUrl = imgUrl;
            conImagen++;
            
            // Be kind to the API rate limits
            await new Promise(r => setTimeout(r, 1000));
        }
    }

    fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');

    console.log(`\n✨ Completado!`);
    console.log(`   Lugares procesados: ${procesados}`);
    console.log(`   Con imagen web real: ${conImagen}`);
}

procesarBundle().catch(console.error);
