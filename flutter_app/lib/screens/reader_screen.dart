import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/ebook.dart';
import '../models/annotation.dart';
import '../services/tts_service.dart' show TtsService, Voice;
import '../services/local_tts_service.dart';
import '../main.dart' show themeModeNotifier, fontFamilyNotifier, fontSizeNotifier, audioHandler, ensureAudioHandler;
import '../services/stats_service.dart';
import '../data/voice_characters.dart';
import '../data/cloud_voices.dart';
import '../widgets/voice_avatar.dart';

// ─── Modèles internes ────────────────────────────────────────────────────────

abstract class _BookItem {
  const _BookItem();
}

class _ChapterHeader extends _BookItem {
  final String title;
  final int chapterIndex;
  const _ChapterHeader(this.title, this.chapterIndex);
}

class _SentenceItem extends _BookItem {
  final int globalIndex;
  final int chapterIndex;
  final String text;
  const _SentenceItem(this.globalIndex, this.chapterIndex, this.text);
}

/// Groupe de phrases appartenant au même paragraphe — affiché comme un RichText continu.
class _ParagraphItem extends _BookItem {
  final List<int> sentenceIndices;
  final int chapterIndex;
  /// Index du paragraphe au sein de son chapitre (0, 1, 2...) — identifiant
  /// stable pour une annotation, contrairement aux index de phrase globaux
  /// qui dépendent de l'ensemble du livre.
  final int paragraphIndexInChapter;
  const _ParagraphItem(
      this.sentenceIndices, this.chapterIndex, this.paragraphIndexInChapter);
}

/// Un paragraphe de texte avec un surlignage arrondi dessiné derrière —
/// contrairement à TextSpan.backgroundColor (rectangulaire, et qui fragmente
/// en plusieurs boîtes dès qu'on découpe le texte en plusieurs spans), ceci
/// mesure le texte une fois pour obtenir les rectangles exacts de chaque
/// ligne concernée (via TextPainter.getBoxesForSelection) et les dessine en
/// rectangles arrondis — un par ligne si la phrase surlignée s'étend sur
/// plusieurs lignes, ce qui reste visuellement continu.
class _HighlightedParagraph extends StatelessWidget {
  final TextSpan text;
  final TextRange? sentenceRange;
  final TextRange? wordRange;
  final Color sentenceColor;
  final Color wordColor;
  /// Nombre d'ancres WidgetSpan (une par phrase, voir _sentenceAnchorKeys)
  /// insérées dans [text] — un TextPainter autonome (contrairement à
  /// RichText, qui gère ça tout seul) a besoin qu'on lui indique leur
  /// taille avant layout(), sinon il plante.
  final int placeholderCount;

  /// Sélection tactile en cours (surlignage à sauvegarder) — distincte du
  /// surlignage de lecture.
  final TextRange? selectionRange;
  final Color selectionColor;

  /// Passages déjà sauvegardés dans ce paragraphe (persistants d'une
  /// ouverture à l'autre du livre).
  final List<TextRange> savedHighlights;
  final Color savedHighlightColor;

  /// Résout une position locale en un mot (via TextPainter.getWordBoundary)
  /// et le remonte à l'écran parent — null désactive le geste (paragraphes
  /// qui n'ont pas besoin d'être sélectionnables, aucun cas aujourd'hui mais
  /// garde la porte ouverte).
  final void Function(TextRange word)? onLongPressStart;
  final void Function(TextRange word)? onLongPressMoveUpdate;
  final VoidCallback? onLongPressEnd;

