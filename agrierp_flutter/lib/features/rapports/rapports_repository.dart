import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../elevage/effectif_precedent.dart';
import '../stocks/journal_stocks.dart';
import '../stocks/pmp_service.dart';

/// Une ligne de rapport : ses cellules, dans l'ordre des colonnes du tableau. Le tiret y est une VALEUR, pas une
/// absence de cellule — c'est ce qui garantit que le tableau garde toutes ses colonnes.
class LigneRapport {
  const LigneRapport(this.cellules);

  final List<String> cellules;
}

/// Ticket U12b — une ligne de l'état des Recettes et Dépenses, telle que `RecettesDepenses` (web) la construit :
/// `['date' => …, 'label' => …, 'amount' => …]`.
class MouvementRapport {
  const MouvementRapport({
    required this.date,
    required this.libelle,
    required this.montant,
  });

  /// Le JOUR du mouvement (heure murale du Bénin, minuit).
  final DateTime date;
  final String libelle;
  final double montant;
}

/// Ticket U12b — une ligne de l'État de Trésorerie du web (`Tresorerie::getRowsProperty()`) : les soldes CUMULÉS
/// des comptes de classe 5 à une date où une écriture a touché la trésorerie.
class SoldeTresorerie {
  const SoldeTresorerie({
    required this.date,
    required this.caisse,
    required this.banque,
    required this.total,
  });

  final DateTime date;

  /// `round(Σ débit − Σ crédit des comptes 531…, 2)`.
  final double caisse;

  /// `round(Σ débit − Σ crédit des AUTRES comptes de classe 5, 2)` (521, 5212, Mobile Money…).
  final double banque;

  /// `round(caisse + banque, 2)`, sur les sommes NON arrondies, comme le web.
  final double total;
}

/// Ticket U12b — une créance ou une dette ouverte des rapports du web (`Creances`, `Dettes`).
class EcheanceRapport {
  const EcheanceRapport({
    required this.id,
    required this.nom,
    required this.reste,
    required this.echeance,
  });

  final String id;

  /// `$r->customer?->name` / `$p->supplier?->name` ; `null` : « — » à l'écran, vide au classeur.
  final String? nom;

  /// `Receivable::getBalanceAttribute()` / `Payable::getBalanceAttribute()` : `round(amount − amount_paid, 2)`.
  final double reste;

  /// Le jour de l'échéance (jamais nul : le web filtre `whereDate('due_date', …)`, qui écarte une échéance absente).
  final DateTime echeance;
}

/// Ticket U12b — une ligne du Rapport de Stocks du web (`StocksSynth::getRowsProperty()`).
class StockCategorie {
  const StockCategorie({
    required this.categorie,
    required this.valeur,
    required this.sousSeuil,
    required this.nonValorises,
    required this.negatifs,
  });

  final String categorie;

  /// `round(Σ (Product::valeurStock() ?? 0), 2)` — stock négatif retenu à zéro, produit sans PMP compté à zéro.
  final double valeur;

  /// Produits dont `alert_threshold !== null && stock_qty <= alert_threshold`.
  final int sousSeuil;

  /// Produits jamais achetés (PMP nul) ET en stock (`stock_qty > 0`) : non valorisés.
  final int nonValorises;

  /// Produits en stock négatif (`Product::stockEstNegatif()`).
  final int negatifs;
}

/// Les quatre indicateurs zootechniques du rapport d'élevage — `ElevageSynth::getKpisProperty()` (ticket U10).
class IndicateursElevage {
  const IndicateursElevage({
    required this.productionTotale,
    required this.tauxPonteMoyen,
    required this.mortaliteHebdo,
    required this.chiffreAffaires,
  });

  /// `(int) $entries->sum('ponte_total')`.
  final int productionTotale;

  /// `round(avg(OR ÷ Effectif Final × 100), 1)` sur les fiches à effectif ET ponte > 0 ; `null` (« — ») sans elles.
  final double? tauxPonteMoyen;

  /// `round(Σ morts ÷ previousEffectif(fiche la plus ancienne) × 100, 1)` ; `null` (« — ») si cet effectif est nul.
  final double? mortaliteHebdo;

  /// 🔴→✅ Ticket U10 — `(float) $entries->sum('vente_montant')` : `vente_montant` descend au poste (schéma v45). Le
  /// web affiche toujours un montant, « 0 FCFA » compris : le poste aussi.
  final double chiffreAffaires;

  /// `round(...)` puis conversion en chaîne de PHP, suivie de « % » ; « — » si `null` (Blade du web).
  static String taux(double? valeur) =>
      valeur == null ? '—' : '${PmpService.flottant(valeur)} %';
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
    this.bandesElevage = const [],
    this.elevageT3Export = const [],
    this.elevageClasseur = const [],
  });

  final DateTime du;
  final DateTime au;

  final List<MouvementRapport> recettes;
  final List<MouvementRapport> depenses;
  final double totalRecettes;
  final double totalDepenses;

  /// `'solde' => (float) $totalRecettes - $totalDepenses`.
  double get soldeNet => totalRecettes - totalDepenses;

  final List<SoldeTresorerie> tresorerie;
  final List<EcheanceRapport> creances;
  final List<EcheanceRapport> dettes;

  final List<LigneRapport> elevageT1;
  final List<LigneRapport> elevageT2;
  final List<LigneRapport> elevageT3;
  final IndicateursElevage indicateurs;

  /// Ticket U10 — options du filtre « Lot / Souche » : bandes ACTIVES triées par code (`ElevageSynth::getLotsProperty()`).
  final List<LivestockLot> bandesElevage;

  /// Ticket U10 — Tableau 3 du PDF du web (`exports/elevage-synth.blade.php`) : Jour, Lot, Œufs Récoltés, Taux Ponte
  /// %, Cassés, Commercialisables.
  final List<LigneRapport> elevageT3Export;

  /// Ticket U12b — lignes de l'export « Excel » du Rapport Élevage (le CSV de `ElevageSynth::exportReport()`), sans
  /// l'en-tête : une par fiche de la sélection, dans l'ordre des tableaux.
  final List<List<String>> elevageClasseur;

  /// Catégories du Rapport de Stocks, AVANT la recherche (voir [RapportsRepository.filtrerStocks]).
  final List<StockCategorie> stocks;
}

