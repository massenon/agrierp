import 'dart:math' as math;

import '../../core/audit/libelles_audit.dart';
import '../../core/auth/permissions_poste.dart';
import '../../core/database/app_database.dart';

/// Une mesure du tableau de bord : un chiffre, ou une absence assumée.
///
/// ⚠️⚠️ **`null` N'EST PAS `0`.** Un zéro se lit comme une mesure — « la ferme
/// n'a aucune créance » — là où la vérité est « le poste ne reçoit pas la
/// table des créances ». Les deux se rendent différemment à l'écran et la
/// distinction se perd si on les confond ici.
class Mesure {
  const Mesure.chiffre(double this.valeur) : motifAbsence = null;

  const Mesure.absente(String this.motifAbsence) : valeur = null;

  final double? valeur;

  /// Pourquoi la mesure n'existe pas au poste. Affiché en sous-ligne.
  final String? motifAbsence;

  bool get disponible => valeur != null;
}

/// Une alerte de la colonne « Alertes Critiques » — `Index::getAlertesCritiquesProperty()`.
class AlerteCritique {
  const AlerteCritique({
    required this.message,
    required this.grave,
    required this.lien,
  });

  final String message;

  /// Sévérité `critique` du web (fond `error-bg`) ; sinon `moyen` (fond jaune).
  final bool grave;

  /// Adresse web de l'alerte (`link`), d'où le poste déduit l'écran à ouvrir.
  final String lien;
}

/// Une carte de la bande Lapins · Volailles · Porcs — `Index::getCartesElevageProperty()`.
class CarteEspece {
  const CarteEspece({
    required this.titre,
    required this.mesures,
    required this.mortalite,
  });

  final String titre;

  /// Trois premières mesures, `(libellé, valeur affichable)`, dans l'ordre du Blade.
  final List<(String, String)> mesures;

  /// Quatrième mesure, toujours « Mortalité » : `round(…, 1)` du PHP, 0,0 sans fiche. Séparée parce que sa
  /// couleur dépend du seuil (`> 5`).
  final double mortalite;
}

/// Un mois de la courbe « CA vs Dépenses » et des « Statistiques de Ventes ».
class PointMensuel {
  const PointMensuel({
    required this.libelle,
    required this.chiffreAffaires,
    required this.depenses,
  });

  final String libelle;
  final double chiffreAffaires;
  final double depenses;
}

/// Couleur du montant d'une ligne de « Transactions Récentes », reprise des classes du Blade.
enum TonMontant {
  /// `text-brand-emerald` : vente ou facture hors crédit.
  emeraude,

  /// `text-brand-forest` : achat au comptant.
  foret,

  /// `text-accent-yellow` : vente à crédit, achat non comptant.
  jaune,

  /// `text-info-blue` : devis.
  bleu,

  /// `text-error-red` : dépense.
  rouge,
}

/// Une ligne des « Transactions Récentes ».
class LigneTransaction {
  const LigneTransaction({
    required this.libelle,
    required this.montant,
    required this.ton,
  });

  final String libelle;
  final double montant;
  final TonMontant ton;
}

/// Une ligne des « Activités du Jour » : l'action, puis « HH:mm — auteur · module ».
class LigneActivite {
  const LigneActivite({required this.libelle, required this.detail});

  final String libelle;
  final String detail;
}

/// Une ligne du « Top 5 Produits du Mois ».
class LigneTopProduit {
  const LigneTopProduit({
    required this.produit,
    required this.quantite,
    required this.chiffreAffaires,
    required this.margePct,
  });

  /// Nom du produit, « — » s'il est inconnu du poste (`$row['product']?->name ?? '—'`).
  final String produit;
  final double quantite;
  final double chiffreAffaires;

  /// Marge en %, `null` → « — ».
  final int? margePct;
}

/// Tout ce que la vue Blade du tableau de bord affiche, dans son ordre.
class DonneesTableauDeBord {
  const DonneesTableauDeBord({
    required this.debutPeriode,
    required this.finPeriode,
    required this.chiffreAffaires,
    required this.legendeChiffreAffaires,
    required this.tresorerie,
    required this.tresorerieParType,
    required this.depenses,
    required this.legendeDepenses,
    required this.resultatNet,
    required this.legendeResultatNet,
    required this.creances,
    required this.dettes,
    required this.produitsSousSeuil,
    required this.effectifAnimaux,
    required this.alertes,
    required this.especes,
    required this.serie,
    required this.ventesRecentes,
    required this.achatsRecents,
    required this.depensesRecentes,
    required this.facturesRecentes,
    required this.activitesDuJour,
    required this.topProduits,
    this.exerciceOuvert,
  });

