"""
Speechify Backend - FastAPI Server
Handles TTS synthesis and voice list management
"""

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
from google.cloud import texttospeech
from google.api_core.exceptions import ResourceExhausted
import asyncio
import os
import io
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

app = FastAPI(title="Speechify API", version="1.0.0")

# CORS middleware to allow Flutter app requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Pydantic models
class SynthesizeRequest(BaseModel):
    text: str
    voice_name: str = "en-US-Journey-D"
    language_code: str = "en-US"

class Voice(BaseModel):
    name: str
    display_name: str
    language_code: str

# Initialize TTS client
try:
    tts_client = texttospeech.TextToSpeechClient()
except Exception as e:
    print(f"Warning: Google Cloud TTS client not initialized: {e}")
    print("Make sure GOOGLE_APPLICATION_CREDENTIALS environment variable is set")
    tts_client = None

# Available voices — vérifiées une à une contre le catalogue réel Google
# Cloud TTS (client.list_voices) le 2026-08-14. "Journey" a été retiré du
# catalogue Google entre-temps ; remplacé par Neural2. fr-FR et pt-PT n'ont
# que 2 voix Neural2/Wavenet distinctes chacune côté Google — pas plus
# disponible, peu importe le nom demandé.
AVAILABLE_VOICES = [
    # ── English (US) — Neural2 ───────────────────────────────────────────────
    {"name": "en-US-Neural2-D",  "display_name": "🇺🇸 English (US) - Male D",     "language_code": "en-US"},
    {"name": "en-US-Neural2-C",  "display_name": "🇺🇸 English (US) - Female C",   "language_code": "en-US"},
    {"name": "en-US-Neural2-F",  "display_name": "🇺🇸 English (US) - Female F",   "language_code": "en-US"},
    # ── English (GB) — Neural2 ───────────────────────────────────────────────
    {"name": "en-GB-Neural2-B",  "display_name": "🇬🇧 English (UK) - Male B",     "language_code": "en-GB"},
    {"name": "en-GB-Neural2-F",  "display_name": "🇬🇧 English (UK) - Female F",   "language_code": "en-GB"},
    # ── Français (Canada) — Neural2 ─────────────────────────────────────────
    {"name": "fr-CA-Neural2-A",  "display_name": "🇨🇦 Français (Canada) - Féminin A",   "language_code": "fr-CA"},
    {"name": "fr-CA-Neural2-B",  "display_name": "🇨🇦 Français (Canada) - Masculin B",  "language_code": "fr-CA"},
    {"name": "fr-CA-Neural2-C",  "display_name": "🇨🇦 Français (Canada) - Féminin C",   "language_code": "fr-CA"},
    {"name": "fr-CA-Neural2-D",  "display_name": "🇨🇦 Français (Canada) - Masculin D",  "language_code": "fr-CA"},
    # ── Français (France) — Neural2 (seulement 2 voix existent chez Google) ─
    {"name": "fr-FR-Neural2-F",  "display_name": "🇫🇷 Français (France) - Féminin F",   "language_code": "fr-FR"},
    {"name": "fr-FR-Neural2-G",  "display_name": "🇫🇷 Français (France) - Masculin G",  "language_code": "fr-FR"},
    # ── Español (España) — Neural2 ──────────────────────────────────────────
    {"name": "es-ES-Neural2-A",  "display_name": "🇪🇸 Español (España) - Femenino A",   "language_code": "es-ES"},
    {"name": "es-ES-Neural2-F",  "display_name": "🇪🇸 Español (España) - Masculino F",  "language_code": "es-ES"},
    {"name": "es-ES-Neural2-H",  "display_name": "🇪🇸 Español (España) - Femenino H",   "language_code": "es-ES"},
    {"name": "es-ES-Neural2-G",  "display_name": "🇪🇸 Español (España) - Masculino G",  "language_code": "es-ES"},
    # ── Español (US) — Neural2 ──────────────────────────────────────────────
    {"name": "es-US-Neural2-A",  "display_name": "🇺🇸 Español (US) - Femenino A",       "language_code": "es-US"},
    {"name": "es-US-Neural2-B",  "display_name": "🇺🇸 Español (US) - Masculino B",      "language_code": "es-US"},
    {"name": "es-US-Neural2-C",  "display_name": "🇺🇸 Español (US) - Femenino C",       "language_code": "es-US"},
    # ── Português (Brasil) — Neural2 ────────────────────────────────────────
    {"name": "pt-BR-Neural2-A",  "display_name": "🇧🇷 Português (Brasil) - Feminino A",  "language_code": "pt-BR"},
    {"name": "pt-BR-Neural2-B",  "display_name": "🇧🇷 Português (Brasil) - Masculino B", "language_code": "pt-BR"},
    {"name": "pt-BR-Neural2-C",  "display_name": "🇧🇷 Português (Brasil) - Feminino C",  "language_code": "pt-BR"},
    # ── Português (Portugal) — Wavenet (pas de Neural2 pour cette langue) ───
    {"name": "pt-PT-Wavenet-E",  "display_name": "🇵🇹 Português (Portugal) - Feminino E",  "language_code": "pt-PT"},
    {"name": "pt-PT-Wavenet-F",  "display_name": "🇵🇹 Português (Portugal) - Masculino F", "language_code": "pt-PT"},
]

