import 'package:drift/drift.dart' show OrderingTerm, OrderingMode;

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../elevage/production_oeufs_service.dart';

/// Une ligne de rapport : ses cellules, dans l'ordre des colonnes de la
/// maquette. Le tiret y est une VALEUR, pas une absence de cellule — c'est ce
/// qui garantit que le tableau garde toutes ses colonnes.
class LigneRapport {
  const LigneRapport(this.cellules);

  final List<String> cellules;
}

/// Position de trésorerie telle que le poste peut honnêtement la connaître.
///
/// ⚠️⚠️ **LE POSTE NE TIENT PAS DE SÉRIE JOURNALIÈRE, ET N'EN TIENDRA PAS.**
/// `treasury_accounts` ne porte qu'un **solde courant**, figé au dernier
/// tirage ; et `Expenses` le dit déjà en toutes lettres : « le poste ne tient
/// NI comptabilité NI solde de trésorerie faisant foi ».
///
/// Reconstituer la série depuis les lignes d'écriture de classe 5 serait pire
/// que de ne rien afficher : le poste ne détient que les écritures descendues
/// **depuis son dernier tirage**, et un cumul partiel donnerait un solde FAUX
/// sans rien signaler — en cassant au passage la règle « deux livres qui
/// doivent s'accorder ».
class PositionTresorerie {
  const PositionTresorerie({
    required this.caisse,
    required this.banque,
    required this.autres,
    required this.releveLe,
  });

  final double? caisse;
  final double? banque;

  /// ⚠️⚠️ **LE MOBILE MONEY N'EST PAS LA BANQUE.** Le serveur connaît trois
  /// types (`caisse`, `banque`, `mobile_money`). La maquette n'affiche que
  /// deux colonnes, et ses données de démonstration ont un Mobile Money à
  /// zéro — d'où un total qui semble valoir caisse + banque. Sur cette ferme,
  /// où le Mobile Money encaisse réellement, additionner deux colonnes sur
  /// trois donnerait un total qui MANQUE de l'argent sans le dire.
  final double? autres;

  /// Instant du dernier tirage. `null` : le poste n'a jamais reçu de solde.
  final DateTime? releveLe;

  bool get connue => releveLe != null && (caisse != null || banque != null);

  double? get total =>
      connue ? (caisse ?? 0) + (banque ?? 0) + (autres ?? 0) : null;
}

/// Les quatre indicateurs zootechniques du rapport d'élevage.
class IndicateursElevage {
  const IndicateursElevage({
    required this.productionTotale,
    required this.tauxPonteMoyen,
    required this.mortaliteHebdo,
    required this.chiffreAffaires,
  });

  final int productionTotale;
  final double? tauxPonteMoyen;
  final double? mortaliteHebdo;

  /// ⚠️ `null` — ET NON ZÉRO. `vente_montant` existe au serveur mais **ne
  /// figure pas dans la charge utile d'envoi des fiches** : le poste ne l'a
  /// jamais eu. Afficher « 0 FCFA » dirait « rien n'a été vendu » là où il
  /// faut lire « ce poste ne détient pas le montant ».
  final double? chiffreAffaires;
}

class DonneesRapports {
  const DonneesRapports({
    required this.du,
    required this.au,
    required this.recettes,
    required this.depenses,
    required this.totalRecettes,
    required this.totalDepenses,
    required this.tresorerie,
    required this.creances,
    required this.dettes,
    required this.elevageT1,
    required this.elevageT2,
    required this.elevageT3,
    required this.indicateurs,
    required this.stocks,
  });

  final DateTime du;
  final DateTime au;

  final List<LigneRapport> recettes;
  final List<LigneRapport> depenses;
  final double totalRecettes;
  final double totalDepenses;

  double get soldeNet => totalRecettes - totalDepenses;

  final PositionTresorerie tresorerie;
  final List<LigneRapport> creances;
  final List<LigneRapport> dettes;

  final List<LigneRapport> elevageT1;
  final List<LigneRapport> elevageT2;
  final List<LigneRapport> elevageT3;
  final IndicateursElevage indicateurs;

