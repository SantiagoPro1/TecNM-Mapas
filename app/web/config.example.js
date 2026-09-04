// Plantilla de config.js para la versión WEB.
//
// Copia este archivo como `web/config.js` y pon tus llaves reales ahí.
// `web/config.js` está en .gitignore a propósito: NO debe subirse al repo.
//
//   cp web/config.example.js web/config.js
//
// Dónde salen los valores (proyecto Firebase/GCP de NAVIA):
//   GOOGLE_MAPS_API_KEY      → Google Cloud Console → APIs y servicios →
//                              Credenciales → clave de API. Restringirla por
//                              referrer HTTP antes de publicar.
//   GOOGLE_SIGN_IN_CLIENT_ID → el "Web client (auto created by Google
//                              Service)" del mismo proyecto. Su origen
//                              autorizado debe incluir el host donde corras
//                              la app (ej. http://localhost:5959 en dev).
window.ENV = {
    GOOGLE_MAPS_API_KEY: "TU_LLAVE_DE_GOOGLE_MAPS_AQUI",
    GOOGLE_SIGN_IN_CLIENT_ID: "TU_CLIENT_ID_WEB_AQUI.apps.googleusercontent.com"
};
