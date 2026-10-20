import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter, 🔁 ticket U12a (mise en page du Blade) — écran de saisie journalière des lapins.
///
/// Les comportements sont vérifiés à l'écran plutôt que dans le dépôt, parce que c'est là qu'ils peuvent se perdre :
/// le champ « Ventes » reste inaccessible à la saisie, l'effectif, la provende et le poids moyen se recalculent à
/// chaque geste.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;

  const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bande,
            code: 'CUN-2026-01',
            speciesId: 'esp-0000-0000-0000-0000-000000000001',
            speciesCode: const Value('cuniculture'),
            initialQuantity: const Value(40),
            currentQuantity: const Value(40),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FicheLapinsScreen(
          depot: depot,
          soins: SoinsRepository(database: db, deviceId: 'poste-test'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;

  Future<void> toucher(WidgetTester tester, String cle) async {
    await tester.ensureVisible(find.byKey(Key(cle)));
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
  }

  testWidgets('l effectif de depart de la bande est affiche', (tester) async {
    await afficher(tester);

    expect(texte(tester, 'effectif-final'), '40');
  });

  /// ⚠️ « VENTES » VIENT DE LA CAISSE : une valeur affichée, aucun champ de saisie (`readonly` du Blade).
  testWidgets('le champ Ventes reste en lecture seule', (tester) async {
    await afficher(tester);

    expect(texte(tester, 'champ-ventes'), '0');
    expect(
      find.descendant(of: find.byKey(const Key('champ-ventes')), matching: find.byType(TextField)),
      findsNothing,
    );
    expect(find.text('(POS, réel)'), findsOneWidget);
  });

  /// L'effectif se recalcule sans enregistrement, comme au web (`wire:model.live`).
  testWidgets('un mort saisi diminue l effectif a l ecran', (tester) async {
    await afficher(tester);

    await toucher(tester, 'pas-mort-repro-1');

    expect(texte(tester, 'effectif-final'), '39');
  });

  /// D9 (`getAvertissementMortsProperty`) : des morts supérieurs à la veille ne bloquent pas — l'effectif est ramené
  /// à 0 et l'écran le dit, mot pour mot comme le web.
  testWidgets('D9 — morts supérieurs à la veille : plancher à 0 et avertissement du web', (tester) async {
    await afficher(tester);

    final champ = find.byKey(const Key('compteur-mort-repro'));
    await tester.ensureVisible(champ);
    await tester.enterText(champ, '45');
    await tester.pumpAndSettle();

    expect(texte(tester, 'effectif-final'), '0');
    expect(
      find.text(
        "Morts du jour (45) supérieurs à l'effectif de la veille (40) : l'effectif est ramené à 0, vérifiez la saisie.",
      ),
      findsOneWidget,
    );
  });

  /// ⚠️ Le compteur ne descend pas sous zéro (`max(0, … - 1)` du Blade).
  testWidgets('le compteur ne passe jamais sous zero', (tester) async {
    await afficher(tester);

    await toucher(tester, 'pas-mort-repro--1');

    expect(texte(tester, 'effectif-final'), '40', reason: 'aucun mort negatif ne doit gonfler l effectif');
  });

  testWidgets('enregistrer met la journee en file de synchronisation', (tester) async {
    await afficher(tester);

    await toucher(tester, 'pas-mort-repro-1');
    await toucher(tester, 'bouton-enregistrer');

    expect(await db.pendingCount(), 1);

    final fiche = await depot.chargerJour(bande, HeureBenin.maintenant());
    expect(fiche!.mort, 1);
    expect(fiche.mortRepro, 1);
    expect(fiche.effectifFinal, 39);
    expect(find.text('Jour enregistré avec succès.'), findsOneWidget);
    // Le toast se retire après 3,5 s.
    await tester.pump(const Duration(seconds: 4));
  });

  /// Sans barème synchronisé, le web retombe sur les rations de SECOURS du serveur (`RATIONS_DE_SECOURS`), et le
  /// poste aussi ; une bande sans stade laisse ses catégories inconnues (« — »), jamais 0.
  testWidgets('sans barème, les rations de secours ; sans stade, « — »', (tester) async {
    await afficher(tester);

    expect(find.text('120 g/j'), findsOneWidget);
    expect(find.text('60 g/j'), findsOneWidget);
    expect(find.text('30 g/j'), findsOneWidget);
    expect(texte(tester, 'total-provende'), '—');
  });

  /// Le total est calculé sur la ration descendue du serveur, en grammes ET en kilos (`round(total / 1000, 2)`).
  testWidgets('la provende totale suit la ration du referentiel', (tester) async {
    await db
        .into(db.feedRationStandards)
        .insert(
          FeedRationStandardsCompanion.insert(
            id: '11111111-2222-4333-8444-555555555555',
            speciesCode: 'cuniculture',
            stageLabel: 'engraissement',
            rationGPerDay: 60,
          ),
        );
    await (db.update(db.livestockLots)..where((t) => t.id.equals(bande))).write(
      const LivestockLotsCompanion(stage: Value('engraissement')),
    );

    await afficher(tester);

    // 40 sujets × 60 g = 2 400 g, soit 2.4 Kg.
    expect(texte(tester, 'total-provende'), '2400 g (2.4 Kg)');
  });

  /// La provende suit l'effectif en direct : un mort Jeune de plus, 60 g de moins.
  testWidgets('un mort saisi reduit aussitot la provende', (tester) async {
    await db
        .into(db.feedRationStandards)
        .insert(
          FeedRationStandardsCompanion.insert(
            id: '11111111-2222-4333-8444-555555555555',
            speciesCode: 'cuniculture',
            stageLabel: 'engraissement',
            rationGPerDay: 60,
          ),
        );
    await (db.update(db.livestockLots)..where((t) => t.id.equals(bande))).write(
      const LivestockLotsCompanion(stage: Value('engraissement')),
    );

    await afficher(tester);
    await toucher(tester, 'pas-mort-jeune-1');

    expect(texte(tester, 'total-provende'), '2340 g (2.34 Kg)');
  });

  /// ⚠️ Tant que rien n'est pesé, le poids moyen affiche « — » et non « 0 g ».
  testWidgets('sans pesee, le poids moyen affiche un tiret', (tester) async {
    await afficher(tester);

    expect(texte(tester, 'champ-poids-moyen'), '—');
    expect(texte(tester, 'champ-taille-echantillon'), '40', reason: 'la taille d echantillon suit l effectif final');
  });

  /// La pesée se convertit en direct : `round(pesée ÷ effectif final).' g'`.
  testWidgets('le poids moyen se calcule a la saisie', (tester) async {
    await afficher(tester);

    await tester.ensureVisible(find.byKey(const Key('champ-pesee')));
    await tester.enterText(find.byKey(const Key('champ-pesee')), '3500');
    await tester.pumpAndSettle();

    // 3 500 g répartis sur 40 sujets = 87,5 → 88 g.
    expect(texte(tester, 'champ-poids-moyen'), '88 g');
  });

  /// ⚠️ LE DIVISEUR SUIT L'EFFECTIF : saisir un mort change le poids moyen.
  testWidgets('un mort saisi change aussitot le poids moyen', (tester) async {
    await afficher(tester);

    await tester.ensureVisible(find.byKey(const Key('champ-pesee')));
    await tester.enterText(find.byKey(const Key('champ-pesee')), '3900');
    await tester.pumpAndSettle();
    expect(texte(tester, 'champ-poids-moyen'), '98 g');

    await toucher(tester, 'pas-mort-repro-1');

    // 3 900 g sur 39 sujets.
    expect(texte(tester, 'champ-poids-moyen'), '100 g');
  });

  /// Sans bande, la carte du Blade : « Aucune bande active en cuniculture pour le moment. » et son lien.
  testWidgets('sans bande, la carte du Blade', (tester) async {
    await db.delete(db.livestockLots).go();

    await afficher(tester);

    expect(find.text('Aucune bande active en cuniculture pour le moment.'), findsOneWidget);
    expect(find.text('Créer une bande depuis Bandes & Sujets →'), findsOneWidget);
    expect(find.byKey(const Key('bouton-enregistrer')), findsNothing);
  });
}