# API Routes

@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "ok", "service": "Speechify API"}

@app.get("/api/voices", response_model=dict)
async def get_voices():
    """
    Return list of available TTS voices
    
    Response:
        {
            "voices": [
                {
                    "name": "en-US-Neural2-C",
                    "display_name": "English (US) - Neural C (Male)",
                    "language_code": "en-US"
                },
                ...
            ]
        }
    """
    return {"voices": AVAILABLE_VOICES}

@app.post("/api/synthesize")
async def synthesize_text(request: SynthesizeRequest):
    """
    Synthesize text to speech using Google Cloud TTS
    
    Args:
        text: The text to synthesize
        voice_name: The voice name to use (e.g., "en-US-Neural2-C")
        language_code: The language code (default: "en-US")
    
    Returns:
        {
            "audio_content": base64-encoded MP3 audio,
            "voice_used": "en-US-Neural2-C",
            "characters_used": 1234
        }
    """
    if not tts_client:
        raise HTTPException(status_code=500, detail="TTS client not initialized. Check Google Cloud credentials.")
    
    if not request.text or len(request.text.strip()) == 0:
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    # Dériver le code de langue depuis le nom de la voix (ex: fr-FR-Neural2-B → fr-FR)
    import re as _re
    voice_lang_match = _re.match(r'^([a-z]{2}-[A-Z]{2})', request.voice_name)
    if voice_lang_match:
        request.language_code = voice_lang_match.group(1)
    
    if len(request.text) > 5000:
        raise HTTPException(
            status_code=400,
            detail=f"Text exceeds maximum length of 5000 characters (got {len(request.text)})"
        )
    
    try:
        # Prepare synthesis input
        synthesis_input = texttospeech.SynthesisInput(text=request.text)
        
        # Select voice
        voice = texttospeech.VoiceSelectionParams(
            language_code=request.language_code,
            name=request.voice_name,
        )
        
        # Select audio configuration
        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3,
            speaking_rate=1.0,
        )
        
        # Call TTS API — exécuté dans un thread séparé pour ne pas bloquer
        # la boucle asyncio : c'est un appel réseau synchrone (google-cloud-tts
        # n'a pas de client async), donc l'appeler directement ici bloquerait
        # TOUTES les autres requêtes (y compris les préchargements en
        # parallèle depuis l'app) pendant toute la durée de l'appel.
        #
        # Retry avec backoff sur 429 (quota dépassé) : les voix premium
        # (Journey/Neural2) ont un quota par défaut assez bas côté Google,
        # et l'app envoie plusieurs requêtes de préchargement en parallèle —
        # un 429 occasionnel est normal, pas la peine d'échouer tout de suite.
        max_retries = 3
        response = None
        for attempt in range(max_retries):
            try:
                response = await run_in_threadpool(
                    tts_client.synthesize_speech,
                    input=synthesis_input,
                    voice=voice,
                    audio_config=audio_config,
                )
                break
            except ResourceExhausted:
                if attempt == max_retries - 1:
                    raise
                delay = 0.5 * (2 ** attempt)  # 0.5s, 1s, 2s
                print(f"[TTS] Quota atteint (429), nouvelle tentative dans {delay}s...")
                await asyncio.sleep(delay)
        
        # Return audio content (in production, save to Cloud Storage and return URL)
        import base64
        audio_b64 = base64.b64encode(response.audio_content).decode('utf-8')
        
        return {
            "audio_content": audio_b64,
            "voice_used": request.voice_name,
            "characters_used": len(request.text),
            "format": "mp3"
        }
    
    except Exception as e:
        print(f"[TTS ERROR] {type(e).__name__}: {e}")
        raise HTTPException(status_code=500, detail=f"TTS synthesis failed: {str(e)}")