  /// Ticket H5 — année de l'exercice OUVERT (`FiscalYear::current()` : statut `ouvert`, le plus récent), affichée
  /// « · Exercice {année} actif » comme au web ; `null` : « · Aucun exercice ouvert ». 🔴 Le poste affichait l'année
  /// du CALENDRIER, même sans exercice ouvert.
  final int? exerciceOuvert;

  /// Période AFFICHÉE (champs désactivés du Blade) : 1er du mois → aujourd'hui.
  final DateTime debutPeriode;
  final DateTime finPeriode;

  final Mesure chiffreAffaires;

  /// « Mois précédent : X F (±y,z%) », `null` sans valeur.
  final String? legendeChiffreAffaires;
  final Mesure tresorerie;
  final Map<String, double> tresorerieParType;
  final Mesure depenses;
  final String? legendeDepenses;
  final Mesure resultatNet;

  /// « Marge nette : X% », `null` quand le CA n'est pas positif.
  final String? legendeResultatNet;
  final Mesure creances;
  final Mesure dettes;
  final List<Product> produitsSousSeuil;
  final Mesure effectifAnimaux;
  final List<AlerteCritique> alertes;
  final List<CarteEspece> especes;

  /// Les six derniers mois, le courant en dernier (courbe ET histogramme, comme le web).
  final List<PointMensuel> serie;
  final List<LigneTransaction> ventesRecentes;
  final List<LigneTransaction> achatsRecents;
  final List<LigneTransaction> depensesRecentes;
  final List<LigneTransaction> facturesRecentes;
  final List<LigneActivite> activitesDuJour;
  final List<LigneTopProduit> topProduits;
}

/// Lectures du Tableau de Bord — ticket H5 : **la vue Blade et `Dashboard/Index.php` font foi.**
///
/// Chaque calcul ci-dessous est la transposition d'une méthode du composant Livewire, citée à son endroit, avec
/// SES filtres et SES arrondis — y compris là où ils surprennent (vente annulée comptée au CA, jours de retard
/// signés) : ces deux-là sont marqués « reproduit, signalé au web » à leur endroit, le web corrige d'abord.
///
/// ⚠️ **TOUT EST CALÉ SUR LE MOIS COURANT**, comme le web : sa période « Du / au » est désactivée. Le poste
/// affiche les mêmes deux champs, désactivés aussi.
///
/// ⚠️ Depuis 14.79/14.80, `sales`, `purchases`, `payables`, `receivables`, `customers` et
/// `livestock_reproduction_events` descendent au poste : les mentions « Ce poste uniquement » et « Table non
/// synchronisée » étaient fausses. Restent propres au poste (non servies par le tirage) : `sale_lines`,
/// `purchase_lines` et `expenses` — voir le Top 5, « Ventes (mois) » et l'onglet Dépenses.
class TableauDeBordRepository {
  TableauDeBordRepository({required this.database, DateTime Function()? horloge})
    : _horloge = horloge ?? DateTime.now;

  final AppDatabase database;
  final DateTime Function() _horloge;

  /// Seuil de couleur des cartes espèces : `$x['mortalite'] > 5` dans le Blade (strict).
  static const double seuilMortaliteCarte = 5;

  /// Seuil de l'alerte « Mortalité anormale » : `AlertesElevageService::SEUIL_MORTALITE_JOUR`, comparé par `>=`.
  static const double seuilMortaliteAlerte = 5;

