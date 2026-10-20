import '../../core/database/app_database.dart';
import '../../core/export/document_officiel.dart';
import 'mention_anouveaux.dart';
import 'soldes_exercice.dart';

/// Ticket EX8 (EF11, décision Q5 du client du 20/10/2026) — BILAN ET COMPTE DE RÉSULTAT N / N-1 AU POSTE, en
/// consultation.
///
/// Transposition de `FinancialReportService::bilan / compteResultat / bilanComparatif / compteResultatComparatif /
/// exercicesComparatif / arreteDeLExercice` (Laravel) et de la présentation des onglets « Bilan » et « Compte de
/// Résultat » de `etats-financiers.blade.php` (et de leur PDF, `exports/etats-financiers.blade.php`), prouvée par une
/// parité EXÉCUTÉE contre le PHP (`test/comparatif_n_moins_un_parite_test.dart` : chiffres, et lignes RENDUES par le
/// Blade, libellé pour libellé).
///
///  - colonne « Exercice N » : l'exercice de la date d'arrêté ; colonne « Exercice N-1 » : l'exercice enregistré
///    précédent, à sa clôture ; « — » quand il n'existe pas, JAMAIS 0 (un 0 dirait « rien ce jour-là ») ;
///  - les soldes sont ceux de la règle R1 ([SoldesExercice.soldes]), SANS l'écriture de solde des comptes de gestion
///    (`closing`, étape 2 de la clôture) : lue telle quelle, elle ramènerait le Compte de résultat d'un exercice clos à
///    0 et déplacerait son résultat au 131 (point relevé par EX1).
///
/// ⚠️ Un compte absent du plan reçu au poste n'a pas de classe : il n'entre dans aucune rubrique (au serveur, la
/// jointure sur le plan donne toujours sa classe) — même écart assumé que [SoldesExercice].
abstract final class EtatsComparatifs {
  // ── Calculs (FinancialReportService) ────────────────────────────────────

  /// `lignesDeSoldes()` : une ligne par compte (solde arrondi au centime), plus la ligne de résultat provisoire (classe
  /// 1, marquée) ; tri STABLE par code — la ligne provisoire suit le compte réel du même numéro.
  static List<LigneSolde> lignesDeSoldes(SoldesR1 soldes) {
    final lignes = <LigneSolde>[
      for (final c in soldes.comptes.values)
        LigneSolde(code: c.code, libelle: c.libelle, classe: c.classe, solde: SoldesExercice.arrondi(c.net)),
      if (soldes.resultatProvisoire != null)
        LigneSolde(
          code: soldes.resultatProvisoire!.code,
          libelle: soldes.resultatProvisoire!.libelle,
          classe: 1,
          solde: soldes.resultatProvisoire!.net,
          provisoire: true,
        ),
    ];
    final rang = {for (var i = 0; i < lignes.length; i++) lignes[i]: i};
    lignes.sort((a, b) {
      final c = a.code.compareTo(b.code);
      return c != 0 ? c : rang[a]!.compareTo(rang[b]!);
    });
    return lignes;
  }

  /// `bilan($asOfDate)` : soldes R1 à [arrete], écriture de solde des comptes de gestion écartée.
  static BilanEtat bilan(SoldesExercice s, DateTime arrete) =>
      _bilanDepuis(s.soldes(arrete, horsSoldeGestion: true));

