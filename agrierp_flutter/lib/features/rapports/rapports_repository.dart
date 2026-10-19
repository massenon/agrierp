import 'package:drift/drift.dart' show OrderingTerm, OrderingMode;

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../stocks/journal_stocks.dart';
import '../stocks/pmp_service.dart';

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

  /// Ticket U10 — options du filtre « Lot / Souche » : bandes ACTIVES triées par code (`ElevageSynth::getLotsProperty()`).
  final List<LivestockLot> bandesElevage;

  /// Ticket U10 — Tableau 3 du PDF du web (`exports/elevage-synth.blade.php`) : Jour, Lot, Œufs Récoltés, Taux Ponte
  /// %, Cassés, Commercialisables.
  final List<LigneRapport> elevageT3Export;

  final List<LigneRapport> stocks;
}

/// Lectures de `prototype_html/rapports-exports.html` et de ses six pages.
///
/// ⚠️⚠️ **CES RAPPORTS NE COUVRENT QUE CE QUE LE POSTE DÉTIENT, ET LE DISENT.**
///
/// 1. ~~Les fiches d'élevage ne sont jamais tirées~~ — 🔴→✅ elles descendent depuis F0.94 (journées du serveur ET
///    saisies ici).
/// 2. ~~Onze colonnes de la fiche ne descendent pas~~ — 🔴→✅ la ventilation par sexe et par état descend depuis
///    F0.95 ; `vente_sexe`, `vente_montant`, le traitement, la dose et les symptômes depuis U10 (schéma v45). Les
///    Tableaux 1 et 2 et les indicateurs sont ceux du Blade (`ElevageSynth`), formule pour formule.
/// 3. **Aucune série journalière de trésorerie** — voir [PositionTresorerie].
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
    // Ticket U9 — grand livre des stocks (descendu + saisies en attente) : Tableau 3 de la ponte.
    final journal = await JournalStocks.charger(
      database,
      maintenant: DateTime.now(),
    );

    final fiches =
        await (database.select(database.livestockDailyEntries)..orderBy([
              (t) => OrderingTerm(
                expression: t.entryDate,
                mode: OrderingMode.desc,
              ),
            ]))
            .get();

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
      elevageT1: elevageRecensement(dansLaPeriode, bandes),
      elevageT2: elevageMouvements(dansLaPeriode, bandes, nomProduit),
      elevageT3: elevagePonte(
        dansLaPeriode,
        bandes,
        journal,
        JournalStocks.produitOeufs(produits)?.id,
      ),
      elevageT3Export: elevagePonteExport(dansLaPeriode, bandes),
      indicateurs: indicateursElevage(dansLaPeriode, connues, bandes),
      bandesElevage:
          bandes.where((b) => b.isActive).toList()
            ..sort((a, b) => comparerCommeLeServeur(a.code, b.code)),
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
    ]..sort((a, b) => b.entryDate.compareTo(a.entryDate));

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
    // `$entries->sortBy('entry_date')->first()` : tri STABLE croissant de la liste décroissante.
    final croissant = [...periode]
      ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
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
  static int effectifPrecedent(
    LivestockDailyEntry fiche,
    List<LivestockDailyEntry> toutes,
    List<LivestockLot> bandes,
  ) {
    final jour = JournalStocks.jour(fiche.entryDate);
    LivestockDailyEntry? precedente;
    for (final f in toutes) {
      if (f.lotId != fiche.lotId ||
          f.id == fiche.id ||
          !JournalStocks.jour(f.entryDate).isBefore(jour)) {
        continue;
      }
      if (precedente == null || f.entryDate.isAfter(precedente.entryDate)) {
        precedente = f;
      }
    }
    if (precedente != null) return precedente.effectifFinal;
    for (final b in bandes) {
      if (b.id == fiche.lotId) return b.initialQuantity;
    }
    return 0;
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
