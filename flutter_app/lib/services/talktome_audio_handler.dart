import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'tts_service.dart';
import 'local_tts_service.dart';
import 'google_tts_direct_service.dart';
import '../models/word_timing.dart';

/// Gère la session média Android (foreground service + notification de lecture).
/// Contient la boucle complète de synthèse + lecture pour que tout fonctionne
/// en arrière-plan sans être throttlé par Android.
class TalkTomeAudioHandler extends BaseAudioHandler {
  static TalkTomeAudioHandler? _instance;
  static TalkTomeAudioHandler? get instance => _instance;

  // Double-buffer : deux lecteurs pour transitions instantanées entre phrases
  final List<AudioPlayer> _players = [AudioPlayer(), AudioPlayer()];
  int _currentIdx = 0;

  AudioPlayer get _currentPlayer => _players[_currentIdx];
  AudioPlayer get _bufferPlayer  => _players[1 - _currentIdx];

  // ── État de session ────────────────────────────────────────────────────────

  List<String> _sentenceTexts = [];
  String _bookTitle = '';
  int _currentIndex = 0;

  /// Id du livre (Hive) en cours de lecture — utilisé par le mini-lecteur
  /// affiché en bas de l'app pour retrouver l'Ebook complet (couverture,
  /// nombre de mots) et y naviguer d'un tap, peu importe l'écran affiché.
  final ValueNotifier<String?> currentEbookIdNotifier = ValueNotifier(null);

  String get bookTitle => _bookTitle;
  int get totalSentenceCount => _sentenceTexts.length;
  double get speed => _speed;
  TtsService? _ttsService;
  final GoogleTtsDirectService _googleTts = GoogleTtsDirectService();
  final LocalTtsService _localTts = LocalTtsService();
  String _voiceName = 'en-US-Neural2-C';
  String _languageCode = 'en-US';
  double _speed = 1.0;
  bool _isSessionActive = false;
  bool _isPlaying = false;

  /// Vrai si la voix sélectionnée est une voix locale (moteur du téléphone,
  /// hors ligne) plutôt qu'une voix cloud nécessitant réseau + quota API.
  bool get _isLocalVoice => _voiceName.startsWith('local-');

  // ── Cache de pré-synthèse ──────────────────────────────────────────────────

  String? _prefetchedPath;
  int? _prefetchedIndex;
  List<WordTiming>? _prefetchedWords;
  int _synthesisToken = 0;
  int _prefetchToken = 0;
  int? _bufferLoadedIndex;

  /// Timings mot par mot (secondes depuis le début de la phrase) pour la
  /// phrase en cours de lecture — alimente currentWordIndexNotifier.
  List<WordTiming> _currentWordTimings = [];
  Timer? _wordTrackingTimer;

  /// Cache des phrases pré-synthétisées sur disque, au-delà de celle chargée
  /// dans le buffer (indexée par numéro de phrase, pas par "distance" — donc
  /// aucun conflit possible quand plusieurs préchargements tournent en
  /// parallèle). Vidé uniquement lors d'un changement de voix, puisque c'est
  /// le seul cas où un fichier en cache devient réellement incorrect (les
  /// autres cas — sauter en arrière, changer de phrase — laissent le contenu
  /// déjà en cache tout à fait valable pour son propre index).
  final Map<int, String> _prefetchCache = {};
  final Map<int, List<WordTiming>> _prefetchWordCache = {};
  int _voiceGeneration = 0;

  // ── Notifiers pour l'UI ───────────────────────────────────────────────────

  /// Index de la phrase en cours — l'UI écoute ça pour le scroll et le surlignage
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier(0);

  /// Index du mot en cours DANS la phrase courante (-1 = aucun mot actif /
  /// pas de timing disponible pour cette phrase). Alimente le surlignage
  /// mot par mot, en plus du surlignage de la phrase entière.
  final ValueNotifier<int> currentWordIndexNotifier = ValueNotifier(-1);

  /// Vrai pendant la synthèse TTS — l'UI affiche un spinner sur le bouton play
  final ValueNotifier<bool> isSynthesizingNotifier = ValueNotifier(false);