/// Lectures du hub « Rapports & Exports » — les six composants Livewire de `app/Livewire/Rapports/` et leurs vues.
///
/// 🔴→✅ **Ticket U12b — LE WEB EST MAÎTRE POUR LES SIX ONGLETS** (doctrine, article 5). Les cinq onglets autres que
/// le Rapport Élevage (U10 / U11) gardaient la maquette : en-tête et boutons par onglet, recherche partout, trésorerie
/// réduite au solde du dernier tirage, créances et dettes sans période, stocks valorisés au prix de vente minimal.
/// Ils suivent désormais leur composant, règle pour règle, prouvé par `test/rapports_parite_test.dart` (parité
/// exécutée : le VRAI composant rend ses tableaux et son CSV sur le même jeu).
///
/// 🔴→✅ **Ticket U13** — les dépenses du web portent aussi la PAIE (`payslips`) et les dépenses saisies sur le web ou
/// un autre poste : les deux descendent désormais au poste (tirage, `SyncEngine._absorberDepenses` / `_absorberPaie`),
/// archivage compris. « Recettes et Dépenses » a la même matière qu'au web, et donne le même total (parité exécutée).
class RapportsRepository {
  RapportsRepository({required this.database});

  final AppDatabase database;

  /// [lot] : filtre « Lot / Souche » du web (`$lotFilter`, identifiant de bande ; vide = toutes).
  Future<DonneesRapports> charger({
    required DateTime du,
    required DateTime au,
    String lot = '',
  }) async {
    // ⚠️ La borne haute est INCLUSIVE : « au 31/07 » doit contenir le 31/07
    // dans son entier, pas s'arrêter à minuit. Une vente de fin de journée
    // disparaîtrait sinon du rapport sans qu'on sache pourquoi.
    final debut = DateTime(du.year, du.month, du.day);
    final fin = DateTime(au.year, au.month, au.day, 23, 59, 59, 999);

    final ventes = await database.select(database.sales).get();
    final achats = await database.select(database.purchases).get();
    final lignesAchat = await database.select(database.purchaseLines).get();
    final depenses = await database.select(database.expenses).get();
    // Ticket U13 — la paie réglée, descendue du serveur (comptes `view-rapports`).
    final paie = await database.select(database.payslips).get();
    final clients = await database.select(database.customers).get();
    final creances = await database.select(database.receivables).get();
    final dettes = await database.select(database.payables).get();
    final fournisseurs = await database.select(database.suppliers).get();
    final produits = await database.select(database.products).get();
    final categories = await database.select(database.productCategories).get();
    final bandes = await database.select(database.livestockLots).get();
    final ecritures = await database.select(database.accountingEntries).get();
    final lignesEcriture = await database
        .select(database.accountingEntryLines)
        .get();
    final planComptable = await database.select(database.chartOfAccounts).get();
    // Ticket U9 — grand livre des stocks (descendu + saisies en attente) : Tableau 3 de la ponte.
    final journal = await JournalStocks.charger(
      database,
      maintenant: HeureBenin.maintenant(),
    );

    // Ticket U11 — ordre du web (`orderByDesc('entry_date')->orderBy('id')`), appliqué par [ordreDesFiches].
    final fiches = (await database.select(database.livestockDailyEntries).get())
      ..sort(ordreDesFiches);

    // 🔴→✅ Ticket U10 — `ElevageSynth::baseQuery()` : fiches de la période et de la bande filtrée. ⚠️ Une fiche
    // REFUSÉE par le serveur (`conflict`) n'existe pas au web : elle ne compte nulle part (règle U8) ; une fiche en
    // attente d'envoi compte, elle part vers lui.
    final connues = [
      for (final f in fiches)
        if (f.syncStatus != SyncStatus.conflict) f,
    ];
    final dansLaPeriode = connues
        .where(
          (f) =>
              !f.entryDate.isBefore(debut) &&
              !f.entryDate.isAfter(fin) &&
              (lot.isEmpty || f.lotId == lot),
        )
        .toList();
    final nomProduit = {for (final p in produits) p.id: p.name};
    final nomFournisseur = {for (final f in fournisseurs) f.id: f.name};

    final recettes = recettesDe(ventes, clients, debut, fin);
    final sorties = depensesDe(
      achats: achats,
      nomFournisseur: nomFournisseur,
      depenses: depenses,
      paie: paie,
      du: debut,
      au: fin,
    );

    return DonneesRapports(
      du: debut,
      au: au,
      recettes: recettes,
      depenses: sorties,
      totalRecettes: recettes.fold<double>(0, (t, m) => t + m.montant),
      totalDepenses: sorties.fold<double>(0, (t, m) => t + m.montant),
      tresorerie: soldesTresorerie(
        ecritures: ecritures,
        lignes: lignesEcriture,
        comptes: planComptable,
        du: debut,
        au: fin,
      ),
      creances: creancesDe(creances, clients, debut, fin),
      dettes: dettesDe(dettes, nomFournisseur, debut, fin),
      elevageT1: elevageRecensement(dansLaPeriode, bandes),
      elevageT2: elevageMouvements(dansLaPeriode, bandes, nomProduit),
      elevageT3: elevagePonte(
        dansLaPeriode,
        bandes,
        journal,
        JournalStocks.produitOeufs(produits)?.id,
      ),
      elevageT3Export: elevagePonteExport(dansLaPeriode, bandes),
      elevageClasseur: elevageClasseurDe(dansLaPeriode, bandes),
      indicateurs: indicateursElevage(dansLaPeriode, connues, bandes),
      bandesElevage:
          bandes.where((b) => b.isActive).toList()
            ..sort((a, b) => comparerCommeLeServeur(a.code, b.code)),
      stocks: stocksDe(
        produits,
        categories,
        PmpService.parProduit(PmpService.lignesRetenues(achats, lignesAchat)),
      ),
    );
  }

