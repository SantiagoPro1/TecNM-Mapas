# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SINAIT-APP is an institutional mobile app for TecNM Campus Colima (InnovaTecNM 2026). It provides digital credentials, campus navigation, QR scanning, and an AI-powered assistant for students and staff. Access is restricted to `@colima.tecnm.mx` accounts.

The repo has two independently deployable components:
- `app/` — Flutter 3.x mobile app
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
- `constants/app_routes.dart` — Route name constants shared by both Navigator 1.0 and app_router.dart
- `theme/app_theme.dart` — Dark theme: background Slate `#0F172A`, surface Slate `#1E293B`, accent Sky `#38BDF8`

**`lib/data/`** — Data layer
- `models/` — Plain Dart data classes (no business logic): `CampusNode`, `CampusEdge`, `NavRoute`, `Announcement`, `PlaceNode`
- `providers/` — Riverpod providers: `auth_provider`, `feed_provider`, `navigation_provider`, `voice_provider`, `settings_provider`, `zone_provider`
- `repositories/` — Abstractions over data sources (Firestore + Hive)
- `cache/map_cache_service.dart` — Hive-backed offline cache for campus map JSON; initialized in `main()` before `runApp`

**`lib/services/`** — Business logic
- `auth/auth_service.dart` — Google Sign-In restricted to `hostedDomain: 'colima.tecnm.mx'`
- `auth/credential_service.dart` — JWT generation for QR credential cards
- `navigation/campus_graph.dart` + `dijkstra.dart` — Graph-based campus pathfinding
- `navigation/navigation_service.dart` — GPS + voice query → nearest node lookup
- `voice/voice_service.dart` + `intent_parser.dart` — STT + intent parsing
- `vision_service.dart` — ML Kit image labeling + TFLite model inference

**`lib/presentation/`** — UI layer
- Each feature has its own `screens/<feature>/` folder
- Shared widgets in `widgets/`
- Screens are thin — they read Riverpod providers and delegate to services

**State management:** Riverpod (`flutter_riverpod: ^2.5.1`). Use `ConsumerWidget` / `ConsumerStatefulWidget`. Core providers live in `data/providers/`; screen-specific providers (e.g., `map/providers/map_providers.dart`) live alongside their screen.

**Local persistence:**
- Hive for structured local data (campus graph cache, history)
- SharedPreferences for simple flags (e.g., onboarding completed)

**Assets:**
- `assets/maps/tec_colima_map.json` — Campus graph data (nodes + edges) for offline navigation
- `assets/models/` — TFLite model files
- `.env` loaded via `flutter_dotenv` at runtime; the committed file is a safe placeholder — sensitive values go in `.env.local` (git-ignored). Set `DEV_MODE=true` to bypass the `@colima.tecnm.mx` domain lock during local development (never ship `true` to production).

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

Express 5 REST API with three layers:

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
1. Flutter app signs in via Google with `hostedDomain: 'colima.tecnm.mx'`
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

- **Email domain lock:** Only `@colima.tecnm.mx` accounts can authenticate. Enforced in both Flutter (`hostedDomain` + email suffix check in `auth_service.dart`) and backend middleware. Override locally with `DEV_MODE=true` in `app/.env`.
- **Credential QR:** JWT-signed, verified server-side via `/api/auth/verify-credential`.
- **Onboarding gate:** `SharedPreferences` key checked in `main.dart` to redirect first-time users before reaching home.