  /// Intention de l'utilisateur (jouer ou pause) — respectée même quand la
  /// synthèse est en cours, pour qu'un pause pendant le chargement empêche
  /// bien la lecture automatique une fois l'audio prêt. L'UI écoute ça pour
  /// savoir quelle action déclencher au prochain tap, sans dépendre d'un
  /// état de lecture qui peut être temporairement désynchronisé pendant
  /// un chargement.
  final ValueNotifier<bool> shouldBePlayingNotifier = ValueNotifier(true);

  /// Diagnostic temporaire : liste les voix TTS locales installées sur
  /// l'appareil (visible dans les logs adb).
  Future<void> debugListLocalVoices() => _localTts.debugListVoices();

  /// Diagnostic temporaire : fait parler chaque voix candidate d'une langue
  /// l'une après l'autre pour identifier les genres à l'oreille. Appeler
  /// depuis main() avec les codes bruts trouvés via debugListLocalVoices().
  Future<void> debugSpeakCandidates(
    List<String> deviceVoiceNames,
    String languageCode, {
    List<String>? phrases,
  }) =>
      _localTts.debugSpeakCandidates(deviceVoiceNames, languageCode, phrases: phrases);

  /// Diagnostic temporaire : teste les 5 voix locales françaises (France)
  /// disponibles sur l'appareil, en annonçant chacune en français.
  Future<void> debugSpeakFrFrCandidates() => debugSpeakCandidates(
        const [
          'fr-fr-x-frc-local',
          'fr-fr-x-frb-local',
          'fr-fr-x-fra-local',
          'fr-fr-x-vlf-local',
          'fr-fr-x-frd-local',
        ],
        'fr-FR',
        phrases: const [
          'Voix numéro un.',
          'Voix numéro deux.',
          'Voix numéro trois.',
          'Voix numéro quatre.',
          'Voix numéro cinq.',
        ],
      );

  TalkTomeAudioHandler() {
    _instance = this;
    _setupPlayerListeners();
  }

  /// Écouter les deux lecteurs — réagir uniquement au lecteur courant
  void _setupPlayerListeners() {
    for (int i = 0; i < 2; i++) {
      final idx = i; // capture par valeur pour la closure
      _players[idx].playerStateStream.listen((state) {
        if (idx != _currentIdx) return;
        _onPlayerStateChanged(state);
      });
    }
  }

  void _onPlayerStateChanged(PlayerState state) {
    // Phrase terminée → passer à la suivante
    if (state.processingState == ProcessingState.completed && _isPlaying) {
      _isPlaying = false;
      _onSentenceFinished();
      return;
    }
    // Ignorer les états "completed + not playing" (transition normale)
    if (!state.playing && state.processingState == ProcessingState.completed) return;

    _isPlaying = state.playing;
    _updateNotification(playing: state.playing);
  }

  void _onSentenceFinished() {
    if (_currentIndex < _sentenceTexts.length - 1) {
      _playSentence(_currentIndex + 1);
    } else {
      // Fin du livre
      _isPlaying = false;
      isSynthesizingNotifier.value = false;
      _updateNotification(playing: false);
    }
  }

  // ── Configuration de session ───────────────────────────────────────────────

