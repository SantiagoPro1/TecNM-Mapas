# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SINAIT-APP (branded **NAVIA**) is an institutional mobile app originally built for TecNM Campus Colima (InnovaTecNM 2026), now expanding to cover multiple venues for the Evento Nacional Deportivo del TecNM 2026. It provides digital credentials, multi-venue campus navigation, and a voice assistant for students and staff. Access is restricted to `@*.tecnm.mx` institutional accounts (any TecNM campus nationwide).

The repo has two independently deployable components:
- `app/` — Flutter 3.x mobile app (package name: `navia`)
- `backend/` — Node.js/Express REST API

---

## Flutter App (`app/`)

### Commands

```bash
# From app/ directory
flutter pub get              # Install dependencies
flutter analyze              # Lint / static analysis
flutter test                 # Run all tests
flutter test test/widget_test.dart  # Run a single test file
flutter run                  # Run on connected device/emulator
flutter build apk            # Build Android APK
flutter build ios            # Build iOS (macOS only)

# Code generation (Riverpod, Hive adapters)
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch  # Watch mode during development
```

### Architecture

Clean Architecture with three layers:

**`lib/core/`** — App-wide configuration
- `router/app_router.dart` — GoRouter definitions (declared but **not used**; `main.dart` uses Navigator 1.0 with a `routes` map instead)
- `constants/app_routes.dart` — Route name constants
- `theme/app_theme.dart` — 4 selectable themes: TecNM Dark, Industrial HC, Light Clean, Pastel Minimal. `themeProvider` (Riverpod) lives here. Use `Theme.of(context).colorScheme` for reactive theming; `AppTheme.*` constants are only for `const` widget contexts.

**`lib/data/`** — Data layer
- `models/` — Plain Dart data classes: `CampusNode`, `CampusEdge`, `NavRoute`, `Announcement`, `PlaceNode`, `Venue`
- `providers/` — Riverpod providers: `auth_provider` (also `isAdminProvider`, `adminRepositoryProvider`), `feed_provider`, `navigation_provider`, `settings_provider`, `voice_provider`, `venue_provider`, `zone_provider`
- `repositories/` — Abstractions over data sources (Firestore + Hive): `place_repository.dart` (POI pins, `venues/{zoneId}/places`), `venue_graph_repository.dart` (walkable graph, `venues/{zoneId}/nodes|edges` — nodes/edges providers for the admin editor live in `map/providers/map_providers.dart`), `admin_repository.dart` (`admins/{uid}` role check)
- `cache/map_cache_service.dart` — Hive-backed offline cache for campus map JSON; initialized in `main()` before `runApp`

**`lib/services/`** — Business logic
- `auth/auth_service.dart` — Google Sign-In restricted to any `@*.tecnm.mx` email (regex-checked; Google's `hostedDomain` param is not used since it can't express a wildcard domain)
- `auth/credential_service.dart` — JWT generation for QR credential cards
- `feed/feed_service.dart` — Firestore-backed announcements feed
- `navigation/campus_graph.dart` + `dijkstra.dart` — Graph-based campus pathfinding
- `navigation/navigation_service.dart` — GPS + voice query → nearest node lookup
- `offline/offline_manager.dart` — Central offline orchestrator: monitors connectivity, persists last GPS position to SharedPreferences, verifies offline readiness
- `offline/connectivity_service.dart` — Network connectivity monitoring singleton
- `voice/voice_service.dart` + `intent_parser.dart` — STT + intent parsing

