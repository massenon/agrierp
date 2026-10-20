import '../../core/database/app_database.dart';
import '../../core/export/document_officiel.dart';
import '../stocks/journal_stocks.dart';
import '../stocks/pmp_service.dart';
import 'effectif_precedent.dart';
import 'mois_pondeuses.dart';

/// Les quatre fiches du ticket U12a, avec ce qui les distingue au web : code d'espèce de leurs bandes et titre de leur
/// PDF (`exportFichePdf()` de chaque composant).
enum EspeceFiche {
  lapins('cuniculture', 'Fiche Lapins — Suivi Mensuel'),
  porcs('porciculture', 'Fiche Porcs — Suivi Mensuel'),
  reproducteurs('aviculture', 'Fiche Reproducteurs (Aviculture) — Suivi Mensuel'),
  escargots('helico', 'Fiche Escargots — Suivi Mensuel');

  const EspeceFiche(this.codeEspece, this.titrePdf);

  final String codeEspece;
  final String titrePdf;
}

/// Une ligne du tableau du mois : un JOUR du mois, avec ou sans fiche.
class JourFiche {
  const JourFiche({
    required this.jour,
    required this.fiche,
    required this.effectifDebut,
    required this.traitements,
  });

  final DateTime jour;

  /// Fiche de la bande ce jour-là, `null` pour un jour sans fiche (ses cellules sont alors « — », sauf la colonne
  /// « Traitements & Prophylaxie », qui peut porter un soin du registre).
  final LivestockDailyEntry? fiche;

  /// `$entry->previousEffectif()` ; `null` sans fiche.
  final int? effectifDebut;

  /// `traitementsDuJour($dateStr, $entry)` du web (`AvecSoinsDuMois`) ; vide pour la fiche Reproducteurs, dont le
  /// tableau n'a pas cette colonne.
  final String traitements;

  /// « Date » : `format('d/m')`.
  String get date =>
      '${jour.day.toString().padLeft(2, '0')}/${jour.month.toString().padLeft(2, '0')}';

  /// `$entry->mortality_rate` : `round(morts ÷ effectif de début × 100, 2)`, 0 si l'effectif de début est nul ; `null`
  /// sans fiche.
  double? get tauxMortalite {
    final f = fiche;
    if (f == null) return null;
    final debut = effectifDebut!;
    return debut <= 0 ? 0.0 : PmpService.arrondi(f.mort / debut * 100, 2);
  }

  /// `{{ $entry ? number_format($entry->mortality_rate, 1) : '—' }}` — point décimal, virgule des milliers (DEUX
  /// arrondis, comme le web).
  String get tauxMort {
    final t = tauxMortalite;
    return t == null ? '—' : PmpService.nombre(t, 1, virgule: '.', milliers: ',');
  }

  /// `getPoidsGeneralGAttribute()` : total pesé reconstitué, `(int) round(moyenne × effectif final)` ; `null` sans
  /// pesée (moyenne absente ou nulle) ou sans effectif final.
  int? get poidsGeneralG {
    final f = fiche;
    final moyenne = f?.weightSampleAvgG;
    if (f == null || moyenne == null || moyenne == 0 || f.effectifFinal == 0) return null;
    return (moyenne * f.effectifFinal).round();
  }

  /// Fiche Porcs : `round((moyenne × effectif final) ÷ 1000, 1)`, affiché tel quel par PHP (« 85 », « 85.5 ») ; « — »
  /// sans pesée.
  String get poidsGeneralKg {
    final f = fiche;
    final moyenne = f?.weightSampleAvgG;
    if (f == null || moyenne == null || moyenne == 0 || f.effectifFinal == 0) return '—';
    return PmpService.flottant(PmpService.arrondi(moyenne * f.effectifFinal / 1000, 1));
  }

  /// `{{ $entry?->colonne ?? '—' }}`.
  static String _ou(int? v) => v == null ? '—' : '$v';