  /// Appeler quand on ouvre un livre. Initialise le handler pour cette session.
  void startSession({
    required List<String> sentences,
    required String bookTitle,
    required String ebookId,
    required TtsService ttsService,
    required String voiceName,
    required String languageCode,
    required double speed,
    required int startIndex,
  }) {
    // Annuler toute synthèse en cours avant de changer de session
    _synthesisToken++;
    _prefetchToken++;
    _voiceGeneration++;

    _sentenceTexts = sentences;
    _bookTitle = bookTitle;
    currentEbookIdNotifier.value = ebookId;
    _ttsService = ttsService;
    _voiceName = voiceName;
    _languageCode = languageCode;
    _speed = speed;
    _currentIndex = startIndex;
    _isSessionActive = true;
    _isPlaying = false;
    // Faux à l'ouverture : rien ne joue encore (seul un préchargement est
    // lancé plus bas), donc le bouton doit afficher ▶ « prêt à jouer », pas
    // ⏸ comme si la lecture était déjà en cours. Le mettre à `true` ici
    // forçait l'utilisateur à appuyer sur pause puis sur play pour que la
    // première lecture démarre réellement.
    shouldBePlayingNotifier.value = false;
    isSynthesizingNotifier.value = false;
    currentIndexNotifier.value = startIndex;

    // Vider le cache de pré-synthèse
    _prefetchedPath = null;
    _prefetchedIndex = null;
    _prefetchedWords = null;
    _prefetchCache.clear();
    _prefetchWordCache.clear();
    _bufferLoadedIndex = null;
    _resetWordTracking();

    _updateMediaItem();
    _updateNotification(playing: false);

    // Précharger la phrase de départ (et la suivante) dès l'ouverture du
    // livre : quand l'utilisateur appuie sur play pour la première fois,
    // l'audio est déjà prêt au lieu d'attendre l'appel réseau à ce moment-là.
    _prefetchAhead(startIndex - 1);
  }

  /// Mettre à jour la voix (invalide le cache de pré-synthèse)
  void updateVoice(String voiceName, String languageCode) {
    _voiceName = voiceName;
    _languageCode = languageCode;
    // Invalider le cache — les fichiers pré-synthétisés sont pour l'ancienne voix
    _prefetchToken++;
    _voiceGeneration++;
    _prefetchedPath = null;
    _prefetchedIndex = null;
    _prefetchedWords = null;
    _prefetchCache.clear();
    _prefetchWordCache.clear();
    _bufferLoadedIndex = null;
  }

  /// Mettre à jour la vitesse de lecture
  void updateSpeed(double speed) {
    _speed = speed;
    _players[0].setSpeed(speed);
    _players[1].setSpeed(speed);
  }

  // ── Contrôles audio (BaseAudioHandler — appelés depuis la notification) ────

  @override
  Future<void> play() async {
    if (!_isSessionActive) return;
    shouldBePlayingNotifier.value = true;

    if (_isLocalVoice) {
      // Le moteur natif ne sait pas reprendre au milieu d'une phrase —
      // on relit simplement la phrase courante depuis le début.
      await _playSentenceLocal(_currentIndex);
      return;
    }

    // Si synthèse en cours, marquer comme "doit jouer" — _playSentence jouera automatiquement
    if (isSynthesizingNotifier.value) {
      _isPlaying = true;
      _updateNotification(playing: true);
      return;
    }
    if (_currentPlayer.duration != null) {
      // Audio déjà chargé → reprendre la lecture. unawaited : le Future de
      // just_audio play() ne se termine qu'à la fin de la phrase, pas à son
      // démarrage — l'attendre ici bloquerait cette méthode jusqu'à la fin
      // de la phrase en cours.
      unawaited(_currentPlayer.play());
      _isPlaying = true;
      _startWordTracking(); // reprend le suivi mot par mot après une pause
    } else {
      // Pas d'audio chargé → synthétiser et jouer
      await _playSentence(_currentIndex);
    }
  }

  @override
  Future<void> pause() async {
    // Toujours honoré immédiatement, même pendant une synthèse en cours :
    // empêche la lecture automatique de démarrer une fois l'audio prêt.
    shouldBePlayingNotifier.value = false;
    _isPlaying = false;
    _pauseWordTracking();
    if (_isLocalVoice) {
      await _localTts.stop();
    } else {
      await _currentPlayer.pause();
    }
    _updateNotification(playing: false);
  }

