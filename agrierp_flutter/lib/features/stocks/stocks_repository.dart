import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import 'journal_stocks.dart';
import 'pmp_service.dart';

/// Une ligne du tableau « Tableau & Valorisation » — une ligne de `GestionStocks::stockRowsRaw()`.
class LigneStock {
  const LigneStock({required this.produit, required this.categorie, this.pmp});

  final Product produit;

  /// `$row['product']->category?->label` : vide (et non « — ») pour un produit sans catégorie, comme le Blade.
  final String categorie;

  /// PMP unitaire du produit — `Product::computePmp()` du web, calculé par [PmpService] sur les lignes d'achat
  /// descendues au poste depuis U4 (ticket U8). `null` (« — ») pour un produit jamais acheté (sujets nés à la
  /// ferme, œufs) : jamais une estimation à partir du prix de VENTE, qui donnerait une valorisation supérieure au
  /// coût et gonflerait l'actif.
  final double? pmp;

  /// Valeur de la ligne, comme `GestionStocks::stockRowsRaw()` : `round(Product::valeurStock())`, soit
  /// `round(round(max(0, stock) × PMP, 2))` — le stock NÉGATIF est valorisé à zéro (ticket 14.30 : un actif ne
  /// peut pas être négatif) ; `null` (« — ») sans PMP.
  double? get valeur => pmp == null
      ? null
      : PmpService.arrondi(
          PmpService.arrondi(
            (produit.stockQty < 0 ? 0 : produit.stockQty) * pmp!,
            2,
          ),
          0,
        );

  /// 🔴→✅ Ticket U9 — `'urgence' => $product->alert_threshold > 0 && $product->stock_qty <= $product->alert_threshold`.
  /// Un seuil NUL (ou absent) ne déclenche rien au web ; le poste comptait « Sous seuil » tout produit à zéro dont le
  /// seuil valait 0.
  bool get urgence =>
      (produit.alertThreshold ?? 0) > 0 &&
      produit.stockQty <= produit.alertThreshold!;

  /// Règle du CATALOGUE PRODUITS (`Product::is_stock_low` du web, `stock_qty <= alert_threshold`), lue par
  /// `CatalogueProduitsScreen` : ce n'est PAS l'urgence de Gestion des Stocks ([urgence]).
  bool get sousSeuil =>
      produit.alertThreshold != null &&
      produit.stockQty <= produit.alertThreshold!;

  /// ⚠️ **UN STOCK NÉGATIF N'EST PAS UNE FRAUDE** : c'est le signe d'une ENTRÉE NON SAISIE (production ou achat pas
  /// encore enregistré), régularisable par un ajustement d'inventaire — `Product::stockEstNegatif()` (ticket 14.30).
  /// Le Blade l'écrit dans la cellule Stock (« Entrée non saisie »), pas dans la pastille d'urgence.
  bool get stockNegatif => produit.stockQty < 0;
}

/// Une ligne du « Journal des Mouvements » du web : un mouvement du grand livre (descendu ou en attente d'envoi).
class LigneJournal {
  const LigneJournal({required this.mouvement, this.designation, this.pmp});

  final MouvementStock mouvement;

  /// `$movement->product?->name` ; `null` pour un produit inconnu du poste.
  final String? designation;

  /// PMP du produit ([PmpService]), `null` s'il n'en a pas.
  final double? pmp;

  /// Colonne « Valeur » du Blade : `abs(quantité) × PMP`, « — » sans PMP.
  double? get valeur => pmp == null ? null : mouvement.quantity.abs() * pmp!;

  /// « Date / Heure » : `movement_date->format('d/m/Y H:i')`.
  String get dateHeure {
    final d = mouvement.date;
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}/${d.year} ${deux(d.hour)}:${deux(d.minute)}';
  }

  /// « Référence » : `strtoupper(substr($reference_id, 0, 8))`, « — » sans pièce.
  String get reference {
    final r = mouvement.referenceId;
    if (r == null || r.isEmpty) return '—';
    return (r.length > 8 ? r.substring(0, 8) : r).toUpperCase();
  }

  /// « Motif » : `referenceLabel($reference_type)` puis « — motif » s'il y en a un.
  String get motif {
    final raison = mouvement.reason;
    return '${JournalStocks.libelleReference(mouvement.referenceType)}'
        '${raison == null || raison.isEmpty ? '' : ' — $raison'}';
  }

  /// « Quantité » : `-` pour une sortie, `+` sinon, puis la quantité au format du Blade.
  String get quantite =>
      '${mouvement.type == 'sortie' ? '-' : '+'}${PmpService.quantite(mouvement.quantity)}';

  /// « Valeur » : `number_format(abs(quantité) × PMP, 0, ',', ' ').' FCFA'`, « — » sans PMP.
  String get valeurAffichee =>
      valeur == null ? '—' : '${PmpService.francs(valeur!)} FCFA';
}

class DonneesStocks {
  const DonneesStocks({
    required this.lignes,
    required this.journal,
    required this.categories,
    required this.ecartsDuMois,
    required this.rotation,
    this.maintenant,
  });

