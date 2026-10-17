import '../../core/database/app_database.dart';
import '../elevage/production_oeufs_service.dart';

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

/// Une alerte de la colonne « Alertes Critiques ».
class AlerteCritique {
  const AlerteCritique({required this.message, required this.grave});

  final String message;

  /// Rouge (fond `error-bg`) plutôt que jaune, comme dans la maquette.
  final bool grave;
}

/// Une carte de la bande « Élevage en temps réel ».
///
/// Les quatre mesures diffèrent d'une espèce à l'autre dans la maquette : la
/// liste est donc portée telle quelle, dans SON ordre.
class CarteEspece {
  const CarteEspece({
    required this.titre,
    required this.mesures,
    required this.mortalite,
  });

  final String titre;

  /// Trois premières mesures, `(libellé, valeur affichable)`.
  final List<(String, String)> mesures;

  /// Quatrième mesure de la maquette, toujours « Mortalité ». Séparée parce
  /// que sa couleur dépend du seuil.
  final double? mortalite;
}

/// Un mois de la courbe « CA vs Dépenses ».
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

/// Une ligne des « Transactions Récentes » ou des « Activités du Jour ».
class LigneTransaction {
  const LigneTransaction({
    required this.libelle,
    required this.montant,
    this.horodatage,
  });

  final String libelle;
  final double? montant;
  final String? horodatage;
}

/// Une ligne du « Top 5 Produits du Mois ».
class LigneTopProduit {
  const LigneTopProduit({
    required this.produit,
    required this.quantite,
    required this.chiffreAffaires,
  });

  final String produit;
  final double quantite;
  final double chiffreAffaires;
}

/// Tout ce que la maquette `dashboard.html` demande, dans son ordre.
class DonneesTableauDeBord {
  const DonneesTableauDeBord({
    required this.chiffreAffaires,
    required this.nombreDeVentes,
    required this.tresorerie,
    required this.tresorerieParType,
    required this.depenses,
    required this.resultatNet,
    required this.creances,
    required this.dettes,
    required this.produitsSousSeuil,
    required this.effectifAnimaux,
    required this.effectifPrecedentConnu,
    required this.alertes,
    required this.especes,
    required this.serie,
    required this.serieAnnuelle,
    required this.ventesRecentes,
    required this.depensesRecentes,
    required this.activitesDuJour,
    required this.topProduits,
  });

  final Mesure chiffreAffaires;
  final int nombreDeVentes;
  final Mesure tresorerie;
  final Map<String, double> tresorerieParType;
  final Mesure depenses;
  final Mesure resultatNet;
  final Mesure creances;
  final Mesure dettes;
  final List<Product> produitsSousSeuil;
  final Mesure effectifAnimaux;
  final bool effectifPrecedentConnu;
  final List<AlerteCritique> alertes;
  final List<CarteEspece> especes;
  final List<PointMensuel> serie;

  /// Douze mois, pour l'histogramme de « Statistiques de Ventes ».
  final List<PointMensuel> serieAnnuelle;
  final List<LigneTransaction> ventesRecentes;
  final List<LigneTransaction> depensesRecentes;
  final List<LigneTransaction> activitesDuJour;
  final List<LigneTopProduit> topProduits;
}

/// Lectures du Tableau de Bord — `prototype_html/dashboard.html`.
///
/// ⚠️⚠️ **LE TIRAGE NE DESCEND NI LES VENTES NI LES DÉPENSES.** Vérifié dans
/// `SyncController::pull()` : la charge utile porte les produits, les bandes,
/// les fiches, les référentiels, les comptes de trésorerie et les catégories
/// de charge — **jamais `sales`, jamais `expenses`**. Ces deux tables ne
/// contiennent donc, au poste, que ce que CE poste a saisi.
///
/// Conséquence directe : « Chiffre d'Affaires » et « Dépenses » ne sont pas
/// ceux de la ferme, et l'écran doit le dire. Les afficher sans mention
/// tromperait un gérant qui compare deux postes.
///
/// ⚠️ **SEUIL DE MORTALITÉ : 5 %**, et il n'est pas inventé — c'est celui du
/// prototype lui-même, `gestion-elevage.html` : « Attention : Seuil critique
/// dépassé ! » à partir de `>= 5`, « Seuil normal < 5% » en dessous. La même
/// formule y est écrite noir sur blanc : *(Cumul des Morts du Mois / Effectif
/// Initial Cumulé) × 100*.
class TableauDeBordRepository {
  TableauDeBordRepository({required this.database});