  final List<LigneRapport> stocks;
}

/// Lectures de `prototype_html/rapports-exports.html` et de ses six pages.
///
/// ⚠️⚠️ **CES RAPPORTS NE COUVRENT QUE CE QUE LE POSTE DÉTIENT, ET LE DISENT.**
/// Trois limites structurelles, toutes vérifiées dans le contrat de
/// synchronisation plutôt que supposées :
///
/// 1. **Les fiches d'élevage ne sont JAMAIS TIRÉES, seulement poussées.**
///    `livestock_daily_entries` ne figure pas dans les 36 absorbeurs du
///    tirage. Le rapport d'élevage porte donc les journées saisies **sur ce
///    poste**, jamais celles d'un autre — même règle que l'historique des
///    ventes, et pour la même raison.
/// 2. **L'envoi d'une fiche ne porte que onze champs sur la vingtaine du
///    serveur.** `effectif_m`, `effectif_f`, `effectif_sevres`,
///    `effectif_smeres`, `cat_eff_*`, `treatment_dose`, `symptomes`,
///    `vente_sexe` et `vente_montant` existent en base côté serveur mais
///    **ne quittent pas le poste** — donc n'y reviennent pas. Le Tableau 1 en
///    perd onze colonnes sur treize, le Tableau 2 cinq sur neuf. Elles restent
///    AFFICHÉES, avec un tiret : une colonne retirée ferait croire que la
///    maquette ne la demande pas.
/// 3. **Aucune série journalière de trésorerie** — voir [PositionTresorerie].
///
/// ⚠️ **LES FORMULES DE PONTE NE SONT PAS RÉÉCRITES ICI.** Elles vivent dans
/// `ProductionOeufsService`, où elles ont déjà été alignées sur le serveur
/// (taux divisé par l'effectif FINAL, commercialisables jamais négatifs,
/// plateau de 30). Les redériver pour un rapport ferait deux vérités pour un
/// même chiffre.
class RapportsRepository {
  RapportsRepository({required this.database});

  final AppDatabase database;

  Future<DonneesRapports> charger({
    required DateTime du,
    required DateTime au,
  }) async {
    // ⚠️ La borne haute est INCLUSIVE : « au 31/07 » doit contenir le 31/07
    // dans son entier, pas s'arrêter à minuit. Une vente de fin de journée
    // disparaîtrait sinon du rapport sans qu'on sache pourquoi.
    final debut = DateTime(du.year, du.month, du.day);
    final fin = DateTime(au.year, au.month, au.day, 23, 59, 59, 999);

    final ventes = await database.select(database.sales).get();
    final depenses = await database.select(database.expenses).get();
    final comptes = await database.select(database.treasuryAccounts).get();
    final etat = await database.etatDeSynchronisation();
    final clients = await database.select(database.customers).get();
    final creances = await database.select(database.receivables).get();
    final dettes = await database.select(database.payables).get();
    final fournisseurs = await database.select(database.suppliers).get();
    final produits = await database.select(database.products).get();
    final categories = await database.select(database.productCategories).get();
    final bandes = await database.select(database.livestockLots).get();
    final lignesDeVente = await database.select(database.saleLines).get();

    final fiches =
        await (database.select(database.livestockDailyEntries)..orderBy([
              (t) => OrderingTerm(
                expression: t.entryDate,
                mode: OrderingMode.desc,
              ),
            ]))
            .get();

    final dansLaPeriode = fiches
        .where((f) => !f.entryDate.isBefore(debut) && !f.entryDate.isAfter(fin))
        .toList();

    return DonneesRapports(
      du: debut,
      au: au,
      recettes: _recettes(ventes, debut, fin),
      depenses: _depenses(depenses, debut, fin),
      totalRecettes: _totalRecettes(ventes, debut, fin),
      totalDepenses: _totalDepenses(depenses, debut, fin),
      tresorerie: _tresorerie(comptes, etat),
      creances: _creances(creances, clients),
      dettes: _dettes(dettes, fournisseurs),
      elevageT1: _elevageRecensement(dansLaPeriode, bandes),
      elevageT2: _elevageMouvements(dansLaPeriode, bandes),
      elevageT3: _elevagePonte(
        fiches,
        dansLaPeriode,
        bandes,
        lignesDeVente,
        produits,
        ventes,
      ),
      indicateurs: _indicateurs(dansLaPeriode),
      stocks: _stocks(produits, categories),
    );
  }

