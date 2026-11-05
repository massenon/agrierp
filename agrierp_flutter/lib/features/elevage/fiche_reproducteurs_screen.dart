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
import 'categorie_volaille.dart';
import 'effectif_par_categorie.dart';
import 'elements_fiche.dart';
import 'autonomie_alimentaire_carte.dart';
import 'fiche_journaliere_repository.dart';
import 'jour_categories.dart';
import 'mois_fiche.dart';
import 'soins_repository.dart';

/// `fiche-reproducteurs.blade.php` (web, `FicheReproducteurs`) → Fiches Volailles - Reproducteurs, Poussins & Goliath.
///
/// 🔴→✅ **TICKET U12a — LE BLADE EST LA RÉFÉRENCE DE MISE EN PAGE** (doctrine, article 5), et non plus la maquette
/// `fiche-volailles-reproducteurs.html`. Sections du Blade, dans son ordre, libellés au mot près :
///   1. en-tête, sous-titre, « Exporter PDF » ; 2. quatre cartes du MOIS, avec leurs légendes ;
///   3. sans bande : « Aucune bande active (Reproducteurs/Goliath/Poussins) pour le moment. » ;
///   4. carte « Saisie Journalière Couvoir & Suivi Chair » (« Date : » seul) : transferts du jour ; « Bande / Lot
///      Concerné » · Achats du jour · Ventes (POS, réel) ; **Workflow Couvoir & Éclosion** ; Morts par catégorie ;
///      Dons par catégorie ; passage Poussin → Jeune ; départ obligatoire ; « Effectif Final » et taux de mortalité ;
///      rationnement PAR CATÉGORIE et autonomie alimentaire (VOL-1) ;
///      pesée ; Traitements & Prophylaxie (protocole du jour, « Observations ») ; « Enregistrer ce Jour » ;
///   5. le tableau du mois (TOUS les jours), et sa note sur la ventilation des morts.
///
/// Retirés avec la maquette : « Taille Échantillon » de la pesée, « Attribution Bâtiments & Parcs Volailles
/// Traités », « Réinitialiser », le « Jour N » du titre et des lignes du tableau.
///
/// 🔁 **TICKET VOL-1 (décision client du 04/11/2026) — EFFECTIF PAR CATÉGORIE CALCULÉ**, comme les lapins et les porcs :
/// Reproducteur, Jeune (jamais « Poulet », ni aucune formule plus longue), Poussin ; calcul = [EffectifParCategorie] (miroir du
/// service PHP, parité exécutée). AUCUNE catégorie « inconnue » : le DÉPART de la bande est exigé avant toute journée
/// (la fiche le demande au lieu de l'effectif et refuse d'enregistrer), les jours antérieurs au départ ne sont pas
/// saisissables. Les ventes par catégorie viennent de la caisse (catégorie du produit vendu), en lecture seule.
///
/// ⚠️⚠️ **AVICULTURE HORS PONTE** (`stage != 'ponte'`), comme le web : la fiche couvre aussi les bandes de chair
/// (Goliath) et de démarrage (poussins). `ponte_total` porte les œufs COUVÉS, `ne` les poussins nés — ce ne sont pas
/// des œufs de table, aucun stock d'œufs n'est touché (ticket 14.59).
class FicheReproducteursScreen extends StatefulWidget {
  const FicheReproducteursScreen({
    super.key,
    required this.depot,
    required this.soins,
    this.imprimer,
    this.onOuvrirTransferts,
    this.onCommanderStock,
    this.maintenant,
  });

  final FicheJournaliereRepository depot;
  final SoinsRepository soins;

  /// « Exporter PDF » — `EditeursRapports.imprimer` en production, un espion en test ; `null` : bouton inerte.
  final Future<String?> Function(DocumentOfficiel document, DateTime maintenant)? imprimer;
  final VoidCallback? onOuvrirTransferts;