  /// `whereDate(…, '>=', du)->whereDate(…, '<=', au)` : le JOUR de [d] est dans la période.
  static bool _dansLaPeriode(DateTime d, DateTime du, DateTime au) =>
      !_jour(d).isBefore(_jour(du)) && !_jour(d).isAfter(_jour(au));

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Tri STABLE (celui de PHP 8, `arsort` de `sortByDesc`) : à clé égale, l'ordre d'entrée est gardé.
  static List<T> _trierStable<T>(List<T> liste, int Function(T, T) comparer) {
    final indices = [for (var i = 0; i < liste.length; i++) i]
      ..sort((a, b) {
        final c = comparer(liste[a], liste[b]);
        return c != 0 ? c : a.compareTo(b);
      });
    return [for (final i in indices) liste[i]];
  }

  // ── Onglet 1 : Recettes et Dépenses ───────────────────────────────────────

  /// 🔴→✅ Ticket U12b — `RecettesDepenses::recettesQuery()` puis `getRecettesProperty()` :
  ///
  ///   ventes `status = 'validee'` ET `payment_mode != 'credit'` (une vente à crédit n'est pas un encaissement
  ///   immédiat) dont la date effective tombe dans la période (`soldBetween`, journées entières) ; de la plus récente
  ///   à la plus ancienne (`orderByEffectiveDate()`, puis l'identifiant) ; libellé « Vente — {client} », « Client
  ///   comptant » sans client.
  ///
  /// Le poste comptait aussi les ventes à CRÉDIT et nommait le mode de paiement ; il ne gardait que le statut
  /// « non annulée ». ⚠️ Une vente REFUSÉE par le serveur (`conflict`) n'existe pas au web : elle ne compte pas
  /// (règle U8) ; une vente en attente d'envoi compte, elle part vers lui.
  static List<MouvementRapport> recettesDe(
    List<Sale> ventes,
    List<Customer> clients,
    DateTime du,
    DateTime au,
  ) {
    final nomClient = {for (final c in clients) c.id: c.name};
    final retenues = [
      for (final v in ventes)
        if (v.syncStatus != SyncStatus.conflict &&
            v.status == 'validee' &&
            v.paymentMode != 'credit' &&
            _dansLaPeriode(v.soldAt, du, au))
          v,
    ]..sort((a, b) {
        final parDate = b.soldAt.compareTo(a.soldAt);
        return parDate != 0 ? parDate : a.id.compareTo(b.id);
      });

    return [
      for (final v in retenues)
        MouvementRapport(
          date: _jour(v.soldAt),
          // `$s->customer?->name` : le nom servi avec la vente, sinon celui du client du poste (vente saisie ici).
          libelle:
              'Vente — ${v.customerName ?? nomClient[v.customerId] ?? 'Client comptant'}',
          montant: v.total,
        ),
    ];
  }

  /// 🔴→✅ Ticket U12b — `RecettesDepenses::depensesRows()` : les achats NON à crédit de la période (« Achat —
  /// {fournisseur} », « Fournisseur » sans nom), PUIS les dépenses de la période (leur seul libellé), PUIS la paie,
  /// triés par date décroissante d'un tri STABLE (`sortByDesc('date')`) : à date égale, achats avant dépenses, et dans
  /// chaque source l'identifiant croissant (`orderBy('id')`, ticket U12b au web).
  ///
  /// Le poste ne comptait que ses dépenses, libellées « {libellé} ({catégorie}) » : ni achats ni paie.
  ///
  /// 🔴→✅ Ticket U13 — les dépenses du web et des autres postes et la PAIE (`payslips`) descendent au poste : les
  /// dépenses ARCHIVÉES sont écartées (`where('is_active', true)`, U12b au web), la paie entre datée du JOUR de son
  /// règlement (`created_at->toDateString()`, heure murale du serveur), libellée « Paie — {Nom Prénom} » (« Employé »
  /// sans employé, libellé corrigé au web par U13), montant `net_salary`. Achat ou dépense REFUSÉ (`conflict`) :
  /// exclu (absent du web) ; en attente d'envoi : compté (il part vers lui).
  static List<MouvementRapport> depensesDe({
    required List<Purchase> achats,
    required Map<String, String> nomFournisseur,
    required List<Expense> depenses,
    List<Payslip> paie = const [],
    required DateTime du,
    required DateTime au,
  }) {
    final lignes = <MouvementRapport>[
      for (final a in [...achats]..sort((x, y) => x.id.compareTo(y.id)))
        if (a.syncStatus != SyncStatus.conflict &&
            a.paymentMode != 'credit' &&
            _dansLaPeriode(a.purchaseDate, du, au))
          MouvementRapport(
            date: _jour(a.purchaseDate),
            libelle:
                'Achat — ${a.supplierName ?? nomFournisseur[a.supplierId] ?? 'Fournisseur'}',
            montant: a.total,
          ),
      for (final e in [...depenses]..sort((x, y) => x.id.compareTo(y.id)))
        if (e.syncStatus != SyncStatus.conflict &&
            e.isActive &&
            _dansLaPeriode(e.expenseDate, du, au))
          MouvementRapport(
            date: _jour(e.expenseDate),
            libelle: e.label,
            montant: e.amount,
          ),
      for (final p in [...paie]..sort((x, y) => x.id.compareTo(y.id)))
        if (_dansLaPeriode(p.createdAt, du, au))
          MouvementRapport(
            date: _jour(p.createdAt),
            libelle: libellePaie(p.employeeName),
            montant: p.netSalary,
          ),
    ];
    return _trierStable(lignes, (a, b) => b.date.compareTo(a.date));
  }

