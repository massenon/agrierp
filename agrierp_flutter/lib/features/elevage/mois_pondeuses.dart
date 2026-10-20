import '../../core/database/app_database.dart';
import '../../core/export/document_officiel.dart';
import '../stocks/journal_stocks.dart';
import '../stocks/pmp_service.dart';
import 'effectif_precedent.dart';

/// Les quatre cartes de la fiche Pondeuses du web (`FichePondeuses::getKpisProperty()`), DÉJÀ mises en forme.
class IndicateursPondeuses {
  const IndicateursPondeuses({
    required this.effectif,
    required this.tauxPonteMoyen,
    required this.stockPlateaux,
    required this.tauxMortaliteMois,
  });

  /// `number_format(Σ current_quantity des bandes, 0, ',', ' ')`.
  final String effectif;

  /// `number_format(taux, 1, ',', ' ').' %'` — « 0,0 % » sans effectif ni fiche, comme le web.
  final String tauxPonteMoyen;

  /// `floor(stock_qty).' Plateaux'` du produit œufs ; `null` sans produit œufs (carte « en attente » du web).
  final String? stockPlateaux;

  /// `number_format(taux, 1, ',', ' ').' %'`.
  final String tauxMortaliteMois;
}

/// Une ligne du tableau du mois : un JOUR du mois, avec ou sans fiche.
class JourPondeuses {
  const JourPondeuses({
    required this.jour,
    required this.fiche,
    required this.effectifDebut,
    required this.traitements,
  });

  final DateTime jour;

  /// Fiche de la bande ce jour-là, `null` pour un jour sans fiche (toutes ses cellules sont alors « — », sauf la
  /// colonne « Traitements & Rappels », qui peut porter un soin du registre).
  final LivestockDailyEntry? fiche;

  /// `$entry->previousEffectif()` ; `null` sans fiche.
  final int? effectifDebut;

  /// `traitementsDuJour($dateStr, $entry)` du web.
  final String traitements;

  /// « Date / Jour » : `format('d/m')`.
  String get date =>
      '${jour.day.toString().padLeft(2, '0')}/${jour.month.toString().padLeft(2, '0')}';

  /// `number_format($x, 1)` de PHP : point décimal, virgule des milliers.
  static String _un(double x) =>
      PmpService.nombre(x, 1, virgule: '.', milliers: ',');

  /// Cellules du groupe « Cheptel du Jour » puis « Suivi de la Ponte & Récolte », comme le Blade :
  /// Eff. Début, Morts, Taux Mort %, Eff. Fin, Total (OR), Taux Ponte %, Cassés (OF), Comm. (OR-OF).
  ///
  ///   Taux Mort % = `number_format($entry->mortality_rate, 1)`, `mortality_rate` = `round(morts ÷ effectif de
  ///     début × 100, 2)` (0 si l'effectif de début est nul) — DEUX arrondis, comme le web ;
  ///   Taux Ponte % = `number_format(round(OR ÷ effectif de début × 100, 1), 1)`, « — » sans effectif de début
  ///     (le web divise par l'effectif de DÉBUT, pas par l'effectif final) ;
  ///   Comm. = `max(0, OR − OF)`.
  List<String> get cellules {
    final f = fiche;
    if (f == null) return List.filled(8, '—');
    final debut = effectifDebut!;
    final or = f.ponteTotal ?? 0;
    final mortalite = debut <= 0
        ? 0.0
        : PmpService.arrondi(f.mort / debut * 100, 2);
    final comm = or - (f.ponteCasses ?? 0);
    return [
      '$debut',
      '${f.mort}',
      _un(mortalite),
      '${f.effectifFinal}',
      f.ponteTotal == null ? '—' : '${f.ponteTotal}',
      debut > 0 ? _un(PmpService.arrondi(or / debut * 100, 1)) : '—',
      f.ponteCasses == null ? '—' : '${f.ponteCasses}',
      '${comm < 0 ? 0 : comm}',
    ];
  }
}

/// Le mois de la fiche Pondeuses : indicateurs, tableau, PDF.
class DonneesMoisPondeuses {
  const DonneesMoisPondeuses({
    required this.indicateurs,
    required this.jours,
    required this.document,
  });

  final IndicateursPondeuses indicateurs;

  /// TOUS les jours du mois en cours, du 1er au dernier (`range(1, now()->daysInMonth)`).
  final List<JourPondeuses> jours;

  /// « Exporter PDF » (`exportFichePdf()`).
  final DocumentOfficiel document;
}