  /// « Commander Stock » de la carte d'autonomie alimentaire (`/achats-commandes` au web).
  final VoidCallback? onCommanderStock;

  /// Horloge injectable : le mois du tableau et des cartes est celui de MAINTENANT (`now()` du web).
  final DateTime Function()? maintenant;

  @override
  State<FicheReproducteursScreen> createState() => _FicheReproducteursScreenState();
}

class _FicheReproducteursScreenState extends State<FicheReproducteursScreen> {
  /// Catégories des morts et des dons du Blade, dans son ordre (VOL-1). Clés = emplacements génériques de
  /// synchronisation : `repro` = Reproducteur, `jeune` = Jeune (ex-« Poulet »), `sevre` = Poussin.
  static const _categories = [('repro', 'Reproducteur'), ('jeune', 'Jeune'), ('sevre', 'Poussin')];

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
  int _passage = 0;
  final _depart = <String, int?>{'repro': null, 'sevre': null, 'jeune': null};
  LivestockDailyEntry? _fiche;
  int _achat = 0;
  int _oeufsCouves = 0;
  int _poussinsNes = 0;
  final _morts = <String, int>{for (final (c, _) in _categories) c: 0};
  final _dons = <String, int>{for (final (c, _) in _categories) c: 0};
  int? _mortEnregistre;
  int? _donEnregistre;
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
    final bandes = MoisFiche.bandesDe(EspeceFiche.reproducteurs, await widget.depot.bandesActives());
    final rations = await widget.depot.rations('aviculture');
    final db = widget.depot.database;
    final produits = await db.select(db.products).get();
    final especes = await db.select(db.livestockSpecies).get();
    final types = await db.select(db.feedTypes).get();
    final produit = AutonomieAlimentaire.produitProvende('aviculture', produits, especes);
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

  /// `loadDay()` : la fiche de la bande à CETTE date, quel que soit le mois ; à l'ouverture (`mount()`) et à chaque
  /// changement de date ou de bande (🔴→✅ U12a, corrigé aussi au web) ; morts et dons enregistrés gardés en total.
  Future<void> _chargerJour() async {
    final bande = _bande;
    // Ticket EX8 (EF12) : le mois AFFICHÉ est celui du jour choisi (`AvecMoisDeFiche` du web).
    final mois = await MoisFiche.charger(
      widget.depot.database,
      espece: EspeceFiche.reproducteurs,
      bandes: _bandes,
      bande: bande,
      maintenant: _jour,
    );
    // Ticket EX8 (EF12) : un jour d'un exercice CLOS se consulte en lecture seule ; fusion EX7 + EX8 : bandeau d'EX7.
    final lectureSeule = await LectureSeuleDuJour.charger(widget.depot.database, _jour, maintenant: _maintenant);
    final precedent = bande == null ? 0 : await widget.depot.effectifPrecedent(bande.id, _jour);
    final fiche = bande == null ? null : await widget.depot.chargerJour(bande.id, _jour);
    final etat = bande == null ? null : await widget.depot.etatCategories(bande.id, _jour);
    final protocole = bande == null
        ? null
        : await widget.soins.protocoleDuJour(bande: bande, codeEspece: 'aviculture', quand: _jour);
    if (!mounted) return;
    setState(() {
      _mois = mois;
      _lectureSeule = lectureSeule;
      _precedent = precedent;
      _etat = etat;
      _fiche = fiche;
      _protocole = protocole;
      // Une case cochée ne survit pas à un changement de jour ; le départ saisi (aperçu) non plus.
      _coches.clear();
      _depart
        ..['repro'] = null
        ..['sevre'] = null
        ..['jeune'] = null;
      _morts.updateAll((_, _) => 0);
      _dons.updateAll((_, _) => 0);
      // VOL-1 : la ventilation STOCKÉE recharge le jour ; une fiche d'AVANT le ticket (colonnes à null) garde son total,
      // qui doit être ventilé avant d'enregistrer.
      _mortEnregistre = null;
      _donEnregistre = null;
      _passage = fiche?.passageSevreJeune ?? 0;
      if (fiche != null) {
        if (fiche.mortRepro != null && fiche.mortSevre != null && fiche.mortJeune != null) {
          _morts
            ..['repro'] = fiche.mortRepro!
            ..['sevre'] = fiche.mortSevre!
            ..['jeune'] = fiche.mortJeune!;
        } else {
          _mortEnregistre = fiche.mort > 0 ? fiche.mort : null;
        }
        if (fiche.donRepro != null && fiche.donSevre != null && fiche.donJeune != null) {
          _dons
            ..['repro'] = fiche.donRepro!
            ..['sevre'] = fiche.donSevre!
            ..['jeune'] = fiche.donJeune!;
        } else {
          _donEnregistre = fiche.don > 0 ? fiche.don : null;
        }
      }
      _achat = fiche?.achat ?? 0;
      _oeufsCouves = fiche?.ponteTotal ?? 0;
      _poussinsNes = fiche?.ne ?? 0;
      final moyenne = fiche?.weightSampleAvgG;
      _pesee = fiche == null || moyenne == null || moyenne == 0 || fiche.effectifFinal <= 0
          ? null
          : (moyenne * fiche.effectifFinal).roundToDouble();
      _chargement = false;
    });
  }

