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

  /// Ticket U9 — `number_format($valeur, $decimales, $virgule, $milliers)` de PHP : arrondi demi loin de zéro,
  /// jamais « -0 » (PHP 8). Défauts = ceux du Blade de la ferme (`',', ' '`) ; `number_format($v, 1)` sans
  /// séparateurs s'écrit `nombre(v, 1, virgule: '.', milliers: ',')`.
  static String nombre(
    double valeur,
    int decimales, {
    String virgule = ',',
    String milliers = ' ',
  }) {
    final arrondie = arrondi(valeur, decimales);
    final morceaux = arrondie.abs().toStringAsFixed(decimales).split('.');
    final chiffres = morceaux[0];
    final groupes = <String>[];
    for (var i = chiffres.length; i > 0; i -= 3) {
      groupes.insert(0, chiffres.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    final negatif = arrondie < 0 && RegExp('[1-9]').hasMatch(morceaux.join());
    return '${negatif ? '-' : ''}${groupes.join(milliers)}'
        '${decimales > 0 ? '$virgule${morceaux[1]}' : ''}';
  }

  /// Ticket U9 — quantité du Blade de Gestion des Stocks :
  /// `rtrim(rtrim(number_format($q, 2, '.', ''), '0'), '.')` — « 12.5 », « 3.25 », « 150 », « -0.5 ».
  static String quantite(double valeur) {
    final texte = nombre(valeur, 2, virgule: '.', milliers: '');
    return texte.contains('.')
        ? texte
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '')
        : texte;
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

/// Clé de tri de `orderBy('name')` sous la collation du serveur (`utf8mb4_unicode_ci`) : insensible à la casse et
/// aux accents ; égalité départagée par le texte brut, pour un ordre stable.
int comparerCommeLeServeur(String a, String b) {
  String cle(String t) {
    const accents = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', //
      'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o', //
      'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ÿ': 'y', 'œ': 'oe', //
      'æ': 'ae',
    };
    final minuscules = t.toLowerCase();
    final sortie = StringBuffer();
    for (final c in minuscules.split('')) {
      sortie.write(accents[c] ?? c);
    }
    return sortie.toString();
  }

  final parCle = cle(a).compareTo(cle(b));
  return parCle != 0 ? parCle : a.compareTo(b);
}
