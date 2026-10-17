import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/gestion_elevage_screen.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/elevage/transferts_bandes_screen.dart';
import 'package:agrierp/features/elevage/transferts_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

/// Ticket 15.46 — TRANSFERTS ENTRE BANDES SUR LE POSTE, miroir de `TransfertsEntreBandesTest` (PHP).
///
/// Mêmes scénarios, mêmes valeurs calculées À LA MAIN : le poste et le serveur doivent donner les
/// mêmes effectifs, sinon la synchronisation ferait changer les chiffres sous les yeux de l'éleveur.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository fiches;
  late TransfertsRepository depot;

  const especeLapins = 'esp-lapins-0000-0000-000000000001';
  const especePorcs = 'esp-porcs-00000-0000-000000000002';
  const mere = 'aaaaaaaa-0000-4000-8000-000000000001';
  const portee = 'aaaaaaaa-0000-4000-8000-000000000002';
  const a = 'bbbbbbbb-0000-4000-8000-000000000001';
  const b = 'bbbbbbbb-0000-4000-8000-000000000002';
  const porc = 'cccccccc-0000-4000-8000-000000000001';

  Future<void> bande(
    String id,
    String code,
    int initial,
    String stade,
    DateTime creation, {
    String espece = especeLapins,
    String codeEspece = 'cuniculture',
  }) => db
      .into(db.livestockLots)
      .insert(
        LivestockLotsCompanion.insert(
          id: id,
          code: code,
          speciesId: espece,
          speciesCode: Value(codeEspece),
          stage: Value(stade),
          initialQuantity: Value(initial),
          currentQuantity: Value(initial),
          createdDate: Value(creation),
        ),
      );

  /// Fiche posée puis passée par la cascade locale, comme la saisie l'aurait fait.
  Future<void> fiche(
    String lot,
    DateTime jour, {
    int ne = 0,
    int mort = 0,
    int? mortSevre,
    (int, int, int)? depart,
  }) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: const Uuid().v4(),
            deviceId: 'poste-test',
            updatedAt: DateTime.now(),
            lotId: lot,
            entryDate: jour,
            ne: Value(ne),
            mort: Value(mort),
            mortRepro: const Value(0),
            mortSevre: Value(mortSevre ?? 0),
            mortJeune: const Value(0),
            donRepro: const Value(0),
            donSevre: const Value(0),
            donJeune: const Value(0),
            passageSevreJeune: const Value(0),
            catDepartRepro: Value(depart?.$1),
            catDepartSevre: Value(depart?.$2),
            catDepartJeune: Value(depart?.$3),
            syncStatus: const Value(SyncStatus.synced),
          ),
        );
    // Effectif du jour puis cascade, comme `enregistrer`.
    final f = (await fiches.chargerJour(lot, jour))!;
    final effectif = FicheJournaliereRepository.calculerEffectifFinal(
      effectifPrecedent: await fiches.effectifPrecedent(lot, jour),
      achat: f.achat,
      ne: f.ne,
      mort: f.mort,
      vente: f.vente,
      don: f.don,
    );
    await (db.update(db.livestockDailyEntries)..where((t) => t.id.equals(f.id)))
        .write(LivestockDailyEntriesCompanion(effectifFinal: Value(effectif)));
    await fiches.recalculerEnCascade(lot, jour);
  }

  Future<int> effectif(String lot) async => (await (db.select(
    db.livestockLots,
  )..where((t) => t.id.equals(lot))).getSingle()).currentQuantity;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fiches = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    depot = TransfertsRepository(database: db, deviceId: 'poste-test', fiches: fiches);
  });

  tearDown(() async => db.close());

  test('⚠️⚠️ rattacher une portée à sa bande mère supprime le double comptage (A2)', () async {
    await bande(mere, 'LAP-MERE', 10, 'reproduction', DateTime(2026, 9, 1));
    await fiche(mere, DateTime(2026, 9, 1), ne: 8, depart: (10, 0, 0));
    await bande(portee, 'LAP-PORTEE', 8, 'croissance', DateTime(2026, 9, 10));

    expect(await effectif(mere) + await effectif(portee), 26, reason: 'double comptage avant correction');
    expect((await depot.bandesARattacher()).map((l) => l.id), [portee]);

    final t = await depot.creer(
      sourceLotId: mere,
      targetLotId: portee,
      jour: DateTime(2026, 9, 10),
      quantite: 8,
      categorie: 'sevre',
      constitution: true,
    );

    expect(t.syncStatus, SyncStatus.pending);
    expect(await effectif(mere), 10);
    expect(await effectif(portee), 8);
    final jour = (await fiches.chargerJour(mere, DateTime(2026, 9, 10)))!;
    expect([jour.transfertSortie, jour.transfertSortieSevre], [8, 8]);
    expect([jour.catEffRepro, jour.catEffSevre, jour.catEffJeune], [10, 0, 0]);
    expect(jour.syncStatus, SyncStatus.pending, reason: 'la fiche créée pour le transfert part au serveur');
    expect(await fiches.chargerJour(portee, DateTime(2026, 9, 10)), isNull);
    expect(await depot.bandesARattacher(), isEmpty);
  });

  test('un transfert ordinaire suit la cascade, puis son annulation rétablit tout', () async {
    await bande(a, 'LAP-A', 20, 'croissance', DateTime(2026, 9, 1));
    await bande(b, 'LAP-B', 5, 'croissance', DateTime(2026, 9, 1));
    await fiche(a, DateTime(2026, 9, 1), depart: (0, 20, 0));
    await fiche(b, DateTime(2026, 9, 1), depart: (0, 5, 0));
    await fiche(b, DateTime(2026, 9, 8), mort: 1, mortSevre: 1);

    final t = await depot.creer(
      sourceLotId: a,
      targetLotId: b,
      jour: DateTime(2026, 9, 5),
      quantite: 6,
      categorie: 'sevre',
    );

    // A : 20 − 6 = 14. B : 5 + 6 = 11 le 05/09, puis 11 − 1 = 10 le 08/09.
    expect(await effectif(a), 14);
    expect(await effectif(b), 10);
    final b08 = (await fiches.chargerJour(b, DateTime(2026, 9, 8)))!;
    expect([b08.effectifFinal, b08.catEffSevre], [10, 10]);

    await depot.annuler(t.id);
    expect(await effectif(a), 20);
    expect(await effectif(b), 4);
    final annule = await (db.select(db.livestockTransfers)..where((x) => x.id.equals(t.id))).getSingle();
    expect([annule.isActive, annule.syncStatus], [false, SyncStatus.pending]);
  });

  test('ressaisir la fiche du jour de transfert garde le transfert dans l effectif', () async {
    await bande(a, 'LAP-A', 20, 'croissance', DateTime(2026, 9, 1));
    await bande(b, 'LAP-B', 5, 'croissance', DateTime(2026, 9, 1));
    await fiche(a, DateTime(2026, 9, 1), depart: (0, 20, 0));
    await depot.creer(sourceLotId: a, targetLotId: b, jour: DateTime(2026, 9, 5), quantite: 6, categorie: 'sevre');

    await fiches.enregistrer(lotId: b, jour: DateTime(2026, 9, 5), achat: 0, ne: 0, mort: 0, don: 0);

    expect(await effectif(b), 11);
  });

  test('un transfert qui rendrait la source négative un jour suivant est refusé', () async {
    await bande(a, 'LAP-A', 20, 'croissance', DateTime(2026, 9, 1));
    await bande(b, 'LAP-B', 5, 'croissance', DateTime(2026, 9, 1));
    await fiche(a, DateTime(2026, 9, 1), depart: (0, 20, 0));
    await fiche(a, DateTime(2026, 9, 10), mort: 8, mortSevre: 8);

    await expectLater(
      depot.creer(sourceLotId: a, targetLotId: b, jour: DateTime(2026, 9, 5), quantite: 13, categorie: 'sevre'),
      throwsA(
        isA<TransfertRefuse>().having(
          (e) => e.motif,
          'motif',
          contains('ne compte que 12 sujet(s) le 10/09/2026'),
        ),
      ),
    );
    expect(await db.select(db.livestockTransfers).get(), isEmpty);
    expect(await effectif(a), 12);
  });

  test('espèces différentes, date future, catégorie manquante : refusés', () async {
    await bande(a, 'LAP-A', 20, 'croissance', DateTime(2026, 9, 1));
    await bande(b, 'LAP-B', 5, 'croissance', DateTime(2026, 9, 1));
    await bande(porc, 'PORC-A', 5, 'croissance', DateTime(2026, 9, 1), espece: especePorcs, codeEspece: 'porciculture');

    for (final (cible, jour, categorie) in [
      (porc, DateTime(2026, 9, 5), 'sevre'),
      (b, DateTime.now().add(const Duration(days: 3)), 'sevre'),
      (b, DateTime(2026, 9, 5), null),
      (b, DateTime(2026, 8, 20), 'sevre'),
    ]) {
      await expectLater(
        depot.creer(sourceLotId: a, targetLotId: cible, jour: jour, quantite: 2, categorie: categorie),
        throwsA(isA<TransfertRefuse>()),
      );
    }
    expect(await db.select(db.livestockTransfers).get(), isEmpty);
  });

  testWidgets('l écran liste la bande à rattacher et affiche le refus en clair', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await bande(mere, 'LAP-MERE', 10, 'reproduction', DateTime(2026, 9, 1));
      await fiche(mere, DateTime(2026, 9, 1), depart: (10, 0, 0));
      await bande(portee, 'LAP-PORTEE', 8, 'croissance', DateTime(2026, 9, 10));
    });

    await tester.pumpWidget(MaterialApp(home: TransfertsBandesScreen(depot: depot)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Transferts entre Bandes'), findsOneWidget);
    expect(find.byKey(const Key('rattacher-$portee')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rattacher-$portee')));
    await tester.pumpAndSettle();
    expect(find.text("Rattacher une Bande à sa Bande d'Origine"), findsOneWidget);

    await tester.tap(find.byKey(const Key('transfert-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LAP-MERE (10)').last);
    await tester.pumpAndSettle();

    // Aucun Sous-mères dans la bande mère : le refus du dépôt s'affiche tel quel.
    await tester.runAsync(() async {
      await tester.tap(find.text('Rattacher'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transfert-erreur')), findsOneWidget);
    expect(find.textContaining('ne compte que 0 Sous-mères'), findsOneWidget);
  });

  testWidgets('le hub Gestion Élevage ouvre l écran des transferts', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    EcranPoste? ouvert;
    await tester.pumpWidget(
      MaterialApp(
        home: GestionElevageScreen(
          onOuvrir: (e) => ouvert = e,
          modules: ParametresGenerauxRepository(database: db),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('carte-${EcranPoste.transfertsBandes.name}')));
    expect(ouvert, EcranPoste.transfertsBandes);
    expect(PermissionsPoste.autorise('animalier', EcranPoste.transfertsBandes), isTrue);
    expect(PermissionsPoste.autorise('caissier', EcranPoste.transfertsBandes), isFalse);
  });
}