  /// Ticket U13 — « Paie — {Nom Prénom} », « Paie — Employé » sans employé (`RecettesDepenses::depensesRows()`, libellé
  /// corrigé au web par U13 : la priorité de `??` en PHP rendait « Employé » inatteignable).
  static String libellePaie(String? employe) => 'Paie — ${employe ?? 'Employé'}';

  /// Cellules d'une recette à l'écran et au PDF : « dd/mm/AAAA », libellé, « +N FCFA ».
  static List<String> celluleRecette(MouvementRapport m) => [
    date(m.date),
    m.libelle,
    '+${PmpService.francs(m.montant)} FCFA',
  ];

  /// Cellules d'une dépense : « -N FCFA ».
  static List<String> celluleDepense(MouvementRapport m) => [
    date(m.date),
    m.libelle,
    '-${PmpService.francs(m.montant)} FCFA',
  ];

  // ── Onglet 2 : État de Trésorerie ─────────────────────────────────────────

  /// 🔴→✅ Ticket U12b — `Tresorerie::getRowsProperty()`, DEPUIS LE GRAND LIVRE comme au web (le poste n'affichait
  /// que le solde de `treasury_accounts` au dernier tirage, sur une seule ligne) :
  ///
  ///   une ligne par JOUR de la période où une écriture ACTIVE a touché un compte de classe 5, du plus récent au plus
  ///   ancien ; pour chaque jour, le solde CUMULÉ (Σ débit − Σ crédit de TOUTES les écritures jusqu'à ce jour inclus)
  ///   des comptes 531… (« Solde Caisse ») et des autres comptes de classe 5 (« Solde Banque ») ; chacun arrondi à
  ///   deux décimales, et leur total arrondi sur les sommes brutes.
  ///
  /// Le journal descend entier au poste depuis 14.83 / F0.84 (écritures actives, avec leurs lignes, liste des
  /// écritures actives pour les retraits) pour les rôles qui ouvrent ce hub (`view-comptabilite`). Un compte mouvementé
  /// ne peut pas être archivé au web (`PlanComptable::archiveAccount`) : le plan servi (comptes actifs) les contient
  /// tous.
  static List<SoldeTresorerie> soldesTresorerie({
    required List<AccountingEntry> ecritures,
    required List<AccountingEntryLine> lignes,
    required List<ChartOfAccount> comptes,
    required DateTime du,
    required DateTime au,
  }) {
    final codeClasse5 = {
      for (final c in comptes)
        if (c.accountClass == 5) c.id: c.code,
    };
    final jourDe = {for (final e in ecritures) e.id: _jour(e.entryDate)};

    final caisseDuJour = <DateTime, double>{};
    final banqueDuJour = <DateTime, double>{};
    final jours = <DateTime>{};
    for (final l in lignes) {
      final code = codeClasse5[l.accountId];
      final jour = jourDe[l.entryId];
      if (code == null || jour == null) continue;
      jours.add(jour);
      final mouvement = l.debit - l.credit;
      if (code.startsWith('531')) {
        caisseDuJour[jour] = (caisseDuJour[jour] ?? 0) + mouvement;
      } else {
        banqueDuJour[jour] = (banqueDuJour[jour] ?? 0) + mouvement;
      }
    }

    final croissants = jours.toList()..sort();
    var caisse = 0.0;
    var banque = 0.0;
    final soldes = <SoldeTresorerie>[];
    for (final jour in croissants) {
      caisse += caisseDuJour[jour] ?? 0;
      banque += banqueDuJour[jour] ?? 0;
      if (_dansLaPeriode(jour, du, au)) {
        soldes.add(
          SoldeTresorerie(
            date: jour,
            caisse: PmpService.arrondi(caisse, 2),
            banque: PmpService.arrondi(banque, 2),
            total: PmpService.arrondi(caisse + banque, 2),
          ),
        );
      }
    }
    return soldes.reversed.toList();
  }

  /// Cellules d'une ligne de trésorerie (`number_format(…, 0, ',', ' ')`, sans unité, comme le Blade).
  static List<String> celluleTresorerie(SoldeTresorerie s) => [
    date(s.date),
    PmpService.francs(s.caisse),
    PmpService.francs(s.banque),
    PmpService.francs(s.total),
  ];

  // ── Onglets 3 et 4 : Créances et Dettes ───────────────────────────────────

  /// 🔴→✅ Ticket U12b — `Creances::getReceivablesProperty()` : créances OUVERTES (`amount_paid < amount`) dont
  /// l'ÉCHÉANCE tombe dans la période du hub (une échéance absente n'y tombe pas), par échéance croissante puis
  /// identifiant (`orderBy('id')`, ticket U12b au web). Le poste ignorait la période et listait les échéances absentes.
  static List<EcheanceRapport> creancesDe(
    List<Receivable> creances,
    List<Customer> clients,
    DateTime du,
    DateTime au,
  ) {
    final nomDe = {for (final c in clients) c.id: c.name};
    return _echeances([
      for (final c in creances)
        if (c.amountPaid < c.amount &&
            c.dueDate != null &&
            _dansLaPeriode(c.dueDate!, du, au))
          EcheanceRapport(
            id: c.id,
            nom: nomDe[c.customerId],
            reste: PmpService.arrondi(c.amount - c.amountPaid, 2),
            echeance: _jour(c.dueDate!),
          ),
    ]);
  }

