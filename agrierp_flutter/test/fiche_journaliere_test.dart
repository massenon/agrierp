import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masques ici pour
// laisser accessibles les matchers homonymes de `flutter_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — SAISIE JOURNALIÈRE DU CHEPTEL.
///
/// Les deux défauts que ces tests verrouillent ont RÉELLEMENT existé côté
/// serveur, et aucun ne levait d'erreur :
///   • la fiche se trouvait elle-même comme « jour précédent » et repartait de
///     son propre effectif — deux ventes le même jour donnaient −8 au lieu
///     de 35 ;
///   • l'enregistrement de la journée remettait `vente` à zéro, effaçant le
///     passage en caisse dès que l'éleveur sauvegardait.
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
            initialQuantity: const Value(40),
            currentQuantity: const Value(40),
          ),
        );
  });

  tearDown(() async => db.close());

  /// La formule affichée sous le champ calculé, appliquée telle quelle.
  test('la formule est celle du serveur', () {
    expect(
      FicheJournaliereRepository.calculerEffectifFinal(
        effectifPrecedent: 40,
        achat: 5,
        ne: 8,
        mort: 2,
        vente: 3,
        don: 1,
      ),
      47,
    );
  });

  /// Sans fiche antérieure, on repart de l'effectif INITIAL de la bande.
  test('sans historique, l effectif initial sert de base', () async {
    expect(await depot.effectifPrecedent(bande, DateTime(2026, 8, 18)), 40);
  });

  test('une premiere journee enregistree calcule son effectif', () async {
    final fiche = await depot.enregistrer(
      lotId: bande,
      jour: DateTime(2026, 8, 18),
      achat: 0,
      ne: 6,
      mort: 1,
      don: 0,
    );

    expect(fiche.effectifFinal, 45);
    expect(fiche.syncStatus, SyncStatus.pending);
    expect(await db.pendingCount(), 1);
  });

  /// ⚠️ LE DÉFAUT LE PLUS COÛTEUX. Enregistrer deux fois la même journée ne
  /// doit pas faire repartir le calcul de son propre résultat.
  test('reenregistrer la meme journee ne cumule pas sur soi-meme', () async {
    await depot.enregistrer(
      lotId: bande,
      jour: DateTime(2026, 8, 18),
      achat: 0,
      ne: 0,
      mort: 5,
      don: 0,
    );

    final seconde = await depot.enregistrer(
      lotId: bande,
      jour: DateTime(2026, 8, 18),
      achat: 0,
      ne: 0,
      mort: 5,
      don: 0,
    );

    expect(
      seconde.effectifFinal,
      35,
      reason: 'la fiche ne doit jamais se lire comme sa propre veille',
    );

    final lignes = await db.select(db.livestockDailyEntries).get();
    expect(lignes, hasLength(1), reason: 'upsert sur (bande, date)');
  });

  /// L'effectif de la veille vient bien de la fiche antérieure.
  test('le jour suivant repart de la veille', () async {
    await depot.enregistrer(
      lotId: bande,
      jour: DateTime(2026, 8, 17),
      achat: 0,
      ne: 0,
      mort: 4,
      don: 0,
    );

    expect(await depot.effectifPrecedent(bande, DateTime(2026, 8, 18)), 36);

    final suivante = await depot.enregistrer(
      lotId: bande,
      jour: DateTime(2026, 8, 18),
      achat: 0,
      ne: 2,
      mort: 0,
      don: 0,
    );

    expect(suivante.effectifFinal, 38);
  });

  /// ⚠️ L'HEURE NE DOIT RIEN CHANGER : une date porteuse d'une heure ferait
  /// passer la journée pour antérieure à elle-même.
  test(
    'une heure residuelle ne trompe pas la recherche de la veille',
    () async {
      await depot.enregistrer(
        lotId: bande,
        jour: DateTime(2026, 8, 18, 14, 30),
        achat: 0,
        ne: 0,
        mort: 5,
        don: 0,
      );

      final relue = await depot.chargerJour(bande, DateTime(2026, 8, 18));

      expect(relue, isNotNull);
      expect(relue!.effectifFinal, 35);
      expect(
        await depot.effectifPrecedent(bande, DateTime(2026, 8, 18, 23, 59)),
        40,
        reason: 'la journee elle-meme reste exclue',
      );
    },
  );

  /// ⚠️ LE SECOND DÉFAUT RÉEL : la vente de caisse ne doit pas être effacée
  /// par un enregistrement de la fiche.
  test(
    'l enregistrement n efface jamais la vente venue de la caisse',
    () async {
      await depot.enregistrer(
        lotId: bande,
        jour: DateTime(2026, 8, 18),
        achat: 0,
        ne: 0,
        mort: 0,
        don: 0,
      );

      // La caisse inscrit 6 sujets vendus sur la journée.
      await (db.update(db.livestockDailyEntries)
            ..where((t) => t.lotId.equals(bande)))
          .write(const LivestockDailyEntriesCompanion(vente: Value(6)));

      final apres = await depot.enregistrer(
        lotId: bande,
        jour: DateTime(2026, 8, 18),
        achat: 0,
        ne: 0,
        mort: 1,
        don: 0,
      );

      expect(
        apres.vente,
        6,
        reason: 'la vente est relue, jamais supposee nulle',
      );
      expect(apres.effectifFinal, 33, reason: '40 - (1 mort + 6 ventes)');
    },
  );

  /// Une correction après synchronisation repart en file.
  test('une fiche corrigee repasse en attente', () async {
    await depot.enregistrer(
      lotId: bande,
      jour: DateTime(2026, 8, 18),
      achat: 0,
      ne: 0,
      mort: 1,
      don: 0,
    );

    await (db.update(
      db.livestockDailyEntries,
    )..where((t) => t.lotId.equals(bande))).write(
      const LivestockDailyEntriesCompanion(
        syncStatus: Value(SyncStatus.synced),
      ),
    );
    expect(await db.pendingCount(), 0);

    await depot.enregistrer(
      lotId: bande,
      jour: DateTime(2026, 8, 18),
      achat: 0,
      ne: 0,
      mort: 2,
      don: 0,
    );

    expect(
      await db.pendingCount(),
      1,
      reason: 'sinon le serveur garde l ancienne valeur, l ecran la nouvelle',
    );
  });

  /// L'effectif courant de la bande suit la fiche.
  test('l effectif de la bande suit la fiche', () async {
    await depot.enregistrer(
      lotId: bande,
      jour: DateTime(2026, 8, 18),
      achat: 0,
      ne: 0,
      mort: 7,
      don: 0,
    );

    final relue = await (db.select(
      db.livestockLots,
    )..where((t) => t.id.equals(bande))).getSingle();

    expect(relue.currentQuantity, 33);
  });

  /// ⚠️⚠️ CORRECTIF « EFFECTIF TOTAL VIVANT ». Une fiche ANTÉRIEURE saisie après coup ramenait
  /// la bande à l'effectif de son propre jour et laissait les jours suivants faux.
  /// Bande de 40 : le 19/08, 6 nés → 46 ; puis le 18/08, 7 morts → 33 ; le 19/08 recalculé
  /// = 33 + 6 = 39 ; bande = 39 (dernière fiche), jamais 33. Littéraux calculés à la main.
  test(
    'une fiche anterieure recalcule les jours suivants et la bande suit la derniere',
    () async {
      await depot.enregistrer(
        lotId: bande,
        jour: DateTime(2026, 8, 19),
        achat: 0,
        ne: 6,
        mort: 0,
        don: 0,
      );
      await depot.enregistrer(
        lotId: bande,
        jour: DateTime(2026, 8, 18),
        achat: 0,
        ne: 0,
        mort: 7,
        don: 0,
      );

      expect(
        (await depot.chargerJour(bande, DateTime(2026, 8, 18)))!.effectifFinal,
        33,
      );
      expect(
        (await depot.chargerJour(bande, DateTime(2026, 8, 19)))!.effectifFinal,
        39,
      );
      final relue = await (db.select(
        db.livestockLots,
      )..where((t) => t.id.equals(bande))).getSingle();
      expect(relue.currentQuantity, 39);
    },
  );

  /// ⚠️ LES GRAMMAGES VIENNENT DU SERVEUR, jamais du code : ils sont
  /// éditables depuis l'écran Paramètres > Élevage.
  test('les rations sont lues depuis le referentiel synchronise', () async {
    await db
        .into(db.feedRationStandards)
        .insert(
          FeedRationStandardsCompanion.insert(
            id: '11111111-2222-4333-8444-555555555555',
            speciesCode: 'cuniculture',
            stageLabel: 'Lapine Mere / Reproducteur',
            rationGPerDay: 120,
          ),
        );
    await db
        .into(db.feedRationStandards)
        .insert(
          FeedRationStandardsCompanion.insert(
            id: '22222222-3333-4444-8555-666666666666',
            speciesCode: 'aviculture',
            stageLabel: 'Poussin ponte',
            rationGPerDay: 30,
          ),
        );

    final cuniculture = await depot.rations('cuniculture');

    expect(cuniculture, hasLength(1), reason: 'l espece filtre bien');
    expect(cuniculture.single.rationGPerDay, 120);
  });

  /// Provende = effectif x ration, en grammes.
  test('la provende servie multiplie l effectif par la ration', () {
    expect(
      FicheJournaliereRepository.provendeGrammes(
        effectif: 12,
        rationGParJour: 120,
      ),
      1440,
    );
  });

  /// ⚠️ Un effectif nul ne consomme rien — et ne doit pas produire de reliquat.
  test('sans effectif, aucune provende', () {
    expect(
      FicheJournaliereRepository.provendeGrammes(
        effectif: 0,
        rationGParJour: 120,
      ),
      0,
    );
  });

  /// La formule de la maquette : poids total ÷ effectif final, arrondi.
  test('le poids moyen divise le total par l effectif final', () {
    expect(
      FicheJournaliereRepository.poidsMoyen(
        poidsTotalG: 3500,
        tailleEchantillon: 40,
      ),
      88,
    );
  });

  /// ⚠️ `null` ET NON ZÉRO sans pesée : « 0 g » se lirait comme un cheptel
  /// sans poids, alors qu'il s'agit d'une absence de mesure. Un zéro
  /// enregistré fausserait le suivi de croissance ; une absence ne fausse rien.
  test('sans pesee, le poids moyen n existe pas', () {
    expect(
      FicheJournaliereRepository.poidsMoyen(
        poidsTotalG: 0,
        tailleEchantillon: 40,
      ),
      isNull,
    );
    expect(
      FicheJournaliereRepository.poidsMoyen(
        poidsTotalG: 3500,
        tailleEchantillon: 0,
      ),
      isNull,
    );
  });

  /// Le poids moyen est bien persisté, et part en file.
  test('le poids moyen est enregistre avec la journee', () async {
    final fiche = await depot.enregistrer(
      lotId: bande,
      jour: DateTime(2026, 8, 18),
      achat: 0,
      ne: 0,
      mort: 0,
      don: 0,
      poidsMoyen: 88,
    );

    expect(fiche.weightSampleAvgG, 88);
    expect(await db.pendingCount(), 1);
  });

  /// ⚠️ Sans cheptel, le taux de mortalité n'existe pas — 0 % ferait lire
  /// « aucune perte ».
  test('le taux de mortalite est nul et non zero sans cheptel', () {
    expect(
      FicheJournaliereRepository.tauxMortalite(effectifPrecedent: 0, mort: 3),
      isNull,
    );
    expect(
      FicheJournaliereRepository.tauxMortalite(effectifPrecedent: 40, mort: 2),
      closeTo(5.0, 0.001),
    );
  });
}