  const _HighlightedParagraph({
    required this.text,
    required this.sentenceRange,
    required this.wordRange,
    required this.sentenceColor,
    required this.wordColor,
    required this.placeholderCount,
    this.selectionRange,
    this.selectionColor = Colors.transparent,
    this.savedHighlights = const [],
    this.savedHighlightColor = Colors.transparent,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Filet de sécurité : un pépin de layout transitoire ici (ex:
          // pendant un changement de taille de police, où plusieurs
          // paragraphes se remesurent en même temps) ne doit jamais faire
          // planter tout l'écran de lecture avec le rectangle d'erreur
          // rouge de Flutter — au pire, le texte s'affiche sans surlignage.
          try {
            final painter = TextPainter(
              text: text,
              textAlign: TextAlign.justify,
              textDirection: Directionality.of(context),
            );
            if (placeholderCount > 0) {
              painter.setPlaceholderDimensions(List.generate(
                placeholderCount,
                (_) => const PlaceholderDimensions(
                  size: Size.zero,
                  alignment: PlaceholderAlignment.middle,
                ),
              ));
            }
            painter.layout(maxWidth: constraints.maxWidth);
            final paragraphSize = Size(constraints.maxWidth, painter.height);

            // Traduit une position locale en un mot, en la bornant d'abord
            // aux limites du paragraphe : un glissement qui sort visuellement
            // du paragraphe (au-dessus/en dessous) reste ainsi accroché à son
            // premier/dernier mot plutôt que de tenter de sélectionner un
            // autre paragraphe (portée v1 : sélection à un seul paragraphe).
            TextRange wordAt(Offset local) {
              final clamped = Offset(
                local.dx.clamp(0.0, paragraphSize.width),
                local.dy.clamp(0.0, paragraphSize.height),
              );
              final pos = painter.getPositionForOffset(clamped);
              return painter.getWordBoundary(pos);
            }

            Widget content = CustomPaint(
              size: paragraphSize,
              painter: (sentenceRange != null ||
                      wordRange != null ||
                      selectionRange != null ||
                      savedHighlights.isNotEmpty)
                  ? _HighlightPainter(
                      textPainter: painter,
                      sentenceRange: sentenceRange,
                      wordRange: wordRange,
                      sentenceColor: sentenceColor,
                      wordColor: wordColor,
                      selectionRange: selectionRange,
                      selectionColor: selectionColor,
                      savedHighlights: savedHighlights,
                      savedHighlightColor: savedHighlightColor,
                    )
                  : null,
              child: RichText(text: text, textAlign: TextAlign.justify),
            );

            if (onLongPressStart != null) {
              content = GestureDetector(
                onLongPressStart: (d) => onLongPressStart!(wordAt(d.localPosition)),
                onLongPressMoveUpdate: (d) =>
                    onLongPressMoveUpdate?.call(wordAt(d.localPosition)),
                onLongPressEnd: (_) => onLongPressEnd?.call(),
                child: content,
              );
            }

            return content;
          } catch (_) {
            return RichText(text: text, textAlign: TextAlign.justify);
          }
        },
      ),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  final TextPainter textPainter;
  final TextRange? sentenceRange;
  final TextRange? wordRange;
  final Color sentenceColor;
  final Color wordColor;
  final TextRange? selectionRange;
  final Color selectionColor;
  final List<TextRange> savedHighlights;
  final Color savedHighlightColor;

  _HighlightPainter({
    required this.textPainter,
    required this.sentenceRange,
    required this.wordRange,
    required this.sentenceColor,
    required this.wordColor,
    this.selectionRange,
    this.selectionColor = Colors.transparent,
    this.savedHighlights = const [],
    this.savedHighlightColor = Colors.transparent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Les surlignages sauvegardés se peignent en premier (dessous) : la
    // lecture en cours doit rester visible par-dessus si elle chevauche un
    // passage déjà surligné.
    for (final range in savedHighlights) {
      _paintRange(canvas, range, savedHighlightColor, 3);
    }
    if (sentenceRange != null) {
      _paintRange(canvas, sentenceRange!, sentenceColor, 3);
    }
    if (wordRange != null) {
      _paintRange(canvas, wordRange!, wordColor, 3);
    }
    if (selectionRange != null) {
      _paintRange(canvas, selectionRange!, selectionColor, 3);
    }
  }

  void _paintRange(Canvas canvas, TextRange range, Color color, double padH) {
    // Pendant un défilement rapide, le texte peut changer entre le moment où
    // sentenceRange/wordRange sont calculés et celui où ce painter dessine —
    // un TextSelection avec des offsets hors des bornes du texte actuel fait
    // planter getBoxesForSelection (et Flutter affiche alors un gros
    // rectangle d'erreur rouge à la place du paragraphe). On borne toujours
    // aux limites réelles du texte, peu importe la langue ou le contenu.
    final textLength = textPainter.plainText.length;
    final start = range.start.clamp(0, textLength);
    final end = range.end.clamp(0, textLength);
    if (start >= end) return;

    final boxes = textPainter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    final paint = Paint()..color = color;
    for (final box in boxes) {
      final rect = Rect.fromLTRB(box.left - padH, box.top, box.right + padH, box.bottom);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) {
    return oldDelegate.sentenceRange != sentenceRange ||
        oldDelegate.wordRange != wordRange ||
        oldDelegate.selectionRange != selectionRange ||
        !listEquals(oldDelegate.savedHighlights, savedHighlights) ||
        oldDelegate.textPainter.text != textPainter.text;
  }
}

// ─── Écran lecteur ───────────────────────────────────────────────────────────

class ReaderScreen extends StatefulWidget {
  final Ebook ebook;
  /// Si fourni, l'écran défile jusqu'à ce passage sauvegardé à l'ouverture
  /// (venant de l'onglet Annotations).
  final Annotation? jumpToAnnotation;
  const ReaderScreen({Key? key, required this.ebook, this.jumpToAnnotation})
      : super(key: key);

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late TtsService _ttsService;

  // Abonnement à l'état de lecture du handler (playbackState)
  StreamSubscription<dynamic>? _playerStateSub;

  late Box<Ebook> ebookBox;

  final List<_BookItem> _displayItems = [];
  final List<_SentenceItem> _sentences = [];
  final Map<int, int> _chapterDisplayIndex = {};

  // ── Sélection tactile (surlignage à sauvegarder) ─────────────────────────
  // Identité du _ParagraphItem en cours de sélection (v1 : un seul
  // paragraphe à la fois — voir _HighlightedParagraph.wordAt).
  _ParagraphItem? _selectingParagraph;
  TextRange? _selectionAnchorWord;
  // Photo du texte aplati du paragraphe au moment du début de la sélection —
  // sert à extraire l'extrait sélectionné sans reconstruire tout le span.
  String? _selectionParagraphPlainText;
  final ValueNotifier<TextRange?> _selectionRangeNotifier = ValueNotifier(null);
  late Box<Annotation> _annotationBox;
  // ebook.id -> chapterId -> paragraphIndexInChapter -> annotations, pour un
  // lookup bon marché depuis _buildParagraphWidget (appelé à chaque frame
  // pour le paragraphe en cours de lecture).
  Map<String, Map<int, List<Annotation>>> _savedHighlightsByChapter = {};

  // Une GlobalKey par phrase pour ensureVisible précis
  final Map<int, GlobalKey> _sentenceKeys = {};

  /// Une GlobalKey par phrase, ancrée à l'endroit EXACT où elle commence
  /// dans le texte (via un WidgetSpan invisible inséré juste avant, voir
  /// _buildParagraphWidget). _sentenceKeys pointe vers le paragraphe entier
  /// (partagé par toutes ses phrases) — insuffisant pour un défilement
  /// automatique qui doit réagir à chaque phrase : deux phrases voisines du
  /// même paragraphe ont sinon la même position, donc aucun mouvement n'est
  /// détecté avant de changer de paragraphe (où le saut devient trop grand).
  final Map<int, GlobalKey> _sentenceAnchorKeys = {};

  // Défilement précis vers un index arbitraire (voir pubspec) — remplace
  // notre ancienne estimation "à la main" (taille de ligne/police devinée),
  // jamais fiable sur de longues distances : ce package mesure réellement
  // les items au fur et à mesure plutôt que de deviner leur hauteur.
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  int _currentGlobalIndex = 0;


  /// Position verticale cible pour la phrase en cours de lecture, en
  /// fraction de la hauteur visible (0.0 = haut, 0.5 = centre). La phrase
  /// est ré-ancrée à cette position à chaque changement, façon téléprompteur,
  /// plutôt que de simplement "rester visible" où qu'elle atterrisse.
  static const double _scrollAnchorFraction = 1 / 3;
  bool _showReturnButton = false;
  bool _autoScrollEnabled = true;  // défilement automatique pendant la lecture
  bool _readerVisible = true;       // afficher/masquer le texte pendant la lecture

  List<Voice> availableVoices = [];
  String selectedVoice = "en-US-Neural2-C";
  String selectedLanguageCode = "en-US";

  bool _isSynthesizing = false;
  // Faux tant que la session audio n'a pas confirmé l'état réel (voir
  // _startHandlerSession) : rien ne joue encore au tout premier affichage,
  // le bouton doit donc montrer ▶, jamais ⏸.
  bool _wantsToPlay = false;

  // Chronomètre pour tracker le temps de lecture réel
  final Stopwatch _readingStopwatch = Stopwatch();

  double _playbackSpeed = 1.0;
  static const double _speedMin = 0.5;
  static const double _speedMax = 2.0;
  static const double _speedStep = 0.05;

  /// Valeur affichée pendant qu'on glisse la barre de navigation façon
  /// YouTube — null quand on ne glisse pas (on suit alors _currentGlobalIndex).
  double? _scrubberPreviewIndex;


  @override
  void initState() {
    super.initState();
    _ttsService = TtsService();
    _buildFlatList();
    _annotationBox = Hive.box<Annotation>('annotations');
    _loadSavedHighlights();
    // Restaurer la position de lecture sauvegardée
    final saved = widget.ebook.lastReadPosition;
    if (saved > 0 && saved < _sentences.length) {
      _currentGlobalIndex = saved;
    }
    // Un saut vers une annotation prime sur la position sauvegardée.
    final jump = widget.jumpToAnnotation;
    final jumpIndex = jump == null ? null : _findGlobalIndexForAnnotation(jump);
    if (jumpIndex != null) {
      _currentGlobalIndex = jumpIndex;
    }
    _configureAudioSession();
    _startHandlerSession(); // async, intentionnellement non-awaited
    _initializeScreen();
    fontSizeNotifier.addListener(_onFontChanged);
    fontFamilyNotifier.addListener(_onFontChanged);
    if (jumpIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToSentence(jumpIndex, animate: false);
      });
    }
  }

  /// Regroupe les annotations sauvegardées de ce livre par chapitre +
  /// paragraphe, pour un lookup bon marché dans _buildParagraphWidget.
  void _loadSavedHighlights() {
    final map = <String, Map<int, List<Annotation>>>{};
    for (final a in _annotationBox.values) {
      if (a.ebookId != widget.ebook.id) continue;
      map
          .putIfAbsent(a.chapterId, () => {})
          .putIfAbsent(a.paragraphIndexInChapter, () => [])
          .add(a);
    }
    _savedHighlightsByChapter = map;
  }

  /// Retrouve la première phrase du paragraphe visé par une annotation, pour
  /// pouvoir y défiler — null si le livre a changé de structure entre-temps
  /// (ré-import) et que le paragraphe n'existe plus tel quel.
  int? _findGlobalIndexForAnnotation(Annotation a) {
    for (final item in _displayItems) {
      if (item is _ParagraphItem &&
          item.chapterIndex < widget.ebook.chapters.length &&
          widget.ebook.chapters[item.chapterIndex].id == a.chapterId &&
          item.paragraphIndexInChapter == a.paragraphIndexInChapter &&
          item.sentenceIndices.isNotEmpty) {
        return item.sentenceIndices.first;
      }
    }
    return null;
  }

  // ── Sélection tactile (surlignage) ────────────────────────────────────────

  void _onSelectionStart(_ParagraphItem para, TextRange word, String plainText) {
    setState(() {
      _selectingParagraph = para;
      _selectionAnchorWord = word;
      _selectionParagraphPlainText = plainText;
    });
    _selectionRangeNotifier.value = word;
  }

  void _onSelectionUpdate(_ParagraphItem para, TextRange word) {
    if (!identical(_selectingParagraph, para)) return;
    final anchor = _selectionAnchorWord;
    if (anchor == null) return;
    final start = anchor.start < word.start ? anchor.start : word.start;
    final end = anchor.end > word.end ? anchor.end : word.end;
    _selectionRangeNotifier.value = TextRange(start: start, end: end);
  }

  void _onSelectionEnd(_ParagraphItem para) {
    // L'état (_selectingParagraph, _selectionRangeNotifier) est déjà à jour
    // à ce stade — la barre de confirmation les observe directement, rien à
    // faire de plus ici.
  }

  void _cancelSelection() {
    setState(() {
      _selectingParagraph = null;
      _selectionAnchorWord = null;
      _selectionParagraphPlainText = null;
    });
    _selectionRangeNotifier.value = null;
  }

  Future<void> _saveSelectionAsAnnotation() async {
    final para = _selectingParagraph;
    final range = _selectionRangeNotifier.value;
    final plainText = _selectionParagraphPlainText;
    if (para == null || range == null || plainText == null) {
      _cancelSelection();
      return;
    }

    final start = range.start.clamp(0, plainText.length);
    final end = range.end.clamp(0, plainText.length);
    if (start >= end) {
      _cancelSelection();
      return;
    }
    // Le caractère objet des ancres invisibles (voir _buildParagraphWidget)
    // peut se retrouver en bord de sélection — trim() l'élimine avec le
    // reste des espaces superflus.
    final selectedText = plainText.substring(start, end).trim();
    if (selectedText.isEmpty) {
      _cancelSelection();
      return;
    }

    final chapter = widget.ebook.chapters[para.chapterIndex];
    final annotation = Annotation(
      id: 'anno_${DateTime.now().microsecondsSinceEpoch}',
      ebookId: widget.ebook.id,
      chapterId: chapter.id,
      paragraphIndexInChapter: para.paragraphIndexInChapter,
      startOffset: start,
      endOffset: end,
      selectedText: selectedText,
      createdAt: DateTime.now(),
    );
    await _annotationBox.put(annotation.id, annotation);
    if (!mounted) return;

    setState(() {
      _savedHighlightsByChapter
          .putIfAbsent(chapter.id, () => {})
          .putIfAbsent(para.paragraphIndexInChapter, () => [])
          .add(annotation);
      _selectingParagraph = null;
      _selectionAnchorWord = null;
      _selectionParagraphPlainText = null;
    });
    _selectionRangeNotifier.value = null;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Passage surligné')),
    );
  }