  /// 🔴→✅ Ticket U12b — `Dettes::getPayablesProperty()` : la règle de [creancesDe] côté fournisseurs. Le nom est celui
  /// du fournisseur de la dette (`$p->supplier?->name`, servi avec elle : un fournisseur archivé reste nommé).
  static List<EcheanceRapport> dettesDe(
    List<Payable> dettes,
    Map<String, String> nomFournisseur,
    DateTime du,
    DateTime au,
  ) => _echeances([
    for (final d in dettes)
      if (d.amountPaid < d.amount &&
          d.dueDate != null &&
          _dansLaPeriode(d.dueDate!, du, au))
        EcheanceRapport(
          id: d.id,
          nom: d.supplierName ?? nomFournisseur[d.supplierId],
          reste: PmpService.arrondi(d.amount - d.amountPaid, 2),
          echeance: _jour(d.dueDate!),
        ),
  ]);

  static List<EcheanceRapport> _echeances(List<EcheanceRapport> lignes) =>
      lignes..sort((a, b) {
        final parEcheance = a.echeance.compareTo(b.echeance);
        return parEcheance != 0 ? parEcheance : a.id.compareTo(b.id);
      });

  /// Cellules d'une créance ou d'une dette à l'écran : nom (« — »), reste dû (`number_format`), échéance.
  static List<String> celluleEcheance(EcheanceRapport e) => [
    e.nom ?? '—',
    PmpService.francs(e.reste),
    date(e.echeance),
  ];

  /// `->when($this->search, fn ($q) => $q->whereHas('supplier', fn ($q2) => $q2->where('name', 'like',
  /// '%'.$this->search.'%')))` : recherche dans le NOM du fournisseur, sans casse ni accents (collation
  /// `utf8mb4_unicode_ci`) ; une dette sans fournisseur connu ne répond à aucune recherche.
  static List<EcheanceRapport> filtrerDettes(
    List<EcheanceRapport> dettes,
    String recherche,
  ) {
    if (!_rechercheActive(recherche)) return dettes;
    final terme = cleCommeLeServeur(recherche);
    return [
      for (final d in dettes)
        if (d.nom case final nom?
            when cleCommeLeServeur(nom).contains(terme))
          d,
    ];
  }

  /// `->when($this->search, …)` de PHP : une chaîne vide ET « 0 » sont fausses — aucune recherche alors.
  static bool _rechercheActive(String recherche) =>
      recherche.isNotEmpty && recherche != '0';

  // ── Onglet 5 : Rapport Élevage ────────────────────────────────────────────

  /// 🔴→✅ Ticket U11 — ORDRE DES FICHES DU RAPPORT, celui du web (`ElevageSynth::baseQuery()` :
  /// `orderByDesc('entry_date')->orderBy('id')`) : le jour le plus récent d'abord, puis, entre deux fiches du même
  /// jour (deux bandes), l'identifiant croissant. Sans second critère, l'ordre de deux fiches du même jour dépendait
  /// du moteur de base (et `List.sort` de Dart n'est pas stable) : les tableaux et la fiche « la plus ancienne » de
  /// la mortalité hebdo pouvaient différer d'une surface à l'autre.
  ///
  /// ⚠️ Les identifiants sont des UUID en minuscules (le poste et `HasUuids` du serveur) : la comparaison binaire
  /// de Dart et la collation `utf8mb4_unicode_ci` du serveur les rangent de la même façon.
  static int ordreDesFiches(LivestockDailyEntry a, LivestockDailyEntry b) {
    final parJour = JournalStocks.jour(
      b.entryDate,
    ).compareTo(JournalStocks.jour(a.entryDate));
    return parJour != 0 ? parJour : a.id.compareTo(b.id);
  }

  /// 🔴→✅ Ticket U10 — Tableau 1 « Recensement » du BLADE (`elevage-synth.blade.php`), dix colonnes : Date, Lot /
  /// Souche, Effectif M, Effectif F, Sous Mères, Sevrés, Achats, Nés, Morts, Effectif Final.
  ///
  /// Le poste portait les treize colonnes de la maquette, toutes en tiret ; le web est maître (article 5) : il
  /// affiche les colonnes que la fiche porte réellement. `{{ $e->effectif_m }}` d'une valeur absente rend une
  /// cellule VIDE au web : le poste aussi (ni « — » ni 0).
  static List<LigneRapport> elevageRecensement(
    List<LivestockDailyEntry> fiches,
    List<LivestockLot> bandes,
  ) {
    final codeDe = {for (final b in bandes) b.id: b.code};
    String vide(int? v) => v == null ? '' : '$v';

    return [
      for (final f in fiches)
        LigneRapport([
          date(f.entryDate),
          codeDe[f.lotId] ?? '',
          vide(f.effectifM),
          vide(f.effectifF),
          vide(f.effectifSmeres),
          vide(f.effectifSevres),
          '${f.achat}',
          '${f.ne}',
          '${f.mort}',
          '${f.effectifFinal}',
        ]),
    ];
  }

