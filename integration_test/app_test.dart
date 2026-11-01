// Test sur appareil/émulateur : démarrage, Bible, recherche plein texte, notes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sermons_branham_matomate/data/db.dart';
import 'package:sermons_branham_matomate/data/models.dart';
import 'package:sermons_branham_matomate/data/search_service.dart';
import 'package:sermons_branham_matomate/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('parcours principal', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Accueil
    expect(find.text('Accueil'), findsWidgets);
    expect(find.textContaining('Bonjour'), findsOneWidget);

    // Base biblique complète
    final adb = AppDb.I;
    expect(adb.books().length, 66);
    expect(adb.db.select('SELECT count(*) c FROM bible.verses').first['c'], 31102);
    expect(adb.chapter('LSG', 43, 1).first.text, startsWith('Au commencement était la Parole'));

    // Recherche plein texte insensible aux accents
    final search = SearchService(adb);
    final page = search.search('tenebres lumiere', SearchMode.words);
    expect(page.total, greaterThan(0));
    expect(page.hits.first.kind, HitKind.bible);
    final typo = search.search('agneu', SearchMode.words);
    expect(typo.total, 0);
    expect(typo.suggestion, isNotNull);

    // Onglet Bible
    await tester.tap(find.text('Bible').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Jean 1'), findsWidgets);

    // Onglet Chercher
    await tester.tap(find.text('Chercher').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'colombe');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('résultat'), findsWidgets);

    // Onglet Plans
    await tester.tap(find.text('Plans').last);
    await tester.pumpAndSettle();
    expect(find.text('Lire toute la Bible en un an'), findsOneWidget);
  });
}
