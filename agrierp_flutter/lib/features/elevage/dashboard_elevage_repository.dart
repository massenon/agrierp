import '../../core/database/app_database.dart';
import 'production_oeufs_service.dart';
import 'soins_repository.dart';

/// Statut d'une bande face à son objectif de croissance.
enum StatutGmq { sousObjectif, dansLaCible, auDessusObjectif, sansObjectif }

/// Une ligne du tableau « GMQ & Croissance ».
class LigneGmq {
  const LigneGmq({
    required this.code,
    required this.codeEspece,
    required this.libelleEspece,
    required this.datePesee,
    required this.poidsPrecedent,
    required this.poidsActuel,
    required this.jours,
    required this.gmq,
    required this.statut,
  });

  final String code;
  final String codeEspece;
  final String libelleEspece;
  final DateTime datePesee;
  final double poidsPrecedent;
  final double poidsActuel;
  final int jours;
  final double gmq;
  final StatutGmq statut;
}

/// Un rappel du bloc « Rappels VMS à venir ».
class RappelVms {
  const RappelVms({
    required this.libelle,
    required this.echeance,
    required this.jours,
    required this.enRetard,
  });

  final String libelle;

  /// « Dans 2 jours », « Depuis 3 jours »…
  final String echeance;
  final int jours;
  final bool enRetard;
}

/// Une ligne du tableau « Analyse Sanitaire ».
class LigneSanitaire {
  const LigneSanitaire({
    required this.libelleEspece,
    required this.nombreDeTraitements,
    required this.coutTotal,
    required this.morbidite,
  });

  final String libelleEspece;
  final int nombreDeTraitements;
  final double coutTotal;

  /// ⚠️ TOUJOURS `null` AU POSTE : le taux de morbidité se lit sur
  /// `infirmary_records`, table qui n'existe pas dans la base locale et que le
  /// tirage ne descend pas.
  final double? morbidite;
}

/// Une bande de l'onglet « Prévision de Croissance ».
///
/// ⚠️⚠️ **LA RÈGLE EST CELLE DE LARAVEL** (`DashboardElevage::getPrevisionsProperty`) :
/// régression linéaire (moindres carrés) sur TOUTES les pesées de la bande, avec
/// au moins TROIS pesées. Le poste projetait jusqu'ici à partir des deux dernières
/// seulement — une pesée aberrante faisait alors tout le résultat. La maquette
/// parle d'un « GMQ moyen sur 7 jours » : ce n'est ni la règle de Laravel ni un
/// calcul que le serveur sait reproduire (ARBITRAGE CLIENT, voir le ticket F0.68).
class Prevision {
  const Prevision({
    required this.bandeId,
    required this.code,
    required this.libelleEspece,
    required this.poidsActuel,
    required this.gmqObserve,
    required this.ordonnee,
    required this.dernierJour,
    required this.nbPesees,
  });

  final String bandeId;
  final String code;
  final String libelleEspece;
  final double poidsActuel;

  /// Pente de la droite de régression, en g/jour.
  final double gmqObserve;

  /// Ordonnée à l'origine de la droite, au jour de la première pesée.
  final double ordonnee;

  /// Jours écoulés entre la première et la dernière pesée.
  final int dernierJour;
  final int nbPesees;

  /// Poids projeté `jours` après la dernière pesée — arrondi à l'entier, comme
  /// Laravel (`round($intercept + $slope * ($lastX + 30))`).
  double projeter(int jours) =>
      (ordonnee + gmqObserve * (dernierJour + jours)).roundToDouble();
}

/// Une carte espèce de l'onglet « Synthèse Globale ».
class CarteEspeceElevage {
  const CarteEspeceElevage({required this.titre, required this.lignes});

  final String titre;

  /// Quatre lignes `(libellé, valeur, critique)`, dans l'ordre de la maquette.
  final List<(String, String, bool)> lignes;
}

class DonneesDashboardElevage {
  const DonneesDashboardElevage({
    required this.effectifTotal,
    required this.gmqMoyen,
    required this.mortaliteMois,
    required this.especes,
    required this.gmqParEspeceParSemaine,
    required this.rappels,
    required this.lignesGmq,
    required this.gmqParEspece,
    required this.lotsSuivis,
    required this.bandeSuivie,
    required this.evolutionGmq,
    required this.sanitaire,
    required this.traitementsDuMois,
    required this.coutSanitaireDuMois,
    required this.traitementLePlusFrequent,
    required this.previsions,
  });

