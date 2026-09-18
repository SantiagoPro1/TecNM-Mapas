const https = require('https');
require('dotenv').config();

const GOOGLE_API_KEY = process.env.GOOGLE_MAPS_API_KEY;

if (!GOOGLE_API_KEY) {
  console.error('Falta GOOGLE_MAPS_API_KEY. Copia .env.example a .env y pon tu clave.');
  process.exit(1);
}

const url = 'https://places.googleapis.com/v1/places:searchText';
const body = JSON.stringify({
  textQuery: "TecNM Colima Edificio A",
  maxResultCount: 1,
});

const req = https.request(
  url,
  {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body),
      'X-Goog-Api-Key': GOOGLE_API_KEY,
      'X-Goog-FieldMask': 'places.displayName,places.photos',
    },
  },
  (res) => {
    let chunks = '';
    res.on('data', (c) => (chunks += c));
    res.on('end', () => {
      console.log(`Status: ${res.statusCode}`);
      console.log(chunks);
    });
  }
);
req.on('error', console.error);
req.write(body);
req.end();
