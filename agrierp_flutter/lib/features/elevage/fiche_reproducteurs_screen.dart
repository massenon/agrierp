import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/export/document_officiel.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/tableau_mensuel.dart';
import '../../core/widgets/toast_agri.dart';
import '../stocks/journal_stocks.dart';
import '../stocks/pmp_service.dart';
import 'elements_fiche.dart';
import 'fiche_journaliere_repository.dart';
import 'mois_fiche.dart';
import 'ration_volaille.dart';
import 'soins_repository.dart';

/// `fiche-reproducteurs.blade.php` (web, `FicheReproducteurs`) → Fiches Volailles - Reproducteurs, Poussins & Goliath.
///
/// 🔴→✅ **TICKET U12a — LE BLADE EST LA RÉFÉRENCE DE MISE EN PAGE** (doctrine, article 5), et non plus la maquette
/// `fiche-volailles-reproducteurs.html`. Sections du Blade, dans son ordre, libellés au mot près :
///   1. en-tête, sous-titre, « Exporter PDF » ; 2. quatre cartes du MOIS, avec leurs légendes ;
///   3. sans bande : « Aucune bande active (Reproducteurs/Goliath/Poussins) pour le moment. » ;
///   4. carte « Saisie Journalière Couvoir & Suivi Chair » (« Date : » seul) : transferts du jour ; « Bande / Lot
///      Concerné » · Achats du jour · Ventes (POS, réel) ; **Workflow Couvoir & Éclosion** ; Morts par catégorie ;
///      Dons par catégorie ; « Effectif Final » et taux de mortalité ; rationnement par stade (`x-ration-volaille`) ;
///      pesée ; Traitements & Prophylaxie (protocole du jour, « Observations ») ; « Enregistrer ce Jour » ;
///   5. le tableau du mois (TOUS les jours), et sa note sur la ventilation des morts.
///
/// Retirés avec la maquette : « Taille Échantillon » de la pesée, « Attribution Bâtiments & Parcs Volailles
/// Traités », « Réinitialiser », le « Jour N » du titre et des lignes du tableau.
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
    this.maintenant,
  });

  final FicheJournaliereRepository depot;
  final SoinsRepository soins;

  /// « Exporter PDF » — `EditeursRapports.imprimer` en production, un espion en test ; `null` : bouton inerte.
  final Future<String?> Function(DocumentOfficiel document, DateTime maintenant)? imprimer;
  final VoidCallback? onOuvrirTransferts;

  /// Horloge injectable : le mois du tableau et des cartes est celui de MAINTENANT (`now()` du web).
  final DateTime Function()? maintenant;

  @override
  State<FicheReproducteursScreen> createState() => _FicheReproducteursScreenState();
}

class _FicheReproducteursScreenState extends State<FicheReproducteursScreen> {
  /// Catégories des morts et des dons du Blade (15.56), dans son ordre.
  static const _categories = [('repro', 'Repro'), ('poulet', 'Poulet'), ('poussin', 'Poussin')];

  List<LivestockLot> _bandes = const [];
  LivestockLot? _bande;
  late DateTime _jour;
  bool _chargement = true;
  DonneesMoisFiche? _mois;
  List<FeedRationStandard> _rations = const [];

