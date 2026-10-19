import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import 'pmp_service.dart';

/// Un mouvement du grand livre des stocks : descendu du serveur (`stock_movements`), ou PROJETÉ depuis une saisie
/// du poste encore en attente d'envoi ([enAttente]).
class MouvementStock {
  const MouvementStock({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.referenceType,
    required this.date,
    this.referenceId,
    this.reason,
    this.enAttente = false,
  });

  final String id;
  final String productId;

  /// `entree`, `sortie` ou `ajustement` ; la quantité est toujours positive.
  final String type;
  final double quantity;
  final String referenceType;
  final String? referenceId;
  final String? reason;

  /// `movement_date` du serveur (heure murale) ; pour une saisie en attente, la date que le serveur lui donnera.
  final DateTime date;

  /// Vrai pour une saisie du poste pas encore envoyée : le serveur ne la connaît pas encore.
  final bool enAttente;

  /// Signe du web : `type === 'sortie' ? -quantité : quantité` (un `ajustement` compte en entrée, comme
  /// `StockRotationService` et `EggStockLedgerService`).
  double get quantiteSignee => type == 'sortie' ? -quantity : quantity;
}

/// « Rotation du Stock » — `StockRotationService::pourLeMois()`.
class RotationStock {
  const RotationStock({
    required this.rotation,
    required this.cogs,
    required this.stockMoyen,
    required this.produitsSansPmp,
    required this.couverture,
  });

  /// `null` : stock moyen valorisable nul (ou aucun produit valorisable) — la carte du web dit alors « — ».
  final double? rotation;
  final double cogs;
  final double stockMoyen;
  final int produitsSansPmp;

  /// Part (%) des sorties de vente du mois portant un coût connu ; `null` sans aucune vente.
  final double? couverture;
}

/// Ticket U9 — LE GRAND LIVRE DES STOCKS AU POSTE, ET LES FORMULES DU WEB QUI LE LISENT.
///
/// Le web calcule « Rotation du Stock » (`StockRotationService`), « Écarts d'Inventaire » (`GestionStocks`), le
/// Journal des Mouvements et le Tableau 3 de la ponte (`EggStockLedgerService`) sur `stock_movements`. Ce journal
/// descend au poste depuis U9 ; chaque formule est transposée ICI, une fois, et les écrans la lisent.
///
/// ## ⚠️⚠️ RÈGLE DES SAISIES EN ATTENTE (`pending`) — décidée au ticket U9
///
/// Un mouvement né d'une saisie du poste n'existe dans `stock_movements` du serveur qu'APRÈS l'envoi. La règle est
/// celle du Tableau de bord (U8) : le poste compte ce que le web compte (`synced`) PLUS ce qui part vers lui
/// (`pending`) ; une saisie REFUSÉE (`conflict`) ne compte nulle part — le web ne la connaîtra jamais.
///
///  - **Ce que le web compte** : les mouvements DESCENDUS, tels quels.
///  - **Ce qui part** : chaque saisie `pending` est PROJETÉE en mouvement selon la règle exacte du serveur qui la
///    recevra ([projeter]) — jamais écrite dans la table, recalculée à chaque lecture :
///      * ajustement d'inventaire (`stock_adjustments`) → son type, sa quantité, son motif de référence et son motif,
///        `reference_id` = la ligne du poste (`pushStockAdjustments`) ; DATÉ DE L'INSTANT PRÉSENT : le serveur le
///        rejoue par `AdjustStockAction` sans date, donc à sa réception — au plus tôt maintenant ;
///      * vente → une sortie `sale` par ligne, datée de la vente (`sold_at`, ticket 15.30), `reference_id` = la vente ;
///      * achat → une entrée `purchase` par ligne, à l'instant présent (`RecordPurchaseAction` ne date pas le
///        mouvement), `reference_id` = l'achat ;
///      * fiche de ponte NOUVELLE d'une bande avicole au stade ponte → une entrée `daily_entry` de
///        ⌊max(0, OR − OF) ÷ 30⌋ plateaux au jour de la fiche (`RecordEggProductionStockAction`), `reference_id` =
///        la fiche ;
///      * retour fournisseur → une sortie `purchase_return` par ligne de l'achat retourné, au jour du retour
///        (`PurchaseReturnService`).
///  - **⚠️⚠️ Jamais deux fois.** Une projection est RETIRÉE dès qu'un mouvement descendu porte le même
///    (`reference_type`, `reference_id`) : c'est la trace que le serveur l'a rejouée (renvoi sans accusé de
///    réception compris). Une saisie acquittée (`synced`) n'est plus projetée : le serveur l'a, son mouvement
///    descend. Pour un ajustement, au TIRAGE DE CONFIRMATION qui suit l'envoi (les écarts ne manquent jamais) ;
///    pour une vente, un achat, une fiche, au tirage suivant (synchronisation automatique, 15 min par défaut) —
///    entre les deux, ce mouvement manque à la rotation et au Tableau 3, jamais compté deux fois. Projeter aussi les
///    pièces acquittées serait pire : une pièce ancienne dont le serveur n'a gardé aucun mouvement (fiche d'avant
///    14.59, ajustement d'avant 14.74) serait comptée pour toujours.
///  - **Non projetés, et dits** : les naissances, morts et dons d'une fiche en attente
///    (`SyncLotProductionStockAction` : `reference_id` = la BANDE et calcul par ÉCART avec la version que le serveur
///    détient, que le poste n'a pas). Ils touchent le produit rattaché à la bande — des sujets vivants, sans PMP —
///    et entrent au journal à l'envoi.
class JournalStocks {
  const JournalStocks(this.mouvements);