  Future<DonneesTableauDeBord> charger() async {
    final maintenant = _horloge();
    final debutMois = DateTime(maintenant.year, maintenant.month);
    // `now()->subMonthNoOverflow()->startOfMonth()` / `->endOfMonth()` (23:59:59.999999).
    final debutPrecedent = DateTime(maintenant.year, maintenant.month - 1);
    final finPrecedent = debutMois.subtract(const Duration(microseconds: 1));

    final ventes = await database.select(database.sales).get();
    // Ticket H5 — `Sale::nonAnnulees()` du web (corrigé au web d'abord) : une vente annulée ne compte ni au CA, ni à
    // la courbe, ni aux ventes du mois, ni au Top 5. Les LISTES (transactions récentes, factures) la montrent encore.
    final ventesValides = ventes.where((v) => v.status != 'annulee').toList();
    final lignes = await database.select(database.saleLines).get();
    final produits = await database.select(database.products).get();
    final categories = await database.select(database.productCategories).get();
    final achats = await database.select(database.purchases).get();
    final depenses = await database.select(database.expenses).get();
    final comptes = await database.select(database.treasuryAccounts).get();
    final creances = await database.select(database.receivables).get();
    final dettes = await database.select(database.payables).get();
    final clients = await database.select(database.customers).get();
    final toutesBandes = await database.select(database.livestockLots).get();
    final fiches = await database.select(database.livestockDailyEntries).get();
    final cycles = await database
        .select(database.livestockReproductionEvents)
        .get();
    final journal = await database.select(database.auditLogs).get();

    // ── KPI (`getKpisProperty`) ─────────────────────────────────────────────────────────────────────────
    double caEntre(DateTime du, DateTime? au) => ventesValides
        .where((v) => !v.soldAt.isBefore(du) && (au == null || !v.soldAt.isAfter(au)))
        .fold<double>(0, (t, v) => t + v.total);
    double achatsEntre(DateTime du, DateTime? au) => achats
        .where(
          (a) =>
              !a.purchaseDate.isBefore(du) &&
              (au == null || !a.purchaseDate.isAfter(au)),
        )
        .fold<double>(0, (t, a) => t + a.total);

    final ca = caEntre(debutMois, null);
    final caPrecedent = caEntre(debutPrecedent, finPrecedent);
    // ⚠️ « Dépenses » = ACHATS (`Purchase.total`), pas les charges (`expenses`) : c'est le KPI du web.
    final totalAchats = achatsEntre(debutMois, null);
    final achatsPrecedents = achatsEntre(debutPrecedent, finPrecedent);
    final resultat = ca - totalAchats;

    final parType = <String, double>{};
    for (final c in comptes) {
      parType[(c.type ?? 'autre')] =
          (parType[c.type ?? 'autre'] ?? 0) + c.balance;
    }

    // `Product::where('is_active', true)->whereColumn('stock_qty', '<=', 'alert_threshold')` — un seuil NULL
    // ne compare jamais en SQL.
    final sousSeuil = produits
        .where(
          (p) =>
              p.isActive &&
              p.alertThreshold != null &&
              p.stockQty <= p.alertThreshold!,
        )
        .toList();

    // `LivestockLot::where('is_active', true)->where('status', 'actif')`.
    final bandesActives = toutesBandes.where(_vivante).toList();
    final effectif = bandesActives.fold<int>(0, (t, b) => t + b.currentQuantity);

    final nomsClients = {for (final c in clients) c.id: c.name};

    final exercices = await (database.select(database.fiscalYears)..where((e) => e.status.equals('ouvert'))).get();
    final exerciceOuvert = exercices.isEmpty ? null : exercices.map((e) => e.year).reduce((a, b) => a > b ? a : b);

    return DonneesTableauDeBord(
      exerciceOuvert: exerciceOuvert,
      debutPeriode: debutMois,
      finPeriode: maintenant,
      chiffreAffaires: Mesure.chiffre(ca),
      legendeChiffreAffaires: legendeMoisPrecedent(ca, caPrecedent),
      tresorerie: Mesure.chiffre(
        comptes.fold<double>(0, (t, c) => t + c.balance),
      ),
      tresorerieParType: parType,
      depenses: Mesure.chiffre(totalAchats),
      legendeDepenses: legendeMoisPrecedent(totalAchats, achatsPrecedents),
      // `$ca['value'] - $depenses['value']` : CA du mois − achats du mois.
      resultatNet: Mesure.chiffre(resultat),
      legendeResultatNet: legendeMargeNette(resultat, ca),
      // ⚠️ LE RESTE DÛ, PAS LE MONTANT FACTURÉ, et seulement `amount_paid < amount` (`Receivable::balance`).
      creances: Mesure.chiffre(
        creances
            .where((c) => c.amountPaid < c.amount)
            .fold<double>(0, (t, c) => t + _arrondi(c.amount - c.amountPaid, 2)),
      ),
      // 🔴→✅ H5 — `payables` descend depuis 14.79 : « Table non synchronisée » était faux. Même règle.
      dettes: Mesure.chiffre(
        dettes
            .where((d) => d.amountPaid < d.amount)
            .fold<double>(0, (t, d) => t + _arrondi(d.amount - d.amountPaid, 2)),
      ),
      produitsSousSeuil: sousSeuil,
      effectifAnimaux: Mesure.chiffre(effectif.toDouble()),
      alertes: _alertes(
        maintenant,
        sousSeuil,
        toutesBandes,
        fiches,
        creances,
        nomsClients,
      ),
      especes: _cartesEspeces(
        debutMois,
        toutesBandes,
        fiches,
        cycles,
        ventesValides,
        lignes,
        produits,
        categories,
      ),
      serie: _serie(ventesValides, achats, maintenant),
      ventesRecentes: _ventes(ventes, nomsClients),
      achatsRecents: _achats(achats),
      depensesRecentes: _depenses(depenses),
      // Facturation = `Sale` dont `mecef_status = 'transmise'` (pas de modèle `Invoice`).
      facturesRecentes: _ventes(
        ventes.where((v) => v.mecefStatus == 'transmise').toList(),
        nomsClients,
      ),
      activitesDuJour: _activites(journal, maintenant),
      topProduits: _topProduits(debutMois, ventesValides, lignes, produits),
    );
  }

