import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/chapter.dart';
import 'scan_to_book_service.dart';

/// Erreur levée quand une URL ne peut pas être transformée en livre.
class UrlImportException implements Exception {
  UrlImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Récupère une page web et la transforme en livre écoutable.
///
/// Ne fait qu'une requête HTTP simple (pas de rendu JS) : fonctionne bien
/// pour des articles/blogs classiques, pas pour un site qui charge son
/// contenu en JavaScript ou le cache derrière un paywall.
class UrlToBookService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        // Certains serveurs renvoient une page d'erreur/différente sans
        // user-agent de type navigateur.
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      },
      followRedirects: true,
      validateStatus: (status) => status != null && status < 400,
    ),
  );

  static final _tagsToDrop = {
    'script', 'style', 'nav', 'header', 'footer', 'aside', 'form',
    'iframe', 'noscript', 'svg', 'button', 'figcaption',
  };

  /// Récupère [rawUrl], en extrait le titre et le texte principal, et
  /// renvoie les chapitres prêts à être enregistrés dans un [Ebook].
  static Future<UrlArticle> fetch(String rawUrl) async {
    final uri = _normalizeUrl(rawUrl);

    late Response<String> response;
    try {
      response = await _dio.get<String>(uri.toString());
    } on DioException catch (e) {
      throw UrlImportException(_messageFor(e));
    }

    final body = response.data;
    if (body == null || body.trim().isEmpty) {
      throw UrlImportException('La page ne contient aucun contenu.');
    }

    final document = html_parser.parse(body);
    final title = _extractTitle(document, uri);
    final continuationUrl = _findContinuationLink(document, uri);
    final pageText = _extractReadableText(_cleanedBody(document));

    if (pageText.trim().length < 200) {
      throw UrlImportException(
        "Impossible d'extraire assez de texte de cette page "
        "(contenu généré par JavaScript ou protégé par un paywall ?).",
      );
    }

    final chapters = ScanToBookService.buildChapters([pageText]);
    return UrlArticle(
      title: title,
      sourceUrl: uri.toString(),
      chapters: chapters,
      continuationUrl: continuationUrl,
    );
  }

  static final _continuationKeyword =
      RegExp(r'\b(suivant\w*|suite|next)\b', caseSensitive: false);

  /// Beaucoup de listes/articles longs sont coupés sur plusieurs pages
  /// (« 25 sélections suivantes », « page suivante »…) : on cherche un vrai
  /// lien `<a href>` de continuation, sur le même site, pour pouvoir le
  /// proposer à l'utilisateur plutôt que de silencieusement tronquer.
  static String? _findContinuationLink(Document document, Uri baseUri) {
    for (final a in document.querySelectorAll('a[href]')) {
      final text = a.text.trim();
      if (text.isEmpty || text.length > 80) continue;
      if (!_continuationKeyword.hasMatch(text)) continue;

      final href = a.attributes['href'];
      if (href == null || href.isEmpty) continue;

      Uri resolved;
      try {
        resolved = baseUri.resolve(href);
      } catch (_) {
        continue;
      }
      if (resolved.host != baseUri.host) continue;
      if (resolved.toString() == baseUri.toString()) continue;

      return resolved.toString();
    }
    return null;
  }

  static Uri _normalizeUrl(String rawUrl) {
    var trimmed = rawUrl.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      throw UrlImportException('Adresse invalide : "$rawUrl".');
    }
    return uri;
  }

  static String _messageFor(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return "La page a mis trop de temps à répondre.";
      case DioExceptionType.connectionError:
        return "Impossible de joindre cette adresse. Vérifiez le lien et votre connexion.";
      default:
        final status = e.response?.statusCode;
        return status != null
            ? "La page a répondu avec une erreur ($status)."
            : "Impossible de récupérer cette page.";
    }
  }

  /// Titre : balise `<title>`, sinon le premier `<h1>`, sinon le nom d'hôte.
  static String _extractTitle(Document document, Uri fallbackUri) {
    final titleTag = document.querySelector('title')?.text.trim();
    if (titleTag != null && titleTag.isNotEmpty) {
      // Beaucoup de sites suffixent " | Nom du site" ou " - Nom du site" :
      // on ne garde que la première partie, plus lisible comme titre de livre.
      return titleTag.split(RegExp(r'\s*[\|–—-]\s*')).first.trim();
    }
    final h1 = document.querySelector('h1')?.text.trim();
    if (h1 != null && h1.isNotEmpty) return h1;
    return fallbackUri.host;
  }

  static const _inlineTags = {
    'a', 'span', 'b', 'i', 'em', 'strong', 'sub', 'sup', 'br', 'u', 'small', 'mark',
  };

  /// Retire menus/pubs/scripts structurellement identifiables, puis renvoie
  /// tout le corps de la page.
  ///
  /// Une première version essayait de deviner LE conteneur principal de
  /// l'article (comme le fait un lecteur "mode lecture"). Ça perd du
  /// contenu sur les sites construits avec des composants (Wix,
  /// Squarespace…) : une longue liste peut être répartie sur plusieurs
  /// widgets indépendants, imbriqués si profondément qu'aucun ancêtre commun
  /// raisonnable ne les regroupe. Comme on a déjà retiré la navigation, les
  /// scripts et le pied de page, prendre tout le corps restant perd
  /// beaucoup moins de contenu qu'une mauvaise devinette — au prix d'un peu
  /// de texte promotionnel qui peut s'y glisser.
  static Element _cleanedBody(Document document) {
    for (final tag in _tagsToDrop) {
      for (final el in document.querySelectorAll(tag)) {
        el.remove();
      }
    }
    return document.body ?? document.documentElement!;
  }

  /// Descend récursivement jusqu'aux éléments qui portent effectivement du
  /// texte : soit une feuille (aucun enfant élément), soit un élément dont
  /// tous les enfants sont des balises en ligne (`<span>`, `<a>`…), qu'on
  /// traite comme un seul bloc plutôt que de fragmenter son texte.
  static List<Element> _collectTextLeaves(Element root) {
    final leaves = <Element>[];

    void visit(Element el) {
      final children = el.children;
      if (children.isEmpty) {
        if (el.text.trim().isNotEmpty) leaves.add(el);
        return;
      }
      final onlyInline = children.every((c) => _inlineTags.contains(c.localName));
      if (onlyInline && el.text.trim().isNotEmpty) {
        leaves.add(el);
        return;
      }
      for (final child in children) {
        visit(child);
      }
    }

    visit(root);
    return leaves;
  }

  /// Concatène le texte de chaque bloc du conteneur choisi, dans l'ordre du
  /// document, séparés par une ligne vide (le format attendu par
  /// `ScanToBookService.buildChapters`).
  static String _extractReadableText(Element container) {
    final blocks = <String>[];
    for (final leaf in _collectTextLeaves(container)) {
      final text = leaf.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      blocks.add(text);
    }
    return blocks.join('\n\n');
  }
}

