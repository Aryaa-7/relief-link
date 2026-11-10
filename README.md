# ReliefLink — two-laptop offline setup (v0.2)

```
 Volunteer phones (Flutter) ──┐
                              ├── Wi-Fi (no internet needed) ──► WINDOWS HUB
 Admin browser (React) ───────┘                                  FastAPI :8000  + MongoDB (localhost)
                                                                       │  HTTP
                                                                       ▼
                                                                  MAC AI SERVER
                                                                  Ollama :11434 + Gemma
```
API contract for the Flutter app is **unchanged** (`/api/v1/...`, `X-Admin-Pin`, `updated_at`, `?since=`).

## STATUS — read this first
Written but **NOT yet run or tested** (the build environment had no Python packages, no MongoDB,
no Ollama, no npm registry and no internet). Nothing below is claimed to work until you tick it off in
section 6. Please paste any error you hit and it will be fixed.

---
## 1. Mac (AI server), one-time
1. Install Ollama, then pull your model and note the **exact tag**: `ollama pull <model>` and `ollama list`.
2. Make Ollama listen on the network (default is localhost only):
   - Ollama menu-bar app: `launchctl setenv OLLAMA_HOST "0.0.0.0:11434"`, then quit and reopen Ollama.
   - or in Terminal: `OLLAMA_HOST=0.0.0.0:11434 ollama serve`