  Widget _buildSelectionBar() {
    return ValueListenableBuilder<TextRange?>(
      valueListenable: _selectionRangeNotifier,
      builder: (context, range, _) {
        if (_selectingParagraph == null || range == null) {
          return const SizedBox.shrink();
        }
        final plainText = _selectionParagraphPlainText ?? '';
        final start = range.start.clamp(0, plainText.length);
        final end = range.end.clamp(0, plainText.length);
        final preview = start < end ? plainText.substring(start, end).trim() : '';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  preview.isEmpty ? '…' : '« $preview »',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: _cancelSelection,
                child: const Text('Annuler'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _saveSelectionAsAnnotation,
                icon: const Icon(Icons.border_color_rounded, size: 18),
                label: const Text('Surligner'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Un changement de taille/police reconstruit entièrement la liste (voir
  /// la clé sur ScrollablePositionedList) — elle se repositionne alors par
  /// défaut au HAUT du paragraphe courant plutôt qu'à l'ancrage habituel à
  /// 1/3. On refait donc le réglage fin juste après, une fois la nouvelle
  /// mise en page mesurée.
  void _onFontChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToSentence(_currentGlobalIndex, animate: false);
    });
  }

  // ─── Initialisation du handler audio ─────────────────────────────────────

  Future<void> _startHandlerSession() async {
    await ensureAudioHandler();
    if (!mounted) return;
    final h = audioHandler;
    if (h == null) return;

    // Démarrer la session dans le handler (foreground service)
    h.startSession(
      sentences: _sentences.map((s) => s.text).toList(),
      bookTitle: widget.ebook.title,
      ebookId: widget.ebook.id,
      ttsService: _ttsService,
      voiceName: selectedVoice,
      languageCode: selectedLanguageCode,
      speed: _playbackSpeed,
      startIndex: _currentGlobalIndex,
    );

    // Écouter l'index courant pour scroll automatique et surlignage
    h.currentIndexNotifier.addListener(_onHandlerIndexChanged);

    // Écouter l'état de synthèse pour le spinner du bouton play
    h.isSynthesizingNotifier.addListener(_onHandlerSynthesizingChanged);

    // Écouter l'intention play/pause — source de vérité pour le bouton,
    // fiable même pendant un chargement (contrairement à _isPlaying)
    h.shouldBePlayingNotifier.addListener(_onHandlerWantsToPlayChanged);
    // setState nécessaire : ce point est atteint après un `await`, donc le
    // premier build a déjà eu lieu avec la valeur par défaut du champ
    // (`true` → icône pause). Sans ça, le bouton affichait ⏸ à l'ouverture
    // même une fois la valeur corrigée, jusqu'à ce qu'une interaction
    // ultérieure force un rebuild.
    if (mounted) {
      setState(() => _wantsToPlay = h.shouldBePlayingNotifier.value);
    }

    // Écouter l'état lecture/pause pour le chronomètre de temps de lecture
    _playerStateSub = h.playbackState.listen((state) {
      if (!mounted) return;
      if (state.playing && !_readingStopwatch.isRunning) {
        _readingStopwatch.start();
      } else if (!state.playing && _readingStopwatch.isRunning) {
        _readingStopwatch.stop();
        _flushReadingTime();
      }
    });
  }

  void _onHandlerIndexChanged() {
    final idx = audioHandler?.currentIndexNotifier.value ?? 0;
    if (!mounted) return;
    setState(() => _currentGlobalIndex = idx);
    _saveProgress();
    if (_autoScrollEnabled && !_showReturnButton) {
      _autoScrollToCurrentSentence(idx);
    }
  }

  /// Défilement automatique pendant la lecture. Contrairement à
  /// _scrollToSentence (qui re-centre systématiquement la phrase à
  /// _scrollAnchorFraction — utile pour un saut volontaire précis), celui-ci
  /// ne bouge la page QUE si la phrase courante sort d'une zone confortable
  /// au milieu de l'écran, et l'anime plus lentement quand il le fait. Sans
  /// ça, chaque changement de phrase re-déclenchait un ajustement — souvent
  /// minime, mais parfois un grand saut brusque (paragraphe long, dialogue
  /// court...) — ce qui donnait un défilement saccadé et étourdissant.
  Future<void> _autoScrollToCurrentSentence(int globalIndex) async {
    try {
      // L'ancre précise de la phrase (voir _sentenceAnchorKeys) en priorité
      // — sans elle, deux phrases voisines du même paragraphe pointeraient
      // vers le même repère (celui du paragraphe entier) et aucun mouvement
      // ne serait jamais détecté avant de changer de paragraphe.
      final anchorContext = _sentenceAnchorKeys[globalIndex]?.currentContext ??
          _sentenceKeys[globalIndex]?.currentContext;
      final renderObject = anchorContext?.findRenderObject();
      if (anchorContext == null || renderObject == null) {
        // Pas encore construit (saut plus large que d'habitude, ex: après une
        // synthèse très rapide) — retombe sur le comportement habituel.
        await _scrollToSentence(globalIndex);
        return;
      }

      final scrollable = Scrollable.of(anchorContext);
      final viewportBox = RenderAbstractViewport.of(renderObject) as RenderBox;
      final currentY = _paintedY(renderObject, viewportBox);
      final viewportHeight = _viewportHeight(viewportBox);
      // Zone confortable très resserrée (30%-36%, autour de l'ancrage à
      // 1/3) : un petit ajustement se déclenche à presque chaque phrase au
      // lieu d'attendre plusieurs phrases — beaucoup de petits pas plutôt
      // que peu de grands, pour une impression de défilement continu.
      final lower = viewportHeight * 0.30;
      final upper = viewportHeight * 0.36;
      if (currentY >= lower && currentY <= upper) return;

      final desiredY = viewportHeight * _scrollAnchorFraction;
      final target = scrollable.position.pixels + (currentY - desiredY);
      // Voir le commentaire équivalent dans _animateToAnchor : offset 0 n'est
      // pas le haut du livre ici, donc le minimum valide est minScrollExtent
      // (souvent négatif), pas 0.0.
      await scrollable.position.animateTo(
        target.clamp(scrollable.position.minScrollExtent, scrollable.position.maxScrollExtent),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeInOut,
      );
    } catch (_) {
      // Purement un confort visuel — jamais laisser un pépin de layout
      // transitoire (ex: pendant un changement de taille de police) casser
      // le rendu de la page avec l'écran d'erreur rouge de Flutter.
    }
  }

  void _onHandlerSynthesizingChanged() {
    if (!mounted) return;
    setState(() => _isSynthesizing = audioHandler?.isSynthesizingNotifier.value ?? false);
  }

  void _onHandlerWantsToPlayChanged() {
    if (!mounted) return;
    setState(() => _wantsToPlay = audioHandler?.shouldBePlayingNotifier.value ?? false);
  }

  // ─── Session audio (lecture en arrière-plan) ──────────────────────────────

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
  }

  // ─── Rendu d'un paragraphe ────────────────────────────────────────────────

  Widget _buildParagraphWidget(
      _ParagraphItem para, GlobalKey? paraKey, BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final baseColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    final containsCurrent = para.sentenceIndices.contains(_currentGlobalIndex);
    final wordNotifier = audioHandler?.currentWordIndexNotifier;
    final chapterId = widget.ebook.chapters[para.chapterIndex].id;
    final savedRanges = (_savedHighlightsByChapter[chapterId]?[para.paragraphIndexInChapter] ?? const [])
        .map((a) => TextRange(start: a.startOffset, end: a.endOffset))
        .toList();
    final isSelectingThis = identical(_selectingParagraph, para);

    return KeyedSubtree(
      key: paraKey,
      child: ValueListenableBuilder<double>(
        valueListenable: fontSizeNotifier,
        builder: (context, fontSize, _) => ValueListenableBuilder<String?>(
          valueListenable: fontFamilyNotifier,
          builder: (context, fontFamily, _) {
            final baseStyle = TextStyle(
              fontFamily: fontFamily,
              fontSize: fontSize,
              height: 1.6,
              color: baseColor,
            );

            // Construit le texte du paragraphe une seule fois, en notant les
            // offsets de caractères de la phrase courante — nécessaires pour
            // mesurer ensuite où dessiner le surlignage.
            final spans = <InlineSpan>[];
            int cursor = 0;
            int? sentenceStart;
            int? sentenceEnd;
            String currentSentenceText = '';
            for (final idx in para.sentenceIndices) {
              final s = _sentences[idx];
              final isCurrent = idx == _currentGlobalIndex;
              final tap = TapGestureRecognizer()..onTap = () => audioHandler?.playSentenceAt(idx);

              // Ancre invisible (largeur nulle) juste avant la phrase — donne
              // au défilement automatique un point de repère précis pour
              // CHAQUE phrase, plutôt qu'un seul partagé par tout le
              // paragraphe (voir _sentenceAnchorKeys). Chaque WidgetSpan
              // occupe UNE position dans le texte "plat" utilisé pour les
              // offsets de sélection — il faut donc avancer cursor en
              // conséquence, sinon le surlignage se décale.
              final anchorKey = _sentenceAnchorKeys[idx];
              if (anchorKey != null) {
                spans.add(WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: KeyedSubtree(key: anchorKey, child: const SizedBox.shrink()),
                ));
                cursor += 1;
              }

              spans.add(TextSpan(
                text: s.text,
                recognizer: tap,
                style: isCurrent ? TextStyle(fontWeight: FontWeight.w600, color: baseColor) : null,
              ));
              if (isCurrent) {
                sentenceStart = cursor;
                sentenceEnd = cursor + s.text.length;
                currentSentenceText = s.text;
              }
              cursor += s.text.length;

              spans.add(TextSpan(text: ' ', recognizer: tap));
              cursor += 1;
            }

            final fullSpan = TextSpan(style: baseStyle, children: spans);

            Widget buildParagraph(int activeWordIndex, TextRange? selection) {
              TextRange? wordRange;
              final sStart = sentenceStart;
              if (sStart != null && activeWordIndex >= 0) {
                final words = currentSentenceText.split(' ');
                var offset = sStart;
                for (var i = 0; i < words.length && i <= activeWordIndex; i++) {
                  if (i == activeWordIndex) {
                    wordRange = TextRange(start: offset, end: offset + words[i].length);
                    break;
                  }
                  offset += words[i].length + 1;
                }
              }

              final sEnd = sentenceEnd;
              return _HighlightedParagraph(
                text: fullSpan,
                sentenceRange: (sStart != null && sEnd != null)
                    ? TextRange(start: sStart, end: sEnd)
                    : null,
                wordRange: wordRange,
                sentenceColor: primary.withOpacity(0.18),
                wordColor: primary.withOpacity(0.45),
                placeholderCount: para.sentenceIndices.length,
                selectionRange: selection,
                selectionColor: Colors.amber.withOpacity(0.45),
                savedHighlights: savedRanges,
                savedHighlightColor: Colors.amber.withOpacity(0.28),
                onLongPressStart: (word) =>
                    _onSelectionStart(para, word, fullSpan.toPlainText()),
                onLongPressMoveUpdate: (word) => _onSelectionUpdate(para, word),
                onLongPressEnd: () => _onSelectionEnd(para),
              );
            }

            Widget withWordTracking(TextRange? selection) {
              // Seul le paragraphe contenant la phrase en cours a besoin de se
              // reconstruire à chaque changement de mot (~25ms) — les autres
              // restent statiques, pour ne pas ralentir tout le reste de la page.
              if (!containsCurrent || wordNotifier == null) {
                return buildParagraph(-1, selection);
              }
              return ValueListenableBuilder<int>(
                valueListenable: wordNotifier,
                builder: (context, wordIdx, _) => buildParagraph(wordIdx, selection),
              );
            }

            // Seul le paragraphe en cours de sélection a besoin d'écouter le
            // notifier de sélection (partagé par tous les paragraphes) — les
            // autres passent directement `null`, sans s'abonner, pour ne pas
            // se reconstruire à chaque déplacement du doigt ailleurs.
            if (!isSelectingThis) return withWordTracking(null);
            return ValueListenableBuilder<TextRange?>(
              valueListenable: _selectionRangeNotifier,
              builder: (context, selection, _) => withWordTracking(selection),
            );
          },
        ),
      ),
    );
  }

  // ─── Construction de la liste ─────────────────────────────────────────────

  void _buildFlatList() {
    int globalIndex = 0;

    for (int ci = 0; ci < widget.ebook.chapters.length; ci++) {
      final chapter = widget.ebook.chapters[ci];
      _chapterDisplayIndex[ci] = _displayItems.length;
      _displayItems.add(_ChapterHeader(chapter.title, ci));
      var paraIndexInChapter = 0;

      // Séparer en paragraphes (double saut de ligne ou saut simple)
      final rawParagraphs = chapter.textContent
          .split(RegExp(r'\n\s*\n'))
          .map((p) => p.replaceAll('\n', ' ').trim())
          .where((p) => p.isNotEmpty)
          .toList();

      // Fallback : si pas de paragraphes détectés, traiter tout le texte comme un seul
      final paragraphTexts = rawParagraphs.isEmpty
          ? [chapter.textContent.replaceAll('\n', ' ').trim()]
          : rawParagraphs;

      for (final paraText in paragraphTexts) {
        final sentences = _splitIntoSentences(paraText);
        if (sentences.isEmpty) continue;

        final paraIndices = <int>[];
        final paraKey = GlobalKey();

        for (final text in sentences) {
          _sentences.add(_SentenceItem(globalIndex, ci, text));
          _sentenceKeys[globalIndex] = paraKey; // toutes les phrases du para partagent la même clé
          _sentenceAnchorKeys[globalIndex] = GlobalKey();
          paraIndices.add(globalIndex);
          globalIndex++;
        }

        _displayItems.add(_ParagraphItem(paraIndices, ci, paraIndexInChapter));
        paraIndexInChapter++;
      }
    }
  }

  int _findDisplayIndex(int globalIndex) {
    if (globalIndex < 0 || globalIndex >= _sentences.length) return -1;
    final ci = _sentences[globalIndex].chapterIndex;
    final start = _chapterDisplayIndex[ci] ?? 0;
    for (int di = start; di < _displayItems.length; di++) {
      final item = _displayItems[di];
      if (item is _ParagraphItem && item.sentenceIndices.contains(globalIndex)) return di;
      if (item is _ChapterHeader && item.chapterIndex > ci) break;
    }
    return -1;
  }

  // ─── Scroll ───────────────────────────────────────────────────────────────

  /// N'affiche "Retour au texte en cours" que sur un vrai glissement tactile
  /// (dragDetails non nul) — jamais sur un mouvement programmatique (nos
  /// propres jumpTo/animateTo, le placement initial de
  /// scrollable_positioned_list, ou même un simple changement d'état comme
  /// pause/lecture qui redéclenche parfois un evenement de position sans
  /// qu'aucun doigt ne touche l'écran). Contrairement à écouter
  /// itemPositions (qui réagit à N'IMPORTE QUEL changement de position, peu
  /// importe sa cause), dragDetails distingue fiablement un geste utilisateur
  /// de tout le reste, sans avoir besoin de délais de grâce fragiles.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
      if (!_showReturnButton) {
        setState(() => _showReturnButton = true);
      }
    }
    return false;
  }

  /// Position Y actuelle de [renderObject] dans le viewport (0 = haut du
  /// viewport, [_viewportHeight] = bas), mesurée directement sur l'arbre de
  /// rendu déjà peint plutôt que via getOffsetToReveal — dont le calcul de
  /// fraction ne correspond PAS au viewport visuel réel avec ce package
  /// (UnboundedRenderViewport, utilisé pour permettre un scroll bidirectionnel
  /// à partir d'un index arbitraire, rapporte une géométrie différente d'un
  /// Viewport classique). Mesurer la position peinte réelle est fiable quel
  /// que soit ce détail interne.
  double _paintedY(RenderObject renderObject, RenderBox viewportBox) {
    return (renderObject as RenderBox).localToGlobal(Offset.zero, ancestor: viewportBox).dy;
  }

  double _viewportHeight(RenderBox viewportBox) => viewportBox.size.height;

  /// Anime le scroll pour amener [renderObject] (via son [anchorContext],
  /// nécessaire pour retrouver le Scrollable qui le contient) exactement à
  /// [_scrollAnchorFraction] de la hauteur du viewport, qu'il soit déjà
  /// visible ou non — contrairement à ensureVisible, qui ne bouge que si
  /// l'item est hors champ et ne garantit aucune position précise. Réservé
  /// à l'ajustement FIN une fois le bon paragraphe déjà à l'écran — le gros
  /// du trajet (potentiellement très loin) est fait par
  /// _itemScrollController.scrollTo, voir _scrollToSentence.
  Future<void> _animateToAnchor(
    BuildContext anchorContext,
    RenderObject renderObject,
    Duration duration,
    Curve curve, {
    bool animate = true,
  }) async {
    final scrollable = Scrollable.of(anchorContext);
    final viewportBox = RenderAbstractViewport.of(renderObject) as RenderBox;
    final currentY = _paintedY(renderObject, viewportBox);
    final desiredY = _viewportHeight(viewportBox) * _scrollAnchorFraction;
    final target = scrollable.position.pixels + (currentY - desiredY);
    // scrollable_positioned_list ancre son offset 0 sur le paragraphe visé par
    // le saut grossier (étape 1), pas sur le haut du livre : les phrases qui
    // précèdent cette ancre dans le viewport ont un offset NÉGATIF. Borner à
    // 0.0 comme minimum (au lieu de minScrollExtent, qui peut être très
    // négatif ici) écrasait systématiquement ces corrections vers le bas —
    // exactement le bug "ça ramène vers le bas" signalé par l'utilisateur.
    final clamped = target.clamp(
      scrollable.position.minScrollExtent,
      scrollable.position.maxScrollExtent,
    );
    if (!animate) {
      scrollable.position.jumpTo(clamped);
      return;
    }
    await scrollable.position.animateTo(
      clamped,
      duration: duration,
      curve: curve,
    );
  }

  /// Retourne true si la phrase [globalIndex] a bien été atteinte.
  /// [animate] à false pour un saut instantané, sans les allers-retours
  /// visibles habituels — utilisé pour restaurer la position à l'ouverture
  /// d'un livre, où une longue animation étape par étape est juste
  /// étourdissante plutôt qu'utile (contrairement à la navigation en cours
  /// de lecture, où voir le défilement aide à se repérer).
  Future<bool> _scrollToSentence(int globalIndex, {bool animate = true}) async {
    if (globalIndex < 0 || globalIndex >= _sentences.length) return false;
    if (!_itemScrollController.isAttached) return false;
    bool success = false;

    try {
      final di = _findDisplayIndex(globalIndex);
      if (di < 0) return false;

      // Étape 1 : saut vers le bon PARAGRAPHE, fiable même à grande
      // distance — scrollable_positioned_list mesure réellement les items
      // déjà construits et affine son estimation au fur et à mesure, au
      // lieu de deviner leur hauteur comme le faisait notre ancien code
      // (jamais fiable sur un livre long : l'erreur s'accumulait à chaque
      // paragraphe et empirait avec une taille de police différente de 16).
      if (animate) {
        await _itemScrollController.scrollTo(
          index: di,
          alignment: _scrollAnchorFraction,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      } else {
        _itemScrollController.jumpTo(index: di, alignment: _scrollAnchorFraction);
      }
      if (!mounted) return false;

      // Étape 2 : ajustement fin vers la PHRASE exacte dans ce paragraphe —
      // un paragraphe peut contenir plusieurs phrases sur plusieurs lignes,
      // et l'alignement ci-dessus ne cible que le paragraphe dans son
      // ensemble. Deux passes : scrollable_positioned_list continue de
      // s'auto-corriger sur plusieurs frames après un jumpTo/scrollTo —
      // mesurer et corriger une seule fois immédiatement après l'étape 1 lit
      // une géométrie pas encore à jour et vise donc une cible fausse. La
      // deuxième passe rattrape ce décalage une fois la mise en page
      // stabilisée.
      for (var pass = 0; pass < 2; pass++) {
        await Future.delayed(const Duration(milliseconds: 80));
        if (!mounted) break;
        final anchorContext = _sentenceAnchorKeys[globalIndex]?.currentContext ??
            _sentenceKeys[globalIndex]?.currentContext;
        final renderObject = anchorContext?.findRenderObject();
        if (anchorContext != null && renderObject != null) {
          await _animateToAnchor(
            anchorContext,
            renderObject,
            const Duration(milliseconds: 200),
            Curves.easeOut,
            animate: animate,
          );
          success = true;
        }
      }
    } catch (_) {
      // Confort visuel seulement — jamais casser l'écran de lecture.
    }
    return success;
  }

  Future<void> _returnToCurrent() async {
    final found = await _scrollToSentence(_currentGlobalIndex);
    // Le bouton ne se cache que si on a vraiment atteint la phrase — sinon
    // il reste affiché pour permettre de réessayer, au lieu de disparaître
    // silencieusement en laissant l'utilisateur sans repère.
    if (mounted) setState(() => _showReturnButton = !found);
  }

  // Direction du bouton de retour : ↑ si la phrase est plus haut (on a
  // scrollé vers le bas, au-delà de la position de lecture), ↓ sinon (on a
  // scrollé vers le haut, avant la position de lecture). S'appuie sur les
  // items RÉELLEMENT visibles (fournis par le package) plutôt que sur une
  // estimation de position — fiable même très loin dans un livre long.
  bool get _isCurrentAbove {
    final di = _findDisplayIndex(_currentGlobalIndex);
    if (di < 0) return false;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return false;

    var minVisible = positions.first.index;
    var maxVisible = positions.first.index;
    for (final p in positions) {
      if (p.index < minVisible) minVisible = p.index;
      if (p.index > maxVisible) maxVisible = p.index;
    }
    if (di < minVisible) return true; // la lecture est plus haut que ce qui est visible
    if (di > maxVisible) return false; // plus bas

    for (final p in positions) {
      if (p.index == di) return p.itemLeadingEdge < 0;
    }
    return false;
  }

  // ─── Utilitaires ─────────────────────────────────────────────────────────

  /// Rythme de lecture moyen à voix haute, à vitesse 1x (mots/minute) —
  /// utilisé pour estimer le temps déjà écouté et le temps total du livre.
  static const double _baseWordsPerMinute = 150.0;

  int? _totalWordCountCache;

  int get _totalWordCount {
    final cached = _totalWordCountCache;
    if (cached != null) return cached;
    final total = _sentences.fold<int>(0, (sum, s) => sum + s.text.split(' ').length);
    _totalWordCountCache = total;
    return total;
  }

  int get _wordsReadSoFar {
    final upTo = (_scrubberPreviewIndex?.round() ?? _currentGlobalIndex);
    var count = 0;
    for (var i = 0; i <= upTo && i < _sentences.length; i++) {
      count += _sentences[i].text.split(' ').length;
    }
    return count;
  }

  Duration get _elapsedReadingEstimate {
    final wpm = _baseWordsPerMinute * _playbackSpeed;
    return Duration(seconds: (_wordsReadSoFar / wpm * 60).round());
  }

  Duration get _totalReadingEstimate {
    final wpm = _baseWordsPerMinute * _playbackSpeed;
    return Duration(seconds: (_totalWordCount / wpm * 60).round());
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Sauvegarde le temps de lecture accumulé dans les stats Hive
  void _flushReadingTime() {
    final seconds = _readingStopwatch.elapsed.inSeconds;
    if (seconds < 2) return;
    StatsService.instance.addSeconds(seconds);
    _readingStopwatch.reset();
  }

  Future<void> _togglePlayPause() async {
    if (_wantsToPlay) {
      await audioHandler?.pause();
    } else {
      await audioHandler?.play();
    }
  }

  // ─── Voix ─────────────────────────────────────────────────────────────────

  Future<void> _initializeScreen() async {
    ebookBox = Hive.box<Ebook>('ebooks');
    if (widget.ebook.selectedVoiceName.isNotEmpty) {
      setState(() => selectedVoice = widget.ebook.selectedVoiceName);
    }

    // Mettre à jour totalSentences si pas encore calculé (livres existants)
    if (widget.ebook.totalSentences == 0 && _sentences.isNotEmpty) {
      widget.ebook.totalSentences = _sentences.length;
      await ebookBox.put(widget.ebook.id, widget.ebook);
    }

    // Scroller jusqu'à la position restaurée après le premier frame
    if (_currentGlobalIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSentence(_currentGlobalIndex, animate: false);
      });
    }

    // Les voix cloud sont synthétisées en appel direct à l'API Google (clé
    // API), donc plus besoin du backend ni du Wi-Fi maison — la liste est
    // simplement hardcodée (vérifiée une à une contre le vrai catalogue
    // Google). Les voix locales restent disponibles hors ligne comme avant.
    final voices = <Voice>[
      ...allCloudVoices,
      ...LocalTtsService.availableVoices.map((v) => Voice(
            name: v.name,
            displayName: v.language,
            languageCode: v.languageCode,
            isLocal: true,
          )),
    ];

    if (!mounted) return;
    setState(() => availableVoices = voices);
    final savedVoice = voices.where((v) => v.name == selectedVoice).firstOrNull;
    if (savedVoice != null) {
      setState(() => selectedLanguageCode = savedVoice.languageCode);
      // Mettre à jour la voix dans le handler maintenant qu'on a le bon languageCode
      audioHandler?.updateVoice(savedVoice.name, savedVoice.languageCode);
    } else if (voices.isNotEmpty) {
      // La voix sauvegardée pour ce livre n'existe plus (catalogue Google
      // modifié depuis) — on bascule sur une voix valide, si possible dans
      // la même langue, plutôt que de rester bloqué sur un nom de voix qui
      // échouera à chaque tentative de synthèse.
      final fallback = voices.where((v) => v.languageCode == selectedLanguageCode).firstOrNull ??
          voices.first;
      setState(() {
        selectedVoice = fallback.name;
        selectedLanguageCode = fallback.languageCode;
      });
      audioHandler?.updateVoice(fallback.name, fallback.languageCode);
      widget.ebook.selectedVoiceName = fallback.name;
      await ebookBox.put(widget.ebook.id, widget.ebook);
    }

    // Demander les permissions requises pour la lecture en arrière-plan
    await _requestBackgroundPermissions();
  }

  /// Demande la permission notification (Android 13+) et l'exemption batterie (Samsung One UI)
  Future<void> _requestBackgroundPermissions() async {
    // Permission notification — obligatoire sur Android 13+ pour afficher la notification
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    // Exemption batterie — Samsung One UI tue les services en arrière-plan sans ça
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  void _saveProgress() {
    widget.ebook.lastReadPosition = _currentGlobalIndex;
    ebookBox.put(widget.ebook.id, widget.ebook);
  }

  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Vitesse de lecture'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_playbackSpeed % 1 == 0 ? _playbackSpeed.toInt() : _playbackSpeed}x',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                Slider(
                  value: _playbackSpeed,
                  min: _speedMin,
                  max: _speedMax,
                  divisions: ((_speedMax - _speedMin) / _speedStep).round(),
                  label: '${_playbackSpeed % 1 == 0 ? _playbackSpeed.toInt() : _playbackSpeed}x',
                  onChanged: (value) {
                    final newSpeed = double.parse(value.toStringAsFixed(2));
                    setDialogState(() => _playbackSpeed = newSpeed);
                    setState(() {});
                    audioHandler?.updateSpeed(newSpeed);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('0.5x', style: TextStyle(color: Colors.grey)),
                      Text('2x', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _changeVoice(String? newVoiceName) {
    if (newVoiceName == null) return;
    final voice = availableVoices.firstWhere((v) => v.name == newVoiceName);
    setState(() {
      selectedVoice = voice.name;
      selectedLanguageCode = voice.languageCode;
    });
    audioHandler?.updateVoice(voice.name, voice.languageCode);
    widget.ebook.selectedVoiceName = voice.name;
    ebookBox.put(widget.ebook.id, widget.ebook);
  }

  /// Extrait la "famille" de langue d'un libellé précis (ex: "Anglais (US)"
  /// -> "Anglais", "Français (Canada) · hors ligne" -> "Français") — sert
  /// aux boutons de raccourci en haut du panneau de voix.
  String _languageFamily(String language) {
    final idx = language.indexOf('(');
    final base = idx > 0 ? language.substring(0, idx).trim() : language.trim();
    return base.replaceAll('· hors ligne', '').trim();
  }

  /// Grille de voix pour une langue — la taille des pastilles s'adapte à la
  /// largeur réellement disponible (via LayoutBuilder) pour bien remplir
  /// chaque cellule, au lieu d'une taille fixe qui laissait de l'espace
  /// mort tout autour sur les écrans larges (ce qui donnait l'impression
  /// de gros espaces entre les images).
  Widget _buildVoiceGrid(List<Voice> voices, {VoidCallback? onSelected}) {
    const crossAxisCount = 3;
    const spacing = 4.0;
    const nameLineHeight = 16.0; // hauteur de ligne fixe et déterministe du nom (voir style ci-dessous)
    // La bordure de sélection (largeur 3) s'ajoute à la taille du cercle
    // plutôt que d'être peinte à l'intérieur — donc réservée en permanence
    // (transparente si non sélectionné) pour que la hauteur de cellule ne
    // change jamais selon la sélection, sinon la pastille sélectionnée
    // débordait de la grille.
    const circleExtra = 2 * (2.0 + 3.0); // padding (2) + bordure (3), des deux côtés
    const textAndPaddingHeight = circleExtra + 3.0 + nameLineHeight; // cercle + espacement + nom

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final avatarSize = cellWidth * 0.76;
        final cellHeight = avatarSize + textAndPaddingHeight;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: cellWidth / cellHeight,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: voices.map((v) {
            final character = characterForVoice(v.name);
            final isSelected = v.name == selectedVoice;
            return GestureDetector(
              onTap: () {
                _changeVoice(v.name);
                // Le panneau reste ouvert (pas de Navigator.pop) pour
                // pouvoir essayer plusieurs voix d'affilée rapidement.
                onSelected?.call();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Toujours une bordure de largeur 3 (transparente si
                      // non sélectionné) — la taille du cercle ne change
                      // jamais selon l'état, seule la couleur change.
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: ClipOval(
                      child: VoiceAvatar(character: character, size: avatarSize),
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: nameLineHeight,
                    child: Text(
                      character.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3, // hauteur de ligne fixe : ni le gras ni la police ne peuvent la faire déborder
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Panneau de choix de voix — 3/4 de l'écran, voix groupées par langue
  /// précise (avec région : US, UK, Canada...) sous un titre, avec des
  /// boutons de raccourci par famille de langue en haut. N'interrompt pas
  /// la lecture (showModalBottomSheet ne touche pas à audioHandler).
  void _showVoicePicker() {
    // Groupe les voix par langue précise, en conservant l'ordre d'origine.
    final groups = <String, List<Voice>>{};
    for (final v in availableVoices) {
      final lang = characterForVoice(v.name).language;
      groups.putIfAbsent(lang, () => []).add(v);
    }

    // Familles de langue pour les raccourcis (dédupliquées, ordre de
    // première apparition), + un raccourci "Hors ligne" séparé si des voix
    // locales existent — utile pour aller directement aux voix gratuites
    // sans passer par les voix cloud premium.
    final families = <String>[];
    for (final lang in groups.keys) {
      final f = _languageFamily(lang);
      if (!families.contains(f)) families.add(f);
    }
    final hasLocalVoices = groups.keys.any((lang) => lang.contains('hors ligne'));
    final chips = [...families, if (hasLocalVoices) 'Hors ligne'];

    final sectionKeys = {for (final lang in groups.keys) lang: GlobalKey()};
    final panelScrollController = ScrollController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        // StatefulBuilder pour rafraîchir localement la pastille
        // sélectionnée (bordure + gras) à chaque tap, sans fermer le
        // panneau — permet d'essayer plusieurs voix d'affilée rapidement.
        return StatefulBuilder(builder: (context, setModalState) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Choisir une voix',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                // Raccourcis par famille de langue (+ "Hors ligne")
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: chips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final f = chips[i];
                      return ActionChip(
                        label: Text(f),
                        onPressed: () {
                          final targetLang = f == 'Hors ligne'
                              ? groups.keys.firstWhere((lang) => lang.contains('hors ligne'))
                              : groups.keys.firstWhere((lang) => _languageFamily(lang) == f);
                          final renderObject =
                              sectionKeys[targetLang]?.currentContext?.findRenderObject();
                          // Calcul direct de l'offset cible (au lieu de
                          // Scrollable.ensureVisible) : marche de façon fiable
                          // dans les deux sens, vers le haut comme vers le bas.
                          if (renderObject != null) {
                            final viewport = RenderAbstractViewport.of(renderObject);
                            final target = viewport.getOffsetToReveal(renderObject, 0.0).offset;
                            panelScrollController.animateTo(
                              target.clamp(
                                0.0, panelScrollController.position.maxScrollExtent),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  // SingleChildScrollView + Column plutôt que ListView : la
                  // liste virtualisée démontait les sections déjà visitées
                  // dès qu'elles sortaient de l'écran, donc les raccourcis
                  // ne les retrouvaient plus pour y remonter. Le contenu ici
                  // reste modeste (quelques dizaines de pastilles au total),
                  // donc tout garder construit n'a aucun coût perceptible.
                  child: SingleChildScrollView(
                    controller: panelScrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in groups.entries) ...[
                          Padding(
                            key: sectionKeys[entry.key],
                            padding: const EdgeInsets.only(top: 2, bottom: 8),
                            child: Text(
                              entry.key,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          // Les voix Chirp3-HD n'offrent pas le surlignage mot
                          // par mot (Google ne renvoie pas les timepoints des
                          // marqueurs SSML pour ce tier) — séparées des voix
                          // Neural2 avec un sous-titre pour ne pas les mélanger.
                          _buildVoiceGrid(
                            entry.value.where((v) => v.hasWordTiming).toList(),
                            onSelected: () => setModalState(() {}),
                          ),
                          if (entry.value.any((v) => !v.hasWordTiming)) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 6),
                              child: Row(
                                children: [
                                  Icon(Icons.hd_rounded, size: 15, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Haute qualité — sans surlignage mot par mot',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: Colors.grey.shade600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            _buildVoiceGrid(
                              entry.value.where((v) => !v.hasWordTiming).toList(),
                              onSelected: () => setModalState(() {}),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        });
      },
    );
  }

  List<String> _splitIntoSentences(String text) {
    // Découpe après la ponctuation de fin de phrase, avec ou sans guillemet
    // fermant juste après (ex: Il dit : "Bonjour."  Puis il partit.) — sans
    // ça, tout ce qui suit un dialogue reste collé au paragraphe entier et
    // devient un seul énorme bloc envoyé à l'API TTS en un coup.
    final rawSentences = text
        .split(RegExp(
            r'(?<=[.!?…])\s+|(?<=[.!?…]["\x27’”»)\]])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Filet de sécurité : si un morceau reste quand même très long (texte
    // sans ponctuation de fin détectée), le redécouper pour éviter un appel
    // TTS unique portant sur un pavé de texte — source de longues pauses.
    const maxChunkLength = 220;
    final result = <String>[];
    for (final sentence in rawSentences) {
      result.addAll(_splitLongChunk(sentence, maxChunkLength));
    }
    return result;
  }

  /// Redécoupe un morceau de texte trop long sur une ponctuation "douce"
  /// (virgule, point-virgule, deux-points, tiret), ou à défaut sur un espace.
  List<String> _splitLongChunk(String text, int maxLength) {
    if (text.length <= maxLength) return [text];

    final chunks = <String>[];
    var remaining = text;
    while (remaining.length > maxLength) {
      final window = remaining.substring(0, maxLength);
      var cut = -1;
      for (final sep in [', ', '; ', ': ', ' — ', ' - ']) {
        final idx = window.lastIndexOf(sep);
        if (idx > cut) cut = idx + sep.length;
      }
      if (cut <= 0) {
        final spaceIdx = window.lastIndexOf(' ');
        cut = spaceIdx > 0 ? spaceIdx + 1 : maxLength;
      }
      chunks.add(remaining.substring(0, cut).trim());
      remaining = remaining.substring(cut).trim();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }

  // ─── Panneau d'apparence (police + thème) ─────────────────────────────────

  void _showAppearancePanel() {
    final settings = Hive.box('settings');

    // Polices système Android disponibles sans package externe
    const fonts = [
      (label: 'Roboto',      value: null,                  preview: 'Aa'),
      (label: 'Serif',       value: 'serif',               preview: 'Aa'),
      (label: 'Condensé',    value: 'sans-serif-condensed', preview: 'Aa'),
      (label: 'Light',       value: 'sans-serif-light',    preview: 'Aa'),
      (label: 'Medium',      value: 'sans-serif-medium',   preview: 'Aa'),
      (label: 'Mono',        value: 'monospace',           preview: 'Aa'),
      (label: 'Cursif',      value: 'cursive',             preview: 'Aa'),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Padding pour la barre Samsung
          final bottomPad = MediaQuery.of(context).padding.bottom + 24;
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poignée
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Text('Apparence',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),

                // ── Fond ──────────────────────────────────────────────────
                Text('FOND', style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeNotifier,
                  builder: (context, themeMode, _) => Row(
                    children: [
                      _themeChip(context: context, label: 'Clair',
                          icon: Icons.light_mode,
                          selected: themeMode == ThemeMode.light,
                          onTap: () {
                            themeModeNotifier.value = ThemeMode.light;
                            settings.put('themeMode', 'light');
                            setModalState(() {});
                          }),
                      const SizedBox(width: 10),
                      _themeChip(context: context, label: 'Sombre',
                          icon: Icons.dark_mode,
                          selected: themeMode == ThemeMode.dark,
                          onTap: () {
                            themeModeNotifier.value = ThemeMode.dark;
                            settings.put('themeMode', 'dark');
                            setModalState(() {});
                          }),
                      const SizedBox(width: 10),
                      _themeChip(context: context, label: 'Système',
                          icon: Icons.brightness_auto,
                          selected: themeMode == ThemeMode.system,
                          onTap: () {
                            themeModeNotifier.value = ThemeMode.system;
                            settings.put('themeMode', 'system');
                            setModalState(() {});
                          }),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Taille du texte ───────────────────────────────────────
                Text('TAILLE DU TEXTE', style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                ValueListenableBuilder<double>(
                  valueListenable: fontSizeNotifier,
                  builder: (context, fontSize, _) => Row(
                    children: [
                      // Bouton diminuer
                      IconButton.outlined(
                        icon: const Text('A', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        onPressed: fontSize > 10
                            ? () {
                                final newSize = fontSize - 1;
                                fontSizeNotifier.value = newSize;
                                settings.put('fontSize', newSize);
                                setModalState(() {});
                              }
                            : null,
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      // Aperçu de la taille
                      Expanded(
                        child: Center(
                          child: Text(
                            '${fontSize.toInt()} pt',
                            style: TextStyle(fontSize: fontSize.clamp(12, 22), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      // Bouton augmenter
                      IconButton.outlined(
                        icon: const Text('A', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                        onPressed: fontSize < 32
                            ? () {
                                final newSize = fontSize + 1;
                                fontSizeNotifier.value = newSize;
                                settings.put('fontSize', newSize);
                                setModalState(() {});
                              }
                            : null,
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Police ────────────────────────────────────────────────
                Text('POLICE', style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                ValueListenableBuilder<String?>(
                  valueListenable: fontFamilyNotifier,
                  builder: (context, currentFont, _) => Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: fonts.map((f) {
                      final selected = currentFont == f.value;
                      final color = Theme.of(context).colorScheme.primary;
                      return GestureDetector(
                        onTap: () {
                          fontFamilyNotifier.value = f.value;
                          settings.put('fontFamily', f.value);
                          setModalState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withOpacity(0.12)
                                : Colors.transparent,
                            border: Border.all(
                                color: selected
                                    ? color
                                    : Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(f.preview,
                                  style: TextStyle(
                                      fontFamily: f.value,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                      color: selected
                                          ? color
                                          : null)),
                              const SizedBox(height: 4),
                              Text(f.label,
                                  style: TextStyle(
                                      fontFamily: f.value,
                                      fontSize: 11,
                                      color: selected
                                          ? color
                                          : Colors.grey.shade600)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _themeChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          border: Border.all(color: selected ? color : Colors.grey.shade400),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
                color: selected ? color : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: selected ? color : Colors.grey.shade600,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  // ─── Table des matières ───────────────────────────────────────────────────

  Future<void> _renameFile() async {
    final controller = TextEditingController(text: widget.ebook.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le fichier'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nom du document'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != widget.ebook.title) {
      widget.ebook.title = result;
      await Hive.box<Ebook>('ebooks').put(widget.ebook.id, widget.ebook);
      if (mounted) setState(() {});
    }
  }

  void _showSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        String query = '';
        return StatefulBuilder(builder: (context, setModal) {
          final results = query.isEmpty
              ? <_SentenceItem>[]
              : _sentences
                  .where((s) =>
                      s.text.toLowerCase().contains(query.toLowerCase()))
                  .toList();
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Rechercher dans le document…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () => setModal(() => query = ''),
                            )
                          : null,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (v) => setModal(() => query = v),
                  ),
                ),
                if (query.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${results.length} résultat${results.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight:
                          MediaQuery.of(context).size.height * 0.45),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final s = results[i];
                      final lower = s.text.toLowerCase();
                      final qLower = query.toLowerCase();
                      final matchStart = lower.indexOf(qLower);

                      return ListTile(
                        dense: true,
                        title: matchStart < 0
                            ? Text(s.text, maxLines: 2, overflow: TextOverflow.ellipsis)
                            : RichText(
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    TextSpan(text: s.text.substring(0, matchStart)),
                                    TextSpan(
                                      text: s.text.substring(matchStart, matchStart + query.length),
                                      style: TextStyle(
                                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(text: s.text.substring(matchStart + query.length)),
                                  ],
                                ),
                              ),
                        subtitle: Text(
                          'Chapitre ${s.chapterIndex + 1} · Phrase ${s.globalIndex + 1}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _currentGlobalIndex = s.globalIndex);
                          _scrollToSentence(s.globalIndex);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        });
      },
    );
  }

  void _showChapterList() {
    final currentChapterIndex = _sentences.isNotEmpty
        ? _sentences[_currentGlobalIndex].chapterIndex
        : 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, sc) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Table des matières',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: widget.ebook.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = widget.ebook.chapters[index];
                  final isCurrent = index == currentChapterIndex;
                  return ListTile(
                    selected: isCurrent,
                    leading: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[500],
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    title: Text(chapter.title,
                        style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    subtitle: Text('${chapter.wordCount} mots'),
                    trailing: isCurrent
                        ? Icon(Icons.volume_up,
                            color: Theme.of(context).colorScheme.primary,
                            size: 18)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      final firstSentence = _sentences.firstWhere(
                        (s) => s.chapterIndex == index,
                        orElse: () => _sentences.first,
                      );
                      audioHandler?.stopAndSeekTo(firstSentence.globalIndex);
                      setState(() {
                        _currentGlobalIndex = firstSentence.globalIndex;
                        _isSynthesizing = false;
                        _showReturnButton = false;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToSentence(firstSentence.globalIndex);
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _readerVisible
          ? AppBar(
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.format_size_rounded),
            tooltip: 'Apparence',
            onPressed: _showAppearancePanel,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Options',
            onSelected: (value) {
              switch (value) {
                case 'toc':
                  _showChapterList();
                case 'rename':
                  _renameFile();
                case 'search':
                  _showSearch();
                case 'reader':
                  setState(() => _readerVisible = !_readerVisible);
                case 'autoscroll':
                  setState(() => _autoScrollEnabled = !_autoScrollEnabled);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'toc',
                child: ListTile(
                  leading: Icon(Icons.list_alt_rounded),
                  title: Text('Table des matières'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'search',
                child: ListTile(
                  leading: Icon(Icons.search_rounded),
                  title: Text('Rechercher'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.drive_file_rename_outline_rounded),
                  title: Text('Renommer le fichier'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'reader',
                child: ListTile(
                  leading: Icon(_readerVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded),
                  title: Text(
                      _readerVisible ? 'Masquer le lecteur' : 'Afficher le lecteur'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'autoscroll',
                child: ListTile(
                  leading: Icon(_autoScrollEnabled
                      ? Icons.sync_disabled_rounded
                      : Icons.sync_rounded),
                  title: Text(_autoScrollEnabled
                      ? 'Désactiver défilement auto'
                      : 'Activer défilement auto'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
          )
          : null,
      floatingActionButton: _readerVisible
          ? null
          : FloatingActionButton.small(
              onPressed: () => setState(() => _readerVisible = true),
              tooltip: 'Afficher les contrôles',
              backgroundColor: Colors.black45,
              child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.miniEndTop,
      body: Column(
        children: [
          // ── Texte + bouton de retour ─────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: fontSizeNotifier,
                  builder: (context, fontSize, _) => ValueListenableBuilder<String?>(
                    valueListenable: fontFamilyNotifier,
                    builder: (context, fontFamily, _) => NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: ScrollablePositionedList.builder(
                  // scrollable_positioned_list mesure et met en cache la
                  // hauteur de chaque item au fur et à mesure qu'il est
                  // construit. Un changement de taille/police de texte
                  // modifie la hauteur de TOUS les paragraphes d'un coup,
                  // mais les items déjà mis en cache (visibles ou non)
                  // gardent leur ancienne hauteur tant qu'ils ne sont pas
                  // reconstruits — le calcul de position du package devient
                  // incohérent entre items "neuve taille" et "vieille
                  // taille", ce qui faisait se chevaucher des paragraphes
                  // voisins à l'écran (les fameuses lignes qui traversaient
                  // les phrases). Une clé qui change avec la taille/police
                  // force Flutter à détruire et reconstruire tout le widget
                  // — donc tout le cache d'extents — plutôt que d'essayer de
                  // réconcilier un mélange d'anciennes et de nouvelles
                  // mesures.
                  key: ValueKey('list_${fontSize}_$fontFamily'),
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  initialScrollIndex: _findDisplayIndex(_currentGlobalIndex).clamp(0, _displayItems.length - 1),
                  itemCount: _displayItems.length,
                  itemBuilder: (context, index) {
                    final item = _displayItems[index];

                    if (item is _ChapterHeader) {
                      return Padding(
                        key: ValueKey('h_${item.chapterIndex}'),
                        padding: EdgeInsets.only(
                          top: item.chapterIndex == 0 ? 0 : 32,
                          bottom: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.chapterIndex > 0)
                              Divider(color: Colors.grey[300], height: 1),
                            const SizedBox(height: 12),
                            Text(
                              item.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }

                    final para = item as _ParagraphItem;
                    final paraKey = _sentenceKeys[para.sentenceIndices.first];
                    return _buildParagraphWidget(para, paraKey, context);
                  },
                  ),
                    ),
                  ),
                ),

                // ── Bouton "Retour au texte en cours" ─────────────────────
                if (_showReturnButton)
                  Positioned(
                    bottom: 12 + (_readerVisible ? 0 : MediaQuery.of(context).padding.bottom),
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _returnToCurrent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ValueListenableBuilder(
                                valueListenable: _itemPositionsListener.itemPositions,
                                builder: (context, _, __) => Icon(
                                  _isCurrentAbove
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Retour au texte en cours',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Barre de confirmation de sélection ───────────────────────────
          _buildSelectionBar(),

          // ── Contrôles fixes en bas ───────────────────────────────────────
          if (_readerVisible) Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Barre de navigation façon YouTube : glisser pour parcourir
                // rapidement tout le livre. onChanged met juste à jour
                // l'affichage (curseur + chrono) ; le vrai saut de lecture
                // n'a lieu qu'au relâchement (onChangeEnd), pour ne pas
                // spammer playSentenceAt pendant le glissement.
                if (_sentences.length > 1)
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    ),
                    child: Slider(
                      value: (_scrubberPreviewIndex ?? _currentGlobalIndex.toDouble())
                          .clamp(0.0, (_sentences.length - 1).toDouble()),
                      min: 0,
                      max: (_sentences.length - 1).toDouble(),
                      onChanged: (v) => setState(() => _scrubberPreviewIndex = v),
                      onChangeEnd: (v) {
                        final idx = v.round();
                        setState(() => _scrubberPreviewIndex = null);
                        // Navigue seulement jusqu'au texte visé, sans lancer
                        // la lecture — pour parcourir le livre sans
                        // interrompre ce qui est en train d'être lu. La
                        // lecture démarre en tapant directement une phrase
                        // dans le texte (déjà possible).
                        final wasElsewhere = idx != _currentGlobalIndex;
                        _scrollToSentence(idx).then((_) {
                          if (mounted && wasElsewhere) {
                            setState(() => _showReturnButton = true);
                          }
                        });
                      },
                    ),
                  ),
                // Chronomètre : temps déjà écouté / temps total estimé du
                // livre (estimation basée sur un rythme de lecture moyen,
                // ajusté à la vitesse de lecture choisie). Suit le curseur
                // de navigation pendant qu'on glisse.
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_formatDuration(_elapsedReadingEstimate)} / ${_formatDuration(_totalReadingEstimate)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ),
                Row(
                  children: [
                    // Sélecteur de voix : pastille circulaire, en bas à
                    // gauche, qui ouvre un panneau complet (la lecture
                    // continue pendant qu'on choisit). Légèrement décalée
                    // vers la droite et le haut.
                    Transform.translate(
                      offset: const Offset(10, -8),
                      child: GestureDetector(
                      onTap: availableVoices.isEmpty ? null : _showVoicePicker,
                      child: ClipOval(
                        child: availableVoices.any((v) => v.name == selectedVoice)
                            ? VoiceAvatar(
                                character: characterForVoice(selectedVoice),
                                size: 56,
                              )
                            : Container(
                                width: 56,
                                height: 56,
                                color: Colors.grey[300],
                                child: const Icon(Icons.record_voice_over_rounded),
                              ),
                      ),
                      ),
                    ),
                    // Contrôles centrés
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: _currentGlobalIndex > 0 && !_isSynthesizing
                                ? () => audioHandler?.playSentenceAt(_currentGlobalIndex - 1)
                                : null,
                            icon: const Icon(Icons.skip_previous_rounded),
                            iconSize: 36,
                            tooltip: 'Phrase précédente',
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                                    onPressed: _togglePlayPause,
                                    icon: _isSynthesizing && _wantsToPlay
                                        // Chargement en cours (et on veut jouer) : spinner
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                            ),
                                          )
                                        : Icon(
                                            _wantsToPlay
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            color: Colors.white,
                                          ),
                                    iconSize: 36,
                                    tooltip: _wantsToPlay ? 'Pause' : 'Lecture',
                                  ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _currentGlobalIndex < _sentences.length - 1 &&
                                    !_isSynthesizing
                                ? () => audioHandler?.playSentenceAt(_currentGlobalIndex + 1)
                                : null,
                            icon: const Icon(Icons.skip_next_rounded),
                            iconSize: 36,
                            tooltip: 'Phrase suivante',
                          ),
                        ],
                      ),
                    ),
                    // Bouton vitesse à droite
                    GestureDetector(
                      onTap: _showSpeedDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Theme.of(context).colorScheme.primary),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${_playbackSpeed % 1 == 0 ? _playbackSpeed.toInt() : _playbackSpeed}x',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _saveProgress(); // sauvegarder en quittant l'écran
    // Sauvegarder le temps de lecture si l'utilisateur ferme sans pauser
    if (_readingStopwatch.isRunning) {
      _readingStopwatch.stop();
      _flushReadingTime();
    }
    _ttsService.cancel();
    audioHandler?.currentIndexNotifier.removeListener(_onHandlerIndexChanged);
    audioHandler?.isSynthesizingNotifier.removeListener(_onHandlerSynthesizingChanged);
    audioHandler?.shouldBePlayingNotifier.removeListener(_onHandlerWantsToPlayChanged);
    fontSizeNotifier.removeListener(_onFontChanged);
    fontFamilyNotifier.removeListener(_onFontChanged);
    _playerStateSub?.cancel();
    _selectionRangeNotifier.dispose();
    // On ne reset plus jamais ici, même en pause — sinon la session (et donc
    // le mini-lecteur affiché sur les autres onglets) disparaît dès qu'on
    // quitte le livre sans être en train de lire. La session est de toute
    // façon remplacée proprement au prochain startSession() (même livre ou
    // un autre).
    super.dispose();
  }
}
