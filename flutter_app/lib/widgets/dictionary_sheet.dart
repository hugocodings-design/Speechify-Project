import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show audioHandler, dictionaryLanguageNotifier;
import '../models/dictionary_entry.dart';
import '../services/dictionary_service.dart';
import '../services/local_tts_service.dart';

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
  final LocalTtsService _localTts = LocalTtsService();

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
    });
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

  Future<void> _speakWord() async {
    // Deux moteurs audio (flutter_tts pour la prononciation, just_audio pour
    // la lecture du livre) se disputeraient sinon le focus audio — mettre la
    // lecture en pause est de toute façon le comportement attendu : on
    // s'est arrêté pour chercher un mot.
    await audioHandler?.pause();
    final voice = LocalTtsService.availableVoices.firstWhere(
      (o) => o.languageCode.startsWith(widget.sourceLang),
      orElse: () => LocalTtsService.availableVoices.first,
    );
    await _localTts.speak(widget.word, option: voice, speed: 0.9);
  }

  Future<void> _saveEntry() async {
    final lookup = _lookup;
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
                Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[400]),
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

  Widget _buildResult(BuildContext context) {
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
                onPressed: _saved || _streaming ? null : _saveEntry,
                icon: Icon(_saved ? Icons.check_rounded : Icons.bookmark_add_rounded),
                label: Text(_saved ? l10n.common_saved : l10n.common_save),
              ),
          ],
        ),
      ),
    );
  }
}