  static BilanEtat _bilanDepuis(SoldesR1 soldes) {
    final lignes = lignesDeSoldes(soldes);
    List<LigneSolde> deClasse(int c) => [for (final l in lignes) if (l.classe == c) l];
    double somme(Iterable<LigneSolde> ls) => ls.fold<double>(0, (t, l) => t + l.solde);

    final immo = deClasse(2);
    final stocks = deClasse(3);
    final tresorerie = deClasse(5);
    final tiers = deClasse(4);
    final capitaux = deClasse(1);
    final charges = deClasse(6);
    final produits = deClasse(7);
    final creances = [for (final l in tiers) if (l.solde > 0) l];
    final dettes = [
      for (final l in tiers)
        if (l.solde < 0) LigneSolde(code: l.code, libelle: l.libelle, classe: 4, solde: -l.solde),
    ];

    final totalImmo = somme(immo);
    final totalStocks = somme(stocks);
    final totalCreances = somme(creances);
    final totalTresorerie = somme(tresorerie);
    final totalCirculant = totalStocks + totalCreances;
    final totalCapitaux = -somme(capitaux);
    final resultat = SoldesExercice.arrondi(-somme(produits) - somme(charges));
    final totalDettes = somme(dettes);
    final totalActif = SoldesExercice.arrondi(totalImmo + totalCirculant + totalTresorerie);
    final totalPassif = SoldesExercice.arrondi(totalCapitaux + resultat + totalDettes);

    return BilanEtat(
      immo: immo,
      stocks: stocks,
      creances: creances,
      tresorerie: tresorerie,
      capitaux: capitaux,
      dettes: dettes,
      totalImmo: totalImmo,
      totalCirculant: totalCirculant,
      totalTresorerie: totalTresorerie,
      totalActif: totalActif,
      totalCapitaux: totalCapitaux,
      resultat: resultat,
      totalDettes: totalDettes,
      totalPassif: totalPassif,
      ouverture: soldes.ouverture,
    );
  }

  /// `compteResultat($asOfDate)` : la cascade SYSCOHADA, classes 6 et 7 de l'exercice, écriture de solde écartée ; la
  /// ligne « autres charges » ABSORBE tout compte de classe 6 non classé ailleurs (Résultat Net = produits − charges).
  static CompteResultatEtat compteResultat(SoldesExercice s, DateTime arrete) {
    final lignes = lignesDeSoldes(s.soldes(arrete, horsSoldeGestion: true));
    bool prefixe(String code, List<String> p) => p.any(code.startsWith);
    double charges(List<String> p) => SoldesExercice.arrondi(
      lignes.fold<double>(0, (t, l) => t + (l.classe == 6 && prefixe(l.code, p) ? l.solde : 0)),
    );
    double produits(List<String> p) => SoldesExercice.arrondi(
      -lignes.fold<double>(0, (t, l) => t + (l.classe == 7 && prefixe(l.code, p) ? l.solde : 0)),
    );
    final totalCharges = SoldesExercice.arrondi(
      lignes.fold<double>(0, (t, l) => t + (l.classe == 6 ? l.solde : 0)),
    );
    final totalProduits = SoldesExercice.arrondi(
      -lignes.fold<double>(0, (t, l) => t + (l.classe == 7 ? l.solde : 0)),
    );

    final achats = charges(['60']);
    final personnel = charges(['66']);
    final dotations = charges(['68']);
    final chargesFinancieres = charges(['67']);
    final produitsFinanciers = produits(['77']);
    final ventes = SoldesExercice.arrondi(totalProduits - produitsFinanciers);
    final autresCharges = SoldesExercice.arrondi(
      totalCharges - achats - personnel - dotations - chargesFinancieres,
    );
    final marge = SoldesExercice.arrondi(ventes - achats);
    final ebe = SoldesExercice.arrondi(marge - personnel);
    final exploitation = SoldesExercice.arrondi(ebe - dotations);
    final financier = SoldesExercice.arrondi(produitsFinanciers - chargesFinancieres);
    final rao = SoldesExercice.arrondi(exploitation + financier);

    return CompteResultatEtat(
      ventes: ventes,
      achats: achats,
      margeCommerciale: marge,
      chargesPersonnel: personnel,
      ebe: ebe,
      dotations: dotations,
      resultatExploitation: exploitation,
      resultatFinancier: financier,
      rao: rao,
      autresCharges: autresCharges,
      resultatNet: SoldesExercice.arrondi(rao - autresCharges),
    );
  }

