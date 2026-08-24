import 'package:flutter_test/flutter_test.dart';
import 'package:speechify/services/scan_to_book_service.dart';

/// Le reste du flux de scan (caméra, OCR, redressement) se vérifie sur
/// l'appareil. La structuration du texte, elle, est du Dart pur : c'est la
/// partie qui mérite un test, et celle qui casse le plus discrètement.
void main() {
  group('nettoyage du texte OCR', () {
    test('recolle les mots coupés par une césure', () {
      final chapters = ScanToBookService.buildChapters([
        'Il trouvait la chose impos-\nsible à croire, et pour-\ntant elle advint.',
      ]);
      expect(chapters.single.textContent, contains('impossible'));
      expect(chapters.single.textContent, contains('pourtant'));
      expect(chapters.single.textContent, isNot(contains('-')));
    });

    test('préserve un tiret cadratin de pause en fin de ligne', () {
      final chapters = ScanToBookService.buildChapters([
        'Il allait répondre—\nQuand la porte claqua.',
      ]);
      final text = chapters.single.textContent;
      expect(text, contains('répondre—'));
      expect(text, contains('Quand la porte'));
      expect(text, isNot(contains('répondreQuand')));
    });

    test('préserve un tiret demi-cadratin de pause en fin de ligne', () {
      final chapters = ScanToBookService.buildChapters([
        'Elle hésita, puis reprit–\nMais il était trop tard.',
      ]);
      final text = chapters.single.textContent;
      expect(text, contains('reprit–'));
      expect(text, contains('Mais il'));
      expect(text, isNot(contains('repritMais')));
    });

    test('recolle quand même une vraie césure suivie d\'une minuscule après un tiret court', () {
      final chapters = ScanToBookService.buildChapters([
        'Le mot inconnu semblait presque impos-\nsible à prononcer.',
      ]);
      expect(chapters.single.textContent, contains('impossible'));
    });

    test('recolle les fins de ligne à l\'intérieur d\'un paragraphe', () {
      final chapters = ScanToBookService.buildChapters([
        'Le vent se levait\nsur la plaine\ndéserte.',
      ]);
      expect(chapters.single.textContent, 'Le vent se levait sur la plaine déserte.');
    });

    test('supprime les numéros de page en pied', () {
      final chapters = ScanToBookService.buildChapters([
        'Première page de texte.\n\n12',
        'Deuxième page de texte.\n\n13',
        'Troisième page de texte.\n\n14',
      ]);
      final text = chapters.map((c) => c.textContent).join(' ');
      expect(text, isNot(contains('12')));
      expect(text, isNot(contains('13')));
      expect(text, contains('Première page'));
      expect(text, contains('Troisième page'));
    });

    test('supprime un titre courant répété', () {
      final chapters = ScanToBookService.buildChapters([
        'Les Misérables\n\nCorps du texte un.',
        'Les Misérables\n\nCorps du texte deux.',
        'Les Misérables\n\nCorps du texte trois.',
      ]);
      final text = chapters.map((c) => c.textContent).join(' ');
      expect(text, isNot(contains('Misérables')));
      expect(text, contains('Corps du texte deux.'));
    });
  });

  group('découpage en chapitres', () {
    test('détecte les titres de chapitre', () {
      final chapters = ScanToBookService.buildChapters([
        'Chapitre premier\n\nIl était une fois un roi.',
        'Chapitre second\n\nLe roi avait une fille.',
      ]);
      expect(chapters, hasLength(2));
      expect(chapters[0].title, 'Chapitre premier');
      expect(chapters[1].title, 'Chapitre second');
      expect(chapters[0].textContent, 'Il était une fois un roi.');
      // Le titre ne doit pas être relu dans le corps.
      expect(chapters[1].textContent, isNot(contains('Chapitre')));
    });

    test('retombe sur un découpage par pages sans titre détecté', () {
      final pages = List.generate(6, (i) => 'Contenu ordinaire de la page $i.');
      final chapters = ScanToBookService.buildChapters(pages);
      expect(chapters, isNotEmpty);
      expect(chapters.first.title, startsWith('Page'));
    });

    test('renseigne wordCount et pageNumber', () {
      final chapters = ScanToBookService.buildChapters(['un deux trois']);
      expect(chapters.single.wordCount, 3);
      expect(chapters.single.pageNumber, 1);
    });

    test('rend une liste vide sur une entrée vide', () {
      expect(ScanToBookService.buildChapters(['', '   ']), isEmpty);
      expect(ScanToBookService.buildChapters([]), isEmpty);
    });
  });

  group('garde-fou de taille', () {
    // reader_screen tronque à 4500 caractères : aucun chapitre ne doit
    // s'en approcher, sinon la synthèse perd du texte sans rien dire.
    test('découpe un chapitre trop long sur les paragraphes', () {
      final para = '${'Une phrase de remplissage. ' * 20}\n\n';
      final chapters = ScanToBookService.buildChapters([para * 15]);

      expect(chapters.length, greaterThan(1));
      for (final c in chapters) {
        expect(c.textContent.length,
            lessThanOrEqualTo(ScanToBookService.maxChapterChars));
      }
      expect(chapters.first.title, contains('(1/'));
    });

    test('découpe sur les phrases un paragraphe unique trop long', () {
      final huge = 'Phrase courte. ' * 500; // un seul bloc, ~7500 caractères
      final chapters = ScanToBookService.buildChapters([huge]);

      for (final c in chapters) {
        expect(c.textContent.length,
            lessThanOrEqualTo(ScanToBookService.maxChapterChars));
      }
    });

    test('les identifiants de chapitre restent uniques', () {
      final para = '${'Du texte de remplissage. ' * 20}\n\n';
      final chapters = ScanToBookService.buildChapters([para * 15]);
      final ids = chapters.map((c) => c.id).toSet();
      expect(ids, hasLength(chapters.length));
    });
  });
}
