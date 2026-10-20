import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/export/document_officiel.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/tableau_mensuel.dart';
import '../../core/widgets/toast_agri.dart';
import '../../core/comptabilite/exercice_de_saisie.dart';
import '../stocks/journal_stocks.dart';
import '../stocks/pmp_service.dart';
import 'effectif_par_categorie.dart';
import 'elements_fiche.dart';
import 'fiche_journaliere_repository.dart';
import 'jour_categories.dart';
import 'mois_fiche.dart';
import 'soins_repository.dart';

/// Ce qui distingue, au web, `fiche-lapins.blade.php` de `fiche-porcs.blade.php` : les deux vues ont la MÊME
/// structure (ticket 15.42 = miroir de 15.41), seuls l'espèce, les libellés, l'ordre des catégories et l'unité de la
/// pesée changent. Chaque écran (`FicheLapinsScreen`, `FichePorcsScreen`) porte sa configuration, mot pour mot.
class ConfigFicheCategories {
  const ConfigFicheCategories({
    required this.espece,
    required this.especeChaine,
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.cartes,
    required this.aucuneBande,
    required this.toastAucuneBande,
    required this.titreSaisie,
    required this.libelleNes,
    required this.categoriesMorts,
    required this.categoriesDons,
    required this.libellePassage,
    this.suffixePassage,
    required this.categoriesDepart,
    required this.texteAncien,
    required this.libellesEffectifs,
    required this.titreRationnement,
    required this.enteteRation,
    required this.libellesRation,
    required this.infobullesRation,
    required this.rationAffichee,
    required this.ligneRationMiseEnAvant,
    required this.filiere,
    required this.peseeEnKg,
    required this.titreTraitements,
    required this.libelleObservations,
    required this.indiceObservations,
    required this.ventilation,
    required this.colonnesEffectif,
    required this.libellePoids,
  });

  final EspeceFiche espece;

  /// `EffectifParCategorie.lapins` / `.porcs` (`EffectifParCategorieService::LAPINS` / `PORCS`).
  final String especeChaine;

  final IconData icone;
  final String titre;
  final String sousTitre;

  /// Les quatre `x-kpi-card` (libellé, icône, variante), valeurs de [MoisFiche.indicateurs].
  final List<(String, IconData, Color)> cartes;
  final String aucuneBande;
  final String toastAucuneBande;
  final String titreSaisie;
  final String libelleNes;

  /// `(emplacement, libellé)` dans l'ordre du Blade ; emplacements `repro`, `sevre`, `jeune`.
  final List<(String, String)> categoriesMorts;
  final List<(String, String)> categoriesDons;
  final String libellePassage;
  final String? suffixePassage;
  final List<(String, String)> categoriesDepart;

  /// Fin de la phrase D6 : « Reproducteur 3, Jeune 10, Sous-mères 4 ».
  final String Function(EffectifCategories) texteAncien;

  /// Libellés des quatre effectifs saisis, dans l'ordre `effectif_m`, `effectif_f`, `effectif_sevres`,
  /// `effectif_smeres`.
  final List<String> libellesEffectifs;
  final String titreRationnement;
  final String enteteRation;
  final Map<String, String> libellesRation;

  /// Ticket U14 — `title="Calculé automatiquement : …"` du champ grisé de l'effectif de chaque ligne du rationnement
  /// (Blade), par catégorie.
  final Map<String, String> infobullesRation;
  final String Function(LigneProvende) rationAffichee;

  /// Ligne du rationnement à la ration en vert gras (`text-brand-emerald font-bold`) — Jeune / Reproducteur.
  final String ligneRationMiseEnAvant;
  final String filiere;
  final bool peseeEnKg;
  final String titreTraitements;
  final String libelleObservations;
  final String indiceObservations;

  /// « (Reproducteur / Jeune / Sous-mères) » du toast de la fiche ancienne non ventilée.
  final String ventilation;

  /// Sous-colonnes « Effectif Final du Jour » du tableau du mois (avant « Total »).
  final List<String> colonnesEffectif;
  final String libellePoids;
}

/// 🔴→✅ Ticket U12a — LES FICHES LAPINS ET PORCS DU POSTE, MISES EN PAGE COMME LEUR BLADE (doctrine, article 5).
///
/// Sections dans l'ordre de `fiche-lapins.blade.php` / `fiche-porcs.blade.php` :
///   1. en-tête (titre, sous-titre, « Exporter PDF ») ; 2. quatre cartes du MOIS (`getKpisProperty()`) ;
///   3. sans bande : la carte « Aucune bande active en … pour le moment. » ;
///   4. carte de saisie : titre, « Bande : » (plusieurs bandes), « Date : » ; transferts du jour ; mention D6 ;
///      Achats du jour · Nés · Ventes (POS, réel) ; Morts par catégorie ; Dons par catégorie ; sevrage / passage de
///      stade ; effectif de départ par catégorie (pré-rempli du stade, corrigeable, puis verrouillé) ; motifs,
///      refus, avertissements ; quatre effectifs saisis ; effectif final et taux de mortalité ; rationnement ;
///      autonomie alimentaire ; pesée ; Traitements & Prophylaxie / Suivi Clinique & Prophylaxie (protocole du
///      jour, observations) ; « Enregistrer ce Jour » ;
///   5. le tableau du mois (TOUS les jours, `hidden lg:block`).
///
/// Retirés avec la maquette : « Réinitialiser », « Attribution Cages & Bandes » / « Logettes & Porcheries »,
/// « Jour N » du titre de saisie et des lignes du tableau, « Alimenté par la caisse », les toasts du poste
/// (« Journée enregistrée sur ce poste… », « Jour enregistré. »).
class FicheCategoriesVue extends StatefulWidget {
  const FicheCategoriesVue({
    super.key,
    required this.config,
    required this.depot,
    required this.soins,
    this.imprimer,
    this.onOuvrirTransferts,
    this.onCommanderStock,
    this.maintenant,
  });