  /// Mouvements descendus + saisies en attente projetées.
  final List<MouvementStock> mouvements;

  /// `GestionStocks::TYPES_ECART_INVENTAIRE` : l'écran du web (`adjustment`) et le poste (`inventaire`).
  static const typesEcartInventaire = {'adjustment', 'inventaire'};

  /// `EggStockLedgerService::OEUFS_PAR_PLATEAU`.
  static const oeufsParPlateau = 30;

  static Future<JournalStocks> charger(
    AppDatabase db, {
    required DateTime maintenant,
  }) async {
    final enAttente = SyncStatus.pending;
    return JournalStocks(
      projeter(
        descendus: await db.select(db.stockMovements).get(),
        ajustements: await (db.select(
          db.stockAdjustments,
        )..where((t) => t.syncStatus.equalsValue(enAttente))).get(),
        ventes: await (db.select(
          db.sales,
        )..where((t) => t.syncStatus.equalsValue(enAttente))).get(),
        lignesDeVente: await db.select(db.saleLines).get(),
        achats: await db.select(db.purchases).get(),
        lignesDAchat: await db.select(db.purchaseLines).get(),
        retours: await (db.select(
          db.purchaseReturns,
        )..where((t) => t.syncStatus.equalsValue(enAttente))).get(),
        fiches: await (db.select(
          db.livestockDailyEntries,
        )..where((t) => t.syncStatus.equalsValue(enAttente))).get(),
        bandes: await db.select(db.livestockLots).get(),
        produits: await db.select(db.products).get(),
        maintenant: maintenant,
      ),
    );
  }

