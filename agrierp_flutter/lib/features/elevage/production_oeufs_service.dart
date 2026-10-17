import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';

/// Conversion des œufs récoltés en plateaux, et entrée au stock du poste.
///
/// ⚠️⚠️ **LE POSTE PRODUIT L'EFFET TOUT DE SUITE, PAS SEULEMENT LE SERVEUR.**
/// `RecordEggProductionStockAction` le fait bien à la réception (ticket 14.59),
/// mais un poste peut rester des jours hors ligne : d'ici là, sa propre caisse
/// refuserait de vendre des plateaux qu'il vient pourtant de récolter. Même
/// raisonnement que pour les quatre effets d'une vente et pour la rémanence
/// d'un soin — ce que le serveur rejoue, le poste doit le produire aussitôt.
///
/// ⚠️ **LE GARDE-FOU EST L'ESPÈCE ET LE STADE**, identique au serveur :
/// `aviculture` **et** stade `ponte`. Les fiches Reproducteurs et Escargots
/// renseignent aussi la ponte ; leurs œufs ne sont pas des œufs de table, et un
/// stade « ponte » seul ne les distingue pas.
class ProductionOeufsService {
  ProductionOeufsService({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  /// Nombre d'œufs par plateau — valeur de la maquette, reprise du serveur.
  static const int oeufsParPlateau = 30;

  /// Œufs commercialisables : récoltés moins cassés, jamais négatif.
  static int commercialisables({required int recoltes, required int casses}) {
    return recoltes - casses < 0 ? 0 : recoltes - casses;
  }

  /// Plateaux entiers et reliquat en vrac.
  ///
  /// ⚠️ LE RELIQUAT N'ENTRE PAS AU STOCK : un plateau incomplet ne se vend pas
  /// comme un plateau. La maquette l'affiche séparément (« N Plateaux (M œufs
  /// vrac) ») précisément pour que la distinction reste visible.
  static ({int plateaux, int vrac}) enPlateaux(int oeufs) {
    final total = oeufs < 0 ? 0 : oeufs;

    return (plateaux: total ~/ oeufsParPlateau, vrac: total % oeufsParPlateau);
  }

  /// Taux de ponte du jour : œufs récoltés ÷ effectif, en pourcentage.
  ///
  /// ⚠️ `null` ET NON ZÉRO sans effectif : un taux de 0 % se lit « les poules
  /// n'ont pas pondu », alors qu'il s'agit d'une absence de cheptel.
  /// La maquette divise par l'**effectif final**, pas par l'effectif de la
  /// veille (`computePonteAndPlateaux`).
  static double? tauxDePonte({required int recoltes, required int effectif}) {
    if (effectif <= 0) return null;
    return (recoltes / effectif) * 100;
  }

  /// Produit « œufs » du catalogue local.
  ///
  /// ⚠️ RECHERCHE SUR UN LIBELLÉ NORMALISÉ, LIGATURE COMPRISE. Le catalogue
  /// écrit « **Œ**ufs de table (plateau) » : une comparaison qui ne rapproche
  /// pas « Œ » de « oe » ne trouve rien, et le stock resterait à zéro sans la
  /// moindre erreur — exactement le piège déjà rencontré côté serveur.
  Future<Product?> produitOeufs() async {
    final produits = await (_db.select(
      _db.products,
    )..where((t) => t.isActive.equals(true))).get();

    for (final produit in produits) {
      final normalise = produit.name.toLowerCase().replaceAll('œ', 'oe');
      if (normalise.contains('oeufs')) return produit;
    }

    return null;
  }

  /// Fait entrer au stock local les plateaux nets d'une fiche de ponte.
  ///
  /// ⚠️ **À LA CRÉATION SEULEMENT**, comme au serveur : incrémenter à chaque
  /// enregistrement compterait plusieurs fois les mêmes œufs lors d'une simple
  /// correction du même jour.
  ///
  /// @return le nombre de plateaux réellement entrés en stock.
  Future<int> entrerAuStock({
    required LivestockLot bande,
    required int recoltes,
    required int casses,
    required bool creation,
  }) async {
    if (!creation) return 0;

    // ⚠️ Œufs de TABLE uniquement.
    if (bande.stage != 'ponte' || bande.speciesCode != 'aviculture') return 0;

    final nets = enPlateaux(
      commercialisables(recoltes: recoltes, casses: casses),
    );
    if (nets.plateaux <= 0) return 0;

    final produit = await produitOeufs();
    if (produit == null) return 0;

    await (_db.update(
      _db.products,
    )..where((t) => t.id.equals(produit.id))).write(
      ProductsCompanion(stockQty: Value(produit.stockQty + nets.plateaux)),
    );

    return nets.plateaux;
  }
}
