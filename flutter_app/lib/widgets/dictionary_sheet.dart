import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show audioHandler, dictionaryLanguageNotifier;
import '../models/dictionary_entry.dart';
import '../services/dictionary_service.dart';
import '../services/local_llm_service.dart';
import '../services/sherpa_tts_service.dart';
import '../services/offline_dictionary_service.dart';

enum _SheetState { loading, error, result }

/// Fiche de définition d'un mot — montée depuis le bas de l'écran à ~75% de
/// hauteur (voir _openDictionaryForWord dans reader_screen.dart). Widget
/// PUBLIC : réutilisé tel quel par l'onglet Dictionnaire des annotations,
/// où [preloaded] permet de rouvrir une entrée déjà enregistrée sans réseau.
class DictionarySheet extends StatefulWidget {
  final String word;

  /// Langue DU MOT (code court ISO, ex: 'en') — Gemini rédige la définition
  /// dans la langue choisie par l'utilisateur (dictionaryLanguageNotifier),
  /// pas forcément celle-ci.
  final String sourceLang;
  final String ebookId;
  final String chapterId;

  /// Non-null quand on rouvre un mot déjà enregistré depuis la liste de
  /// vocabulaire : aucune requête réseau n'est alors faite, la fiche marche
  /// hors-ligne, et le bouton du bas devient "Supprimer" plutôt
  /// qu'"Enregistrer".
  final DictionaryEntry? preloaded;

  /// Phrase du livre où le mot a été sélectionné — l'IA locale explique le
  /// sens qu'il a dans CETTE phrase.
  final String? contextSentence;

  const DictionarySheet({
    Key? key,
    required this.word,
    required this.sourceLang,
    this.ebookId = '',
    this.chapterId = '',
    this.preloaded,
    this.contextSentence,
  }) : super(key: key);

  @override
  State<DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends State<DictionarySheet> {
  final DictionaryService _service = DictionaryService();
  final AudioPlayer _wordPlayer = AudioPlayer();

  _SheetState _state = _SheetState.loading;
  DictionaryLookup? _lookup;

  /// Vrai tant que l'IA locale écrit encore la fiche (bouton Enregistrer
  /// désactivé, petite barre de progression en haut).
  bool _streaming = false;
  bool _saved = false;
  // null = message générique traduit (common_noConnectionDictionary),
  // non-null = catégorie d'erreur précise remontée par l'API, mappée à un
  // message localisé à l'affichage (voir DictionaryNetworkException).
  DictionaryErrorCode? _errorCode;

  /// Fiche du dictionnaire hors ligne (null : mot absent → fiche IA).
  OfflineLookup? _offline;

  /// Sens dans la phrase, écrit par l'IA locale en complément de [_offline].
  LocalContextMeaning? _ctx;
  bool _ctxStreaming = false;
  static final Map<String, LocalContextMeaning> _contextCache = {};

  /// Langue cible figée au moment de l'ouverture — si l'utilisateur change
  /// la langue du dictionnaire dans Profil pendant que cette fiche est
  /// ouverte, on ne veut pas qu'elle change de langue sous ses yeux.
  late final String _targetLang;

  @override
  void initState() {
    super.initState();
    _targetLang = widget.preloaded?.targetLang ?? dictionaryLanguageNotifier.value;
    if (widget.preloaded != null) {
      _saved = true;
    }
    _load();
  }

  Future<void> _load() async {
    final preloaded = widget.preloaded;
    if (preloaded != null) {
      // Fiche déjà enregistrée : on reconstruit le résultat depuis les
      // champs stockés, sans le moindre appel réseau — la liste de
      // vocabulaire doit rester consultable hors-ligne.
      setState(() {
        _lookup = DictionaryLookup(
          word: preloaded.word,
          translatedWord: preloaded.translatedWord,
          partOfSpeech: preloaded.partOfSpeech,
          definition: preloaded.definition,
          example: preloaded.example,
          synonyms: preloaded.synonyms,
        );
        _state = _SheetState.result;
      });
      return;
    }

    setState(() {
      _state = _SheetState.loading;
      _streaming = true;
      _offline = null;
      _ctx = null;
    });

    // 1) Dictionnaire hors ligne (Wiktionary, SQLite) : instantané.
    OfflineLookup? offline;
    try {
      offline = await OfflineDictionaryService.instance.lookup(
        word: widget.word,
        sourceLang: widget.sourceLang,
        targetLang: _targetLang,
      );
    } catch (e) {
      debugPrint('[DICT] base hors ligne indisponible : $e');
    }
    if (!mounted) return;
    if (offline != null) {
      setState(() {
        _offline = offline;
        _state = _SheetState.result;
        _streaming = false;
      });
      // 2) En complément, l'IA locale donne le sens dans CETTE phrase.
      await _loadContextMeaning();
      return;
    }

    // Mot absent de la base : fiche complète rédigée par l'IA locale.
    try {
      // Flux : avec l'IA locale, la fiche se remplit pendant que le modèle
      // écrit (premiers mots en 1-2 s au lieu d'attendre la réponse entière).
      await for (final lookup in _service.lookupStream(
        word: widget.word,
        sourceLang: widget.sourceLang,
        targetLang: _targetLang,
        contextSentence: widget.contextSentence,
      )) {
        if (!mounted) return;
        setState(() {
          _lookup = lookup;
          _state = _SheetState.result;
        });
      }
      if (!mounted) return;
      setState(() => _streaming = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _streaming = false;
        _state = _SheetState.error;
        _errorCode = e is DictionaryNetworkException ? e.code : null;
      });
    }
  }

