import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show translationLanguageNotifier;
import '../models/translation_entry.dart';
import '../services/translation_service.dart';

enum _SheetState { loading, error, result }

/// Fiche de traduction manuelle d'un mot ou d'une phrase sélectionnée dans
/// le lecteur (bouton "Traduire" de la barre de sélection, voir
/// reader_screen.dart) — montée depuis le bas de l'écran. Widget PUBLIC :
/// réutilisé tel quel par l'onglet Traductions des annotations, où
/// [preloaded] permet de rouvrir une entrée déjà enregistrée sans réseau.
class TranslationSheet extends StatefulWidget {
  final String text;

  /// Langue DU TEXTE (code court ISO, ex: 'en') — la traduction se fait vers
  /// translationLanguageNotifier (réglage indépendant de celui du
  /// dictionnaire).
  final String sourceLang;
  final String ebookId;
  final String chapterId;

  /// Position dans le chapitre — permet de retrouver le passage exact dans
  /// le livre plus tard (voir _TranslationTile dans annotations_screen.dart).
  final int paragraphIndexInChapter;

  /// Non-null quand on rouvre une entrée déjà enregistrée depuis la liste :
  /// aucune requête réseau n'est alors faite, la fiche marche hors-ligne, et
  /// le bouton du bas devient "Supprimer" plutôt qu'"Enregistrer".
  final TranslationEntry? preloaded;

  const TranslationSheet({
    Key? key,
    required this.text,
    required this.sourceLang,
    this.ebookId = '',
    this.chapterId = '',
    this.paragraphIndexInChapter = -1,
    this.preloaded,
  }) : super(key: key);

  @override
  State<TranslationSheet> createState() => _TranslationSheetState();
}

class _TranslationSheetState extends State<TranslationSheet> {
  final TranslationService _service = TranslationService();

  _SheetState _state = _SheetState.loading;
  String? _translatedText;
  bool _saved = false;

  /// Langue cible figée au moment de l'ouverture — si l'utilisateur change
  /// la langue de traduction dans Profil pendant que cette fiche est
  /// ouverte, on ne veut pas qu'elle change de langue sous ses yeux.
  late final String _targetLang;

  @override
  void initState() {
    super.initState();
    _targetLang = widget.preloaded?.targetLang ?? translationLanguageNotifier.value;
    if (widget.preloaded != null) {
      _saved = true;
    }
    _load();
  }

  Future<void> _load() async {
    final preloaded = widget.preloaded;
    if (preloaded != null) {
      setState(() {
        _translatedText = preloaded.translatedText;
        _state = _SheetState.result;
      });
      return;
    }

    setState(() => _state = _SheetState.loading);
    try {
      final translated = await _service.translate(
        text: widget.text,
        sourceLang: widget.sourceLang,
        targetLang: _targetLang,
      );
      if (!mounted) return;
      setState(() {
        _translatedText = translated;
        _state = _SheetState.result;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _SheetState.error);
    }
  }

  Future<void> _saveEntry() async {
    final translated = _translatedText;
    if (translated == null) return;
    final box = Hive.box<TranslationEntry>('translations');

    final alreadySaved = box.values.any((e) =>
        e.text == widget.text && e.ebookId == widget.ebookId && e.targetLang == _targetLang);

    final messenger = ScaffoldMessenger.of(context);
    if (alreadySaved) {
      setState(() => _saved = true);
      messenger.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.translationSheet_alreadySaved)),
      );
      return;
    }

    final entry = TranslationEntry(
      id: 'trad_${DateTime.now().microsecondsSinceEpoch}',
      text: widget.text,
      translatedText: translated,
      ebookId: widget.ebookId,
      chapterId: widget.chapterId,
      paragraphIndexInChapter: widget.paragraphIndexInChapter,
      sourceLang: widget.sourceLang,
      targetLang: _targetLang,
      createdAt: DateTime.now(),
    );
    await box.put(entry.id, entry);
    if (!mounted) return;
    setState(() => _saved = true);
  }

  Future<void> _deletePreloaded() async {
    final preloaded = widget.preloaded;
    if (preloaded == null) return;
    await Hive.box<TranslationEntry>('translations').delete(preloaded.id);
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
        return const Center(child: CircularProgressIndicator());
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
                  l10n.common_noConnectionTranslation,
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
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, l10n.translationSheet_originalText),
          const SizedBox(height: 4),
          Text(widget.text, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 20),
          _sectionTitle(context, l10n.translationSheet_translation),
          const SizedBox(height: 4),
          Text(
            _translatedText ?? '',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
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
                onPressed: _saved ? null : _saveEntry,
                icon: Icon(_saved ? Icons.check_rounded : Icons.bookmark_add_rounded),
                label: Text(_saved ? l10n.common_saved : l10n.common_save),
              ),
          ],
        ),
      ),
    );
  }
}