  final int effectifTotal;
  final double? gmqMoyen;
  final double? mortaliteMois;
  final List<CarteEspeceElevage> especes;

  /// Cinq points hebdomadaires (S1..S5) par code d'espèce ; `null` = pas assez
  /// de pesées à cette date pour calculer un GMQ.
  final Map<String, List<double?>> gmqParEspeceParSemaine;

  final List<RappelVms> rappels;
  final List<LigneGmq> lignesGmq;
  final Map<String, double?> gmqParEspece;
  final int lotsSuivis;

  /// Bande retenue pour la courbe « Évolution du GMQ ».
  final String? bandeSuivie;
  final List<double?> evolutionGmq;

  final List<LigneSanitaire> sanitaire;
  final int traitementsDuMois;
  final double coutSanitaireDuMois;
  final String? traitementLePlusFrequent;
  final List<Prevision> previsions;
}

/// Lectures du Dashboard Élevage — `prototype_html/elevage-dashboard.html`.
///
/// ⚠️⚠️ **LA FORMULE DU GMQ EST CELLE DU PROTOTYPE : LES DEUX DERNIÈRES
/// PESÉES.** Elle y est écrite deux fois — en toutes lettres sur l'onglet
/// (« Gain Moyen Quotidien = (Poids actuel − Poids précédent) ÷ Jours
/// écoulés »), et dans son propre JS, qui prend `entries[n-1]` et
/// `entries[n-2]`. Les en-têtes du tableau disent la même chose : « Poids
/// Précédent », « Jours Écoulés ».
///
/// ⚠️ **DIVERGENCE RÉELLE AVEC LARAVEL — ARBITRAGE CLIENT.**
/// `GrowthAnalysisService::gmqCumule()` calcule un GMQ **cumulé depuis la
/// PREMIÈRE pesée**, et le tableau Blade renomme la colonne en « Poids Initial
/// (g) ». Le composant Laravel documente lui-même cet « écart assumé ». Les
/// deux surfaces affichent donc, pour une même bande, deux GMQ différents.
/// Le poste suit la maquette, source de vérité #1 ; le doc invoqué à l'appui
/// de l'autre formule (`FORMULE_FICHE_ELEVAGE.md`) **n'existe pas dans le
/// dépôt** — seul `draft/README_SPRINT0.md` le cite. À trancher par le client.
///
/// ⚠️ **L'AUTONOMIE ALIMENTAIRE N'EST CALCULABLE NULLE PART**, et Laravel
/// l'avait déjà constaté (carte marquée `pending`). La ration est bien connue
/// (`feed_ration_standards`, en g/jour) et le stock aussi (`products.stock_qty`
/// pour la catégorie « Aliments »), mais le stock est compté **en sacs** et le
/// poids du sac ne vit que dans le NOM du produit (« Aliment ponte 25kg »),
/// jamais dans une colonne. Lire « 25 » dans un libellé serait inventer une
/// donnée de gestion. **ARBITRAGE CLIENT** : ajouter une colonne de
/// conditionnement (kg par unité) sur `products`.
class DashboardElevageRepository {
  DashboardElevageRepository({required this.database, required this.soins});

  final AppDatabase database;
  final SoinsRepository soins;

  /// Objectifs de GMQ, en g/jour — repris **du JS du prototype**, pas des
  /// libellés des cartes.
  ///
  /// ⚠️ Les cartes KPI de la maquette annoncent des fourchettes plus fines
  /// (« Volailles Chair : 45-55 », « poussins : 20-30 ») que la table qui
  /// pilote réellement le statut (`aviculture: 20–55`). Divergence interne au
  /// prototype ; c'est la table exécutée qui fait foi ici.
  static const objectifs = <String, (double, double)>{
    'cuniculture': (15, 20),
    'aviculture': (20, 55),
    'porciculture': (400, 650),
  };

  static const libellesEspeces = <String, String>{
    'cuniculture': 'Cuniculture',
    'aviculture': 'Aviculture',
    'porciculture': 'Porciculture',
    'helico': 'Héliciculture',
  };

  /// Horizon des rappels VMS, en jours.
  static const horizonRappels = 7;

  Future<DonneesDashboardElevage> charger({DateTime? quand}) async {
    final maintenant = quand ?? DateTime.now();
    final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);