  /// Les cellules du tableau du mois, après « Date », dans l'ordre du Blade de chaque fiche :
  ///   • Lapins : Achat, Né, Mort, Vente, Don, M, F, Jeunes, S/Mères, Total, Taux Mort %, Poids Général (g),
  ///     Traitements & Prophylaxie ;
  ///   • Porcs : Achat, Né, Mort, Vente, Don, Truies Gest. (`effectif_f`), Verrats (`effectif_m`), Porcelets,
  ///     Engraiss., Total, Taux Mort %, Poids Général (Kg), Traitements & Prophylaxie ;
  ///   • Escargots : Achat, Naissain Né, Mort, Vente, Don, Naissains, Engraiss., Bordés, Total, Taux Mort %, Poids
  ///     Général (g), Traitements & Prophylaxie ;
  ///   • Reproducteurs : Couvés, Nés, Repro+Poulet+Poussin, Effectif Final, Taux Mort %, Poids Général (g).
  List<String> cellules(EspeceFiche espece) {
    final f = fiche;
    final poidsG = poidsGeneralG;
    final g = poidsG == null ? '—' : '$poidsG';
    final mouvements = [
      _ou(f?.achat),
      _ou(f?.ne),
      _ou(f?.mort),
      _ou(f?.vente),
      _ou(f?.don),
    ];
    return switch (espece) {
      EspeceFiche.lapins => [
        ...mouvements,
        _ou(f?.effectifM),
        _ou(f?.effectifF),
        _ou(f?.effectifSevres),
        _ou(f?.effectifSmeres),
        _ou(f?.effectifFinal),
        tauxMort,
        g,
        traitements,
      ],
      EspeceFiche.porcs => [
        ...mouvements,
        _ou(f?.effectifF),
        _ou(f?.effectifM),
        _ou(f?.effectifSevres),
        _ou(f?.effectifSmeres),
        _ou(f?.effectifFinal),
        tauxMort,
        poidsGeneralKg,
        traitements,
      ],
      EspeceFiche.escargots => [
        ...mouvements,
        _ou(f?.effectifM),
        _ou(f?.effectifF),
        _ou(f?.effectifSevres),
        _ou(f?.effectifFinal),
        tauxMort,
        g,
        traitements,
      ],
      EspeceFiche.reproducteurs => [
        _ou(f?.ponteTotal),
        _ou(f?.ne),
        _ou(f?.mort),
        _ou(f?.effectifFinal),
        tauxMort,
        g,
      ],
    };
  }
}

/// Le mois d'une fiche : indicateurs (déjà mis en forme), tableau, PDF.
class DonneesMoisFiche {
  const DonneesMoisFiche({
    required this.indicateurs,
    required this.jours,
    required this.document,
    required this.fiches,
  });

  /// Les quatre `x-kpi-card` du Blade, valeurs mises en forme comme le web, dans l'ordre du Blade.
  final List<String> indicateurs;

  /// TOUS les jours du mois affiché, du 1er au dernier (`getDaysInMonthProperty()` d'`AvecMoisDeFiche`).
  final List<JourFiche> jours;

  /// « Exporter PDF » (`exportFichePdf()`).
  final DocumentOfficiel document;

  /// Toutes les fiches des bandes de la fiche, toutes dates (veille, tête implicite…).
  final List<LivestockDailyEntry> fiches;
}

/// 🔴→✅ Ticket U12a — LE MOIS DES FICHES LAPINS, PORCS, REPRODUCTEURS ET ESCARGOTS DU WEB, calculé au poste (modèle :
/// [MoisPondeuses], ticket U11).
///
/// Le poste ne listait que les jours SAISIS, en « Jour N (jj/mm) », avec un taux de mortalité divisé par un effectif
/// de début reconstitué, une colonne « Traitements & Prophylaxie » vide et des cartes calculées sur le FORMULAIRE. Le
/// web est maître (article 5) :
///
///   • tableau : chaque jour du mois en cours (celui de MAINTENANT), la fiche de LA bande s'il y en a une, le taux de
///     mortalité `mortality_rate` (effectif de début `previousEffectif()`), le poids général reconstitué ;
///   • « Traitements & Prophylaxie » (Lapins, Porcs, Escargots) : [MoisPondeuses.traitementsDuJour] ;
///   • cartes : celles de `getKpisProperty()` de chaque composant, sur toutes les bandes de la fiche.
abstract final class MoisFiche {
  /// Les bandes de la fiche, comme `getLotsProperty()` du web : espèce, statut `actif`, non archivées ; Reproducteurs :
  /// stade différent de `ponte` (un stade NUL est exclu, comme `stage != 'ponte'` en SQL) ; Escargots : aucune tant que
  /// le module Héliciculture n'est pas activé. [toutes] : `bandesActives()` du dépôt (non archivées, par code).
  static List<LivestockLot> bandesDe(
    EspeceFiche espece,
    List<LivestockLot> toutes, {
    bool helicoActif = true,
  }) {
    if (espece == EspeceFiche.escargots && !helicoActif) return const [];
    return [
      for (final b in toutes)
        if (b.isActive &&
            b.speciesCode == espece.codeEspece &&
            (b.status == null || b.status == 'actif') &&
            (espece != EspeceFiche.reproducteurs || (b.stage != null && b.stage != 'ponte')))
          b,
    ];
  }