  /// Mouvements descendus + projection des saisies EN ATTENTE (règle ci-dessus). Les listes de saisies peuvent
  /// contenir d'autres statuts : seules les `pending` sont projetées.
  static List<MouvementStock> projeter({
    required List<StockMovement> descendus,
    required List<StockAdjustment> ajustements,
    required List<Sale> ventes,
    required List<SaleLine> lignesDeVente,
    required List<Purchase> achats,
    required List<PurchaseLine> lignesDAchat,
    required List<RetourFournisseur> retours,
    required List<LivestockDailyEntry> fiches,
    required List<LivestockLot> bandes,
    required List<Product> produits,
    required DateTime maintenant,
  }) {
    final resultat = [
      for (final m in descendus)
        MouvementStock(
          id: m.id,
          productId: m.productId,
          type: m.type,
          quantity: m.quantity,
          referenceType: m.referenceType,
          referenceId: m.referenceId,
          reason: m.reason,
          date: m.movementDate,
        ),
    ];
    // (type de référence, pièce) déjà rejoués par le serveur et redescendus.
    final rejoues = {
      for (final m in descendus)
        if (m.referenceId != null) '${m.referenceType}|${m.referenceId}',
    };
    final connus = {for (final p in produits) p.id};
    bool enAttente(SyncStatus s) => s == SyncStatus.pending;
    void projette(MouvementStock m) {
      if (!rejoues.contains('${m.referenceType}|${m.referenceId}')) {
        resultat.add(m);
      }
    }

    for (final a in ajustements) {
      if (!enAttente(a.syncStatus)) continue;
      projette(
        MouvementStock(
          id: 'attente-ajustement-${a.id}',
          productId: a.productId,
          type: a.type,
          quantity: a.quantity,
          referenceType: a.referenceType,
          referenceId: a.id,
          reason: a.reason,
          date: maintenant,
          enAttente: true,
        ),
      );
    }

    final ventesEnAttente = {
      for (final v in ventes)
        if (enAttente(v.syncStatus)) v.id: v,
    };
    for (final l in lignesDeVente) {
      final vente = ventesEnAttente[l.saleId];
      // `Product::find()` : une ligne d'un produit inconnu ne bouge aucun stock.
      if (vente == null || !connus.contains(l.productId)) continue;
      projette(
        MouvementStock(
          id: 'attente-vente-${l.id}',
          productId: l.productId,
          type: 'sortie',
          quantity: l.qty.abs(),
          referenceType: 'sale',
          referenceId: vente.id,
          date: vente.soldAt,
          enAttente: true,
        ),
      );
    }

    final achatsEnAttente = {
      for (final a in achats)
        if (enAttente(a.syncStatus)) a.id,
    };
    for (final l in lignesDAchat) {
      if (!achatsEnAttente.contains(l.purchaseId) ||
          !connus.contains(l.productId)) {
        continue;
      }
      final entree = l.qty >= 0;
      projette(
        MouvementStock(
          id: 'attente-achat-${l.id}',
          productId: l.productId,
          type: entree ? 'entree' : 'sortie',
          quantity: l.qty.abs(),
          referenceType: 'purchase',
          referenceId: l.purchaseId,
          date: maintenant,
          enAttente: true,
        ),
      );
    }

    for (final r in retours) {
      if (!enAttente(r.syncStatus)) continue;
      for (final l in lignesDAchat.where((l) => l.purchaseId == r.purchaseId)) {
        if (!connus.contains(l.productId)) continue;
        projette(
          MouvementStock(
            id: 'attente-retour-${r.id}-${l.id}',
            productId: l.productId,
            type: 'sortie',
            quantity: l.qty.abs(),
            referenceType: 'purchase_return',
            referenceId: r.id,
            reason: r.reason,
            date: DateTime(
              r.returnDate.year,
              r.returnDate.month,
              r.returnDate.day,
              maintenant.hour,
              maintenant.minute,
              maintenant.second,
            ),
            enAttente: true,
          ),
        );
      }
    }

    final oeufs = produitOeufs(produits);
    final bandeDe = {for (final b in bandes) b.id: b};
    if (oeufs != null) {
      for (final f in fiches) {
        if (!enAttente(f.syncStatus)) continue;
        final bande = bandeDe[f.lotId];
        // ⚠️ Œufs de TABLE uniquement : aviculture au stade ponte (garde-fou de 14.59).
        if (bande == null ||
            bande.stage != 'ponte' ||
            bande.speciesCode != 'aviculture') {
          continue;
        }
        final commercialisables = (f.ponteTotal ?? 0) - (f.ponteCasses ?? 0);
        final plateaux =
            (commercialisables < 0 ? 0 : commercialisables) ~/ oeufsParPlateau;
        if (plateaux <= 0) continue;
        projette(
          MouvementStock(
            id: 'attente-ponte-${f.id}',
            productId: oeufs.id,
            type: 'entree',
            quantity: plateaux.toDouble(),
            referenceType: 'daily_entry',
            referenceId: f.id,
            date: jour(f.entryDate),
            enAttente: true,
          ),
        );
      }
    }

    return resultat;
  }

