# ReliefLink

Offline-first disaster-response triage system: volunteers file free-text reports (any language) from an Android app, a local hub stores them, and Gemma 4 E2B served by Ollama triages them into severity, category, needs and suggested action for coordinators on a React dashboard. Everything runs on a local network with no internet connection required.

> **Decision support only.** AI triage output is a suggestion for human coordinators, not a verified emergency dispatch decision.

<!-- Badges: replace with real URLs -->
[![License](https://img.shields.io/github/license/Aryaa-7/https://github.com/Aryaa-7/relief-link.git)](LICENSE)
![License](https://img.shields.io/badge/license-TODO-lightgrey)
![Gemma 4](https://img.shields.io/badge/Gemma_4-E2B-blue)
![Python](https://img.shields.io/badge/python-3.11%2B-blue)
![Node](https://img.shields.io/badge/node-LTS-green)
![Flutter](https://img.shields.io/badge/flutter-stable-blue)

> **Status:** v0.2 is written but **not yet run or tested**. Nothing is claimed to work until you complete the checklist in the hub guide.

## System Architecture Overview

```text
 Volunteer phones (Flutter) ──┐
                              ├── Wi-Fi / hotspot (no internet needed) ──► WINDOWS HUB
 Admin browser (React) ───────┘                                           FastAPI :8000 + MongoDB (localhost)
                                                                                │ HTTP
                                                                                ▼
                                                                           MAC AI SERVER
                                                                           Ollama :11434 + gemma4:e2b
```

- Phones and the dashboard talk **only to the hub**. The app never talks to the AI server directly.
- The hub talks to the Mac over HTTP. The Mac IP is only configured on the hub.
- The hub serves the built dashboard (`dashboard/dist`) at `/admin/`.

## Core Features

### Frontend Capabilities

**Flutter volunteer app (Android)**
- Free-text emergency reports in Hindi, Hinglish, English or other languages, with an optional language hint.
- Flexible location: none, phone GPS, a known place from the hub (hospital, shelter, camp), or manual latitude/longitude (range-checked).
- Offline queue: reports are saved on the phone first and sent when the hub is reachable.
- Idempotent sync via app-generated UUIDs, so retries never create duplicates.
- Live results: severity, category, people affected, needs, English summary, suggested action and coordinator-set case status.
- Resources: list and register. Places: list hospitals, shelters and camps.
- Runtime hub-address settings with a connection test.

**React admin dashboard (Vite)**
- Shows reports with triage results and a "Waiting for AI server" pending counter.
- AI server status (online / offline / model_missing) and an *AI server settings* panel to change the Ollama URL and model without restarting.
- Case status changes, protected by the admin PIN.
- Serves all assets from the hub's own address (no CDN or font hosts).

### Backend / API Engine
- FastAPI hub with MongoDB storage (localhost only).
- Idempotent report ingestion; the same report id returns 200 with no second row.
- Incremental sync with `?since=` and `updated_at`; `server_time` is read before the query so polling cannot miss an update.
- Background AI worker (`app/worker.py`) that processes pending reports oldest first, checking every ~8 s.
- Admin actions gated by the `X-Admin-Pin` header.

### Gemma 4 Intelligence / Inference Integration
- **Gemma 4 E2B** (`gemma4:e2b`) served by Ollama on a separate machine, reached by the hub over HTTP.
- Modules in `app/ai/*`: Ollama client, prompt, validation, fallback.
- Reports are always accepted and stored with status `processing`. If the AI server is unreachable they stay pending and are triaged automatically when it returns.
- Rule-based fallback is used only if Gemma returns unusable JSON twice, or times out 3 times for the same report.
- The model can be swapped (for example to `gemma4:e4b`) by changing `OLLAMA_MODEL`, with no code change.

## Repository Structure

Root folder names below are placeholders; adjust to your repo. Hub paths come from the hub guide.

```text
.
├── hub/                          # TODO: confirm folder name
│   ├── app/
│   │   ├── ai/                   # Ollama client, prompt, validation, fallback
│   │   ├── worker.py             # AI worker
│   │   └── runtime.py
│   ├── dashboard/                # React/Vite dashboard (dashboard/dist is built output)
│   ├── scripts/
│   │   └── send_test_report.py
│   ├── main.py                   # starts the AI worker, serves dashboard/dist
│   ├── run.py                    # starts the hub
│   ├── requirements.txt
│   └── .env.example
└── volunteer_app/                # TODO: confirm folder name (Flutter)
    ├── lib/
    │   ├── main.dart
    │   ├── models.dart
    │   ├── api.dart
    │   ├── state.dart
    │   └── screens/
    │       ├── home_screen.dart
    │       ├── report_screen.dart
    │       ├── reports_screen.dart
    │       ├── resources_screen.dart
    │       ├── places_screen.dart
    │       └── settings_screen.dart
    └── android/app/src/main/AndroidManifest.xml
```

The Gemma model has no directory in the repo. Weights are pulled and served by Ollama on the Mac.

## Prerequisites & Dependencies

| Machine | Requirement |
|---|---|
| Windows hub | Python 3.11+, MongoDB Community Server (as a Service), Node.js LTS (only to build the dashboard) |
| Mac AI server | Ollama (version 0.22 or newer for Gemma 4; verify with `ollama --version`), `gemma4:e2b` pulled (about 7.2 GB download per the Ollama library); plugged in and kept awake during use |
| Dev machine (app) | Flutter stable, Dart `>=3.0.0 <4.0.0`, Android device or emulator |
| Flutter packages | `http`, `shared_preferences`, `uuid`, `geolocator` |
| Mac RAM / GPU | TODO: not specified in the sources; measure on your Mac |
| Network | Shared Wi-Fi/router (no uplink needed) or a Windows hotspot; client isolation must be off |

## Quickstart & Local Development Setup

### 1. Clone the repository

```bash
git clone <REPO_URL>
cd <REPO_DIR>
```

### 2. Gemma 4 model setup (Mac)

```bash
ollama --version                 # needs a Gemma 4-capable release
ollama pull gemma4:e2b
ollama list                      # copy the exact tag shown
```

Make Ollama listen on the network (default is localhost only):

```bash
# Ollama menu-bar app, then quit and reopen Ollama
launchctl setenv OLLAMA_HOST "0.0.0.0:11434"

# or run in Terminal
OLLAMA_HOST=0.0.0.0:11434 ollama serve
```

```bash
caffeinate -d                    # keep the Mac awake; leave the terminal open
ipconfig getifaddr en0           # the Mac's Wi-Fi IP
```

Allow incoming connections for Ollama if macOS asks. Ollama then accepts requests from any device on the network, so do not leave it open on public Wi-Fi.

### 3. Backend configuration (Windows hub)

```powershell
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
```

Edit `.env`:

```bash
OLLAMA_BASE_URL=http://<MAC_IP>:11434
OLLAMA_MODEL=gemma4:e2b          # must match `ollama list` exactly
# plus the admin PIN variable defined in .env.example
```

Open the firewall for phones and the dashboard (PowerShell **as Administrator**):

```powershell
New-NetFirewallRule -DisplayName "ReliefLink 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Any
```

Verify the Mac link from Windows (the output should list `gemma4:e2b`):

```powershell
curl.exe http://<MAC_IP>:11434/api/tags
```

### 4. Frontend initialization

**Dashboard** (needs internet once, for npm):

```powershell
cd dashboard
npm install
npm run build                    # creates dashboard\dist
cd ..
```

If the hub has no internet, run these two npm commands on another computer and copy `dashboard\dist` over.

**Flutter app:**

```bash
flutter pub get
flutter run                      # or: flutter build apk
```

### 5. Run the combined stack

```powershell
python run.py
```

The console prints the hub address, the dashboard URL and the AI server in use. Then:

1. Open `http://localhost:8000/docs` and `http://localhost:8000/admin/`.
2. On the phone, confirm `http://<HUB_IP>:8000/docs` opens in the browser (phone on the same Wi-Fi, mobile data off).
3. In the app, tap the gear icon, enter `http://<HUB_IP>:8000`, and tap **Save & test**. You should see a green **Hub online** chip.
4. Send a test report: `python scripts/send_test_report.py`
5. Confirm the dashboard header shows "AI server online" and the report is triaged with source `gemma`.

Use the Windows laptop's IP for phones, not the Mac's and not `localhost`. On a Windows hotspot it is usually `192.168.137.1`. For an emulator on the same machine as the hub, use `http://10.0.2.2:8000`.

If the Mac IP or model tag changes, open `http://localhost:8000/admin/` → *AI server settings*, enter the new URL and model, and click *Save & test*. No restart is needed. Status shows as online, offline or `model_missing`.

## Environment Variables Reference

| Variable / setting | Default | Service | Purpose |
|---|---|---|---|
| `OLLAMA_BASE_URL` | none (set in `.env`) | Backend | Address of the Ollama server, `http://<MAC_IP>:11434` |
| `OLLAMA_MODEL` | none (set in `.env`); `gemma4:e2b` for this project | Backend | Exact model tag from `ollama list` |
| Admin PIN | TODO: variable name not in sources | Backend | Sent by clients as `X-Admin-Pin` |
| `OLLAMA_HOST` | `127.0.0.1:11434` (localhost only); set to `0.0.0.0:11434` | Model (Mac) | Makes Ollama listen on the network |
| Hub URL (in-app setting) | `http://192.168.137.1:8000` | Frontend (Flutter) | Hub address, saved on the device |
| Sync interval (`lib/state.dart`) | 6 seconds | Frontend (Flutter) | `Timer.periodic` sync loop |
| Request timeout (`_timeout` in `lib/api.dart`) | 8 seconds | Frontend (Flutter) | HTTP timeout |

The AI server URL and model can also be changed at runtime from the dashboard; the saved values are stored in MongoDB.

## API & Model Interface Brief

Base path: `/api/v1`. JSON is snake_case, timestamps are ISO-8601 UTC, errors look like `{"error": {"code": "...", "message": "..."}}`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Hub, MongoDB and AI status |
| POST | `/reports/batch` | Offline sync of queued reports (up to 100 per call) |
| GET | `/reports?since=` | Poll for new or updated reports |
| GET | `/resources` | List resources |
| POST | `/resources` | Add a resource (idempotent on `id`) |
| GET | `/locations` | Known places (list shape assumed by the app) |
| GET / PUT | `/admin/ai-server` | Read or set the Ollama URL and model (admin PIN) |

Report payload:

```json
{
  "id": "uuid-v4",
  "raw_text": "3 log fasse hain, budhe ko insulin chahiye, road band hai",
  "lang_hint": "hi",
  "client_created_at": "2026-11-10T07:30:00Z",
  "gps": { "lat": 20.2961, "lng": 85.8245 }
}
```

`lang_hint` and `gps` are optional. A report's `status` is `processing` and `triage` is `null` until the AI worker finishes.

**How reports reach Gemma 4:**
1. `POST /reports/batch` stores each report in MongoDB as `processing`; duplicates by id are ignored.
2. The worker picks up pending reports oldest first (checked every ~8 s) and sends them over HTTP to Ollama at `OLLAMA_BASE_URL` using `OLLAMA_MODEL` (`gemma4:e2b`).
3. The response is validated as JSON. Unusable JSON twice, or 3 timeouts, triggers the rule-based fallback; an unreachable server leaves the report pending.
4. The triaged report (source `gemma` or fallback) appears on the next `GET /reports?since=` poll.

TODO: document the exact Ollama request shape and the prompt/output schema from the code in `app/ai/*`.

## Known Limitations

- Not covered by automated tests; verify manually using the hub's test checklist.
- E2B is the smallest Gemma 4 size; check the `gemma` vs fallback ratio on messy mixed-language reports before relying on it, and switch `OLLAMA_MODEL` to `gemma4:e4b` if too many fall back.
- No authentication for volunteers: anyone on the network can submit reports. Coordinator actions require the admin PIN on the dashboard.
- Cleartext HTTP is enabled for local-network use only. Do not expose the hub to the internet.
- No map view (tiles need internet). Resource creation is not queued offline.

## License & Acknowledgments

- **Project code:** Released under the MIT License. See [LICENSE](LICENSE).
- **Gemma 4:** released by Google in April 2026 and described as Apache 2.0 licensed in third-party sources (verify at `ai.google.dev/gemma` before publishing). Model card: `https://ai.google.dev/gemma/docs/core/model_card_4`.
- Built with FastAPI, MongoDB, React/Vite, Flutter and Ollama.