  /// `is_active = true` ET `status = 'actif'` — le scope `vivantes()` et les filtres du tableau de bord.
  static bool _vivante(LivestockLot b) => b.isActive && b.status == 'actif';

  // ── Alertes (`getAlertesCritiquesProperty`) ─────────────────────────────────────────────────────────

  List<AlerteCritique> _alertes(
    DateTime maintenant,
    List<Product> sousSeuil,
    List<LivestockLot> bandes,
    List<LivestockDailyEntry> fiches,
    List<Receivable> creances,
    Map<String, String> nomsClients,
  ) {
    final alertes = <AlerteCritique>[];

    // 1. Stock : `->limit(5)`, libellé `{$product->stock_qty}` — cast `decimal:2`, donc « 5.00 » (point).
    for (final p in sousSeuil.take(5)) {
      alertes.add(
        AlerteCritique(
          message:
              'Stock critique — ${p.name} '
              '(${p.stockQty.toStringAsFixed(2)} ${p.unit} restant(s))',
          grave: true,
          lien: '/gestion-stocks',
        ),
      );
    }

    // 2. Mortalité : `AlertesElevageService::mortalitesAnormales()` — fiches du jour J−7 et après, bandes
    //    vivantes, PIRE JOUR par bande (taux rapporté à la fiche précédente ou à l'effectif initial), ≥ 5 %.
    final parId = {for (final b in bandes) b.id: b};
    final depuis = DateTime(maintenant.year, maintenant.month, maintenant.day - 7);
    final pires = <String, (LivestockDailyEntry, double)>{};
    for (final f in fiches) {
      final b = parId[f.lotId];
      if (b == null || !_vivante(b) || _jour(f.entryDate).isBefore(depuis)) {
        continue;
      }
      final taux = _tauxMortalite(f, b, fiches);
      final actuel = pires[f.lotId];
      // `sortByDesc(...)->first()` : à égalité, la première fiche lue reste.
      if (actuel == null || taux > actuel.$2) pires[f.lotId] = (f, taux);
    }
    for (final MapEntry(key: lot, value: (_, taux)) in pires.entries) {
      if (taux < seuilMortaliteAlerte) continue;
      alertes.add(
        AlerteCritique(
          message: 'Mortalité anormale — Lot ${parId[lot]!.code} (${nombre(taux, 1)}%)',
          grave: true,
          lien: '/gestion-bandes',
        ),
      );
    }

    // 3. Créances en retard : solde non nul, échéance dépassée, `->limit(3)`.
    //    Ticket H5 — le retard se compte de l'échéance à aujourd'hui, en jours calendaires (le web affichait
    //    « (-10 jours) », corrigé au web d'abord).
    for (final c
        in creances
            .where(
              (c) =>
                  c.amountPaid < c.amount &&
                  c.dueDate != null &&
                  c.dueDate!.isBefore(maintenant),
            )
            .take(3)) {
      final echeance = DateTime(c.dueDate!.year, c.dueDate!.month, c.dueDate!.day);
      final jours = DateTime(maintenant.year, maintenant.month, maintenant.day).difference(echeance).inDays;
      alertes.add(
        AlerteCritique(
          message:
              'Créance en retard — ${nomsClients[c.customerId] ?? ''} ($jours jours)',
          grave: false,
          lien: '/creances-clients',
        ),
      );
    }

    // `array_slice($alerts, 0, 6)`.
    return alertes.take(6).toList();
  }

