# Speechify — AI-Powered Ebook Reader with TTS

## What This Project Is
A Flutter cross-platform mobile app that lets you upload ebooks (PDFs/EPUBs) and listen to them read aloud using Google Cloud Text-to-Speech with multiple voice options.

## Phase 1 Status: COMPLETE ✅
- Backend FastAPI server with Google Cloud TTS integration: **DONE**
- Flutter project structure & core models: **DONE**  
- Services (TTS, File extraction, Audio player): **DONE**
- **Next:** Follow [PHASE_1_SETUP.md](./PHASE_1_SETUP.md) to set up credentials and test both services

---

## Tech Stack
- **Frontend:** Flutter (Dart) + Material Design 3
- **Audio Playback:** just_audio package
- **Local Database:** Hive (key-value store)
- **Text Extraction:** pdf + epub (Dart packages)
- **TTS Engine:** Google Cloud Text-to-Speech API
- **Backend:** Node.js/Python (FastAPI recommended)
- **Deployment:** Google Cloud Run (or AWS Lambda)

---

## Project Structure
SPEECHIFY HUGO/
├── claude.md
├── backend/
│ ├── server.js (or main.py)
│ ├── requirements.txt
│ ├── .env.example
│ └── api/
│ ├── voices (GET - list available voices)
│ └── synthesize (POST - TTS endpoint)
├── flutter_app/
│ ├── pubspec.yaml
│ ├── lib/
│ │ ├── main.dart
│ │ ├── screens/
│ │ │ ├── home_screen.dart
│ │ │ ├── upload_screen.dart
│ │ │ ├── reader_screen.dart
│ │ │ └── settings_screen.dart
│ │ ├── models/
│ │ │ ├── ebook.dart
│ │ │ ├── chapter.dart
│ │ │ └── audio_chunk.dart
│ │ └── services/
│ │ ├── tts_service.dart
│ │ ├── file_service.dart
│ │ └── audio_service.dart
└── docs/
└── setup_guide.md

---

## Core Features (MVP)
✅ Upload PDF/EPUB ebooks  
✅ Extract text by chapter  
✅ Voice selection (380+ voices from Google Cloud TTS)  
✅ AI-powered audio synthesis  
✅ Audio player with controls (play/pause, seek, speed 0.75x–1.5x)  
✅ Local progress tracking (resume where you left off)  
✅ Offline audio playback  

---

## Technology Decisions

| Component | Choice | Why |
|-----------|--------|-----|
| **Framework** | Flutter (Dart) | Single codebase for iOS & Android, easier language, hot reload |
| **TTS Engine** | Google Cloud TTS | 380+ voices, affordable ($0.30/300-page book), reliable |
| **Audio Player** | just_audio | Best Flutter audio package, playback speed, background audio |
| **Local DB** | Hive | Lightweight, fast, perfect for local-only app |
| **Text Extraction** | pdf + epub packages | No native dependencies, pure Dart |
| **Backend** | FastAPI (Python) | Simple setup, easy TTS integration |

---

## Implementation Plan (2–4 weeks)

### Phase 1: Backend + Flutter Setup (2–3 days)
- [ ] Create Flutter project: `flutter create speechify`
- [ ] Add pubspec.yaml dependencies
- [ ] Deploy backend with 2 endpoints: `/api/voices` and `/api/synthesize`
- [ ] Set up Google Cloud TTS credentials

### Phase 2: Ebook Upload & Text Extraction (3–4 days)
- [ ] Build file picker UI
- [ ] Implement PDF/EPUB text extraction
- [ ] Split text into chunks, store in Hive
- [ ] Display chapters with word counts

### Phase 3: Voice Selection + TTS + Audio Player (4–5 days)
- [ ] Voice selector dropdown UI
- [ ] Google Cloud TTS integration
- [ ] Audio player with just_audio
- [ ] Playback speed & seek controls
- [ ] Cache audio locally

### Phase 4: UI Polish & Testing (2–3 days)
- [ ] Complete Material Design 3 UI
- [ ] Test on Android emulator (Windows)
- [ ] Manual testing with real ebooks
- [ ] Bug fixes & optimization

---

## Estimated Costs
- **Google Cloud TTS:** ~$0.30 per 300-page book
- **Cloud Run hosting:** ~$5–10/month (free tier for POC)
- **Total:** <$30 for initial testing

---

## Commands (To Be Added)

### Backend Startup
```bash
cd backend
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
python main.py  # Start on localhost:8000

COMMANDED TO START BACKEND :
cd "c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\SPEECHIFY HUGO\backend"
venv\Scripts\activate
$env:GOOGLE_APPLICATION_CREDENTIALS="c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\SPEECHIFY HUGO\speechify-copy-bc0092c5c34f.json"
uvicorn main:app --reload --host 0.0.0.0 --port 8000


Flutter Startup
cd flutter_app
flutter pub get
flutter run  # Android emulator (Windows)

Oui, deux choses rapides :

Arrêtez le serveur backend — dans le terminal où tourne uvicorn, appuyez Ctrl+C

Arrêtez Flutter — dans le terminal Flutter, appuyez q

C'est tout. Bonne nuit ! 🌙

La prochaine fois, pour redémarrer :


# Terminal 1 — Backend
cd "c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\SPEECHIFY HUGO\backend"
venv\Scripts\activate
$env:GOOGLE_APPLICATION_CREDENTIALS="c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\SPEECHIFY HUGO\speechify-copy-bc0092c5c34f.json"
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Terminal 2 — Flutter
cd C:\dev\speechify
$env:PATH += ";c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\SPEECHIFY HUGO\flutter_windows_3.41.5-stable\flutter\bin"
flutter run -d R5CX81KDFJJ
