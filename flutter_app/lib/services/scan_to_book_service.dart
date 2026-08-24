import 'dart:math' as math;

import '../models/chapter.dart';

/// Un paragraphe et la page dont il provient.
class _Para {
  _Para(this.text, this.pageNumber);
  final String text;
  final int pageNumber;
  bool isChapterStart = false;
  String? detectedTitle;
}

/// Transforme le texte OCR brut de N pages en chapitres lisibles.
///
/// C'est ce qui fait la différence entre « un tas de texte reconnu » et un
/// livre écoutable : sans nettoyage, la synthèse lit les numéros de page en
/// plein milieu d'une phrase et prononce les mots coupés par une césure.
class ScanToBookService {
  /// `reader_screen.dart` tronque à 4500 caractères avant la synthèse : on
  /// reste sous ce seuil pour ne jamais perdre de texte silencieusement.
  static const int maxChapterChars = 4000;

  /// Une ligne isolée plus courte que ça peut être un titre.
  static const int _maxTitleLength = 60;

  static final RegExp _pageNumberLine = RegExp(
    r'^\s*[\-–—\[\(]?\s*(?:page\s*)?[\divxlcIVXLC]{1,6}\s*[\-–—\]\)]?\s*$',
    caseSensitive: false,
  );

  static final RegExp _chapterKeyword = RegExp(
    r'^\s*(chapitre|chapter|partie|livre|section|prologue|'
    r'épilogue|epilogue|avant[- ]propos|introduction|conclusion)\b',
    caseSensitive: false,
  );

  /// Point d'entrée : le texte OCR de chaque page, dans l'ordre de lecture.
  static List<Chapter> buildChapters(List<String> pageTexts) {
    final cleaned = _stripRunningHeaders(pageTexts);

    final paras = <_Para>[];
    for (var i = 0; i < cleaned.length; i++) {
      for (final p in _paragraphsOf(cleaned[i])) {
        paras.add(_Para(p, i + 1));
      }
    }
    if (paras.isEmpty) return const [];

    _markChapterStarts(paras);

    final detected = paras.where((p) => p.isChapterStart).length;
    var chapters = const <Chapter>[];
    if (detected >= 2) chapters = _groupByDetectedTitles(paras);

    // Repli si aucun titre n'a été trouvé, ou si l'heuristique a pris *tous*
    // les paragraphes pour des titres et n'a donc produit aucun corps.
    if (chapters.isEmpty) chapters = _groupByPages(paras, cleaned.length);

    return _enforceSizeLimit(chapters);
  }

  // -------------------------------------------------------------------
  // A. Nettoyage
  // -------------------------------------------------------------------

  /// Retire les en-têtes et pieds de page courants.
  ///
  /// La détection croisée entre pages est bien plus fiable qu'une heuristique
  /// page par page : un titre courant se reconnaît à ce qu'il se répète, un
  /// vrai titre de chapitre non.
  ///
  /// Le découpage en blocs (lignes vides) est préservé d'un bout à l'autre :
  /// c'est lui qui porte les paragraphes, et donc la détection des titres.
  static List<String> _stripRunningHeaders(List<String> pages) {
    if (pages.isEmpty) return const [];

    final blocksPerPage = pages.map(_blocksOf).toList();

    final firsts = <String, int>{};
    final lasts = <String, int>{};
    for (final blocks in blocksPerPage) {
      if (blocks.isEmpty) continue;
      final f = _signature(_firstLine(blocks));
      final l = _signature(_lastLine(blocks));
      if (f.isNotEmpty) firsts[f] = (firsts[f] ?? 0) + 1;
      if (l.isNotEmpty) lasts[l] = (lasts[l] ?? 0) + 1;
    }

    // Répété sur au moins 40 % des pages (et au moins 2 fois).
    final threshold = math.max(2, (pages.length * 0.4).ceil());
    bool repeated(Map<String, int> counts, String line) {
      final sig = _signature(line);
      return sig.isNotEmpty && (counts[sig] ?? 0) >= threshold;
    }

    bool droppable(Map<String, int> counts, String line) =>
        line.trim().length <= _maxTitleLength &&
        (_pageNumberLine.hasMatch(line) || repeated(counts, line));

    final out = <String>[];
    for (final blocks in blocksPerPage) {
      // On ne vide jamais une page entièrement : s'il ne reste qu'une ligne,
      // c'est du contenu, pas un en-tête.
      if (_lineCount(blocks) > 1 && droppable(firsts, _firstLine(blocks))) {
        _dropFirstLine(blocks);
      }
      if (_lineCount(blocks) > 1 && droppable(lasts, _lastLine(blocks))) {
        _dropLastLine(blocks);
      }
      out.add(blocks.join('\n\n'));
    }
    return out;
  }

