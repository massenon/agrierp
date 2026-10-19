import 'dart:math' as math;

import '../../core/database/app_database.dart';
import 'production_oeufs_service.dart';
import 'soins_repository.dart';

/// Une ligne du tableau « GMQ & Croissance » — `DashboardElevage::getGmqTableProperty` (Blade).
///
/// ⚠️ Une bande active sans deux pesées a SA ligne (poids connus, « — » pour les jours,
/// « Pesées insuffisantes » pour le GMQ) : le Blade la montre, il ne la retire pas.
class LigneGmq {
  const LigneGmq({
    required this.code,
    required this.codeEspece,
    required this.libelleEspece,
    required this.poidsInitial,
    required this.poidsActuel,
    required this.jours,
    required this.gmq,
    required this.derniereDate,
  });

  final String code;
  final String codeEspece;

  /// Colonne « Filière » : libellé de l'espèce de la bande.
  final String libelleEspece;

  /// Première pesée (`null` : aucune pesée).
  final double? poidsInitial;

  /// Dernière pesée (`null` : aucune pesée).
  final double? poidsActuel;

  /// Jours entre la première et la dernière pesée — `null` sous deux pesées.
  final int? jours;

  /// GMQ CUMULÉ, 1 décimale — `null` sous deux pesées ou sur 0 jour.
  final double? gmq;

  /// Date de la dernière pesée (sert au choix de la bande suivie de la courbe du poste).
  final DateTime? derniereDate;
}

/// Une ligne du tableau « Prévision de Croissance » du Blade (`getPrevisionsProperty`).
class LignePrevision {
  const LignePrevision({
    required this.code,
    required this.insuffisant,
    this.poidsActuel,
    this.tendance,
    this.projection30j,
  });

  final String code;

  /// Moins de 3 pesées, ou toutes le même jour : « Historique insuffisant… ».
  final bool insuffisant;
  final int? poidsActuel;

  /// Pente arrondie à 1 décimale (g/j).
  final double? tendance;

  /// Poids projeté à 30 jours après la dernière pesée, arrondi à l'entier.
  final double? projection30j;
}

/// Un rappel du bloc « Rappels VMS à venir » (AJOUT du poste, décision client du 19/10/2026).
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

/// Une ligne du tableau « Analyse Sanitaire » (`getSanitaireBySpeciesProperty`).
class LigneSanitaire {
  const LigneSanitaire({
    required this.code,
    required this.libelleEspece,
    required this.nombreDeTraitements,
    required this.coutTotal,
    required this.morbidite,
  });

  final String code;
  final String libelleEspece;
  final int nombreDeTraitements;
  final double coutTotal;

  /// ⚠️ TOUJOURS `null` AU POSTE : le taux de morbidité se lit sur
  /// `infirmary_records`, table qui n'existe pas dans la base locale et que le
  /// tirage ne descend pas (décision D-H8, ticket H8b).
  final double? morbidite;
}

/// Une bande projetable des AJOUTS du poste (sélecteur, horizons, cartes) — même régression que
/// le tableau du Blade.
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
  double projeter(int jours) => DashboardElevageRepository.arrondiPhp(
    ordonnee + gmqObserve * (dernierJour + jours),
  );
}

/// Une carte de filière de l'onglet « Synthèse Globale ».
class CarteEspeceElevage {
  const CarteEspeceElevage({
    required this.code,
    required this.titre,
    required this.lignes,
  });

  final String code;
  final String titre;

  /// Lignes `(libellé, valeur, critique)` : les trois du Blade, dans son ordre (Effectif vivant,
  /// Taux mortalité (mois), Autonomie aliment), puis la ligne propre au poste quand l'espèce en a
  /// une (AJOUT conservé, décision client du 19/10/2026).
  final List<(String, String, bool)> lignes;
}

class DonneesDashboardElevage {
  const DonneesDashboardElevage({
    required this.effectifTotal,
    required this.gmqMoyen,
    required this.mortalite7j,
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
    required this.lignesPrevision,
    required this.previsions,
  });