  // ── Onglet 1 : Recettes et Dépenses ───────────────────────────────────────

  /// ⚠️ **UNE VENTE ANNULÉE N'EST PAS UNE RECETTE.** Elle reste visible dans
  /// l'historique des ventes — c'est une trace — mais elle n'a rien encaissé.
  /// La compter gonflerait le chiffre d'affaires de tout ce qui a été repris.
  static bool _encaissee(Sale v) => v.status != 'annulee';

  List<LigneRapport> _recettes(List<Sale> ventes, DateTime du, DateTime au) {
    final retenues =
        ventes
            .where(
              (v) =>
                  _encaissee(v) &&
                  !v.soldAt.isBefore(du) &&
                  !v.soldAt.isAfter(au),
            )
            .toList()
          ..sort((a, b) => b.soldAt.compareTo(a.soldAt));

    return [
      for (final v in retenues)
        LigneRapport([
          date(v.soldAt),
          'Vente ${v.paymentMode} — ${v.customerName ?? 'client comptant'}',
          '+${montant(v.total)} FCFA',
        ]),
    ];
  }

  List<LigneRapport> _depenses(
    List<Expense> depenses,
    DateTime du,
    DateTime au,
  ) {
    final retenues =
        depenses
            .where(
              (d) => !d.expenseDate.isBefore(du) && !d.expenseDate.isAfter(au),
            )
            .toList()
          ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));

    return [
      for (final d in retenues)
        LigneRapport([
          date(d.expenseDate),
          '${d.label} (${d.category})',
          '-${montant(d.amount)} FCFA',
        ]),
    ];
  }

  double _totalRecettes(List<Sale> ventes, DateTime du, DateTime au) => ventes
      .where(
        (v) => _encaissee(v) && !v.soldAt.isBefore(du) && !v.soldAt.isAfter(au),
      )
      .fold<double>(0, (t, v) => t + v.total);

  double _totalDepenses(List<Expense> depenses, DateTime du, DateTime au) =>
      depenses
          .where(
            (d) => !d.expenseDate.isBefore(du) && !d.expenseDate.isAfter(au),
          )
          .fold<double>(0, (t, d) => t + d.amount);

  // ── Onglet 2 : État de Trésorerie ─────────────────────────────────────────

  PositionTresorerie _tresorerie(
    List<TreasuryAccount> comptes,
    SyncStateData? etat,
  ) {
    if (comptes.isEmpty) {
      return PositionTresorerie(
        caisse: null,
        banque: null,
        autres: null,
        releveLe: etat?.lastPulledAt,
      );
    }

    double sommeDe(String type) => comptes
        .where((c) => c.type == type)
        .fold<double>(0, (t, c) => t + c.balance);

    final connus = {'caisse', 'banque'};

    return PositionTresorerie(
      caisse: comptes.any((c) => c.type == 'caisse') ? sommeDe('caisse') : null,
      banque: comptes.any((c) => c.type == 'banque') ? sommeDe('banque') : null,
      autres: comptes
          .where((c) => !connus.contains(c.type))
          .fold<double>(0, (t, c) => t + c.balance),
      releveLe: etat?.lastPulledAt,
    );
  }

  // ── Onglets 3 et 4 : Créances et Dettes ───────────────────────────────────

  /// ⚠️⚠️ **LE RESTE DÛ SE CALCULE : `amount - amountPaid`.** Afficher
  /// `amount` compterait une seconde fois ce qui a déjà été réglé — c'est le
  /// défaut que la balance âgée du serveur a dû corriger.
  List<LigneRapport> _creances(
    List<Receivable> creances,
    List<Customer> clients,
  ) {
    final nomDe = {for (final c in clients) c.id: c.name};

    final ouvertes = creances.where((c) => c.amount - c.amountPaid > 0).toList()
      ..sort((a, b) => _echeance(a.dueDate).compareTo(_echeance(b.dueDate)));

    return [
      for (final c in ouvertes)
        LigneRapport([
          nomDe[c.customerId] ?? '—',
          montant(c.amount - c.amountPaid),
          c.dueDate == null ? '—' : date(c.dueDate!),
        ]),
    ];
  }

  List<LigneRapport> _dettes(
    List<Payable> dettes,
    List<Supplier> fournisseurs,
  ) {
    final nomDe = {for (final f in fournisseurs) f.id: f.name};

    final ouvertes = dettes.where((d) => d.amount - d.amountPaid > 0).toList()
      ..sort((a, b) => _echeance(a.dueDate).compareTo(_echeance(b.dueDate)));

    return [
      for (final d in ouvertes)
        LigneRapport([
          // ⚠️ Le nom porté par la dette prime le référentiel : un fournisseur
          // archivé doit rester nommé sur l'ardoise qu'il a laissée.
          d.supplierName ?? nomDe[d.supplierId] ?? '—',
          montant(d.amount - d.amountPaid),
          d.dueDate == null ? '—' : date(d.dueDate!),
        ]),
    ];
  }

  static DateTime _echeance(DateTime? d) => d ?? DateTime(9999);

  // ── Onglet 5 : Rapport Élevage ────────────────────────────────────────────

  /// Tableau 1 — Recensement Hebdomadaire, treize colonnes.
  ///
  /// ⚠️⚠️ **ONZE DE CES TREIZE COLONNES NE DESCENDENT PAS AU POSTE.** La
  /// ventilation par sexe et par stade (`effectif_m`, `effectif_f`,
  /// `effectif_sevres`, `effectif_smeres`, `cat_eff_*`) existe bien en base
  /// côté serveur, mais **`_ficheEnJson` ne l'envoie pas** — le poste ne la
  /// possède donc à aucun moment. Les colonnes restent affichées avec un
  /// tiret : les retirer ferait croire que la maquette ne les demande pas, et
  /// le contrôle de structure les compte.
  List<LigneRapport> _elevageRecensement(
    List<LivestockDailyEntry> fiches,
    List<LivestockLot> bandes,
  ) {
    final codeDe = {for (final b in bandes) b.id: b.code};

    return [
      for (final f in fiches)
        LigneRapport([
          date(f.entryDate),
          codeDe[f.lotId] ?? '—',
          '—', // Mères Pondeuses
          '—', // Mères Couveuses
          '—', // Mères Éleveuses
          '—', // Poussins S/Mères
          '—', // Sevrés M
          '—', // Sevrés F
          '—', // Morts M
          '—', // Morts F
          '—', // Morts SM
          '—', // Géniteurs
          '—', // Effectif Malade
        ]),
    ];
  }

  /// Tableau 2 — Mouvements, Traitements & Ventes, neuf colonnes.
  ///
  /// ⚠️ **QUATRE COLONNES SUR NEUF SONT RÉELLES.** `vente` et `effectifFinal`
  /// font partie de l'envoi ; `vente_sexe`, `vente_montant`,
  /// `treatment_dose` et `symptomes` n'en font pas partie. Le traitement
  /// administré vit dans le registre `veterinary_records`, une AUTRE table,
  /// avec sa propre date — les rapprocher ici sur la seule date produirait des
  /// associations fausses le jour où deux soins tombent le même jour.
  List<LigneRapport> _elevageMouvements(
    List<LivestockDailyEntry> fiches,
    List<LivestockLot> bandes,
  ) {
    final codeDe = {for (final b in bandes) b.id: b.code};

    return [
      for (final f in fiches)
        LigneRapport([
          date(f.entryDate),
          codeDe[f.lotId] ?? '—',
          '—', // Sexe Vendu
          f.vente == 0 ? '—' : '${f.vente}',
          '—', // Montant Vente (FCFA)
          '${f.effectifFinal}',
          '—', // Traitement Administré
          '—', // Dose
          '—', // Signes de Maladie Observés
        ]),
    ];
  }

  /// Tableau 3 — Suivi Intégral de la Ponte, dix colonnes.
  ///
  /// ⚠️ **C'EST LE SEUL DES TROIS QUI SOIT ENTIÈREMENT CALCULABLE AU POSTE**,
  /// et c'est normal : la ponte est ce que le poste saisit lui-même.
  ///
  /// Formules affichées par la maquette en pied de tableau, appliquées ici
  /// telles quelles :
  ///   Taux de Ponte % = (OR × 100) ÷ Effectif Final
  ///   Total Stock (TS) = (OR − OF) + SRH
  ///   Stock Final = TS − OS
  List<LigneRapport> _elevagePonte(
    List<LivestockDailyEntry> toutes,
    List<LivestockDailyEntry> periode,
    List<LivestockLot> bandes,
    List<SaleLine> lignesDeVente,
    List<Product> produits,
    List<Sale> ventes,
  ) {
    final bandeDe = {for (final b in bandes) b.id: b};

    // Ticket U8 — JOUR DE VENTE de chaque vente : sa date effective (`sold_at ?? created_at` au web ; le serveur la
    // sert dans `sold_at`, et une vente du poste porte l'instant de la saisie), ramenée au jour. Une vente REFUSÉE
    // par le serveur (`conflict`) n'a rien fait sortir du stock de la ferme : elle n'a pas de jour de sortie.
    final jourDeVente = <String, DateTime>{
      for (final v in ventes)
        if (v.syncStatus != SyncStatus.conflict)
          v.id: DateTime(v.soldAt.year, v.soldAt.month, v.soldAt.day),
    };

    // ⚠️ LE STOCK RESTANT HIER SE LIT SUR LA VEILLE, PAS SUR LA PREMIÈRE LIGNE
    // AFFICHÉE. Filtrer d'abord la période puis chercher la veille ferait
    // repartir tout rapport de zéro à sa première journée : le SRH est
    // cherché dans TOUTES les journées du poste.
    final parBande = <String, List<LivestockDailyEntry>>{};
    for (final f in toutes) {
      parBande.putIfAbsent(f.lotId, () => []).add(f);
    }
    for (final liste in parBande.values) {
      liste.sort((a, b) => a.entryDate.compareTo(b.entryDate));
    }

    final oeufs = _produitOeufs(produits);

    final lignes = <LigneRapport>[];

    for (final f in periode) {
      if (f.ponteTotal == null) continue;

      final bande = bandeDe[f.lotId];
      final or = f.ponteTotal ?? 0;
      final of = f.ponteCasses ?? 0;
      final commercialisables = ProductionOeufsService.commercialisables(
        recoltes: or,
        casses: of,
      );

      final srh = _stockDeLaVeille(
        parBande[f.lotId] ?? const [],
        f.entryDate,
        lignesDeVente,
        oeufs,
        jourDeVente,
      );
      final ts = commercialisables + srh;
      final osOeufs = _sortiesVente(f, lignesDeVente, oeufs, jourDeVente);
      final finalOeufs = ts - osOeufs < 0 ? 0 : ts - osOeufs;

      final taux = ProductionOeufsService.tauxDePonte(
        recoltes: or,
        effectif: f.effectifFinal,
      );
      final osPlateaux = ProductionOeufsService.enPlateaux(osOeufs);
      final restant = ProductionOeufsService.enPlateaux(finalOeufs);

      lignes.add(
        LigneRapport([
          _ageEnSemaines(bande, f.entryDate),
          date(f.entryDate),
          '$or',
          taux == null ? '—' : '${taux.toStringAsFixed(1)} %',
          '$of',
          '$commercialisables',
          '$srh',
          '$ts',
          '${osPlateaux.plateaux} ($osOeufs œufs)',
          '${restant.plateaux} plateaux + ${restant.vrac} vrac',
        ]),
      );
    }

    return lignes.reversed.toList();
  }

  /// ⚠️ **LES SORTIES SONT IMPUTÉES À LA BANDE, JAMAIS RÉPARTIES.**
  /// `SaleLines.lotId` porte la bande d'origine, précisément pour éviter une
  /// répartition inventée. Une vente d'œufs prise sur le stock sans bande
  /// d'origine ne peut donc pas être imputée — et n'est pas devinée.
  ///
  /// 🔴→✅ **TICKET U8 — LES SORTIES DU JOUR DE LA FICHE, PAS DE TOUTE LA VIE DE
  /// LA BANDE.** OS est la colonne « Sorties Vente » d'UNE journée : le web
  /// (`EggStockLedgerService::ventesDu($date)`) ne compte que les ventes de ce
  /// jour-là. Le poste additionnait toutes les lignes d'œufs de la bande à
  /// chaque journée — une vente du 3 sortait aussi le 4, le 5… et le stock
  /// final s'effondrait à tort. Le jour d'une vente est sa date effective
  /// ([jourDeVente]) ; une ligne dont la vente est inconnue du poste n'a pas de
  /// jour et ne sort nulle part.
  int _sortiesVente(
    LivestockDailyEntry fiche,
    List<SaleLine> lignes,
    Product? oeufs,
    Map<String, DateTime> jourDeVente,
  ) {
    final jour = DateTime(
      fiche.entryDate.year,
      fiche.entryDate.month,
      fiche.entryDate.day,
    );
    return _sorties(
      fiche.lotId,
      lignes,
      oeufs,
      jourDeVente,
      (jourVente) => jourVente == jour,
    );
  }

  /// Œufs sortis par les ventes de la bande [lotId] dont le jour de vente satisfait [retenu].
  int _sorties(
    String lotId,
    List<SaleLine> lignes,
    Product? oeufs,
    Map<String, DateTime> jourDeVente,
    bool Function(DateTime jourVente) retenu,
  ) {
    if (oeufs == null) return 0;

    return lignes
        .where((l) {
          final jourVente = jourDeVente[l.saleId];
          return l.productId == oeufs.id &&
              l.lotId == lotId &&
              jourVente != null &&
              retenu(jourVente);
        })
        .fold<int>(
          0,
          (t, l) =>
              t + (l.qty.round() * ProductionOeufsService.oeufsParPlateau),
        );
  }

  int _stockDeLaVeille(
    List<LivestockDailyEntry> journees,
    DateTime jour,
    List<SaleLine> lignes,
    Product? oeufs,
    Map<String, DateTime> jourDeVente,
  ) {
    final debutDuJour = DateTime(jour.year, jour.month, jour.day);
    var stock = 0;

    for (final f in journees) {
      if (!f.entryDate.isBefore(debutDuJour)) break;
      if (f.ponteTotal == null) continue;

      stock += ProductionOeufsService.commercialisables(
        recoltes: f.ponteTotal ?? 0,
        casses: f.ponteCasses ?? 0,
      );
    }

    // Ticket U8 — les ventes de la bande AVANT ce jour, chacune UNE fois, à son jour de vente (jour avec ou sans
    // fiche) : sans le filtre par jour, chaque vente était retranchée autant de fois qu'il y avait de journées.
    if (journees.isNotEmpty) {
      stock -= _sorties(
        journees.first.lotId,
        lignes,
        oeufs,
        jourDeVente,
        (jourVente) => jourVente.isBefore(debutDuJour),
      );
    }

    return stock < 0 ? 0 : stock;
  }

  /// ⚠️ Même normalisation de ligature que `ProductionOeufsService` : le
  /// catalogue écrit « **Œ**ufs de table (plateau) », et une comparaison qui
  /// ne rapproche pas « Œ » de « oe » ne trouve rien — en silence.
  Product? _produitOeufs(List<Product> produits) {
    for (final p in produits.where((p) => p.isActive)) {
      if (p.name.toLowerCase().replaceAll('œ', 'oe').contains('oeufs')) {
        return p;
      }
    }
    return null;
  }

  String _ageEnSemaines(LivestockLot? bande, DateTime jour) {
    final debut = bande?.createdDate;
    if (debut == null) return '—';

    final jours = jour.difference(debut).inDays;
    return jours < 0 ? '—' : '${jours ~/ 7}';
  }

  IndicateursElevage _indicateurs(List<LivestockDailyEntry> fiches) {
    final pondeuses = fiches.where((f) => f.ponteTotal != null).toList();

    final production = pondeuses.fold<int>(0, (t, f) => t + (f.ponteTotal!));

    final taux = <double>[];
    for (final f in pondeuses) {
      final t = ProductionOeufsService.tauxDePonte(
        recoltes: f.ponteTotal!,
        effectif: f.effectifFinal,
      );
      if (t != null) taux.add(t);
    }

    // ⚠️ **LA MORTALITÉ SE RAPPORTE À L'EFFECTIF DE DÉBUT DE JOURNÉE**, que le
    // poste reconstitue : effectif final + morts + ventes + dons − achats −
    // nés. Diviser par l'effectif FINAL surestimerait la mortalité, l'effectif
    // final étant justement amputé des morts.
    var morts = 0;
    var debuts = 0;
    for (final f in fiches) {
      morts += f.mort;
      debuts += f.effectifFinal + f.mort + f.vente + f.don - f.achat - f.ne;
    }

    return IndicateursElevage(
      productionTotale: production,
      tauxPonteMoyen: taux.isEmpty
          ? null
          : taux.reduce((a, b) => a + b) / taux.length,
      mortaliteHebdo: debuts <= 0 ? null : (morts / debuts) * 100,
      chiffreAffaires: null,
    );
  }

  // ── Onglet 6 : Rapport de Stocks ──────────────────────────────────────────

  /// ⚠️⚠️ **LA VALORISATION NE COMPTE PAS LES QUANTITÉS NÉGATIVES.** Un stock
  /// négatif signale une ENTRÉE NON SAISIE, pas une dette de marchandise :
  /// le valoriser en négatif retrancherait de la valeur du magasin de l'argent
  /// qui n'a jamais quitté la ferme.
  ///
  /// ⚠️ **LE PRIX RETENU EST `priceMin`.** C'est le seul prix dont dispose le
  /// poste pour un produit en fourchette ; le maximum donnerait la valeur la
  /// plus flatteuse, ce qui n'est pas la prudence attendue d'un état de stock.
  List<LigneRapport> _stocks(
    List<Product> produits,
    List<ProductCategory> categories,
  ) {
    final actifs = produits.where((p) => p.isActive).toList();
    final nomDe = {for (final c in categories) c.id: c.label};

    final valeur = <String, double>{};
    final sousSeuil = <String, int>{};

    for (final p in actifs) {
      final cle = p.categoryId ?? '';
      final quantite = p.stockQty < 0 ? 0.0 : p.stockQty;

      valeur[cle] = (valeur[cle] ?? 0) + quantite * (p.priceMin ?? 0);

      final seuil = p.alertThreshold;
      if (seuil != null && p.stockQty <= seuil) {
        sousSeuil[cle] = (sousSeuil[cle] ?? 0) + 1;
      } else {
        sousSeuil[cle] ??= 0;
      }
    }

    final cles = valeur.keys.toList()
      ..sort(
        (a, b) => (nomDe[a] ?? 'Sans catégorie').compareTo(
          nomDe[b] ?? 'Sans catégorie',
        ),
      );

    return [
      for (final cle in cles)
        LigneRapport([
          nomDe[cle] ?? 'Sans catégorie',
          montant(valeur[cle] ?? 0),
          '${sousSeuil[cle] ?? 0}',
        ]),
    ];
  }

  // ── Mise en forme ─────────────────────────────────────────────────────────

  static String date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String montant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }
}