  /// Sens du mot dans sa phrase (≈20 mots, 2-3 s), par l'IA locale.
  /// Silencieux si le modèle n'est pas installé : la fiche de la base suffit.
  Future<void> _loadContextMeaning() async {
    final sentence = (widget.contextSentence ?? '').trim();
    final llm = LocalLlmService.instance;
    if (!await llm.isInstalled()) return;
    final key = '${widget.sourceLang}|$_targetLang|${widget.word.toLowerCase()}|$sentence';
    final cached = _contextCache[key];
    if (cached != null) {
      if (mounted) setState(() => _ctx = cached);
      return;
    }
    if (!mounted) return;
    setState(() => _ctxStreaming = true);
    try {
      LocalContextMeaning? last;
      await for (final m in llm.explainInContext(
        word: widget.word,
        // Sans phrase, le modèle donne simplement le sens le plus courant.
        sentence: sentence.isEmpty ? widget.word : sentence,
        sourceLang: widget.sourceLang,
        targetLang: _targetLang,
        senses: [
          for (final e in _offline?.entries ?? const <OfflineEntry>[])
            for (final s in e.senses) s.gloss,
        ],
      )) {
        if (!mounted) return;
        last = m;
        setState(() => _ctx = m);
      }
      if (last != null && last.meaning.isNotEmpty) _contextCache[key] = last;
    } catch (e) {
      debugPrint('[DICT] sens en contexte échoué : $e');
    } finally {
      if (mounted) setState(() => _ctxStreaming = false);
    }
  }

  Future<void> _speakWord() async {
    // La lecture du livre est mise en pause : on s'est arrêté pour chercher
    // un mot.
    await audioHandler?.pause();
    // Voix IA locale de la langue du mot — de préférence celle du livre, déjà
    // chargée dans le moteur (pas de rechargement de modèle).
    final current = SherpaTtsService.voiceByName(audioHandler?.voiceName ?? '');
    final voice = current != null &&
            current.languageCode.toLowerCase().startsWith(widget.sourceLang.toLowerCase())
        ? current
        : await SherpaTtsService.instance.firstInstalledVoiceFor(widget.sourceLang);
    if (voice == null) return;
    try {
      final tmp = await getTemporaryDirectory();
      final path = '${tmp.path}/word_${DateTime.now().millisecondsSinceEpoch}.wav';
      await SherpaTtsService.instance.synthesizeToFile(
          text: widget.word, voiceName: voice.name, outPath: path, speed: 0.9);
      if (!mounted) return;
      await _wordPlayer.setAudioSource(AudioSource.uri(Uri.file(path)));
      await _wordPlayer.play();
    } catch (e) {
      debugPrint('[DICT] prononciation impossible : $e');
    }
  }