  /// Blocs séparés par une ligne vide, chacun normalisé (lignes vides
  /// internes supprimées, espaces rognés).
  static List<String> _blocksOf(String page) => page
      .split(RegExp(r'\n\s*\n'))
      .map((b) => _linesOf(b).join('\n'))
      .where((b) => b.isNotEmpty)
      .toList();

  static int _lineCount(List<String> blocks) =>
      blocks.fold(0, (n, b) => n + b.split('\n').length);

  static String _firstLine(List<String> blocks) =>
      blocks.isEmpty ? '' : blocks.first.split('\n').first;

  static String _lastLine(List<String> blocks) =>
      blocks.isEmpty ? '' : blocks.last.split('\n').last;

  static void _dropFirstLine(List<String> blocks) {
    final lines = blocks.first.split('\n')..removeAt(0);
    if (lines.isEmpty) {
      blocks.removeAt(0);
    } else {
      blocks[0] = lines.join('\n');
    }
  }

  static void _dropLastLine(List<String> blocks) {
    final lines = blocks.last.split('\n')..removeLast();
    if (lines.isEmpty) {
      blocks.removeLast();
    } else {
      blocks[blocks.length - 1] = lines.join('\n');
    }
  }

  static List<String> _linesOf(String page) => page
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  /// Signature insensible aux numéros : « Chapitre 3 — Les nuages » et
  /// « Chapitre 7 — Les nuages » se ressemblent assez pour compter comme le
  /// même titre courant.
  static String _signature(String line) => line
      .toLowerCase()
      .replaceAll(RegExp(r'\d+'), '')
      .replaceAll(RegExp(r'[^\p{L} ]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Découpe une page en paragraphes.
  ///
  /// ML Kit sépare déjà les blocs par une ligne vide (voir `OcrService`), ce
  /// qui correspond en pratique aux paragraphes. À l'intérieur d'un bloc, les
  /// retours à la ligne sont de simples fins de ligne typographiques : on les
  /// recolle, en réparant les césures au passage.
  static List<String> _paragraphsOf(String pageText) {
    final blocks = pageText.split(RegExp(r'\n\s*\n'));
    final paras = <String>[];
    // Uniquement de vrais traits d'union (ASCII, U+2010, U+2011) — pas le
    // tiret demi-cadratin (–, U+2013) ni cadratin (—, U+2014), qui marquent
    // une pause ou une incise et n'ont jamais coupé un mot en deux. Les
    // confondre effaçait le tiret et recollait les deux mots (« il a dit—
    // attends » devenait « il a ditattends »).
    final hyphenEnd = RegExp(r'\p{L}[-‐‑]$', unicode: true);
    // Une vraie césure reprend toujours en minuscule (fin de mot coupé) ;
    // une phrase après un tiret de ponctuation commence presque toujours
    // par une majuscule ou une nouvelle proposition — ce second filtre
    // écarte les faux positifs restants.
    final startsLowercase = RegExp(r'^\p{Ll}', unicode: true);

    for (final block in blocks) {
      final lines = _linesOf(block);
      if (lines.isEmpty) continue;

      final buffer = StringBuffer(lines.first);
      for (var i = 1; i < lines.length; i++) {
        final prev = lines[i - 1];
        final line = lines[i];
        if (hyphenEnd.hasMatch(prev) && startsLowercase.hasMatch(line)) {
          // Césure de fin de ligne : « impos- sible » → « impossible ».
          final current = buffer.toString();
          buffer
            ..clear()
            ..write(current.substring(0, current.length - 1))
            ..write(line);
        } else {
          buffer
            ..write(' ')
            ..write(line);
        }
      }

      final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) paras.add(text);
    }
    return paras;
  }

  // -------------------------------------------------------------------
  // B. Découpage en chapitres
  // -------------------------------------------------------------------

  static void _markChapterStarts(List<_Para> paras) {
    for (final para in paras) {
      final t = para.text.trim();
      if (t.length > _maxTitleLength) continue;

      final byKeyword = _chapterKeyword.hasMatch(t);
      final byCaps = _isMostlyUpperCase(t);

      if (byKeyword || byCaps) {
        para.isChapterStart = true;
        para.detectedTitle = t;
      }
    }
  }

  static bool _isMostlyUpperCase(String s) {
    final letters = s.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
    if (letters.length < 3) return false;
    final upper = letters.replaceAll(RegExp(r'[^\p{Lu}]', unicode: true), '');
    return upper.length / letters.length >= 0.8;
  }

  static List<Chapter> _groupByDetectedTitles(List<_Para> paras) {
    final chapters = <Chapter>[];
    var current = <_Para>[];
    String? title;

    void flush() {
      if (current.isEmpty) return;
      chapters.add(_chapterOf(
        index: chapters.length,
        title: title ?? 'Chapitre ${chapters.length + 1}',
        paras: current,
      ));
      current = <_Para>[];
    }

    for (final para in paras) {
      if (para.isChapterStart) {
        flush();
        title = para.detectedTitle;
        continue; // le titre lui-même ne fait pas partie du corps
      }
      current.add(para);
    }
    flush();

    return chapters;
  }

  /// Repli : on reprend la convention de `/api/extract-pdf`
  /// (`backend/main.py:249-251`) pour que l'import scan et l'import PDF
  /// produisent des livres comparables.
  static List<Chapter> _groupByPages(List<_Para> paras, int totalPages) {
    final pagesPerChapter = math.max(1, totalPages ~/ 20);
    final chapters = <Chapter>[];

    for (var start = 1; start <= totalPages; start += pagesPerChapter) {
      final end = math.min(start + pagesPerChapter - 1, totalPages);
      final slice = paras
          .where((p) => p.pageNumber >= start && p.pageNumber <= end)
          .toList();
      if (slice.isEmpty) continue;
      chapters.add(_chapterOf(
        index: chapters.length,
        title: start == end ? 'Page $start' : 'Pages $start–$end',
        paras: slice,
      ));
    }
    return chapters;
  }

  static Chapter _chapterOf({
    required int index,
    required String title,
    required List<_Para> paras,
  }) {
    final text = paras.map((p) => p.text).join('\n\n');
    return Chapter(
      id: 'scan_ch_$index',
      title: title,
      textContent: text,
      wordCount: _countWords(text),
      pageNumber: paras.first.pageNumber,
    );
  }

  // -------------------------------------------------------------------
  // C. Garde-fou de taille
  // -------------------------------------------------------------------

  /// Re-découpe les chapitres trop longs à la frontière de paragraphe.
  static List<Chapter> _enforceSizeLimit(List<Chapter> chapters) {
    final out = <Chapter>[];

    for (final chapter in chapters) {
      if (chapter.textContent.length <= maxChapterChars) {
        out.add(_reindex(chapter, out.length, chapter.title));
        continue;
      }

      final parts = _splitOnParagraphs(chapter.textContent);
      for (var i = 0; i < parts.length; i++) {
        out.add(Chapter(
          id: 'scan_ch_${out.length}',
          title: '${chapter.title} (${i + 1}/${parts.length})',
          textContent: parts[i],
          wordCount: _countWords(parts[i]),
          pageNumber: chapter.pageNumber,
        ));
      }
    }
    return out;
  }

  static Chapter _reindex(Chapter c, int index, String title) => Chapter(
        id: 'scan_ch_$index',
        title: title,
        textContent: c.textContent,
        wordCount: c.wordCount,
        pageNumber: c.pageNumber,
      );

  static List<String> _splitOnParagraphs(String text) {
    final paras = text.split('\n\n');
    final parts = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) parts.add(s);
      buffer.clear();
    }

    for (final para in paras) {
      // Un paragraphe seul plus long que la limite : on descend aux phrases.
      if (para.length > maxChapterChars) {
        flush();
        parts.addAll(_splitOnSentences(para));
        continue;
      }
      if (buffer.length + para.length + 2 > maxChapterChars) flush();
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(para);
    }
    flush();

    return parts.isEmpty ? [text] : parts;
  }

  static List<String> _splitOnSentences(String para) {
    final sentences = para.split(RegExp(r'(?<=[.!?…])\s+'));
    final parts = <String>[];
    final buffer = StringBuffer();

    for (final sentence in sentences) {
      if (buffer.isNotEmpty &&
          buffer.length + sentence.length + 1 > maxChapterChars) {
        parts.add(buffer.toString().trim());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString().trim());

    return parts;
  }

  static int _countWords(String text) {
    final t = text.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }
}