@app.post("/api/extract-pdf")
async def extract_pdf(file: UploadFile = File(...)):
    """
    Extraire le texte d'un fichier PDF et le retourner en chapitres

    Returns:
        {
            "chapters": [{"id", "title", "textContent", "wordCount", "pageNumber"}],
            "total_pages": 42
        }
    """
    try:
        from pypdf import PdfReader

        content = await file.read()
        reader = PdfReader(io.BytesIO(content))
        total_pages = len(reader.pages)

        if total_pages == 0:
            raise HTTPException(status_code=400, detail="PDF has no pages")

        # Grouper les pages en chapitres (~10 pages chacun, max 20 chapitres)
        pages_per_chapter = max(1, total_pages // 20)
        chapters = []
        chapter_num = 0

        for i in range(0, total_pages, pages_per_chapter):
            page_group = reader.pages[i : i + pages_per_chapter]
            text_parts = []
            for page in page_group:
                page_text = page.extract_text()
                if page_text:
                    text_parts.append(page_text)

            text = "\n\n".join(text_parts).strip()
            if not text:
                continue

            chapter_num += 1
            end_page = min(i + pages_per_chapter, total_pages)
            chapters.append({
                "id": f"ch_{chapter_num}",
                "title": f"Pages {i + 1}–{end_page}",
                "textContent": text,
                "wordCount": len(text.split()),
                "pageNumber": i + 1,
            })

        if not chapters:
            raise HTTPException(
                status_code=400,
                detail="No readable text found. The PDF may be scanned or image-based.",
            )

        return {"chapters": chapters, "total_pages": total_pages}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"PDF extraction failed: {str(e)}")