  /// `LivestockDailyEntry::mortality_rate` : `round(mort / effectif précédent × 100, 2)`, 0 sans effectif.
  /// L'effectif précédent est celui de la DERNIÈRE fiche strictement antérieure de la bande, sinon l'effectif
  /// initial de la bande (`previousEffectif()`).
  static double _tauxMortalite(
    LivestockDailyEntry f,
    LivestockLot bande,
    List<LivestockDailyEntry> fiches,
  ) {
    LivestockDailyEntry? precedente;
    for (final x in fiches) {
      if (x.lotId != f.lotId || x.id == f.id) continue;
      if (!_jour(x.entryDate).isBefore(_jour(f.entryDate))) continue;
      if (precedente == null || x.entryDate.isAfter(precedente.entryDate)) {
        precedente = x;
      }
    }
    final base = precedente?.effectifFinal ?? bande.initialQuantity;
    if (base <= 0) return 0;
    return _arrondi(f.mort / base * 100, 2);
  }

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  // ── Cartes espèces (`getCartesElevageProperty`) ─────────────────────────────────────────────────────

  List<CarteEspece> _cartesEspeces(
    DateTime debutMois,
    List<LivestockLot> bandes,
    List<LivestockDailyEntry> fiches,
    List<LivestockReproductionEvent> cycles,
    List<Sale> ventes,
    List<SaleLine> lignes,
    List<Product> produits,
    List<ProductCategory> categories,
  ) {
    final especeDe = {for (final b in bandes) b.id: b.speciesCode};

    // `$effectif` : bandes actives ET `status = 'actif'`.
    int effectif(String code) => bandes
        .where((b) => _vivante(b) && b.speciesCode == code)
        .fold<int>(0, (t, b) => t + b.currentQuantity);

    // Fiches du mois des bandes `is_active` de l'espèce — ⚠️ SANS le filtre `status` (code PHP : « bande
    // archivée exclue », pas « vendue »).
    List<LivestockDailyEntry> fichesDuMois(String code) {
      final ids = bandes
          .where((b) => b.isActive && b.speciesCode == code)
          .map((b) => b.id)
          .toSet();
      return fiches
          .where((f) => ids.contains(f.lotId) && !f.entryDate.isBefore(debutMois))
          .toList();
    }

    // `$mortaliteMois` : Σ morts / Σ max(effectif_final − achat − né + mort + vente + don, 1) × 100, arrondi à
    // 1 décimale ; 0,0 sans fiche (le dénominateur vaut alors 0).
    double mortalite(String code) {
      final du = fichesDuMois(code);
      final morts = du.fold<int>(0, (t, f) => t + f.mort);
      final reference = du.fold<int>(
        0,
        (t, f) =>
            t +
            math.max(
              f.effectifFinal - f.achat - f.ne + f.mort + f.vente + f.don,
              1,
            ),
      );
      return reference > 0 ? _arrondi(morts / reference * 100, 1) : 0.0;
    }

    // `$gestantes` : cycles `en_cours` dont la bande est de l'espèce — sans filtre sur la bande.
    int gestantes(String code) => cycles
        .where((c) => c.status == 'en_cours' && especeDe[c.lotId] == code)
        .length;

    // « Marchands » : bandes vivantes au stade `engraissement`, et lui seul.
    final marchands = bandes
        .where(
          (b) =>
              _vivante(b) &&
              b.speciesCode == 'cuniculture' &&
              b.stage == 'engraissement',
        )
        .fold<int>(0, (t, b) => t + b.currentQuantity);

    final lotsActifsVolailles = bandes
        .where((b) => _vivante(b) && b.speciesCode == 'aviculture')
        .length;

    // Taux de ponte : Σ ponte_total / Σ effectif_final des fiches du mois × 100, `round(…, 0)`.
    final fichesVolailles = fichesDuMois('aviculture');
    final ponte = fichesVolailles.fold<int>(0, (t, f) => t + (f.ponteTotal ?? 0));
    final effectifPondeuses = fichesVolailles.fold<int>(
      0,
      (t, f) => t + f.effectifFinal,
    );
    final tauxPonte = effectifPondeuses > 0
        ? _arrondi(ponte / effectifPondeuses * 100, 0).toInt()
        : 0;

    // « Ventes (mois) » porcs : lignes de vente dont le produit est de la catégorie « Porciculture », vendues
    // depuis le 1er du mois (`SaleLine::count()`).
    // ⚠️ `sale_lines` NE DESCEND PAS au poste : seules les lignes des ventes saisies ICI sont comptées.
    final categoriePorcs = categories
        .where((c) => c.label == 'Porciculture')
        .map((c) => c.id)
        .toSet();
    final produitsPorcs = produits
        .where((p) => categoriePorcs.contains(p.categoryId))
        .map((p) => p.id)
        .toSet();
    final ventesDuMois = ventes
        .where((v) => !v.soldAt.isBefore(debutMois))
        .map((v) => v.id)
        .toSet();
    final ventesPorcs = lignes
        .where(
          (l) =>
              produitsPorcs.contains(l.productId) &&
              ventesDuMois.contains(l.saleId),
        )
        .length;

    return [
      CarteEspece(
        titre: 'Lapins',
        mesures: [
          ('Effectif', nombre(effectif('cuniculture').toDouble(), 0)),
          ('Gestantes', '${gestantes('cuniculture')}'),
          ('Marchands', '$marchands'),
        ],
        mortalite: mortalite('cuniculture'),
      ),
      CarteEspece(
        titre: 'Volailles',
        mesures: [
          ('Lots actifs', '$lotsActifsVolailles'),
          ('Taux ponte', '$tauxPonte%'),
          ('Effectif', nombre(effectif('aviculture').toDouble(), 0)),
        ],
        mortalite: mortalite('aviculture'),
      ),
      CarteEspece(
        titre: 'Porcs',
        mesures: [
          ('Effectif', nombre(effectif('porciculture').toDouble(), 0)),
          ('Gestantes', '${gestantes('porciculture')}'),
          ('Ventes (mois)', '$ventesPorcs'),
        ],
        mortalite: mortalite('porciculture'),
      ),
    ];
  }