  final int effectifTotal;

  /// Moyenne des GMQ cumulés des bandes actives, 1 décimale — `null` si aucune n'en a.
  final double? gmqMoyen;

  /// « Mortalité Cumulée (7j) » — 0,0 quand le dénominateur est nul, comme le web.
  final double mortalite7j;
  final List<CarteEspeceElevage> especes;

  /// AJOUT du poste — cinq points hebdomadaires (S1..S5) par code d'espèce ; `null` = pas assez
  /// de pesées à cette date.
  final Map<String, List<double?>> gmqParEspeceParSemaine;

  /// AJOUT du poste — liste des rappels (le web n'a qu'un texte et un lien).
  final List<RappelVms> rappels;

  /// Tableau du Blade : une ligne par bande active.
  final List<LigneGmq> lignesGmq;

  /// AJOUTS du poste (cartes de l'onglet GMQ).
  final Map<String, double?> gmqParEspece;
  final int lotsSuivis;

  /// AJOUT du poste — bande retenue pour la courbe « Évolution du GMQ ».
  final String? bandeSuivie;
  final List<double?> evolutionGmq;

  final List<LigneSanitaire> sanitaire;
  final int traitementsDuMois;
  final double coutSanitaireDuMois;
  final String? traitementLePlusFrequent;

  /// Tableau du Blade : une ligne par bande active, projetable ou non.
  final List<LignePrevision> lignesPrevision;

  /// AJOUT du poste — les seules bandes projetables, pour le sélecteur.
  final List<Prevision> previsions;
}

/// Espèce affichée : `LivestockSpecies::enabled()` côté web.
class _Espece {
  const _Espece({this.id, required this.code, required this.libelle});

  final String? id;
  final String code;
  final String libelle;
}

/// Lectures du Dashboard Élevage — le maître est `Livewire\Elevage\DashboardElevage` et sa vue
/// `dashboard-elevage.blade.php` (Doctrine, article 5 ; ticket H6).
///
/// ⚠️⚠️ **LE GMQ EST LE GMQ CUMULÉ DU SERVEUR** (`GrowthAnalysisService::gmqCumule`) : (dernière
/// pesée − PREMIÈRE pesée) ÷ jours écoulés, 1 décimale, `null` sur 0 jour. Le poste prenait les
/// deux dernières pesées (formule de la maquette) : pour une même bande, les deux surfaces
/// affichaient deux GMQ différents. Une seule formule sur tout l'écran, ajouts compris — la
/// parité est EXÉCUTÉE contre le vrai PHP (`test/dashboard_elevage_blade_test.dart`).
///
/// ⚠️ **PÉRIMÈTRE : `status = 'actif'` ET `is_active`** (`getActiveLotsProperty`) pour l'effectif,
/// le GMQ, la mortalité, les KPI sanitaires et les prévisions. Le tableau sanitaire par filière,
/// lui, prend les bandes NON ARCHIVÉES (`is_active` seul) : une bande clôturée ce mois-ci a bien
/// reçu ses soins — c'est la règle du web.
///
/// ⚠️ **L'AUTONOMIE ALIMENTAIRE N'EST CALCULABLE NULLE PART**, et Laravel
/// l'avait déjà constaté (carte marquée `pending`). Le stock d'aliment est compté **en sacs** et
/// le poids du sac ne vit que dans le NOM du produit (« Aliment ponte 25kg »), jamais dans une
/// colonne. **ARBITRAGE CLIENT** : ajouter une colonne de conditionnement (kg par unité).
class DashboardElevageRepository {
  DashboardElevageRepository({required this.database, required this.soins});

  final AppDatabase database;
  final SoinsRepository soins;

  /// Objectifs de GMQ des cartes de l'onglet GMQ (AJOUT du poste), en g/jour.
  static const objectifs = <String, (double, double)>{
    'cuniculture': (15, 20),
    'aviculture': (20, 55),
    'porciculture': (400, 650),
  };

