import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:xml/xml.dart';
import '../models/chapter.dart';

class FileService {
  final _logger = Logger();

  /// Au-delà, on regroupe plusieurs pages par chapitre — même convention que
  /// l'ancien backend (`pages_per_chapter = max(1, total_pages // 20)`), pour
  /// ne pas produire des dizaines de micro-chapitres sur un livre de 300 pages.
  static const int _maxChaptersTarget = 20;

  /// Extraire le texte d'un PDF, entièrement sur l'appareil (pdfrx/pdfium) —
  /// aucun réseau requis, fonctionne loin de tout Wi-Fi.
  Future<List<Chapter>> extractPdfText(String filePath) async {
    pdfrx.PdfDocument? document;
    try {
      _logger.i('Extraction PDF locale: $filePath');
      document = await pdfrx.PdfDocument.openFile(filePath);
      final totalPages = document.pages.length;
      if (totalPages == 0) {
        throw Exception('Ce PDF ne contient aucune page');
      }

      final pageTexts = <String>[];
      for (final page in document.pages) {
        final pageText = await page.loadText();
        pageTexts.add(pageText.fullText);
      }

      final chapters = _groupPagesIntoChapters(pageTexts);
      if (chapters.isEmpty) {
        throw Exception(
          'Aucun texte extractible — ce PDF est probablement scanné/image '
          '(essayez plutôt le scan caméra, qui utilise la reconnaissance de texte).',
        );
      }
      _logger.i('PDF extrait: ${chapters.length} chapitres');
      return chapters;
    } catch (e) {
      _logger.e('Erreur extraction PDF: $e');
      rethrow;
    } finally {
      await document?.dispose();
    }
  }

  /// Regroupe le texte page par page en chapitres, façon backend :
  /// `pagesParChapitre = max(1, totalPages / 20)`, titre "Pages N–M".
  List<Chapter> _groupPagesIntoChapters(List<String> pageTexts) {
    final totalPages = pageTexts.length;
    final pagesPerChapter = (totalPages / _maxChaptersTarget).ceil().clamp(1, totalPages);
    final chapters = <Chapter>[];

    for (var start = 0; start < totalPages; start += pagesPerChapter) {
      final end = (start + pagesPerChapter).clamp(0, totalPages);
      final text = pageTexts
          .sublist(start, end)
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .join('\n\n');
      if (text.isEmpty) continue;

      final firstPage = start + 1;
      final lastPage = end;
      chapters.add(Chapter(
        id: 'ch_${chapters.length}',
        title: firstPage == lastPage ? 'Page $firstPage' : 'Pages $firstPage–$lastPage',
        textContent: text,
        wordCount: text.split(RegExp(r'\s+')).length,
        pageNumber: firstPage,
      ));
    }
    return chapters;
  }