  /// Libellé du motif d'un mouvement — `GestionStocks::referenceLabel()` (défaut : `ucfirst($type)`).
  static String libelleReference(String type) => switch (type) {
    'sale' => 'Vente',
    'purchase' => 'Achat',
    'purchase_return' => 'Retour Fournisseur',
    'credit_note' => 'Retour Client',
    'transformation' => 'Transformation',
    'daily_entry' => 'Production',
    'manual_addition' => 'Ajout Manuel',
    'adjustment' => 'Ajustement',
    _ => type.isEmpty ? type : '${type[0].toUpperCase()}${type.substring(1)}',
  };

  /// Le jour d'un instant : ce que compare `whereDate` au web.
  static DateTime jour(DateTime d) => DateTime(d.year, d.month, d.day);

  /// `EggStockLedgerService::eggProduct()` : le PREMIER produit, par nom (collation du serveur), dont le libellé normalisé (minuscules,
  /// « œ » → « oe ») contient « oeufs » — tous les produits, archivés compris, comme le web.
  static Product? produitOeufs(List<Product> produits) {
    final tries = [...produits]
      ..sort((a, b) => comparerCommeLeServeur(a.name, b.name));
    for (final p in tries) {
      if (p.name.toLowerCase().replaceAll('œ', 'oe').contains('oeufs')) {
        return p;
      }
    }
    return null;
  }

  // ── Gestion des Stocks ────────────────────────────────────────────────────

  /// « Écarts d'Inventaire » — `GestionStocks::getKpisProperty()` : `round(Σ quantité signée × PMP)` sur les
  /// mouvements d'écart d'inventaire du MOIS de [maintenant], un produit sans PMP comptant pour 0.
  double ecartsDuMois(Map<String, double> pmp, DateTime maintenant) {
    var somme = 0.0;
    for (final m in mouvements) {
      if (!typesEcartInventaire.contains(m.referenceType) ||
          m.date.year != maintenant.year ||
          m.date.month != maintenant.month) {
        continue;
      }
      final p = pmp[m.productId];
      if (p != null) somme += m.quantiteSignee * p;
    }
    return PmpService.arrondi(somme, 0);
  }

  /// Journal des Mouvements du web : les 100 derniers, du plus récent au plus ancien.
  List<MouvementStock> derniers([int nombre = 100]) {
    final tries = [...mouvements]..sort((a, b) => b.date.compareTo(a.date));
    return tries.take(nombre).toList();
  }

  /// « Rotation du Stock » — `StockRotationService::pourLeMois()` du mois de [maintenant].
  ///
  ///   Rotation = COGS du mois ÷ stock moyen ; stock moyen = (valeur la veille du 1er + valeur au dernier jour) ÷ 2.
  ///   COGS = sorties de VENTE seules × PMP ; valeurs reconstruites depuis le journal, quantité négative = 0.
  ///   Périmètre : produits ACTIFS dont le PMP est connu et strictement positif ; les autres sont comptés.
  RotationStock rotation({
    required List<Product> produits,
    required Map<String, double> pmp,
    required DateTime maintenant,
  }) {
    final valorisables = <String, double>{};
    var sansPmp = 0;
    for (final p in produits.where((p) => p.isActive)) {
      final valeur = pmp[p.id];
      if (valeur == null || valeur <= 0) {
        sansPmp++;
        continue;
      }
      valorisables[p.id] = valeur;
    }
    if (valorisables.isEmpty) {
      return RotationStock(
        rotation: null,
        cogs: 0,
        stockMoyen: 0,
        produitsSansPmp: sansPmp,
        couverture: null,
      );
    }

    final debut = DateTime(maintenant.year, maintenant.month);
    final fin = DateTime(maintenant.year, maintenant.month + 1, 0);
    bool duMois(MouvementStock m) {
      final j = jour(m.date);
      return !j.isBefore(debut) && !j.isAfter(fin);
    }

    bool venteDuMois(MouvementStock m) =>
        m.type == 'sortie' && m.referenceType == 'sale' && duMois(m);

    final quantitesVendues = <String, double>{};
    for (final m in mouvements.where(venteDuMois)) {
      if (!valorisables.containsKey(m.productId)) continue;
      quantitesVendues[m.productId] =
          (quantitesVendues[m.productId] ?? 0) + m.quantity;
    }
    var cogs = 0.0;
    quantitesVendues.forEach((p, q) => cogs += q * valorisables[p]!);
    cogs = PmpService.arrondi(cogs, 2);

    double valeurAu(DateTime date) {
      final soldes = <String, double>{};
      for (final m in mouvements) {
        if (!valorisables.containsKey(m.productId) ||
            jour(m.date).isAfter(date)) {
          continue;
        }
        soldes[m.productId] = (soldes[m.productId] ?? 0) + m.quantiteSignee;
      }
      var total = 0.0;
      soldes.forEach(
        (p, solde) => total += (solde < 0 ? 0 : solde) * valorisables[p]!,
      );
      return PmpService.arrondi(total, 2);
    }

    // `$debut->subDay()` : la veille du 1er (jour 0 du mois = dernier jour du mois précédent).
    final valeurDebut = valeurAu(DateTime(maintenant.year, maintenant.month, 0));
    final valeurFin = valeurAu(fin);
    final stockMoyen = PmpService.arrondi((valeurDebut + valeurFin) / 2, 2);

    final ventes = mouvements.where(venteDuMois).toList();
    final couverture = ventes.isEmpty
        ? null
        : PmpService.arrondi(
            100 *
                ventes
                    .where((m) => valorisables.containsKey(m.productId))
                    .length /
                ventes.length,
            1,
          );

    return RotationStock(
      rotation: stockMoyen > 0
          ? PmpService.arrondi(cogs / stockMoyen, 2)
          : null,
      cogs: cogs,
      stockMoyen: stockMoyen,
      produitsSansPmp: sansPmp,
      couverture: couverture,
    );
  }