  // ── Calculs, ceux du composant web ────────────────────────────────────────

  int get _vente => _fiche?.vente ?? 0;

  /// `mortDuJour()` (15.55) : la répartition saisie, sinon le total déjà enregistré.
  int get _totalMorts {
    final saisis = _morts.values.fold(0, (a, b) => a + b);
    return saisis > 0 ? saisis : (_mortEnregistre ?? 0);
  }

  /// `donDuJour()` (15.56).
  int get _totalDons {
    final saisis = _dons.values.fold(0, (a, b) => a + b);
    return saisis > 0 ? saisis : (_donEnregistre ?? 0);
  }

  int get _effectifFinal => FicheJournaliereRepository.calculerEffectifFinal(
    effectifPrecedent: _precedent,
    achat: _achat,
    ne: _poussinsNes,
    mort: _totalMorts,
    vente: _vente,
    don: _totalDons,
    transfertEntree: _fiche?.transfertEntree ?? 0,
    transfertSortie: _fiche?.transfertSortie ?? 0,
  ).clamp(0, 1 << 30);

  double get _tauxMortalite => _precedent > 0 ? PmpService.arrondi(_totalMorts / _precedent * 100, 1) : 0;

  /// `getEclosionRateCalcProperty()` : jamais 85 % (14.61) ; 🔴→✅ U14 — sans œuf couvé, INCONNU (`null`, « — »), comme
  /// le web désormais (il affichait « 0,0 % »).
  double? get _tauxEclosion => _oeufsCouves > 0 ? PmpService.arrondi(_poussinsNes / _oeufsCouves * 100, 1) : null;

  static String _pourcent(double x) => '${PmpService.nombre(x, 1)} %';

  /// Option du sélecteur : `{{ $lot->code }} ({{ $lot->libelleStade() }} — {{ $lot->current_quantity }} têtes)`.
  /// 🔁 VOL-1 : le stade s'affiche par son LIBELLÉ (Reproducteur / Poussin / Jeune / Ponte), jamais la valeur stockée.
  static String libelleBande(LivestockLot b) {
    const libelles = {'reproduction': 'Reproducteur', 'croissance': 'Poussin', 'engraissement': 'Jeune', 'ponte': 'Ponte'};
    final stade = b.stage ?? '';
    final affiche = libelles[stade] ?? (stade.isEmpty ? '' : stade[0].toUpperCase() + stade.substring(1));
    return '${b.code} ($affiche — ${b.currentQuantity} têtes)';
  }

  EffectifCategories get _departSaisi =>
      EffectifCategories(repro: _depart['repro'], sevre: _depart['sevre'], jeune: _depart['jeune']);