  /// Libellés de repli, quand la table des espèces n'a pas encore été tirée.
  static const libellesEspeces = <String, String>{
    'cuniculture': 'Cuniculture',
    'aviculture': 'Aviculture',
    'porciculture': 'Porciculture',
    'helico': 'Héliciculture',
  };

  /// Ordre d'affichage des filières : celui du semis du serveur (`LivestockSpeciesSeeder`). Le web
  /// n'ordonne pas sa requête (`enabled()->get()`) : il suit l'ordre de la base.
  static const ordreEspeces = [
    'cuniculture',
    'aviculture',
    'porciculture',
    'helico',
  ];

  /// Horizon des rappels VMS, en jours.
  static const horizonRappels = 7;

  // ── Arithmétique et formats de PHP ─────────────────────────────────────────

  /// `round($v, $decimales)` de PHP 8.3 : demi-unité éloignée de zéro, APRÈS un pré-arrondi à
  /// 15 chiffres significatifs. Sans ce pré-arrondi, 29 ÷ 20 = 1,45 (stocké 1,4499…) donnerait
  /// 1,4 au poste et 1,5 au web.
  static double arrondiPhp(double v, [int decimales = 0]) {
    if (!v.isFinite) return v;
    final facteur = math.pow(10, decimales).toDouble();
    final pre = double.parse(v.toStringAsPrecision(15));
    final echelle = double.parse((pre * facteur).toStringAsPrecision(15));
    return echelle.round() / facteur;
  }

  /// Un flottant tel que PHP l'écrit (`{{ $gmq }}`) : « 28.6 », « 35 », « -3.5 ».
  static String nombrePhp(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  /// `number_format($v, 1, ',', ' ').' %'` : « 2,5 % ».
  static String pourcent(double v) =>
      '${arrondiPhp(v, 1).toStringAsFixed(1).replaceAll('.', ',')} %';

  /// `number_format($v, 0, ',', ' ')` : « 1 234 ».
  static String milliers(double v) {
    final arrondi = arrondiPhp(v).toInt();
    final entier = arrondi.abs().toString();
    final groupes = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      groupes.insert(0, entier.substring(math.max(0, i - 3), i));
    }
    return '${arrondi < 0 ? '-' : ''}${groupes.join(' ')}';
  }