  /// Produits ACTIFS triés par NOM (`Product::where('is_active', true)->orderBy('name')`).
  final List<LigneStock> lignes;

  /// Les 100 derniers mouvements, du plus récent au plus ancien (`GestionStocks::getMovementsProperty()`).
  final List<LigneJournal> journal;

  /// Catégories ACTIVES triées par libellé (`ProductCategory::where('is_active', true)->orderBy('label')`) : le
  /// filtre « Catégorie » porte sur l'identifiant, comme `$categoryFilter`.
  final List<ProductCategory> categories;

  /// « Écarts d'Inventaire » — [JournalStocks.ecartsDuMois] : écarts du MOIS saisis au web, sur ce poste ou sur un
  /// autre (`adjustment` et `inventaire`), plus ceux de ce poste en attente d'envoi.
  final double ecartsDuMois;

  /// « Rotation du Stock » — [JournalStocks.rotation].
  final RotationStock rotation;

  /// Instant du chargement : borne le mois des « Écarts d'Inventaire » et de la rotation.
  final DateTime? maintenant;

  /// « Alertes de Seuil » : produits actifs en urgence (`$rows->filter(fn ($r) => $r['urgence'])->count()`).
  int get alertesDeSeuil => lignes.where((l) => l.urgence).length;

  /// « Valorisation Stocks » — `GestionStocks::getKpisProperty()` : Σ des valeurs de TOUS les produits actifs (la
  /// recherche et le filtre de catégorie ne s'appliquent pas aux KPI), un produit sans PMP comptant pour 0 (il est
  /// « exclu de la Valorisation Stocks plutôt que remplacé par une estimation inventée »). Le web affiche donc
  /// toujours un montant, « 0 FCFA » compris : le poste aussi.
  double get valorisation =>
      lignes.fold<double>(0, (t, l) => t + (l.valeur ?? 0));
}

/// Lectures et écritures de `prototype_html/gestion-stocks.html`.
///
/// ⚠️⚠️ **AUCUN ÉCRAN NE CRÉAIT D'AJUSTEMENT.** `stock_adjustments` est
/// poussée par le moteur de synchronisation depuis le ticket F0.3, et le
/// serveur la rejoue par son action d'ajustement — mais **rien au poste ne
/// l'alimentait**. Le canal d'envoi existait sans producteur : un inventaire
/// physique constaté au magasin n'avait aucun moyen d'être saisi hors ligne.
///
/// 🔴→✅ **TICKET U9 — LE JOURNAL DES MOUVEMENTS EST CELUI DU WEB.** Le grand
/// livre `stock_movements` (ventes, achats, production, ajustements de la
/// ferme entière) descend au poste ; les saisies de ce poste encore en attente
/// d'envoi y sont projetées par [JournalStocks] (règle des `pending`).
class StocksRepository {
  StocksRepository({
    required this.database,
    this.deviceId = 'poste',
    Uuid? uuid,
    DateTime Function()? horloge,
  }) : _uuid = uuid ?? const Uuid(),
       _horloge = horloge ?? DateTime.now;

  final AppDatabase database;
  final String deviceId;
  final Uuid _uuid;

  /// Horloge injectée (tests) : borne le mois des « Écarts d'Inventaire ».
  final DateTime Function() _horloge;

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
    final maintenant = _horloge();
    final tousProduits = await database.select(database.products).get();
    final categories = await database.select(database.productCategories).get();
    // Ticket U8 — PMP sur les lignes d'achat de la ferme (descendues depuis U4), règle de [PmpService].
    final pmpDe = PmpService.parProduit(
      PmpService.lignesRetenues(
        await database.select(database.purchases).get(),
        await database.select(database.purchaseLines).get(),
      ),
    );
    // Ticket U9 — grand livre descendu + saisies en attente projetées.
    final journal = await JournalStocks.charger(
      database,
      maintenant: maintenant,
    );

    final libelleDe = {for (final c in categories) c.id: c.label};
    final nomDe = {for (final p in tousProduits) p.id: p.name};
    final actifs =
        tousProduits.where((p) => p.isActive).toList()
          ..sort((a, b) => comparerCommeLeServeur(a.name, b.name));

    return DonneesStocks(
      maintenant: maintenant,
      lignes: [
        for (final p in actifs)
          LigneStock(
            produit: p,
            categorie: libelleDe[p.categoryId] ?? '',
            pmp: pmpDe[p.id],
          ),
      ],
      journal: [
        for (final m in journal.derniers())
          LigneJournal(
            mouvement: m,
            designation: nomDe[m.productId],
            pmp: pmpDe[m.productId],
          ),
      ],
      categories:
          categories.where((c) => c.isActive).toList()
            ..sort((a, b) => comparerCommeLeServeur(a.label, b.label)),
      ecartsDuMois: journal.ecartsDuMois(pmpDe, maintenant),
      rotation: journal.rotation(
        produits: tousProduits,
        pmp: pmpDe,
        maintenant: maintenant,
      ),
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