  /// 🔴→✅ Ticket EX8 (EF12) — [maintenant] est un jour du MOIS AFFICHÉ (le jour choisi, `AvecMoisDeFiche` du web) :
  /// tableau, cartes du mois, soins du mois et PDF le suivent ; seul son mois compte. Avant EX8 : toujours le mois de
  /// l'horloge.
  static Future<DonneesMoisFiche> charger(
    AppDatabase db, {
    required EspeceFiche espece,
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
    // La fiche Reproducteurs n'a pas de colonne « Traitements » (pas d'`AvecSoinsDuMois` au web).
    final avecSoins = espece != EspeceFiche.reproducteurs;
    final produits = avecSoins ? await db.select(db.products).get() : const <Product>[];
    final soins = bande == null || !avecSoins
        ? const <VeterinaryRecord>[]
        : [
            for (final s in await db.select(db.veterinaryRecords).get())
              if (s.lotId == bande.id && s.isActive && duMois(s.recordDate)) s,
          ];
    final nomProduit = {for (final p in produits) p.id: p.name};

    final ficheDu = {
      for (final f in fiches)
        if (bande != null && f.lotId == bande.id && duMois(f.entryDate))
          JournalStocks.jour(f.entryDate): f,
    };

    final jours = [
      for (var j = 1; j <= DateTime(maintenant.year, maintenant.month + 1, 0).day; j++)
        () {
          final jour = DateTime(maintenant.year, maintenant.month, j);
          final fiche = ficheDu[jour];
          return JourFiche(
            jour: jour,
            fiche: fiche,
            effectifDebut: fiche == null ? null : effectifPrecedentDe(fiche, fiches, bandes),
            traitements: avecSoins
                ? MoisPondeuses.traitementsDuJour(
                    jour,
                    fiche,
                    soins,
                    fiche?.treatmentProductId == null ? null : nomProduit[fiche!.treatmentProductId],
                  )
                : '',
          );
        }(),
    ];

    return DonneesMoisFiche(
      indicateurs: indicateurs(espece, bandes: bandes, fiches: fiches, maintenant: maintenant),
      jours: jours,
      document: document(espece, jours, maintenant),
      fiches: fiches,
    );
  }

  /// `getKpisProperty()` de chaque composant, formule pour formule, valeurs mises en forme comme le Blade :
  ///   • Lapins : Effectif Total Vivant · Géniteurs (M/F) · Naissances du Mois · Taux de Mortalité ;
  ///   • Porcs : Effectif Porcins Vivants · Truies Gestantes / Verrats · Porcelets sous Mère · Taux de Mortalité ;
  ///   • Reproducteurs : Effectif Total Vivant · Taux d'Éclosion Couvoir · Poussins Nés (Éclosion) · Taux de
  ///     Mortalité ;
  ///   • Escargots : Effectif Total Vivant · Naissains Nés (mois) · Taux d'Éclosion Naissains · Taux de Mortalité.
  ///
  /// Effectif = `number_format(Σ current_quantity)` ; taux de mortalité du MOIS = morts ÷ Σ des effectifs de début de
  /// chaque fiche du mois ; géniteurs, truies, verrats, porcelets = Σ des effectifs saisis de la DERNIÈRE fiche de
  /// chaque bande (toutes dates) ; taux d'éclosion du mois = nés ÷ œufs, « — » sans œuf (🔴→✅ U12a : le web affichait
  /// 85,0 % (Reproducteurs, valeur de démonstration) ou 0,0 % (Escargots) sans un seul œuf).
  static List<String> indicateurs(
    EspeceFiche espece, {
    required List<LivestockLot> bandes,
    required List<LivestockDailyEntry> fiches,
    required DateTime maintenant,
  }) {
    final debutMois = DateTime(maintenant.year, maintenant.month);
    final finMois = DateTime(maintenant.year, maintenant.month + 1);
    final ids = {for (final b in bandes) b.id};
    final desBandes = [for (final f in fiches) if (ids.contains(f.lotId)) f];
    final duMois = [
      for (final f in desBandes)
        if (!f.entryDate.isBefore(debutMois) && f.entryDate.isBefore(finMois)) f,
    ];

    final morts = duMois.fold<int>(0, (t, f) => t + f.mort);
    final departs = duMois.fold<int>(0, (t, f) => t + effectifPrecedentDe(f, desBandes, bandes));
    final mortalite = departs > 0 ? PmpService.arrondi(morts / departs * 100, 1) : 0.0;
    final effectif = PmpService.francs(
      bandes.fold<int>(0, (t, b) => t + b.currentQuantity).toDouble(),
    );
    final nes = duMois.fold<int>(0, (t, f) => t + f.ne);
    final oeufs = duMois.fold<int>(0, (t, f) => t + (f.ponteTotal ?? 0));
    String pourcent(double x) => '${PmpService.nombre(x, 1)} %';
    final eclosion = oeufs > 0 ? pourcent(PmpService.arrondi(nes / oeufs * 100, 1)) : '—';

    // `orderBy('entry_date')->get()->groupBy('lot_id')->map(fn ($g) => $g->last())`.
    final derniere = <String, LivestockDailyEntry>{};
    for (final f in desBandes) {
      final d = derniere[f.lotId];
      if (d == null || !f.entryDate.isBefore(d.entryDate)) derniere[f.lotId] = f;
    }
    int somme(int? Function(LivestockDailyEntry) champ) =>
        derniere.values.fold<int>(0, (t, f) => t + (champ(f) ?? 0));

    return switch (espece) {
      EspeceFiche.lapins => [
        effectif,
        '${somme((f) => f.effectifM)} / ${somme((f) => f.effectifF)}',
        '$nes',
        pourcent(mortalite),
      ],
      EspeceFiche.porcs => [
        effectif,
        '${somme((f) => f.effectifF)} Truies / ${somme((f) => f.effectifM)} Verrats',
        '${somme((f) => f.effectifSevres)}',
        pourcent(mortalite),
      ],
      EspeceFiche.reproducteurs => [effectif, eclosion, '$nes', pourcent(mortalite)],
      EspeceFiche.escargots => [effectif, '$nes', eclosion, pourcent(mortalite)],
    };
  }

  static const _mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre',
    'décembre',
  ];