  final ConfigFicheCategories config;
  final FicheJournaliereRepository depot;
  final SoinsRepository soins;

  /// « Exporter PDF » — `EditeursRapports.imprimer` en production, un espion en test ; `null` : bouton inerte.
  final Future<String?> Function(DocumentOfficiel document, DateTime maintenant)? imprimer;

  /// Lien « Transferts entre Bandes » des transferts du jour (`/transferts-bandes` au web).
  final VoidCallback? onOuvrirTransferts;

  /// Bouton « Commander Stock » de l'alerte d'autonomie (`/achats-commandes` au web).
  final VoidCallback? onCommanderStock;

  /// Horloge injectable : le mois du tableau et des cartes est celui de MAINTENANT (`now()` du web).
  final DateTime Function()? maintenant;

  @override
  State<FicheCategoriesVue> createState() => _FicheCategoriesVueState();
}

class _FicheCategoriesVueState extends State<FicheCategoriesVue> {
  ConfigFicheCategories get _c => widget.config;

  List<LivestockLot> _bandes = const [];
  LivestockLot? _bande;
  late DateTime _jour;
  bool _chargement = true;

  DonneesMoisFiche? _mois;

  /// Ticket EX8 (EF12) — motif R4 de la lecture seule (exercice clos), `null` quand le jour se saisit.
  LectureSeuleDuJour? _lectureSeule;
  List<FeedRationStandard> _rations = const [];
  Product? _produitProvende;
  double? _stockProvendeKg;

  int _precedent = 0;
  EtatJour? _etat;
  LivestockDailyEntry? _fiche;

  int _achat = 0;
  int _ne = 0;
  final _morts = <String, int>{'repro': 0, 'sevre': 0, 'jeune': 0};
  final _dons = <String, int>{'repro': 0, 'sevre': 0, 'jeune': 0};
  int _passage = 0;
  final _depart = <String, int?>{'repro': null, 'sevre': null, 'jeune': null};
  int? _mortAncien;
  int? _donAncien;

  /// `effectif_m`, `effectif_f`, `effectif_sevres`, `effectif_smeres` — saisis (décision client QC5).
  final _effectifs = <int>[0, 0, 0, 0];

  /// Pesée TOTALE : grammes (lapins) ou kilos (porcs) ; `null` = rien de pesé.
  double? _pesee;

  ProtocoleDuJour? _protocole;
  final _coches = <String>{};
  final _observations = TextEditingController();
  bool _validationEnCours = false;

  // S-T11 : le jour métier est celui du Bénin, quel que soit le réglage de Windows.
  DateTime get _maintenant => (widget.maintenant ?? HeureBenin.maintenant)();

  @override
  void initState() {
    super.initState();
    final m = _maintenant;
    _jour = DateTime(m.year, m.month, m.day);
    _initialiser();
  }

  @override
  void dispose() {
    _observations.dispose();
    super.dispose();
  }

  Future<void> _initialiser() async {
    final db = widget.depot.database;
    final bandes = MoisFiche.bandesDe(_c.espece, await widget.depot.bandesActives());
    final rations = await widget.depot.rations(_c.espece.codeEspece);
    final produits = await db.select(db.products).get();
    final especes = await db.select(db.livestockSpecies).get();
    final types = await db.select(db.feedTypes).get();
    final produit = AutonomieAlimentaire.produitProvende(_c.espece.codeEspece, produits, especes);
    if (!mounted) return;
    setState(() {
      _bandes = bandes;
      _bande = bandes.isEmpty ? null : bandes.first;
      _rations = rations;
      _produitProvende = produit;
      _stockProvendeKg = produit == null ? null : AutonomieAlimentaire.stockEnKg(produit, types);
    });
    await _chargerJour();
  }

