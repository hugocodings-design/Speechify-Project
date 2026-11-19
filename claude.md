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

## Emplacement unique du projet (mis à jour 2026-08-22)

Tout vit désormais sous ce seul dossier — plus de `C:\dev\speechify` séparé :
```
SPEECHIFY HUGO/
├── backend/          ← serveur FastAPI (TTS)
├── flutter_app/       ← l'application réelle (Accueil, Bibliothèque, +, Paramètres, Profil)
└── claude.md
```

### Pour démarrer (deux terminaux)

```powershell
# Terminal 1 — Backend
cd "c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\SPEECHIFY HUGO\backend"
venv\Scripts\activate
$env:GOOGLE_APPLICATION_CREDENTIALS="c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\SPEECHIFY HUGO\speechify-app-491902-c2f95c0c3aa3.json"
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```
Note : utiliser `python -m uvicorn`, pas `uvicorn.exe` directement — le stub `.exe` est bloqué sur cette machine.

```powershell
# Terminal 2 — Flutter (l'app réelle, avec Accueil/Bibliothèque/Profil)
cd "c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\SPEECHIFY HUGO\flutter_app"
$env:PATH += ";c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\SPEECHIFY HUGO\flutter_windows_3.41.5-stable\flutter\bin"
flutter run -d R5CX81KDFJJ
```

### Pour arrêter
- Backend : Ctrl+C dans le terminal uvicorn
- Flutter : `q` dans le terminal flutter run

⚠️ Ne jamais utiliser `flutter install` pour mettre à jour l'app sur le téléphone — ça désinstalle l'app avant de la réinstaller et efface toutes les données locales (bibliothèque, progression de lecture). Toujours utiliser `adb install -r build\app\outputs\flutter-apk\app-debug.apk`, qui préserve les données.

---

## Dépôt Git / GitHub (ajouté 2026-09-23)

- Le vrai dépôt Git est à la racine de `SPEECHIFY HUGO/` (pas dans `flutter_app/`). Il est déjà connecté à GitHub :
  `https://github.com/hugocodings-design/Speechify-Project` (privé).
- Toujours lancer les commandes `git` depuis `SPEECHIFY HUGO/`, pas depuis `flutter_app/`.
- ⚠️ Piège connu : le dossier `flutter_app/` contient un **second `.git` imbriqué**, orphelin, jamais poussé sur GitHub, avec un historique totalement différent (ancien projet séparé avant la fusion du 2026-08-22). Si une commande `git` lancée depuis `flutter_app/` donne des résultats étranges (historique inconnu, remote absent), c'est ce `.git` parasite qui répond à la place de celui de `SPEECHIFY HUGO/`. Il faudra le supprimer un jour (`flutter_app/.git` uniquement, aucun fichier de code n'est concerné).
- Pour cloner ce projet sur un autre appareil (PC boulot, etc.) : `git clone https://github.com/hugocodings-design/Speechify-Project.git`, puis suivre les instructions de démarrage ci-dessus.

---

## iPhone (iOS) — ajouté 2026-11-19

- Installation sur l'iPhone de Carolane depuis un Mac : ouvrir `flutter_app/ios/Runner.xcworkspace` (jamais le `.xcodeproj`), équipe « Carolane Rebelo (Personal Team) », destination = l'iPhone réel (section « iOS Device »), configuration **Release**. Compte gratuit : l'app expire au bout de 7 jours → rebrancher et relancer ▶.
- Identifiant d'app : `com.hugo.talktome`. iOS 15.5 minimum (exigé par ML Kit), fixé dans `ios/Podfile` et le projet Xcode.
- Voix IA : sur iPhone, les modèles sherpa-onnx se téléchargent depuis l'app (Profil → Voix IA, ou le bouton « Voix IA » du sélecteur de voix). Ils viennent des versions officielles `k2-fsa/sherpa-onnx` (`tts-models/<dossier>.tar.bz2`), dans le même dossier que sur Android.
- Speechify Boost fonctionne sur iPhone (exception ATS + description réseau local dans `Info.plist`). Quand le PC répond, toutes les voix sont proposées, même non installées.
- L'IA Qwen intégrée (`packages/llama_flutter_android`) est Android uniquement : sur iPhone, le dictionnaire/traduction IA ne marche que via Speechify Boost.
- Mise à jour sur le Mac : `git pull`, `flutter pub get`, `cd ios && pod install && cd ..`, puis ▶ dans Xcode.