  @override
  Future<void> skipToNext() async {
    final next = _currentIndex + 1;
    if (next < _sentenceTexts.length && !isSynthesizingNotifier.value) {
      shouldBePlayingNotifier.value = true;
      _currentPlayer.stop();
      unawaited(_localTts.stop());
      await _playSentence(next);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final prev = _currentIndex - 1;
    if (prev >= 0 && !isSynthesizingNotifier.value) {
      shouldBePlayingNotifier.value = true;
      // Saut en arrière : invalide seulement le buffer en cours de
      // préchargement (le cache par index reste valable pour son propre
      // index, peu importe le sens de navigation).
      _prefetchToken++;
      _currentPlayer.stop();
      unawaited(_localTts.stop());
      await _playSentence(prev);
    }
  }

  /// Sauter à une phrase précise (tap sur le texte ou navigation)
  Future<void> playSentenceAt(int index) async {
    if (index < 0 || index >= _sentenceTexts.length) return;
    debugPrint('[WORD-TRACK] >>> playSentenceAt($index) — tap manuel');
    shouldBePlayingNotifier.value = true;
    // Saut arbitraire : invalide seulement le buffer en cours de
    // préchargement (le cache par index reste valable pour son propre
    // index, peu importe où on saute).
    _prefetchToken++;
    // Annule toute requête réseau en cours (tap précédent encore en train de
    // charger, préchargement en fond) : sans ça, taper plusieurs phrases
    // rapidement empile des requêtes concurrentes qui se disputent le même
    // quota au lieu de laisser la place nette à celle qu'on veut vraiment.
    _ttsService?.cancel();
    _googleTts.cancel();
    _currentPlayer.stop();
    unawaited(_localTts.stop());
    await _playSentence(index);
  }

  /// Positionner le curseur sans démarrer la lecture (navigation par chapitre)
  void stopAndSeekTo(int index) {
    _synthesisToken++;
    _prefetchToken++;
    _currentPlayer.stop();
    _bufferPlayer.stop();
    unawaited(_localTts.stop());
    _localTts.setWordBoundaryHandler(null);
    _resetWordTracking();
    _currentIndex = index;
    _isPlaying = false;
    shouldBePlayingNotifier.value = false;
    _bufferLoadedIndex = null;
    _prefetchedPath = null;
    _prefetchedIndex = null;
    _prefetchedWords = null;
    isSynthesizingNotifier.value = false;
    _updateNotification(playing: false);
  }

  // ── Boucle de synthèse + lecture (cœur du foreground service) ─────────────

  Future<void> _playSentence(int index) async {
    if (index < 0 || index >= _sentenceTexts.length) return;
    if (_isLocalVoice) return _playSentenceLocal(index);

    _synthesisToken++;
    final myToken = _synthesisToken;

    _currentIndex = index;
    currentIndexNotifier.value = index;
    isSynthesizingNotifier.value = true;
    debugPrint('[LOAD-TRACK] phrase $index : isSynthesizing=true (token=$myToken)');
    _resetWordTracking();

    // Mettre à jour la notification avec le numéro de phrase et la progression
    _updateMediaItem();
    _updateNotification(playing: _isPlaying, loading: true);

    try {
      // ── Chemin 1 : buffer pré-chargé → swap instantané ──────────────────
      if (_bufferLoadedIndex == index) {
        _currentPlayer.stop();
        _swapPlayers();
        _currentWordTimings = _prefetchedWords ?? [];
        _prefetchedWords = null;
        debugPrint('[WORD-TRACK] phrase $index (buffer) : ${_currentWordTimings.length} mots');

        unawaited(_currentPlayer.setSpeed(_speed));
        if (shouldBePlayingNotifier.value) {
          unawaited(_currentPlayer.play());
          _isPlaying = true;
          _startWordTracking();
        } else {
          _isPlaying = false;
        }

        isSynthesizingNotifier.value = false;
        debugPrint('[LOAD-TRACK] phrase $index (buffer) : isSynthesizing=false');
        _updateNotification(playing: _isPlaying);
        _prefetchAhead(index);
        return;
      }

      // ── Chemin 2 : synthèse directe ──────────────────────────────────────
      _currentPlayer.stop();

      String audioPath;
      List<WordTiming> words;

      if (_prefetchedIndex == index && _prefetchedPath != null) {
        // Fichier déjà synthétisé (niveau 1 du pipeline)
        audioPath = _prefetchedPath!;
        words = _prefetchedWords ?? [];
        _prefetchedPath = null;
        _prefetchedIndex = null;
        _prefetchedWords = null;
      } else if (_prefetchCache.containsKey(index)) {
        // Fichier déjà synthétisé (cache de préchargement) — évite un appel
        // réseau redondant quand cette phrase a déjà été pré-synthétisée
        audioPath = _prefetchCache.remove(index)!;
        words = _prefetchWordCache.remove(index) ?? [];
      } else {
        // Invalider tout pré-chargement en cours qui ne correspond plus
        _prefetchToken++;

        final callStart = DateTime.now();
        debugPrint('[LOAD-TRACK] phrase $index : appel réseau démarré (token=$myToken)');
        final result = await _googleTts.synthesizeText(
          text: _sentenceTexts[index],
          voiceName: _voiceName,
          languageCode: _languageCode,
        );
        final elapsed = DateTime.now().difference(callStart).inMilliseconds;
        debugPrint('[LOAD-TRACK] phrase $index : appel réseau terminé en ${elapsed}ms '
            '(token=$myToken, actuel=$_synthesisToken)');
        if (myToken != _synthesisToken) return;

        final audioBytes = base64Decode(result['audio_content'] as String);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/sentence_$index.mp3');
        await tempFile.writeAsBytes(audioBytes);
        audioPath = tempFile.path;
        words = parseWordTimings(result['word_timings']);
      }

      if (myToken != _synthesisToken) return;

      _currentWordTimings = words;
      debugPrint('[WORD-TRACK] phrase $index (direct) : ${_currentWordTimings.length} mots '
          '(texte: ${_sentenceTexts[index].split(' ').length} mots)');
      await _currentPlayer.setAudioSource(AudioSource.uri(Uri.file(audioPath)));
      await _currentPlayer.setSpeed(_speed);

      if (shouldBePlayingNotifier.value) {
        // unawaited, PAS "await" : le Future de just_audio play() ne se
        // termine qu'à la fin de la lecture, pas à son démarrage — l'attendre
        // ici bloquait tout (spinner, suivi mot par mot) pendant TOUTE la
        // durée de la phrase, exactement comme le chemin buffer le fait déjà
        // correctement plus haut.
        unawaited(_currentPlayer.play());
        _isPlaying = true;
        _startWordTracking();
      } else {
        _isPlaying = false;
      }

      isSynthesizingNotifier.value = false;
      debugPrint('[LOAD-TRACK] phrase $index (direct) : isSynthesizing=false');
      _updateNotification(playing: _isPlaying);
      _prefetchAhead(index);
    } catch (e) {
      if (myToken != _synthesisToken) {
        debugPrint('[LOAD-TRACK] phrase $index : erreur ignorée, token périmé ($myToken vs $_synthesisToken) — $e');
        return;
      }
      // Annulation silencieuse (ex: changement de phrase pendant la synthèse)
      if (e.toString().contains('cancelled')) {
        isSynthesizingNotifier.value = false;
        debugPrint('[LOAD-TRACK] phrase $index : annulée, isSynthesizing=false');
        return;
      }
      isSynthesizingNotifier.value = false;
      debugPrint('[LOAD-TRACK] phrase $index : ❌ erreur, isSynthesizing=false — $e');
    }
  }

  /// Lit une phrase avec le moteur TTS local du téléphone — pas de réseau,
  /// pas de préchargement nécessaire (c'est déjà instantané localement).
  Future<void> _playSentenceLocal(int index) async {
    _synthesisToken++;
    final myToken = _synthesisToken;

    _currentIndex = index;
    currentIndexNotifier.value = index;
    isSynthesizingNotifier.value = false; // pas d'attente réseau en local
    _resetWordTracking();

    _updateMediaItem();

    if (!shouldBePlayingNotifier.value) {
      _isPlaying = false;
      _localTts.setWordBoundaryHandler(null);
      _updateNotification(playing: false);
      return;
    }

    final localVoice = LocalTtsService.availableVoices.firstWhere(
      (v) => v.name == _voiceName,
      orElse: () => LocalTtsService.availableVoices.first,
    );

    // Offsets de caractère de début de chaque mot — le callback de
    // progression natif donne un offset caractère, pas un index de mot.
    final sentenceText = _sentenceTexts[index];
    final wordOffsets = [for (final m in RegExp(r'\S+').allMatches(sentenceText)) m.start];
    _localTts.setWordBoundaryHandler((charStart) {
      if (myToken != _synthesisToken) return; // phrase déjà changée
      final idx = wordOffsets.lastIndexWhere((offset) => offset <= charStart);
      if (idx != currentWordIndexNotifier.value) {
        currentWordIndexNotifier.value = idx;
      }
    });

    _isPlaying = true;
    _updateNotification(playing: true);

    try {
      await _localTts.speak(
        sentenceText,
        option: localVoice,
        speed: _speed,
      );
    } catch (_) {
      // Échec silencieux (ex: coupé par un stop() pendant la lecture)
    }

    _localTts.setWordBoundaryHandler(null);

    // Superseded entre-temps (pause, saut, changement de voix) → ne rien faire
    if (myToken != _synthesisToken) return;
    if (!shouldBePlayingNotifier.value) return;

    _onSentenceFinished();
  }

  /// Pré-charge N+1 dans le buffer player. Utilise le niveau 2 si disponible.
  Future<void> _prefetchNext(int afterIndex) async {
    final nextIndex = afterIndex + 1;
    if (nextIndex >= _sentenceTexts.length) return;

    _prefetchToken++;
    final myToken = _prefetchToken;
    _bufferLoadedIndex = null;

    try {
      String filePath;
      List<WordTiming> words;

      // Chemin rapide : N+1 déjà pré-synthétisé et en cache
      if (_prefetchCache.containsKey(nextIndex)) {
        filePath = _prefetchCache.remove(nextIndex)!;
        words = _prefetchWordCache.remove(nextIndex) ?? [];
      } else {
        final result = await _googleTts.synthesizeText(
          text: _sentenceTexts[nextIndex],
          voiceName: _voiceName,
          languageCode: _languageCode,
        );
        if (myToken != _prefetchToken) return;

        final audioBytes = base64Decode(result['audio_content'] as String);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/prefetch_$nextIndex.mp3');
        await tempFile.writeAsBytes(audioBytes);
        filePath = tempFile.path;
        words = parseWordTimings(result['word_timings']);
      }

      if (myToken != _prefetchToken) return;

      await _bufferPlayer.setAudioSource(AudioSource.uri(Uri.file(filePath)));
      if (myToken != _prefetchToken) return;

      _bufferLoadedIndex = nextIndex;
      _prefetchedPath = filePath;
      _prefetchedIndex = nextIndex;
      _prefetchedWords = words;
      debugPrint('[WORD-TRACK] préchargement phrase $nextIndex (buffer) : ${words.length} mots');
    } catch (e) {
      debugPrint('[WORD-TRACK] ⚠ échec préchargement phrase $nextIndex (buffer) : $e');
      // Échec silencieux — synthèse à la demande en fallback
    }
  }

  /// Lance le préchargement de N+1 (dans le buffer) ET de N+2 (en cache sur
  /// disque) EN PARALLÈLE plutôt qu'en chaîne — 2 phrases d'avance au lieu
  /// de 3, pour rester sous le quota TTS actuel (30 requêtes/min sur les
  /// voix Journey) tout en gardant des transitions rapides. Repasser à 3
  /// (ajouter `unawaited(_prefetchToFile(currentIndex + 3));`) une fois le
  /// quota augmenté, pour une marge encore plus confortable.
  void _prefetchAhead(int currentIndex) {
    // Les voix locales sont instantanées (moteur natif du téléphone) — pas
    // de latence réseau à masquer, donc rien à précharger. Sans cette
    // garde, ces appels partaient quand même vers le backend cloud avec un
    // nom de voix locale invalide pour Google (échec systématique).
    if (_isLocalVoice) return;
    unawaited(_prefetchNext(currentIndex));
    unawaited(_prefetchToFile(currentIndex + 2));
  }

  /// Pré-synthétise une phrase sur disque et la place dans le cache
  /// (sans la charger dans un player — ça, c'est le rôle de _prefetchNext).
  Future<void> _prefetchToFile(int index) async {
    if (index >= _sentenceTexts.length || index < 0) return;
    if (_prefetchCache.containsKey(index)) return; // déjà en cache

    final myGeneration = _voiceGeneration;

    try {
      final result = await _googleTts.synthesizeText(
        text: _sentenceTexts[index],
        voiceName: _voiceName,
        languageCode: _languageCode,
      );
      // La voix a changé pendant l'attente : ce fichier ne correspond plus
      if (myGeneration != _voiceGeneration) return;

      final audioBytes = base64Decode(result['audio_content'] as String);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/prefetch2_$index.mp3');
      await tempFile.writeAsBytes(audioBytes);

      if (myGeneration != _voiceGeneration) return;
      final words = parseWordTimings(result['word_timings']);
      _prefetchCache[index] = tempFile.path;
      _prefetchWordCache[index] = words;
      debugPrint('[WORD-TRACK] préchargement phrase $index (disque) : ${words.length} mots');
    } catch (e) {
      debugPrint('[WORD-TRACK] ⚠ échec préchargement phrase $index (disque) : $e');
    }
  }

  void _swapPlayers() {
    _currentIdx = 1 - _currentIdx;
    _bufferLoadedIndex = null;
  }

  // ── Suivi mot par mot (voix cloud) ─────────────────────────────────────────

  /// Repart de zéro pour une nouvelle phrase : coupe le suivi en cours et
  /// efface le mot actif, avant que la nouvelle phrase ne charge ses propres
  /// timings.
  void _resetWordTracking() {
    _wordTrackingTimer?.cancel();
    _wordTrackingTimer = null;
    _currentWordTimings = [];
    currentWordIndexNotifier.value = -1;
  }

  /// Suspend le suivi (pause) sans effacer le mot actif — la mise en
  /// surbrillance reste sur le dernier mot lu pendant la pause.
  void _pauseWordTracking() {
    _wordTrackingTimer?.cancel();
    _wordTrackingTimer = null;
  }

  /// Estime les timings mot par mot quand Google n'en renvoie aucun (voix
  /// Chirp3-HD, qui accepte le SSML `<mark>` sans erreur mais l'ignore
  /// silencieusement — voir `chirp3_personas.dart`) : répartit la durée
  /// réelle de l'audio entre les mots, au prorata de leur longueur en
  /// caractères. Approximatif — ne tient pas compte des pauses naturelles ni
  /// de l'emphase du modèle — mais nettement plus utile qu'un surlignage de
  /// phrase entière, seule alternative sans timings réels.
  List<WordTiming> _estimateWordTimings(String text, Duration? duration) {
    if (duration == null || duration <= Duration.zero) return const [];

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];

    // Longueur totale en caractères + un espace entre chaque mot, pour que
    // les mots longs reçoivent proportionnellement plus de temps que les
    // courts (approximation raisonnable du débit de parole réel).
    final totalChars =
        words.fold<int>(0, (sum, w) => sum + w.length) + (words.length - 1);
    if (totalChars <= 0) return const [];

    final totalSeconds = duration.inMilliseconds / 1000.0;
    final timings = <WordTiming>[];
    var charsBefore = 0;
    for (final word in words) {
      timings.add(WordTiming(word, totalSeconds * charsBefore / totalChars));
      charsBefore += word.length + 1;
    }
    return timings;
  }