  /// 🔴→✅ Ticket U10 — Tableau 2 « Mouvements, Traitements & Ventes » du BLADE, neuf colonnes, cellules du web :
  /// `vente_sexe ?? '—'`, `vente` (0 compris), `number_format(vente_montant, 0, ',', ' ')` (« 0 » sans montant, comme
  /// PHP), `effectif_final`, `treatmentProduct?->name ?? '—'`, `treatment_dose ?? '—'`, `symptomes ?: 'RAS'`.
  /// Les cinq colonnes jadis en tiret descendent au poste depuis U10 (schéma v45).
  static List<LigneRapport> elevageMouvements(
    List<LivestockDailyEntry> fiches,
    List<LivestockLot> bandes,
    Map<String, String> nomProduit,
  ) {
    final codeDe = {for (final b in bandes) b.id: b.code};
    // `?:` de PHP : chaîne vide et « 0 » sont fausses.
    String symptomes(String? s) =>
        s == null || s.isEmpty || s == '0' ? 'RAS' : s;

    return [
      for (final f in fiches)
        LigneRapport([
          date(f.entryDate),
          codeDe[f.lotId] ?? '',
          f.venteSexe ?? '—',
          '${f.vente}',
          PmpService.francs(f.venteMontant ?? 0),
          '${f.effectifFinal}',
          (f.treatmentProductId == null
                  ? null
                  : nomProduit[f.treatmentProductId]) ??
              '—',
          f.treatmentDose ?? '—',
          symptomes(f.symptomes),
        ]),
    ];
  }

  /// Tableau 3 — Suivi Intégral de la Ponte : le tableau du WEB (`ElevageSynth` et son Blade), onze colonnes.
  ///
  /// 🔴→✅ **TICKET U9 — MÊME TABLEAU QU'AU WEB.** Le poste calculait des soldes PAR BANDE, EN ŒUFS, depuis ses
  /// fiches et ses lignes de vente ; le web tient des soldes de FERME, EN PLATEAUX, lus dans le grand livre des
  /// stocks (`EggStockLedgerService`) — qui descend au poste depuis U9 ([JournalStocks]). Le web est maître
  /// (article 5) : mêmes colonnes (dont « Lot »), mêmes unités, même périmètre, même calcul.
  ///
  ///   Lignes : les fiches de la période dont la ponte est > 0, de la plus récente à la plus ancienne.
  ///   Âge (Sem.) = `intdiv(création de la bande → jour de la fiche, en jours, 7)` (signé, tronqué) ; « — » sans date.
  ///   Taux Ponte % = `number_format(OR ÷ Effectif Final × 100, 1)` puis « % », « — % » sans effectif.
  ///   Commercialisables = OR − OF, tels quels.
  ///   SRH / TS / OS / Stock Final : `EggStockLedgerService::ligne(jour, Σ max(0, OR − OF) des fiches du JOUR)` —
  ///   le même solde pour deux bandes pondeuses du même jour (le stock d'œufs est tenu au niveau du produit).
  static List<LigneRapport> elevagePonte(
    List<LivestockDailyEntry> periode,
    List<LivestockLot> bandes,
    JournalStocks journal,
    String? produitOeufs,
  ) {
    final bandeDe = {for (final b in bandes) b.id: b};
    final pondeuses = [
      for (final f in periode)
        if ((f.ponteTotal ?? 0) > 0) f,
    ]..sort(ordreDesFiches);

    // `getLedgerOeufsProperty()` : une ligne du grand livre par JOUR affiché, production commercialisable du jour
    // agrégée une seule fois.
    final commercialisablesDuJour = <DateTime, int>{};
    for (final f in pondeuses) {
      final j = JournalStocks.jour(f.entryDate);
      final c = f.ponteTotal! - (f.ponteCasses ?? 0);
      commercialisablesDuJour[j] =
          (commercialisablesDuJour[j] ?? 0) + (c < 0 ? 0 : c);
    }
    final grandLivre = {
      for (final e in commercialisablesDuJour.entries)
        e.key: journal.ligneOeufs(produitOeufs, e.key, e.value),
    };

    String entier(double v) => PmpService.nombre(v, 0);

    return [
      for (final f in pondeuses)
        () {
          final bande = bandeDe[f.lotId];
          final l = grandLivre[JournalStocks.jour(f.entryDate)]!;
          final or = f.ponteTotal!;
          return LigneRapport([
            ageEnSemaines(bande?.createdDate, f.entryDate),
            date(f.entryDate),
            bande?.code ?? '',
            '$or',
            '${f.effectifFinal > 0 ? PmpService.nombre(or / f.effectifFinal * 100, 1, virgule: '.', milliers: ',') : '—'} %',
            f.ponteCasses == null ? '' : '${f.ponteCasses}',
            '${or - (f.ponteCasses ?? 0)}',
            entier(l.srh),
            entier(l.ts),
            entier(l.os),
            '${entier(l.stockFinal)} plateaux${l.vrac > 0 ? ' + ${l.vrac} vrac' : ''}',
          ]);
        }(),
    ];
  }

  /// Colonne « Âge (Sem.) » du Blade : `intdiv($lot->created_date->diffInDays($e->entry_date), 7)` — Carbon 3 rend
  /// un écart SIGNÉ (une fiche antérieure à la création de la bande donne un âge négatif), `intdiv` tronque vers
  /// zéro ; « — » si la bande n'a pas de date de création.
  static String ageEnSemaines(DateTime? creation, DateTime jour) {
    if (creation == null) return '—';
    final jours = DateTime.utc(
      jour.year,
      jour.month,
      jour.day,
    ).difference(DateTime.utc(creation.year, creation.month, creation.day)).inDays;
    return '${jours ~/ 7}';
  }

  /// Tableau 3 du PDF du web (`exports/elevage-synth.blade.php`) : les fiches à ponte > 0, six colonnes — Jour, Lot,
  /// Œufs Récoltés, Taux Ponte % (`number_format(…, 1)` puis « % », « — % » sans effectif), Cassés (vide si absent),
  /// Commercialisables (`ponte_total - ponte_casses`, une casse absente valant 0).
  static List<LigneRapport> elevagePonteExport(
    List<LivestockDailyEntry> periode,
    List<LivestockLot> bandes,
  ) {
    final codeDe = {for (final b in bandes) b.id: b.code};
    return [
      for (final f in periode)
        if ((f.ponteTotal ?? 0) > 0)
          LigneRapport([
            date(f.entryDate),
            codeDe[f.lotId] ?? '',
            '${f.ponteTotal}',
            '${f.effectifFinal > 0 ? PmpService.nombre(f.ponteTotal! / f.effectifFinal * 100, 1, virgule: '.', milliers: ',') : '—'} %',
            f.ponteCasses == null ? '' : '${f.ponteCasses}',
            '${f.ponteTotal! - (f.ponteCasses ?? 0)}',
          ]),
    ];
  }