  /// `exercicesComparatif($asOfDate)` : N = l'exercice de [arrete] ; N-1 = l'exercice ENREGISTRÉ qui couvre la veille
  /// du premier jour de N, présenté à sa clôture, ou `null`.
  static ({ColonneExercice n, ColonneExercice? n1}) exercices(SoldesExercice s, DateTime arrete) {
    final jourArrete = DateTime(arrete.year, arrete.month, arrete.day);
    final n = s.exerciceDe(SoldesExercice.jour(jourArrete));
    final debut = _date(n.debut);
    final precedent = s.exerciceDe(SoldesExercice.jour(DateTime(debut.year, debut.month, debut.day - 1)));
    return (
      n: ColonneExercice(annee: n.annee, arrete: jourArrete),
      n1: precedent.reel
          ? ColonneExercice(annee: precedent.annee, arrete: _date(precedent.fin), statut: precedent.statut)
          : null,
    );
  }

  /// `bilanComparatif($asOfDate)` : les deux Bilans et, par rubrique, l'union des comptes des deux colonnes triée par
  /// code (un compte absent d'un exercice EXISTANT y vaut 0 ; sans N-1, `n1` est `null`).
  static BilanComparatif bilanComparatif(SoldesExercice s, DateTime arrete) {
    final ex = exercices(s, arrete);
    final n = bilan(s, ex.n.arrete);
    final n1 = ex.n1 == null ? null : bilan(s, ex.n1!.arrete);

    Map<String, List<LigneComparee>> lignes = {};
    for (final rubrique in BilanEtat.rubriques) {
      final fusion = <String, LigneComparee>{};
      final ordre = <String>[];
      void verser(List<LigneSolde> source, bool colonneN) {
        for (final l in source) {
          final cle = '${l.code}|${l.libelle}|${l.provisoire ? 'p' : ''}';
          final avant = fusion[cle];
          if (avant == null) ordre.add(cle);
          final base = avant ??
              LigneComparee(code: l.code, libelle: l.libelle, provisoire: l.provisoire, n: 0, n1: n1 == null ? null : 0);
          fusion[cle] = colonneN
              ? base.avec(n: SoldesExercice.arrondi(base.n + l.solde))
              : base.avec(n1: SoldesExercice.arrondi((base.n1 ?? 0) + l.solde));
        }
      }

      verser(n.rubrique(rubrique), true);
      if (n1 != null) verser(n1.rubrique(rubrique), false);
      final rang = {for (var i = 0; i < ordre.length; i++) ordre[i]: i};
      final triees = ordre.toList()
        ..sort((a, b) {
          final c = fusion[a]!.code.compareTo(fusion[b]!.code);
          return c != 0 ? c : rang[a]!.compareTo(rang[b]!);
        });
      lignes[rubrique] = [for (final k in triees) fusion[k]!];
    }

    return BilanComparatif(exerciceN: ex.n, exerciceN1: ex.n1, n: n, n1: n1, lignes: lignes);
  }

  /// `compteResultatComparatif($asOfDate)` : la cascade de N à [arrete] et celle de N-1 entier.
  static CompteResultatComparatif compteResultatComparatif(SoldesExercice s, DateTime arrete) {
    final ex = exercices(s, arrete);
    return CompteResultatComparatif(
      exerciceN: ex.n,
      exerciceN1: ex.n1,
      n: compteResultat(s, ex.n.arrete),
      n1: ex.n1 == null ? null : compteResultat(s, ex.n1!.arrete),
    );
  }

  /// `arreteDeLExercice($annee)` : aujourd'hui si l'exercice est en cours, sa clôture s'il est passé, son premier jour
  /// s'il est à venir ; l'exercice enregistré de cette année, à défaut l'année civile. Paramètre explicite de la page
  /// (le sélecteur d'exercice d'EX7 s'y branchera).
  static DateTime arreteDeLExercice(List<FiscalYear> exercices, int annee, DateTime aujourdhui) {
    final e = exercices.where((x) => x.year == annee).firstOrNull;
    final debut = e?.startDate ?? DateTime(annee, 1, 1);
    final fin = e?.endDate ?? DateTime(annee, 12, 31);
    final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
    final d = DateTime(debut.year, debut.month, debut.day);
    final f = DateTime(fin.year, fin.month, fin.day);
    if (jour.isBefore(d)) return d;
    if (jour.isAfter(f)) return f;
    return jour;
  }

