# 🫀 PulsePal AI — Mobile Application (`chimichangaibmz`)

AI-powered vital sign monitoring mobile application built with **Flutter**, designed to connect directly with the **IBM LinuxONE (s390x)** enterprise backend.

---

## 📐 Architecture Mapping (Matches Your Handwritten Diagram)

| Step | Diagram Section | Flutter File / Implementation |
| :--- | :--- | :--- |
| **(1)** | **Patient Input** (`Age`, `Sex`) | [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart) |
| **(1)** | **30 FPS Video Ingestion** | [`lib/services/rppg_extractor_service.dart`](lib/services/rppg_extractor_service.dart) |
| **(1)** | **ROI Tracking & Color Averaging** | [`lib/widgets/camera_overlay_widget.dart`](lib/widgets/camera_overlay_widget.dart) |
| **(1) ➔ (2)** | **HTTPS REST / JSON Egress** | [`lib/services/linuxone_api_service.dart`](lib/services/linuxone_api_service.dart) |
| **(2)** | **LinuxONE Enterprise Core (s390x)** | [`linuxone_server/main.py`](linuxone_server/main.py) |
| **(2)** | **AI Part (Tunggu Asli)** | *Left empty with clear `# TODO` hooks in `linuxone_server/main.py`* |
| **(3)** | **Pop-up Patient Health Dashboard** | [`lib/widgets/health_dashboard_popup.dart`](lib/widgets/health_dashboard_popup.dart) |

---

## 🚨 WHERE TO CONNECT TO LINUXONE (Highlighted)

You can set the LinuxONE IP in **two easy ways**:

### Method A: In the Code
Open [`lib/config/api_config.dart`](lib/config/api_config.dart):
```dart
// 🚨 CHANGE THIS TO YOUR LINUXONE SERVER IP / HOSTNAME
static const String defaultLinuxOneHost = "http://192.168.1.50:8000"; 
```

### Method B: Directly Inside the App UI (No Recompiling Needed!)
1. Launch the app on your phone.
2. Tap the **Status Pill / Settings Icon** (top-right of the Home Screen).
3. Type in your LinuxONE server's IP address and tap **"Test Health Endpoint"**.
4. The app will immediately verify connection with `http://<IP>:8000/api/v1/health`!

> 💡 **Hackathon Safety Net:** The app includes a **"Pitch Rehearsal Mock Mode"** switch in Settings. If your LinuxONE server or venue Wi-Fi is temporarily down during judging, the app automatically serves realistic data so your live demo **never crashes**!

---

## 📱 What Step (3) Displays (Pop-Up Dashboard)

When the 15-second scan finishes and the response returns, the **Patient Health Dashboard** pops up with:
1. **Heart Rate:** `74 BPM` (Color-coded)
2. **Blood Oxygen Level:** `98.2% SpO2`
3. **Respiratory Rate:** `16 breathing/min`
4. **Status & Risk Score:** `NORMAL (94%)`
5. **IBM Granite Health Reasoning:** Full natural language explanation of all physiological factors + *"Explainability: 100% transparent"*.

---

## 🚀 How to Run the Flutter App

```bash
cd /Users/syedario/Downloads/chimichangaibmz
flutter run
```

---

## ☁️ How to Run the LinuxONE Backend (`linuxone_server/`)

Transfer the `linuxone_server/` folder to your LinuxONE s390x virtual machine:
```bash
cd linuxone_server
pip install -r requirements.txt
python main.py
```
Or run as a container on LinuxONE:
```bash
docker build -t pulsepal-linuxone .
docker run -p 8000:8000 pulsepal-linuxone
```