  /// « Exporter PDF » — `exportFichePdf()` : gabarit PARTAGÉ `exports.fiche-elevage`, titre de la fiche, sous-titre
  /// `now()->translatedFormat('F Y')`, les fiches du mois de la bande par date, huit colonnes ; « Aucune saisie ce
  /// mois-ci. » sans fiche ; fichier `fiche-AAAA-MM.pdf`.
  static DocumentOfficiel document(EspeceFiche espece, List<JourFiche> jours, DateTime maintenant) {
    String deux(int n) => n.toString().padLeft(2, '0');
    final saisis = [for (final j in jours) if (j.fiche != null) j];
    return DocumentOfficiel(
      titre: espece.titrePdf,
      sousTitre: '${_mois[maintenant.month - 1]} ${maintenant.year}',
      // Ticket EX8 (EF12) : le mois AFFICHÉ (`fichierDuPdf()` du web), jamais celui de l'horloge à l'édition.
      fichier: 'fiche-${maintenant.year}-${deux(maintenant.month)}.pdf',
      entetes: const ['Date', 'Achat', 'Nés', 'Morts', 'Ventes', 'Dons', 'Effectif Final', 'Mortalité'],
      lignes: [
        if (saisis.isEmpty) const DonneesDocument(['Aucune saisie ce mois-ci.']),
        for (final j in saisis)
          DonneesDocument([
            '${deux(j.jour.day)}/${deux(j.jour.month)}/${j.jour.year}',
            '${j.fiche!.achat}',
            '${j.fiche!.ne}',
            '${j.fiche!.mort}',
            '${j.fiche!.vente}',
            '${j.fiche!.don}',
            '${j.fiche!.effectifFinal}',
            '${PmpService.nombre(j.tauxMortalite!, 1)}%',
          ]),
      ],
    );
  }
}
