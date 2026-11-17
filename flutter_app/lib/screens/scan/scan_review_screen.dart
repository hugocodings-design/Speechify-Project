import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/ebook.dart';
import '../../models/scan_page.dart';
import '../../services/image_processing_service.dart';
import '../../services/ocr_service.dart';
import '../../services/scan_to_book_service.dart';
import 'crop_screen.dart';

/// Révision de la session : remettre les pages dans l'ordre, en retirer,
/// en recadrer une mal cadrée, puis produire le livre.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({Key? key, required this.pages}) : super(key: key);

  final List<ScanPage> pages;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  bool _busy = false;

  Future<void> _recrop(ScanPage page) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CropScreen(page: page)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editText(ScanPage page) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: page.recognizedText ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.scanReview_correctText),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 14,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.common_save),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        page.recognizedText = controller.text;
        page.status =
            controller.text.trim().isEmpty ? ScanStatus.failed : ScanStatus.done;
        page.error = controller.text.trim().isEmpty ? l10n.scanReview_noTextFound : null;
      });
    }
  }

  Future<void> _createBook() async {
    final l10n = AppLocalizations.of(context)!;
    final usable = widget.pages.where((p) => p.hasText).toList();
    if (usable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.scanReview_noPagesWithText),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year}';
    final controller = TextEditingController(
      text: l10n.scanReview_defaultTitle(dateStr),
    );
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.scanReview_bookTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.scanReview_create),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final chapters = ScanToBookService.buildChapters(
        usable.map((p) => p.recognizedText ?? '').toList(),
      );
      if (chapters.isEmpty) {
        throw Exception('Le texte reconnu est vide après nettoyage');
      }

      // Nombre total de phrases, pour la barre de progression — même calcul
      // que pour un import PDF/EPUB (voir MainScreen._pickAndUploadFile).
      var totalSentences = 0;
      for (final ch in chapters) {
        totalSentences += ch.textContent
            .split(RegExp(r'(?<=[.!?…])\s+'))
            .where((s) => s.trim().isNotEmpty)
            .length;
      }

      final ebook = Ebook(
        id: now.millisecondsSinceEpoch.toString(),
        title: title,
        chapters: chapters,
        uploadedAt: now,
        fileFormat: 'scan',
        totalSentences: totalSentences,
      );
      await Hive.box<Ebook>('ebooks').put(ebook.id, ebook);

      await OcrService.instance.dispose();
      await ImageProcessingService.clearSession();

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.scanReview_creationFailed('$e')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalWords =
        widget.pages.fold<int>(0, (sum, p) => sum + p.wordCount);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scanReview_verifyPages),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.scanReview_pagesWordsSummary(widget.pages.length, totalWords),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          ReorderableListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: widget.pages.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                widget.pages.insert(newIndex, widget.pages.removeAt(oldIndex));
              });
            },
            itemBuilder: (context, index) {
              final page = widget.pages[index];
              return _buildTile(page, index);
            },
          ),
          if (_busy)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _busy ? null : _createBook,
            icon: const Icon(Icons.auto_stories),
            label: Text(l10n.scanReview_createBook),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(ScanPage page, int index) {
    final l10n = AppLocalizations.of(context)!;
    final path = page.rectifiedPath ?? page.sourcePath;
    final preview = (page.recognizedText ?? '').replaceAll('\n', ' ').trim();

    return Card(
      key: ValueKey(page.id),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            File(path),
            key: ValueKey(path),
            width: 44,
            height: 60,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
        title: Text(l10n.scanReview_pageWordCount(index + 1, page.wordCount)),
        subtitle: Text(
          page.hasText
              ? (preview.length > 90 ? '${preview.substring(0, 90)}…' : preview)
              : (page.error ?? l10n.crop_noTextRecognized),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: page.hasText ? null : const TextStyle(color: Colors.red),
        ),
        onTap: () => _editText(page),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.crop),
              tooltip: l10n.scanReview_recrop,
              onPressed: _busy ? null : () => _recrop(page),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: l10n.common_delete,
              onPressed: _busy
                  ? null
                  : () => setState(() => widget.pages.remove(page)),
            ),
          ],
        ),
      ),
    );
  }
}