3. If macOS asks to allow incoming connections for Ollama, click **Allow**.
4. Keep the Mac awake during the demo: `caffeinate -d` (leave the terminal open) and keep it plugged in.
5. Find the Mac's IP: `ipconfig getifaddr en0` (Wi-Fi). You need it in section 3.
   (Ollama then accepts requests from any device on the Wi-Fi. Fine for a demo; don't leave it open on public Wi-Fi.)

## 2. Windows (hub), one-time
1. Install **Python 3.11+**, **MongoDB Community Server** (choose "run as a Service"; it listens on localhost only),
   and **Node.js LTS** (only needed to *build* the dashboard).
2. In this folder (PowerShell):
   ```
   python -m venv .venv
   .venv\Scripts\activate
   pip install -r requirements.txt
   copy .env.example .env        # then edit .env: admin PIN, OLLAMA_BASE_URL, OLLAMA_MODEL
   cd dashboard
   npm install
   npm run build                 # creates dashboard\dist  (needs internet ONCE, for npm)
   cd ..
   ```
   No internet on the Windows laptop? Run the two npm commands on any other computer and copy the
   resulting `dashboard\dist` folder over. After that, no Node or internet is needed at all.
3. Allow phones and the dashboard in through the Windows firewall (PowerShell **as Administrator**):
   ```
   New-NetFirewallRule -DisplayName "ReliefLink 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Any
   ```
4. Start: `python run.py`. The console prints the hub address(es), the dashboard URL and the AI server it will use.

## 3. Pointing the hub at the Mac (never hard-coded)
Edit `.env`:
```
OLLAMA_BASE_URL=http://<MAC_IP>:11434
OLLAMA_MODEL=<exact tag from ollama list>
```
**Mac IP changed (new network)?** No restart needed: open `http://localhost:8000/admin/` → *AI server settings*
→ enter the new URL (and model) → *Save & test*. It is saved in MongoDB and shown as online/offline/model_missing.

Test the link from Windows before anything else: `curl.exe http://<MAC_IP>:11434/api/tags` should list your model.

## 4. The two network setups (both need NO internet)
**A. Windows hotspot.** Settings → Network → Mobile hotspot → on. Connect the Mac and phones to it.
Windows is usually `192.168.137.1` (check with `ipconfig`); get the Mac's IP with `ipconfig getifaddr en0`.
Known risk: Windows may refuse to start the hotspot when it has *no* network connection at all. If so, connect
the laptop to any Wi-Fi first, or use setup B. Test this early.

**B. Shared Wi-Fi.** Windows, Mac and phones join the same Wi-Fi/router (a router with no internet uplink is fine).
Some public/college Wi-Fi blocks devices from talking to each other ("client isolation"), so it will not work there.
Use your own router or a phone hotspot.

Phones/Flutter always use `http://<WINDOWS_IP>:8000` (the printed address / QR code). The Mac IP is only for the hub.

## 5. How the AI behaves when the Mac is away
Reports are always accepted and stored (status `processing`). If the Mac or Ollama is unreachable, they simply
stay pending (dashboard: "Waiting for AI server", counter in header) and are processed automatically, oldest first,
as soon as the Mac is back (checked every ~8 s). Rule-based fallback is used only if Gemma answered with unusable
JSON twice, or timed out 3 times for the same report.

## 6. TEST CHECKLIST (tick only what you actually saw)
Do 6a and 6b with internet ON first (to separate bugs from network issues), then repeat 6c with it OFF.

**6a. Hub alone**
- [ ] `python run.py` starts, no "MongoDB not reachable" error.
- [ ] `http://localhost:8000/docs` opens; `GET /api/v1/health` shows `mongo: ok`.
- [ ] `http://localhost:8000/admin/` shows the React dashboard (not the "not built" message).
- [ ] `python scripts/send_test_report.py` → appears on dashboard within ~3 s as pending.
- [ ] Re-sending the same report id returns 200 and no second row appears (idempotency).
- [ ] Changing the Case dropdown asks for the PIN, works, wrong PIN is rejected.

**6b. Mac link**
- [ ] `curl.exe http://<MAC_IP>:11434/api/tags` works from Windows.
- [ ] Dashboard header shows "AI server online"; the pending report becomes triaged with source `gemma`.
- [ ] Stop Ollama on the Mac → send 2 reports → they stay "Waiting for AI server" → start Ollama → both triage by themselves.
- [ ] Change the Mac URL in *AI server settings* to a wrong one and back; status updates each time.
- [ ] Send 10 messy mixed-language reports; check severity/category look sensible.

**6c. Offline proof (internet actually disconnected)**
- [ ] Disconnect every internet source (unplug router uplink / turn off mobile data / hotspot with no uplink).
- [ ] On Windows: `ping 8.8.8.8` fails and a website will not load, so you know it is truly offline.
- [ ] Setup A: Mac + phone join the Windows hotspot. Repeat the 6a + 6b checks.
- [ ] Setup B: all three on the same offline router. Repeat the 6a + 6b checks.
- [ ] Dashboard: browser DevTools → Network tab → reload: every request is to the hub's own address only
      (no google/cdn/fonts hosts).
- [ ] Flutter app: queue a report in airplane mode, reconnect to the hub Wi-Fi, report appears exactly once.

## 7. Troubleshooting
| Symptom | Likely cause |
|---|---|
| Dashboard shows "Dashboard not built yet" | run `npm run build` in `dashboard/`, restart |
| Phones can't open the hub | Windows firewall rule missing, or wrong IP/Wi-Fi, or client isolation |
| AI status `offline` | Mac IP wrong/changed, Ollama not bound to 0.0.0.0, Mac firewall/asleep |
| AI status `model_missing` | `OLLAMA_MODEL` doesn't match `ollama list` exactly |
| Health `mongo: down` | MongoDB service not running |
| Reports stuck on "AI is processing…" | slow Mac; check Ollama on the Mac; after 3 timeouts the fallback is used |

## 8. What changed from v0.1
Replaced: `store.py` (in-memory → MongoDB), `dashboard/` (HTML → React/Vite), `main.py` (starts AI worker, serves `dashboard/dist`).
New: `app/ai/*` (Ollama client, prompt, validation, fallback), `app/worker.py`, `app/runtime.py`,
`/api/v1/admin/ai-server` (GET/PUT, admin PIN). Routes only swapped their data calls; models and endpoints are unchanged
except the additive AI-server models. One small fix: `server_time` is now read *before* the query so polling can't miss an update.
