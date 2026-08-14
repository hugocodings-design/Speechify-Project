import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:epub_decoder/epub_decoder.dart';
import 'package:logger/logger.dart';
import 'package:xml/xml.dart';

import '../models/chapter.dart';

class FileService {
  final String apiBaseUrl;
  late final Dio _dio;
  final _logger = Logger();

  FileService({this.apiBaseUrl = 'http://192.168.0.10:8000'}) {
    _dio = Dio(BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }

  /// Extrait le texte d'un PDF en envoyant le fichier au backend Python
  Future<List<Chapter>> extractPdfText(String filePath) async {
    try {
      _logger.i('Extraction PDF via backend: $filePath');

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: 'document.pdf'),
      });

      final response = await _dio.post<Map<String, dynamic>>(
        '/api/extract-pdf',
        data: formData,
      );

      final chaptersJson = response.data!['chapters'] as List;
      final chapters = chaptersJson.map((c) {
        final map = c as Map<String, dynamic>;
        return Chapter(
          id: map['id'] as String,
          title: map['title'] as String,
          textContent: map['textContent'] as String,
          wordCount: map['wordCount'] as int,
          pageNumber: map['pageNumber'] as int,
        );
      }).toList();

      _logger.i('Extraction PDF terminée: ${chapters.length} chapitres');
      return chapters;
    } on DioException catch (e) {
      _logger.e('Erreur réseau extraction PDF: $e');
      throw Exception('Impossible d\'extraire le PDF: ${e.message}');
    } catch (e) {
      _logger.e('Erreur extraction PDF: $e');
      rethrow;
    }
  }

  /// Extrait le texte d'un EPUB.
  /// Essaie epub_decoder en premier, puis fallback ZIP direct si ça échoue.
  Future<List<Chapter>> extractEpubText(String filePath) async {
    _logger.i('Extraction EPUB: $filePath');
    final bytes = await File(filePath).readAsBytes();

    // Tentative 1 : epub_decoder (standard EPUBs avec dossier OEBPS/)
    try {
      final chapters = await _extractViaEpubDecoder(bytes);
      if (chapters.isNotEmpty) {
        _logger.i('epub_decoder: ${chapters.length} chapitres extraits');
        return chapters;
      }
    } catch (e) {
      _logger.w('epub_decoder a échoué, fallback ZIP: $e');
    }

    // Tentative 2 : lecture directe du ZIP (EPUBs non-standard)
    try {
      final chapters = await _extractViaZip(bytes);
      if (chapters.isNotEmpty) {
        _logger.i('Fallback ZIP: ${chapters.length} chapitres extraits');
        return chapters;
      }
    } catch (e) {
      _logger.e('Fallback ZIP a aussi échoué: $e');
    }

    return _emptyChapter();
  }

  /// Méthode 1 : epub_decoder (fonctionne pour les EPUBs avec structure OEBPS/)
  Future<List<Chapter>> _extractViaEpubDecoder(List<int> bytes) async {
    final epub = Epub.fromBytes(Uint8List.fromList(bytes));
    final chapters = <Chapter>[];

    for (final section in epub.sections) {
      try {
        final xhtmlBytes = section.content.fileContent;
        final xhtmlString = utf8.decode(xhtmlBytes);
        final text = _stripHtml(xhtmlString);

        if (text.trim().length < 100) continue;

        final words = text.trim().split(RegExp(r'\s+'));
        final order = section.readingOrder;

        chapters.add(Chapter(
          id: 'ch_$order',
          title: _extractTitle(xhtmlString, order),
          textContent: text.trim(),
          wordCount: words.length,
          pageNumber: order,
        ));
      } catch (e) {
        _logger.w('Section ${section.readingOrder} ignorée: $e');
      }
    }

    return chapters;
  }

  /// Méthode 2 : lecture directe du ZIP EPUB sans supposer la structure
  Future<List<Chapter>> _extractViaZip(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Étape 1 : lire META-INF/container.xml pour trouver le fichier OPF
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) throw Exception('META-INF/container.xml introuvable');

    final containerXml = XmlDocument.parse(utf8.decode(containerFile.content));
    final opfPath = containerXml
        .findAllElements('rootfile')
        .first
        .getAttribute('full-path');
    if (opfPath == null) throw Exception('Chemin OPF introuvable');

    // Dossier de base = répertoire contenant le fichier OPF
    final baseDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    // Étape 2 : lire le fichier OPF pour obtenir le spine (ordre de lecture)
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) throw Exception('Fichier OPF introuvable: $opfPath');

    final opfXml = XmlDocument.parse(utf8.decode(opfFile.content));

    // Construire une map id → href depuis le manifest
    final manifestItems = <String, String>{};
    for (final item in opfXml.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final mediaType = item.getAttribute('media-type') ?? '';
      if (id != null && href != null && mediaType.contains('xhtml')) {
        manifestItems[id] = href;
      }
    }

    // Lire l'ordre du spine
    final spineItems = opfXml.findAllElements('itemref')
        .map((e) => e.getAttribute('idref'))
        .whereType<String>()
        .toList();

    // Étape 3 : extraire le texte de chaque fichier XHTML dans l'ordre du spine
    final chapters = <Chapter>[];
    int order = 0;

    for (final idref in spineItems) {
      final href = manifestItems[idref];
      if (href == null) continue;

      // Construire le chemin complet dans le ZIP
      final fullPath = href.startsWith('/') ? href.substring(1) : '$baseDir$href';
      final xhtmlFile = archive.findFile(fullPath);
      if (xhtmlFile == null) continue;

      final xhtmlString = utf8.decode(xhtmlFile.content);
      final text = _stripHtml(xhtmlString);

      if (text.trim().length < 100) continue;

      order++;
      final words = text.trim().split(RegExp(r'\s+'));

      chapters.add(Chapter(
        id: 'ch_$order',
        title: _extractTitle(xhtmlString, order),
        textContent: text.trim(),
        wordCount: words.length,
        pageNumber: order,
      ));
    }

    return chapters;
  }

  /// Supprime les balises HTML et décode les entités pour obtenir du texte brut
  String _stripHtml(String html) {
    String text = html.replaceAll(
      RegExp(r'<(script|style)[^>]*>.*?</(script|style)>', dotAll: true),
      '',
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
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

  List<Chapter> _emptyChapter() {
    return [
      Chapter(
        id: 'ch_1',
        title: 'Chapitre 1',
        textContent: 'Aucun texte lisible trouvé dans ce fichier.',
        wordCount: 8,
        pageNumber: 1,
      ),
    ];
  }

  /// Détecte le format selon l'extension du fichier
  String detectFileFormat(String filePath) {
    if (filePath.toLowerCase().endsWith('.pdf')) return 'pdf';
    if (filePath.toLowerCase().endsWith('.epub')) return 'epub';
    throw Exception('Format non supporté (PDF et EPUB seulement)');
  }

  /// Point d'entrée principal: extrait le texte selon le format détecté
  Future<List<Chapter>> extractText(String filePath) async {
    final format = detectFileFormat(filePath);
    if (format == 'pdf') return extractPdfText(filePath);
    if (format == 'epub') return extractEpubText(filePath);
    throw Exception('Format non supporté: $format');
  }
}
