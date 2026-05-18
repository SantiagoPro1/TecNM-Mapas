# 🚀 NAVIA - Sistema de Navegación Inteligente Accesible

> **Proyecto para InnovaTecNM 2026 - Campus Colima**  
> _Transformando la movilidad estudiantil a través de la inclusión y la tecnología. Innovando para un futuro accesible._

---

## 📖 Descripción del Proyecto

**NAVIA** es una solución móvil multiplataforma revolucionaria diseñada para eliminar las barreras de movilidad en el **TecNM Campus Colima**. Nuestro compromiso es la **accesibilidad universal**, empoderando a estudiantes con discapacidad visual o movilidad limitada para navegar el campus de manera autónoma mediante guías de voz inteligentes, posicionamiento indoor preciso, realidad aumentada y una interfaz intuitiva adaptada a sus necesidades.

### 🎯 Visión y Misión

- **Visión:** Ser el referente nacional en soluciones tecnológicas inclusivas para instituciones educativas, demostrando que la innovación puede ser sinónimo de equidad.
- **Misión:** Desarrollar herramientas que no solo faciliten la movilidad, sino que también promuevan la independencia y la dignidad de todos los estudiantes.

---

## 🏆 Estado del Arte y Arquitectura (Actualizado)

NAVIA ha evolucionado hacia un modelo maduro, adoptando una arquitectura de 4 capas y procesamientos avanzados de machine learning e integración en nube.

### 👑 Dirección & Liderazgo: Juanpablo E. Gómez D. (Lead Developer)
Liderazgo estratégico de NAVIA, encargado de:
- **Arquitectura de 4 Capas:** Diseño e implementación de Clean Architecture combinada con Riverpod para inyección de dependencias y estado.
- **Módulo NAVIA AR:** Implementación de la visión artificial y realidad aumentada para detección de obstáculos (TFLite) y validación cruzada.
- **UI/UX y Accesibilidad:** Diseño integral de 8 pantallas en Figma bajo normativas WCAG 2.1, sumado a la API Semantics de Flutter para soporte de TalkBack/VoiceOver.
- **Backend y Autenticación:** Integración de Google ML Kit, validación institucional estricta en Firebase y gestión de CI/CD.

### ⚙️ Ingeniería de Sistemas

**Santiago G. García (Desarrollo y Arquitectura)**
- Motor de navegación geoespacial con algoritmo Dijkstra y grafo topológico milimétrico.
- GPS asíncrono con snap-to-node y posicionamiento indoor.
- Pipeline de Machine Learning (training, optimization, deployment) para Computer Vision.
- Integración robusta de TTS (Text-to-Speech) y STT.

**Juan J. Rosales C. (Interfaces y APIs)**
- Creación de Design System y adopción de Dark/Light mode accesible.
- Manejo de estado de credencial digital dinámica y formularios de validación en tiempo real.
- Optimización de UI con animaciones de easing estándar y caché local mediante **Hive** (funcionalidad offline).

**Brisa A. Rosas O. (QA & Seguridad)**
- Diseño de la estrategia de testing (Unit Testing, Integración, E2E).
- Configuración automatizada de tests en GitHub Actions.
- Seguridad en reglas de Firebase y encriptación de datos sensibles de usuarios.

### 📊 Gestión Empresarial

**Aylen Y. González C. (Estrategia y Legal)**
- Business Model Canvas, análisis de viabilidad técnica y financiera.
- Estructuración del modelo de ingresos B2B2C, identificando segmentos y competidores.
- Propiedad Intelectual: INDAUTOR y registro IMPI.

---

## 🛠️ Stack Tecnológico Completo

| Categoría         | Tecnología                              | Versión                     | Propósito                        |
| ----------------- | --------------------------------------- | --------------------------- | -------------------------------- |
| **Lenguaje**      | [Dart](https://dart.dev)                | >=3.0.0                     | Desarrollo multiplataforma       |
| **Framework**     | [Flutter](https://flutter.dev)          | 3.x                         | UI nativa y rendimiento          |
| **Backend**       | [Firebase](https://firebase.google.com) | Auth, Firestore, Storage    | Autenticación y datos en la nube |
| **Backend Local** | [Node.js](https://nodejs.org)           | -                           | API REST con Express 5.2.1       |
| **Base de Datos** | Firestore / Local (Hive)                | -                           | Persistencia híbrida offline     |
| **IA/ML**         | Google ML Kit, TensorFlow Lite          | -                           | NAVIA AR y Reconocimiento visual |
| **CI/CD**         | GitHub Actions                          | -                           | Automatización de Testing        |

### 📦 Dependencias Críticas (Flutter)

- **Autenticación:** `firebase_auth`, `google_sign_in`, `firebase_core`
- **Machine Learning / AR:** `tflite_flutter`, `google_mlkit_image_labeling`, `camera`
- **Accesibilidad:** `flutter_tts`, `speech_to_text`
- **Escaneo:** `qr_flutter`, `barcode_widget`
- **Persistencia:** `hive`, `hive_flutter`, `shared_preferences`

---

## 🏗️ Arquitectura del Proyecto (Clean Architecture Adaptada a 4 Capas)

```
NAVIA-APP/
├── 📱 app/                          
│   ├── lib/
│   │   ├── core/                    # Núcleo (constantes, router, theme)
│   │   ├── data/                    # Modelos, providers (Riverpod), repositorios y servicios API
│   │   ├── domain/                  # Lógica de negocio pura y entidades
│   │   ├── presentation/            # Pantallas, widgets, animaciones accesibles
│   │   └── services/                # Handlers complejos (ej: ML Vision, Navegación Dijkstra, STT)
│   └── pubspec.yaml                 
├── 🔧 backend/                      # API REST (Node.js/Express)
└── 📚 docs/                         # Documentación de la capa de Gestión y Negocio
```

---

## 🚀 Guía de Instalación Rápida

1. **Configurar el entorno:** Flutter (3.x), JDK 17, Node LTS.
2. **Clonar repositorio:**
   ```bash
   git clone https://github.com/TacosAlPastorMX/SINAIT-APP.git
   cd SINAIT-APP/app
   flutter pub get
   ```
3. **Credenciales Firebase:** Solicita al líder técnico el archivo `google-services.json` y colócalo en `android/app/src/main/`.
4. **Ejecutar App:**
   ```bash
   flutter run
   ```

---

## 🛡️ Privacidad y Seguridad Total

NAVIA no almacena contraseñas y todo el proceso biométrico o de visión por computadora se realiza de forma **On-Device** (TFLite). Garantizamos el anonimato y la protección de datos bajo las regulaciones de INAI y el Código de Ética del TecNM.

---

⭐ **InnovaTecNM 2026 - Tecnología con sentido humano.**  
_Construyendo un futuro donde la movilidad no es un privilegio, sino un derecho._