  /// Date d'arrêté par défaut des États financiers (`EtatsFinanciers::asOfDate()` sans exercice choisi) : aujourd'hui,
  /// jamais au-delà de la fin de l'exercice ouvert le plus récent ([exerciceOuvert], `FiscalYear::current()`).
  static DateTime arreteParDefaut(FiscalYear? exerciceOuvert, DateTime maintenant) {
    final fin = exerciceOuvert?.endDate;
    // `now()->greaterThan($year->end_date)` : un instant APRÈS le début du dernier jour.
    if (fin != null && maintenant.isAfter(DateTime(fin.year, fin.month, fin.day))) {
      return DateTime(fin.year, fin.month, fin.day);
    }
    return DateTime(maintenant.year, maintenant.month, maintenant.day);
  }

  static DateTime _date(int jour) => DateTime(jour ~/ 10000, jour ~/ 100 % 100, jour % 100);

  // ── Présentation (`etats-financiers.blade.php`, `ComparatifNMoinsUn`) ──

  /// `ComparatifNMoinsUn::ENTETE_N` / `ENTETE_N1` / `SANS_EXERCICE`.
  static const enteteN = 'Exercice N';
  static const enteteN1 = 'Exercice N-1';
  static const sansExercice = 'Aucun exercice antérieur';

