const https = require('https');
require('dotenv').config();

const GOOGLE_API_KEY = process.env.GOOGLE_MAPS_API_KEY;

if (!GOOGLE_API_KEY) {
  console.error('Falta GOOGLE_MAPS_API_KEY. Copia .env.example a .env y pon tu clave.');
  process.exit(1);
}
const lat = 19.262373;
const lng = -103.723879; // Edificio A

const url = `https://maps.googleapis.com/maps/api/streetview/metadata?location=${lat},${lng}&key=${GOOGLE_API_KEY}`;

https.get(url, (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => console.log(data));
}).on('error', console.error);