/// Résultat de l'extraction : de quoi construire un [Ebook] directement.
class UrlArticle {
  UrlArticle({
    required this.title,
    required this.sourceUrl,
    required this.chapters,
    this.continuationUrl,
  });

  final String title;
  final String sourceUrl;
  final List<Chapter> chapters;

  /// Lien vers une éventuelle page suivante détectée sur la page source
  /// (contenu réparti sur plusieurs pages), ou `null` si aucune trouvée.
  final String? continuationUrl;
}

/// Combine plusieurs articles récupérés séparément en une seule liste de
/// chapitres, dans l'ordre où ils ont été ajoutés — le premier article
/// devient le tout début du livre, le dernier la fin.
List<Chapter> mergeUrlArticles(List<UrlArticle> articles) {
  final merged = <Chapter>[];

  for (final article in articles) {
    for (var i = 0; i < article.chapters.length; i++) {
      final chapter = article.chapters[i];
      // Un seul chapitre pour cette source : son titre devient celui de
      // l'article, pour qu'on sache d'où vient chaque section à l'écoute.
      // Plusieurs chapitres : on garde le titre détecté, préfixé par
      // l'article d'origine.
      final title = article.chapters.length == 1
          ? article.title
          : '${article.title} — ${chapter.title}';

      merged.add(Chapter(
        id: 'url_ch_${merged.length}',
        title: title,
        textContent: chapter.textContent,
        wordCount: chapter.wordCount,
        pageNumber: merged.length + 1,
      ));
    }
  }

  return merged;
}
