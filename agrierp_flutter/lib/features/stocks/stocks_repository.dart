import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/export/document_officiel.dart';
import '../../core/temps/heure_benin.dart';
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
       _horloge = horloge ?? HeureBenin.maintenant;

  final AppDatabase database;
  final String deviceId;
  final Uuid _uuid;

  /// Horloge injectée (tests) : borne le mois des « Écarts d'Inventaire ».
  final DateTime Function() _horloge;

  /// Ticket U11 — les deux `<optgroup>` du Blade, dans son ordre : « Écart négatif (perte) » (cinq motifs) puis
  /// « Écart positif (surplus) » (trois). Le poste les présentait à plat, et sa note parlait de « quatre + quatre ».
  /// Le groupe guide le choix sans le restreindre : le web accepte tout motif quel que soit le sens de l'écart.
  static const motifsPerte = [
    'Casse de matériel',
    'Vol / Disparition',
    'Mortalité non déclarée',
    "Erreur de pesée d'approvisionnement",
    'Péremption dépassée',
  ];

  static const motifsSurplus = [
    'Naissance non répertoriée',
    'Surplus de livraison',
    "Erreur d'inventaire antérieur",
  ];

  /// Les huit motifs d'écart, dans l'ordre du Blade.
  static const motifs = [...motifsPerte, ...motifsSurplus];

  /// `GestionStocks::getStockRowsProperty()` : recherche (`str_contains` en minuscules sur le nom OU le SKU, texte
  /// tel que saisi) puis filtre de catégorie (identifiant). Le tableau ET l'export lisent cette liste.
  static List<LigneStock> filtrer(
    List<LigneStock> lignes, {
    required String recherche,
    required String categorie,
  }) {
    final terme = recherche.toLowerCase();
    return [
      for (final l in lignes)
        if ((terme.isEmpty ||
                l.produit.name.toLowerCase().contains(terme) ||
                l.produit.sku.toLowerCase().contains(terme)) &&
            (categorie.isEmpty || l.produit.categoryId == categorie))
          l,
    ];
  }

  /// Ticket U10 — `GestionStocks::getAdjDiffProperty()` : 0 sans produit ou sans stock physique saisi, sinon
  /// `round(physique − théorique, 2)`. Jamais « — » : le web affiche « 0 ».
  static double ecartCalcule({double? theorique, double? physique}) =>
      theorique == null || physique == null
      ? 0
      : PmpService.arrondi(physique - theorique, 2);

  /// `{{ $adjDiff > 0 ? '+' : '' }}{{ $adjDiff }}` : « +7 », « -5 », « 0 », « 2.5 » (flottant PHP).
  static String ecartAffiche(double ecart) =>
      '${ecart > 0 ? '+' : ''}${PmpService.flottant(ecart)}';

  /// 🔴→✅ Ticket U11 — RÈGLES DE L'ONGLET « AJUSTEMENT / CORRECTION » DU WEB (`GestionStocks::validateAdjustment()`),
  /// messages de `lang/fr/validation.php` avec les noms de champ du web (`adjProductId` → « produit »,
  /// `adjPhysical` → « stock physique constaté ») : `adjProductId` `required|exists:products,id`, `adjPhysical`
  /// `required|numeric|min:0`. Rend les erreurs par champ (`produit`, `physique`), vide si tout est valable.
  ///
  /// ⚠️ **LE MOTIF N'EST PAS OBLIGATOIRE** : le web ne le valide pas (`$this->adjReason ?: null`). Le poste
  /// l'exigeait — un comptage sans motif choisi, accepté au web, était refusé ici.
  static Map<String, String> validerAjustement({
    required String? productId,
    required String physique,
    bool produitConnu = true,
  }) {
    final erreurs = <String, String>{};
    if (productId == null || productId.isEmpty) {
      erreurs['produit'] = 'Le champ produit est obligatoire.';
    } else if (!produitConnu) {
      erreurs['produit'] =
          "La valeur sélectionnée pour le champ produit n'existe pas.";
    }
    final texte = physique.trim();
    final valeur = double.tryParse(texte);
    if (texte.isEmpty) {
      erreurs['physique'] =
          'Le champ stock physique constaté est obligatoire.';
    } else if (valeur == null || !valeur.isFinite) {
      erreurs['physique'] =
          'Le champ stock physique constaté doit être un nombre.';
    } else if (valeur < 0) {
      erreurs['physique'] =
          'Le champ stock physique constaté doit être au moins égal à 0.';
    }
    return erreurs;
  }

  /// `validateAdjustment()` : un écart nul (`$diff == 0`, écart ARRONDI au centième) n'écrit rien et le dit.
  static const messageEcartNul = 'Aucun écart détecté — rien à ajuster.';

  /// 🔴→✅ Ticket U11 — LE TOAST DU WEB APRÈS UN AJUSTEMENT, branche pour branche (`validateAdjustment()`) :
  ///
  ///   écart positif → « Ajustement enregistré — écart positif de N. Aucune écriture : … » (succès) ;
  ///   perte chiffrée → « Ajustement enregistré — perte de X FCFA portée en charge exceptionnelle (débit 657 /
  ///     crédit 601). » (avertissement), X = `number_format(round(|écart| × PMP, 2), 0, ',', ' ')`, la règle de
  ///     `RecordStockAdjustmentEntryAction` (PMP connu et positif, valeur ≥ 0,01, comptes 657 et 601 au plan) ;
  ///   sinon → « … ATTENTION : perte non comptabilisée … » (avertissement).
  ///
  /// ⚠️ **AU POSTE, LA PERTE EST CHIFFRÉE SUR SON ÉTAT LOCAL.** L'écriture, elle, est passée par le SERVEUR à la
  /// réception (`pushStockAdjustments` → `RecordStockAdjustmentEntryAction`), sur SON état : si le stock ou le PMP
  /// du produit ont bougé entre-temps (vente ou achat saisis ailleurs), le montant écrit peut différer de celui
  /// annoncé ici. [comptesDePerte] `null` (plan comptable jamais tiré par ce compte) vaut « présents » : le plan
  /// SYSCOHADA du serveur les porte d'origine (`ChartOfAccountsSeeder`).
  static ({String message, bool avertissement}) messageAjustement({
    required double ecart,
    required double? pmp,
    required bool? comptesDePerte,
  }) {
    if (ecart > 0) {
      return (
        message:
            'Ajustement enregistré — écart positif de ${PmpService.flottant(ecart)}. Aucune écriture : un excédent '
            'signale une entrée non saisie, jamais un gain.',
        avertissement: false,
      );
    }
    final valeur = pmp == null || pmp <= 0
        ? null
        : PmpService.arrondi(ecart.abs() * pmp, 2);
    if (valeur != null && valeur >= 0.01 && comptesDePerte != false) {
      return (
        message:
            'Ajustement enregistré — perte de ${PmpService.francs(valeur)} FCFA portée en charge exceptionnelle '
            '(débit 657 / crédit 601).',
        avertissement: true,
      );
    }
    return (
      message:
          "Ajustement enregistré — ATTENTION : perte non comptabilisée (aucun coût d'achat connu pour ce produit, ou "
          'compte manquant). À régulariser au Journal Comptable.',
      avertissement: true,
    );
  }

  /// Les comptes 657 (charges exceptionnelles) et 601 (achats) existent-ils au plan comptable du poste ? `null` si
  /// le poste ne détient aucun plan comptable (table servie avec `view-comptabilite` seulement).
  Future<bool?> comptesDePerte() async {
    final comptes = await database.select(database.chartOfAccounts).get();
    if (comptes.isEmpty) return null;
    final codes = {for (final c in comptes) c.code};
    return codes.contains('657') && codes.contains('601');
  }

  /// 🔴→✅ Ticket U10 — « Exporter » : le document de `exportStocksPdf()` (vue `exports.gestion-stocks`), lignes
  /// FILTRÉES comme à l'écran. Titre « Gestion des Stocks — Tableau & Valorisation », sous-titre « État au
  /// jj/mm/aaaa », sept colonnes (sans « Actions »), cellules du Blade d'export : stock `number_format(…, 2, ',', ' ')`
  /// et unité, PMP et valeur en « … FCFA » ou « — », urgence « Oui » ou « — ».
  static DocumentOfficiel documentTableau(
    List<LigneStock> lignes,
    DateTime maintenant,
  ) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return DocumentOfficiel(
      titre: 'Gestion des Stocks — Tableau & Valorisation',
      fichier: 'stocks-{jour}.pdf',
      sousTitre:
          'État au ${deux(maintenant.day)}/${deux(maintenant.month)}/${maintenant.year}',
      entetes: const [
        'Code',
        'Désignation',
        'Catégorie',
        'Stock',
        'PMP Unit.',
        'Valeur',
        'Urgence',
      ],
      lignes: [
        if (lignes.isEmpty)
          const DonneesDocument([
            'Aucun produit ne correspond aux filtres actifs.',
            '',
            '',
            '',
            '',
            '',
            '',
          ]),
        for (final l in lignes)
          DonneesDocument([
            l.produit.sku,
            l.produit.name,
            l.categorie.isEmpty ? '—' : l.categorie,
            '${PmpService.nombre(l.produit.stockQty, 2)} ${l.produit.unit}',
            l.pmp == null ? '—' : '${PmpService.francs(l.pmp!)} FCFA',
            l.valeur == null ? '—' : '${PmpService.francs(l.valeur!)} FCFA',
            l.urgence ? 'Oui' : '—',
          ]),
      ],
    );
  }

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

  /// Ticket U10 — règles de la modale « Ajouter Stock » du web (`GestionStocks::submitAjouterStock()`), messages de
  /// `lang/fr/validation.php` avec les noms de champ du web (`addDate` → « date », `addProductId` → « produit »,
  /// `addQty` → « quantité ») : `addDate` `required|date`, `addProductId` `required|exists`, `addQty`
  /// `required|integer|min:1`. Rend les erreurs par champ (`date`, `produit`, `quantite`), vide si tout est valable.
  static Map<String, String> validerAjout({
    required DateTime? date,
    required String? productId,
    required String quantite,
  }) {
    final erreurs = <String, String>{};
    if (date == null) erreurs['date'] = 'Le champ date est obligatoire.';
    if (productId == null || productId.isEmpty) {
      erreurs['produit'] = 'Le champ produit est obligatoire.';
    }
    final texte = quantite.trim();
    if (texte.isEmpty) {
      erreurs['quantite'] = 'Le champ quantité est obligatoire.';
    } else {
      // `integer` de Laravel : « 20 » ou « 20.0 » passent, « 2.5 » ou « abc » non.
      final reel = double.tryParse(texte);
      if (reel == null || !reel.isFinite || reel != reel.truncateToDouble()) {
        erreurs['quantite'] = 'Le champ quantité doit être un nombre entier.';
      } else if (reel < 1) {
        erreurs['quantite'] = 'Le champ quantité doit être au moins égal à 1.';
      }
    }
    return erreurs;
  }

  /// 🔴→✅ Ticket U10 — « AJOUTER STOCK » (modale du web) : une ENTRÉE manuelle, écrite au poste en attente d'envoi.
  ///
  /// Le web passe par `AdjustStockAction::execute($product, $qty, 'manual_addition', null, Carbon::parse($addDate))` :
  /// le poste écrit le même FAIT dans `stock_adjustments` (`type = entree`, `reference_type = manual_addition`,
  /// `movement_date` = le jour choisi), et le serveur le rejoue par la même action, daté du même jour
  /// (`pushStockAdjustments`) — aucune écriture comptable, comme au web. Le stock local suit immédiatement, comme
  /// l'inventaire. [ArgumentError] porte le premier message de [validerAjout] (le web refuse de la même façon).
  Future<StockAdjustment> ajouterStock({
    required DateTime? date,
    required String? productId,
    required String quantite,
    DateTime? quand,
  }) async {
    final erreurs = validerAjout(
      date: date,
      productId: productId,
      quantite: quantite,
    );
    if (erreurs.isNotEmpty) throw ArgumentError(erreurs.values.first);

    final produit = await (database.select(
      database.products,
    )..where((t) => t.id.equals(productId!))).getSingleOrNull();
    // `exists:products,id` : « La valeur sélectionnée pour le champ produit n'existe pas. »
    if (produit == null) {
      throw ArgumentError(
        "La valeur sélectionnée pour le champ produit n'existe pas.",
      );
    }

    final qte = double.parse(quantite.trim());
    final id = _uuid.v4();
    final jour = DateTime(date!.year, date.month, date.day);

    await database.transaction(() async {
      await database
          .into(database.stockAdjustments)
          .insert(
            StockAdjustmentsCompanion.insert(
              id: id,
              deviceId: deviceId,
              syncStatus: const Value(SyncStatus.pending),
              // ⚠️ L'instant de la SAISIE (règle de `updatedAt`), pas le jour choisi.
              updatedAt: HeureBenin.versInstant(quand ?? _horloge()),
              productId: produit.id,
              type: 'entree',
              quantity: qte,
              referenceType: 'manual_addition',
              movementDate: jour,
            ),
          );

      await (database.update(database.products)
            ..where((t) => t.id.equals(produit.id)))
          .write(ProductsCompanion(stockQty: Value(produit.stockQty + qte)));
    });

    return (await (database.select(
      database.stockAdjustments,
    )..where((t) => t.id.equals(id))).getSingle());
  }

  /// Enregistre un écart d'inventaire et aligne le stock local sur le comptage.
  ///
  /// ⚠️⚠️ **LE SENS EST PORTÉ PAR `type`, JAMAIS PAR LE SIGNE DE LA
  /// QUANTITÉ.** C'est la convention du serveur, et sa validation refuse une
  /// quantité négative ou nulle. Envoyer −3 en « entrée » passerait le
  /// contrôle de sens et remonterait le stock au lieu de le baisser.
  ///
  /// ⚠️ **LE STOCK LOCAL SUIT IMMÉDIATEMENT.** C'est tout l'objet d'un
  /// inventaire : le comptage physique devient la vérité.
  ///
  /// 🔴→✅ **TICKET S-T10 — CE QUI PART, C'EST LE COMPTAGE, PAS L'ÉCART.** L'écart
  /// local se calcule contre le stock de CE poste, qui ignore une vente faite
  /// ailleurs et pas encore descendue : envoyé seul, il faisait décompter cette
  /// vente une seconde fois au serveur. La ligne garde donc la QUANTITÉ COMPTÉE
  /// ([StockAdjustment.countedQuantity]) et l'INSTANT du comptage
  /// (`movementDate`, heure murale du Bénin) ; le serveur calcule l'écart contre
  /// son grand livre à cet instant (règle du web) et le rejoue. `type` +
  /// `quantity` (écart local) restent pour l'affichage et pour un serveur
  /// ancien. Le poste se recale au tirage de confirmation qui suit l'acquittement
  /// (stock du produit et mouvement du serveur).
  Future<StockAdjustment> enregistrerEcart({
    required String productId,
    required double stockPhysique,
    required String motif,
    DateTime? quand,
  }) async {
    // Ticket S-T11 : l'instant du comptage en heure murale du Bénin.
    final maintenant = quand ?? _horloge();

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

    // Ticket U11 — le motif est FACULTATIF, comme au web (`$this->adjReason ?: null`) : plus de refus ici.

    final id = _uuid.v4();

    await database.transaction(() async {
      await database
          .into(database.stockAdjustments)
          .insert(
            StockAdjustmentsCompanion.insert(
              id: id,
              deviceId: deviceId,
              syncStatus: const Value(SyncStatus.pending),
              updatedAt: HeureBenin.versInstant(maintenant),
              productId: productId,
              type: ecart > 0 ? 'entree' : 'sortie',
              quantity: ecart.abs(),
              referenceType: 'inventaire',
              reason: Value(motif),
              movementDate: maintenant,
              countedQuantity: Value(stockPhysique),
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
