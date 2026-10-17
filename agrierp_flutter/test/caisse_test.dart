import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masques ici pour
// laisser accessibles les matchers homonymes de `flutter_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — CAISSE HORS LIGNE.
///
/// Les quatre effets d'une vente sont garantis côté serveur depuis le ticket
/// 14.53. Ils doivent l'être AUSSI localement : un poste peut rester des jours
/// hors ligne, et le comptoir continuerait sinon de proposer des sujets déjà
/// vendus en affichant un effectif périmé.
///
/// Le test le plus important est le blocage sanitaire : c'est le seul refus dur
/// de cette caisse.
void main() {
  late AppDatabase db;
  late CaisseRepository caisse;

  const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const espece = 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee';

  late Product poulet;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    caisse = CaisseRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bande,
            code: 'AVI-2026-01',
            speciesId: espece,
            initialQuantity: const Value(50),
            currentQuantity: const Value(50),
          ),
        );

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'pppppppp-1111-4111-8111-pppppppppppp',
            sku: 'AVI-001',
            name: 'Poulet goliath',
            speciesId: const Value(espece),
            unit: 'u',
            pricingMode: 'fourchette',
            stockQty: const Value(50),
          ),
        );

    poulet = await (db.select(
      db.products,
    )..where((t) => t.sku.equals('AVI-001'))).getSingle();
  });

  tearDown(() async => db.close());

  Future<VeterinaryWithdrawalPeriod> poserRemanence(DateTime fin) async {
    await db
        .into(db.veterinaryWithdrawalPeriods)
        .insert(
          VeterinaryWithdrawalPeriodsCompanion.insert(
            id: 'rrrrrrrr-1111-4111-8111-rrrrrrrrrrrr',
            lotId: bande,
            productUsed: const Value('Antibiotique polyvalent'),
            endDate: fin,
          ),
        );

    return (await db.select(db.veterinaryWithdrawalPeriods).getSingle());
  }

  List<LignePanier> panier({int quantite = 6, double montant = 21000}) => [
    LignePanier(
      produit: poulet,
      quantite: quantite,
      montant: montant,
      lotId: bande,
    ),
  ];

  /// LE FLUX NOMINAL : la vente est enregistrée et mise en file.
  test('une vente est enregistree et mise en file', () async {
    final vente = await caisse.enregistrerVente(
      panier: panier(),
      modePaiement: 'especes',
      especesRecues: 25000,
    );

    expect(vente.total, 21000);
    expect(vente.changeDue, 4000, reason: 'la monnaie est calculee');
    expect(vente.syncStatus, SyncStatus.pending);

    final lignes = await db.select(db.saleLines).get();
    expect(lignes, hasLength(1));
    expect(lignes.single.lotId, bande, reason: 'la bande vendue est conservee');
  });

  /// ⚠️ Le montant de la ligne fait foi ; le prix unitaire s'en déduit.
  test('le prix unitaire se deduit du montant, jamais l inverse', () async {
    await caisse.enregistrerVente(
      panier: panier(quantite: 3, montant: 10000),
      modePaiement: 'especes',
    );

    final ligne = await db.select(db.saleLines).getSingle();

    expect(ligne.manualTotalAmount, 10000);
    expect(ligne.unitPrice, closeTo(3333.33, 0.01));
  });

  /// 🔴→✅ EFFET LOCAL 1 : le stock suit immédiatement.
  test('le stock local est decremente aussitot', () async {
    await caisse.enregistrerVente(panier: panier(), modePaiement: 'especes');

    final relu = await (db.select(
      db.products,
    )..where((t) => t.id.equals(poulet.id))).getSingle();

    expect(relu.stockQty, 44);
  });

  /// 🔴→✅ EFFET LOCAL 2 : la fiche du jour suit la sortie du cheptel.
  test('la fiche du jour suit la vente', () async {
    await caisse.enregistrerVente(panier: panier(), modePaiement: 'especes');

    final fiche = await db.select(db.livestockDailyEntries).getSingle();

    expect(fiche.vente, 6);
    expect(fiche.effectifFinal, 44, reason: '50 sujets moins 6 vendus');
    expect(fiche.syncStatus, SyncStatus.pending);

    final relue = await (db.select(
      db.livestockLots,
    )..where((t) => t.id.equals(bande))).getSingle();
    expect(relue.currentQuantity, 44);
  });

  /// ⚠️ LA FICHE EST COMPLÉTÉE, JAMAIS ÉCRASÉE : les morts déjà saisis par
  /// l'animalier doivent survivre au passage en caisse.
  test('la vente n efface pas ce que l animalier a deja saisi', () async {
    final aujourdhui = DateTime.now();
    final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);

    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'ffffffff-1111-4111-8111-ffffffffffff',
            deviceId: 'poste-test',
            updatedAt: jour,
            lotId: bande,
            entryDate: jour,
            mort: const Value(4),
            effectifFinal: const Value(46),
          ),
        );

    await caisse.enregistrerVente(panier: panier(), modePaiement: 'especes');

    final fiche = await db.select(db.livestockDailyEntries).getSingle();

    expect(fiche.mort, 4, reason: 'la mortalite saisie survit');
    expect(fiche.vente, 6);
    expect(fiche.effectifFinal, 40, reason: '50 - (4 morts + 6 ventes)');
  });

  /// ⚠️⚠️ LE SEUL REFUS DUR DE CETTE CAISSE — santé publique.
  test('une bande sous remanence ne vend rien', () async {
    await poserRemanence(DateTime.now().add(const Duration(days: 5)));

    expect(
      () => caisse.enregistrerVente(panier: panier(), modePaiement: 'especes'),
      throwsA(
        isA<VenteRefusee>().having(
          (e) => e.message,
          'message',
          allOf(contains('rémanence'), contains('AVI-2026-01')),
        ),
      ),
    );
  });

  /// ⚠️ UN REFUS NE LAISSE AUCUNE TRACE PARTIELLE : ni vente, ni stock entamé.
  test('une vente refusee ne laisse aucune trace', () async {
    await poserRemanence(DateTime.now().add(const Duration(days: 5)));

    try {
      await caisse.enregistrerVente(panier: panier(), modePaiement: 'especes');
    } on VenteRefusee {
      // attendu
    }

    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.saleLines).get(), isEmpty);

    final relu = await (db.select(
      db.products,
    )..where((t) => t.id.equals(poulet.id))).getSingle();
    expect(relu.stockQty, 50, reason: 'le stock est intact');
  });

  /// Une rémanence expirée ne bloque plus rien.
  test('une remanence expiree ne bloque plus', () async {
    await poserRemanence(DateTime.now().subtract(const Duration(days: 1)));

    final vente = await caisse.enregistrerVente(
      panier: panier(),
      modePaiement: 'especes',
    );

    expect(vente.total, 21000);
  });

  /// Une rémanence qui se termine AUJOURD'HUI bloque encore : le délai
  /// d'attente court jusqu'à la fin de la journée.
  test('une remanence qui finit aujourd hui bloque encore', () async {
    await poserRemanence(DateTime.now());

    expect(
      () => caisse.enregistrerVente(panier: panier(), modePaiement: 'especes'),
      throwsA(isA<VenteRefusee>()),
    );
  });

  /// ⚠️ Le stock négatif n'est pas bridé : il révèle une entrée non saisie,
  /// et le brider ferait diverger le poste du serveur.
  test('un stock insuffisant passe et devient negatif', () async {
    final vente = await caisse.enregistrerVente(
      panier: panier(quantite: 60, montant: 210000),
      modePaiement: 'especes',
    );

    expect(vente.total, 210000);

    final relu = await (db.select(
      db.products,
    )..where((t) => t.id.equals(poulet.id))).getSingle();
    expect(relu.stockQty, -10);
  });

  /// Un panier vide est refusé avant toute écriture.
  test('un panier vide est refuse', () async {
    expect(
      () => caisse.enregistrerVente(panier: const [], modePaiement: 'especes'),
      throwsA(isA<VenteRefusee>()),
    );
  });

  /// Une vente sans bande (provende) ne crée aucune fiche d'élevage.
  test('une vente sans bande ne cree aucune fiche', () async {
    await caisse.enregistrerVente(
      panier: [LignePanier(produit: poulet, quantite: 2, montant: 7000)],
      modePaiement: 'especes',
    );

    expect(await db.select(db.livestockDailyEntries).get(), isEmpty);

    final relu = await (db.select(
      db.products,
    )..where((t) => t.id.equals(poulet.id))).getSingle();
    expect(relu.stockQty, 48, reason: 'le stock baisse quand meme');
  });
}