    final bandes = await (database.select(
      database.livestockLots,
    )..where((t) => t.isActive.equals(true))).get();
    final fiches = await database.select(database.livestockDailyEntries).get();
    final soinsRegistre = await database
        .select(database.veterinaryRecords)
        .get();
    final remanences = await database
        .select(database.veterinaryWithdrawalPeriods)
        .get();

    final lignes = _lignesGmq(bandes, fiches);
    final gmqs = lignes.map((l) => l.gmq).toList();

    return DonneesDashboardElevage(
      effectifTotal: bandes.fold<int>(0, (t, b) => t + b.currentQuantity),
      gmqMoyen: gmqs.isEmpty
          ? null
          : gmqs.reduce((a, b) => a + b) / gmqs.length,
      mortaliteMois: _mortalite(bandes.map((b) => b.id).toSet(), fiches, jour),
      especes: _cartes(bandes, fiches, jour),
      gmqParEspeceParSemaine: {
        for (final code in ['cuniculture', 'aviculture', 'porciculture'])
          code: _serieHebdomadaire(
            bandes.where((b) => b.speciesCode == code).toList(),
            fiches,
            jour,
            semaines: 5,
          ),
      },
      rappels: await _rappels(bandes, remanences, jour),
      lignesGmq: lignes,
      gmqParEspece: {
        for (final code in objectifs.keys)
          code: () {
            final v = lignes
                .where((l) => l.codeEspece == code)
                .map((l) => l.gmq)
                .toList();
            return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
          }(),
      },
      lotsSuivis: lignes.length,
      bandeSuivie: lignes.isEmpty ? null : lignes.first.code,
      evolutionGmq: lignes.isEmpty
          ? const []
          : _serieHebdomadaire(
              bandes.where((b) => b.code == lignes.first.code).toList(),
              fiches,
              jour,
              semaines: 8,
            ),
      sanitaire: _sanitaire(bandes, soinsRegistre, jour),
      traitementsDuMois: _duMois(soinsRegistre, jour).length,
      coutSanitaireDuMois: _duMois(
        soinsRegistre,
        jour,
      ).fold<double>(0, (t, s) => t + (s.cost ?? 0)),
      traitementLePlusFrequent: _plusFrequent(_duMois(soinsRegistre, jour)),
      previsions: _previsions(bandes, fiches, jour),
    );
  }

  // ── GMQ ───────────────────────────────────────────────────────────────────

  /// Pesées d'une bande, du plus ancien au plus récent.
  ///
  /// ⚠️ Une pesée à zéro n'est pas une pesée : c'est l'absence de saisie. La
  /// retenir écraserait le poids précédent et produirait un GMQ massivement
  /// négatif le lendemain d'une journée non pesée.
  List<LivestockDailyEntry> _pesees(
    String lotId,
    List<LivestockDailyEntry> fiches, {
    DateTime? jusquA,
  }) {
    final retenues =
        fiches
            .where(
              (f) =>
                  f.lotId == lotId &&
                  (f.weightSampleAvgG ?? 0) > 0 &&
                  (jusquA == null || !f.entryDate.isAfter(jusquA)),
            )
            .toList()
          ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
    return retenues;
  }

  /// GMQ d'une bande — **les deux dernières pesées**, formule du prototype.
  double? _gmq(
    String lotId,
    List<LivestockDailyEntry> fiches, {
    DateTime? jusquA,
  }) {
    final pesees = _pesees(lotId, fiches, jusquA: jusquA);
    if (pesees.length < 2) return null;

    final dernier = pesees[pesees.length - 1];
    final precedent = pesees[pesees.length - 2];

    // ⚠️ `max(1, …)` comme le JS du prototype : deux pesées le même jour ne
    // doivent pas produire une division par zéro.
    final jours = dernier.entryDate.difference(precedent.entryDate).inDays;
    final ecart = jours < 1 ? 1 : jours;

    return (dernier.weightSampleAvgG! - precedent.weightSampleAvgG!) / ecart;
  }

  List<LigneGmq> _lignesGmq(
    List<LivestockLot> bandes,
    List<LivestockDailyEntry> fiches,
  ) {
    final lignes = <LigneGmq>[];

    for (final bande in bandes) {
      final pesees = _pesees(bande.id, fiches);
      if (pesees.length < 2) continue;

      final dernier = pesees[pesees.length - 1];
      final precedent = pesees[pesees.length - 2];
      final jours = dernier.entryDate.difference(precedent.entryDate).inDays;
      final ecart = jours < 1 ? 1 : jours;
      final gmq =
          (dernier.weightSampleAvgG! - precedent.weightSampleAvgG!) / ecart;

      final code = bande.speciesCode ?? '';
      final objectif = objectifs[code];

      lignes.add(
        LigneGmq(
          code: bande.code,
          codeEspece: code,
          libelleEspece: libellesEspeces[code] ?? code,
          datePesee: dernier.entryDate,
          poidsPrecedent: precedent.weightSampleAvgG!,
          poidsActuel: dernier.weightSampleAvgG!,
          jours: ecart,
          gmq: gmq,
          statut: objectif == null
              // ⚠️ Le JS retombe sur `{min:0, max:9999}` : tout est « dans la
              // cible ». Un statut affiché sans objectif tromperait — l'espèce
              // n'a simplement pas de barème.
              ? StatutGmq.sansObjectif
              : gmq < objectif.$1
              ? StatutGmq.sousObjectif
              : gmq > objectif.$2
              ? StatutGmq.auDessusObjectif
              : StatutGmq.dansLaCible,
        ),
      );
    }

    lignes.sort((a, b) => b.datePesee.compareTo(a.datePesee));
    return lignes;
  }

  /// Série hebdomadaire du GMQ : le GMQ tel qu'il était connu à la fin de
  /// chaque semaine. `null` quand la bande n'avait pas encore deux pesées.
  List<double?> _serieHebdomadaire(
    List<LivestockLot> bandes,
    List<LivestockDailyEntry> fiches,
    DateTime jour, {
    required int semaines,
  }) {
    final serie = <double?>[];

    for (var i = semaines - 1; i >= 0; i--) {
      final borne = jour.subtract(Duration(days: 7 * i));
      final valeurs = bandes
          .map((b) => _gmq(b.id, fiches, jusquA: borne))
          .whereType<double>()
          .toList();

      serie.add(
        valeurs.isEmpty
            ? null
            : valeurs.reduce((a, b) => a + b) / valeurs.length,
      );
    }

    return serie;
  }

  // ── Mortalité ─────────────────────────────────────────────────────────────

  /// Effectif au début de la journée — même reconstitution que les tableaux
  /// mensuels des fiches, et même dénominateur que `previousEffectif()` côté
  /// serveur.
  static int _effectifDebut(LivestockDailyEntry f) =>
      f.effectifFinal + f.mort + f.vente + f.don - f.achat - f.ne;

  double? _mortalite(
    Set<String> lots,
    List<LivestockDailyEntry> fiches,
    DateTime jour,
  ) {
    final duMois = fiches.where(
      (f) =>
          lots.contains(f.lotId) &&
          f.entryDate.year == jour.year &&
          f.entryDate.month == jour.month,
    );

    if (duMois.isEmpty) return null;

    final morts = duMois.fold<int>(0, (t, f) => t + f.mort);
    final depart = duMois.fold<int>(0, (t, f) => t + _effectifDebut(f));

    if (depart <= 0) return null;
    return (morts / depart) * 100;
  }

  // ── Cartes espèces ────────────────────────────────────────────────────────

  List<CarteEspeceElevage> _cartes(
    List<LivestockLot> bandes,
    List<LivestockDailyEntry> fiches,
    DateTime jour,
  ) {
    List<LivestockLot> de(String code) =>
        bandes.where((b) => b.speciesCode == code).toList();

    String mortalite(String code) {
      final lots = de(code);
      final taux = _mortalite(lots.map((l) => l.id).toSet(), fiches, jour);
      return taux == null ? '—' : '${taux.toStringAsFixed(1)}%';
    }

    bool critique(String code) {
      final taux =
          _mortalite(de(code).map((l) => l.id).toSet(), fiches, jour) ?? 0;
      return taux >= 5;
    }

    String effectif(String code) =>
        '${de(code).fold<int>(0, (t, b) => t + b.currentQuantity)}';

    // Taux de ponte du mois, sur les seules bandes en ponte.
    final pondeuses = de(
      'aviculture',
    ).where((b) => (b.stage ?? '') == 'ponte').map((b) => b.id).toSet();
    final taux = fiches
        .where(
          (f) =>
              pondeuses.contains(f.lotId) &&
              f.entryDate.year == jour.year &&
              f.entryDate.month == jour.month,
        )
        .map(
          (f) => ProductionOeufsService.tauxDePonte(
            recoltes: f.ponteTotal ?? 0,
            effectif: f.effectifFinal,
          ),
        )
        .whereType<double>()
        .toList();

    final tauxPonte = taux.isEmpty
        ? '—'
        : '${(taux.reduce((a, b) => a + b) / taux.length).toStringAsFixed(1)}%';

    // ⚠️ « AUTONOMIE ALIMENT » EST UN TIRET SUR LES QUATRE CARTES — voir le
    // docblock de la classe : le poids du sac n'existe dans aucune colonne.
    const autonomie = ('Autonomie aliment', '—', false);

    return [
      CarteEspeceElevage(
        titre: 'Cuniculture',
        lignes: [
          ('Effectif vivant', effectif('cuniculture'), false),
          // ⚠️ Aucun décompte de mères ni de géniteurs n'est stocké : la fiche
          // les saisit, la base ne garde que l'effectif total.
          ('Mères / Géniteurs', '—', false),
          ('Taux mortalité', mortalite('cuniculture'), critique('cuniculture')),
          autonomie,
        ],
      ),
      CarteEspeceElevage(
        titre: 'Aviculture',
        lignes: [
          ('Effectif vivant', effectif('aviculture'), false),
          ('Taux de ponte', tauxPonte, false),
          ('Taux mortalité', mortalite('aviculture'), critique('aviculture')),
          autonomie,
        ],
      ),
      CarteEspeceElevage(
        titre: 'Porciculture',
        lignes: [
          ('Effectif vivant', effectif('porciculture'), false),
          ('Truies reproductrices', '—', false),
          (
            'Taux mortalité',
            mortalite('porciculture'),
            critique('porciculture'),
          ),
          autonomie,
        ],
      ),
      CarteEspeceElevage(
        titre: 'Héliciculture',
        lignes: [
          ('Effectif vivant', effectif('helico'), false),
          // ⚠️ Le couvoir hélicicole n'a pas de compteur d'œufs incubés : la
          // fiche Escargots ne porte aucune colonne d'éclosion.
          ("Taux d'éclosion", '—', false),
          ('Taux mortalité', mortalite('helico'), critique('helico')),
          autonomie,
        ],
      ),
    ];
  }

  // ── Rappels VMS ───────────────────────────────────────────────────────────

  /// ⚠️ **LE CYCLE EST CALCULÉ PAR `SoinsRepository`, PAS RECOPIÉ ICI.** Deux
  /// implémentations de la règle « J1 = le jour de référence » (mise en lot,
  /// ou dernière saillie pour une bande en reproduction, F0.91) finiraient
  /// par diverger, et un rappel affiché au mauvais jour fait administrer un
  /// traitement au mauvais moment.
  Future<List<RappelVms>> _rappels(
    List<LivestockLot> bandes,
    List<VeterinaryWithdrawalPeriod> remanences,
    DateTime jour,
  ) async {
    final rappels = <RappelVms>[];

    for (final bande in bandes) {
      final code = bande.speciesCode;
      if (code == null) continue;

      for (var d = 0; d <= horizonRappels; d++) {
        final quand = jour.add(Duration(days: d));
        final protocole = await soins.protocoleDuJour(
          bande: bande,
          codeEspece: code,
          quand: quand,
        );

        // ⚠️ Un traitement DEJA ADMINISTRE n'est plus un rappel : l'afficher
        // ferait redoser la bande.
        for (final t in protocole.traitements.where((t) => !t.dejaAdministre)) {
          rappels.add(
            RappelVms(
              libelle: '${t.standard.treatment} — ${bande.code}',
              echeance: d == 0
                  ? "Aujourd'hui"
                  : 'Dans $d jour${d > 1 ? 's' : ''}',
              jours: d,
              enRetard: false,
            ),
          );
        }
      }
    }

    // Rémanences en cours : elles ne sont pas des rappels de soin mais des
    // interdictions de vente en vigueur, et la maquette les mêle au bloc.
    for (final r in remanences.where((r) => !r.endDate.isBefore(jour))) {
      final restants = r.endDate.difference(jour).inDays;
      rappels.add(
        RappelVms(
          libelle: 'Rémanence en cours — ${r.productUsed ?? 'traitement'}',
          echeance: 'Fin dans $restants jour${restants > 1 ? 's' : ''}',
          jours: restants,
          enRetard: false,
        ),
      );
    }

    rappels.sort((a, b) => a.jours.compareTo(b.jours));
    return rappels;
  }

  // ── Analyse sanitaire ─────────────────────────────────────────────────────

  List<VeterinaryRecord> _duMois(List<VeterinaryRecord> soins, DateTime jour) =>
      soins
          .where(
            (s) =>
                s.recordDate.year == jour.year &&
                s.recordDate.month == jour.month,
          )
          .toList();

  List<LigneSanitaire> _sanitaire(
    List<LivestockLot> bandes,
    List<VeterinaryRecord> registre,
    DateTime jour,
  ) {
    final duMois = _duMois(registre, jour);

    return libellesEspeces.entries.map((e) {
      final lots = bandes
          .where((b) => b.speciesCode == e.key)
          .map((b) => b.id)
          .toSet();
      final leurs = duMois.where((s) => lots.contains(s.lotId)).toList();

      return LigneSanitaire(
        libelleEspece: e.value,
        nombreDeTraitements: leurs.length,
        coutTotal: leurs.fold<double>(0, (t, s) => t + (s.cost ?? 0)),
        // ⚠️ `infirmary_records` n'existe pas au poste — voir la classe.
        morbidite: null,
      );
    }).toList();
  }

  String? _plusFrequent(List<VeterinaryRecord> soins) {
    if (soins.isEmpty) return null;

    final compte = <String, int>{};
    for (final s in soins) {
      compte[s.actionType] = (compte[s.actionType] ?? 0) + 1;
    }

    return (compte.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }

  // ── Prévision de croissance ───────────────────────────────────────────────

  /// Projection linéaire, comme l'annonce la maquette : « Projection basée
  /// sur le GMQ moyen observé (7 derniers jours) appliqué de manière linéaire
  /// jusqu'à la date cible ».
  ///
  /// ⚠️⚠️ **LE GMQ EMPLOYÉ EST CELUI DU RESTE DE L'ÉCRAN — LES DEUX DERNIÈRES
  /// PESÉES.** La ferme pèse chaque semaine : les deux dernières pesées SONT,
  /// en pratique, les sept derniers jours. Appliquer ici une seconde formule
  /// mettrait deux GMQ différents sur le même écran, pour la même bande — le
  /// défaut exact que le ticket 14.9 a corrigé côté serveur en fusionnant
  /// `gmqForLot()` et `getGmqTableProperty()`.
  ///
  /// ⚠️ Laravel projette encore autrement : une **régression linéaire des
  /// moindres carrés sur toutes les pesées**, à partir de trois pesées.
  /// Troisième divergence de formule de cet écran, signalée et non tranchée.
  List<Prevision> _previsions(
    List<LivestockLot> bandes,
    List<LivestockDailyEntry> fiches,
    DateTime jour,
  ) {
    final previsions = <Prevision>[];

    for (final bande in bandes) {
      final pesees = _pesees(bande.id, fiches);
      // ⚠️ Trois pesées au minimum, comme Laravel : avec deux, la droite passe
      // par les deux points et ne mesure rien.
      if (pesees.length < 3) continue;

      final x0 = pesees.first.entryDate;
      final points = [
        for (final p in pesees)
          (p.entryDate.difference(x0).inDays.toDouble(), p.weightSampleAvgG!),
      ];

      final n = points.length;
      final sommeX = points.fold<double>(0, (a, p) => a + p.$1);
      final sommeY = points.fold<double>(0, (a, p) => a + p.$2);
      final sommeXY = points.fold<double>(0, (a, p) => a + p.$1 * p.$2);
      final sommeX2 = points.fold<double>(0, (a, p) => a + p.$1 * p.$1);

      final denominateur = n * sommeX2 - sommeX * sommeX;
      // Toutes les pesées le même jour : aucune pente à mesurer.
      if (denominateur == 0) continue;

      final pente = (n * sommeXY - sommeX * sommeY) / denominateur;
      final ordonnee = (sommeY - pente * sommeX) / n;

      previsions.add(
        Prevision(
          bandeId: bande.id,
          code: bande.code,
          libelleEspece:
              libellesEspeces[bande.speciesCode ?? ''] ??
              (bande.speciesCode ?? ''),
          poidsActuel: pesees.last.weightSampleAvgG!,
          gmqObserve: pente,
          ordonnee: ordonnee,
          dernierJour: points.last.$1.toInt(),
          nbPesees: n,
        ),
      );
    }

    return previsions;
  }
}
