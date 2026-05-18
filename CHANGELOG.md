# Bitácora de Cambios — NAVIA APP

Todos los cambios relevantes del proyecto se documentan en este archivo.  
Formato: **[Tipo] Módulo/Archivo — Descripción breve**

Tipos: `feat` · `fix` · `refactor` · `chore` · `docs` · `perf`

---

## [Unreleased] — 2026-05-18

### refactor — Rebranding a NAVIA y Actualización de Arquitectura
**Archivos:** Múltiples (`README.md`, `NAVIA_ANALISIS.md`, `settings_screen.dart`, `credits_screen.dart`, etc.)

**Motivación:** Cambiar la identidad completa del proyecto de SINAIT a NAVIA, implementar módulo de Visión Artificial (NAVIA AR) y reflejar la adopción de una arquitectura Clean de 4 capas.

**Cambios aplicados:**
- **Rebranding Masivo:** Reemplazo de "SINAIT" por "NAVIA", "sinait" por "navia", y "ESCANEAR" por "NAVIA AR" a lo largo de todo el proyecto (Dart, XML, JSON, YAML).
- **Módulo Ajustes (`settings_screen.dart`):** Inclusión de nuevas políticas de privacidad, información de plataforma on-device y encriptación end-to-end.
- **Créditos del Proyecto (`credits_screen.dart`):** Reasignación equitativa de tareas. Juanpablo como Lead Developer/Backend Lead. Distribución de responsabilidades de ML, UI, y Testing entre Santiago, Juan José y Brisa. Incorporación de BMC y gestión empresarial a Aylen.
- **Documentación:** Reescritura completa de `README.md` y `NAVIA_ANALISIS.md` (antes SINAIT_ANALISIS) para explicar el pipeline de Tflite, Isolates, GitHub Actions, y pruebas E2E.

---

## 2026-05-07

**Motivación:** Garantizar cumplimiento total con `flutter_lints ^3.0.0` sin
alterar lógica de negocio ni estructura de carpetas.

**Cambios aplicados:**

#### `app/lib/presentation/screens/map/map_screen.dart`
- **`avoid_void_async`**: `_startListening` y `_stopListening` cambiados de
  `void ... async` a `Future<void> ... async`.
- **`prefer_final_locals`**: variable local `bool available` → `final bool available`.
- **`prefer_const_declarations`**: campo `_isSimulatingLocation` (nunca mutado)
  promovido de `final bool` a `static const bool`.
- **Normalización `mounted`**: `context.mounted` → `mounted` en `_handleArrival()`
  para consistencia con las demás guardias del archivo.

#### `app/lib/data/providers/navigation_provider.dart`
- **Equatable**: `NavigationState` ahora extiende `Equatable`.
  - `props` declarados: `status`, `currentNode`, `activeRoute`,
    `currentStepIndex`, `accessibleOnly`, `errorMessage`.
  - Garantiza inmutabilidad semántica y comparaciones por valor.
- **Import**: añadido `package:equatable/equatable.dart`.

#### `app/lib/data/models/nav_route.dart`
- **Equatable en `RouteStep`**: `props` → `[node, edge, voiceInstruction]`.
- **Equatable en `NavRoute`**: `props` → `[steps, totalDistance,
  estimatedMinutes, fullyAccessible, origin, destination]`.
- **Import**: añadido `package:equatable/equatable.dart`.

**Verificación:** `flutter analyze` → **No issues found.**

---

## 2026-05-07 — commit `821366c`

### fix(ci) — `map_screen.dart`
- Elimina `const` redundantes dentro del constructor `SnackBar const`
  (`unnecessary_const`).

---

## 2026-05-06 — commit `2a70d44`

### fix(ci) — Análisis estático y asset faltante
- `map_screen.dart`: agrega `const` al constructor `SnackBar`
  (`prefer_const_constructors`).
- `app/.env`: agrega placeholder seguro al repo para satisfacer el
  validador de assets de Flutter.
- `app/.gitignore`: excluye `.env.local` (secretos locales) en lugar de `.env`.
- `.gitignore` raíz: limita el patrón `/.env` al directorio raíz.

---

## 2026-05-06 — commit `e1bdd30`

### chore — Configuración, UI del mapa y registro de skills
- Mejoras generales en la interfaz del mapa.
- Actualización de la configuración del entorno.

---

## 2026-05-06 — commit `5be6c91`

### chore — Corrección masiva de linter
- Corregidas **135 advertencias** de análisis estático.
- `.withOpacity()` → `.withValues(alpha: ...)` en módulos de mapa,
  visión y ajustes.
- Añadidas guardias `if (!mounted) return;` en funciones asíncronas
  de navegación.

---

## Historial anterior (commits en rama `Santi` / `main`)

| Commit    | Descripción                                          |
|-----------|------------------------------------------------------|
| `e761511` | Eliminación de `.env` del tracking de git            |
| `574091e` | Añadidos créditos a la app                           |
| `00b9349` | Cambios en mapa                                      |
| `1e16b7a` | Corrección de puntos de mapa (casi final)            |
| `bd34b05` | Final antes de corregir puntos Sendera/Zentralia/Tec |
| `cc788a2` | Rediseño de `ScannerScreen`, desactivación de rotación, restauración de navegación |
| `c9751b7` | Mapa — iteración 2                                   |
| `f21745f` | Mapa completado (estado estable)                     |

---

> **Nota:** Este archivo debe actualizarse manualmente antes de cada commit
> o pull request relevante.