@app.post("/api/extract-epub")
async def extract_epub(file: UploadFile = File(...)):
    """
    Extraire le texte d'un fichier EPUB et le retourner en chapitres.
    Un EPUB est un fichier ZIP contenant des fichiers HTML/XHTML.
    """
    try:
        import zipfile
        import re as re_module

        content = await file.read()

        import html as html_module

        def strip_html(html_text):
            """Supprime les balises HTML et retourne le texte brut avec sauts de paragraphe."""
            # Les balises de bloc créent un saut de paragraphe
            text = re_module.sub(r'<br\s*/?>',                                       '\n',   html_text, flags=re_module.IGNORECASE)
            text = re_module.sub(r'</(p|div|li|blockquote|h[1-6])>',                '\n\n', text,      flags=re_module.IGNORECASE)
            text = re_module.sub(r'<(p|div|li|blockquote|h[1-6])\b[^>]*/?>',       '\n\n', text,      flags=re_module.IGNORECASE)
            # Supprimer toutes les autres balises
            text = re_module.sub(r'<[^>]+>', '', text)
            # Décoder les entités HTML
            text = html_module.unescape(text)
            # Normaliser les espaces sur chaque ligne sans toucher aux sauts de ligne
            lines = [re_module.sub(r'[^\S\n]+', ' ', line).strip() for line in text.splitlines()]
            text = '\n'.join(lines)
            # Max 2 sauts de ligne consécutifs (= 1 saut de paragraphe)
            text = re_module.sub(r'\n{3,}', '\n\n', text)
            return text.strip()

        def find_opf_path(zf):
            """Trouve le fichier OPF via container.xml."""
            try:
                container = zf.read('META-INF/container.xml').decode('utf-8', errors='ignore')
                m = re_module.search(r'full-path="([^"]+\.opf)"', container)
                if m:
                    return m.group(1)
            except Exception:
                pass
            # Fallback : chercher directement
            for name in zf.namelist():
                if name.endswith('.opf'):
                    return name
            return None

        def get_spine_order(zf, opf_path):
            """Retourne les fichiers HTML dans l'ordre de lecture défini par le spine OPF."""
            opf_dir = '/'.join(opf_path.split('/')[:-1])
            opf_content = zf.read(opf_path).decode('utf-8', errors='ignore')

            # Construire le mapping id → href depuis le manifest
            # Supporte n'importe quel ordre des attributs (id avant ou après href)
            manifest = {}
            for m in re_module.finditer(r'<item\b[^>]*>', opf_content):
                item_tag = m.group(0)
                id_m = re_module.search(r'\bid="([^"]+)"', item_tag)
                href_m = re_module.search(r'\bhref="([^"]+)"', item_tag)
                if id_m and href_m:
                    manifest[id_m.group(1)] = href_m.group(1)

            # Lire l'ordre du spine
            spine_match = re_module.search(r'<spine[^>]*>(.*?)</spine>', opf_content, re_module.DOTALL)
            if not spine_match:
                return []

            ordered_files = []
            for m in re_module.finditer(r'<itemref[^>]+idref="([^"]+)"', spine_match.group(1)):
                idref = m.group(1)
                if idref in manifest:
                    href = manifest[idref]
                    if opf_dir:
                        full_path = opf_dir + '/' + href
                    else:
                        full_path = href
                    # Normaliser le chemin
                    full_path = full_path.replace('\\', '/')
                    ordered_files.append(full_path)

            return ordered_files

        with zipfile.ZipFile(io.BytesIO(content)) as zf:
            opf_path = find_opf_path(zf)
            html_files = []

            if opf_path:
                html_files = get_spine_order(zf, opf_path)

            # Fallback si le spine n'a rien donné
            if not html_files:
                html_files = sorted([
                    n for n in zf.namelist()
                    if n.endswith(('.html', '.xhtml', '.htm'))
                    and 'toc' not in n.lower()
                ])

            if not html_files:
                raise HTTPException(status_code=400, detail="Aucun contenu HTML trouvé dans l'EPUB.")

            chapters = []
            for i, filepath in enumerate(html_files):
                try:
                    raw = zf.read(filepath).decode('utf-8', errors='ignore')
                except Exception:
                    continue

                # Extraire le titre depuis <title> ou <h1>/<h2>
                title_match = (
                    re_module.search(r'<title[^>]*>(.*?)</title>', raw, re_module.IGNORECASE | re_module.DOTALL) or
                    re_module.search(r'<h[12][^>]*>(.*?)</h[12]>', raw, re_module.IGNORECASE | re_module.DOTALL)
                )
                title = strip_html(title_match.group(1)) if title_match else f'Chapitre {i + 1}'
                if not title or len(title) > 100:
                    title = f'Chapitre {i + 1}'

                # Extraire uniquement le corps du texte
                body_match = re_module.search(r'<body[^>]*>(.*?)</body>', raw, re_module.IGNORECASE | re_module.DOTALL)
                body = body_match.group(1) if body_match else raw
                text = strip_html(body)

                if len(text) < 50:  # Ignorer les pages quasi-vides
                    continue

                chapters.append({
                    'id': f'ch_{i + 1}',
                    'title': title,
                    'textContent': text,
                    'wordCount': len(text.split()),
                    'pageNumber': i + 1,
                })

        if not chapters:
            raise HTTPException(status_code=400, detail="Aucun texte lisible trouvé dans l'EPUB.")

        return {'chapters': chapters, 'total_chapters': len(chapters)}

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Extraction EPUB échouée: {str(e)}")


# Catch-all for debugging
@app.get("/api/")
async def api_root():
    """API root endpoint"""
    return {
        "service": "Speechify API",
        "version": "1.0.0",
        "endpoints": {
            "health": "/api/health",
            "voices": "/api/voices",
            "synthesize": "/api/synthesize"
        }
    }

if __name__ == "__main__":
    import uvicorn
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host=host, port=port)
