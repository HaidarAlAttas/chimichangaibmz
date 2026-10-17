# PulsePal (`chimichangaibmz`)

Contactless vital-signs **screening** for IBM Z Datathon 2026. A Flutter app
records 30 s of face colour with the front camera and sends only per-frame
average colour (never video) to a FastAPI service on IBM LinuxONE (s390x). The
server returns heart rate, an experimental breathing rate, partial NEWS2
early-warning flags and a plain-language explanation.

> Screening only, adults only, not a medical device. SpO₂ is deliberately
> **not** estimated: a phone RGB camera can't measure it reliably.

## Architecture → code

| Diagram box | Code |
|---|---|
| ① Consent + 18+ gate (review) | `lib/screens/consent_screen.dart` |
| ① 1 Patient input | `lib/screens/home_screen.dart` |
| ① 2–3 Camera capture, fixed ROIs → RGB per frame | `lib/services/capture/capture_controller.dart`, `frame_reader.dart`, `lib/config/scan_spec.dart` |
| ① 4 On-device quality gate (ML Kit face check, light, movement) | `lib/services/capture/quality_gate.dart`, `face_detector_service.dart` |
| ① 5 REST egress, single API seam, demo mode | `lib/services/linuxone_api_service.dart` |
| ② 1 Ingest gateway (`POST /scans`, `GET /scans/{id}`, API key) | `linuxone_server/main.py`, `schemas.py` |
| ② 2 Signal DSP (POS, cardiac + separate respiratory band, SQI) | `linuxone_server/pipeline/dsp.py` |
| ② 3 Vitals model (baseline now, trained model plugs in) | `linuxone_server/pipeline/vitals.py` |
| ② 4 Partial NEWS2 flags | `linuxone_server/pipeline/risk.py` |
| ② 5 Explanation (template; Granite 3 optional) | `linuxone_server/pipeline/reasoning.py` |
| ② PostgreSQL (TODO; in-memory for now) | `linuxone_server/store.py` |
| ③ Results dashboard | `lib/screens/results_screen.dart` |
| Offline lane: same ROIs as the phone | `training/roi_reference.py`, `docs/MODEL_INPUT_SPEC.md` |

## Run the app

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # Android or iOS device; front camera required for real scans
```

- **iOS:** needs iOS 15.5+ (ML Kit). `ios/Podfile` already sets this.
- **Simulator / desktop / no camera:** the app falls back to a simulated
  signal. Those results are always marked **DEMO**.
- **Server address:** tap the status chip (top right) → Settings. Default is
  `http://10.0.2.2:8000` (Android emulator → your laptop).
- **Demo mode** (Settings, on by default): if the server can't be reached,
  the app shows sample results labelled **DEMO**. Server errors such as a
  wrong API key are never hidden behind demo data.

### Networking for the demo

Phones block plain `http://` by default. For a dev network this project sets
`usesCleartextTraffic` on Android and `NSAllowsLocalNetworking` on iOS. For
anything outside your own Wi-Fi, put the server behind HTTPS with a
certificate the phone trusts (e.g. a reverse proxy with Let's Encrypt), and
test from a phone on mobile data early.

## Run the server (LinuxONE)

```bash
cd linuxone_server
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
# optional
export PULSEPAL_API_KEY=change-me                     # require Bearer key on /scans
export GRANITE_URL=http://127.0.0.1:8081/v1/chat/completions   # Granite via llama-server (see below)
```

Container (Podman or Docker): `podman build -t pulsepal . && podman run -p 8000:8000 pulsepal`

Tests: `pip install pytest && python -m pytest -q tests`

## Granite on the LinuxONE VM (optional explanation step)

Granite only writes the plain-language "Why this result" text from numbers the
pipeline already computed. It never measures anything, and the suggestion and
disclaimer stay fixed in code. If it's off or fails, a template is used.

For an 8 GB VM: **Granite 3.3 2B Instruct, Q4_K_M (~1.5 GB), big-endian GGUF,
served by llama.cpp `llama-server`.** Convert to big-endian F16 on the Mac, then
quantise on the VM (quantising during conversion produced a broken model).

1. **On your Mac** (the converter needs PyTorch, which has no s390x build):
   `bash linuxone_server/scripts/granite_convert_on_mac.sh`, then
   `scp ~/granite/granite-3.3-2b-instruct-be.f16.gguf <user>@<vm>:~/granite/`
2. **On the VM:** `bash scripts/setup_granite.sh` (builds llama.cpp for s390x and
   quantises the model to Q4_K_M)
3. **Run both** (two terminals or tmux):
   ```bash
   ~/granite/llama.cpp/build/bin/llama-server -m ~/granite/granite-3.3-2b-instruct-be.Q8_0.gguf \
       --host 127.0.0.1 --port 8081 -c 2048 -t $(nproc) --jinja
   GRANITE_URL=http://127.0.0.1:8081/v1/chat/completions uvicorn main:app --host 0.0.0.0 --port 8000
   ```
4. **Check:** `GRANITE_URL=... python3 scripts/check_granite.py`. The app's
   "Why this result" chip then shows **Granite 3** instead of **Template**.

Tuning: `GRANITE_TIMEOUT_S` (default 30), `GRANITE_MAX_TOKENS` (default 120).

## What's real vs. stretch (per the architecture review cut line)

| Item | Status |
|---|---|
| Fixed-ROI capture, quality gate, RGB upload | Done |
| DSP: POS + separate breathing band + SQI gate | Done |
| Heart rate | Spectral baseline now; swap in the trained model in `vitals.load_model()` |
| Breathing rate | Labelled **experimental** in the app |
| Partial NEWS2 flags | Done (heart rate + breathing = 2 of 7 parameters) |
| Explanation | Template now; Granite 3 optional via `GRANITE_URL`, template fallback |
| PostgreSQL | TODO (`store.py`) |
| Snap ML / XGBoost, zDLC on Telum, Secure Execution | Design-slide only unless built and measured |

## Contract

`linuxone_server/schemas.py` ⇄ `lib/models/scan_result.dart`. Change both together.
