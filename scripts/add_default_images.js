const fs = require('fs');
const path = require('path');

const BUNDLE_PATH = path.join(__dirname, '../app/assets/maps/venues_bundle.json');

const DEFAULT_IMAGES = {
    'Parque': 'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?auto=format&fit=crop&w=800&q=80',
    'Edificio': 'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?auto=format&fit=crop&w=800&q=80',
    'Cafetería': 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=800&q=80',
    'Servicios': 'https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=800&q=80',
    'Cancha': 'https://images.unsplash.com/photo-1505322022379-7c3353ee6291?auto=format&fit=crop&w=800&q=80',
};

function getImageUrlForPlace(place) {
    const name = place.name.toLowerCase();
    
    if (name.includes('futbol') || name.includes('fútbol')) {
        return 'https://images.unsplash.com/photo-1518605368461-1ee12523f2f0?auto=format&fit=crop&w=800&q=80';
    }
    if (name.includes('basquetbol') || name.includes('básquetbol')) {
        return 'https://images.unsplash.com/photo-1505322022379-7c3353ee6291?auto=format&fit=crop&w=800&q=80';
    }
    if (name.includes('voleibol')) {
        return 'https://images.unsplash.com/photo-1612872087720-bb876e2e67d1?auto=format&fit=crop&w=800&q=80';
    }
    if (name.includes('atletismo')) {
        return 'https://images.unsplash.com/photo-1461896836934-ffe607ba8211?auto=format&fit=crop&w=800&q=80';
    }
    if (name.includes('laboratorio') || name.includes('lab.')) {
        return 'https://images.unsplash.com/photo-1532094349884-543bc11b234d?auto=format&fit=crop&w=800&q=80';
    }
    if (name.includes('biblioteca') || name.includes('centro de información')) {
        return 'https://images.unsplash.com/photo-1568667256549-094345857637?auto=format&fit=crop&w=800&q=80';
    }
    if (name.includes('estacionamiento')) {
        return 'https://images.unsplash.com/photo-1506521781263-d8422e82f27a?auto=format&fit=crop&w=800&q=80';
    }
    
    return DEFAULT_IMAGES[place.type] || DEFAULT_IMAGES['Edificio'];
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

            place.imageUrl = getImageUrlForPlace(place);
            conImagen++;
        }
    }

    fs.writeFileSync(BUNDLE_PATH, JSON.stringify(bundle, null, 2), 'utf8');

    console.log(`\n✨ Completado!`);
    console.log(`   Lugares procesados: ${procesados}`);
    console.log(`   Con imagen: ${conImagen}`);
}

procesarBundle().catch(console.error);