  /// Démarre un minuteur qui interroge la position de lecture pour savoir
  /// quel mot est en train d'être prononcé (voix cloud uniquement — les
  /// voix locales utilisent le callback natif de progression à la place).
  /// Intervalle court (25ms) car une phrase courte (2-4 mots) peut ne durer
  /// qu'une fraction de seconde — un intervalle plus large ratait des
  /// transitions de mot entières sur ces phrases-là.
  void _startWordTracking() {
    _wordTrackingTimer?.cancel();

    // Voix sans timepoints Google (Chirp3-HD et semblables, voir
    // `Voice.hasWordTiming`) : on estime la position de chaque mot en
    // répartissant la durée réelle de l'audio au prorata de la longueur des
    // mots, plutôt que de se limiter à un surlignage de phrase entière.
    if (_currentWordTimings.isEmpty && _currentIndex < _sentenceTexts.length) {
      final estimated = _estimateWordTimings(
        _sentenceTexts[_currentIndex],
        _currentPlayer.duration,
      );
      if (estimated.isNotEmpty) {
        debugPrint('[WORD-TRACK] pas de timings Google — estimation pour '
            '${estimated.length} mots (durée=${_currentPlayer.duration})');
        _currentWordTimings = estimated;
      }
    }

    debugPrint('[WORD-TRACK] _startWordTracking() appelé avec ${_currentWordTimings.length} mots');
    if (_currentWordTimings.isEmpty) {
      debugPrint('[WORD-TRACK] ⚠ aucun timing — le minuteur ne démarre pas');
      return;
    }
    // Premier mot affiché immédiatement, sans attendre le premier tick du
    // minuteur — sur une phrase très courte, ce délai d'attente pouvait à
    // lui seul représenter une bonne partie de la durée totale de la phrase.
    currentWordIndexNotifier.value = 0;
    var tickCount = 0;
    _wordTrackingTimer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      final posSeconds = _currentPlayer.position.inMilliseconds / 1000.0;
      var idx = -1;
      for (var i = 0; i < _currentWordTimings.length; i++) {
        if (_currentWordTimings[i].time <= posSeconds) {
          idx = i;
        } else {
          break;
        }
      }
      tickCount++;
      if (tickCount <= 5) {
        debugPrint('[WORD-TRACK] tick $tickCount : position=${posSeconds}s -> mot $idx');
      }
      if (idx != currentWordIndexNotifier.value) {
        currentWordIndexNotifier.value = idx;
      }
    });
  }

  // ── Notification Android ───────────────────────────────────────────────────

  /// Met à jour la notification média Android avec position, vitesse et contrôles.
  /// [loading] = true pendant la synthèse TTS (montre un indicateur de chargement).
  void _updateNotification({required bool playing, bool loading = false}) {
    // Position : on utilise l'index de phrase comme proxy de progression
    // (1 phrase ≈ 1 seconde de façon arbitraire — donne une barre de progression)
    final position = Duration(seconds: _currentIndex);

    playbackState.add(playbackState.value.copyWith(
      playing: playing,
      processingState: loading
          ? AudioProcessingState.loading
          : AudioProcessingState.ready,
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      systemActions: const {
        MediaAction.skipToPrevious,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
      },
      updatePosition: position,
      speed: _speed,
    ));
  }

  /// Met à jour le MediaItem avec le titre du livre, la phrase courante et la durée totale.
  void _updateMediaItem() {
    final total = _sentenceTexts.length;
    mediaItem.add(MediaItem(
      id: 'talktome_current',
      title: _bookTitle,
      artist: 'Phrase ${_currentIndex + 1} / $total',
      // Durée totale = nombre de phrases (proxy arbitraire pour la barre de progression)
      duration: Duration(seconds: total),
    ));
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  /// Réinitialise complètement le handler quand on quitte le lecteur
  void reset() {
    _synthesisToken++;
    _prefetchToken++;
    _voiceGeneration++;
    _ttsService?.cancel();
    _googleTts.cancel();
    _isSessionActive = false;
    _isPlaying = false;
    _currentPlayer.stop();
    _bufferPlayer.stop();
    unawaited(_localTts.stop());
    _localTts.setWordBoundaryHandler(null);
    _resetWordTracking();
    _bufferLoadedIndex = null;
    _prefetchedPath = null;
    _prefetchedIndex = null;
    _prefetchedWords = null;
    _prefetchCache.clear();
    _prefetchWordCache.clear();
    isSynthesizingNotifier.value = false;
    playbackState.add(PlaybackState(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    mediaItem.add(null);
  }
}