  /// 🔴→✅ Ticket U10 — `ElevageSynth::getKpisProperty()`, formule pour formule (le poste reconstituait l'effectif
  /// de début de CHAQUE journée et moyennait autrement ; le web est maître) :
  ///
  ///   Production Totale = Σ ponte_total ;
  ///   Taux de Ponte Moyen = round(moyenne des OR ÷ Effectif Final × 100, 1), fiches à effectif ET ponte > 0 ;
  ///   Taux de Mortalité Hebdo = round(Σ morts ÷ Effectif Début × 100, 1), Effectif Début = `previousEffectif()` de
  ///     la fiche la PLUS ANCIENNE de la sélection : effectif final de la fiche précédente de SA bande (toutes dates,
  ///     hors période), sinon effectif initial de la bande ; « — » s'il est nul ;
  ///   CA Ventes du Lot = Σ vente_montant.
  ///
  /// [periode] : les fiches affichées (période et bande), de la plus récente à la plus ancienne ; [toutes] : toutes
  /// les fiches connues du serveur (pour la fiche précédente).
  static IndicateursElevage indicateursElevage(
    List<LivestockDailyEntry> periode,
    List<LivestockDailyEntry> toutes,
    List<LivestockLot> bandes,
  ) {
    final production = periode.fold<int>(0, (t, f) => t + (f.ponteTotal ?? 0));

    final taux = [
      for (final f in periode)
        if (f.effectifFinal > 0 && (f.ponteTotal ?? 0) > 0)
          f.ponteTotal! / f.effectifFinal * 100,
    ];

    final morts = periode.fold<int>(0, (t, f) => t + f.mort);
    // `$entries->sortBy('entry_date')->first()` : tri STABLE croissant de la liste triée par [ordreDesFiches] —
    // entre deux fiches du même jour, l'identifiant croissant reste en tête (ticket U11 ; `List.sort` de Dart n'est
    // pas stable : le second critère est écrit).
    final croissant = [...periode]
      ..sort((a, b) {
        final parJour = JournalStocks.jour(
          a.entryDate,
        ).compareTo(JournalStocks.jour(b.entryDate));
        return parJour != 0 ? parJour : a.id.compareTo(b.id);
      });
    final premiere = croissant.isEmpty ? null : croissant.first;
    final debut = premiere == null
        ? 0
        : effectifPrecedent(premiere, toutes, bandes);

    return IndicateursElevage(
      productionTotale: production,
      tauxPonteMoyen: taux.isEmpty
          ? null
          : PmpService.arrondi(taux.reduce((a, b) => a + b) / taux.length, 1),
      mortaliteHebdo: debut > 0
          ? PmpService.arrondi(morts / debut * 100, 1)
          : null,
      chiffreAffaires: periode.fold<double>(
        0,
        (t, f) => t + (f.venteMontant ?? 0),
      ),
    );
  }

  /// `LivestockDailyEntry::previousEffectif()` : effectif final de la fiche de la même bande au jour STRICTEMENT
  /// antérieur le plus récent, sinon `initial_quantity` de la bande, sinon 0.
  ///
  /// Ticket U11 — la règle vit dans `elevage/effectif_precedent.dart`, partagée avec la fiche Pondeuses.
  static int effectifPrecedent(
    LivestockDailyEntry fiche,
    List<LivestockDailyEntry> toutes,
    List<LivestockLot> bandes,
  ) => effectifPrecedentDe(fiche, toutes, bandes);

  // ── Onglet 6 : Rapport de Stocks ──────────────────────────────────────────

  /// 🔴→✅ Ticket U12b — `StocksSynth::getRowsProperty()`, règle pour règle (le poste valorisait au PRIX DE VENTE
  /// minimal et rangeait les produits sans catégorie dans « Sans catégorie ») :
  ///
  ///   catégories ACTIVES ayant au moins un produit actif, par libellé (`orderBy('label')`, collation du serveur) ;
  ///   Valeur Stock = `round(Σ Product::valeurStock() ?? 0, 2)`, soit `round(max(0, stock) × PMP, 2)` par produit
  ///   actif, 0 pour un produit sans PMP (jamais acheté) — le PMP est celui de [PmpService] (`computePmp()`) ;
  ///   Sous Seuil = produits dont le seuil existe et `stock <= seuil` ; plus les deux comptes que la cellule
  ///   mentionne : produits en stock négatif, produits jamais achetés mais en stock.
  ///
  /// La recherche (sur le libellé) est appliquée à l'affichage par [filtrerStocks].
  static List<StockCategorie> stocksDe(
    List<Product> produits,
    List<ProductCategory> categories,
    Map<String, double> pmpDe,
  ) {
    final actives = categories.where((c) => c.isActive).toList()
      ..sort((a, b) => comparerCommeLeServeur(a.label, b.label));
    return [
      for (final c in actives)
        if (produits.any((p) => p.isActive && p.categoryId == c.id))
          () {
            final duRayon = [
              for (final p in produits)
                if (p.isActive && p.categoryId == c.id) p,
            ];
            double? valeurStock(Product p) {
              final pmp = pmpDe[p.id];
              return pmp == null
                  ? null
                  : PmpService.arrondi(
                      (p.stockQty < 0 ? 0.0 : p.stockQty) * pmp,
                      2,
                    );
            }

            return StockCategorie(
              categorie: c.label,
              valeur: PmpService.arrondi(
                duRayon.fold<double>(0, (t, p) => t + (valeurStock(p) ?? 0)),
                2,
              ),
              sousSeuil: duRayon
                  .where(
                    (p) =>
                        p.alertThreshold != null &&
                        p.stockQty <= p.alertThreshold!,
                  )
                  .length,
              nonValorises: duRayon
                  .where((p) => pmpDe[p.id] == null && p.stockQty > 0)
                  .length,
              negatifs: duRayon.where((p) => p.stockQty < 0).length,
            );
          }(),
    ];
  }