  /// Ventes du jour par catégorie (colonnes `vente_*` posées par la caisse) ; 0 sans fiche.
  int get _venteRepro => _fiche?.venteRepro ?? 0;
  int get _venteSevre => _fiche?.venteSevre ?? 0;
  int get _venteJeune => _fiche?.venteJeune ?? 0;

  /// Vente d'AVANT le ticket : le total existe, sa répartition par catégorie non.
  bool get _venteNonVentilee => _fiche != null && _fiche!.vente > 0 && _fiche!.venteRepro == null;

  /// `getCategoriesJourProperty()` du web : effectifs CALCULÉS (jamais saisis), départ, refus, avertissements.
  CategoriesJour get _categoriesJour {
    final bande = _bande;
    final f = _fiche;
    return CategoriesJour.calculerVolailles(
      etat: bande == null ? null : _etat,
      departSaisi: _departSaisi,
      effectifPrecedent: _precedent,
      mouvements: MouvementsJour(
        achat: _achat,
        ne: _poussinsNes,
        venteRepro: _venteRepro,
        venteSevre: _venteSevre,
        venteJeune: _venteJeune,
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
      proposition: bande == null
          ? null
          : EffectifParCategorie.departDepuisStade(
              codeEspece: bande.speciesCode,
              stade: bande.stage,
              totalDebutJour: _precedent,
            ),
    );
  }

  /// `getAvertissementMortsProperty()` (D9) : le plancher à 0 s'applique et l'écran le dit.
  String? get _avertissementMorts => _totalMorts > _precedent
      ? "Morts du jour ($_totalMorts) supérieurs à l'effectif de la veille ($_precedent) : l'effectif est ramené à 0, "
            'vérifiez la saisie.'
      : null;

  /// `appliquerPropositionDepart()` : reprend la proposition d'après le stade, sur demande de l'éleveur seulement.
  void _appliquerProposition(EffectifCategories p) => setState(() {
    _depart
      ..['repro'] = p.repro
      ..['sevre'] = p.sevre
      ..['jeune'] = p.jeune;
  });

  // ── Rendu ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    final k = _mois?.indicateurs;
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EnTeteFiche(
              icone: SymbolesAgri.grid_view,
              titre: 'Fiches Volailles - Reproducteurs, Poussins & Goliath',
              sousTitre: 'Suivi de la reproduction avicole, couvoir, incubation, éclosion, poussins et poulets de chair.',
              onExporter: widget.imprimer == null || _mois == null ? null : _exporter,
            ),
            const SizedBox(height: AgriSpacing.lg),
            CartesFiche(
              cartes: [
                CarteFiche(
                  'Effectif Total Vivant',
                  k?[0] ?? '—',
                  SymbolesAgri.grid_view,
                  CarteFiche.emerald,
                  legende: 'Reproducteurs, Poussins & Goliath',
                ),
                CarteFiche(
                  "Taux d'Éclosion Couvoir",
                  k?[1] ?? '—',
                  SymbolesAgri.egg,
                  CarteFiche.blue,
                  legende: 'Ratio : Poussins Nés ÷ Œufs Couvés',
                ),
                CarteFiche(
                  'Poussins Nés (Éclosion)',
                  k?[2] ?? '—',
                  SymbolesAgri.child_care,
                  CarteFiche.maize,
                  legende: 'Cumul naissances au couvoir',
                ),
                CarteFiche(
                  'Taux de Mortalité',
                  k?[3] ?? '—',
                  SymbolesAgri.trending_down,
                  CarteFiche.red,
                  legende: 'Seuil critique < 5%',
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.lg),
            if (_bande == null && !_chargement)
              const AucuneBandeFiche(message: 'Aucune bande active (Reproducteurs/Goliath/Poussins) pour le moment.')
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
    final cat = _categoriesJour;
    final tableau = cat.repro == null
        ? null
        : CategorieVolaille.tableauReproducteurs(_rations, {'repro': cat.repro, 'sevre': cat.sevre, 'jeune': cat.jeune});
    final moyen = _pesee == null || _pesee == 0 || _effectifFinal <= 0 ? '—' : '${(_pesee! / _effectifFinal).round()} g';
    return CarteSaisieFiche(
      lectureSeule: _lectureSeule,
      onJour: _ouvrirJour,
      // Le Blade n'a que « Date : » dans l'en-tête : la bande se choisit dans le formulaire.
      enTete: EnTeteSaisieFiche(
        titre: 'Saisie Journalière Couvoir & Suivi Chair',
        jour: _jour,
        onJour: _ouvrirJour,
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
        GrilleFiche(
          enfants: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EtiquetteFiche('Bande / Lot Concerné'),
                Container(
                  key: const Key('bande-fiche'),
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
                  decoration: BoxDecoration(
                    color: AgriColors.surfaceCard,
                    border: Border.all(color: AgriColors.outlineVariant),
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _bande?.id,
                      isExpanded: true,
                      style: const TextStyle(
                        fontSize: AgriTypography.sm,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.onSurface,
                      ),
                      items: [
                        for (final b in _bandes) DropdownMenuItem(value: b.id, child: Text(libelleBande(b))),
                      ],
                      onChanged: (id) async {
                        if (id == null) return;
                        setState(() => _bande = _bandes.firstWhere((b) => b.id == id));
                        await _chargerJour();
                      },
                    ),
                  ),
                ),
              ],
            ),
            ChampSaisieFiche(
              libelle: 'Achats du jour',
              cle: 'achat',
              valeur: _achat,
              onChange: (v) => setState(() => _achat = (v ?? 0).toInt()),
            ),
            // VOL-1 : la caisse range chaque vente dans la catégorie du PRODUIT vendu (lecture seule).
            ChampLectureFiche(
              libelle: 'Ventes',
              suffixe: '(POS, réel)',
              valeur: '$_vente',
              cle: 'champ-ventes',
              note: 'Reproducteur $_venteRepro · Jeune $_venteJeune · Poussin $_venteSevre',
              cleNote: const Key('ventes-par-categorie'),
            ),
          ],
        ),
        _workflowCouvoir(),
        BlocCategoriesFiche.morts(
          categories: _categories,
          valeurs: _morts,
          dejaEnregistres: _mortEnregistre,
          finMention: "ventilez-les ci-dessous (Reproducteur / Jeune / Poussin) avant d'enregistrer.",
          onChange: (c, v) => setState(() => _morts[c] = v),
        ),
        BlocCategoriesFiche.dons(
          categories: _categories,
          valeurs: _dons,
          dejaEnregistres: _donEnregistre,
          finMention: "ventilez-les ci-dessous (Reproducteur / Jeune / Poussin) avant d'enregistrer.",
          onChange: (c, v) => setState(() => _dons[c] = v),
        ),
        // VOL-1 — passage de stade du jour (Poussin → Jeune), hors maquette, assumé.
        GrilleFiche(
          colonnes: 3,
          enfants: [
            ChampSaisieFiche(
              libelle: 'Passage du jour (Poussin → Jeune)',
              cle: 'passage',
              valeur: _passage,
              onChange: (v) => setState(() => _passage = (v ?? 0).toInt()),
            ),
          ],
        ),
        if (cat.departRequis)
          _departModifiable(cat)
        else if (cat.depart != null)
          _departVerrouille(cat),
        if (cat.motif != null) EncadreFiche(key: const Key('motif-categories'), cat.motif!, erreur: true),
        if (cat.refusPassage != null) EncadreFiche(key: const Key('refus-passage'), cat.refusPassage!, erreur: true),
        if (_avertissementMorts != null) EncadreFiche(key: const Key('avertissement-morts'), _avertissementMorts!),
        for (final a in cat.avertissements) EncadreFiche(a),
        if (_venteNonVentilee)
          const EncadreFiche(
            key: Key('ventes-non-ventilees'),
            "Cette journée porte des ventes d'avant la mise en place des catégories, non ventilées : elle ne peut pas être ré-enregistrée.",
          ),
        BlocEffectifFiche(
          titreEffectif: 'Effectif Final',
          formuleEffectif: '= Effectif (J-1) + Achats/Poussins Nés − (Morts + Ventes + Dons)',
          effectif: '$_effectifFinal',
          tauxMortalite: _pourcent(_tauxMortalite),
        ),
        // VOL-1 — rationnement PAR CATÉGORIE : effectif calculé de chaque catégorie × la ration de sa ligne du barème
        // (`CategorieVolaille.tableauReproducteurs`, même tableau que le web) ; la demande de départ tient lieu d'effectif.
        RationReproducteursFiche(tableau: tableau),
        // Autonomie alimentaire sur la provende du jour : SOMME des trois catégories (information, jamais un blocage).
        CarteAutonomieAlimentaire(
          autonomie: AutonomieAlimentaire.evaluer(_produitProvende, _stockProvendeKg, tableau?.totalKg),
          filiere: 'aviculture',
          onCommanderStock: widget.onCommanderStock,
        ),
        GrilleFiche(
          enfants: [
            ChampSaisieFiche(
              libelle: 'Poids Général Pesé (g)',
              cle: 'pesee',
              valeur: _pesee,
              gras: true,
              indice: 'ex : 1800',
              onChange: (v) => setState(() => _pesee = v?.toDouble()),
            ),
            ChampLectureFiche(
              libelle: 'Poids Moyen Constaté',
              suffixe: '(Poids Général ÷ Effectif Final)',
              valeur: moyen,
              cle: 'champ-poids-moyen',
              couleur: AgriColors.brandEmerald,
              gras: true,
            ),
          ],
        ),
        FiletFiche(
          enfants: [
            const TitreSectionFiche(
              'Traitements & Prophylaxie',
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
            ObservationsFiche(libelle: 'Observations', indice: 'ex : RAS', controleur: _observations),
          ],
        ),
        BoutonEnregistrerFiche(onPressed: _enregistrer),
      ],
    );
  }

  /// Bloc « Effectif de départ par catégorie (obligatoire) » du Blade : saisi UNE fois par bande, verrouillé ensuite.
  Widget _departModifiable(CategoriesJour cat) => Container(
    key: const Key('depart-requis'),
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
          'Effectif de départ par catégorie (obligatoire)',
          icone: SymbolesAgri.edit_note,
          couleurIcone: AgriColors.brandEmerald,
          couleur: AgriColors.brandEmerald,
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          "Cette bande n'a pas encore d'effectif de départ : saisissez l'effectif de chaque catégorie au DÉBUT de ce "
          'jour, avant les mouvements du jour. La somme des trois catégories doit égaler l\'effectif total au début du '
          'jour ($_precedent). Il est verrouillé au premier enregistrement ; la journée ne s\'enregistre pas sans lui.',
          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.xs),
        GrilleFiche(
          colonnes: 3,
          ecart: AgriSpacing.sm,
          enfants: [
            for (final (cle, libelle) in _categories)
              ChampSaisieFiche(
                libelle: libelle,
                cle: 'depart-$cle',
                valeur: _depart[cle],
                petite: true,
                onChange: (v) => setState(() => _depart[cle] = v?.toInt()),
              ),
          ],
        ),
        if (cat.proposition != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('depart-proposition'),
              onPressed: () => _appliquerProposition(cat.proposition!),
              child: Text(
                "Reprendre la proposition d'après le stade de la bande (Reproducteur ${cat.proposition!.repro} · "
                'Jeune ${cat.proposition!.jeune} · Poussin ${cat.proposition!.sevre})',
                style: const TextStyle(fontSize: 11, fontWeight: AgriTypography.gras, color: AgriColors.brandEmerald),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _departVerrouille(CategoriesJour cat) => Container(
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
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          'Effectif de départ fixé le ${EnTeteSaisieFiche.dateLongue(cat.departDate!)} (au début de ce jour).',
          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.xs),
        GrilleFiche(
          colonnes: 3,
          ecart: AgriSpacing.sm,
          enfants: [
            for (final (cle, libelle) in _categories)
              ChampLectureFiche(
                libelle: libelle,
                valeur: '${switch (cle) {
                  'repro' => cat.depart!.repro,
                  'sevre' => cat.depart!.sevre,
                  _ => cat.depart!.jeune,
                }}',
                cle: 'depart-verrouille-$cle',
                petite: true,
              ),
          ],
        ),
        if (cat.mode == 'avant_depart')
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: Text(
              "Jour antérieur à l'effectif de départ fixé le ${EnTeteSaisieFiche.dateLongue(cat.departDate!)} : il n'est pas saisissable.",
              key: const Key('avant-depart'),
              style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.errorDeep),
            ),
          ),
      ],
    ),
  );

  /// « Workflow Couvoir & Éclosion (Incubation → Poussins Nés) » — le bloc ambre du Blade.
  Widget _workflowCouvoir() => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: TeintesFiche.amber500.withValues(alpha: 0.10),
      border: Border.all(color: TeintesFiche.amber500.withValues(alpha: 0.30)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSectionFiche(
          'Workflow Couvoir & Éclosion (Incubation → Poussins Nés)',
          icone: SymbolesAgri.egg,
          couleurIcone: TeintesFiche.amber700,
          couleur: TeintesFiche.amber900,
          tailleIcone: 18,
        ),
        const SizedBox(height: AgriSpacing.sm),
        GrilleFiche(
          ecart: AgriSpacing.sm,
          enfants: [
            ChampSaisieFiche(
              libelle: 'Œufs Couvés (Mis en incubation)',
              cle: 'oeufs-couves',
              valeur: _oeufsCouves,
              gras: true,
              onChange: (v) => setState(() => _oeufsCouves = (v ?? 0).toInt()),
            ),
            ChampSaisieFiche(
              libelle: 'Poussins Nés (Éclosion du jour)',
              cle: 'poussins-nes',
              valeur: _poussinsNes,
              gras: true,
              couleur: AgriColors.brandEmerald,
              onChange: (v) => setState(() => _poussinsNes = (v ?? 0).toInt()),
            ),
            ChampLectureFiche(
              libelle: "Taux d'Éclosion Calculé (%)",
              valeur: _tauxEclosion == null ? '—' : _pourcent(_tauxEclosion!),
              cle: 'champ-taux-eclosion',
              couleur: AgriColors.brandEmerald,
              gras: true,
            ),
          ],
        ),
      ],
    ),
  );

  /// `AvecProphylaxieDuJour::validerTraitements()` : refus d'un jour à venir, l'écriture idempotente du dépôt, les
  /// toasts du web.
  Future<void> _validerTraitements() async {
    // ⚠️ F0.93 : garde de l'écran (un second appel avant le setState), EN PLUS du dépôt, qui recalcule le protocole
    // sous transaction.
    if (_validationEnCours) return;
    final bande = _bande;
    if (bande == null || _protocole == null) return;
    if (_jour.isAfter(JournalStocks.jour(_maintenant))) {
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
      codeEspece: 'aviculture',
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

  /// `saveDay()` : la bande, puis l'écriture (achats, poussins nés, morts et dons du jour, œufs couvés, poids MOYEN),
  /// la cascade du dépôt, le toast du web.
  Future<void> _enregistrer() async {
    final bande = _bande;
    if (bande == null) {
      ToastAgri.afficher(context, "Sélectionnez d'abord une bande.", type: TypeToast.erreur);
      return;
    }
    // 🔁 VOL-1 — `saveDay()` : fiche d'AVANT le ticket (morts / dons / ventes non ventilés) : on ne devine pas la
    // catégorie, on le dit. (Les autres refus — jour avant le départ, départ absent ou incohérent, passage > source —
    // sont levés par le dépôt, avec les motifs du web.)
    final cat = _categoriesJour;
    if ((_mortEnregistre != null && _morts.values.fold(0, (a, b) => a + b) == 0) ||
        (_donEnregistre != null && _dons.values.fold(0, (a, b) => a + b) == 0)) {
      ToastAgri.afficher(
        context,
        "Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les (Reproducteur / Jeune / Poussin) avant d'enregistrer.",
        type: TypeToast.erreur,
      );
      return;
    }
    if (cat.refusPassage != null) {
      ToastAgri.afficher(context, cat.refusPassage!, type: TypeToast.erreur);
      return;
    }
    try {
      await widget.depot.enregistrer(
        lotId: bande.id,
        jour: _jour,
        achat: _achat,
        ne: _poussinsNes,
        mort: _morts.values.fold(0, (a, b) => a + b),
        don: _dons.values.fold(0, (a, b) => a + b),
        ponteTotal: _oeufsCouves,
        poidsMoyen: FicheJournaliereRepository.poidsMoyen(
          poidsTotalG: _pesee ?? 0,
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
          departSaisi: cat.departRequis ? _departSaisi : null,
        ),
      );
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7, Q3) — `saveDay()` : fiche d'un exercice clos, motif R4 en toast d'erreur.
      if (mounted) ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    } on FicheRefusee catch (e) {
      // VOL-1 : départ, jour antérieur au départ, ventes non ventilées… — le motif du web, tel quel.
      if (mounted) ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    }
    if (!mounted) return;
    ToastAgri.afficher(context, 'Jour enregistré avec succès.');
    await _chargerJour();
  }

  /// Le tableau du mois du Blade : TOUS les jours du mois en cours ; une ligne touchée charge son jour (`loadDay`) ;
  /// la note du Blade ferme la carte.
  Widget _tableauMensuel() {
    final jours = _mois?.jours ?? const <JourFiche>[];
    final cellules = [for (final j in jours) j.cellules(EspeceFiche.reproducteurs)];
    final indexChoisi = jours.indexWhere((j) => j.jour == JournalStocks.jour(_jour));
    ColonneMensuelle colonne(
      String libelle,
      int rang, {
      double largeur = 1,
      bool gras = false,
      Color? Function(int)? couleur,
      bool Function(int)? grasSelon,
    }) => ColonneMensuelle(
      libelle: libelle,
      largeur: largeur,
      gras: gras,
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
      pied:
          'La ventilation Reproducteur / Jeune / Poussin des morts, des dons et des ventes est conservée par catégorie '
          "(ticket VOL-1) — le tableau mensuel en affiche le cumul.",
      clePied: const Key('note-ventilation-morts'),
      dateDe: (i) => jours[i].date,
      onOuvrirJour: (i) => _ouvrirJour(jours[i].jour),
      groupes: [
        GroupeColonnes(libelle: 'Couvoir', colonnes: [colonne('Couvés', 0), colonne('Nés', 1)]),
        GroupeColonnes(
          libelle: 'Morts (total)',
          colonnes: [
            colonne(
              'Reproducteur+Jeune+Poussin',
              2,
              largeur: 2,
              couleur: (i) => mort(i) ? AgriColors.errorDeep : null,
              grasSelon: mort,
            ),
          ],
        ),
      ],
      colonnesSimples: [
        colonne('Effectif Final', 3, largeur: 1.3, gras: true),
        colonne(
          'Taux Mort %',
          4,
          largeur: 1.2,
          couleur: (i) => taux(i) ? AgriColors.errorDeep : null,
          grasSelon: taux,
        ),
        colonne('Poids Général (g)', 5, largeur: 1.4),
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
