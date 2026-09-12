# Scripts de NAVIA

## fetch_place_images.js

Busca imágenes de Google Places API para los lugares en el bundle y las agrega automáticamente.

### Configuración

1. Copia el archivo de ejemplo:
```bash
cp .env.example .env
```

2. Edita `.env` y agrega tu API key de Google Maps:
```
GOOGLE_MAPS_API_KEY=tu_api_key_aqui
```

3. Instala dependencias:
```bash
npm install dotenv
```

### Uso

```bash
node fetch_place_images.js
```

El script actualizará `app/assets/maps/venues_bundle.json` agregando el campo `imageUrl` a cada lugar donde encuentre una imagen.
