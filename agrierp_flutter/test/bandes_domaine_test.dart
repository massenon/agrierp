import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/domain/entities/bande_origine.dart';
import 'package:agrierp/domain/entities/produit_candidat.dart';
import 'package:agrierp/features/elevage/bandes_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// B6 — DDD : `BandesRepository.produitsCandidats()` et `bandesOrigine()` exposent des entités
/// de domaine pures (jamais des types Drift `Product` / `LivestockLot`).
void main() {
  const speciesId = 'aaaaaaaa-0000-4000-8000-000000000001';
  const autreSpeciesId = 'aaaaaaaa-0000-4000-8000-000000000002';
  String uid(String s) => s.padLeft(36, '0');

  Future<AppDatabase> creerDb() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.livestockSpecies).insert(
      LivestockSpeciesCompanion.insert(id: speciesId, code: 'cuniculture', label: 'Cuniculture'),
    );
    await db.into(db.livestockSpecies).insert(
      LivestockSpeciesCompanion.insert(id: autreSpeciesId, code: 'aviculture', label: 'Aviculture'),
    );
    return db;
  }

  Future<void> insererProduit(
    AppDatabase db, {
    required String id,
    required String sku,
    required String nom,
    bool actif = true,
    String sid = speciesId,
  }) =>
      db.into(db.products).insert(
        ProductsCompanion.insert(
          id: uid(id),
          sku: sku,
          name: nom,
          unit: 'tete',
          pricingMode: 'fixe',
          speciesId: Value(sid),
          isActive: Value(actif),
        ),
      );

  Future<void> insererBande(
    AppDatabase db, {
    required String id,
    required String code,
    int effectif = 10,
    bool active = true,
    String sid = speciesId,
  }) =>
      db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: uid(id),
          code: code,
          speciesId: sid,
          speciesCode: const Value('cuniculture'),
          stage: const Value('reproduction'),
          initialQuantity: Value(effectif),
          currentQuantity: Value(effectif),
          createdDate: Value(DateTime(2026, 1, 1)),
          status: const Value('actif'),
          isActive: Value(active),
        ),
      );

  // ── produitsCandidats ────────────────────────────────────────────────────

  group('produitsCandidats', () {
    test('renvoie [] quand speciesId est vide', () async {
      final db = await creerDb();
      addTearDown(db.close);
      final repo = BandesRepository(database: db, deviceId: 'test');
      expect(await repo.produitsCandidats(''), isEmpty);
    });

    test('renvoie List<ProduitCandidat> (entite de domaine, jamais Product Drift)', () async {
      final db = await creerDb();
      addTearDown(db.close);
      await insererProduit(db, id: 'p-01', sku: 'LAP-001', nom: 'Lapin Reproducteur');
      final repo = BandesRepository(database: db, deviceId: 'test');
      final liste = await repo.produitsCandidats(speciesId);
      expect(liste, isA<List<ProduitCandidat>>());
    });

    test('exclut les intrants ALI-*', () async {
      final db = await creerDb();
      addTearDown(db.close);
      await insererProduit(db, id: 'p-ali-01', sku: 'ALI-LAP-001', nom: 'Aliment Lapins');
      await insererProduit(db, id: 'p-ok-01', sku: 'LAP-002', nom: 'Lapin Chair');
      final repo = BandesRepository(database: db, deviceId: 'test');
      final liste = await repo.produitsCandidats(speciesId);
      expect(liste.any((p) => p.id == uid('p-ali-01')), isFalse);
      expect(liste.any((p) => p.id == uid('p-ok-01')), isTrue);
    });

    test('exclut les intrants MED-*', () async {
      final db = await creerDb();
      addTearDown(db.close);
      await insererProduit(db, id: 'p-med-01', sku: 'MED-LAP-001', nom: 'Medicament Lapins');
      await insererProduit(db, id: 'p-ok-02', sku: 'LAP-003', nom: 'Lapin Engraissement');
      final repo = BandesRepository(database: db, deviceId: 'test');
      final liste = await repo.produitsCandidats(speciesId);
      expect(liste.any((p) => p.id == uid('p-med-01')), isFalse);
      expect(liste.any((p) => p.id == uid('p-ok-02')), isTrue);
    });

    test('exclut les produits inactifs', () async {
      final db = await creerDb();
      addTearDown(db.close);
      await insererProduit(db, id: 'p-inact', sku: 'LAP-004', nom: 'Archive', actif: false);
      final repo = BandesRepository(database: db, deviceId: 'test');
      final liste = await repo.produitsCandidats(speciesId);
      expect(liste.any((p) => p.id == uid('p-inact')), isFalse);
    });

    test('les champs id, sku et nom sont correctement mappes', () async {
      final db = await creerDb();
      addTearDown(db.close);
      await insererProduit(db, id: 'p-map-01', sku: 'LAP-005', nom: 'Lapin Grand-Pere');
      final repo = BandesRepository(database: db, deviceId: 'test');
      final liste = await repo.produitsCandidats(speciesId);
      final p = liste.firstWhere((x) => x.id == uid('p-map-01'));
      expect(p.sku, 'LAP-005');
      expect(p.nom, 'Lapin Grand-Pere');
    });
  });

  // ── bandesOrigine ────────────────────────────────────────────────────────

  group('bandesOrigine', () {
    test('renvoie [] quand speciesId est vide', () async {
      final db = await creerDb();
      addTearDown(db.close);
      final repo = BandesRepository(database: db, deviceId: 'test');
      expect(await repo.bandesOrigine(''), isEmpty);
    });

    test('renvoie List<BandeOrigine> (entite de domaine, jamais LivestockLot Drift)', () async {
      final db = await creerDb();
      addTearDown(db.close);
      await insererBande(db, id: 'b-01------', code: 'LOT-001');
      final repo = BandesRepository(database: db, deviceId: 'test');
      final liste = await repo.bandesOrigine(speciesId);
      expect(liste, isA<List<BandeOrigine>>());
    });

    test('exclut les bandes archivees', () async {
      final db = await creerDb();
      addTearDown(db.close);
      await insererBande(db, id: 'b-arch----', code: 'LOT-ARCH', active: false);
      await insererBande(db, id: 'b-ok------', code: 'LOT-OK');
      final repo = BandesRepository(database: db, deviceId: 'test');
      final liste = await repo.bandesOrigine(speciesId);
      expect(liste.any((o) => o.id == uid('b-arch----')), isFalse);
      expect(liste.any((o) => o.id == uid('b-ok------')), isTrue);
    });

    test('les champs id, code et quantiteActuelle sont correctement mappes', () async {
      final db = await creerDb();
      addTearDown(db.close);
      await insererBande(db, id: 'b-map-----', code: 'LOT-002', effectif: 42);
      final repo = BandesRepository(database: db, deviceId: 'test');
      final liste = await repo.bandesOrigine(speciesId);
      final o = liste.firstWhere((x) => x.id == uid('b-map-----'));
      expect(o.code, 'LOT-002');
      expect(o.quantiteActuelle, 42.0);
    });

    test('exclut les bandes d une autre espece', () async {
      final db = await creerDb();
      addTearDown(db.close);
      await insererBande(db, id: 'b-autre---', code: 'VOL-001', sid: autreSpeciesId);
      await insererBande(db, id: 'b-ok2-----', code: 'LOT-003');
      final repo = BandesRepository(database: db, deviceId: 'test');
      final liste = await repo.bandesOrigine(speciesId);
      expect(liste.any((o) => o.id == uid('b-autre---')), isFalse);
      expect(liste.any((o) => o.id == uid('b-ok2-----')), isTrue);
    });
  });
}
