import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';

/// Une ligne du tableau « Tableau & Valorisation ».
class LigneStock {
  const LigneStock({required this.produit, required this.categorie});

  final Product produit;
  final String categorie;

  /// ⚠️⚠️ **LE PMP N'EST PAS ENCORE CALCULÉ SUR CET ÉCRAN.** Côté serveur,
  /// `Product::computePmp()` est une moyenne pondérée des **lignes d'achat** ;
  /// elles descendent au poste depuis U4 (D-U4) — le Tableau de bord s'en sert
  /// pour la marge du Top 5 (`TableauDeBordRepository.pmp`) —, mais la
  /// valorisation de cet écran reste à porter. D'ici là : un tiret, jamais une
  /// estimation à partir du prix de VENTE, qui donnerait une valorisation
  /// supérieure au coût et gonflerait l'actif.
  double? get pmp => null;

  bool get sousSeuil =>
      produit.alertThreshold != null &&
      produit.stockQty <= produit.alertThreshold!;

  /// ⚠️ **UN STOCK NÉGATIF N'EST PAS UNE FRAUDE** : c'est le signe d'une
  /// ENTRÉE NON SAISIE (production ou achat pas encore enregistré),
  /// régularisable par un ajustement d'inventaire. Le serveur pose la même
  /// lecture (`Product`, ticket 14.30).
  bool get negatif => produit.stockQty < 0;
}

/// Une ligne du « Journal des Mouvements ».
class MouvementStock {
  const MouvementStock({required this.ajustement, required this.designation});

  final StockAdjustment ajustement;
  final String designation;
}

class DonneesStocks {
  const DonneesStocks({
    required this.lignes,
    required this.mouvements,
    required this.categories,
  });

  final List<LigneStock> lignes;
  final List<MouvementStock> mouvements;
  final List<String> categories;

  int get alertesDeSeuil => lignes.where((l) => l.sousSeuil).length;

  /// Nombre d'écarts d'inventaire saisis sur ce poste.
  ///
  /// ⚠️ **EN NOMBRE, PAS EN FRANCS.** La maquette affiche « Écarts
  /// d'Inventaire » en FCFA — un écart se valorise au PMP, que le poste n'a
  /// pas. Le compte, lui, est exact.
  int get ecartsDInventaire => mouvements.length;
}

