# ReliefLink Volunteer App (Flutter)

Offline-first Android app for volunteers in disaster response. Volunteers write a report in any
language; the app stores it on the phone, syncs it to the ReliefLink hub when the local Wi-Fi is
available, and shows the AI triage result (severity, category, needs, suggested action) once the hub
has processed it.

> **Decision support only.** AI triage output is a suggestion for human coordinators. It is not a
> verified emergency dispatch decision.

## Contents
1. [How it fits in the system](#how-it-fits-in-the-system)
2. [Features](#features)
3. [Requirements](#requirements)
4. [Quick start](#quick-start)
5. [Configuration](#configuration)
6. [Project structure](#project-structure)
7. [Architecture](#architecture)
8. [API contract used by the app](#api-contract-used-by-the-app)
9. [Offline behavior](#offline-behavior)
10. [Android permissions](#android-permissions)
11. [Troubleshooting](#troubleshooting)
12. [Known limitations](#known-limitations)
13. [Roadmap](#roadmap)

## How it fits in the system

```
 Volunteer phone (this app) ──┐
                              ├── same Wi-Fi / hotspot (no internet needed) ──► WINDOWS HUB
 Coordinator browser (React) ─┘                                                FastAPI :8000 + MongoDB
                                                                                    │ HTTP
                                                                                    ▼
                                                                              MAC AI SERVER
                                                                              Ollama :11434 + Gemma
```

The app talks **only to the hub**. It never talks to the AI server directly.

## Features

- **Report an emergency** in free text (Hindi, Hinglish, English or other), with an optional language hint.
- **Flexible location** (GPS is optional):
  - no location (describe it in the message),
  - phone location (GPS),
  - a known place from the hub's list (hospital, shelter, camp),
  - manually typed latitude and longitude (range-checked).
- **Offline queue:** reports are saved on the phone first and sent automatically when the hub is reachable.
- **Idempotent sync:** every report has an app-generated UUID, so retries never create duplicates.
- **Live results:** the Reports tab polls the hub and shows severity, category, people affected, needs,
  English summary and suggested action, plus the case status set by coordinators.
- **Resources:** list available resources and register a new one.
- **Places:** list hospitals, shelters and camps.
- **Hub settings:** change the hub address at runtime and test the connection.

## Requirements

| Tool | Version |
|---|---|
| Flutter SDK | Stable channel, Dart `>=3.0.0 <4.0.0` |
| Android | A device or emulator (API level supported by your Flutter version) |
| Hub | ReliefLink hub v0.2.x reachable on the local network |

Packages (see `pubspec.yaml`): `http`, `shared_preferences`, `uuid`, `geolocator`.

## Quick start

```bash
# 1. Get dependencies
flutter pub get

# 2. Run on a connected device or emulator
flutter run

# 3. Build a release APK (optional)
flutter build apk
```

First run:

1. Make sure the phone is on the **same Wi-Fi** as the hub laptop and mobile data is off.
2. Verify the hub from the phone's browser: `http://<HUB_IP>:8000/docs` should open.
3. In the app, tap the **gear icon**, enter `http://<HUB_IP>:8000`, and tap **Save & test**.
4. You should see "Connected" and a green **Hub online** chip.

**Which IP?** The Windows laptop that runs the hub. Not the Mac (that is the AI server), and not
`localhost` (on a phone this means the phone itself). The hub prints its address on startup:
`Phones / app server address : http://X.X.X.X:8000`.

**Emulator:** use the hub's real LAN address. Use `http://10.0.2.2:8000` only when the hub runs on the same
computer as the emulator.

## Configuration

| Setting | Where | Default |
|---|---|---|
| Hub URL | In-app: gear icon, Hub settings (saved on the device) | `http://192.168.137.1:8000` (usual Windows hotspot address) |
| Sync interval | `Timer.periodic` in `lib/state.dart` | 6 seconds |
| Request timeout | `_timeout` in `lib/api.dart` | 8 seconds |
| Default location mode | `_mode` in `lib/screens/report_screen.dart` | No location |

Plain `http://` is intentional: the hub runs on a local network without TLS. The Android manifest sets
`usesCleartextTraffic="true"` for this reason. Do not expose the hub to the internet in this configuration.

## Project structure

```
lib/
├── main.dart                  App entry: loads saved state, runs the app
├── models.dart                Report, Triage, Resource, Place (match the hub's JSON)
├── api.dart                   HTTP client for /api/v1
├── state.dart                 AppState: hub URL, offline queue, report cache, periodic sync
└── screens/
    ├── home_screen.dart       Bottom navigation and Hub online/Offline chip
    ├── report_screen.dart     Compose and send a report; choose location mode
    ├── reports_screen.dart    Report list and detail (triage result)
    ├── resources_screen.dart  List and add resources
    ├── places_screen.dart     Hospitals, shelters, camps
    └── settings_screen.dart   Hub URL and connection test
android/app/src/main/AndroidManifest.xml   INTERNET + location permissions, cleartext HTTP
```

## Architecture

Unidirectional and deliberately small:

```
screens/*  ──►  AppState (state.dart)  ──►  Api (api.dart)  ──►  Hub /api/v1
                    │                              │
                    └─────── models.dart ◄─────────┘
                    └─────── shared_preferences (queue, cached reports, hub URL, `since` cursor)
```

- **Screens** render state and call `AppState`; they contain no networking.
- **`AppState`** (a `ChangeNotifier`) owns the offline queue, the cache and the sync loop.
- **`Api`** is the only code that touches the network. It maps HTTP errors to `ApiException`
  (`network: true` means the hub could not be reached).
- **`models.dart`** parses JSON defensively (missing fields get safe defaults).

### Sync cycle (every 6 seconds and after each submit)

1. **Push:** send queued reports with `POST /reports/batch` (up to 100 per call). A report leaves the queue
   when the hub answers `created`, `duplicate` or `rejected`. If the hub is unreachable, nothing is removed.
2. **Pull:** `GET /reports?since=<cursor>`; merge changed reports into the cache; store the returned
   `server_time` as the next cursor.
3. Persist queue and cache, update the Hub online/Offline chip.

## API contract used by the app

Base path: `/api/v1`. JSON is snake_case, timestamps are ISO-8601 UTC, errors look like
`{"error": {"code": "...", "message": "..."}}`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Connection test; shows hub, MongoDB and AI status |
| POST | `/reports/batch` | Offline sync of queued reports |
| GET | `/reports?since=` | Poll for new or updated reports |
| GET | `/resources` | List resources |
| POST | `/resources` | Add a resource (idempotent on `id`) |
| GET | `/locations` | Known places (assumed to return a list; see limitations) |

Report payload sent by the app:

```json
{
  "id": "uuid-v4",
  "raw_text": "3 log fasse hain, budhe ko insulin chahiye, road band hai",
  "lang_hint": "hi",
  "client_created_at": "2026-11-10T07:30:00Z",
  "gps": { "lat": 20.2961, "lng": 85.8245 }
}
```
`lang_hint` and `gps` are optional. The report's `status` is `processing` until the AI worker on the hub
has triaged it; `triage` is `null` until then.

## Offline behavior

| Situation | What happens |
|---|---|
| Phone cannot reach the hub | Report stays in the on-device queue (shown as "Waiting to send"); sent automatically later |
| Hub is up but the AI server is down | Report is accepted and shown as "AI is processing"; triage appears when the AI server returns |
| Same report sent twice | The hub answers `duplicate`; no second report appears |
| App restarted offline | Queue and cached reports are restored from local storage |
| Hub address changes | Update it in Hub settings; the cache cursor is reset and reports are refetched |

Resource creation and the places list need the hub to be reachable (they are not queued).

## Android permissions

| Permission | Why |
|---|---|
| `INTERNET` | Talk to the hub on the local network |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | Only when the volunteer chooses "Use my phone location" |

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| "Cannot reach hub (TimeoutException ...)" | Wrong hub IP, or phone and hub on different networks. Open `http://<HUB_IP>:8000/docs` in the phone's browser first |
| Browser shows "refused to connect" | Hub started without `--host 0.0.0.0` (use `python run.py`), or the Windows firewall blocks port 8000 |
| Works on laptop, not on phone | Windows firewall rule missing, network profile is Public, or the Wi-Fi isolates clients (college/public Wi-Fi) |
| Chip stays "Offline · N queued" | The hub is unreachable; the reports are safe and send when it returns |
| Report stays "AI is processing" | The AI server (Mac) is off or the hub's `.env` has a stale Mac IP; check the dashboard's AI server badge |
| Places or resources tab shows an error | Hub unreachable, or `/locations` returned an unexpected shape |
| Build error about Android v1 embedding | The `android/` folder is incomplete: delete it and run `flutter create --platforms=android .`, then re-apply the manifest settings above |
| IP stopped working after changing Wi-Fi | Hub IP changed; read the new address from the hub console and update Hub settings |

## Known limitations

- **Not covered by automated tests.** Verify behavior manually before relying on it.
- **`/locations` response shape is assumed** (a JSON list of `{id, name, type, lat, lng}`); adjust `Place.fromJson`
  if the hub differs.
- **No authentication.** Anyone on the same network can submit reports. Coordinator actions (changing case
  status, AI server settings) are intentionally not in this app; they require the admin PIN on the dashboard.
- **No map view.** Map tiles need internet, which the offline deployment does not have.
- **Cleartext HTTP** is enabled for the local network only.
- **Resource creation is not queued** when offline.

## Roadmap

- Automated tests for `AppState` sync, queue and error paths.
- Move to a layered structure (`data/`, `services/`, `state/`, `widgets/`) as features grow.
- Queue resource creation for offline use.
- Offline map package with pre-downloaded tiles.
- Optional per-device identity so reports can be traced to a volunteer.