  /// `loadDay()` du web : la fiche de LA bande à CETTE date, quel que soit le mois ; mouvements par catégorie
  /// relus, fiche ancienne non ventilée signalée, départ pré-rempli depuis le stade tant que la bande n'a pas de
  /// chaîne, pesée totale reconstituée, cases de prophylaxie décochées.
  Future<void> _chargerJour() async {
    final bande = _bande;
    // Ticket EX8 (EF12) : le mois AFFICHÉ est celui du jour choisi (`AvecMoisDeFiche` du web).
    final mois = await MoisFiche.charger(
      widget.depot.database,
      espece: _c.espece,
      bandes: _bandes,
      bande: bande,
      maintenant: _jour,
    );
    // Ticket EX8 (EF12) : un jour d'un exercice CLOS se consulte en lecture seule ; fusion EX7 + EX8 : bandeau d'EX7.
    final lectureSeule = await LectureSeuleDuJour.charger(widget.depot.database, _jour, maintenant: _maintenant);
    if (bande == null) {
      if (!mounted) return;
      setState(() {
        _mois = mois;
        _lectureSeule = lectureSeule;
        _chargement = false;
      });
      return;
    }
    final precedent = await widget.depot.effectifPrecedent(bande.id, _jour);
    final etat = await widget.depot.etatCategories(bande.id, _jour);
    final fiche = await widget.depot.chargerJour(bande.id, _jour);
    final protocole = await widget.soins.protocoleDuJour(
      bande: bande,
      codeEspece: _c.espece.codeEspece,
      quand: _jour,
    );
    if (!mounted) return;

    setState(() {
      _mois = mois;
      _lectureSeule = lectureSeule;
      _precedent = precedent;
      _etat = etat;
      _fiche = fiche;
      _protocole = protocole;
      _coches.clear();
      // `preremplirDepartDepuisStade()` : seulement sans tête de chaîne.
      final depart = etat?.mode == 'sans_chaine'
          ? EffectifParCategorie.departDepuisStade(
              codeEspece: bande.speciesCode,
              stade: bande.stage,
              totalDebutJour: precedent,
            )
          : null;
      _depart
        ..['repro'] = depart?.repro
        ..['sevre'] = depart?.sevre
        ..['jeune'] = depart?.jeune;
      _mortAncien = null;
      _donAncien = null;
      _morts.updateAll((_, _) => 0);
      _dons.updateAll((_, _) => 0);
      if (fiche == null) {
        _achat = 0;
        _ne = 0;
        _passage = 0;
        _effectifs.fillRange(0, 4, 0);
        _pesee = null;
      } else {
        _achat = fiche.achat;
        _ne = fiche.ne;
        if (fiche.mortRepro != null && fiche.mortSevre != null && fiche.mortJeune != null) {
          _morts
            ..['repro'] = fiche.mortRepro!
            ..['sevre'] = fiche.mortSevre!
            ..['jeune'] = fiche.mortJeune!;
        } else {
          _mortAncien = fiche.mort > 0 ? fiche.mort : null;
        }
        if (fiche.donRepro != null && fiche.donSevre != null && fiche.donJeune != null) {
          _dons
            ..['repro'] = fiche.donRepro!
            ..['sevre'] = fiche.donSevre!
            ..['jeune'] = fiche.donJeune!;
        } else {
          _donAncien = fiche.don > 0 ? fiche.don : null;
        }
        _passage = fiche.passageSevreJeune ?? 0;
        _effectifs
          ..[0] = fiche.effectifM ?? 0
          ..[1] = fiche.effectifF ?? 0
          ..[2] = fiche.effectifSevres ?? 0
          ..[3] = fiche.effectifSmeres ?? 0;
        // Tickets 14.60 / 14.63 : la colonne porte la MOYENNE, le champ affiche le TOTAL pesé.
        final moyenne = fiche.weightSampleAvgG;
        _pesee = moyenne == null || moyenne == 0 || fiche.effectifFinal <= 0
            ? null
            : (_c.peseeEnKg
                  ? PmpService.arrondi(moyenne * fiche.effectifFinal / 1000, 2)
                  : (moyenne * fiche.effectifFinal).roundToDouble());
      }
      _chargement = false;
    });
  }

  // ── Calculs, ceux du composant web ────────────────────────────────────────

  int get _vente => _fiche?.vente ?? 0;
  int get _totalMorts => _morts.values.fold(0, (a, b) => a + b);
  int get _totalDons => _dons.values.fold(0, (a, b) => a + b);

  /// `computeEffectifFinal(...)` : `max(0, …)`, transferts du jour compris.
  int get _effectifFinal => EffectifParCategorie.effectifFinal(
    precedent: _precedent,
    achat: _achat,
    ne: _ne,
    mort: _totalMorts,
    vente: _vente,
    don: _totalDons,
    transfertEntree: _fiche?.transfertEntree ?? 0,
    transfertSortie: _fiche?.transfertSortie ?? 0,
  );

  /// `getMortalityRateCalcProperty()` : `round(morts ÷ veille × 100, 1)`, 0 sans veille.
  double get _tauxMortalite => _precedent > 0 ? PmpService.arrondi(_totalMorts / _precedent * 100, 1) : 0;

  EffectifCategories get _departSaisi =>
      EffectifCategories(repro: _depart['repro'], sevre: _depart['sevre'], jeune: _depart['jeune']);

  CategoriesJour get _categories {
    final bande = _bande;
    final f = _fiche;
    return CategoriesJour.calculer(
      espece: _c.especeChaine,
      etat: bande == null ? null : _etat,
      departSaisi: _departSaisi,
      effectifPrecedent: _precedent,
      mouvements: MouvementsJour(
        achat: _achat,
        ne: _ne,
        vente: _vente,
        mortRepro: _morts['repro'],
        mortSevre: _morts['sevre'],
        mortJeune: _morts['jeune'],
        donRepro: _dons['repro'],
        donSevre: _dons['sevre'],
        donJeune: _dons['jeune'],
        passage: _passage,
        transfertEntreeRepro: f?.transfertEntreeRepro ?? 0,
        transfertEntreeSevre: f?.transfertEntreeSevre ?? 0,
        transfertEntreeJeune: f?.transfertEntreeJeune ?? 0,
        transfertSortieRepro: f?.transfertSortieRepro ?? 0,
        transfertSortieSevre: f?.transfertSortieSevre ?? 0,
        transfertSortieJeune: f?.transfertSortieJeune ?? 0,
      ),
      effectifFinal: _effectifFinal,
      jour: _jour,
      ancien: bande == null ? null : TeteImplicite.de(bande.id, _mois?.fiches ?? const []),
    );
  }

  /// `getAvertissementMortsProperty()` (D9) : le plancher à 0 s'applique et l'écran le dit.
  String? get _avertissementMorts => _totalMorts > _precedent
      ? "Morts du jour ($_totalMorts) supérieurs à l'effectif de la veille ($_precedent) : l'effectif est ramené à 0, "
            'vérifiez la saisie.'
      : null;

  static String _pourcent(double x) => '${PmpService.nombre(x, 1)} %';
  static String _date(DateTime d) => EnTeteSaisieFiche.dateLongue(d);