  int _precedent = 0;
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
    if (!mounted) return;
    setState(() {
      _bandes = bandes;
      _bande = bandes.isEmpty ? null : bandes.first;
      _rations = rations;
    });
    await _chargerJour();
  }

  /// `loadDay()` : la fiche de la bande à CETTE date, quel que soit le mois ; à l'ouverture (`mount()`) et à chaque
  /// changement de date ou de bande (🔴→✅ U12a, corrigé aussi au web) ; morts et dons enregistrés gardés en total.
  Future<void> _chargerJour() async {
    final bande = _bande;
    final mois = await MoisFiche.charger(
      widget.depot.database,
      espece: EspeceFiche.reproducteurs,
      bandes: _bandes,
      bande: bande,
      maintenant: _maintenant,
    );
    final precedent = bande == null ? 0 : await widget.depot.effectifPrecedent(bande.id, _jour);
    final fiche = bande == null ? null : await widget.depot.chargerJour(bande.id, _jour);
    final protocole = bande == null
        ? null
        : await widget.soins.protocoleDuJour(bande: bande, codeEspece: 'aviculture', quand: _jour);
    if (!mounted) return;
    setState(() {
      _mois = mois;
      _precedent = precedent;
      _fiche = fiche;
      _protocole = protocole;
      // Une case cochée ne survit pas à un changement de jour.
      _coches.clear();
      _morts.updateAll((_, _) => 0);
      _dons.updateAll((_, _) => 0);
      _mortEnregistre = (fiche?.mort ?? 0) > 0 ? fiche!.mort : null;
      _donEnregistre = (fiche?.don ?? 0) > 0 ? fiche!.don : null;
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

  /// Option du sélecteur : `{{ $lot->code }} ({{ ucfirst($lot->stage) }} — {{ $lot->current_quantity }} têtes)`.
  static String libelleBande(LivestockLot b) {
    final stade = b.stage ?? '';
    final majuscule = stade.isEmpty ? '' : stade[0].toUpperCase() + stade.substring(1);
    return '${b.code} ($majuscule — ${b.currentQuantity} têtes)';
  }

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
    final moyen = _pesee == null || _pesee == 0 || _effectifFinal <= 0 ? '—' : '${(_pesee! / _effectifFinal).round()} g';
    return CarteSaisieFiche(
      // Le Blade n'a que « Date : » dans l'en-tête : la bande se choisit dans le formulaire.
      enTete: EnTeteSaisieFiche(titre: 'Saisie Journalière Couvoir & Suivi Chair', jour: _jour, onJour: _ouvrirJour),
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
            ChampLectureFiche(libelle: 'Ventes', suffixe: '(POS, réel)', valeur: '$_vente', cle: 'champ-ventes'),
          ],
        ),
        _workflowCouvoir(),
        BlocCategoriesFiche.morts(
          categories: _categories,
          valeurs: _morts,
          dejaEnregistres: _mortEnregistre,
          onChange: (c, v) => setState(() => _morts[c] = v),
        ),
        BlocCategoriesFiche.dons(
          categories: _categories,
          valeurs: _dons,
          dejaEnregistres: _donEnregistre,
          onChange: (c, v) => setState(() => _dons[c] = v),
        ),
        BlocEffectifFiche(
          titreEffectif: 'Effectif Final',
          formuleEffectif: '= Effectif (J-1) + Achats/Poussins Nés − (Morts + Ventes + Dons)',
          effectif: '$_effectifFinal',
          tauxMortalite: _pourcent(_tauxMortalite),
        ),
        // Ticket 15.57 — rationnement par stade, même règle que le web (`RationVolaille`).
        RationVolailleFiche(
          lignes: RationVolaille.lignes(_rations, RationVolaille.reproducteur, _effectifFinal),
          ligneCle: 'des reproducteurs',
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
    await widget.depot.enregistrer(
      lotId: bande.id,
      jour: _jour,
      achat: _achat,
      ne: _poussinsNes,
      mort: _totalMorts,
      don: _totalDons,
      ponteTotal: _oeufsCouves,
      poidsMoyen: FicheJournaliereRepository.poidsMoyen(
        poidsTotalG: _pesee ?? 0,
        tailleEchantillon: _effectifFinal,
      ),
    );
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
          "La ventilation Repro/Poulet/Poussin des morts n'est pas conservée séparément après enregistrement (seul le "
          "total est persisté, conforme au schéma) — affichée en cumul dans l'historique.",
      clePied: const Key('note-ventilation-morts'),
      dateDe: (i) => jours[i].date,
      onOuvrirJour: (i) => _ouvrirJour(jours[i].jour),
      groupes: [
        GroupeColonnes(libelle: 'Couvoir', colonnes: [colonne('Couvés', 0), colonne('Nés', 1)]),
        GroupeColonnes(
          libelle: 'Morts (total)',
          colonnes: [
            colonne(
              'Repro+Poulet+Poussin',
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
}
