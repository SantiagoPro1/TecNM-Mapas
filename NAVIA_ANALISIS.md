# 🚀 Análisis Exhaustivo del Proyecto: NAVIA

Bienvenido al análisis detallado de la arquitectura, tecnologías y estructura de **NAVIA** (Sistema de Navegación Inteligente Accesible). Este documento ha sido diseñado para que cualquier desarrollador, arquitecto o stakeholder pueda entender cómo funciona el proyecto por debajo, desde sus tecnologías base hasta la organización de sus carpetas, arquitectura y despliegues.

---

## 1. 📖 Resumen del Proyecto

**NAVIA** es una solución móvil inclusiva multiplataforma pensada para facilitar la movilidad y accesibilidad dentro del campus del **TecNM Colima**. Provee guías de voz, un mapa interactivo con enrutamiento interno, telemetría GPS, e identificación institucional a través de credenciales digitales dinámicas, complementado con visión por computadora.

El repositorio se divide en dos grandes componentes independientes que trabajan en conjunto:
1. **`app/`**: Aplicación móvil construida en Flutter, bajo Arquitectura Clean de 4 capas.
2. **`backend/`**: API RESTful construida con Node.js y Express.

---

## 2. 🛠️ Stack Tecnológico (Tecnologías Usadas)

### 📱 Frontend Móvil (Directorio `app/`)
- **Lenguaje:** Dart (>= 3.0.0)
- **Framework:** Flutter (Versión 3.x). Compila nativamente a iOS y Android.
- **Gestión de Estado e Inyección de Dependencias:** `flutter_riverpod` (^2.6.x). 
- **Mapas y Localización:**
  - `flutter_map` y `latlong2`: Para renderizar mapas y polígonos.
  - `geolocator`: Telemetría GPS asíncrona continua con snap-to-node.
- **Backend as a Service (BaaS):** Firebase (Auth, Firestore, Storage) y Google Sign-In. Valida estrictamente dominios `@colima.tecnm.mx`.
- **Persistencia Local:** `hive` y `shared_preferences`. `hive` permite caché local offline rápida.
- **IA y Visión (Módulo NAVIA AR):**
  - `google_mlkit_image_labeling` y `tflite_flutter`: Modelos robustos para Inferencia On-Device y detección de obstáculos.
  - `camera`: Interfaz asíncrona nativa mediante Isolates en `CameraFeedHandler`.
- **Accesibilidad y Motor de Voz:**
  - `flutter_tts` y `speech_to_text`: TTS y STT manejados centralmente.
- **UI/UX y Diseño Accesible:** Cumplimiento de WCAG 2.1, Dark/Light Mode adaptativo, `flutter_animate`, y `qr_flutter`.

### ⚙️ Backend API (Directorio `backend/`)
- **Lenguaje:** JavaScript / Node.js
- **Framework:** Express (^5.2.1).
- **Autenticación:** Firebase Admin SDK y JWT.

---

## 3. 🏗️ Arquitectura Limpia en 4 Capas (Clean Architecture)

El equipo de Desarrollo & Arquitectura estructuró el código separando completamente la vista, la lógica de negocio y las integraciones externas, garantizando testeabilidad.

### 📂 Estructura de la Aplicación Móvil (`app/lib/`)
- **`core/`**: Configuraciones vitales. (Router, Theme, Constants).
- **`data/`**: Modelos crudos, servicios externos y repositorios (Firebase/Hive). Aquí se aloja el ecosistema `providers/` (estado global con Riverpod).
- **`domain/`**: Lógica abstracta de negocio. Entidades puras y reglas.
- **`services/`**: Compleja lógica funcional que no pertenece a UI (e.g. `navigation/dijkstra.dart`, `vision/ml_vision_service.dart`, autenticación, TTS).
- **`presentation/`**: Todo lo visible. Las pantallas son "tontas" e invocan a los providers.

---

## 4. 🔀 Ramas, Testing y Flujo de Trabajo (Git Flow)

El equipo de QA y Seguridad mantiene estrictas políticas.

**Testing Automatizado:**
- Se implementan Pruebas Unitarias, Integración (Backend ↔ Frontend) y E2E.
- Integración Continua a través de **GitHub Actions** en cada commit a ramas de desarrollo.

**Flujo de Ramas:**
- `main`: **(PROHIBIDO DESARROLLAR AQUÍ)**
- `develop`: Entorno de pruebas base.
- `feature/<nombre>`: Nuevas características.
- `fix/<bug>`: Corregir bugs.

**Commits:** `tipo(alcance): mensaje` (feat, fix, refactor, docs).

---

## 5. 🧠 ¿Cómo Funciona la Lógica Central?

### A. Módulo NAVIA AR (Visión Artificial)
El flujo utiliza la librería de cámara para capturar frames, los envía mediante `Isolates` a `TfliteObstacleDetector` (MobileNet SSD). Este procesa tensores e infiere detecciones que regresan a `VisionProvider`, el cual notifica a la UI (`CustomPainter` y Bounding Boxes). Todo sin lag en la interfaz principal.

### B. El Mapa y Ruteo (Dijkstra)
Utiliza un Grafo Topológico (`tec_colima_map.json`). 
El archivo `dijkstra.dart` procesa los nodos, calcula los pesos y devuelve la ruta óptima de Dijkstra, trazada con una `Polyline` sobre mapas en caché (Hive).

### C. Geolocalización Constante y Snap-To-Node
El usuario reporta coordenadas continuas. Si está cerca de una arista válida del campus, el motor corrige visualmente el GPS atrayéndolo a la ruta ("snap-to-node").

### D. Sistema de Autenticación Institucional
Firebase verifica el token de sesión y el dominio institucional, limitando accesos y protegiendo los datos bajo estrictas reglas de lectura/escritura definidas por QA.

---
> **Documento Generado Exitosamente (NAVIA).**