  // ── Rendu ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    final indicateurs = _mois?.indicateurs;
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EnTeteFiche(
              icone: _c.icone,
              titre: _c.titre,
              sousTitre: _c.sousTitre,
              onExporter: widget.imprimer == null || _mois == null ? null : _exporter,
            ),
            const SizedBox(height: AgriSpacing.lg),
            CartesFiche(
              cartes: [
                for (var i = 0; i < _c.cartes.length; i++)
                  CarteFiche(_c.cartes[i].$1, indicateurs?[i] ?? '—', _c.cartes[i].$2, _c.cartes[i].$3),
              ],
            ),
            const SizedBox(height: AgriSpacing.lg),
            if (_bande == null && !_chargement)
              AucuneBandeFiche(message: _c.aucuneBande)
            else if (_bande != null) ...[
              _carteSaisie(),
              const SizedBox(height: AgriSpacing.lg),
              // `hidden lg:block` : le tableau du mois n'existe qu'à partir de 1 024 px, comme au web.
              if (large) _tableauMensuel(),
            ],
          ],
        ),
      ),
    );
  }

  /// `exportFichePdf()` — le PDF du mois de la bande (`fiche-AAAA-MM.pdf`).
  Future<void> _exporter() async {
    final editeur = widget.imprimer;
    final mois = _mois;
    if (editeur == null || mois == null) return;
    final message = await editeur(mois.document, _maintenant);
    if (message != null && mounted) {
      ToastAgri.afficher(context, message, type: TypeToast.erreur);
    }
  }

  Widget _carteSaisie() {
    final cat = _categories;
    final provende = Provende.calculer(espece: _c.especeChaine, rations: _rations, categories: cat);
    return CarteSaisieFiche(
      lectureSeule: _lectureSeule,
      onJour: _ouvrirJour,
      enTete: EnTeteSaisieFiche(
        titre: _c.titreSaisie,
        jour: _jour,
        onJour: (j) => _ouvrirJour(j),
        bandes: [for (final b in _bandes) (b.id, b.code)],
        bandeId: _bande?.id,
        onBande: (id) async {
          setState(() => _bande = _bandes.firstWhere((b) => b.id == id));
          await _chargerJour();
        },
        maintenant: _maintenant,
        onMoisPrecedent: _moisPrecedent,
        onMoisSuivant: _moisSuivant,
      ),
      blocs: [
        if ((_fiche?.transfertEntree ?? 0) > 0 || (_fiche?.transfertSortie ?? 0) > 0)
          TransfertsDuJourFiche(
            entree: _fiche!.transfertEntree,
            sortie: _fiche!.transfertSortie,
            onOuvrir: widget.onOuvrirTransferts,
          ),
        if (cat.departRequis && cat.ancien != null)
          EncadreFiche(
            key: const Key('depart-ancien'),
            'Cette bande porte déjà des effectifs par catégorie saisis à la main (fiche du '
            '${_date(cat.ancien!.jour)} : ${_c.texteAncien(cat.ancien!.categories)}). Ils ne sont pas repris comme '
            "effectif de départ : l'effectif de départ ci-dessous est déduit du stade de la bande, corrigez-le si "
            "besoin avant d'enregistrer.",
          ),
        GrilleFiche(
          enfants: [
            ChampSaisieFiche(
              libelle: 'Achats du jour',
              cle: 'achat',
              valeur: _achat,
              onChange: (v) => setState(() => _achat = (v ?? 0).toInt()),
            ),
            ChampSaisieFiche(
              libelle: _c.libelleNes,
              cle: 'ne',
              valeur: _ne,
              onChange: (v) => setState(() => _ne = (v ?? 0).toInt()),
            ),
            ChampLectureFiche(libelle: 'Ventes', suffixe: '(POS, réel)', valeur: '$_vente', cle: 'champ-ventes'),
          ],
        ),
        BlocCategoriesFiche.morts(
          categories: _c.categoriesMorts,
          valeurs: _morts,
          onChange: (cle, v) => setState(() => _morts[cle] = v),
        ),
        BlocCategoriesFiche.dons(
          categories: _c.categoriesDons,
          valeurs: _dons,
          onChange: (cle, v) => setState(() => _dons[cle] = v),
        ),
        GrilleFiche(
          colonnes: 3,
          enfants: [
            ChampSaisieFiche(
              libelle: _c.libellePassage,
              suffixe: _c.suffixePassage,
              cle: 'passage',
              valeur: _passage,
              onChange: (v) => setState(() => _passage = (v ?? 0).toInt()),
            ),
          ],
        ),
        if (cat.departRequis)
          _departModifiable()
        else if (cat.depart != null)
          _departVerrouille(cat),
        if (cat.motif != null) EncadreFiche(key: const Key('motif-categories'), cat.motif!, erreur: true),
        if (cat.refusPassage != null)
          EncadreFiche(key: const Key('refus-passage'), cat.refusPassage!, erreur: true),
        if (_avertissementMorts != null) EncadreFiche(key: const Key('avertissement-morts'), _avertissementMorts!),
        for (final a in cat.avertissements) EncadreFiche(a),
        if (_mortAncien != null || _donAncien != null)
          EncadreFiche(
            key: const Key('fiche-ancienne'),
            'Fiche ancienne non ventilée par catégorie : ${_mortAncien ?? 0} mort(s) et ${_donAncien ?? 0} don(s) '
            "non ventilé(s) y sont enregistrés. Ventilez-les ci-dessus avant d'enregistrer.",
          ),
        GrilleFiche(
          ecart: AgriSpacing.sm,
          enfants: [
            for (var i = 0; i < 4; i++)
              ChampSaisieFiche(
                libelle: _c.libellesEffectifs[i],
                cle: 'effectif-$i',
                valeur: _effectifs[i],
                petite: true,
                onChange: (v) => setState(() => _effectifs[i] = (v ?? 0).toInt()),
              ),
          ],
        ),
        FiletFiche(
          enfants: [
            BlocEffectifFiche(
              titreEffectif: 'Effectif Final du Jour (Calculé dynamique)',
              formuleEffectif: '= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)',
              effectif: '$_effectifFinal',
              tauxMortalite: _pourcent(_tauxMortalite),
            ),
            const SizedBox(height: AgriSpacing.md),
            _rationnement(provende),
            const SizedBox(height: AgriSpacing.md),
            _autonomie(AutonomieAlimentaire.evaluer(_produitProvende, _stockProvendeKg, provende.totalKg)),
            const SizedBox(height: AgriSpacing.md),
            _blocPesee(),
            const SizedBox(height: AgriSpacing.md),
            FiletFiche(
              enfants: [
                TitreSectionFiche(
                  _c.titreTraitements,
                  icone: SymbolesAgri.vaccines,
                  couleurIcone: AgriColors.infoBlue,
                  tailleIcone: 18,
                ),
                const SizedBox(height: AgriSpacing.xs),
                if (_protocole != null)
                  ProphylaxieDuJourFiche(
                    protocole: _protocole!,
                    coches: _coches,
                    onCocher: (id, coche) => setState(() => coche ? _coches.add(id) : _coches.remove(id)),
                    onValider: _validerTraitements,
                    enCours: _validationEnCours,
                  ),
                const SizedBox(height: AgriSpacing.sm),
                ObservationsFiche(
                  libelle: _c.libelleObservations,
                  indice: _c.indiceObservations,
                  controleur: _observations,
                ),
              ],
            ),
          ],
        ),
        BoutonEnregistrerFiche(onPressed: _enregistrer),
      ],
    );
  }

  /// Effectif de DÉPART (D4) : déduit du stade de la bande, corrigeable avant le premier enregistrement.
  Widget _departModifiable() => Container(
    key: const Key('depart-modifiable'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.brandEmerald.withValues(alpha: 0.05),
      border: Border.all(color: AgriColors.brandEmerald.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSectionFiche(
          'Effectif de départ par catégorie (déduit du stade de la bande)',
          icone: SymbolesAgri.edit_note,
          couleur: AgriColors.brandEmerald,
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          "Effectif au DÉBUT du jour, avant les mouvements du jour, pré-rempli automatiquement depuis le stade de la "
          "bande. La somme des trois catégories doit égaler l'effectif total au début du jour ($_precedent). "
          'Corrigez-le seulement pour une bande mixte ; il est verrouillé au premier enregistrement.',
          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.xs),
        GrilleFiche(
          ecart: AgriSpacing.sm,
          enfants: [
            for (final (cle, libelle) in _c.categoriesDepart)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EtiquetteFiche(libelle, petite: true, centree: true),
                  ChampNombreFiche(
                    key: Key('depart-$cle'),
                    valeur: _depart[cle],
                    gras: true,
                    centre: true,
                    hauteur: 36,
                    onChange: (v) => setState(() => _depart[cle] = v?.toInt()),
                  ),
                ],
              ),
          ],
        ),
      ],
    ),
  );

  /// Départ verrouillé (chaîne commencée) : les trois valeurs, la date, et « jour antérieur » (D12).
  Widget _departVerrouille(CategoriesJour cat) {
    final d = cat.depart!;
    int? valeur(String cle) => switch (cle) {
      'repro' => d.repro,
      'sevre' => d.sevre,
      _ => d.jeune,
    };
    return Container(
      key: const Key('depart-verrouille'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TitreSectionFiche(
            'Effectif de départ par catégorie (verrouillé)',
            icone: SymbolesAgri.lock,
            couleurIcone: AgriColors.brandForest,
          ),
          const SizedBox(height: AgriSpacing.xs),
          Text(
            'Effectif de départ fixé le ${_date(cat.departDate!)} (au début de ce jour).',
            style: const TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
          const SizedBox(height: AgriSpacing.xs),
          GrilleFiche(
            ecart: AgriSpacing.sm,
            enfants: [
              for (final (cle, libelle) in _c.categoriesDepart)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EtiquetteFiche(libelle, petite: true, centree: true),
                    Container(
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AgriColors.surfaceZebra,
                        border: Border.all(color: AgriColors.outlineVariant),
                        borderRadius: BorderRadius.circular(AgriRadius.lg),
                      ),
                      child: Text(
                        '${valeur(cle) ?? ''}',
                        key: Key('depart-verrouille-$cle'),
                        style: const TextStyle(
                          fontSize: AgriTypography.sm,
                          fontWeight: AgriTypography.gras,
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (cat.mode == 'avant_depart') ...[
            const SizedBox(height: AgriSpacing.xs),
            Text(
              "Jour antérieur à l'effectif de départ fixé le ${_date(cat.departDate!)} : les effectifs par catégorie "
              'ne sont pas calculés (—).',
              style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.errorDeep),
            ),
          ],
        ],
      ),
    );
  }

  /// Le tableau « Rationnement » du Blade : trois lignes FIXES, effectif CALCULÉ (« — » = inconnu), ration, provende,
  /// total « — » dès qu'une catégorie est inconnue.
  Widget _rationnement(Provende provende) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TitreSectionFiche(_c.titreRationnement, icone: SymbolesAgri.restaurant),
        const SizedBox(height: AgriSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
            boxShadow: AgriShadows.sm,
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.8),
              3: FlexColumnWidth(1.8),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  color: AgriColors.surfaceZebra,
                  border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
                ),
                children: [
                  CelluleFiche(_c.enteteRation, couleur: AgriColors.outline),
                  const CelluleFiche('Effectif', centre: true, couleur: AgriColors.outline),
                  const CelluleFiche('Ration Normative', centre: true, couleur: AgriColors.outline),
                  const CelluleFiche('Provende Servie (g)', droite: true, couleur: AgriColors.outline),
                ],
              ),
              for (var i = 0; i < provende.lignes.length; i++)
                () {
                  final l = provende.lignes[i];
                  final enAvant = l.cle == _c.ligneRationMiseEnAvant;
                  return TableRow(
                    decoration: BoxDecoration(color: i == 1 ? AgriColors.surfaceZebra : null),
                    children: [
                      CelluleFiche(
                        _c.libellesRation[l.cle]!,
                        cleTexte: Key('ration-libelle-${l.cle}'),
                        gras: true,
                        couleur: AgriColors.brandForest,
                      ),
                      // 🔴→✅ Ticket U14 — le champ GRISÉ du Blade (`<input disabled … class="w-16 h-8 text-center border
                      // rounded text-xs font-bold">`, fond zébré sur les lignes blanches et blanc sur la ligne zébrée)
                      // et son info-bulle « Calculé automatiquement : … » : le poste écrivait le nombre nu.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.xs),
                        child: Center(
                          child: Tooltip(
                            key: Key('ration-infobulle-${l.cle}'),
                            message: _c.infobullesRation[l.cle]!,
                            child: Container(
                              width: 64,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: i == 1 ? AgriColors.surfaceCard : AgriColors.surfaceZebra,
                                border: Border.all(color: AgriColors.outlineVariant),
                                borderRadius: BorderRadius.circular(AgriRadius.base),
                              ),
                              child: Text(
                                l.effectif == null ? '—' : '${l.effectif}',
                                key: Key('ration-effectif-${l.cle}'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: AgriTypography.xs,
                                  fontWeight: AgriTypography.gras,
                                  color: AgriColors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      CelluleFiche(
                        _c.rationAffichee(l),
                        cleTexte: Key('ration-normative-${l.cle}'),
                        centre: true,
                        gras: enAvant,
                        couleur: enAvant ? AgriColors.brandEmerald : AgriColors.onSurface,
                      ),
                      CelluleFiche(
                        l.totalG == null ? '—' : '${l.totalG} g',
                        cleTexte: Key('ration-provende-${l.cle}'),
                        droite: true,
                        gras: true,
                        couleur: AgriColors.brandEmerald,
                      ),
                    ],
                  );
                }(),
              TableRow(
                decoration: BoxDecoration(color: AgriColors.brandEmerald.withValues(alpha: 0.10)),
                children: [
                  const CelluleFiche(
                    'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
                    gras: true,
                    taille: 10,
                    couleur: AgriColors.brandForest,
                  ),
                  const CelluleFiche(''),
                  const CelluleFiche(''),
                  CelluleFiche(
                    provende.totalAffiche,
                    cleTexte: const Key('total-provende'),
                    droite: true,
                    gras: true,
                    taille: AgriTypography.sm,
                    couleur: AgriColors.brandEmerald,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// `components/autonomie-alimentaire.blade.php` : aucun produit suivi, rupture, consommation inconnue, alerte
  /// critique, ou autonomie en jours. N'empêche jamais l'enregistrement.
  Widget _autonomie(AutonomieAlimentaire a) {
    Widget alerte(String titre, String texte) => Container(
      key: const Key('autonomie-alimentaire'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.errorBg,
        border: Border.all(color: AgriColors.errorDeep.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        boxShadow: AgriShadows.sm,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: AgriSpacing.sm,
        runSpacing: AgriSpacing.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(SymbolesAgri.warning, size: 22, color: AgriColors.errorDeep),
              const SizedBox(width: AgriSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        fontSize: AgriTypography.sm,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.errorDeep,
                      ),
                    ),
                    Text(texte, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
                  ],
                ),
              ),
            ],
          ),
          ElevatedButton(
            key: const Key('commander-stock'),
            onPressed: widget.onCommanderStock,
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.errorRed,
              foregroundColor: AgriColors.surfaceCard,
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.full)),
            ),
            child: const Text(
              'Commander Stock',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
            ),
          ),
        ],
      ),
    );
    Widget simple(List<InlineSpan> morceaux, Color fond, Color bord) => Container(
      key: const Key('autonomie-alimentaire'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: fond,
        border: Border.all(color: bord),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Text.rich(
        TextSpan(children: morceaux),
        style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.brandForest),
      ),
    );
    const gras = TextStyle(fontWeight: AgriTypography.gras);
    final nom = a.produit?.name;
    final stock = a.stockKg == null ? '' : PmpService.flottant(a.stockKg!);
    final jours = a.jours == null ? '' : PmpService.flottant(a.jours!);

    if (!a.disponible) {
      return Container(
        key: const Key('autonomie-alimentaire'),
        padding: const EdgeInsets.all(AgriSpacing.sm),
        decoration: BoxDecoration(
          color: AgriColors.errorBg,
          border: Border.all(color: AgriColors.errorDeep.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(SymbolesAgri.warning, size: 18, color: AgriColors.errorDeep),
                SizedBox(width: AgriSpacing.xs),
                Expanded(
                  child: Text(
                    'Autonomie alimentaire : aucun stock de provende suivi',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.errorDeep,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              "Aucun produit de provende ${_c.filiere} n'existe en catalogue avec un stock suivi : créez-le et "
              'approvisionnez-vous. La fiche s\'enregistre quand même.',
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
            ),
          ],
        ),
      );
    }
    if (a.rupture) {
      return alerte(
        'Autonomie alimentaire : rupture de stock',
        'Le stock de $nom est épuisé ($stock Kg) : approvisionnez-vous. La fiche s\'enregistre quand même.',
      );
    }
    if (a.inconnu) {
      return simple(
        [
          const TextSpan(text: 'Autonomie alimentaire : '),
          const TextSpan(text: '—', style: gras),
          TextSpan(
            text: ' ($nom, $stock Kg en stock) — la consommation du jour est inconnue tant que les effectifs par '
                'catégorie le sont.',
          ),
        ],
        AgriColors.surfaceZebra,
        AgriColors.outlineVariant,
      );
    }
    if (a.critique) {
      return alerte(
        'Alerte critique - Autonomie alimentaire',
        'Le stock de $nom ne couvre plus que $jours jours de consommation théorique du cheptel actif ! '
            'Approvisionnez-vous.',
      );
    }
    return simple(
      [
        const TextSpan(text: 'Autonomie alimentaire : '),
        TextSpan(text: '$jours jours', style: gras),
        TextSpan(text: ' ($nom, $stock Kg en stock).'),
      ],
      AgriColors.brandEmerald.withValues(alpha: 0.05),
      AgriColors.brandEmerald.withValues(alpha: 0.2),
    );
  }

  /// Pesée du Blade (filet haut, trois colonnes). Lapins : « Poids Général Pesé (g) », « Taille Échantillon (Auto =
  /// Effectif Final) », poids moyen `round(pesée ÷ effectif).' g'`. Porcs : « Poids Général Pesé (Kg) », « Effectif
  /// Final (diviseur) », poids moyen `number_format(pesée ÷ effectif, 1).' Kg'`. « — » sans pesée ni effectif.
  Widget _blocPesee() {
    final p = _pesee;
    final moyen = p == null || p == 0 || _effectifFinal <= 0
        ? '—'
        : (_c.peseeEnKg
              ? '${PmpService.nombre(p / _effectifFinal, 1, virgule: '.', milliers: ',')} Kg'
              : '${(p / _effectifFinal).round()} g');
    return FiletFiche(
      enfants: [
        GrilleFiche(
          enfants: [
            ChampSaisieFiche(
              libelle: _c.peseeEnKg ? 'Poids Général Pesé (Kg)' : 'Poids Général Pesé (g)',
              cle: 'pesee',
              valeur: p,
              gras: true,
              decimal: _c.peseeEnKg,
              indice: _c.peseeEnKg ? 'ex : 85' : 'ex : 3500',
              onChange: (v) => setState(() => _pesee = v?.toDouble()),
            ),
            ChampLectureFiche(
              libelle: _c.peseeEnKg ? 'Effectif Final' : 'Taille Échantillon',
              suffixe: _c.peseeEnKg ? '(diviseur)' : '(Auto = Effectif Final)',
              valeur: '$_effectifFinal',
              cle: 'champ-taille-echantillon',
              couleur: AgriColors.brandForest,
              gras: true,
            ),
            ChampLectureFiche(
              libelle: 'Poids Moyen Constaté',
              valeur: moyen,
              cle: 'champ-poids-moyen',
              couleur: AgriColors.brandEmerald,
              gras: true,
            ),
          ],
        ),
      ],
    );
  }

  /// `AvecProphylaxieDuJour::validerTraitements()` : refus d'un jour à venir, l'écriture idempotente du dépôt, les
  /// toasts du web.
  Future<void> _validerTraitements() async {
    // ⚠️ F0.93 : garde de l'écran (un second appel avant le setState), EN PLUS du dépôt, qui recalcule le protocole
    // sous transaction.
    if (_validationEnCours) return;
    final bande = _bande;
    if (bande == null || _protocole == null) return;
    final aujourdhui = JournalStocks.jour(_maintenant);
    if (_jour.isAfter(aujourdhui)) {
      ToastAgri.afficher(
        context,
        'Un traitement ne peut pas être validé pour un jour à venir.',
        type: TypeToast.erreur,
      );
      return;
    }
    setState(() => _validationEnCours = true);
    // ⚠️⚠️ F0.93 — PAS de boucle sur l'instantané `_protocole` : le dépôt RECALCULE le protocole à l'instant de
    // l'écriture (comme le serveur, 15.35) ; valider deux fois = un seul soin, une seule rémanence.
    final crees = await widget.soins.validerTraitementsDuJour(
      bande: bande,
      codeEspece: _c.espece.codeEspece,
      quand: _jour,
      idsBareme: Set.of(_coches),
      observations: _observations.text,
    );
    if (!mounted) return;
    setState(() => _validationEnCours = false);
    ToastAgri.afficher(
      context,
      crees.isEmpty
          ? 'Aucun traitement à enregistrer (déjà validés, ou non prévus ce jour-là).'
          : '${crees.length} traitement(s) enregistré(s) au registre vétérinaire.',
      type: crees.isEmpty ? TypeToast.avertissement : TypeToast.succes,
    );
    await _chargerJour();
  }

  /// `saveDay()` : contrôles AVANT toute écriture (bande, refus du passage D3, départ D4, fiche ancienne non
  /// ventilée), puis l'écriture (mouvements par catégorie, effectifs saisis, provende du jour, poids MOYEN), la
  /// cascade du dépôt, le toast du web.
  Future<void> _enregistrer() async {
    final bande = _bande;
    if (bande == null) {
      ToastAgri.afficher(context, _c.toastAucuneBande, type: TypeToast.erreur);
      return;
    }
    final cat = _categories;
    if (cat.refusPassage != null) {
      ToastAgri.afficher(context, cat.refusPassage!, type: TypeToast.erreur);
      return;
    }
    final saisi = _departSaisi;
    var departAEcrire = false;
    if (cat.mode == 'sans_chaine' && [saisi.repro, saisi.sevre, saisi.jeune].any((v) => v != null)) {
      final refus = EffectifParCategorie.verifierDepart(saisi, _precedent);
      if (refus != null) {
        ToastAgri.afficher(context, refus, type: TypeToast.erreur);
        return;
      }
      departAEcrire = true;
    }
    if ((_mortAncien != null && _totalMorts == 0) || (_donAncien != null && _totalDons == 0)) {
      ToastAgri.afficher(
        context,
        'Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les ${_c.ventilation} '
        "avant d'enregistrer.",
        type: TypeToast.erreur,
      );
      return;
    }

    final provende = Provende.calculer(espece: _c.especeChaine, rations: _rations, categories: cat);
    final pesee = _pesee;
    try {
      await widget.depot.enregistrer(
        lotId: bande.id,
        jour: _jour,
        achat: _achat,
        ne: _ne,
        mort: _totalMorts,
        don: _totalDons,
        aliment: provende.totalKg,
        // Ticket 14.63 : la colonne porte le poids MOYEN par sujet, en grammes, arrondi.
        poidsMoyen: FicheJournaliereRepository.poidsMoyen(
          poidsTotalG: pesee == null ? 0 : (_c.peseeEnKg ? pesee * 1000 : pesee),
          tailleEchantillon: _effectifFinal,
        ),
        ventilation: VentilationJour(
          mortRepro: _morts['repro']!,
          mortSevre: _morts['sevre']!,
          mortJeune: _morts['jeune']!,
          donRepro: _dons['repro']!,
          donSevre: _dons['sevre']!,
          donJeune: _dons['jeune']!,
          passage: _passage,
          departSaisi: departAEcrire ? saisi : null,
        ),
        effectifs: EffectifsSaisis(m: _effectifs[0], f: _effectifs[1], sevres: _effectifs[2], smeres: _effectifs[3]),
      );
    } on FicheRefusee catch (e) {
      if (mounted) ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7, Q3) — `saveDay()` : fiche d'un exercice clos, motif R4 en toast d'erreur.
      if (mounted) ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    }
    if (!mounted) return;
    ToastAgri.afficher(context, 'Jour enregistré avec succès.');
    await _chargerJour();
  }

  // ── Tableau du mois ───────────────────────────────────────────────────────

  /// Le tableau du mois du Blade : TOUS les jours du mois en cours, la ligne du jour choisi surlignée, une ligne
  /// touchée charge son jour (`loadDay`). Cellules de [JourFiche.cellules].
  Widget _tableauMensuel() {
    final jours = _mois?.jours ?? const <JourFiche>[];
    final cellules = [for (final j in jours) j.cellules(_c.espece)];
    final indexChoisi = jours.indexWhere((j) => j.jour == JournalStocks.jour(_jour));
    ColonneMensuelle colonne(
      String libelle,
      int rang, {
      double largeur = 1,
      bool gras = false,
      bool aGauche = false,
      Color? Function(int)? couleur,
      bool Function(int)? grasSelon,
    }) => ColonneMensuelle(
      libelle: libelle,
      largeur: largeur,
      gras: gras,
      aGauche: aGauche,
      couleur: couleur,
      grasSelon: grasSelon,
      valeur: (i) => cellules[i][rang],
    );
    bool mort(int i) => (jours[i].fiche?.mort ?? 0) > 0;
    bool taux(int i) => (jours[i].tauxMortalite ?? 0) > 0;

    return TableauMensuel(
      key: const Key('tableau-mois'),
      libelleDate: 'Date',
      nombreDeJours: jours.length,
      jourActif: indexChoisi < 0 ? null : indexChoisi,
      zebre: false,
      invite: null,
      dateDe: (i) => jours[i].date,
      onOuvrirJour: (i) => _ouvrirJour(jours[i].jour),
      groupes: [
        GroupeColonnes(libelle: 'Entrées', colonnes: [colonne('Achat', 0), colonne('Né', 1)]),
        GroupeColonnes(
          libelle: 'Sorties',
          colonnes: [
            // `text-error-deep font-bold` quand des morts sont comptés.
            colonne('Mort', 2, couleur: (i) => mort(i) ? AgriColors.errorDeep : null, grasSelon: mort),
            colonne('Vente', 3),
            colonne('Don', 4),
          ],
        ),
        GroupeColonnes(
          libelle: 'Effectif Final du Jour',
          colonnes: [
            for (var k = 0; k < _c.colonnesEffectif.length; k++) colonne(_c.colonnesEffectif[k], 5 + k),
            colonne('Total', 9, gras: true),
          ],
        ),
      ],
      colonnesSimples: [
        colonne(
          'Taux Mort %',
          10,
          largeur: 1.2,
          couleur: (i) => taux(i) ? AgriColors.errorDeep : null,
          grasSelon: taux,
        ),
        colonne(_c.libellePoids, 11, largeur: 1.4),
        colonne('Traitements & Prophylaxie', 12, largeur: 3, aGauche: true, couleur: (_) => AgriColors.outline),
      ],
    );
  }

  /// ⚠️ CHARGE LA JOURNÉE DANS LE FORMULAIRE (`loadDay`).
  Future<void> _ouvrirJour(DateTime jour) async {
    setState(() => _jour = DateTime(jour.year, jour.month, jour.day));
    await _chargerJour();
  }

  /// Ticket EX8 (EF12) — « ‹ » : le premier jour du mois précédent (`moisPrecedent()` du web).
  Future<void> _moisPrecedent() => _ouvrirJour(MoisDeFiche.precedent(_jour));

  /// Ticket EX8 (EF12) — « › » : le mois suivant, jamais au-delà du mois en cours (`moisSuivant()` du web).
  Future<void> _moisSuivant() async {
    final suivant = MoisDeFiche.suivant(_jour, _maintenant);
    if (suivant != null) await _ouvrirJour(suivant);
  }
}
