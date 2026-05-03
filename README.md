# 🚀 SINAIT - Sistema Integral de Navegación y Accesibilidad del Instituto Tecnológico

> **Proyecto para InnovaTecNM 2026 - Campus Colima**  
> _Transformando la movilidad estudiantil a través de la inclusión y la tecnología. Innovando para un futuro accesible._

---

## 📖 Descripción del Proyecto

**SINAIT** es una solución móvil multiplataforma revolucionaria diseñada para eliminar las barreras de movilidad en el **TecNM Campus Colima**. Nuestro compromiso es la **accesibilidad universal**, empoderando a estudiantes con discapacidad visual o movilidad limitada para navegar el campus de manera autónoma mediante guías de voz inteligentes, posicionamiento indoor preciso y una interfaz intuitiva adaptada a sus necesidades.

### 🎯 Visión y Misión

- **Visión:** Ser el referente nacional en soluciones tecnológicas inclusivas para instituciones educativas, demostrando que la innovación puede ser sinónimo de equidad.
- **Misión:** Desarrollar herramientas que no solo faciliten la movilidad, sino que también promuevan la independencia y la dignidad de todos los estudiantes.

---

## 🏆 Estado del Arte (Marzo 2026)

### 👑 Arquitecto de Software & Lead Developer: Santiago G. García

El núcleo tecnológico y la experiencia visual de SINAIT son resultado directo del trabajo de **Santiago**, quien fungió como el cerebro técnico detrás de la implementación más compleja del proyecto. Sus contribuciones magistrales incluyen:

- **🧠 Motor de Algoritmia Espacial:** Programación nativa del motor de enrutamiento (Dijkstra) y construcción milimétrica del grafo topológico del TecNM Colima.
- **🛰️ Arquitectura de Telemetría GPS:** Diseño de un robusto sistema asíncrono para la geolocalización en tiempo real, garantizando precisión sin caídas de rendimiento ni _jitter_ visual en el mapa.
- **🎙️ Ecosistema Inclusivo Inteligente:** Desarrollo del motor de accesibilidad integral, conectando text-to-speech y reconocimiento de voz fluido.
- **✨ UI/UX de Nivel Producción:** Creación de una interfaz _premium_ altamente responsiva, con micro-animaciones inmersivas (ej. _Flip Card_ de la credencial) y optimización absoluta de la capa de renderizado en Flutter.

### ✅ Funcionalidades Implementadas y Operativas (Por Santiago)

#### 🔐 Autenticación Institucional Segura

- Integración completa con **Firebase Auth** y **Google Sign-In**.
- **Validación estricta de dominio:** Exclusivamente cuentas `@colima.tecnm.mx`.
- Extracción automática de datos del usuario (foto de perfil, nombre completo).
- Implementación de `AuthService` con manejo robusto de errores y cierre de sesión seguro.

#### 🪪 Credencial Digital Dinámica

- **Réplica exacta** de la credencial física del TecNM Colima.
- **Efecto de giro (Flip Card):** Anverso y reverso interactivos con animaciones suaves.
- **Generación en tiempo real:** Código QR y Código de Barras basados en la matrícula extraída del email institucional.
- **Animaciones pulsantes** para resaltar elementos dinámicos.
- Integración con `flip_card`, `qr_flutter` y `barcode_widget`.

#### 👋 Flujo de Onboarding Inteligente

- **Pantallas introductorias** que explican funcionalidades clave.
- **Aceptación de Términos y Condiciones** integrada, alineada con el Código de Ética del TecNM.
- **Gestión de estado** mediante SharedPreferences para usuarios recurrentes.
- Verificación de primer uso en `main.dart`.

#### 🛠️ Configuración de Hardware Avanzada

- **Permisos configurados:** Cámara y Micrófono en `AndroidManifest.xml`.
- **Gestión de permisos** con `permission_handler` durante el onboarding.
- Preparación para funciones de escaneo QR y asistencia por voz.

#### 📱 Navegación Robusta y Arquitectura Limpia

- **Sistema de rutas nativo** de Flutter (Navigator 1.0) definido en `AppRoutes`.
- **Clean Architecture adaptada:** Separación clara en capas (presentation, services, core).
- **Tema oscuro** consistente con la identidad visual del TecNM.
- **Orientación forzada a portrait** para optimización móvil.

### 🔄 Integraciones Técnicas Clave