  // ── Courbe et statistiques (`getChartVentesDepensesProperty`) ────────────────────────────────────────

  /// `translatedFormat('M')` de Carbon en français, passé par `ucfirst` dans le Blade.
  static const _moisCourts = [
    'Janv.',
    'Févr.',
    'Mars',
    'Avr.',
    'Mai',
    'Juin',
    'Juil.',
    'Août',
    'Sept.',
    'Oct.',
    'Nov.',
    'Déc.',
  ];

  List<PointMensuel> _serie(
    List<Sale> ventes,
    List<Purchase> achats,
    DateTime maintenant,
  ) {
    final points = <PointMensuel>[];
    for (var i = 5; i >= 0; i--) {
      final debut = DateTime(maintenant.year, maintenant.month - i);
      final fin = DateTime(
        debut.year,
        debut.month + 1,
      ).subtract(const Duration(microseconds: 1));
      bool dans(DateTime d) => !d.isBefore(debut) && !d.isAfter(fin);

      points.add(
        PointMensuel(
          libelle: _moisCourts[debut.month - 1],
          chiffreAffaires: ventes
              .where((v) => dans(v.soldAt))
              .fold<double>(0, (t, v) => t + v.total),
          depenses: achats
              .where((a) => dans(a.purchaseDate))
              .fold<double>(0, (t, a) => t + a.total),
        ),
      );
    }
    return points;
  }

