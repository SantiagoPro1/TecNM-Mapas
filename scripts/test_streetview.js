const https = require('https');

const GOOGLE_API_KEY = 'AIzaSyDTt0U-8LaagPsho1M8Qf4Br3cMAQgIUmQ';
const lat = 19.262373;
const lng = -103.723879; // Edificio A

const url = `https://maps.googleapis.com/maps/api/streetview/metadata?location=${lat},${lng}&key=${GOOGLE_API_KEY}`;

https.get(url, (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => console.log(data));
}).on('error', console.error);
