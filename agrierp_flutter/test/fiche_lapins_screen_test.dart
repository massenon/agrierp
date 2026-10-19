import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — écran de saisie journalière.
///
/// Deux comportements sont vérifiés à l'écran plutôt que dans le dépôt, parce
/// que c'est là qu'ils peuvent se perdre : le champ « Ventes » doit rester
/// inaccessible à la saisie, et l'effectif doit se recalculer à chaque geste.
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

  testWidgets('l effectif de depart de la bande est affiche', (tester) async {
    await afficher(tester);

    expect(find.byKey(const Key('effectif-final')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('effectif-final'))).data,
      '40',
    );
  });

  /// ⚠️ « VENTES » VIENT DE LA CAISSE : le champ doit rester en lecture seule.
  /// Le rendre saisissable ouvrirait deux sources pour un même chiffre.
  testWidgets('le champ Ventes reste en lecture seule', (tester) async {
    await afficher(tester);

    final champ = tester.widget<TextFormField>(
      find.byKey(const Key('champ-vente-0')),
    );

    expect(champ.initialValue, '0');

    // ⚠️ L'ASSERTION PORTE SUR LE CHAMP LUI-MEME, pas sur un decompte des
    // champs saisissables : ce decompte cassait des qu'une section etait
    // ajoutee a l'ecran, sans que la propriete verifiee change.
    final verrouille = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('champ-vente-0')),
        matching: find.byType(TextField),
      ),
    );

    expect(verrouille.readOnly, isTrue);
    expect(find.text('Alimenté par la caisse'), findsOneWidget);
  });

  /// L'effectif se recalcule sans enregistrement, comme dans la maquette.
  testWidgets('un mort saisi diminue l effectif a l ecran', (tester) async {
    await afficher(tester);

    // Un pas « + » sur la catégorie Reproducteur des morts.
    await tester.ensureVisible(
      find.byKey(Key('pas-${'Reproducteur'.hashCode}-1')).first,
    );
    await tester.tap(find.byKey(Key('pas-${'Reproducteur'.hashCode}-1')).first);
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('effectif-final'))).data,
      '39',
    );
  });

  /// ⚠️ Le compteur ne descend pas sous zéro : un nombre de morts négatif
  /// gonflerait l'effectif au lieu de le réduire.
  testWidgets('le compteur ne passe jamais sous zero', (tester) async {
    await afficher(tester);

    await tester.ensureVisible(
      find.byKey(Key('pas-${'Reproducteur'.hashCode}--1')).first,
    );
    await tester.tap(
      find.byKey(Key('pas-${'Reproducteur'.hashCode}--1')).first,
    );
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('effectif-final'))).data,
      '40',
      reason: 'aucun mort negatif ne doit gonfler l effectif',
    );
  });

  testWidgets('enregistrer met la journee en file de synchronisation', (
    tester,
  ) async {
    await afficher(tester);

    await tester.ensureVisible(
      find.byKey(Key('pas-${'Reproducteur'.hashCode}-1')).first,
    );
    await tester.tap(find.byKey(Key('pas-${'Reproducteur'.hashCode}-1')).first);
    await tester.pump();

    // Le bouton est sous la ligne de flottaison du viewport de test : sans
    // ce defilement, le tap porte dans le vide et le test verifierait un
    // enregistrement qui n'a jamais eu lieu.
    await tester.ensureVisible(find.byKey(const Key('bouton-enregistrer')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('bouton-enregistrer')));
    await tester.tap(find.byKey(const Key('bouton-enregistrer')));
    await tester.pumpAndSettle();

    expect(await db.pendingCount(), 1);

    final fiche = await depot.chargerJour(bande, HeureBenin.maintenant());
    expect(fiche!.mort, 1);
    expect(fiche.effectifFinal, 39);
  });

  /// ⚠️ SANS RATIONS SYNCHRONISÉES, le tableau ne s'invente pas des
  /// grammages : il dit d'où ils viennent.
  testWidgets('sans rations, le tableau renvoie a la synchronisation', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.textContaining('Rationnement indisponible'), findsOneWidget);
  });

  /// Le total est calculé sur la ration descendue du serveur, et affiché en
  /// grammes ET en kilos comme dans la maquette.
  testWidgets('la provende totale suit la ration du referentiel', (
    tester,
  ) async {
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

    // 40 sujets x 60 g = 2 400 g, soit 2.4 Kg.
    expect(
      tester.widget<Text>(find.byKey(const Key('total-provende'))).data,
      '2400 g (2.4 Kg)',
    );
  });

  /// La provende suit l'effectif en direct : un mort de plus, 60 g de moins.
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

    await tester.ensureVisible(
      find.byKey(Key('pas-${'Jeune'.hashCode}-1')).first,
    );
    await tester.tap(find.byKey(Key('pas-${'Jeune'.hashCode}-1')).first);
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('total-provende'))).data,
      '2340 g (2.3 Kg)',
    );
  });

  /// ⚠️ Tant que rien n'est pesé, le poids moyen affiche « — » et non « 0 g ».
  testWidgets('sans pesee, le poids moyen affiche un tiret', (tester) async {
    await afficher(tester);

    expect(tester.widget<Text>(find.byKey(const Key('poids-moyen'))).data, '—');
    expect(
      tester.widget<Text>(find.byKey(const Key('taille-echantillon'))).data,
      '40',
      reason: 'la taille d echantillon suit l effectif final',
    );
  });

  /// La pesée se convertit en direct, comme dans la maquette.
  testWidgets('le poids moyen se calcule a la saisie', (tester) async {
    await afficher(tester);

    await tester.enterText(find.byKey(const Key('champ-pesee-0')), '3500');
    await tester.pumpAndSettle();

    // 3500 g repartis sur 40 sujets.
    expect(
      tester.widget<Text>(find.byKey(const Key('poids-moyen'))).data,
      '88 g',
    );
  });

  /// ⚠️ LE DIVISEUR SUIT L'EFFECTIF : saisir un mort change le poids moyen.
  /// Le figer ferait diverger l'affichage du calcul enregistré.
  testWidgets('un mort saisi change aussitot le poids moyen', (tester) async {
    await afficher(tester);

    await tester.enterText(find.byKey(const Key('champ-pesee-0')), '3900');
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('poids-moyen'))).data,
      '98 g',
    );

    await tester.ensureVisible(
      find.byKey(Key('pas-${'Reproducteur'.hashCode}-1')).first,
    );
    await tester.tap(find.byKey(Key('pas-${'Reproducteur'.hashCode}-1')).first);
    await tester.pumpAndSettle();

    // 3900 g sur 39 sujets.
    expect(
      tester.widget<Text>(find.byKey(const Key('poids-moyen'))).data,
      '100 g',
    );
  });

  /// Sans bande sur le poste, l'écran dit d'où elles viennent plutôt que
  /// d'afficher un formulaire vide inutilisable.
  testWidgets('sans bande, l ecran renvoie a la synchronisation', (
    tester,
  ) async {
    await db.delete(db.livestockLots).go();

    await afficher(tester);

    expect(find.textContaining('proviennent du serveur'), findsOneWidget);
  });
}