  /// Extraire le texte d'un EPUB, entièrement sur l'appareil.
  ///
  /// On lit directement le ZIP plutôt que d'utiliser `epub_decoder` : ce
  /// dernier plante sur certains EPUB aux types MIME non standards (déjà
  /// constaté pour l'extraction de couverture, voir `_extractEpubCover`).
  Future<List<Chapter>> extractEpubText(String filePath) async {
    try {
      _logger.i('Extraction EPUB locale: $filePath');
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final containerFile = archive.findFile('META-INF/container.xml');
      if (containerFile == null) {
        throw Exception('META-INF/container.xml introuvable — EPUB invalide');
      }
      final containerXml = XmlDocument.parse(utf8.decode(containerFile.content as List<int>));
      final opfPath = containerXml
          .findAllElements('rootfile')
          .first
          .getAttribute('full-path');
      if (opfPath == null) throw Exception('Chemin OPF introuvable');

      final opfDir = opfPath.contains('/')
          ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
          : '';

      final opfFile = archive.findFile(opfPath);
      if (opfFile == null) throw Exception('Fichier OPF introuvable: $opfPath');
      final opfXml = XmlDocument.parse(utf8.decode(opfFile.content as List<int>));

      final manifestItems = <String, String>{};
      for (final item in opfXml.findAllElements('item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        final mediaType = item.getAttribute('media-type') ?? '';
        if (id != null && href != null && mediaType.contains('html')) {
          manifestItems[id] = href;
        }
      }

      final spineItems = opfXml
          .findAllElements('itemref')
          .map((e) => e.getAttribute('idref'))
          .whereType<String>()
          .toList();

      final chapters = <Chapter>[];
      var order = 0;
      for (final idref in spineItems) {
        final href = manifestItems[idref];
        if (href == null) continue;

        final fullPath = href.startsWith('/') ? href.substring(1) : '$opfDir$href';
        final xhtmlFile = archive.findFile(fullPath);
        if (xhtmlFile == null) continue;

        final xhtmlString = utf8.decode(xhtmlFile.content as List<int>);
        final text = _stripHtml(xhtmlString);
        if (text.trim().length < 50) continue;

        order++;
        chapters.add(Chapter(
          id: 'ch_$order',
          title: _extractTitle(xhtmlString, order),
          textContent: text.trim(),
          wordCount: text.trim().split(RegExp(r'\s+')).length,
          pageNumber: order,
        ));
      }

      if (chapters.isEmpty) {
        throw Exception(
          'Aucun texte lisible trouvé dans cet EPUB (structure non reconnue, '
          'fichier vide, ou protégé par DRM).',
        );
      }
      _logger.i('EPUB extrait: ${chapters.length} chapitres');
      return chapters;
    } catch (e) {
      _logger.e('Erreur extraction EPUB: $e');
      rethrow;
    }
  }

  /// Supprime les balises HTML et décode les entités, en préservant les
  /// coupures de paragraphe (meilleures pauses à la synthèse vocale).
  String _stripHtml(String html) {
    var text = html.replaceAll(
      RegExp(r'<(script|style)[^>]*>.*?</(script|style)>', dotAll: true, caseSensitive: false),
      '',
    );
    // Marque les frontières de bloc avant de retirer les balises, pour ne
    // pas recoller deux paragraphes en une seule phrase.
    text = text.replaceAll(
      RegExp(r'</(p|div|li|h[1-6]|br)\s*>', caseSensitive: false),
      '\n\n',
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
    // Compacte les espaces horizontaux sans toucher aux doubles retours à la
    // ligne qui marquent les paragraphes.
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  /// Extrait le titre depuis les balises h1/h2/h3 du XHTML
  String _extractTitle(String html, int order) {
    final match = RegExp(
      r'<h[1-3][^>]*>(.*?)</h[1-3]>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(html);

    if (match != null) {
      final raw = match.group(1) ?? '';
      final title = _stripHtml(raw).trim();
      if (title.isNotEmpty) return title;
    }
    return 'Chapitre $order';
  }

  /// Détecter le format du fichier selon son extension
  String detectFileFormat(String filePath) {
    if (filePath.toLowerCase().endsWith('.pdf')) return 'pdf';
    if (filePath.toLowerCase().endsWith('.epub')) return 'epub';
    throw Exception('Format non supporté');
  }

  /// Extraire le texte selon le format
  Future<List<Chapter>> extractText(String filePath) async {
    final format = detectFileFormat(filePath);
    if (format == 'pdf') return extractPdfText(filePath);
    if (format == 'epub') return extractEpubText(filePath);
    throw Exception('Format non supporté: $format');
  }

  /// Extraire et sauvegarder la couverture d'un PDF ou EPUB.
  /// Retourne le chemin local de l'image, ou null si introuvable.
  Future<String?> extractCoverImage(String filePath, String fileFormat) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final coverDir = Directory('${docsDir.path}/covers');
      if (!await coverDir.exists()) await coverDir.create(recursive: true);

      final id = filePath.hashCode.abs().toString();
      _logger.i('Extraction couverture [$fileFormat] id=$id');

      String? result;
      if (fileFormat == 'pdf') {
        result = await _extractPdfCover(filePath, coverDir.path, id);
      } else if (fileFormat == 'epub') {
        result = await _extractEpubCover(filePath, coverDir.path, id);
      }

      _logger.i('Couverture extraite: $result');
      return result;
    } catch (e, s) {
      _logger.e('Extraction couverture échouée: $e', error: e, stackTrace: s);
    }
    return null;
  }

  Future<String?> _extractPdfCover(
      String filePath, String coverDir, String id) async {
    PdfDocument? document;
    PdfPage? page;
    try {
      document = await PdfDocument.openFile(filePath);
      _logger.i('PDF ouvert: ${document.pagesCount} pages, taille page 1 ?');
      page = await document.getPage(1);
      _logger.i('Page 1: ${page.width}x${page.height}');

      final renderWidth = page.width.clamp(100.0, 600.0);
      final renderHeight = page.height.clamp(100.0, 900.0);

      final image = await page.render(
        width: renderWidth,
        height: renderHeight,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 85,
      );
      _logger.i('Render résultat: ${image?.bytes.length} bytes');
      if (image != null && image.bytes.isNotEmpty) {
        final destPath = '$coverDir/cover_$id.jpg';
        await File(destPath).writeAsBytes(image.bytes);
        _logger.i('Couverture PDF sauvegardée: $destPath');
        return destPath;
      }
    } finally {
      await page?.close();
      await document?.close();
    }
    return null;
  }

  /// Extrait la couverture directement depuis le ZIP (EPUB = archive ZIP).
  /// Évite epub_decoder qui crash sur des types MIME non standards.
  Future<String?> _extractEpubCover(
      String filePath, String coverDir, String id) async {
    final zipBytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // 1 — Lire container.xml pour trouver le fichier OPF
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      _logger.w('EPUB: container.xml introuvable');
      return null;
    }
    final containerXml = utf8.decode(containerFile.content as List<int>);
    final opfMatch =
        RegExp(r'full-path="([^"]+\.opf)"', caseSensitive: false)
            .firstMatch(containerXml);
    if (opfMatch == null) {
      _logger.w('EPUB: OPF path introuvable dans container.xml');
      return null;
    }
    final opfPath = opfMatch.group(1)!;
    _logger.i('EPUB OPF: $opfPath');

    // 2 — Lire le fichier OPF
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) return null;
    final opfXml = utf8.decode(opfFile.content as List<int>);
    // Log des 1500 premiers caractères pour diagnostiquer le format
    _logger.i('OPF contenu (début):\n${opfXml.substring(0, opfXml.length.clamp(0, 1500))}');
    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    // 3 — Trouver le href de la couverture dans l'OPF
    String? coverHref;

    // Méthode A : <item properties="cover-image" href="..."/>
    final propMatch =
        RegExp(r'<item[^>]*properties="[^"]*cover-image[^"]*"[^>]*href="([^"]+)"',
                caseSensitive: false)
            .firstMatch(opfXml) ??
        RegExp(r'<item[^>]*href="([^"]+)"[^>]*properties="[^"]*cover-image[^"]*"',
                caseSensitive: false)
            .firstMatch(opfXml);
    if (propMatch != null) coverHref = propMatch.group(1);

    // Méthode B : chercher name="cover" n'importe où dans le OPF
    if (coverHref == null) {
      // Extraire l'id depuis content="..." dans un tag qui contient name="cover"
      String? coverId;
      final lowerOpf = opfXml.toLowerCase();
      final nameIdx = lowerOpf.indexOf('name="cover"');
      if (nameIdx >= 0) {
        // Trouver le début du tag <meta contenant ce name="cover"
        final tagStart = opfXml.lastIndexOf('<', nameIdx);
        final tagEnd = opfXml.indexOf('>', nameIdx);
        if (tagStart >= 0 && tagEnd > tagStart) {
          final metaTag = opfXml.substring(tagStart, tagEnd + 1);
          _logger.i('Meta tag trouvé: $metaTag');
          final contentMatch =
              RegExp(r'content="([^"]+)"', caseSensitive: false)
                  .firstMatch(metaTag);
          coverId = contentMatch?.group(1);
          _logger.i('Cover ID: $coverId');
        }
      }

      if (coverId != null) {
        final escapedId = RegExp.escape(coverId);
        final itemMatch =
            RegExp('id="$escapedId"[^>]*href="([^"]+)"', caseSensitive: false)
                .firstMatch(opfXml) ??
            RegExp('href="([^"]+)"[^>]*id="$escapedId"', caseSensitive: false)
                .firstMatch(opfXml);
        coverHref = itemMatch?.group(1);
        _logger.i('Cover href from meta: $coverHref');
      }
    }

    // Méthode C : fallback — premier <item> avec media-type image dans le manifest
    if (coverHref == null) {
      final imageMatch =
          RegExp(r'<item[^>]*media-type="image/[^"]*"[^>]*href="([^"]+)"',
                  caseSensitive: false)
              .firstMatch(opfXml) ??
          RegExp(r'<item[^>]*href="([^"]+)"[^>]*media-type="image/[^"]*"',
                  caseSensitive: false)
              .firstMatch(opfXml);
      if (imageMatch != null) {
        coverHref = imageMatch.group(1);
        _logger.i('Cover href fallback (première image): $coverHref');
      }
    }

    if (coverHref == null) {
      _logger.w('EPUB: couverture introuvable dans OPF');
      return null;
    }

    _logger.i('EPUB cover href: $coverHref');

    // 4 — Extraire l'image depuis l'archive
    final fullPath = '$opfDir$coverHref';
    final coverEntry = archive.findFile(fullPath) ??
        archive.findFile(coverHref); // fallback chemin absolu
    if (coverEntry == null) {
      _logger.w('EPUB: fichier couverture "$fullPath" introuvable dans ZIP');
      return null;
    }

    final coverBytes = coverEntry.content as List<int>;
    final ext = coverHref.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final destPath = '$coverDir/cover_$id.$ext';
    await File(destPath).writeAsBytes(Uint8List.fromList(coverBytes));
    _logger.i('Couverture EPUB sauvegardée: $destPath');
    return destPath;
  }
}