  // ── Grand livre des œufs (Tableau 3 de la ponte) ──────────────────────────

  /// `EggStockLedgerService::stockAvant($date)` : solde du produit [produitId] strictement AVANT le jour [date]
  /// (entrées = tout ce qui n'est pas une sortie), arrondi à 2 décimales. Sans produit œufs : 0.
  double stockAvant(String? produitId, DateTime date) {
    if (produitId == null) return 0;
    final borne = jour(date);
    var solde = 0.0;
    for (final m in mouvements) {
      if (m.productId == produitId && jour(m.date).isBefore(borne)) {
        solde += m.quantiteSignee;
      }
    }
    return PmpService.arrondi(solde, 2);
  }

  /// `EggStockLedgerService::ventesDu($date)` : sorties de VENTE du jour (ni casse ni ajustement), arrondi à 2.
  double ventesDu(String? produitId, DateTime date) {
    if (produitId == null) return 0;
    final j = jour(date);
    var total = 0.0;
    for (final m in mouvements) {
      if (m.productId == produitId &&
          m.type == 'sortie' &&
          m.referenceType == 'sale' &&
          jour(m.date) == j) {
        total += m.quantity;
      }
    }
    return PmpService.arrondi(total, 2);
  }

  /// `EggStockLedgerService::ligne($date, $commercialisables)` : SRH, TS = SRH + plateaux du jour, OS, Stock Final
  /// = TS − OS (jamais borné), et le vrac du jour.
  LigneGrandLivreOeufs ligneOeufs(
    String? produitId,
    DateTime date,
    int commercialisables,
  ) {
    final oeufs = commercialisables < 0 ? 0 : commercialisables;
    final plateaux = oeufs ~/ oeufsParPlateau;
    final srh = stockAvant(produitId, date);
    final ts = srh + plateaux;
    final os = ventesDu(produitId, date);
    return LigneGrandLivreOeufs(
      srh: srh,
      ts: ts,
      os: os,
      stockFinal: ts - os,
      plateaux: plateaux,
      vrac: oeufs % oeufsParPlateau,
    );
  }
}

/// Une ligne du grand livre des œufs (`EggStockLedgerService::ligne`), en PLATEAUX — soldes de FERME.
class LigneGrandLivreOeufs {
  const LigneGrandLivreOeufs({
    required this.srh,
    required this.ts,
    required this.os,
    required this.stockFinal,
    required this.plateaux,
    required this.vrac,
  });

  final double srh;
  final double ts;
  final double os;
  final double stockFinal;
  final int plateaux;
  final int vrac;
}