  /// Jours calendaires entre deux dates (`diffInDays` sur des dates sans heure).
  static int _jours(DateTime de, DateTime a) => DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(de.year, de.month, de.day)).inDays;

  static DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

  /// `GrowthAnalysisService::gmqCumule` : [pesees] = `(date, poids)` d'UNE bande, dans n'importe
  /// quel ordre. (dernière − première) ÷ jours, 1 décimale ; `null` sous deux pesées ou sur 0 jour.
  static double? gmqCumule(List<(DateTime, double)> pesees) {
    if (pesees.length < 2) return null;
    final triees = [...pesees]..sort((a, b) => a.$1.compareTo(b.$1));
    final premiere = triees.first;
    final derniere = triees.last;
    final jours = _jours(premiere.$1, derniere.$1);

    // Deux pesées le même jour ne définissent aucun gain QUOTIDIEN.
    if (jours <= 0) return null;
    return arrondiPhp((derniere.$2 - premiere.$2) / jours, 1);
  }

  Future<DonneesDashboardElevage> charger({DateTime? quand}) async {
    final maintenant = quand ?? DateTime.now();
    final jour = _date(maintenant);

    final toutes = await (database.select(
      database.livestockLots,
    )..where((t) => t.isActive.equals(true))).get();
    // ⚠️ `getActiveLotsProperty` : `status = 'actif'` ET `is_active`. Une bande clôturée n'entre ni
    // dans l'effectif, ni dans le GMQ, ni dans la mortalité, ni dans les prévisions.
    final bandes = toutes.where((b) => b.status == 'actif').toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    final fiches = await database.select(database.livestockDailyEntries).get();
    final soinsRegistre = await database
        .select(database.veterinaryRecords)
        .get();
    final remanences = await database
        .select(database.veterinaryWithdrawalPeriods)
        .get();
    final especes = await _especes();

    final parLot = <String, List<LivestockDailyEntry>>{};
    for (final f in fiches) {
      (parLot[f.lotId] ??= []).add(f);
    }
    for (final l in parLot.values) {
      l.sort((a, b) => a.entryDate.compareTo(b.entryDate));
    }

    final lignes = [
      for (final b in bandes) _ligneGmq(b, parLot[b.id] ?? const [], especes),
    ];
    final avecGmq = lignes.where((l) => l.gmq != null).toList();
    final suivie = avecGmq.isEmpty
        ? null
        : (avecGmq.toList()
                ..sort((a, b) => b.derniereDate!.compareTo(a.derniereDate!)))
              .first;

    final duMoisActives = _duMois(
      soinsRegistre.where((s) => bandes.any((b) => b.id == s.lotId)),
      jour,
    );

    final lignesPrevision = <LignePrevision>[];
    final previsions = <Prevision>[];
    for (final b in bandes) {
      final (ligne, prevision) = _prevision(
        b,
        parLot[b.id] ?? const [],
        especes,
      );
      lignesPrevision.add(ligne);
      if (prevision != null) previsions.add(prevision);
    }

    return DonneesDashboardElevage(
      effectifTotal: bandes.fold<int>(0, (t, b) => t + b.currentQuantity),
      gmqMoyen: avecGmq.isEmpty
          ? null
          : arrondiPhp(
              avecGmq.fold<double>(0, (t, l) => t + l.gmq!) / avecGmq.length,
              1,
            ),
      mortalite7j: _mortalite(
        bandes,
        parLot,
        (d) =>
            !d.isBefore(maintenant.subtract(const Duration(days: 6))) &&
            !d.isAfter(maintenant),
      ),
      especes: _cartes(bandes, parLot, especes, jour),
      gmqParEspeceParSemaine: {
        for (final code in ['cuniculture', 'aviculture', 'porciculture'])
          code: _serieHebdomadaire(
            bandes.where((b) => b.speciesCode == code).toList(),
            parLot,
            jour,
            semaines: 5,
          ),
      },
      rappels: await _rappels(bandes, remanences, jour),
      lignesGmq: lignes,
      gmqParEspece: {
        for (final code in objectifs.keys)
          code: () {
            final v = avecGmq
                .where((l) => l.codeEspece == code)
                .map((l) => l.gmq!)
                .toList();
            return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
          }(),
      },
      lotsSuivis: avecGmq.length,
      bandeSuivie: suivie?.code,
      evolutionGmq: suivie == null
          ? const []
          : _serieHebdomadaire(
              bandes.where((b) => b.code == suivie.code).toList(),
              parLot,
              jour,
              semaines: 8,
            ),
      sanitaire: _sanitaire(toutes, soinsRegistre, especes, jour),
      traitementsDuMois: duMoisActives.length,
      coutSanitaireDuMois: duMoisActives.fold<double>(
        0,
        (t, s) => t + (s.cost ?? 0),
      ),
      traitementLePlusFrequent: _plusFrequent(duMoisActives),
      lignesPrevision: lignesPrevision,
      previsions: previsions,
    );
  }

  // ── Espèces ───────────────────────────────────────────────────────────────

  /// `LivestockSpecies::enabled()` : les espèces dont le module est ACTIF (`modules_config`).
  ///
  /// Le tirage ne sert déjà que les espèces activées ; l'intersection avec `modules_config`
  /// reproduit le scope tel quel. ⚠️ Table des espèces vide = PAS ENCORE TIRÉE (poste antérieur au
  /// ticket 15.15), pas « aucune espèce » : repli sur les codes des modules actifs, puis sur les
  /// quatre filières connues, avec leurs libellés courts.
  Future<List<_Espece>> _especes() async {
    final modules = await database.select(database.modulesConfig).get();
    final actifs = modules.isEmpty
        ? null
        : {
            for (final m in modules)
              if (m.isEnabled) m.speciesCode,
          };
    final table = await database.select(database.livestockSpecies).get();

    final especes = table.isNotEmpty
        ? [
            for (final e in table)
              if (actifs == null || actifs.contains(e.code))
                _Espece(id: e.id, code: e.code, libelle: e.label),
          ]
        : [
            for (final code in actifs ?? ordreEspeces.toSet())
              _Espece(code: code, libelle: libellesEspeces[code] ?? code),
          ];

    int rang(_Espece e) {
      final i = ordreEspeces.indexOf(e.code);
      return i < 0 ? ordreEspeces.length : i;
    }

    return especes..sort((a, b) {
      final r = rang(a).compareTo(rang(b));
      return r != 0 ? r : a.libelle.compareTo(b.libelle);
    });
  }

  static bool _de(LivestockLot b, _Espece e) =>
      b.speciesId == e.id || (b.speciesCode != null && b.speciesCode == e.code);

  static String _libelle(LivestockLot b, List<_Espece> especes) =>
      especes.where((e) => _de(b, e)).firstOrNull?.libelle ??
      libellesEspeces[b.speciesCode] ??
      b.speciesCode ??
      '—';

  // ── GMQ ───────────────────────────────────────────────────────────────────

  /// Pesées d'une bande, chronologiques : `whereNotNull('weight_sample_avg_g')`.
  ///
  /// ⚠️ UNE PESÉE À 0 EST RETENUE, comme au serveur : seul `null` veut dire « pas de pesée ». Le
  /// poste écartait le 0 ; le web le garde, et les deux GMQ divergeaient.
  static List<(DateTime, double)> _pesees(
    List<LivestockDailyEntry> fiches, {
    DateTime? jusquA,
  }) => [
    for (final f in fiches)
      if (f.weightSampleAvgG != null &&
          (jusquA == null || !f.entryDate.isAfter(jusquA)))
        (f.entryDate, f.weightSampleAvgG!),
  ];

  LigneGmq _ligneGmq(
    LivestockLot bande,
    List<LivestockDailyEntry> fiches,
    List<_Espece> especes,
  ) {
    final pesees = _pesees(fiches);
    final deux = pesees.length >= 2;

    return LigneGmq(
      code: bande.code,
      codeEspece: bande.speciesCode ?? '',
      libelleEspece: _libelle(bande, especes),
      poidsInitial: pesees.firstOrNull?.$2,
      poidsActuel: pesees.lastOrNull?.$2,
      jours: deux ? _jours(pesees.first.$1, pesees.last.$1) : null,
      gmq: gmqCumule(pesees),
      derniereDate: pesees.lastOrNull?.$1,
    );
  }

  /// AJOUT du poste — série hebdomadaire du GMQ cumulé tel qu'il était connu à la fin de chaque
  /// semaine. `null` quand aucune bande n'avait encore deux pesées.
  List<double?> _serieHebdomadaire(
    List<LivestockLot> bandes,
    Map<String, List<LivestockDailyEntry>> parLot,
    DateTime jour, {
    required int semaines,
  }) {
    final serie = <double?>[];

    for (var i = semaines - 1; i >= 0; i--) {
      final borne = jour.subtract(Duration(days: 7 * i));
      final valeurs = bandes
          .map(
            (b) => gmqCumule(_pesees(parLot[b.id] ?? const [], jusquA: borne)),
          )
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

  /// `LivestockDailyEntry::previousEffectif()` : l'effectif final de la fiche la plus récente
  /// STRICTEMENT antérieure (par date), sinon l'effectif initial de la bande.
  static int _effectifPrecedent(
    LivestockDailyEntry f,
    List<LivestockDailyEntry> fichesDuLot,
    LivestockLot bande,
  ) {
    final jour = _date(f.entryDate);
    LivestockDailyEntry? veille;
    for (final g in fichesDuLot) {
      if (g.id == f.id || !_date(g.entryDate).isBefore(jour)) continue;
      if (veille == null || g.entryDate.isAfter(veille.entryDate)) veille = g;
    }
    return veille?.effectifFinal ?? bande.initialQuantity;
  }

  /// Σ morts ÷ Σ previousEffectif × 100, 1 décimale ; 0,0 si le dénominateur est nul.
  ///
  /// ⚠️ [dansFenetre] reçoit la date de la fiche À MINUIT, comme MySQL promeut une DATE en
  /// DATETIME pour la comparer à `now()->subDays(6)` : à 10 h 15, la fiche de J-6 (minuit) est
  /// AVANT la borne et sort de la fenêtre « 7j ». Comportement réel du web, vérifié en PHP.
  double _mortalite(
    List<LivestockLot> bandes,
    Map<String, List<LivestockDailyEntry>> parLot,
    bool Function(DateTime) dansFenetre,
  ) {
    var morts = 0;
    var depart = 0;
    for (final b in bandes) {
      final fichesDuLot = parLot[b.id] ?? const <LivestockDailyEntry>[];
      for (final f in fichesDuLot) {
        if (!dansFenetre(_date(f.entryDate))) continue;
        morts += f.mort;
        depart += _effectifPrecedent(f, fichesDuLot, b);
      }
    }
    return depart > 0 ? arrondiPhp(morts / depart * 100, 1) : 0.0;
  }

  // ── Cartes de filière ─────────────────────────────────────────────────────

  List<CarteEspeceElevage> _cartes(
    List<LivestockLot> bandes,
    Map<String, List<LivestockDailyEntry>> parLot,
    List<_Espece> especes,
    DateTime jour,
  ) {
    final debutMois = DateTime(jour.year, jour.month);
    final finMois = DateTime(jour.year, jour.month + 1, 0);

    return [
      for (final e in especes)
        () {
          final lots = bandes.where((b) => _de(b, e)).toList();
          final taux = _mortalite(
            lots,
            parLot,
            (d) => !d.isBefore(debutMois) && !d.isAfter(finMois),
          );
          final supplement = _ligneDuPoste(e.code, lots, parLot, jour);

          return CarteEspeceElevage(
            code: e.code,
            titre: e.libelle,
            lignes: [
              (
                'Effectif vivant',
                '${lots.fold<int>(0, (t, b) => t + b.currentQuantity)}',
                false,
              ),
              ('Taux mortalité (mois)', pourcent(taux), taux > 5),
              // ⚠️ « Autonomie aliment » : un tiret, comme au web (voir l'en-tête de classe).
              ('Autonomie aliment', '—', false),
              ?supplement,
            ],
          );
        }(),
    ];
  }

  /// AJOUT du poste (maquette) conservé : la deuxième ligne propre à chaque filière.
  (String, String, bool)? _ligneDuPoste(
    String code,
    List<LivestockLot> lots,
    Map<String, List<LivestockDailyEntry>> parLot,
    DateTime jour,
  ) {
    switch (code) {
      case 'cuniculture':
        // ⚠️ Aucun décompte de mères ni de géniteurs n'est stocké.
        return ('Mères / Géniteurs', '—', false);
      case 'porciculture':
        return ('Truies reproductrices', '—', false);
      case 'helico':
        // ⚠️ La fiche Escargots ne porte aucune colonne d'éclosion.
        return ("Taux d'éclosion", '—', false);
      case 'aviculture':
        // Taux de ponte du mois, sur les seules bandes en ponte.
        final taux = [
          for (final b in lots.where((b) => (b.stage ?? '') == 'ponte'))
            for (final f in parLot[b.id] ?? const <LivestockDailyEntry>[])
              if (f.entryDate.year == jour.year &&
                  f.entryDate.month == jour.month)
                ProductionOeufsService.tauxDePonte(
                  recoltes: f.ponteTotal ?? 0,
                  effectif: f.effectifFinal,
                ),
        ].whereType<double>().toList();
        return (
          'Taux de ponte',
          taux.isEmpty
              ? '—'
              : '${(taux.reduce((a, b) => a + b) / taux.length).toStringAsFixed(1)}%',
          false,
        );
    }
    return null;
  }

  // ── Rappels VMS (AJOUT du poste) ──────────────────────────────────────────

  /// ⚠️ **LE CYCLE EST CALCULÉ PAR `SoinsRepository`, PAS RECOPIÉ ICI.** Deux
  /// implémentations de la règle « J1 = le jour de référence » finiraient
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

  /// `whereMonth` / `whereYear` sur `record_date`.
  ///
  /// ⚠️ Le web écarte aussi les soins ARCHIVÉS (`is_active = false`). Le poste n'a pas cette
  /// colonne : le tirage ne sert que les soins actifs, mais un soin archivé APRÈS avoir été tiré
  /// reste ici (limite de la donnée, schéma inchangé au ticket H6).
  List<VeterinaryRecord> _duMois(
    Iterable<VeterinaryRecord> soins,
    DateTime jour,
  ) => soins
      .where(
        (s) =>
            s.recordDate.year == jour.year && s.recordDate.month == jour.month,
      )
      .toList();

  /// `getSanitaireBySpeciesProperty` : par espèce activée, les soins du mois des bandes NON
  /// ARCHIVÉES de l'espèce (clôturées comprises).
  List<LigneSanitaire> _sanitaire(
    List<LivestockLot> nonArchivees,
    List<VeterinaryRecord> registre,
    List<_Espece> especes,
    DateTime jour,
  ) {
    final duMois = _duMois(registre, jour);

    return [
      for (final e in especes)
        () {
          final lots = {
            for (final b in nonArchivees)
              if (_de(b, e)) b.id,
          };
          final leurs = duMois.where((s) => lots.contains(s.lotId)).toList();

          return LigneSanitaire(
            code: e.code,
            libelleEspece: e.libelle,
            nombreDeTraitements: leurs.length,
            coutTotal: leurs.fold<double>(0, (t, s) => t + (s.cost ?? 0)),
            // ⚠️ `infirmary_records` n'existe pas au poste — voir la classe.
            morbidite: null,
          );
        }(),
    ];
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

  /// `getPrevisionsProperty` : régression linéaire (moindres carrés) sur TOUTES les pesées de la
  /// bande, trois au minimum ; x = jours depuis la première pesée.
  (LignePrevision, Prevision?) _prevision(
    LivestockLot bande,
    List<LivestockDailyEntry> fiches,
    List<_Espece> especes,
  ) {
    final pesees = _pesees(fiches);
    final insuffisant = LignePrevision(code: bande.code, insuffisant: true);
    if (pesees.length < 3) return (insuffisant, null);

    final x0 = pesees.first.$1;
    final points = [
      for (final p in pesees) (_jours(x0, p.$1).toDouble(), p.$2),
    ];

    final n = points.length;
    final sommeX = points.fold<double>(0, (a, p) => a + p.$1);
    final sommeY = points.fold<double>(0, (a, p) => a + p.$2);
    final sommeXY = points.fold<double>(0, (a, p) => a + p.$1 * p.$2);
    final sommeX2 = points.fold<double>(0, (a, p) => a + p.$1 * p.$1);

    final denominateur = n * sommeX2 - sommeX * sommeX;
    // Toutes les pesées le même jour : aucune pente à mesurer.
    if (denominateur == 0) return (insuffisant, null);

    final pente = (n * sommeXY - sommeX * sommeY) / denominateur;
    final ordonnee = (sommeY - pente * sommeX) / n;
    final dernierX = points.last.$1;

    return (
      LignePrevision(
        code: bande.code,
        insuffisant: false,
        poidsActuel: pesees.last.$2.toInt(),
        tendance: arrondiPhp(pente, 1),
        projection30j: arrondiPhp(ordonnee + pente * (dernierX + 30)),
      ),
      Prevision(
        bandeId: bande.id,
        code: bande.code,
        libelleEspece: _libelle(bande, especes),
        poidsActuel: pesees.last.$2,
        gmqObserve: pente,
        ordonnee: ordonnee,
        dernierJour: dernierX.toInt(),
        nbPesees: n,
      ),
    );
  }
}
