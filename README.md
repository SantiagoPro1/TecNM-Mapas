# 🗺️ TecNM Mapas Nacional Deportivo

> **Plataforma Integral de Movilidad, Geolocalización y Navegación Accesible para las Sedes Deportivas y Campus del TecNM**  
> _Diseñado para guiar a atletas, delegaciones, comités organizadores y visitantes con mapas detallados, rutas accesibles y soporte offline._

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Auth%20%7C%20Firestore%20%7C%20Storage-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![Google Maps](https://img.shields.io/badge/Google%20Maps-Platform-4285F4?logo=googlemaps&logoColor=white)](https://developers.google.com/maps)
[![Tests](https://img.shields.io/badge/Tests-101%20Passed-brightgreen)](https://github.com/SantiagoPro1/TecNM-Mapas)
[![License](https://img.shields.io/badge/License-TecNM-blue)]()

---

## 📌 Descripción General

**TecNM Mapas Nacional Deportivo** es la aplicación móvil oficial de navegación y asistencia en tiempo real desarrollada para el **Evento Nacional Deportivo del TecNM**. La aplicación soluciona el desafío de movilidad en recintos deportivos de gran escala y campus universitarios, ofreciendo posicionamiento en tiempo real, mapas satelitales con trazado de canchas, ruteo peatonal inteligente y credencialización digital.

La plataforma está diseñada con un enfoque prioritario en **accesibilidad universal**, permitiendo trazar rutas adaptadas que evitan escaleras y desniveles para personas con movilidad reducida, además de integrar asistencia por voz paso a paso.

---

## ✨ Características Principales

### 🏟️ Cobertura Multi-Sede (9 Sedes Oficiales en Colima)
- **Visualización completa de todas las sedes del evento:**
  1. **TecNM Campus Colima** (Campus sede central y áreas académicas/deportivas).
  2. **Unidad Deportiva Morelos** (Colima).
  3. **Unidad Deportiva Sur "Las Moras"** (Coquimatlán - Estadio de Béisbol, canchas de fútbol, básquetbol, frontón y skatepark).
  4. **Unidad Deportiva Infantil (UDIF)** (Colima).
  5. **Unidad Deportiva de Villa de Álvarez** (Canchas de fútbol y atletismo).
  6. **Unidad Deportiva Gil Cabrera** (Villa de Álvarez).
  7. **Unidad Deportiva Gustavo Alberto Vázquez Montes**.
  8. **Complejo Deportivo SNTE Sección 6**.
  9. **Complejo Deportivo IMSS**.
- Cada sede cuenta con caja delimitadora de cámara, puntos de interés (POIs) georreferenciados y trazado de andadores peatonales.

### 🧭 Motor Híbrido de Navegación y Ruteo Inteligente
- **Algoritmo Dijkstra sobre Grafo Topológico:** Permite calcular rutas óptimas a pie sin depender de conexión a internet.
- **Rutas Accesibles:** Filtro especializado para personas en silla de ruedas o con movilidad asistida que prioriza rampas y andadores accesibles.
- **Google Directions API con Respaldo Automático:** Consulta rutas en tiempo real y realiza *fallback* transparente al grafo local si se pierde la conectividad.
- **Detección Dinámica de Llegada:** Monitoreo por proximidad GPS y aviso visual/auditivo al arribar al destino.

### 🛰️ Visualización Satelital e Ilustraciones de Sedes
- **Conmutador Satélite / Híbrido:** Botón de capas en tiempo real para alternar entre el mapa vectorial y la fotografía aérea satelital de alta resolución, permitiendo apreciar canchas de pasto, diamantes de béisbol, arcilla y pista sintética.
- **Ilustraciones por Deporte:** Cada disciplina deportiva (béisbol, fútbol, básquetbol, voleibol, tenis/frontón, natación, atletismo, etc.) cuenta con su propia ficha gráfica ilustrada e ícono distintivo.
- **Modo Claro / Oscuro Institucional:** Paleta de colores de alto contraste con tipografía *Manrope* adaptada a condiciones de luz exterior en canchas abiertas.

### 🪪 Credencial Digital con Código QR Dinámico
- Identificación oficial de participantes, delegaciones y alumnos.
- Autenticación institucional vía **Google Sign-In** (`@colima.tecnm.mx`).
- Generación de código QR firmado criptográficamente para validación instantánea en accesos.
- Respaldo de fotografía de perfil institucional en caché local persistente.

### 📲 Actualizador Integrado (In-App OTA Updates)
- Detección automática de nuevas versiones mediante metadatos en Cloud Firestore.
- Descarga directa dentro de la app con barra de progreso interactiva (porcentaje y MB/MB).
- Invocación nativa del instalador de paquetes de Android (`PackageInstaller` vía `FileProvider`) sin redirigir al navegador externo.

### 🗣️ Asistencia por Voz No Bloqueante
- Indicaciones auditivas integradas mediante el motor TTS nativo del dispositivo para guiar al usuario mientras camina sin necesidad de mirar la pantalla permanentemente.

---

## 🏛️ Arquitectura del Software

El proyecto sigue los principios de **Clean Architecture** estructurada en 4 capas desacopladas, utilizando **Riverpod** para la gestión reactiva del estado y la inyección de dependencias:

```
TecNM-Mapas/
├── 📱 app/                          
│   ├── assets/
│   │   ├── categories/              # Ilustraciones de canchas y deportes (PNG)
│   │   ├── maps/                    # Paquete JSON de sedes, nodos y caminos
│   │   ├── map_styles/              # Estilos JSON para Google Maps (dark/light)
│   │   └── places/                  # Fotografías reales de instalaciones
│   ├── lib/
│   │   ├── core/                    # Constantes, rutas, tema institucional y versión
│   │   ├── data/                    # Modelos, repositorios y StateProviders (Riverpod)
│   │   ├── domain/                  # Entidades y contratos de negocio
│   │   ├── presentation/            # Vistas (MapScreen, HomeScreen, CredentialScreen, etc.)
│   │   ├── services/                # Servicios nativos (Navegación Dijkstra, Auth, Update, Voz)
│   │   └── utils/                   # Filtros GPS y utilidades matemáticas
│   ├── test/                        # Suite de 101 pruebas unitarias automatizadas
│   └── pubspec.yaml                 
├── 🔧 backend/                      # API complementaria en Node.js / Express
└── 📜 scripts/                      # Generadores de grafos topológicos y optimización de datos
```

---

## 🧪 Pruebas Unitarias y Calidad de Código

El repositorio cuenta con una rigurosa suite de pruebas unitarias que validan la lógica central:

```bash
flutter test
```

- **Cobertura de pruebas:**
  - `walk_graph_test.dart`: Conectividad y consistencia de grafos Dijkstra en las 9 sedes.
  - `venue_bundle_test.dart` & `venue_registry_test.dart`: Validación de coordenadas, cajas de cámara y nombres de todas las sedes.
  - `place_visuals_test.dart`: Clasificación taxonómica de nombres de canchas hacia deportes e imágenes.
  - `navigation_test.dart`: Algoritmo de camino más corto y filtros de accesibilidad.
  - `student_data_test.dart`: Validación de matrícula, NSS y datos del participante.
  - `gps_filter_test.dart`: Filtrado Kalman / velocidad para detección de marcha.
- **Resultado:** `101/101 tests passed (100% OK)`.

---

## 🛠️ Tecnologías y Librerías

| Componente | Tecnología | Uso |
|---|---|---|
| **Lenguaje** | Dart 3.x | Lógica central y compilación nativa AOT |
| **Framework** | Flutter 3.x | Interfaz gráfica fluida a 60/120 FPS |
| **Mapas** | `google_maps_flutter` | Renderizado nativo vectorial y satelital |
| **Estado** | `flutter_riverpod` | Inyección de dependencias y estado reactivo |
| **Autenticación** | `firebase_auth`, `google_sign_in` | Acceso seguro institucional |
| **Base de Datos** | `cloud_firestore` | Sincronización remota y persistencia offline |
| **Almacenamiento** | `firebase_storage` / GCS | Servidor de paquetes de actualización y fotos |
| **Red & Descargas**| `dio` | Descarga de APKs con reporte de progreso en tiempo real |
| **Canal Nativo** | Kotlin + Android MethodChannel | Invocación de `PackageInstaller` y `FileProvider` |

---

## 🚀 Instalación y Ejecución

### Prerrequisitos
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (versión >= 3.0.0)
- [Android Studio / SDK](https://developer.android.com/studio) (API 34 recomendada)
- [Git](https://git-scm.com/)

### Clonar el Repositorio
```bash
git clone https://github.com/SantiagoPro1/TecNM-Mapas.git
cd TecNM-Mapas/app
```

### Instalar Dependencias
```bash
flutter pub get
```

### Ejecutar en Dispositivo
```bash
flutter run
```

### Generar APK de Producción
```bash
flutter build apk --release
```
El archivo resultante se encontrará en `build/app/outputs/flutter-apk/app-release.apk`.

---

## 👥 Equipo de Desarrollo

Desarrollado con dedicación por estudiantes del **TecNM Campus Colima** para la comunidad deportiva nacional.

- **Santiago G. García** — Arquitectura de software, motor geoespacial Dijkstra, optimizaciones de mapa e infraestructura de despliegue.
- **Colaboradores técnicos y de diseño** — UI/UX accesible, credencialización digital y catalogación de sedes deportivas.

---

## 📄 Licencia

Este software es propiedad del equipo de desarrollo institucional del **Instituto Tecnológico de Colima (TecNM)**. Todos los derechos reservados.
