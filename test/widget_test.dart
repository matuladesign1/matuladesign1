// Tests unitaires : construction des requêtes de recherche et analyse des PDF.
import 'package:flutter_test/flutter_test.dart';
import 'package:sermons_branham_matomate/data/import_service.dart';
import 'package:sermons_branham_matomate/data/models.dart';
import 'package:sermons_branham_matomate/data/search_service.dart';

void main() {
  group('Requêtes de recherche', () {
    test('Mots : chaque mot est requis, ordre libre', () {
      expect(SearchService.buildMatch('colombe agneau', SearchMode.words), '"colombe" "agneau"');
    });
    test('Mots en cours de saisie : dernier mot en préfixe', () {
      expect(SearchService.buildMatch('colombe agn', SearchMode.words, prefixLast: true), '"colombe" "agn"*');
    });
    test('Exacte : expression entière, accents et apostrophes neutralisés', () {
      expect(SearchService.buildMatch('le temps de la fin', SearchMode.exact), '"le temps de la fin"');
      expect(SearchService.buildMatch("l'Agneau", SearchMode.exact), '"l agneau"');
      expect(SearchService.buildMatch('Ténèbres', SearchMode.exact), '"tenebres"');
    });
    test('Sens : mots vides retirés, termes apparentés ajoutés', () {
      final m = SearchService.buildMatch('Le retour de Jésus-Christ', SearchMode.meaning)!;
      expect(m.contains('"retour"*'), isTrue);
      expect(m.contains('"venue"*'), isTrue);
      expect(m.contains('"le"'), isFalse);
      expect(m.contains(' OR '), isTrue);
    });
    test('Requête vide', () {
      expect(SearchService.buildMatch('  ,; ', SearchMode.words), isNull);
    });
    test('Caractères spéciaux FTS neutralisés', () {
      expect(SearchService.buildMatch('foi" OR *', SearchMode.words), '"foi" "or"');
    });
  });

  group('Analyse des PDF de sermons', () {
    const sample = '''
DOCUMENT DE TEST
Ville Exemple, Indiana, USA

1 Premier paragraphe de test qui se poursuit
sur une deuxième ligne.
2 Deuxième paragraphe avec un mot coupé en fin de ligne au-
tomatiquement.

7
3 Troisième paragraphe.
''';

    test('code, date, titre, lieu, paragraphes', () {
      final s = SermonParser.parse('FRN47-0412 Document De Test VGR.pdf', sample);
      expect(s.code, '47-0412');
      expect(s.date, '1947-04-12');
      expect(s.year, 1947);
      expect(s.title, 'Document De Test');
      expect(s.location, 'Ville Exemple, Indiana, USA');
      expect(s.paragraphs.length, 3);
      expect(s.paragraphs[0].$2, 'Premier paragraphe de test qui se poursuit sur une deuxième ligne.');
      expect(s.paragraphs[1].$2.contains('automatiquement'), isTrue);
      expect(s.paragraphs[2].$1, 3);
      expect(s.notes, isEmpty);
    });

    test('suffixe de code (matin/soir)', () {
      expect(SermonParser.parseCode('65-1127B La maison').$1, '65-1127B');
      expect(SermonParser.parseCode('Aucun code ici').$1, isNull);
    });

    test('document sans code : signalé, jamais inventé', () {
      final s = SermonParser.parse('fichier.pdf', '1 Texte.\n2 Suite.');
      expect(s.code.startsWith('SANS-CODE-'), isTrue);
      expect(s.notes, contains('code officiel introuvable'));
    });

    test('détection de la langue', () {
      final fr = List.filled(30, 'le Seigneur est dans la maison et nous').join(' ');
      final ln = List.filled(30, 'Nzambe azali na bato mpe biso oyo').join(' ');
      expect(SermonParser.detectLanguage(fr), 'fr');
      expect(SermonParser.detectLanguage(ln), 'ln');
    });
  });
}
