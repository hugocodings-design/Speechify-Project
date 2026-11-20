# TalkTome — lecteur de livres avec voix IA locales

## Ce qu'est le projet
Application Flutter (Android, iPhone) : on importe des livres (PDF, EPUB, pages web, pages scannées) et on les écoute lus par des voix IA. Tout fonctionne sur le téléphone, sans API payante :
- **Voix IA** : sherpa-onnx (Kokoro, Piper), modèles dans `<support>/tts_models/<dossier>`.
- **Dictionnaire** : base Wiktionary hors ligne (`<support>/dict/dict_<langue>.db`) + sens du mot dans sa phrase par Qwen 3 4B.
- **IA locale Qwen** : llama.cpp intégré (`flutter_app/packages/llama_flutter_android`, Android uniquement), modèle `<support>/llm/qwen3-4b-instruct.gguf`.
- **Traduction en direct** : ML Kit, sur le téléphone.
- **TalkTome Boost** (`pc_server/`) : quand le PC est joignable (Wi-Fi ou Tailscale), voix et Qwen tournent sur sa carte graphique ; sinon le téléphone fait tout.

Les modèles de voix, le dictionnaire et Qwen ne sont pas dans le dépôt : ils ont été copiés sur le téléphone Android à la main.

## Structure
```
TalkTome/
├── flutter_app/   ← l'application
├── pc_server/     ← TalkTome Boost (serveur du PC, voir son README)
├── backend/       ← ancien serveur FastAPI Google Cloud TTS (obsolète, plus utilisé)
└── claude.md
```

## Identifiant de l'app
`com.hugo.talktome` (Android et iOS) depuis le 2026-11-20. L'ancienne app `com.example.speechify` est une app différente pour Android : ses données ont été recopiées dans la nouvelle avec `run-as` (les deux sont des builds debug).

## Compiler et installer sur le téléphone Android (PowerShell)

```powershell
cd "c:\Users\Hdasi\Desktop\PROJETS VISUAL CODE\TalkTome\flutter_app"
$env:PATH += ";C:\Users\Hdasi\Desktop\PROJETS CLAUDE\SPEECHIFY HUGO\flutter_windows_3.41.5-stable\flutter\bin;$env:LOCALAPPDATA\Android\Sdk\platform-tools"
flutter build apk --debug
adb devices
adb -s <appareil> install -r build\app\outputs\flutter-apk\app-debug.apk
```
(Le SDK Flutter est encore rangé dans l'ancien dossier `PROJETS CLAUDE\SPEECHIFY HUGO` sur le PC.)

⚠️ Ne jamais utiliser `flutter install` pour mettre à jour l'app : ça désinstalle l'app avant de la réinstaller et efface toutes les données locales. Toujours `adb install -r`, qui les préserve.

Débogage sans fil : `adb pair <ip>:<port d'appairage>` (une fois), puis `adb connect <ip>:<port>` ; l'appareil s'appelle alors `<ip>:<port>`.

## Dépôt Git / GitHub
- Dépôt : `https://github.com/hugocodings-design/TalkTome`.
- `master` = version Android. La version iPhone vit sur sa propre branche `ios` (section ci-dessous) ; pour lui apporter une nouveauté Android : `git checkout ios && git merge master`. Ne jamais fusionner `ios` dans `master`.

## iPhone (iOS) — branche `ios`

- Installation sur l'iPhone de Carolane depuis un Mac : ouvrir `flutter_app/ios/Runner.xcworkspace` (jamais le `.xcodeproj`), équipe « Carolane Rebelo (Personal Team) », destination = l'iPhone réel (section « iOS Device »), configuration **Release**. Compte gratuit : l'app expire au bout de 7 jours → rebrancher et relancer ▶.
- iOS 15.5 minimum (exigé par ML Kit), fixé dans `ios/Podfile` et le projet Xcode.
- Voix IA : sur iPhone, les modèles sherpa-onnx se téléchargent depuis l'app (Profil → Voix IA, ou le bouton « Voix IA » du sélecteur de voix). Ils viennent des versions officielles `k2-fsa/sherpa-onnx` (`tts-models/<dossier>.tar.bz2`), dans le même dossier que sur Android.
- TalkTome Boost fonctionne sur iPhone (exception ATS + description réseau local dans `Info.plist`). Quand le PC répond, toutes les voix sont proposées, même non installées.
- L'IA Qwen intégrée (`packages/llama_flutter_android`) est Android uniquement : sur iPhone, le dictionnaire/traduction IA ne marche que via TalkTome Boost. Le dictionnaire Wiktionary hors ligne n'est pas encore téléchargeable.
- Mise à jour sur le Mac : `git checkout ios && git pull`, `flutter pub get`, `cd ios && pod install && cd ..`, puis ▶ dans Xcode.