  @override
  void dispose() {
    _wordPlayer.dispose();
    super.dispose();
  }

  /// Fiche hybride (base + sens en contexte) ramenée au format enregistré.
  DictionaryLookup? _hybridLookup() {
    final o = _offline;
    if (o == null) return null;
    final first = o.entries.isNotEmpty ? o.entries.first : null;
    final senses = first?.senses ?? const <OfflineSense>[];
    final ctxMeaning = _ctx?.meaning ?? '';
    return DictionaryLookup(
      word: widget.word,
      translatedWord: _ctx?.translation ?? '',
      partOfSpeech: first?.partOfSpeech ?? '',
      definition: ctxMeaning.isNotEmpty
          ? ctxMeaning
          : (senses.isNotEmpty ? senses.first.gloss : (o.formDescription ?? '')),
      example: senses.map((s) => s.example).firstWhere((e) => e.isNotEmpty, orElse: () => ''),
      synonyms: first?.synonyms.take(6).toList() ?? const [],
    );
  }

  Future<void> _saveEntry() async {
    final lookup = _hybridLookup() ?? _lookup;
    if (lookup == null) return;
    final box = Hive.box<DictionaryEntry>('dictionary');
    final wordLower = widget.word.toLowerCase();

    final alreadySaved = box.values.any((e) =>
        e.wordLower == wordLower && e.ebookId == widget.ebookId && e.targetLang == _targetLang);

    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    if (alreadySaved) {
      setState(() => _saved = true);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dictionarySheet_alreadyInList(widget.word))),
      );
      return;
    }

    final entry = DictionaryEntry(
      id: 'dict_${DateTime.now().microsecondsSinceEpoch}',
      word: widget.word,
      wordLower: wordLower,
      ebookId: widget.ebookId,
      chapterId: widget.chapterId,
      sourceLang: widget.sourceLang,
      targetLang: _targetLang,
      translatedWord: lookup.translatedWord,
      partOfSpeech: lookup.partOfSpeech,
      definition: lookup.definition,
      example: lookup.example,
      synonyms: lookup.synonyms,
      createdAt: DateTime.now(),
    );
    await box.put(entry.id, entry);
    if (!mounted) return;
    setState(() => _saved = true);
  }

  Future<void> _deletePreloaded() async {
    final preloaded = widget.preloaded;
    if (preloaded == null) return;
    await Hive.box<DictionaryEntry>('dictionary').delete(preloaded.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(child: _buildBody(context)),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (_state) {
      case _SheetState.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n.dictionarySheet_searching(widget.word)),
            ],
          ),
        );
      case _SheetState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  _errorMessageFor(l10n, _errorCode),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: Text(l10n.common_retry)),
              ],
            ),
          ),
        );
      case _SheetState.result:
        return _buildResult(context);
    }
  }

  Widget _buildHybrid(BuildContext context, OfflineLookup o) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ctx = _ctx;
    final translation = ctx?.translation ?? '';
    final showTranslation =
        translation.isNotEmpty && translation.toLowerCase() != widget.word.toLowerCase();
    final showCtxCard = _ctxStreaming || (ctx != null && ctx.meaning.isNotEmpty);
    final synonyms = <String>{for (final e in o.entries) ...e.synonyms}.take(8).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.word,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                onPressed: _speakWord,
                icon: const Icon(Icons.volume_up_rounded),
                tooltip: l10n.dictionarySheet_listenPronunciation,
              ),
            ],
          ),
          if (showTranslation)
            Text(translation,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
          if (o.formOf != null) ...[
            const SizedBox(height: 4),
            Text(l10n.dictionarySheet_formOf(o.formOf!),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic, color: Colors.grey[600])),
          ],
          if (showCtxCard) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.auto_awesome_rounded, size: 14, color: scheme.primary),
                    const SizedBox(width: 6),
                    _sectionTitle(context, l10n.dictionarySheet_inThisSentence),
                  ]),
                  const SizedBox(height: 6),
                  if (ctx != null && ctx.meaning.isNotEmpty)
                    Text(ctx.meaning)
                  else
                    const LinearProgressIndicator(minHeight: 2),
                ],
              ),
            ),
          ],
          for (final e in o.entries) ...[
            const SizedBox(height: 18),
            Text(
              [if (e.word.toLowerCase() != widget.word.toLowerCase()) e.word, e.partOfSpeech]
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              style: theme.textTheme.titleSmall?.copyWith(
                  fontStyle: FontStyle.italic, color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < e.senses.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}.',
                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.senses[i].gloss),
                          if (e.senses[i].example.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                e.senses[i].example,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic, color: Colors.grey[600]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (o.entries.isEmpty && o.formDescription != null) ...[
            const SizedBox(height: 14),
            Text(o.formDescription!),
          ],
          if (synonyms.isNotEmpty) ...[
            const SizedBox(height: 14),
            _sectionTitle(context, l10n.dictionarySheet_synonyms),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: synonyms.map((s) => Chip(label: Text(s))).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final offline = _offline;
    if (offline != null) return _buildHybrid(context, offline);
    final lookup = _lookup!;
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_streaming)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  widget.word,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _speakWord,
                icon: const Icon(Icons.volume_up_rounded),
                tooltip: l10n.dictionarySheet_listenPronunciation,
              ),
            ],
          ),
          if (lookup.translatedWord.isNotEmpty &&
              lookup.translatedWord.toLowerCase() != widget.word.toLowerCase()) ...[
            const SizedBox(height: 4),
            Text(
              lookup.translatedWord,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          if (lookup.partOfSpeech.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              lookup.partOfSpeech,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic, color: Colors.grey[600]),
            ),
          ],

          if (lookup.definition.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle(context, l10n.dictionarySheet_definition),
            const SizedBox(height: 4),
            Text(lookup.definition),
          ],

          if (lookup.example.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '« ${lookup.example} »',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[700],
                  ),
            ),
          ],

          // Section masquée entièrement si vide, plutôt qu'un titre orphelin.
          if (lookup.synonyms.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle(context, l10n.dictionarySheet_synonyms),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: lookup.synonyms.map((s) => Chip(label: Text(s))).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _errorMessageFor(AppLocalizations l10n, DictionaryErrorCode? code) {
    switch (code) {
      case DictionaryErrorCode.quotaExceeded:
        return l10n.dictionarySheet_quotaExceeded;
      case DictionaryErrorCode.unexpectedResponse:
        return l10n.dictionarySheet_unexpectedResponse;
      case DictionaryErrorCode.localModelMissing:
        return l10n.dictionarySheet_localModelMissing;
      case DictionaryErrorCode.unreachable:
      case null:
        return l10n.common_noConnectionDictionary;
    }
  }

  Widget _sectionTitle(BuildContext context, String label) => Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        ),
      );

  Widget _buildFooter(BuildContext context) {
    if (_state != _SheetState.result) return const SizedBox.shrink();
    final isPreloaded = widget.preloaded != null;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.common_close),
            ),
            const Spacer(),
            if (isPreloaded)
              TextButton.icon(
                onPressed: _deletePreloaded,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                label: Text(l10n.common_delete, style: const TextStyle(color: Colors.red)),
              )
            else
              FilledButton.icon(
                onPressed: _saved || _streaming || _ctxStreaming ? null : _saveEntry,
                icon: Icon(_saved ? Icons.check_rounded : Icons.bookmark_add_rounded),
                label: Text(_saved ? l10n.common_saved : l10n.common_save),
              ),
          ],
        ),
      ),
    );
  }
}