- **Firebase Ecosystem:** Auth, Firestore, Storage para escalabilidad futura.
- **ML Kit y TensorFlow Lite:** Preparado para reconocimiento de imágenes y IA.
- **Text-to-Speech y Speech-to-Text:** Librerías `flutter_tts` y `speech_to_text` listas para activación.
- **Escaneo QR avanzado:** `mobile_scanner` para validación rápida.

---

## 🛠️ Stack Tecnológico Completo

| Categoría         | Tecnología                              | Versión                     | Propósito                        |
| ----------------- | --------------------------------------- | --------------------------- | -------------------------------- |
| **Lenguaje**      | [Dart](https://dart.dev)                | >=3.0.0                     | Desarrollo multiplataforma       |
| **Framework**     | [Flutter](https://flutter.dev)          | 3.x                         | UI nativa y rendimiento          |
| **Backend**       | [Firebase](https://firebase.google.com) | Auth 5.0.0, Firestore 5.0.0 | Autenticación y datos en la nube |
| **Backend Local** | [Node.js](https://nodejs.org)           | -                           | API REST con Express 5.2.1       |
| **Base de Datos** | Firestore / Local (Hive)                | -                           | Persistencia híbrida             |
| **IA/ML**         | Google ML Kit, TensorFlow Lite          | -                           | Reconocimiento y navegación      |
| **Comunicación**  | Dio, JWT                                | -                           | APIs seguras                     |
| **UI/UX**         | Flutter Animate, Flip Card              | -                           | Animaciones y transiciones       |

### 📦 Dependencias Críticas (Flutter)

- **Autenticación:** `firebase_auth`, `google_sign_in`, `firebase_core`
- **Navegación:** `go_router` (preparado para migración futura)
- **Accesibilidad:** `flutter_tts`, `speech_to_text`
- **Escaneo:** `mobile_scanner`, `qr_flutter`, `barcode_widget`
- **Persistencia:** `shared_preferences`, `hive`, `hive_flutter`
- **Utilidades:** `permission_handler`, `equatable`, `uuid`, `intl`

### 🔧 Backend (Node.js)

- **Framework:** Express 5.2.1 con CORS y Helmet
- **Autenticación:** Firebase Admin SDK, JWT
- **Herramientas:** Dotenv para variables de entorno, ESLint y Prettier

---

## 📋 Requisitos Técnicos Exactos

### 🔧 Entorno de Desarrollo

- **Flutter SDK:** Versión estable (3.x) con Dart >=3.0.0
- **Java JDK:** Versión 17 (obligatorio para Gradle 8.x en Android)
- **Android Studio / VS Code:** Con plugins Flutter y Dart instalados
- **Node.js:** Versión LTS para desarrollo backend
- **Git:** Control de versiones con flujo de ramas

### 📱 Dispositivos Soportados

- **Android:** API 21+ (Android 5.0) con énfasis en Android 13+
- **iOS:** Preparado (requiere configuración adicional)
- **Hardware:** Cámara y micrófono obligatorios para funcionalidades completas

### 🔐 Variables de Entorno

- **Firebase:** `google-services.json` (solicitar al líder técnico)
- **Backend:** Variables en `.env` (API keys, secrets)

---

## 🚀 Guía de Instalación para Nuevos Colaboradores

### 1. Preparación del Entorno

```bash
# Instalar Flutter (si no está instalado)
# Descargar desde https://flutter.dev/docs/get-started/install
flutter doctor  # Verificar instalación

# Instalar Node.js (para backend)
# Descargar LTS desde https://nodejs.org

# Configurar Java 17
# Asegurar JAVA_HOME apunta a JDK 17
```

### 2. Clonación y Configuración

```bash
# Clonar repositorio
git clone https://github.com/TacosAlPastorMX/SINAIT-APP.git
cd SINAIT-APP

# ⚠️ IMPORTANTE: Nunca trabajar en 'main'
# Crear rama personal inmediatamente
git checkout -b feature/tu-nombre-inicializacion
```

### 3. Configuración de Flutter (App)

```bash
cd app

# Instalar dependencias
flutter pub get

# ⚠️ CONFIGURACIÓN CRÍTICA DE FIREBASE
# Solicitar google-services.json al líder técnico
# Colocarlo en: android/app/src/main/google-services.json
# ¡Sin este archivo, la autenticación no funcionará!

# Verificar configuración
flutter doctor --android-licenses
```

### 4. Configuración de Backend

```bash
cd ../backend

# Instalar dependencias
npm install
```

### 5. Ejecución y Pruebas

```bash
# En terminal 1 (Flutter)
cd app
flutter run  # Con dispositivo Android conectado

# Ejecutar pruebas
flutter test
npm test  # Una vez implementadas
```

### 🐛 Solución de Problemas Comunes

- **Error de Gradle:** Verificar JDK 17 y limpiar: `flutter clean`
- **Firebase no conecta:** Verificar `google-services.json` y `firebase_options.dart`
- **Permisos denegados:** Aceptar permisos en dispositivo durante onboarding

---

## 🏗️ Arquitectura del Proyecto (Clean Architecture Adaptada)

```
SINAIT-APP/
├── 📱 app/                          # Aplicación Flutter
│   ├── lib/
│   │   ├── core/                    # Núcleo de la aplicación
│   │   │   ├── constants/           # AppRoutes, constantes globales
│   │   │   ├── theme/               # AppTheme (modo oscuro TecNM)
│   │   │   └── config/              # Configuraciones (Firebase, etc.)
│   │   ├── data/                    # Capa de datos
│   │   │   ├── models/              # Modelos de datos (User, Credential)
│   │   │   ├── repositories/        # Repositorios para acceso a datos
│   │   │   └── services/            # Servicios externos (API calls)
│   │   ├── domain/                  # Lógica de negocio
│   │   │   ├── entities/            # Entidades del dominio
│   │   │   ├── usecases/            # Casos de uso
│   │   │   └── repositories/        # Interfaces de repositorios
│   │   ├── presentation/            # Capa de presentación
│   │   │   ├── screens/             # Pantallas (Home, Credential, etc.)
│   │   │   ├── widgets/             # Componentes reutilizables
│   │   │   ├── providers/           # Estado con Riverpod
│   │   │   └── animations/          # Animaciones personalizadas
│   │   ├── services/                # Servicios de aplicación
│   │   │   ├── auth/                # AuthService (Google Sign-In)
│   │   │   ├── navigation/          # Servicios de navegación
│   │   │   └── voice/               # TTS/STT (preparado)
│   │   └── main.dart                # Punto de entrada
│   ├── android/                     # Configuración Android
│   ├── ios/                         # Configuración iOS
│   └── pubspec.yaml                 # Dependencias Flutter
│
├── 🔧 backend/                      # API REST (Node.js)
│   ├── src/
│   │   ├── controllers/             # Controladores de rutas
│   │   ├── middleware/              # Middlewares (auth, CORS)
│   │   ├── routes/                  # Definición de rutas
│   │   └── utils/                   # Utilidades (JWT, validation)
│   ├── package.json                 # Dependencias Node.js
│   └── .env                         # Variables de entorno
│
├── 📚 docs/                         # Documentación (Gestión Empresarial)
│   ├── legal/                       # Términos, privacidad, ética
│   ├── business/                    # Modelo de negocio, viabilidad
│   └── requirements/                # Requisitos funcionales
│
└── 🔒 .gitignore                    # Archivos ignorados
```

### 🎯 Principios Arquitectónicos

- **Separación de responsabilidades:** Cada capa tiene un propósito claro
- **Inyección de dependencias:** Riverpod para gestión de estado
- **Clean Code:** Nombres descriptivos, funciones pequeñas
- **Testability:** Arquitectura preparada para pruebas unitarias e integración

---

## 📋 Guía de Estilo y Flujo de Trabajo en Git

### 🔀 Flujo de Ramas (Git Flow Adaptado)

```bash
# NUNCA trabajar en 'main' - ¡Prohibido!
# Crear ramas para cada funcionalidad
git checkout -b feature/nombre-funcionalidad

# Para correcciones
git checkout -b fix/descripcion-error

# Para documentación (solo Gestión)
git checkout -b docs/nombre-documento
```

### 📝 Convenciones de Commit

```bash
# Formato: tipo(scope): descripción
feat(auth): implementar validación dominio @colima.tecnm.mx
fix(ui): corregir animación flip card
docs(readme): actualizar guía instalación
refactor(core): limpiar AppRoutes
```

### 👥 Roles y Responsabilidades en Git

- **Ingenieros Sistemas (4):** Trabajan en `/app` y `/backend`
  - Commits en ramas `feature/` o `fix/`
  - Pull Requests revisados por líder técnico
- **Gestión Empresarial (1):** Trabaja exclusivamente en `/docs`
  - Documentación legal, de negocio y requisitos
  - Commits en ramas `docs/`

### 🔄 Proceso de Pull Request

1. **Desarrollar** en rama personal
2. **Testear** localmente
3. **Crear PR** hacia `develop` (no `main`)
4. **Revisión** por pares
5. **Merge** aprobado por líder técnico

---

## 🛣️ Roadmap Técnico (Próximos Hitos)

### 🚀 Fase 1: Voz y Navegación (Q2 2026)

- **Activación TTS/STT:** Implementar guías de voz en `CredentialScreen`
- **Navegación por voz:** "Llévame a la biblioteca"
- **Feedback háptico:** Vibración para confirmaciones

### 🗺️ Fase 2: Mapa Interactivo (Q3 2026)

- **Geofencing indoor:** Posicionamiento preciso en campus
- **Puntos de interés:** Laboratorios, cafetería, baños accesibles
- **Rutas personalizadas:** Evitando barreras arquitectónicas

### 🔗 Fase 3: Integración SII (Q4 2026)

- **Sincronización académica:** Datos en tiempo real del Sistema Integral de Información
- **Horarios dinámicos:** Actualización automática de clases
- **Notificaciones inteligentes:** Recordatorios de eventos

### 🤖 Fase 4: IA Avanzada (2027)

- **Reconocimiento facial:** Acceso seguro a instalaciones
- **Asistente virtual:** IA conversacional para navegación
- **Analytics:** Métricas de uso para mejora continua

---

## 🛡️ Ética y Privacidad

### 📜 Compromiso Ético

SINAIT se desarrolla bajo los principios del **Código de Ética del TecNM**, priorizando la inclusión, la privacidad y la dignidad humana. Cada línea de código refleja nuestro compromiso con la **accesibilidad universal** y el **respeto a la diversidad**.

### 🔒 Protección de Datos

- **No almacenamos contraseñas:** Delegamos seguridad a Google/Firebase
- **Datos mínimos:** Solo recopilamos información esencial para funcionalidad
- **Consentimiento explícito:** Aceptación de términos en onboarding
- **Transparencia:** Usuarios conocen exactamente qué datos se usan

### ♿ Accesibilidad como Core Value

- **Diseño universal:** Funciona para todos, beneficia a muchos
- **Privacidad por diseño:** Consideraciones éticas en cada feature
- **Impacto social:** Reducir brechas digitales en educación superior

### ⚖️ Cumplimiento Legal

- **Ley Federal de Protección de Datos:** Alineación completa
- **Reglamentos TecNM:** Integración con políticas institucionales
- **Auditorías regulares:** Revisión continua de cumplimiento

---

## 👥 Equipo Multidisciplinario

| Integrante                | Perfil   | Responsabilidades Clave                                                     |
| ------------------------- | -------- | --------------------------------------------------------------------------- |
| **Juanpablo E. Gómez D.** | Sistemas | Arquitectura en Nube (Firebase), Gestión Técnica                            |
| **Juan J. Rosales C.**    | Sistemas | Apoyo en Lógica de Interfaces, Gestión de APIs                              |
| **Santiago G. García**    | Sistemas | **Lead Developer, Core Engine (Dijkstra/GPS), UI/UX Master, Accesibilidad** |
| **Brisa A. Rosas O.**     | Sistemas | QA, Testing, Seguridad                                                      |
| **Aylen Y. González C.**  | Gestión  | Modelo de Negocio, Legal, Viabilidad                                        |

### 🤝 Colaboración Efectiva

- **Reuniones semanales:** Alineación técnica y estratégica
- **Documentación compartida:** Este README como fuente única de verdad
- **Mentoría cruzada:** Aprendizaje entre perfiles técnicos y de gestión

---

## 🎉 Impacto Esperado

SINAIT no es solo una app; es un **cambio cultural** en el TecNM Campus Colima. Al finalizar InnovaTecNM 2026, esperamos:

- ✅ **Mayor inclusión:** Todos los estudiantes pueden navegar libremente
- ✅ **Eficiencia operativa:** Reducción de tiempo en trámites administrativos
- ✅ **Modelo replicable:** Inspiración para otros campus TecNM
- ✅ **Orgullo institucional:** Demostración de innovación con propósito

---

⭐ **InnovaTecNM 2026 - Tecnología con sentido humano para el Campus Colima.**  
_Construyendo un futuro donde la movilidad no es un privilegio, sino un derecho._