  final AppDatabase database;

  /// Seuil critique de mortalité, en pourcentage — `gestion-elevage.html`.
  static const double seuilMortalite = 5;

  /// Les cinq stades qui alimentent le « porc marchand » / « lapin marchand ».
  ///
  /// ⚠️ Même correspondance que `_correspondAuStade()` sur la fiche Porcs :
  /// la ferme ne stocke pas de catégorie commerciale, elle stocke un STADE.
  static bool _estMarchand(String? stade) {
    final s = (stade ?? '').toLowerCase();
    return s.contains('engraissement') || s.contains('croissance');
  }

  Future<DonneesTableauDeBord> charger({
    required DateTime du,
    required DateTime au,
  }) async {
    final finDeJournee = DateTime(au.year, au.month, au.day, 23, 59, 59);
    final debut = DateTime(du.year, du.month, du.day);

    final ventes = await database.select(database.sales).get();
    final lignes = await database.select(database.saleLines).get();
    final produits = await database.select(database.products).get();
    final depenses = await database.select(database.expenses).get();
    final comptes = await database.select(database.treasuryAccounts).get();
    final creances = await database.select(database.receivables).get();
    final bandes = await (database.select(
      database.livestockLots,
    )..where((t) => t.isActive.equals(true))).get();
    final fiches = await database.select(database.livestockDailyEntries).get();

    final ventesRetenues =
        ventes
            .where((v) => v.status != 'annulee')
            .where(
              (v) =>
                  !v.soldAt.isBefore(debut) && !v.soldAt.isAfter(finDeJournee),
            )
            .toList()
          ..sort((a, b) => b.soldAt.compareTo(a.soldAt));

    final depensesRetenues =
        depenses
            .where(
              (d) =>
                  !d.expenseDate.isBefore(debut) &&
                  !d.expenseDate.isAfter(finDeJournee),
            )
            .toList()
          ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));

    final ca = ventesRetenues.fold<double>(0, (t, v) => t + v.total);
    final totalDepenses = depensesRetenues.fold<double>(
      0,
      (t, d) => t + d.amount,
    );

    final parType = <String, double>{};
    for (final c in comptes) {
      parType[(c.type ?? 'autre')] =
          (parType[c.type ?? 'autre'] ?? 0) + c.balance;
    }

    final sousSeuil = produits
        .where(
          (p) =>
              p.isActive &&
              p.alertThreshold != null &&
              p.stockQty <= p.alertThreshold!,
        )
        .toList();

    final effectif = bandes.fold<int>(0, (t, b) => t + b.currentQuantity);

    return DonneesTableauDeBord(
      chiffreAffaires: Mesure.chiffre(ca),
      nombreDeVentes: ventesRetenues.length,
      tresorerie: Mesure.chiffre(
        comptes.fold<double>(0, (t, c) => t + c.balance),
      ),
      tresorerieParType: parType,
      depenses: Mesure.chiffre(totalDepenses),
      // ⚠️ PAS « CA − DÉPENSES ». Le résultat net d'un exercice se lit au
      // grand livre : produits et charges y comprennent l'amortissement, les
      // variations de stock et les écritures d'inventaire, dont le poste n'a
      // rien. Le soustraire ici donnerait un chiffre plausible et faux, sur
      // deux agrégats qui ne couvrent déjà que CE poste.
      resultatNet: const Mesure.absente('Sans comptabilité au poste'),
      // 🔴→✅ TICKET F0.43 — L'ENCOURS EST ENFIN CALCULABLE. `receivables`
      // descend au poste depuis le ticket 14.75 ; cette carte portait un
      // tiret parce que la table n'arrivait pas, pas parce que la donnée
      // n'existait pas.
      //
      // ⚠️ **LE RESTE DÛ, PAS LE MONTANT FACTURÉ** : `amount - amount_paid`.
      // Sommer `amount` compterait deux fois ce qui a déjà été réglé.
      creances: Mesure.chiffre(
        creances.fold<double>(0, (t, c) => t + (c.amount - c.amountPaid)),
      ),
      dettes: const Mesure.absente('Table non synchronisée'),
      produitsSousSeuil: sousSeuil,
      effectifAnimaux: Mesure.chiffre(effectif.toDouble()),
      effectifPrecedentConnu: false,
      alertes: _alertes(sousSeuil, bandes, fiches),
      especes: _cartesEspeces(bandes, fiches, au),
      serie: _serie(ventes, depenses, au, mois: 6),
      serieAnnuelle: _serie(ventes, depenses, au, mois: 12),
      ventesRecentes: _ventesRecentes(ventesRetenues),
      depensesRecentes: _depensesRecentes(depensesRetenues),
      activitesDuJour: _activites(ventes, depenses, fiches, au),
      topProduits: _topProduits(ventesRetenues, lignes, produits),
    );
  }

  // ── Alertes ───────────────────────────────────────────────────────────────

  /// ⚠️ **DEUX FAMILLES SUR QUATRE.** La maquette en montre quatre : stock sous
  /// seuil, mortalité anormale, **créance en retard**, **péremption proche**.
  /// Les deux dernières demandent des tables que le poste ne reçoit pas
  /// (`receivables`) ou qui n'existent nulle part (date de péremption d'un
  /// produit vétérinaire). Elles sont absentes, pas simulées.
  List<AlerteCritique> _alertes(
    List<Product> sousSeuil,
    List<LivestockLot> bandes,
    List<LivestockDailyEntry> fiches,
  ) {
    final alertes = <AlerteCritique>[];

    for (final p in sousSeuil) {
      alertes.add(
        AlerteCritique(
          message: '${p.name} sous le seuil critique',
          grave: true,
        ),
      );
    }

    // Mortalité anormale sur les sept derniers jours, bande par bande.
    final reference = fiches.isEmpty
        ? DateTime.now()
        : fiches.map((f) => f.entryDate).reduce((a, b) => a.isAfter(b) ? a : b);
    final depuis = reference.subtract(const Duration(days: 7));

    for (final bande in bandes) {
      final duLot = fiches.where(
        (f) => f.lotId == bande.id && !f.entryDate.isBefore(depuis),
      );
      if (duLot.isEmpty) continue;

      final morts = duLot.fold<int>(0, (t, f) => t + f.mort);
      final base = bande.initialQuantity;
      if (base <= 0 || morts <= 0) continue;

      final taux = (morts / base) * 100;
      if (taux >= seuilMortalite) {
        alertes.add(
          AlerteCritique(
            message:
                'Mortalité anormale — Lot ${bande.code} '
                '(${taux.toStringAsFixed(1)} %)',
            grave: true,
          ),
        );
      }
    }

    return alertes;
  }

  // ── Cartes espèces ────────────────────────────────────────────────────────

  List<CarteEspece> _cartesEspeces(
    List<LivestockLot> bandes,
    List<LivestockDailyEntry> fiches,
    DateTime mois,
  ) {
    List<LivestockLot> de(String code) =>
        bandes.where((b) => b.speciesCode == code).toList();

    double? mortaliteDuMois(List<LivestockLot> lots) {
      final ids = lots.map((l) => l.id).toSet();
      final base = lots.fold<int>(0, (t, l) => t + l.initialQuantity);
      if (base <= 0) return null;

      final morts = fiches
          .where(
            (f) =>
                ids.contains(f.lotId) &&
                f.entryDate.year == mois.year &&
                f.entryDate.month == mois.month,
          )
          .fold<int>(0, (t, f) => t + f.mort);

      // ⚠️ Formule reprise de `gestion-elevage.html` :
      //    (Cumul des Morts du Mois / Effectif Initial Cumulé) × 100.
      return (morts / base) * 100;
    }

    int effectifDe(List<LivestockLot> lots) =>
        lots.fold<int>(0, (t, l) => t + l.currentQuantity);

    final lapins = de('cuniculture');
    final volailles = de('aviculture');
    final porcs = de('porciculture');

    // Taux de ponte du mois, sur les seules bandes en ponte.
    final pondeuses = volailles
        .where((b) => (b.stage ?? '') == 'ponte')
        .toList();
    final idsPonte = pondeuses.map((l) => l.id).toSet();
    final fichesPonte = fiches
        .where(
          (f) =>
              idsPonte.contains(f.lotId) &&
              f.entryDate.year == mois.year &&
              f.entryDate.month == mois.month &&
              (f.ponteTotal ?? 0) > 0,
        )
        .toList();

    double? tauxPonte;
    if (fichesPonte.isNotEmpty) {
      final taux = fichesPonte
          .map(
            (f) => ProductionOeufsService.tauxDePonte(
              recoltes: f.ponteTotal ?? 0,
              effectif: f.effectifFinal,
            ),
          )
          .whereType<double>()
          .toList();
      if (taux.isNotEmpty) {
        tauxPonte = taux.reduce((a, b) => a + b) / taux.length;
      }
    }

    final idsPorcs = porcs.map((l) => l.id).toSet();
    final ventesPorcs = fiches
        .where(
          (f) =>
              idsPorcs.contains(f.lotId) &&
              f.entryDate.year == mois.year &&
              f.entryDate.month == mois.month,
        )
        .fold<int>(0, (t, f) => t + f.vente);

    return [
      CarteEspece(
        titre: 'Lapins',
        mesures: [
          ('Effectif', '${effectifDe(lapins)}'),
          // ⚠️ « GESTANTES » N'EST NULLE PART. La fiche Lapins collecte bien
          // une ventilation par catégorie à la saisie, mais
          // `livestock_daily_entries` ne porte qu'un effectif total et le
          // tirage ne descend aucun décompte de gestantes. Un tiret plutôt
          // qu'un chiffre reconstitué.
          ('Gestantes', '—'),
          ('Marchands', '${effectifDe(lapins.where(_marchand).toList())}'),
        ],
        mortalite: mortaliteDuMois(lapins),
      ),
      CarteEspece(
        titre: 'Volailles',
        mesures: [
          ('Lots actifs', '${volailles.length}'),
          (
            'Taux ponte',
            tauxPonte == null ? '—' : '${tauxPonte.toStringAsFixed(0)}%',
          ),
          ('Effectif', '${effectifDe(volailles)}'),
        ],
        mortalite: mortaliteDuMois(volailles),
      ),
      CarteEspece(
        titre: 'Porcs',
        mesures: [
          ('Effectif', '${effectifDe(porcs)}'),
          // ⚠️ Même absence que chez les lapins.
          ('Gestantes', '—'),
          ('Ventes (mois)', '$ventesPorcs'),
        ],
        mortalite: mortaliteDuMois(porcs),
      ),
    ];
  }

  static bool _marchand(LivestockLot l) => _estMarchand(l.stage);

  // ── Courbe six mois ───────────────────────────────────────────────────────

  static const _moisCourts = [
    'Jan',
    'Fév',
    'Mar',
    'Avr',
    'Mai',
    'Jun',
    'Jul',
    'Aoû',
    'Sep',
    'Oct',
    'Nov',
    'Déc',
  ];

  List<PointMensuel> _serie(
    List<Sale> ventes,
    List<Expense> depenses,
    DateTime fin, {
    required int mois,
  }) {
    final points = <PointMensuel>[];

    for (var i = mois - 1; i >= 0; i--) {
      final leMois = DateTime(fin.year, fin.month - i, 1);

      final ca = ventes
          .where(
            (v) =>
                v.status != 'annulee' &&
                v.soldAt.year == leMois.year &&
                v.soldAt.month == leMois.month,
          )
          .fold<double>(0, (t, v) => t + v.total);

      final sorties = depenses
          .where(
            (d) =>
                d.expenseDate.year == leMois.year &&
                d.expenseDate.month == leMois.month,
          )
          .fold<double>(0, (t, d) => t + d.amount);

      points.add(
        PointMensuel(
          libelle: _moisCourts[leMois.month - 1],
          chiffreAffaires: ca,
          depenses: sorties,
        ),
      );
    }

    return points;
  }

  // ── Transactions & activités ──────────────────────────────────────────────

  static String _heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// ⚠️⚠️ **NI NUMÉRO DE VENTE NI NOM DE CLIENT.** La maquette affiche
  /// « V-2026-0884 · AMOUSSOU Régis ». **Aucune colonne de référence n'existe
  /// nulle part** — ni dans `sales` côté serveur, ni au poste, ni dans le POS
  /// Livewire (vérifié au ticket 14.71) ; et la table des clients ne descend
  /// pas au poste. La vente est donc identifiée par son heure et son mode de
  /// règlement, qui sont réels.
  List<LigneTransaction> _ventesRecentes(List<Sale> ventes) => ventes
      .take(5)
      .map(
        (v) => LigneTransaction(
          libelle: '${_heure(v.soldAt)} · ${v.paymentMode}',
          montant: v.total,
        ),
      )
      .toList();

  List<LigneTransaction> _depensesRecentes(List<Expense> depenses) => depenses
      .take(5)
      .map((d) => LigneTransaction(libelle: d.label, montant: d.amount))
      .toList();

  /// « Activités du Jour » reconstituées depuis les écritures du poste.
  ///
  /// ⚠️ **SANS AUTEUR.** La maquette nomme l'opérateur (« 09:12 — KPOSSOU
  /// Éléonore ») ; le poste n'enregistre qu'un `device_id`, jamais l'agent.
  /// Le journal d'audit qui porte ces noms côté serveur ne descend pas.
  List<LigneTransaction> _activites(
    List<Sale> ventes,
    List<Expense> depenses,
    List<LivestockDailyEntry> fiches,
    DateTime jour,
  ) {
    bool memeJour(DateTime d) =>
        d.year == jour.year && d.month == jour.month && d.day == jour.day;

    final activites = <(DateTime, LigneTransaction)>[];

    for (final v in ventes.where((v) => memeJour(v.soldAt))) {
      activites.add((
        v.soldAt,
        LigneTransaction(
          libelle: 'Vente encaissée (${v.paymentMode})',
          montant: v.total,
          horodatage: _heure(v.soldAt),
        ),
      ));
    }

    for (final d in depenses.where((d) => memeJour(d.expenseDate))) {
      activites.add((
        d.updatedAt,
        LigneTransaction(
          libelle: 'Dépense saisie — ${d.label}',
          montant: d.amount,
          horodatage: _heure(d.updatedAt),
        ),
      ));
    }

    for (final f in fiches.where((f) => memeJour(f.entryDate))) {
      activites.add((
        f.updatedAt,
        LigneTransaction(
          libelle:
              'Fiche d\'élevage mise à jour '
              '(${f.ne} naissances, ${f.mort} morts)',
          montant: null,
          horodatage: _heure(f.updatedAt),
        ),
      ));
    }

    activites.sort((a, b) => b.$1.compareTo(a.$1));
    return activites.take(8).map((a) => a.$2).toList();
  }

  /// « Top 5 Produits du Mois ».
  ///
  /// ⚠️ **LA COLONNE « MARGE » RESTE VIDE.** Elle suppose un prix de revient ;
  /// `products` ne porte au poste que des prix de VENTE (`price_min`,
  /// `price_max`). Un pourcentage calculé sur un prix de vente ne serait pas
  /// une marge.
  List<LigneTopProduit> _topProduits(
    List<Sale> ventes,
    List<SaleLine> lignes,
    List<Product> produits,
  ) {
    final idsRetenus = ventes.map((v) => v.id).toSet();
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
                produit: nommes[e.key] ?? 'Produit inconnu',
                quantite: e.value.$1,
                chiffreAffaires: e.value.$2,
              ),
            )
            .toList()
          ..sort((a, b) => b.chiffreAffaires.compareTo(a.chiffreAffaires));

    return top.take(5).toList();
  }
}