/// 🔴→✅ Ticket U11 — LE MOIS DE LA FICHE PONDEUSES DU WEB (`FichePondeuses` et `AvecSoinsDuMois`), calculé au poste.
///
/// Le poste ne listait que les jours SAISIS, en « Jour N (jj/mm) », avec un effectif de début reconstitué
/// (`effectif final + morts + ventes − achats − nés`, sans dons ni transferts) et une colonne « Traitements &
/// Rappels » toujours vide ; ses indicateurs étaient ceux du FORMULAIRE (effectif final, taux du jour). Le web est
/// maître (article 5) :
///
///   • tableau : chaque jour du mois en cours (celui de MAINTENANT, pas du jour choisi), la fiche de la bande s'il y
///     en a une, l'effectif de début `previousEffectif()` (fiche précédente de la bande, sinon son effectif
///     initial) ;
///   • « Traitements & Rappels » : les soins ACTIFS du registre de la bande ce jour-là (« type (produit) », dans
///     l'ordre de saisie, sans doublon), puis le produit de traitement de la fiche, sinon ses symptômes, sinon « — » ;
///   • indicateurs : effectif = Σ des effectifs courants des bandes de la fiche ; taux de ponte moyen et taux de
///     mortalité du MOIS sur toutes ces bandes ; stock de plateaux = stock du produit œufs du web, arrondi par défaut.
///
/// ⚠️ Ordre de deux soins du même jour : `created_at` au web, qui ne descend pas au poste ; le poste prend
/// `updated_at` (l'instant de saisie, jamais touché ensuite tant que le soin est actif), puis l'identifiant.
abstract final class MoisPondeuses {
  static Future<DonneesMoisPondeuses> charger(
    AppDatabase db, {
    required List<LivestockLot> bandes,
    required LivestockLot? bande,
    required DateTime maintenant,
  }) async {
    final debutMois = DateTime(maintenant.year, maintenant.month);
    final finMois = DateTime(maintenant.year, maintenant.month + 1);
    bool duMois(DateTime d) => !d.isBefore(debutMois) && d.isBefore(finMois);

    final ids = {for (final b in bandes) b.id};
    final fiches = [
      for (final f in await db.select(db.livestockDailyEntries).get())
        if (ids.contains(f.lotId)) f,
    ];
    final produits = await db.select(db.products).get();
    final soins = bande == null
        ? const <VeterinaryRecord>[]
        : [
            for (final s in await db.select(db.veterinaryRecords).get())
              if (s.lotId == bande.id && s.isActive && duMois(s.recordDate)) s,
          ];

    final ficheDu = {
      for (final f in fiches)
        if (bande != null && f.lotId == bande.id && duMois(f.entryDate))
          JournalStocks.jour(f.entryDate): f,
    };
    final nomProduit = {for (final p in produits) p.id: p.name};

    final jours = [
      for (var j = 1; j <= DateTime(maintenant.year, maintenant.month + 1, 0).day; j++)
        () {
          final jour = DateTime(maintenant.year, maintenant.month, j);
          final fiche = ficheDu[jour];
          return JourPondeuses(
            jour: jour,
            fiche: fiche,
            effectifDebut: fiche == null
                ? null
                : effectifPrecedentDe(fiche, fiches, bandes),
            traitements: traitementsDuJour(
              jour,
              fiche,
              soins,
              fiche?.treatmentProductId == null
                  ? null
                  : nomProduit[fiche!.treatmentProductId],
            ),
          );
        }(),
    ];

    return DonneesMoisPondeuses(
      indicateurs: indicateurs(
        bandes: bandes,
        fiches: fiches,
        produitOeufs: JournalStocks.produitOeufs(produits),
        maintenant: maintenant,
      ),
      jours: jours,
      document: document(jours, maintenant),
    );
  }