  /// Suffixes des tuiles « Revenu » et « Dépenses » : `round(… × 100, 1)` puis écrit TEL QUEL par PHP (point
  /// décimal, « 25 » pour 25.0), précédé de « + » si positif ; vide si le mois précédent est nul.
  static (String, String) variationStatistique(List<PointMensuel> serie) {
    String suffixe(double courant, double precedent) {
      if (precedent <= 0) return '';
      final pct = _arrondi((courant - precedent) / precedent * 100, 1);
      final texte = pct == pct.truncateToDouble()
          ? '${pct.toInt()}'
          : '$pct';
      return ' (${pct >= 0 ? '+' : ''}$texte%)';
    }

    if (serie.length < 2) return ('', '');
    final c = serie[serie.length - 1];
    final p = serie[serie.length - 2];
    return (
      suffixe(c.chiffreAffaires, p.chiffreAffaires),
      suffixe(c.depenses, p.depenses),
    );
  }

  // ── Transactions récentes (`getTransactionsRecentesProperty`) ───────────────────────────────────────

  /// `strtoupper(substr($id, 0, 8))`.
  static String _id8(String id) =>
      (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();

  /// `orderByEffectiveDate()->limit(5)` — TOUTES les ventes, pas celles du mois.
  List<LigneTransaction> _ventes(
    List<Sale> ventes,
    Map<String, String> nomsClients,
  ) {
    final triees = [...ventes]..sort((a, b) => b.soldAt.compareTo(a.soldAt));
    return triees
        .take(5)
        .map(
          (v) => LigneTransaction(
            libelle:
                '${_id8(v.id)} · '
                '${v.customerName ?? nomsClients[v.customerId] ?? 'Client Anonyme'}',
            montant: v.total,
            ton: v.paymentMode == 'credit' ? TonMontant.jaune : TonMontant.emeraude,
          ),
        )
        .toList();
  }

  /// `latest('purchase_date')->limit(5)` ; montant `text-brand-forest` au comptant, jaune sinon.
  List<LigneTransaction> _achats(List<Purchase> achats) {
    final tries = [...achats]
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return tries
        .take(5)
        .map(
          (a) => LigneTransaction(
            libelle: '${_id8(a.id)} · ${a.supplierName ?? ''}',
            montant: a.total,
            ton: a.paymentMode == 'comptant' ? TonMontant.foret : TonMontant.jaune,
          ),
        )
        .toList();
  }

  /// `Expense::where('is_active', true)->latest('expense_date')->limit(5)`.
  /// ⚠️ `expenses` ne descend pas au poste et n'y a pas de colonne d'archivage : ce sont les charges saisies
  /// ici, en attente ou acquittées.
  List<LigneTransaction> _depenses(List<Expense> depenses) {
    final triees = [...depenses]
      ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    return triees
        .take(5)
        .map(
          (d) => LigneTransaction(
            libelle: d.label,
            montant: d.amount,
            ton: TonMontant.rouge,
          ),
        )
        .toList();
  }

  // ── Activités du jour (`getActivitesJourProperty`) ──────────────────────────────────────────────────

  /// `AuditLog::whereDate('created_at', today)->latest()->limit(8)`, libellés de `AuditLog` (générés au
  /// poste dans `LibellesAudit`). ⚠️ Le tirage ne sert le journal qu'aux comptes `manage-users` : pour les
  /// autres, la table est vide et l'écran affiche le message vide du web.
  List<LigneActivite> _activites(List<AuditLog> journal, DateTime maintenant) {
    final duJour =
        journal
            .where(
              (j) =>
                  j.createdAt != null &&
                  _jour(j.createdAt!) == _jour(maintenant),
            )
            .toList()
          ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));

