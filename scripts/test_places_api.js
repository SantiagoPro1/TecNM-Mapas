const https = require('https');

const GOOGLE_API_KEY = 'AIzaSyDTt0U-8LaagPsho1M8Qf4Br3cMAQgIUmQ';

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
