import 'dart:async';

import 'package:agrierp/core/demarrage/demarrage_poste.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Une panne AU LANCEMENT se voit : la fenêtre du poste n'est montrée qu'à la première image, donc une exception (ou une
/// attente sans fin) avant `runApp` laissait `agrierp.exe` fantôme en arrière-plan, sans rien d'ouvert.
void main() {
  const normal = SizedBox(key: Key('application'));

  test('tout va bien : l\'application est rendue telle quelle, rien n\'est journalisé', () async {
    final journal = <String>[];

    final w = await DemarragePoste.preparer(
      construire: () async => normal,
      journaliser: (t) async {
        journal.add(t);
        return 'x.log';
      },
    );

    expect(w, same(normal));
    expect(journal, isEmpty);
  });

  testWidgets('⚠️ une exception au démarrage donne un ÉCRAN et un journal, pas un processus fantôme', (tester) async {
    final journal = <String>[];

    final w = await DemarragePoste.preparer(
      construire: () async => throw StateError('migration impossible'),
      journaliser: (t) async {
        journal.add(t);
        return r'C:\Users\x\AppData\Roaming\agrierp\demarrage.log';
      },
    );

    expect(w, isA<EcranDemarrageImpossible>());
    expect(journal.single, contains('migration impossible'));

    await tester.pumpWidget(w);
    expect(find.byKey(const Key('demarrage-titre')), findsOneWidget);
    expect(find.textContaining('migration impossible'), findsOneWidget);
    expect(find.textContaining('demarrage.log'), findsOneWidget);
    expect(find.byKey(const Key('demarrage-quitter')), findsOneWidget);
  });

  testWidgets('⚠️ une préparation qui ne finit jamais est tenue pour bloquée et le dit', (tester) async {
    final journal = <String>[];

    // ⚠️ `runAsync` : le délai est un VRAI minuteur ; dans l'horloge simulée du test il ne s'écoulerait jamais.
    final w = await tester.runAsync(
      () => DemarragePoste.preparer(
        construire: () => Completer<Widget>().future,
        delai: const Duration(milliseconds: 20),
        journaliser: (t) async {
          journal.add(t);
          return null;
        },
      ),
    );

    expect(w, isA<EcranDemarrageImpossible>());
    expect(journal.single, contains('bloqué'));

    await tester.pumpWidget(w!);
    expect(tester.widget<Text>(find.byKey(const Key('demarrage-cause'))).data, contains('autre fenêtre LogiAgriERP'));
    // Journal illisible (disque, droits) : l'écran n'affiche pas de chemin et ne plante pas.
    expect(find.byKey(const Key('demarrage-journal')), findsNothing);
  });

  testWidgets('« Quitter » appelle la fermeture injectée', (tester) async {
    var ferme = false;
    await tester.pumpWidget(EcranDemarrageImpossible(cause: 'x', quitter: () => ferme = true));

    await tester.tap(find.byKey(const Key('demarrage-quitter')));

    expect(ferme, isTrue);
  });
}
