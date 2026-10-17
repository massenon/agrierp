import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';

/// Ce que l'utilisateur saisit dans « Ajouter un Produit » / « Modifier le Produit ».
class FormulaireProduit {
  const FormulaireProduit({
    required this.nom,
    required this.categorieId,
    required this.unite,
    required this.mode,
    this.especeId = '',
    this.prixMin,
    this.prixMax,
    this.stock = 0,
    this.seuil = 0,
    this.tva = 0,
    this.description = '',
  });

  final String nom;
  final String categorieId;
  final String especeId;
  final String unite;

  /// `fourchette` ou `quote` (« Sur devis »).
  final String mode;
  final double? prixMin;
  final double? prixMax;

  /// Stock initial — ⚠️ ne part qu'à la CRÉATION.
  final double stock;
  final double seuil;
  final double tva;
  final String description;

  bool get fourchette => mode == 'fourchette';
}

/// Création et modification d'un produit — `prototype_html/ajouter-produit.html`.
///
/// ⚠️⚠️ **LOCAL D'ABORD, COMME TOUT LE POSTE.** Le produit est écrit tout de suite
/// dans la base du poste, `pending`, avec un UUID du poste ; la synchronisation
/// l'envoie, et le serveur — qui reste maître de la règle — le valide et engendre
/// le SKU définitif, qui revient au tirage suivant. Un refus revient en `conflict`
/// et se lit à l'écran de synchronisation. C'est le SEUL référentiel où le poste
/// écrit ; tous les autres restent « le serveur gagne ».
///
/// ⚠️ **SKU PROVISOIRE** (`LOC-xxxxxx`) tant que le serveur ne l'a pas attribué : le
/// poste ne peut pas le deviner sans doublon possible entre deux postes.
///
/// ⚠️ **LA QUANTITÉ N'EST ÉCRITE QU'À LA CRÉATION** (« Stock Initial »). Modifier un
/// produit ne touche jamais son stock : on le corrige par un ajustement.
///
/// ⚠️ **RÈGLES = CELLES DE LARAVEL** (`ProductCatalogService`) : fourchette ⇒ les
/// deux prix et `max ≥ min` ; sur devis ⇒ aucun prix.
///
/// ⚠️ **ÉCART ASSUMÉ AVEC LE GABARIT DU PROTOTYPE** : `ajouter-produit.html` porte UN
/// « Prix unitaire » ; la règle métier est « Fourchette » ou « Sur devis » (comme la
/// modale de `catalogue-view.html`). La liste de produits que la page embarque existe
/// déjà au Catalogue : deux listes dériveraient.
class ProduitsRepository {
  ProduitsRepository({required this.database, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final Uuid _uuid;

  Future<List<ProductCategory>> categories() =>
      (database.select(database.productCategories)
            ..where((c) => c.isActive.equals(true))
            ..orderBy([(c) => OrderingTerm(expression: c.label)]))
          .get();

  Future<List<EspeceElevage>> especes() => (database.select(
    database.livestockSpecies,
  )..orderBy([(e) => OrderingTerm(expression: e.label)])).get();

  Future<Product?> produit(String id) => (database.select(
    database.products,
  )..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Règles de saisie, à l'identique du serveur. Vide si recevable.
  static Map<String, String> valider(
    FormulaireProduit f, {
    required bool creation,
  }) {
    const obligatoire = 'Ce champ est obligatoire.';
    final e = <String, String>{};

    if (f.nom.trim().isEmpty) {
      e['nom'] = obligatoire;
    } else if (f.nom.trim().length > 150) {
      e['nom'] = '150 caractères au plus.';
    }
    if (f.categorieId.isEmpty) e['categorie'] = obligatoire;
    if (f.unite.trim().isEmpty) {
      e['unite'] = obligatoire;
    } else if (f.unite.trim().length > 20) {
      e['unite'] = '20 caractères au plus.';
    }
    if (f.description.length > 2000) {
      e['description'] = '2000 caractères au plus.';
    }
    if (f.tva < 0 || f.tva > 100) e['tva'] = 'Entre 0 et 100.';
    if (f.seuil < 0) e['seuil'] = 'Ne peut pas être négatif.';
    if (creation && f.stock < 0) e['stock'] = 'Ne peut pas être négatif.';

    // Fourchette ⇒ les deux prix, max ≥ min. Sur devis ⇒ rien à vérifier.
    if (f.fourchette) {
      final min = f.prixMin;
      final max = f.prixMax;
      if (min == null) {
        e['prixMin'] = obligatoire;
      } else if (min < 0) {
        e['prixMin'] = 'Ne peut pas être négatif.';
      }
      if (max == null) {
        e['prixMax'] = obligatoire;
      } else if (max < 0) {
        e['prixMax'] = 'Ne peut pas être négatif.';
      } else if (min != null && max < min) {
        e['prixMax'] =
            'Le prix maximum doit être supérieur ou égal au prix minimum.';
      }
    }

    return e;
  }

  Future<Product> creer(FormulaireProduit f) async {
    final id = _uuid.v4();

    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: id,
            sku: 'LOC-${id.substring(0, 6).toUpperCase()}',
            name: f.nom.trim(),
            categoryId: Value(f.categorieId),
            speciesId: Value(f.especeId.isEmpty ? null : f.especeId),
            unit: f.unite.trim(),
            pricingMode: f.mode,
            priceMin: Value(f.fourchette ? f.prixMin : null),
            priceMax: Value(f.fourchette ? f.prixMax : null),
            tvaRate: Value(f.tva),
            stockQty: Value(f.stock),
            alertThreshold: Value(f.seuil),
            description: Value(
              f.description.trim().isEmpty ? null : f.description.trim(),
            ),
            syncStatus: const Value(SyncStatus.pending),
            updatedAt: Value(DateTime.now()),
          ),
        );

    return (await produit(id))!;
  }

  /// ⚠️ Ni le SKU ni la quantité ne changent ici.
  Future<Product> modifier(String id, FormulaireProduit f) async {
    await (database.update(
      database.products,
    )..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        name: Value(f.nom.trim()),
        categoryId: Value(f.categorieId),
        speciesId: Value(f.especeId.isEmpty ? null : f.especeId),
        unit: Value(f.unite.trim()),
        pricingMode: Value(f.mode),
        priceMin: Value(f.fourchette ? f.prixMin : null),
        priceMax: Value(f.fourchette ? f.prixMax : null),
        tvaRate: Value(f.tva),
        alertThreshold: Value(f.seuil),
        description: Value(
          f.description.trim().isEmpty ? null : f.description.trim(),
        ),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(DateTime.now()),
      ),
    );

    return (await produit(id))!;
  }
}
