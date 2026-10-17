import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masques ici pour
// laisser accessibles les matchers homonymes de `flutter_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — SOINS VÉTÉRINAIRES AU POSTE.
///
/// ⚠️⚠️ Le test qui compte est celui du bout de chaîne : un soin saisi au poste
/// doit **bloquer immédiatement la caisse de ce même poste**. Le serveur crée
/// bien la rémanence à la réception, mais un poste peut rester des jours hors
/// ligne — d'ici là, il vendrait une bande qui vient d'être traitée.
void main() {
  late AppDatabase db;
  late SoinsRepository soins;
  late CaisseRepository caisse;

  const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const espece = 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee';

  late Product lapin;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
    caisse = CaisseRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bande,
            code: 'CUN-2026-01',
            speciesId: espece,
            initialQuantity: const Value(40),
            currentQuantity: const Value(40),
          ),
        );

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'pppppppp-1111-4111-8111-pppppppppppp',
            sku: 'CUN-001',
            name: 'Lapin vivant',
            speciesId: const Value(espece),
            unit: 'u',
            pricingMode: 'fourchette',
            stockQty: const Value(40),
          ),
        );

    lapin = await (db.select(
      db.products,
    )..where((t) => t.sku.equals('CUN-001'))).getSingle();
  });

  tearDown(() async => db.close());

  test('un soin est enregistre et mis en file', () async {
    final soin = await soins.enregistrer(
      lotId: bande,
      typeAction: 'Vaccination',
      produit: 'Vaccin myxomatose',
      dose: '1 ml',
    );

    expect(soin.actionType, 'Vaccination');
    expect(soin.syncStatus, SyncStatus.pending);
    expect(await db.pendingCount(), 1);
  });

  /// ⚠️⚠️ LE CAS QUI COMPTE : la caisse du poste refuse aussitôt.
  test('un soin avec delai bloque immediatement la caisse du poste', () async {
    await soins.enregistrer(
      lotId: bande,
      typeAction: 'Traitement antibiotique',
      produit: 'Antibiotique polyvalent',
      delaiAttenteJours: 7,
    );

    expect(
      () => caisse.enregistrerVente(
        panier: [
          LignePanier(produit: lapin, quantite: 2, montant: 9000, lotId: bande),
        ],
        modePaiement: 'especes',
      ),
      throwsA(isA<VenteRefusee>()),
      reason: 'sans blocage local, le poste vendrait pendant des jours',
    );
  });

  /// Sans délai d'attente, la vente reste possible.
  test('un soin sans delai ne bloque pas la vente', () async {
    await soins.enregistrer(
      lotId: bande,
      typeAction: 'Vitamines',
      produit: 'Vitamines AD3E',
    );

    final vente = await caisse.enregistrerVente(
      panier: [
        LignePanier(produit: lapin, quantite: 2, montant: 9000, lotId: bande),
      ],
      modePaiement: 'especes',
    );

    expect(vente.total, 9000);
  });

  /// ⚠️ Même condition que le serveur : un délai sans produit ne dit pas de
  /// quoi la viande doit se purger.
  test('un delai sans produit ne cree aucune remanence', () async {
    await soins.enregistrer(
      lotId: bande,
      typeAction: 'Observation',
      delaiAttenteJours: 7,
    );

    expect(await db.select(db.veterinaryWithdrawalPeriods).get(), isEmpty);
    expect(await caisse.remanenceActive(bande), isNull);
  });

  /// La rémanence court bien jusqu'à la fin du délai.
  test('la remanence court jusqu au terme du delai', () async {
    final quand = DateTime(2026, 8, 18);

    await soins.enregistrer(
      lotId: bande,
      typeAction: 'Traitement',
      produit: 'Antibiotique',
      delaiAttenteJours: 7,
      quand: quand,
    );

    final periode = await db.select(db.veterinaryWithdrawalPeriods).getSingle();

    expect(periode.endDate, DateTime(2026, 8, 25));
    expect(periode.productUsed, 'Antibiotique');
  });

  /// ⚠️ Un identifiant dérivé du soin empêche qu'une relecture crée une
  /// seconde période — la bande serait bloquée deux fois trop longtemps.
  test('deux soins distincts creent deux periodes distinctes', () async {
    await soins.enregistrer(
      lotId: bande,
      typeAction: 'Traitement 1',
      produit: 'Produit A',
      delaiAttenteJours: 3,
    );
    await soins.enregistrer(
      lotId: bande,
      typeAction: 'Traitement 2',
      produit: 'Produit B',
      delaiAttenteJours: 5,
    );

    expect(await db.select(db.veterinaryWithdrawalPeriods).get(), hasLength(2));
    expect(await db.pendingCount(), 2);
  });

  /// Le protocole est lu depuis le référentiel synchronisé, jamais codé.
  test('le protocole vient du referentiel synchronise', () async {
    await db
        .into(db.prophylaxisScheduleStandards)
        .insert(
          ProphylaxisScheduleStandardsCompanion.insert(
            id: '11111111-2222-4333-8444-555555555555',
            speciesCode: 'cuniculture',
            periodLabel: 'Semaine 4',
            treatment: 'Vaccination myxomatose',
            productRecommended: const Value('Vaccin myxo'),
            withdrawalDays: const Value(0),
          ),
        );
    await db
        .into(db.prophylaxisScheduleStandards)
        .insert(
          ProphylaxisScheduleStandardsCompanion.insert(
            id: '22222222-3333-4444-8555-666666666666',
            speciesCode: 'aviculture',
            periodLabel: 'Semaine 2',
            treatment: 'Anticoccidien',
          ),
        );

    final cuniculture = await soins.protocole('cuniculture');

    expect(cuniculture, hasLength(1));
    expect(cuniculture.single.treatment, 'Vaccination myxomatose');
  });

  test(
    'l historique d une bande est rendu du plus recent au plus ancien',
    () async {
      await soins.enregistrer(
        lotId: bande,
        typeAction: 'Ancien',
        quand: DateTime(2026, 8, 1),
      );
      await soins.enregistrer(
        lotId: bande,
        typeAction: 'Recent',
        quand: DateTime(2026, 8, 18),
      );

      final historique = await soins.historique(bande);

      expect(historique.first.actionType, 'Recent');
      expect(historique.last.actionType, 'Ancien');
    },
  );
}