/// Lectures et écritures de `prototype_html/gestion-stocks.html`.
///
/// ⚠️⚠️ **AUCUN ÉCRAN NE CRÉAIT D'AJUSTEMENT.** `stock_adjustments` est
/// poussée par le moteur de synchronisation depuis le ticket F0.3, et le
/// serveur la rejoue par son action d'ajustement — mais **rien au poste ne
/// l'alimentait**. Le canal d'envoi existait sans producteur : un inventaire
/// physique constaté au magasin n'avait aucun moyen d'être saisi hors ligne.
///
/// ⚠️ **LE JOURNAL DES MOUVEMENTS NE VOIT QUE LES AJUSTEMENTS DE CE POSTE.**
/// `stock_movements` — le grand livre des entrées et sorties, alimenté par
/// les ventes, les achats et la production — ne figure pas dans la charge du
/// tirage. Le journal local est donc partiel, et le dit.
class StocksRepository {
  StocksRepository({
    required this.database,
    this.deviceId = 'poste',
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final String deviceId;
  final Uuid _uuid;

  /// Les huit motifs d'écart de la maquette, dans son ordre.
  ///
  /// ⚠️ Le menu de la maquette invite à choisir « selon le sens de l'écart » :
  /// les quatre premiers correspondent à un manquant, les quatre suivants à
  /// un excédent. La liste est recopiée telle quelle — l'appariement au sens
  /// n'est écrit nulle part, et l'inventer restreindrait à tort la saisie.
  static const motifs = [
    'Casse de matériel',
    'Vol / Disparition',
    'Mortalité non déclarée',
    "Erreur de pesée d'approvisionnement",
    'Péremption dépassée',
    'Naissance non répertoriée',
    'Surplus de livraison',
    "Erreur d'inventaire antérieur",
  ];

  Future<DonneesStocks> charger() async {
    final produits = await (database.select(
      database.products,
    )..where((t) => t.isActive.equals(true))).get();
    final categories = await database.select(database.productCategories).get();
    final ajustements = await database.select(database.stockAdjustments).get();

    final libelleDe = {for (final c in categories) c.id: c.label};
    final nomDe = {for (final p in produits) p.id: p.name};

    return DonneesStocks(
      lignes: (produits.toList()..sort((a, b) => a.sku.compareTo(b.sku)))
          .map(
            (p) => LigneStock(
              produit: p,
              categorie: libelleDe[p.categoryId] ?? '—',
            ),
          )
          .toList(),
      mouvements:
          (ajustements.toList()
                ..sort((a, b) => b.movementDate.compareTo(a.movementDate)))
              .map(
                (a) => MouvementStock(
                  ajustement: a,
                  designation: nomDe[a.productId] ?? 'Produit inconnu',
                ),
              )
              .toList(),
      categories: (libelleDe.values.toSet().toList()..sort()),
    );
  }

  /// Enregistre un écart d'inventaire et aligne le stock local sur le comptage.
  ///
  /// ⚠️⚠️ **LE SENS EST PORTÉ PAR `type`, JAMAIS PAR LE SIGNE DE LA
  /// QUANTITÉ.** C'est la convention du serveur, et sa validation refuse une
  /// quantité négative ou nulle. Envoyer −3 en « entrée » passerait le
  /// contrôle de sens et remonterait le stock au lieu de le baisser.
  ///
  /// ⚠️ **LE STOCK LOCAL SUIT IMMÉDIATEMENT.** C'est tout l'objet d'un
  /// inventaire : le comptage physique devient la vérité. Le serveur, lui, ne
  /// rejoue jamais le delta tel quel — il recalcule depuis l'état réel du
  /// produit au moment de la réception, ce qui rend l'opération sûre même si
  /// l'envoi part deux fois.
  Future<StockAdjustment> enregistrerEcart({
    required String productId,
    required double stockPhysique,
    required String motif,
    DateTime? quand,
  }) async {
    final maintenant = quand ?? DateTime.now();

    final produit = await (database.select(
      database.products,
    )..where((t) => t.id.equals(productId))).getSingleOrNull();

    if (produit == null) {
      throw ArgumentError('Produit inconnu sur ce poste.');
    }

    final ecart = stockPhysique - produit.stockQty;

    // ⚠️ UN ÉCART NUL N'EST PAS UN MOUVEMENT. L'enregistrer produirait une
    // ligne de journal qui ne dit rien et que le serveur rejetterait
    // (`quantity` doit être strictement positive).
    if (ecart == 0) {
      throw ArgumentError(
        'Le stock physique est identique au stock théorique : aucun écart à '
        'enregistrer.',
      );
    }

    if (motif.isEmpty) {
      throw ArgumentError("Le motif de l'écart est obligatoire.");
    }

    final id = _uuid.v4();

    await database.transaction(() async {
      await database
          .into(database.stockAdjustments)
          .insert(
            StockAdjustmentsCompanion.insert(
              id: id,
              deviceId: deviceId,
              syncStatus: const Value(SyncStatus.pending),
              updatedAt: maintenant,
              productId: productId,
              type: ecart > 0 ? 'entree' : 'sortie',
              quantity: ecart.abs(),
              referenceType: 'inventaire',
              reason: Value(motif),
              movementDate: maintenant,
            ),
          );

      await (database.update(database.products)
            ..where((t) => t.id.equals(productId)))
          .write(ProductsCompanion(stockQty: Value(stockPhysique)));
    });

    return (await (database.select(
      database.stockAdjustments,
    )..where((t) => t.id.equals(id))).getSingle());
  }
}