    return duJour.take(8).map((j) {
      final module = LibellesAudit.module(j.module);
      return LigneActivite(
        libelle: LibellesAudit.action(j.action),
        detail:
            '${_heure(j.createdAt!)} — ${j.userName ?? 'Système'}'
            '${module == null || module.isEmpty ? '' : ' · $module'}',
      );
    }).toList();
  }

  static String _heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ── Top 5 (`getTopProduitsProperty`) ─────────────────────────────────────────────────────────────────

  /// Lignes des ventes du mois, groupées par produit, triées par CA décroissant, cinq au plus.
  ///
  /// ⚠️ ÉCART (donnée absente) : `sale_lines` ne descend pas, seules les ventes saisies sur ce poste ont leurs
  /// lignes. Et la MARGE suppose le PMP (`Product::computePmp()`, sur TOUTES les lignes d'achat de la ferme) :
  /// `purchase_lines` ne descend pas non plus, un PMP calculé ici serait faux sans le dire → « — ».
  List<LigneTopProduit> _topProduits(
    DateTime debutMois,
    List<Sale> ventes,
    List<SaleLine> lignes,
    List<Product> produits,
  ) {
    final idsRetenus = ventes
        .where((v) => !v.soldAt.isBefore(debutMois))
        .map((v) => v.id)
        .toSet();
    final parProduit = <String, (double, double)>{};

    for (final l in lignes.where((l) => idsRetenus.contains(l.saleId))) {
      final courant = parProduit[l.productId] ?? (0.0, 0.0);
      parProduit[l.productId] = (
        courant.$1 + l.qty,
        courant.$2 + l.manualTotalAmount,
      );
    }

    final nommes = {for (final p in produits) p.id: p.name};

    final top =
        parProduit.entries
            .map(
              (e) => LigneTopProduit(
                produit: nommes[e.key] ?? '—',
                quantite: e.value.$1,
                chiffreAffaires: e.value.$2,
                margePct: null,
              ),
            )
            .toList()
          ..sort((a, b) => b.chiffreAffaires.compareTo(a.chiffreAffaires));

    return top.take(5).toList();
  }

  // ── Formats du web ──────────────────────────────────────────────────────────────────────────────────

  /// « Mois précédent : X F (±y,z%) » — sous-texte des cartes CA et Dépenses (`$pctChange` du Blade : pas de
  /// pourcentage quand le mois précédent vaut 0).
  static String? legendeMoisPrecedent(double? courant, double? precedent) {
    if (precedent == null) return null;
    var texte = 'Mois précédent : ${nombre(precedent, 0)} F';
    if (courant != null && precedent != 0) {
      final pct = (courant - precedent) / precedent.abs() * 100;
      texte += ' (${pct >= 0 ? '+' : ''}${nombre(pct, 1)}%)';
    }
    return texte;
  }

  /// « Marge nette : X% » — seulement si le CA est strictement positif.
  static String? legendeMargeNette(double? resultat, double? ca) {
    if (resultat == null || ca == null || ca <= 0) return null;
    return 'Marge nette : ${nombre(resultat / ca * 100, 0)}%';
  }

  /// `number_format($valeur, $decimales, ',', ' ')` : arrondi PHP (demi loin de zéro), espace des milliers,
  /// virgule décimale, jamais « -0 ».
  static String nombre(double valeur, int decimales) {
    final arrondi = _arrondi(valeur, decimales);
    final absolu = arrondi.abs().toStringAsFixed(decimales);
    final morceaux = absolu.split('.');
    final entier = morceaux[0];
    final groupes = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      groupes.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    final negatif = arrondi < 0 && RegExp('[1-9]').hasMatch(absolu);
    return '${negatif ? '-' : ''}${groupes.join(' ')}'
        '${decimales > 0 ? ',${morceaux[1]}' : ''}';
  }

  /// Quantité du Top 5 : `rtrim(rtrim(number_format($qty, 2, '.', ''), '0'), '.')` — « 3.5 », « 30 ».
  static String quantiteTop(double quantite) {
    final arrondi = _arrondi(quantite, 2);
    var texte = arrondi.abs().toStringAsFixed(2);
    texte = texte.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '${arrondi < 0 && texte != '0' ? '-' : ''}$texte';
  }

  /// `round($valeur, $decimales)` de PHP : demi loin de zéro, après un pré-arrondi à 15 chiffres significatifs
  /// (1,005 → 1,01, là où l'arrondi binaire brut donnerait 1,00).
  static double _arrondi(double valeur, int decimales) {
    final facteur = math.pow(10, decimales).toDouble();
    final echelle = double.parse((valeur * facteur).toStringAsPrecision(15));
    return echelle.round() / facteur;
  }

  /// Écran du poste qu'ouvre une adresse du web (`link` d'une alerte, `value` d'une option d'état), `null`
  /// s'il n'existe pas au poste. Même règle que `LigneNotification.ecranDuLien` : le chemin web porte le nom de
  /// la page du prototype sans `.html` ; la requête (`?tab=…`) est ignorée.
  static EcranPoste? ecranDuLien(String lien) {
    final chemin = Uri.tryParse(lien)?.path.replaceAll('/', '');
    if (chemin == null || chemin.isEmpty) return null;
    for (final e in EcranPoste.values) {
      if (e.page == '$chemin.html') return e;
    }
    return null;
  }
}