  /// Mention de la cellule « Valeur Stock » du Blade pour les produits en stock négatif.
  static String mentionNegatifs(int n) =>
      '($n produit(s) en stock négatif, retenus à zéro)';

  /// Mention de la cellule « Valeur Stock » du Blade pour les produits jamais achetés mais en stock.
  static String mentionNonValorises(int n) =>
      '($n produit(s) jamais achetés, non valorisés)';

  /// Texte complet de la cellule « Valeur Stock » (« N FCFA », puis les mentions utiles), espaces normalisés.
  static String texteValeurStock(StockCategorie l) => [
    '${PmpService.francs(l.valeur)} FCFA',
    if (l.negatifs > 0) mentionNegatifs(l.negatifs),
    if (l.nonValorises > 0) mentionNonValorises(l.nonValorises),
  ].join(' ');

  /// `->when($this->search, fn ($q) => $q->where('label', 'like', '%'.$this->search.'%'))` : sans casse ni accents.
  static List<StockCategorie> filtrerStocks(
    List<StockCategorie> lignes,
    String recherche,
  ) {
    if (!_rechercheActive(recherche)) return lignes;
    final terme = cleCommeLeServeur(recherche);
    return [
      for (final l in lignes)
        if (cleCommeLeServeur(l.categorie).contains(terme))
          l,
    ];
  }

  // ── Exports « Excel » : le CSV du web, en classeur ────────────────────────
  //
  // Ticket U12b — chaque `exportReport('csv')` du web écrit un CSV ; le poste écrit un classeur `.xlsx` (ajout validé
  // par le client, voir `ExportTableur`) aux MÊMES lignes : même en-tête, mêmes colonnes, mêmes valeurs brutes (un
  // flottant PHP tel qu'il s'écrit, une date `d/m/Y`, un nom absent vide). Seuls les guillemets du CSV disparaissent :
  // une cellule de classeur n'en a pas besoin.

  /// `RecettesDepenses::exportReport('csv')` : « Type,Date,Libellé,Montant », recettes puis dépenses (montant négatif).
  static List<List<String>> classeurRecettesDepenses(DonneesRapports d) => [
    const ['Type', 'Date', 'Libellé', 'Montant'],
    for (final r in d.recettes)
      ['Recette', date(r.date), r.libelle, PmpService.flottant(r.montant)],
    for (final m in d.depenses)
      ['Dépense', date(m.date), m.libelle, '-${PmpService.flottant(m.montant)}'],
  ];

  /// `Tresorerie::exportReport('csv')`.
  static List<List<String>> classeurTresorerie(DonneesRapports d) => [
    const ['Date', 'Solde Caisse', 'Solde Banque', 'Solde Total'],
    for (final s in d.tresorerie)
      [
        date(s.date),
        PmpService.flottant(s.caisse),
        PmpService.flottant(s.banque),
        PmpService.flottant(s.total),
      ],
  ];

  /// `Creances::exportReport('csv')` / `Dettes::exportReport('csv')` ([entete] : « Client » ou « Fournisseur »).
  static List<List<String>> classeurEcheances(
    String entete,
    List<EcheanceRapport> lignes,
  ) => [
    [entete, 'Montant Dû', 'Échéance'],
    for (final e in lignes)
      [e.nom ?? '', PmpService.flottant(e.reste), date(e.echeance)],
  ];

  /// `StocksSynth::exportReport('csv')`.
  static List<List<String>> classeurStocks(List<StockCategorie> lignes) => [
    const ['Catégorie', 'Valeur Stock', 'Sous Seuil'],
    for (final l in lignes)
      [l.categorie, PmpService.flottant(l.valeur), '${l.sousSeuil}'],
  ];

  /// `ElevageSynth::exportReport('csv')` : en-tête du web.
  static const enteteClasseurElevage = [
    'Date',
    'Lot',
    'Effectif M',
    'Effectif F',
    'Sous Mères',
    'Sevrés',
    'Morts',
    'Achats',
    'Nés',
    'Effectif Final',
    'Vente Qté',
    'Vente Montant',
    'Ponte Totale',
    'Ponte Cassés',
  ];

  /// Une ligne par fiche, dans l'ordre des tableaux : une valeur absente s'écrit vide (`implode` de PHP), le montant
  /// de vente avec deux décimales (`vente_montant` est un `decimal:2` au web).
  static List<List<String>> elevageClasseurDe(
    List<LivestockDailyEntry> fiches,
    List<LivestockLot> bandes,
  ) {
    final codeDe = {for (final b in bandes) b.id: b.code};
    String vide(int? v) => v == null ? '' : '$v';
    return [
      for (final f in fiches)
        [
          date(f.entryDate),
          codeDe[f.lotId] ?? '',
          vide(f.effectifM),
          vide(f.effectifF),
          vide(f.effectifSmeres),
          vide(f.effectifSevres),
          '${f.mort}',
          '${f.achat}',
          '${f.ne}',
          '${f.effectifFinal}',
          '${f.vente}',
          f.venteMontant == null
              ? ''
              : PmpService.nombre(f.venteMontant!, 2, virgule: '.', milliers: ''),
          vide(f.ponteTotal),
          vide(f.ponteCasses),
        ],
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