  /// `ComparatifNMoinsUn::montant()` : « — » sans exercice, jamais 0 ; sinon arrondi au franc, espace des milliers,
  /// jamais « -0 ».
  static String montant(double? v) {
    if (v == null) return '—';
    final r = v.round();
    final chiffres = r.abs().toString();
    final morceaux = <String>[];
    for (var i = chiffres.length; i > 0; i -= 3) {
      morceaux.insert(0, chiffres.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${r < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  /// Montant suivi de « F » (totaux du Bilan, Résultat Net) ; « — » seul sans exercice.
  static String montantF(double? v) => v == null ? '—' : '${montant(v)} F';

  /// Montant entre parenthèses (charges de la cascade) ; « — » seul sans exercice.
  static String parentheses(double? v) => v == null ? '—' : '(${montant(v)})';

  static String _jj(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// `ComparatifNMoinsUn::sousTitre()` : « 2027 — au 31/01/2027 », ou « Aucun exercice antérieur ».
  static String sousTitre(ColonneExercice? e) => e == null ? sansExercice : '${e.annee} — au ${_jj(e.arrete)}';

  /// `getSituationLabelProperty()` des États financiers : « Situation au 31/01/2027 — Exercice 2027 ».
  static String situation(DateTime arrete, int annee) => 'Situation au ${_jj(arrete)} — Exercice $annee';

  static double? _neg(double? v) => v == null ? null : -v;

  /// Le tableau « Actif (Emplois) » de l'onglet Bilan, ligne pour ligne comme le Blade.
  static List<LigneTableauEtat> tableauActif(BilanComparatif c) {
    final b1 = c.n1;
    String ligne(LigneComparee l) => '${l.code} — ${l.libelle}';
    return [
      const LigneTableauEtat.titre('Actif Immobilisé (Classe 2)'),
      for (final l in c.lignes['immo']!)
        LigneTableauEtat(ligne(l), montant(l.n), montant(l.n1), negatifN: l.n < 0),
      LigneTableauEtat('Sous-total Immobilisé', montant(c.n.totalImmo), montant(b1?.totalImmo),
          genre: GenreLigneEtat.sousTotal),
      const LigneTableauEtat.titre('Actif Circulant (Classes 3 & 4)'),
      for (final l in [...c.lignes['stocks']!, ...c.lignes['creances']!])
        LigneTableauEtat(ligne(l), montant(l.n), montant(l.n1)),
      LigneTableauEtat('Sous-total Circulant', montant(c.n.totalCirculant), montant(b1?.totalCirculant),
          genre: GenreLigneEtat.sousTotal),
      const LigneTableauEtat.titre('Trésorerie Actif (Classe 5)'),
      for (final l in c.lignes['tresorerie']!) LigneTableauEtat(ligne(l), montant(l.n), montant(l.n1)),
      LigneTableauEtat('Sous-total Trésorerie', montant(c.n.totalTresorerie), montant(b1?.totalTresorerie),
          genre: GenreLigneEtat.sousTotal),
      LigneTableauEtat('Total Actif', montantF(c.n.totalActif), montantF(b1?.totalActif),
          genre: GenreLigneEtat.total),
    ];
  }

  /// Le tableau « Passif (Ressources) » de l'onglet Bilan, ligne pour ligne comme le Blade.
  static List<LigneTableauEtat> tableauPassif(BilanComparatif c) {
    final b1 = c.n1;
    String ligne(LigneComparee l) => '${l.code} — ${l.libelle}';
    return [
      const LigneTableauEtat.titre('Capitaux Propres (Classe 1)'),
      for (final l in c.lignes['capitaux']!) LigneTableauEtat(ligne(l), montant(-l.n), montant(_neg(l.n1))),
      LigneTableauEtat("Résultat de l'Exercice", montant(c.n.resultat), montant(b1?.resultat), gras: true),
      LigneTableauEtat(
        'Sous-total Capitaux Propres',
        montant(c.n.totalCapitaux + c.n.resultat),
        montant(b1 == null ? null : b1.totalCapitaux + b1.resultat),
        genre: GenreLigneEtat.sousTotal,
      ),
      const LigneTableauEtat.titre('Dettes (Classe 4)'),
      for (final l in c.lignes['dettes']!) LigneTableauEtat(ligne(l), montant(l.n), montant(l.n1)),
      LigneTableauEtat('Sous-total Dettes', montant(c.n.totalDettes), montant(b1?.totalDettes),
          genre: GenreLigneEtat.sousTotal),
      LigneTableauEtat('Total Passif', montantF(c.n.totalPassif), montantF(b1?.totalPassif),
          genre: GenreLigneEtat.total),
    ];
  }

  /// Le tableau « Compte de Résultat — Structure en Cascade SYSCOHADA », ligne pour ligne comme le Blade.
  static List<LigneTableauEtat> tableauResultat(CompteResultatComparatif c) {
    final n = c.n;
    final r1 = c.n1;
    return [
      LigneTableauEtat('Ventes (Aviculture, Cuniculture, Porciculture)', montant(n.ventes), montant(r1?.ventes)),
      LigneTableauEtat('− Achats (Aliments, Intrants)', parentheses(n.achats), parentheses(r1?.achats), charge: true),
      LigneTableauEtat('= MARGE COMMERCIALE', montant(n.margeCommerciale), montant(r1?.margeCommerciale),
          genre: GenreLigneEtat.sousTotal),
      LigneTableauEtat('− Charges de Personnel', parentheses(n.chargesPersonnel), parentheses(r1?.chargesPersonnel),
          charge: true),
      LigneTableauEtat("= EXCÉDENT BRUT D'EXPLOITATION", montant(n.ebe), montant(r1?.ebe),
          genre: GenreLigneEtat.sousTotal),
      LigneTableauEtat('− Dotations aux Amortissements', parentheses(n.dotations), parentheses(r1?.dotations),
          charge: true),
      LigneTableauEtat("= RÉSULTAT D'EXPLOITATION", montant(n.resultatExploitation), montant(r1?.resultatExploitation),
          genre: GenreLigneEtat.sousTotal),
      LigneTableauEtat('+ Résultat Financier', montant(n.resultatFinancier), montant(r1?.resultatFinancier)),
      LigneTableauEtat('= RÉSULTAT DES ACTIVITÉS ORDINAIRES (RAO)', montant(n.rao), montant(r1?.rao),
          genre: GenreLigneEtat.sousTotal),
      LigneTableauEtat(
        '+ Résultat Hors Activités Ordinaires (charges diverses de gestion)',
        parentheses(n.autresCharges),
        parentheses(r1?.autresCharges),
        charge: true,
      ),
      LigneTableauEtat("= RÉSULTAT NET DE L'EXERCICE", montantF(n.resultatNet), montantF(r1?.resultatNet),
          genre: GenreLigneEtat.total),
    ];
  }

  /// Phrase sous le Compte de résultat (Blade, mot pour mot).
  static const noteResultat =
      "Le Résultat Net de l'Exercice ci-dessus est calculé depuis la même source que celui affiché au Bilan — les "
      'deux valeurs sont toujours strictement identiques.';

  // ── Documents (`exports/etats-financiers.blade.php`, `exportEtatActifPdf`) ──

  static String _entetePdf(String entete, ColonneExercice? e) => '$entete (${sousTitre(e)})';

  /// « Exporter PDF (Onglet Actif) », onglet Bilan : titre, sous-titre (situation, « — À-nouveaux provisoires »),
  /// colonnes et lignes du gabarit web ; `etats-financiers-bilan-AAAA-MM-JJ.pdf`.
  static DocumentOfficiel documentBilan(BilanComparatif c, {required String situation}) {
    final b1 = c.n1;
    String ligne(LigneComparee l) => '${l.code} — ${l.libelle}';
    final ecart = (c.n.totalActif - c.n.totalPassif).abs();
    return DocumentOfficiel(
      titre: 'États Financiers — Bilan',
      sousTitre: situation + (c.n.ouverture.provisoire ? MentionAnouveauxProvisoires.suffixeDocument : ''),
      fichier: 'etats-financiers-bilan-{jour}.pdf',
      entetes: ['Poste', _entetePdf(enteteN, c.exerciceN), _entetePdf(enteteN1, c.exerciceN1)],
      noteDePied: c.n.equilibre ? null : 'Bilan déséquilibré — écart de ${montant(ecart)} FCFA.',
      lignes: [
        const BandeDocument('ACTIF — Immobilisé (Classe 2)'),
        for (final l in c.lignes['immo']!) DonneesDocument([ligne(l), montant(l.n), montant(l.n1)]),
        const BandeDocument('ACTIF — Circulant (Classes 3 & 4)'),
        for (final l in [...c.lignes['stocks']!, ...c.lignes['creances']!])
          DonneesDocument([ligne(l), montant(l.n), montant(l.n1)]),
        const BandeDocument('ACTIF — Trésorerie (Classe 5)'),
        for (final l in c.lignes['tresorerie']!) DonneesDocument([ligne(l), montant(l.n), montant(l.n1)]),
        TotalDocument(['TOTAL ACTIF', montant(c.n.totalActif), montant(b1?.totalActif)]),
        const BandeDocument('PASSIF — Capitaux Propres (Classe 1)'),
        for (final l in c.lignes['capitaux']!) DonneesDocument([ligne(l), montant(-l.n), montant(_neg(l.n1))]),
        DonneesDocument(["Résultat de l'Exercice", montant(c.n.resultat), montant(b1?.resultat)]),
        const BandeDocument('PASSIF — Dettes (Classe 4)'),
        for (final l in c.lignes['dettes']!) DonneesDocument([ligne(l), montant(l.n), montant(l.n1)]),
        TotalDocument(['TOTAL PASSIF', montant(c.n.totalPassif), montant(b1?.totalPassif)]),
      ],
    );
  }

  /// La cascade du PDF (`$cascade` du gabarit web) : libellé, clé, entre parenthèses, en gras.
  static const cascadePdf = <(String, String, bool, bool)>[
    ('Ventes', 'ventes', false, false),
    ('− Achats', 'achats', true, false),
    ('= MARGE COMMERCIALE', 'marge_commerciale', false, true),
    ('− Charges de Personnel', 'charges_personnel', true, false),
    ("= EXCÉDENT BRUT D'EXPLOITATION", 'ebe', false, true),
    ('− Dotations aux Amortissements', 'dotations', true, false),
    ("= RÉSULTAT D'EXPLOITATION", 'resultat_exploitation', false, true),
    ('+ Résultat Financier', 'resultat_financier', false, false),
    ('= RÉSULTAT DES ACTIVITÉS ORDINAIRES (RAO)', 'rao', false, true),
    ('+ Résultat Hors Activités Ordinaires', 'autres_charges', true, false),
    ("= RÉSULTAT NET DE L'EXERCICE", 'resultat_net', false, true),
  ];

  /// « Exporter PDF (Onglet Actif) », onglet Compte de Résultat.
  static DocumentOfficiel documentResultat(
    CompteResultatComparatif c, {
    required String situation,
    required bool provisoire,
  }) => DocumentOfficiel(
    titre: 'États Financiers — Compte de Résultat',
    sousTitre: situation + (provisoire ? MentionAnouveauxProvisoires.suffixeDocument : ''),
    fichier: 'etats-financiers-resultat-{jour}.pdf',
    entetes: [
      'Compte de Résultat — Cascade SYSCOHADA',
      _entetePdf(enteteN, c.exerciceN),
      _entetePdf(enteteN1, c.exerciceN1),
    ],
    lignes: [
      for (final (libelle, cle, entreParentheses, gras) in cascadePdf)
        () {
          final f = entreParentheses ? parentheses : montant;
          final cellules = [libelle, f(c.n.valeur(cle)), f(c.n1?.valeur(cle))];
          return gras ? TotalDocument(cellules) : DonneesDocument(cellules);
        }(),
    ],
  );
}

/// Une ligne de `lignesDeSoldes()` : solde NET (débit − crédit), arrondi au centime.
class LigneSolde {
  const LigneSolde({
    required this.code,
    required this.libelle,
    required this.classe,
    required this.solde,
    this.provisoire = false,
  });

  final String code;
  final String libelle;
  final int? classe;
  final double solde;
  final bool provisoire;
}

/// `bilan()` du serveur.
class BilanEtat {
  const BilanEtat({
    required this.immo,
    required this.stocks,
    required this.creances,
    required this.tresorerie,
    required this.capitaux,
    required this.dettes,
    required this.totalImmo,
    required this.totalCirculant,
    required this.totalTresorerie,
    required this.totalActif,
    required this.totalCapitaux,
    required this.resultat,
    required this.totalDettes,
    required this.totalPassif,
    required this.ouverture,
  });

  static const rubriques = ['immo', 'stocks', 'creances', 'tresorerie', 'capitaux', 'dettes'];

  final List<LigneSolde> immo;
  final List<LigneSolde> stocks;
  final List<LigneSolde> creances;
  final List<LigneSolde> tresorerie;
  final List<LigneSolde> capitaux;

  /// Soldes CRÉDITEURS de la classe 4, en positif.
  final List<LigneSolde> dettes;
  final double totalImmo;
  final double totalCirculant;
  final double totalTresorerie;
  final double totalActif;
  final double totalCapitaux;
  final double resultat;
  final double totalDettes;
  final double totalPassif;
  final OuvertureExercice ouverture;

  /// `is_balanced` : |actif − passif| < 0,01.
  bool get equilibre => (totalActif - totalPassif).abs() < 0.01;

  List<LigneSolde> rubrique(String nom) => switch (nom) {
    'immo' => immo,
    'stocks' => stocks,
    'creances' => creances,
    'tresorerie' => tresorerie,
    'capitaux' => capitaux,
    'dettes' => dettes,
    _ => throw ArgumentError(nom),
  };
}

/// `compteResultat()` du serveur.
class CompteResultatEtat {
  const CompteResultatEtat({
    required this.ventes,
    required this.achats,
    required this.margeCommerciale,
    required this.chargesPersonnel,
    required this.ebe,
    required this.dotations,
    required this.resultatExploitation,
    required this.resultatFinancier,
    required this.rao,
    required this.autresCharges,
    required this.resultatNet,
  });

  final double ventes;
  final double achats;
  final double margeCommerciale;
  final double chargesPersonnel;
  final double ebe;
  final double dotations;
  final double resultatExploitation;
  final double resultatFinancier;
  final double rao;
  final double autresCharges;
  final double resultatNet;

  /// Valeur par la clé du serveur (`ventes`, `marge_commerciale`…).
  double valeur(String cle) => switch (cle) {
    'ventes' => ventes,
    'achats' => achats,
    'marge_commerciale' => margeCommerciale,
    'charges_personnel' => chargesPersonnel,
    'ebe' => ebe,
    'dotations' => dotations,
    'resultat_exploitation' => resultatExploitation,
    'resultat_financier' => resultatFinancier,
    'rao' => rao,
    'autres_charges' => autresCharges,
    'resultat_net' => resultatNet,
    _ => throw ArgumentError(cle),
  };
}

/// Une colonne du comparatif : l'année et la date d'arrêté (N : la date choisie ; N-1 : sa clôture).
class ColonneExercice {
  const ColonneExercice({required this.annee, required this.arrete, this.statut});

  final int annee;
  final DateTime arrete;
  final String? statut;
}

/// Une ligne fusionnée du Bilan N / N-1 : solde N, solde N-1 (`null` sans exercice N-1).
class LigneComparee {
  const LigneComparee({
    required this.code,
    required this.libelle,
    required this.provisoire,
    required this.n,
    required this.n1,
  });

  final String code;
  final String libelle;
  final bool provisoire;
  final double n;
  final double? n1;

  LigneComparee avec({double? n, double? n1}) =>
      LigneComparee(code: code, libelle: libelle, provisoire: provisoire, n: n ?? this.n, n1: n1 ?? this.n1);
}

class BilanComparatif {
  const BilanComparatif({
    required this.exerciceN,
    required this.exerciceN1,
    required this.n,
    required this.n1,
    required this.lignes,
  });

  final ColonneExercice exerciceN;
  final ColonneExercice? exerciceN1;
  final BilanEtat n;
  final BilanEtat? n1;
  final Map<String, List<LigneComparee>> lignes;
}

class CompteResultatComparatif {
  const CompteResultatComparatif({
    required this.exerciceN,
    required this.exerciceN1,
    required this.n,
    required this.n1,
  });

  final ColonneExercice exerciceN;
  final ColonneExercice? exerciceN1;
  final CompteResultatEtat n;
  final CompteResultatEtat? n1;
}

enum GenreLigneEtat { titre, ligne, sousTotal, total }

/// Une ligne AFFICHÉE d'un tableau d'état : libellé et les deux montants déjà mis en forme (« — » sans N-1).
class LigneTableauEtat {
  const LigneTableauEtat(
    this.libelle,
    this.n,
    this.n1, {
    this.genre = GenreLigneEtat.ligne,
    this.gras = false,
    this.charge = false,
    this.negatifN = false,
  });

  /// Titre de rubrique (une cellule sur toute la largeur).
  const LigneTableauEtat.titre(this.libelle)
    : n = '',
      n1 = '',
      genre = GenreLigneEtat.titre,
      gras = true,
      charge = false,
      negatifN = false;

  final String libelle;
  final String n;
  final String n1;
  final GenreLigneEtat genre;
  final bool gras;

  /// Charge de la cascade (montant entre parenthèses, en rouge).
  final bool charge;

  /// Solde négatif en colonne N (en rouge, comme `text-error-deep` du Blade).
  final bool negatifN;

  /// Cellules comme le Blade les rend (`textContent` de chaque `<td>`) : le titre seul, sinon les trois.
  List<String> get cellules => genre == GenreLigneEtat.titre ? [libelle] : [libelle, n, n1];
}