  /// `FichePondeuses::getKpisProperty()`, formule pour formule. [fiches] : toutes les fiches des [bandes] (toutes
  /// dates : l'effectif de début d'une fiche du 1er vient du mois précédent).
  static IndicateursPondeuses indicateurs({
    required List<LivestockLot> bandes,
    required List<LivestockDailyEntry> fiches,
    required Product? produitOeufs,
    required DateTime maintenant,
  }) {
    final debutMois = DateTime(maintenant.year, maintenant.month);
    final finMois = DateTime(maintenant.year, maintenant.month + 1);
    final ids = {for (final b in bandes) b.id};
    final duMois = [
      for (final f in fiches)
        if (ids.contains(f.lotId) &&
            !f.entryDate.isBefore(debutMois) &&
            f.entryDate.isBefore(finMois))
          f,
    ];

    final morts = duMois.fold<int>(0, (t, f) => t + f.mort);
    final departs = duMois.fold<int>(
      0,
      (t, f) => t + effectifPrecedentDe(f, fiches, bandes),
    );
    final effectif = bandes.fold<int>(0, (t, b) => t + b.currentQuantity);
    final oeufs = duMois.fold<int>(0, (t, f) => t + (f.ponteTotal ?? 0));
    final ponte = effectif > 0 && duMois.isNotEmpty
        ? PmpService.arrondi(oeufs / duMois.length / effectif * 100, 1)
        : 0.0;
    final mortalite = departs > 0
        ? PmpService.arrondi(morts / departs * 100, 1)
        : 0.0;

    return IndicateursPondeuses(
      effectif: PmpService.francs(effectif.toDouble()),
      tauxPonteMoyen: '${PmpService.nombre(ponte, 1)} %',
      stockPlateaux: produitOeufs == null
          ? null
          : '${produitOeufs.stockQty.floor()} Plateaux',
      tauxMortaliteMois: '${PmpService.nombre(mortalite, 1)} %',
    );
  }

  /// `AvecSoinsDuMois::traitementsDuJour()` : soins actifs du jour (« action_type (product_used) », vides écartés,
  /// sans doublon), puis le produit de traitement de la fiche ; sinon les symptômes de la fiche ; sinon « — ».
  /// Les chaînes « 0 » sont fausses en PHP (`?:`, `filter()`), comme les vides.
  static String traitementsDuJour(
    DateTime jour,
    LivestockDailyEntry? fiche,
    List<VeterinaryRecord> soins,
    String? produitTraitement,
  ) {
    bool vrai(String? s) => s != null && s.isNotEmpty && s != '0';
    final duJour = [
      for (final s in soins)
        if (JournalStocks.jour(s.recordDate) == JournalStocks.jour(jour)) s,
    ]..sort((a, b) {
        final parSaisie = a.updatedAt.compareTo(b.updatedAt);
        return parSaisie != 0 ? parSaisie : a.id.compareTo(b.id);
      });
    final libelles = <String>[];
    for (final s in duJour) {
      final l = '${s.actionType}${vrai(s.productUsed) ? ' (${s.productUsed})' : ''}'
          .trim();
      if (vrai(l) && !libelles.contains(l)) libelles.add(l);
    }
    if (vrai(produitTraitement) && !libelles.contains(produitTraitement)) {
      libelles.add(produitTraitement!);
    }
    if (libelles.isNotEmpty) return libelles.join(', ');
    return vrai(fiche?.symptomes) ? fiche!.symptomes! : '—';
  }

  static const _mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre',
    'décembre',
  ];

  /// « Exporter PDF » — `exportFichePdf()` : gabarit PARTAGÉ `exports.fiche-elevage`, titre « Fiche Pondeuses — Suivi
  /// Mensuel », sous-titre `now()->translatedFormat('F Y')` (« octobre 2026 »), les fiches du mois de la bande par
  /// date, huit colonnes ; « Aucune saisie ce mois-ci. » sans fiche ; fichier `fiche-AAAA-MM.pdf`.
  static DocumentOfficiel document(List<JourPondeuses> jours, DateTime maintenant) {
    String deux(int n) => n.toString().padLeft(2, '0');
    final saisis = [for (final j in jours) if (j.fiche != null) j];
    return DocumentOfficiel(
      titre: 'Fiche Pondeuses — Suivi Mensuel',
      sousTitre: '${_mois[maintenant.month - 1]} ${maintenant.year}',
      fichier: 'fiche-{mois}.pdf',
      entetes: const [
        'Date',
        'Achat',
        'Nés',
        'Morts',
        'Ventes',
        'Dons',
        'Effectif Final',
        'Mortalité',
      ],
      lignes: [
        if (saisis.isEmpty)
          const DonneesDocument(['Aucune saisie ce mois-ci.']),
        for (final j in saisis)
          () {
            final f = j.fiche!;
            final debut = j.effectifDebut!;
            final mortalite = debut <= 0
                ? 0.0
                : PmpService.arrondi(f.mort / debut * 100, 2);
            return DonneesDocument([
              '${deux(j.jour.day)}/${deux(j.jour.month)}/${j.jour.year}',
              '${f.achat}',
              '${f.ne}',
              '${f.mort}',
              '${f.vente}',
              '${f.don}',
              '${f.effectifFinal}',
              '${PmpService.nombre(mortalite, 1)}%',
            ]);
          }(),
      ],
    );
  }
}