**`lib/presentation/`** — UI layer
- Each feature has its own `screens/<feature>/` folder
- Shared widgets in `widgets/`
- Screens are thin — they read Riverpod providers and delegate to services
- `screens/auth/login_screen.dart` — post-onboarding, one-time choice between "Invitado" (guest, no auth) and "Jugador / Staff TecNM" (Google Sign-In). Admin is not a third button: it's auto-detected via `isAdminProvider` after signing in, never user-selected. Gated by the `hasChosenEntryMode` SharedPreferences flag (set in `login_screen.dart`, separate from `showOnboarding`) so it only shows once — see Domain Rules.
- `screens/map/map_screen.dart` — also hosts the admin map editor (Fase 2): an edit-mode toggle FAB, visible only when `isAdminProvider` is true, that lets an admin tap the map to add a point (creates a `CampusNode` for routing and, unless the type is "Corredor", a `PlaceNode` with the same id so it's also a visible pin — see `_createUnifiedPoint`), tap an existing point to move/rename/connect/delete it, and tap two points in sequence to create a walkable edge (`_connectNodes`). This is the primary way to build the graph for the 8 event venues, which have no bundled JSON and start with an empty Firestore graph.

**`lib/utils/`**
- `svg_marker_helper.dart` — Preloads SVG map marker icons at startup to prevent render flicker
- `gps_filter.dart` — GPS position filtering/smoothing

**State management:** Riverpod (`flutter_riverpod: ^2.5.1`). Use `ConsumerWidget` / `ConsumerStatefulWidget`. Core providers live in `data/providers/`; screen-specific providers (e.g., `map/providers/map_providers.dart`) live alongside their screen.

**Local persistence:**
- Hive for structured local data (campus graph cache, history)
- SharedPreferences for simple flags (onboarding gate, last GPS position, theme selection)

**Assets:**
- `assets/maps/tec_colima_map.json` — Primary campus graph (nodes + edges)
- `assets/maps/sendera_map.json`, `zentralia_map.json` — Additional campus/zone maps
- `assets/map_styles/dark_style.json`, `light_style.json` — Google Maps styling JSONs
- `assets/icons/svg/` — SVG map marker icons, preloaded by `PrecacheSvg.precacheAll()`
- `.env` loaded via `flutter_dotenv`; the committed file is a safe placeholder — sensitive values go in `.env.local` (git-ignored).

### Startup sequence (`main.dart`)

`main()` uses a two-phase pattern: `_SplashWrapper` is rendered immediately (before any async work), then all services initialize in background (`dotenv`, Firebase, `MapCacheService`, `OfflineManager`, `PrecacheSvg`), then `runApp` is called again with `ProviderScope` wrapping `NaviaApp`.

---

## Backend (`backend/`)

### Commands

```bash
# From backend/ directory
npm install          # Install dependencies
npm run dev          # Start with nodemon (auto-reload)
npm start            # Production start
npm run lint         # ESLint on src/

# Requires .env file — copy from .env.example and fill values
cp .env.example .env
```

### Architecture

Express 5 REST API:

```
server.js               ← Entry point, middleware registration, route mounting
src/
  routes/               ← Route definitions (thin, just wires controllers)
  controllers/          ← Request/response handling
  middleware/auth.middleware.js  ← Firebase Admin SDK token verification
```

**API surface:**
| Route | Auth required | Purpose |
|---|---|---|
| `GET /api/health` | No | Health check |
| `POST /api/auth/verify-credential` | No | Validate credential JWT |
| `POST /api/auth/verify-firebase` | Bearer token | Validate Firebase ID token |
| `/api/directions/*` | Bearer token | Campus navigation |

**Authentication flow:**
1. Flutter app signs in via Google; the resulting email must match `@*.tecnm.mx`
2. Firebase issues an ID token; Flutter passes it as `Authorization: Bearer <token>`
3. `auth.middleware.js` calls Firebase Admin SDK to verify the token and checks the email domain
4. Extracted `matricula` = local part of the institutional email (e.g., `L21450123`)

**Environment variables** (see `.env.example`): Firebase service account credentials, JWT secret, allowed CORS origins, `PORT`.

---

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`) runs on push to `main`/`develop` and on PRs to `main`:
- **Flutter job:** `flutter analyze` + `flutter test`
- **Node job:** `npm ci` + `npm run lint`

Both jobs must pass before merging.

---

## Domain Rules

- **Email domain lock:** Only `@*.tecnm.mx` institutional accounts can authenticate (any TecNM campus, broadened from Colima-only for the national multi-campus sports event). Enforced via regex in both `auth_service.dart` (Flutter) and `auth.middleware.js` (backend) — see `admins/{uid}` in Firestore + `isAdminProvider` for the separate elevated admin role.
- **Credential QR:** JWT-signed, verified server-side via `/api/auth/verify-credential`.
- **Startup routing gate**, both checked once in `main.dart` against `SharedPreferences` and passed into `NaviaApp`: `showOnboarding` (tutorial slides, `AppRoutes.onboarding`) then `hasChosenEntryMode` (Invitado vs. sign-in choice, `AppRoutes.login`) — in that order, both must be satisfied before `AppRoutes.home`. Guests who skip sign-in can still authenticate later from Perfil (`profile_screen.dart`).
- **Admin role:** no self-service promotion exists anywhere in the app by design — the first and every admin is granted by hand via a Firestore `admins/{uid}` document (console or direct REST write), never through app UI. `firestore.rules` denies client writes to that collection outright.
