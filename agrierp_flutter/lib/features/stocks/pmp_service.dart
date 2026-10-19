import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';

/// Ticket U8 — LE PRIX MOYEN PONDÉRÉ, UN SEUL POINT DE CALCUL AU POSTE.
///
/// Transposition de `Product::computePmp()` (Laravel), lui-même extrait au ticket 12.7 pour être le SEUL calcul
/// du PMP du serveur (Gestion des Stocks, Synthèse Stocks, marge du Top 5, écart d'inventaire). Le poste en avait
/// une copie dans le Tableau de bord (U4) ; la Gestion des Stocks en a besoin à son tour : deux copies finiraient
/// par diverger, et la ferme lirait deux PMP pour le même produit.
///
///   PMP = Σ (qté × prix unitaire) ÷ Σ qté sur TOUTES les lignes d'achat du produit, arrondi à 2 décimales ;
///   `null` (« — ») si la quantité achetée totale n'est pas strictement positive — jamais une estimation.
///
/// ⚠️⚠️ **QUELLES LIGNES D'ACHAT ?** Celles que le web connaît ou connaîtra ([lignesRetenues]) : les lignes des
/// achats reçus du serveur (`synced`) et celles des achats saisis ici et en attente d'envoi (`pending`, le serveur
/// les aura dès la synchronisation) — PAS celles d'un achat REFUSÉ par le serveur (`conflict`) : il n'existe que sur
/// ce poste, et le web ne le comptera jamais. Les lignes d'un achat retourné restent comptées, comme au web
/// (`PurchaseLine::where('product_id', …)` ne filtre rien).
class PmpService {
  const PmpService._();

  /// Lignes d'achat qui entrent au PMP : toutes, sauf celles d'un achat refusé par le serveur (`conflict`).
  static List<PurchaseLine> lignesRetenues(
    List<Purchase> achats,
    List<PurchaseLine> lignes,
  ) {
    final refuses = {
      for (final a in achats)
        if (a.syncStatus == SyncStatus.conflict) a.id,
    };
    return [
      for (final l in lignes)
        if (!refuses.contains(l.purchaseId)) l,
    ];
  }

  /// `Product::computePmp()` pour [produitId], sur [lignes] (déjà passées par [lignesRetenues]).
  static double? pmp(String produitId, List<PurchaseLine> lignes) {
    final du = lignes.where((l) => l.productId == produitId);
    final quantite = du.fold<double>(0, (t, l) => t + l.qty);
    if (quantite <= 0) return null;
    final cout = du.fold<double>(0, (t, l) => t + l.qty * l.unitPrice);
    return arrondi(cout / quantite, 2);
  }

  /// PMP de chaque produit qui en a un (les autres sont absents de la table : « — »).
  static Map<String, double> parProduit(List<PurchaseLine> lignes) {
    final quantites = <String, double>{};
    final couts = <String, double>{};
    for (final l in lignes) {
      quantites[l.productId] = (quantites[l.productId] ?? 0) + l.qty;
      couts[l.productId] = (couts[l.productId] ?? 0) + l.qty * l.unitPrice;
    }
    return {
      for (final MapEntry(key: produit, value: quantite) in quantites.entries)
        if (quantite > 0) produit: arrondi(couts[produit]! / quantite, 2),
    };
  }

  /// `round($valeur, $decimales)` de PHP : demi loin de zéro, après un pré-arrondi à 15 chiffres significatifs
  /// (1,005 → 1,01, là où l'arrondi binaire brut donnerait 1,00).
  static double arrondi(double valeur, int decimales) {
    var facteur = 1.0;
    for (var i = 0; i < decimales; i++) {
      facteur *= 10;
    }
    final echelle = double.parse((valeur * facteur).toStringAsPrecision(15));
    return echelle.round() / facteur;
  }

  /// `number_format($valeur, 0, ',', ' ')` de PHP : arrondi demi loin de zéro, milliers séparés par une espace,
  /// signe « - » conservé (« -1 500 »), jamais « -0 ».
  static String francs(double valeur) {
    final entier = arrondi(valeur, 0).round();
    final chiffres = entier.abs().toString();
    final groupes = <String>[];
    for (var i = chiffres.length; i > 0; i -= 3) {
      groupes.insert(0, chiffres.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${entier < 0 ? '-' : ''}${groupes.join(' ')}';
  }
}
