import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/tableau_mensuel.dart';
import '../../core/widgets/toast_agri.dart';
import '../../core/export/document_officiel.dart';
import 'fiche_journaliere_repository.dart';
import 'gestion_elevage_screen.dart' show GestionElevageScreen;
import 'mois_pondeuses.dart';
import 'ration_volaille.dart';
import 'production_oeufs_service.dart';
import 'soins_repository.dart';
import '../stocks/journal_stocks.dart';
import '../stocks/pmp_service.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/comptabilite/exercice_de_saisie.dart';

/// `fiche-pondeuses.blade.php` (web, `FichePondeuses`) → Fiches Pondeuses - Aviculture.
///
/// 🔴→✅ **TICKET U11 — LE BLADE EST LA RÉFÉRENCE DE MISE EN PAGE** (doctrine, article 5), et non plus la maquette
/// `fiche-volailles-pondeuses.html`. Sections du Blade, dans son ordre, libellés au mot près :
///   1. en-tête « Fiches Pondeuses - Aviculture », sous-titre, bouton « Exporter PDF » (`exportFichePdf()`) ;
///   2. 4 cartes (Effectif Pondeuses Vivantes · Taux de Ponte Moyen · Stock Plateaux (30 œufs) · Taux de
///      Mortalité) — indicateurs du MOIS sur toutes les bandes de ponte ([MoisPondeuses.indicateurs]) ;
///   3. sans bande : la carte « Aucune bande active au stade Ponte pour le moment. » ;
///   4. carte « Saisie Journalière Ponte & Cheptel », avec « Bande : » (plusieurs bandes) et « Date : » ;
///   5. transferts entre bandes du jour (s'il y en a) ; Achats / Entrées · Nés / Transferts · Ventes (POS, réel) ;
///   6. **Workflow Récolte & Stock d'Œufs** ; 7. Morts par catégorie ; 8. Dons par catégorie ;
///   9. Effectif Final du Jour + Taux de Mortalité du Jour ; 10. Rationnement ; 11. Pesée ;
///  12. Stock Œufs & Plateaux (30) — Jour Sélectionné ; 13. **Traitements & Rappels** (protocole du jour,
///      « Observations ») ; 14. « Enregistrer ce Jour » ;
///  15. le tableau du mois : TOUS les jours du mois, « Traitements & Rappels » rempli ([MoisPondeuses]).
///
/// Retirés avec la maquette : « Réinitialiser » et « Attribution Bâtiments & Parcs Volailles Traités » (absents du
/// Blade), le « (COMBINE LES FICHES OFFICIELLES DE LA FERME) » du bloc œufs, « (Pré-rempli de J-1) » et « (Auto =
/// Effectif Final) » de la pesée, l'invite « Touchez un jour… » et le « Jour N » des lignes du tableau.
///
/// ⚠️ **« VENTES » EST EN LECTURE SEULE**, comme au web : la valeur vient de la CAISSE.
class FichePondeusesScreen extends StatefulWidget {
  const FichePondeusesScreen({
    super.key,
    required this.depot,
    required this.soins,
    required this.production,
    this.imprimer,
    this.onOuvrirTransferts,
    this.maintenant,
  });

  final FicheJournaliereRepository depot;
  final SoinsRepository soins;
  final ProductionOeufsService production;

  /// « Exporter PDF » — `EditeursRapports.imprimer` en production, un espion en test ; `null` : bouton inerte.
  /// ⚠️ Signature écrite ici (celle de `Editeur`) : importer l'écran des rapports ferait suivre ses tables (fournisseurs…)
  /// au périmètre de tirage de l'animalier (`perimetre_tirage_test.dart`).
  final Future<String?> Function(DocumentOfficiel document, DateTime maintenant)? imprimer;

  /// Lien « Transferts entre Bandes » de la mention des transferts du jour (`/transferts-bandes` au web).
  final VoidCallback? onOuvrirTransferts;

  /// Horloge injectable : le mois du tableau et des indicateurs est celui de MAINTENANT (`now()` du web).
  final DateTime Function()? maintenant;

  @override
  State<FichePondeusesScreen> createState() => _FichePondeusesScreenState();
}

class _FichePondeusesScreenState extends State<FichePondeusesScreen> {
  /// 🔁 F0.99 — catégories des MORTS du web (`fiche-pondeuses.blade.php`), libellés et ordre exacts ; les dons
  /// (15.56) ont les mêmes.
  static const _stades = ['Pondeuse / Repro', 'Poulette', 'Poussin'];

  static const _amber500 = Color(0xFFF59E0B);
  static const _amber700 = Color(0xFFB45309);
  static const _amber900 = Color(0xFF78350F);

  List<LivestockLot> _bandes = const [];
  LivestockLot? _bande;
  late DateTime _jour;
  bool _chargement = true;

  int _achat = 0;
  int _ne = 0;
  int _vente = 0;

  /// Ticket 15.46 — transferts entre bandes du jour (dérivés, jamais saisis ici) : comptés dans l'effectif.
  int _transfertEntree = 0;
  int _transfertSortie = 0;
  int _effectifPrecedent = 0;

  int _oeufsRecoltes = 0;
  int _oeufsCasses = 0;

  final _morts = <String, int>{for (final s in _stades) s: 0};

  /// 🔁 15.56 — dons par catégorie (mêmes catégories que les morts), comme le web.
  final _dons = <String, int>{for (final s in _stades) s: 0};

  /// 🔁 F0.99 — morts déjà enregistrés pour le jour rechargé (web 15.47 / 15.55) : la répartition n'est pas
  /// stockée, seul le total l'est. Sans lui, ré-enregistrer le jour remettait ses morts à zéro.
  int? _mortEnregistre;

  /// 🔁 15.56 — dons déjà enregistrés pour le jour rechargé (même règle que [_mortEnregistre]).
  int? _donEnregistre;

  List<FeedRationStandard> _rations = const [];

  /// Poids TOTAL pesé (g) — `$peseeTotal` du web, rechargé depuis la fiche (moyenne × effectif final).
  double _poidsTotalPese = 0;

  /// Ticket U10 — grand livre des stocks et produit œufs du web, relus à chaque chargement du jour.
  JournalStocks? _journal;
  String? _produitGrandLivre;
  Product? _produitOeufs;

  /// Ticket U11 — indicateurs, tableau et PDF du mois ([MoisPondeuses]).
  DonneesMoisPondeuses? _mois;

  ProtocoleDuJour? _protocole;
  final _traitementsCoches = <String>{};
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
    final toutes = await widget.depot.bandesActives();

    // ⚠️⚠️ **ESPÈCE, STADE ET STATUT, comme le web** (`aviculture`, stade `ponte`, statut `actif`, par code). Le stade
    // seul ne suffit pas : une bande d'ESCARGOTS au stade « ponte » serait apparue sur la fiche Pondeuses.
    final bandes = toutes
        .where(
          (b) =>
              b.speciesCode == 'aviculture' &&
              b.stage == 'ponte' &&
              (b.status == null || b.status == 'actif'),
        )
        .toList();
    final rations = await widget.depot.rations('aviculture');

    if (!mounted) return;

    setState(() {
      _bandes = bandes;
      _bande = bandes.isEmpty ? null : bandes.first;
      _rations = rations;
    });

    await _chargerJour();
  }

  Future<void> _chargerJour() async {
    final bande = _bande;
    final grandLivre = await widget.production.grandLivre();
    final produits = await widget.depot.database
        .select(widget.depot.database.products)
        .get();
    final mois = await MoisPondeuses.charger(
      widget.depot.database,
      bandes: _bandes,
      bande: bande,
      maintenant: _maintenant,
    );
    if (bande == null) {
      if (!mounted) return;
      setState(() {
        _mois = mois;
        _produitOeufs = JournalStocks.produitOeufs(produits);
        _chargement = false;
      });
      return;
    }

    setState(() => _chargement = true);

    final precedent = await widget.depot.effectifPrecedent(bande.id, _jour);
    final fiche = await widget.depot.chargerJour(bande.id, _jour);
    final protocole = await widget.soins.protocoleDuJour(
      bande: bande,
      codeEspece: 'aviculture',
      quand: _jour,
    );

    if (!mounted) return;

    setState(() {
      _effectifPrecedent = precedent;
      _mois = mois;
      _journal = grandLivre.journal;
      _produitGrandLivre = grandLivre.produit;
      _produitOeufs = JournalStocks.produitOeufs(produits);
      _achat = fiche?.achat ?? 0;
      _ne = fiche?.ne ?? 0;
      _vente = fiche?.vente ?? 0;
      _transfertEntree = fiche?.transfertEntree ?? 0;
      _transfertSortie = fiche?.transfertSortie ?? 0;
      _oeufsRecoltes = fiche?.ponteTotal ?? 0;
      _oeufsCasses = fiche?.ponteCasses ?? 0;
      // `loadDay()` : le poids général pesé revient de la fiche (moyenne × effectif final), sinon vide.
      final effectifFiche = fiche?.effectifFinal ?? 0;
      final moyenne = fiche?.weightSampleAvgG;
      _poidsTotalPese = moyenne != null && moyenne > 0 && effectifFiche > 0
          ? (moyenne * effectifFiche).roundToDouble()
          : 0;
      _protocole = protocole;
      // Les cases repartent vides à chaque changement de jour ou de bande (`traitementsCoches = []`).
      _traitementsCoches.clear();
      // ⚠️ Les morts et dons enregistrés ne sont pas ventilés par stade en base : la fiche ne porte qu'un total.
      for (final cle in _stades) {
        _morts[cle] = 0;
        _dons[cle] = 0;
      }
      _mortEnregistre = (fiche?.mort ?? 0) > 0 ? fiche!.mort : null;
      _donEnregistre = (fiche?.don ?? 0) > 0 ? fiche!.don : null;
      _chargement = false;
    });
  }

  // ── Calculs, ceux du composant web ────────────────────────────────────────

  /// Morts du jour : la répartition saisie, sinon le total déjà enregistré (`mortDuJour` du web).
  int get _totalMorts {
    final saisis = _morts.values.fold(0, (a, b) => a + b);
    return saisis > 0 ? saisis : (_mortEnregistre ?? 0);
  }

  /// 🔁 15.56 — dons du jour : la répartition saisie, sinon le total déjà enregistré (`donDuJour` du web).
  int get _totalDons {
    final saisis = _dons.values.fold(0, (a, b) => a + b);
    return saisis > 0 ? saisis : (_donEnregistre ?? 0);
  }

  /// `computeEffectifFinal(...)` : `max(0, …)`.
  int get _effectifFinal => FicheJournaliereRepository.calculerEffectifFinal(
    effectifPrecedent: _effectifPrecedent,
    achat: _achat,
    ne: _ne,
    mort: _totalMorts,
    vente: _vente,
    don: _totalDons,
    transfertEntree: _transfertEntree,
    transfertSortie: _transfertSortie,
  ).clamp(0, 1 << 30);

  int get _commercialisables => ProductionOeufsService.commercialisables(
    recoltes: _oeufsRecoltes,
    casses: _oeufsCasses,
  );

  ({int plateaux, int vrac}) get _plateaux =>
      ProductionOeufsService.enPlateaux(_commercialisables);

  /// 🔴→✅ Ticket U10 — `FichePondeuses::getStockTodayProperty()` : `EggStockLedgerService::ligne($selectedDate,
  /// $commercialisables)`. `null` tant que le grand livre n'est pas lu.
  LigneGrandLivreOeufs? get _stockDuJour =>
      _journal?.ligneOeufs(_produitGrandLivre, _jour, _commercialisables);

  /// 🔴→✅ Ticket U11 — `getTauxPonteCalcProperty()` : `round(OR ÷ effectif de la VEILLE × 100, 1)`, 0 sans effectif
  /// de veille. Le poste divisait par l'effectif FINAL (maquette) et affichait « — ».
  double get _tauxPonte => _effectifPrecedent > 0
      ? PmpService.arrondi(_oeufsRecoltes / _effectifPrecedent * 100, 1)
      : 0;

  /// `getMortalityRateCalcProperty()` : `round(morts ÷ effectif de la veille × 100, 1)`, 0 sans effectif de veille.
  double get _tauxMortalite => _effectifPrecedent > 0
      ? PmpService.arrondi(_totalMorts / _effectifPrecedent * 100, 1)
      : 0;

  /// `number_format($x, 1, ',', ' ').' %'`.
  static String _pourcent(double x) => '${PmpService.nombre(x, 1)} %';

  /// 🔁 15.57 — lignes du rationnement, règle commune au web (`RationVolaille`).
  List<LigneRationVolaille> get _lignesRation =>
      RationVolaille.lignes(_rations, RationVolaille.pondeuse, _effectifFinal);

  // ── Rendu ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _enTete(large),
            const SizedBox(height: AgriSpacing.lg),
            _cartesKpi(),
            const SizedBox(height: AgriSpacing.lg),
            if (_bande == null && !_chargement)
              _messageAucuneBande()
            else ...[
              _carteSaisie(large),
              const SizedBox(height: AgriSpacing.lg),
              // `hidden lg:block` : le tableau du mois n'existe qu'à partir de 1 024 px, comme au web.
              if (large) _tableauMensuel(),
            ],
          ],
        ),
      ),
    );
  }

  /// En-tête du Blade : titre et icône `egg`, sous-titre, « Exporter PDF » à droite (bord fin, arrondi complet).
  Widget _enTete(bool large) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AgriSpacing.sm,
      spacing: AgriSpacing.sm,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(SymbolesAgri.egg, color: AgriColors.brandEmerald, size: 26),
                const SizedBox(width: AgriSpacing.xs),
                Text(
                  'Fiches Pondeuses - Aviculture',
                  style: TextStyle(
                    fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.xs),
            const Text(
              "Suivi quotidien de la ponte et récolte d'œufs — transcription fidèle du registre de la ferme.",
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ],
        ),
        OutlinedButton.icon(
          key: const Key('pondeuses-exporter-pdf'),
          onPressed: widget.imprimer == null || _mois == null ? null : _exporter,
          icon: const Icon(SymbolesAgri.picture_as_pdf, size: 18),
          label: const Text(
            'Exporter PDF',
            style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AgriColors.brandForest,
            backgroundColor: AgriColors.surfaceCard,
            side: const BorderSide(color: AgriColors.outlineVariant),
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.md,
              vertical: AgriSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AgriRadius.full),
            ),
          ),
        ),
      ],
    ),
  );

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

  /// Les quatre `x-kpi-card` du Blade (`grid-cols-2 md:grid-cols-4 gap-md`) : icône et liseré de la variante
  /// (emerald, blue, maize, red) ; « Stock Plateaux » en attente sans produit œufs.
  Widget _cartesKpi() {
    final k = _mois?.indicateurs;
    return LayoutBuilder(
      builder: (context, contraintes) {
        final colonnes = AgriBreakpoints.moyen(context) ? 4 : 2;
        final largeur =
            (contraintes.maxWidth - (colonnes - 1) * AgriSpacing.md) / colonnes;
        Widget carte(
          String libelle,
          String valeur,
          IconData icone,
          Color lisere, {
          Color? couleurIcone,
          String? legende,
          bool enAttente = false,
        }) => SizedBox(
          width: largeur,
          child: CarteKpi(
            key: Key('kpi-$libelle'),
            libelle: libelle,
            valeur: valeur,
            icone: icone,
            couleurLisere: lisere,
            couleurIcone: couleurIcone ?? lisere,
            legende: legende,
            iconeLegende: enAttente ? SymbolesAgri.hourglass_empty : null,
            couleurValeur: enAttente
                ? AgriColors.outline.withValues(alpha: 0.5)
                : AgriColors.onSurface,
          ),
        );
        final stock = k?.stockPlateaux;
        return Wrap(
          spacing: AgriSpacing.md,
          runSpacing: AgriSpacing.md,
          children: [
            carte(
              'Effectif Pondeuses Vivantes',
              k?.effectif ?? '—',
              SymbolesAgri.pets,
              AgriColors.brandEmerald,
            ),
            carte(
              'Taux de Ponte Moyen',
              k?.tauxPonteMoyen ?? '—',
              SymbolesAgri.egg,
              AgriColors.infoBlue,
            ),
            carte(
              'Stock Plateaux (30 œufs)',
              stock ?? '—',
              SymbolesAgri.grid_view,
              AgriColors.accentYellow,
              couleurIcone: AgriColors.brandForest,
              legende: k != null && stock == null
                  ? 'Disponible après qu\'un produit "Œufs de table" existe au catalogue'
                  : null,
              enAttente: k != null && stock == null,
            ),
            carte(
              'Taux de Mortalité',
              k?.tauxMortaliteMois ?? '—',
              SymbolesAgri.trending_down,
              AgriColors.errorRed,
            ),
          ],
        );
      },
    );
  }

  /// Sans bande : la carte du Blade (`inbox`, message, lien vers « Bandes & Sujets », qui n'existe qu'au web).
  Widget _messageAucuneBande() => Container(
    padding: const EdgeInsets.all(AgriSpacing.lg),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      children: [
        const Icon(SymbolesAgri.inbox, size: 44, color: AgriColors.outlineVariant),
        const SizedBox(height: AgriSpacing.sm),
        const Text(
          'Aucune bande active au stade Ponte pour le moment.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AgriTypography.sm,
            fontWeight: FontWeight.w600,
            color: AgriColors.onSurface,
          ),
        ),
        const SizedBox(height: AgriSpacing.sm),
        InkWell(
          key: const Key('lien-bandes'),
          // `route('elevage.bandes')` : l'écran n'existe qu'au web — le poste le dit, comme Gestion Élevage.
          onTap: () => ToastAgri.afficher(
            context,
            GestionElevageScreen.messageBandesWeb,
            type: TypeToast.avertissement,
          ),
          child: const Text(
            'Créer une bande depuis Bandes & Sujets →',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              color: AgriColors.brandEmerald,
            ),
          ),
        ),
      ],
    ),
  );

  /// La carte de saisie du Blade (`bg-white rounded-lg border shadow-sm p-md lg:p-lg`).
  Widget _carteSaisie(bool large) => Container(
    padding: EdgeInsets.all(large ? AgriSpacing.lg : AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      boxShadow: AgriShadows.sm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _enTeteSaisie(),
        const SizedBox(height: AgriSpacing.md),
        if (_transfertEntree > 0 || _transfertSortie > 0) ...[
          _transfertsDuJour(),
          const SizedBox(height: AgriSpacing.md),
        ],
        _entreesEtVentes(),
        const SizedBox(height: AgriSpacing.md),
        _workflowOeufs(),
        const SizedBox(height: AgriSpacing.md),
        _blocCategories(
          titre: 'Morts par catégorie',
          icone: SymbolesAgri.skull,
          couleur: AgriColors.errorDeep,
          fond: AgriColors.errorBg.withValues(alpha: 0.3),
          bord: AgriColors.errorRed.withValues(alpha: 0.2),
          valeurs: _morts,
          dejaEnregistre: _mortEnregistre,
          cleMention: 'morts-enregistres',
          mention: (n) =>
              '$n mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : '
              "ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.",
        ),
        const SizedBox(height: AgriSpacing.md),
        _blocCategories(
          titre: 'Dons par catégorie',
          icone: SymbolesAgri.redeem,
          couleur: AgriColors.brandEmerald,
          fond: AgriColors.brandEmerald.withValues(alpha: 0.05),
          bord: AgriColors.brandEmerald.withValues(alpha: 0.2),
          valeurs: _dons,
          dejaEnregistre: _donEnregistre,
          cleMention: 'dons-enregistres',
          mention: (n) =>
              '$n don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : '
              "ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.",
        ),
        const SizedBox(height: AgriSpacing.md),
        _effectif(),
        const SizedBox(height: AgriSpacing.md),
        _rationnement(),
        const SizedBox(height: AgriSpacing.md),
        _pesee(),
        const SizedBox(height: AgriSpacing.md),
        _stockOeufsDuJour(),
        const SizedBox(height: AgriSpacing.md),
        _traitementsEtRappels(),
        const SizedBox(height: AgriSpacing.md),
        _boutons(),
      ],
    ),
  );

  /// « Saisie Journalière Ponte & Cheptel » (`edit_note`), puis à droite « Bande : » (s'il y a plusieurs bandes,
  /// ticket 15.47) et « Date : ».
  Widget _enTeteSaisie() => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AgriSpacing.xs,
      runSpacing: AgriSpacing.xs,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(SymbolesAgri.edit_note, color: AgriColors.brandEmerald),
            SizedBox(width: AgriSpacing.xs),
            Text(
              'Saisie Journalière Ponte & Cheptel',
              style: TextStyle(
                fontSize: AgriTypography.base,
                fontWeight: AgriTypography.gras,
                color: AgriColors.brandForest,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: AgriSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_bandes.length > 1) ...[
              _etiquetteEnLigne('Bande :'),
              _cadreSelection(
                cle: 'bande-fiche',
                enfant: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _bande?.id,
                    isDense: true,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandForest,
                    ),
                    items: [
                      for (final b in _bandes)
                        DropdownMenuItem(value: b.id, child: Text(b.code)),
                    ],
                    onChanged: (id) async {
                      setState(() => _bande = _bandes.firstWhere((b) => b.id == id));
                      await _chargerJour();
                    },
                  ),
                ),
              ),
            ],
            _etiquetteEnLigne('Date :'),
            _cadreSelection(
              cle: 'date-fiche',
              enfant: InkWell(
                onTap: () async {
                  final choisie = await showDatePicker(
                    context: context,
                    initialDate: _jour,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    locale: const Locale('fr'),
                  );
                  if (choisie != null) await _ouvrirJour(choisie);
                },
                child: Text(
                  _dateLongue(_jour),
                  key: const Key('date-choisie'),
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  static String _dateLongue(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _etiquetteEnLigne(String texte) => Text(
    texte,
    style: const TextStyle(
      fontSize: AgriTypography.xs,
      fontWeight: FontWeight.w600,
      color: AgriColors.outline,
    ),
  );

  /// `h-9 px-md border rounded-lg bg-surface-zebra` des deux sélecteurs.
  Widget _cadreSelection({required String cle, required Widget enfant}) => Container(
    key: Key(cle),
    height: 36,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceZebra,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: enfant,
  );

  /// `components/transferts-du-jour.blade.php` (ticket 15.46) : rien les jours sans transfert.
  Widget _transfertsDuJour() {
    final morceaux = <InlineSpan>[
      const TextSpan(text: 'Transferts entre bandes ce jour : '),
      if (_transfertEntree > 0) ...[
        TextSpan(
          text: '+$_transfertEntree',
          style: const TextStyle(fontWeight: AgriTypography.gras),
        ),
        const TextSpan(text: ' entré(s)'),
      ],
      if (_transfertEntree > 0 && _transfertSortie > 0) const TextSpan(text: ' ; '),
      if (_transfertSortie > 0) ...[
        TextSpan(
          text: '−$_transfertSortie',
          style: const TextStyle(fontWeight: AgriTypography.gras),
        ),
        const TextSpan(text: ' sorti(s)'),
      ],
      const TextSpan(
        text: " — compris dans l'effectif final. Ils se modifient depuis l'écran ",
      ),
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: InkWell(
          key: const Key('lien-transferts'),
          onTap: widget.onOuvrirTransferts,
          child: const Text(
            'Transferts entre Bandes',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: AgriTypography.gras,
              decoration: TextDecoration.underline,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ),
      const TextSpan(text: '.'),
    ];
    return Container(
      key: const Key('transferts-du-jour'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(SymbolesAgri.swap_horiz, size: 16, color: AgriColors.brandEmerald),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(children: morceaux),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.brandForest,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entreesEtVentes() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _champNombre(
            libelle: 'Achats / Entrées du jour',
            cle: 'achat',
            valeur: _achat,
            surChangement: (v) => setState(() => _achat = v),
          ),
        ),
        const SizedBox(width: AgriSpacing.md),
        Expanded(
          child: _champNombre(
            libelle: 'Nés / Transferts du jour',
            cle: 'ne',
            valeur: _ne,
            surChangement: (v) => setState(() => _ne = v),
          ),
        ),
        const SizedBox(width: AgriSpacing.md),
        Expanded(
          child: _champLecture(
            libelle: 'Ventes',
            suffixe: '(POS, réel)',
            valeur: '$_vente',
            cle: 'champ-ventes',
          ),
        ),
      ],
    );
  }

  /// Étiquette de champ du Blade (`text-[10px] text-brand-forest font-bold uppercase`).
  Widget _etiquette(String libelle, {String? suffixe}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 3,
      children: [
        Text(
          libelle.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
        if (suffixe != null)
          Text(
            suffixe,
            style: const TextStyle(fontSize: 9, color: AgriColors.outline),
          ),
      ],
    ),
  );

  Widget _champNombre({
    required String libelle,
    required String cle,
    required int valeur,
    required ValueChanged<int> surChangement,
    bool gras = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _etiquette(libelle),
        SizedBox(
          height: 40,
          child: TextFormField(
            key: Key('champ-$cle-$valeur'),
            initialValue: valeur == 0 ? '' : '$valeur',
            keyboardType: TextInputType.number,
            style: TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: gras ? AgriTypography.gras : AgriTypography.normal,
              color: gras ? AgriColors.brandForest : AgriColors.onSurface,
            ),
            decoration: const InputDecoration(
              hintText: '0',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(),
            ),
            onChanged: (t) => surChangement(int.tryParse(t) ?? 0),
          ),
        ),
      ],
    );
  }

  Widget _champLecture({
    required String libelle,
    String? suffixe,
    required String valeur,
    required String cle,
    Color couleur = AgriColors.outline,
    bool gras = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _etiquette(libelle, suffixe: suffixe),
        Container(
          height: 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AgriColors.surfaceZebra,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Text(
            valeur,
            key: Key(cle),
            style: TextStyle(
              fontSize: AgriTypography.sm,
              color: couleur,
              fontWeight: gras ? AgriTypography.gras : AgriTypography.normal,
            ),
          ),
        ),
      ],
    );
  }

  /// « Workflow Récolte & Stock d'Œufs » — le bloc ambre du Blade.
  Widget _workflowOeufs() {
    final plateaux = _plateaux;
    final produit = _produitOeufs;

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: _amber500.withValues(alpha: 0.10),
        border: Border.all(color: _amber500.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(SymbolesAgri.egg, size: 18, color: _amber700),
              const SizedBox(width: AgriSpacing.xs),
              Text(
                "Workflow Récolte & Stock d'Œufs".toUpperCase(),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: _amber900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _champNombre(
                  libelle: 'Total Œufs Récoltés (OR)',
                  cle: 'oeufs-pondus',
                  valeur: _oeufsRecoltes,
                  gras: true,
                  surChangement: (v) => setState(() => _oeufsRecoltes = v),
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _champNombre(
                  libelle: 'Œufs Cassés / Fêlés (OF)',
                  cle: 'oeufs-casses',
                  valeur: _oeufsCasses,
                  surChangement: (v) => setState(() => _oeufsCasses = v),
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _champLecture(
                  libelle: 'Commercialisables (OR-OF)',
                  valeur: '$_commercialisables',
                  cle: 'champ-commercialisables',
                  couleur: AgriColors.brandEmerald,
                  gras: true,
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _champLecture(
                  libelle: 'Taux de Ponte Calculé (%)',
                  valeur: _pourcent(_tauxPonte),
                  cle: 'champ-taux-ponte',
                  couleur: AgriColors.brandEmerald,
                  gras: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _encartOeufs(
                  'Plateaux Nets Générés (30 œufs/plateau) : ',
                  '${plateaux.plateaux} Plateaux (${plateaux.vrac} œufs vrac)',
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              // `@if($this->eggProduct)` : le nom du produit œufs du web, sinon la mention du Blade.
              Expanded(
                child: produit == null
                    ? _encartOeufs(
                        '',
                        null,
                        mention:
                            'Aucun produit "Œufs de table" trouvé au catalogue — le stock ne sera pas incrémenté.',
                      )
                    : _encartOeufs(
                        'Incrémentation Automatique du Stock : ',
                        '+${plateaux.plateaux} Plateaux (${produit.name})',
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _encartOeufs(String libelle, String? valeur, {String? mention}) {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.w600,
            color: AgriColors.brandForest,
          ),
          children: [
            if (mention != null)
              TextSpan(
                text: mention,
                style: const TextStyle(color: AgriColors.outline),
              )
            else ...[
              TextSpan(text: libelle),
              TextSpan(
                text: valeur,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandEmerald,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Morts (ou dons) par catégorie : le bloc du Blade, la mention des morts / dons déjà enregistrés DEDANS, sous le
  /// titre.
  Widget _blocCategories({
    required String titre,
    required IconData icone,
    required Color couleur,
    required Color fond,
    required Color bord,
    required Map<String, int> valeurs,
    required int? dejaEnregistre,
    required String cleMention,
    required String Function(int) mention,
  }) {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: fond,
        border: Border.all(color: bord),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icone, size: 16, color: couleur),
              const SizedBox(width: AgriSpacing.xs),
              Text(
                titre.toUpperCase(),
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: couleur,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          if (dejaEnregistre != null) ...[
            Container(
              key: Key(cleMention),
              padding: const EdgeInsets.all(AgriSpacing.xs),
              decoration: BoxDecoration(
                color: AgriColors.accentYellow.withValues(alpha: 0.2),
                border: Border.all(color: AgriColors.accentYellow),
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
              child: Text(
                mention(dejaEnregistre),
                style: const TextStyle(fontSize: 11, color: AgriColors.brandForest),
              ),
            ),
            const SizedBox(height: AgriSpacing.xs),
          ],
          Row(
            children: [
              for (final stade in _stades) ...[
                Expanded(child: _compteur(stade, valeurs)),
                if (stade != _stades.last)
                  const SizedBox(width: AgriSpacing.sm),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _compteur(String categorie, Map<String, int> valeurs) {
    final valeur = valeurs[categorie] ?? 0;

    return Column(
      children: [
        Text(
          categorie.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Row(
            children: [
              _pas(categorie, valeurs, -1, '−'),
              Expanded(
                child: Center(
                  child: Text(
                    '$valeur',
                    key: Key(
                      'compteur-${valeurs == _morts ? 'mort' : 'don'}-$categorie',
                    ),
                    style: const TextStyle(
                      fontSize: AgriTypography.sm,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.onSurface,
                    ),
                  ),
                ),
              ),
              _pas(categorie, valeurs, 1, '+'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pas(
    String categorie,
    Map<String, int> valeurs,
    int pas,
    String signe,
  ) {
    return InkWell(
      key: Key('pas-${valeurs == _morts ? 'mort' : 'don'}-$categorie-$pas'),
      onTap: () => setState(() {
        final actuel = valeurs[categorie] ?? 0;
        // `max(0, … - 1)` du Blade : jamais en dessous de zéro.
        valeurs[categorie] = (actuel + pas).clamp(0, 1 << 30);
      }),
      child: Container(
        width: 32,
        height: 34,
        alignment: Alignment.center,
        color: AgriColors.surfaceZebra,
        child: Text(
          signe,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
      ),
    );
  }

  /// Le bloc du Blade : fond zébré, deux colonnes (libellé, formule, valeur dans un encadré blanc).
  Widget _effectif() {
    Widget colonne(String titre, String formule, String valeur, Color couleur, Key cle) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titre.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
        Text(formule, style: const TextStyle(fontSize: 10, color: AgriColors.outline)),
        const SizedBox(height: 4),
        Container(
          height: 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            borderRadius: BorderRadius.circular(AgriRadius.lg),
            boxShadow: AgriShadows.sm,
          ),
          child: Text(
            valeur,
            key: cle,
            style: TextStyle(
              fontSize: AgriTypography.base,
              fontWeight: FontWeight.w900,
              color: couleur,
            ),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: colonne(
              'Effectif Final du Jour',
              '= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)',
              '$_effectifFinal',
              AgriColors.brandEmerald,
              const Key('effectif-final'),
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          Expanded(
            child: colonne(
              'Taux de Mortalité du Jour (%)',
              '= (Morts du Jour ÷ Effectif J-1) × 100',
              _pourcent(_tauxMortalite),
              AgriColors.errorDeep,
              const Key('taux-mortalite-jour'),
            ),
          ),
        ],
      ),
    );
  }

  /// `components/ration-volaille.blade.php` (ticket 15.57) — même tableau que le web, « — » sans ligne du barème.
  Widget _rationnement() {
    final lignes = _lignesRation;
    const titre = Row(
      children: [
        Icon(SymbolesAgri.restaurant, size: 16, color: AgriColors.brandEmerald),
        SizedBox(width: AgriSpacing.xs),
        Expanded(
          child: Text(
            'RATIONNEMENT & PROVENDE SERVIE PAR STADE (EN GRAMMES G/J)',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    );

    if (lignes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titre,
          const SizedBox(height: AgriSpacing.xs),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(
              color: AgriColors.surfaceZebra,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: const Text(
              "Aucune ration normative pour l'aviculture : renseignez le barème dans Paramètres Élevage > "
              'Rationnement.',
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titre,
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
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1.8),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(
                  color: AgriColors.surfaceZebra,
                  border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
                ),
                children: [
                  _Cellule("Stade / Tranche d'Âge", couleur: AgriColors.outline),
                  _Cellule('Effectif', centre: true, couleur: AgriColors.outline),
                  _Cellule('Ration Normative', centre: true, couleur: AgriColors.outline),
                  _Cellule('Provende Servie (g)', droite: true, couleur: AgriColors.outline),
                ],
              ),
              for (final l in lignes)
                TableRow(
                  children: [
                    _Cellule(l.libelle, gras: true, couleur: AgriColors.brandForest),
                    _Cellule(l.effectif == null ? '—' : '${l.effectif}', centre: true, gras: true),
                    _Cellule('${l.ration.round()} g/j', centre: true),
                    _Cellule(
                      l.totalG == null ? '—' : '${l.totalG!.round()} g',
                      droite: true,
                      gras: true,
                      couleur: AgriColors.brandEmerald,
                    ),
                  ],
                ),
              TableRow(
                decoration: BoxDecoration(
                  color: AgriColors.brandEmerald.withValues(alpha: 0.10),
                ),
                children: [
                  const _Cellule(
                    'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
                    gras: true,
                    taille: 10,
                    couleur: AgriColors.brandForest,
                  ),
                  const _Cellule(''),
                  const _Cellule(''),
                  _Cellule(
                    RationVolaille.totalAffiche(RationVolaille.totalG(lignes)),
                    key: const Key('total-provende'),
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
        const SizedBox(height: AgriSpacing.xs),
        if (RationVolaille.rattachee(lignes))
          const Text(
            "L'effectif n'est pas encore ventilé par stade : la fiche du jour n'en porte que le total. La ligne du "
            'stade de la bande (Pondeuse) le reçoit entièrement.',
            style: TextStyle(fontSize: 10, color: AgriColors.outline),
          )
        else
          const Text(
            'Aucune ligne du barème ne correspond du stade de la bande (Pondeuse) : ajoutez-la dans '
            'Paramètres Élevage > Rationnement pour calculer la provende.',
            key: Key('ration-non-rattachee'),
            style: TextStyle(fontSize: 10, color: AgriColors.errorDeep),
          ),
      ],
    );
  }

  /// Pesée du Blade : « Poids Général Pesé (g) », « Taille Échantillon », « Poids Moyen Constaté (Poids Général ÷
  /// Effectif Final) » — `round(pesée ÷ effectif final).' g'`, « — » sans pesée ou sans effectif.
  Widget _pesee() {
    final moyen = FicheJournaliereRepository.poidsMoyen(
      poidsTotalG: _poidsTotalPese,
      tailleEchantillon: _effectifFinal,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _etiquette('Poids Général Pesé (g)'),
              SizedBox(
                height: 40,
                child: TextFormField(
                  key: Key('champ-pesee-${_poidsTotalPese.round()}'),
                  initialValue: _poidsTotalPese == 0 ? '' : '${_poidsTotalPese.round()}',
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: AgriTypography.sm,
                    fontWeight: AgriTypography.gras,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'ex : 1800',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (t) => setState(() => _poidsTotalPese = double.tryParse(t) ?? 0),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AgriSpacing.md),
        Expanded(
          child: _champLecture(
            libelle: 'Taille Échantillon',
            valeur: '$_effectifFinal',
            cle: 'champ-taille-echantillon',
            couleur: AgriColors.onSurface,
            gras: true,
          ),
        ),
        const SizedBox(width: AgriSpacing.md),
        Expanded(
          child: _champLecture(
            libelle: 'Poids Moyen Constaté',
            suffixe: '(Poids Général ÷ Effectif Final)',
            valeur: moyen == null ? '—' : '${moyen.round()} g',
            cle: 'champ-poids-moyen',
            couleur: AgriColors.brandEmerald,
            gras: true,
          ),
        ),
      ],
    );
  }

  /// 🔴→✅ Ticket U10 — bloc « Stock Œufs & Plateaux (30) — Jour Sélectionné » du Blade : quatre encadrés « Stock
  /// Hier (SRH) », « Total Stock (TS) », « Sortie Vente (OS) », « Stock Final », valeurs de [_stockDuJour].
  Widget _stockOeufsDuJour() {
    final l = _stockDuJour;
    String v(double Function(LigneGrandLivreOeufs) champ) =>
        l == null ? '—' : PmpService.flottant(champ(l));

    Widget encadre(
      String cle,
      String libelle,
      String valeur, {
      Color couleur = AgriColors.brandForest,
      bool final_ = false,
    }) => Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: final_
            ? AgriColors.brandEmerald.withValues(alpha: 0.10)
            : AgriColors.surfaceCard,
        border: Border.all(
          color: final_
              ? AgriColors.brandEmerald.withValues(alpha: 0.20)
              : AgriColors.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        children: [
          Text(
            libelle.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: final_ ? AgriColors.brandForest : AgriColors.outline,
            ),
          ),
          Text(
            valeur,
            key: Key(cle),
            style: TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: FontWeight.bold,
              color: couleur,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(SymbolesAgri.inventory_2, size: 16, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              'Stock Œufs & Plateaux (30) — Jour Sélectionné'.toUpperCase(),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: AgriColors.brandForest,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        Row(
          children: [
            Expanded(child: encadre('stock-srh', 'Stock Hier (SRH)', v((l) => l.srh))),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(child: encadre('stock-ts', 'Total Stock (TS)', v((l) => l.ts))),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(
              child: encadre(
                'stock-os',
                'Sortie Vente (OS)',
                v((l) => l.os),
                couleur: AgriColors.outline,
              ),
            ),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(
              child: encadre(
                'stock-final',
                'Stock Final',
                v((l) => l.stockFinal),
                couleur: AgriColors.brandEmerald,
                final_: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Traitements & Rappels ─────────────────────────────────────────────────

  /// 🔴→✅ Ticket U11 — la section « Traitements & Rappels » du Blade (filet haut, `vaccines`) : le protocole du jour
  /// (`x-prophylaxie-du-jour`) puis le champ « Observations ». Le poste gardait le bloc de la maquette
  /// (« Traitements & Prophylaxie Avicole Automatiques Prévus pour ce Jour », « Observations Cliniques / Notes de
  /// l'Animalier »).
  Widget _traitementsEtRappels() {
    final protocole = _protocole;
    return Container(
      padding: const EdgeInsets.only(top: AgriSpacing.md),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(SymbolesAgri.vaccines, size: 18, color: AgriColors.infoBlue),
              const SizedBox(width: AgriSpacing.xs),
              Text(
                'Traitements & Rappels'.toUpperCase(),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandForest,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          if (protocole != null) _prophylaxieDuJour(protocole),
          const SizedBox(height: AgriSpacing.sm),
          _etiquette('Observations'),
          SizedBox(
            height: 40,
            child: TextField(
              key: const Key('champ-observations'),
              controller: _observations,
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: const InputDecoration(
                hintText: 'ex : RAS',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `components/prophylaxie-du-jour.blade.php` (ticket 15.35) : jour de cycle, badge d'état, lignes à cocher,
  /// entrées calendaires non évaluées, bouton de validation, « Indice Rouge ».
  Widget _prophylaxieDuJour(ProtocoleDuJour p) {
    // `$protocole->etat()` et les classes du badge (`$badges`).
    final (etat, fondBadge, texteBadge, bordBadge) = !p.determinable
        ? ('Indéterminé', AgriColors.errorBg, AgriColors.errorDeep, AgriColors.errorDeep.withValues(alpha: 0.3))
        : p.traitements.isEmpty
        ? ('Libre', AgriColors.surfaceZebra, AgriColors.outline, AgriColors.outlineVariant)
        : p.enAttente == 0
        ? (
            'Validé / Effectué',
            AgriColors.brandEmerald.withValues(alpha: 0.2),
            AgriColors.brandEmerald,
            AgriColors.brandEmerald,
          )
        : (
            '${p.traitements.length} Prévu(s)',
            AgriColors.accentYellow.withValues(alpha: 0.3),
            AgriColors.brandForest,
            AgriColors.accentYellow,
          );

    return Container(
      key: const Key('prophylaxie-du-jour'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.infoBlue.withValues(alpha: 0.05),
        border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.determinable
                      ? 'Jour ${p.jourDeCycle} du cycle de la bande'
                      : 'Jour de cycle inconnu',
                  style: const TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: fondBadge,
                  border: Border.all(color: bordBadge),
                  borderRadius: BorderRadius.circular(AgriRadius.full),
                ),
                child: Text(
                  etat,
                  key: const Key('etat-prophylaxie'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: texteBadge,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AgriSpacing.sm),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!p.determinable)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(SymbolesAgri.help, size: 16, color: AgriColors.errorDeep),
                      const SizedBox(width: AgriSpacing.xs),
                      Expanded(
                        child: Text(
                          'Protocole non calculable — ${p.motifIndetermine ?? ''} Consultez le registre avant toute '
                          'administration.',
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            color: AgriColors.errorDeep,
                          ),
                        ),
                      ),
                    ],
                  )
                else if (p.traitements.isEmpty)
                  const Text(
                    '— Aucun traitement récurrent programmé pour ce jour —',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontStyle: FontStyle.italic,
                      color: AgriColors.outline,
                    ),
                  )
                else
                  ...p.traitements.map(_ligneTraitement),
              ],
            ),
          ),
          if (p.calendairesNonEvalues > 0) ...[
            const SizedBox(height: AgriSpacing.sm),
            Text(
              '${p.calendairesNonEvalues} entrée(s) du protocole sans jour de cycle (calendaires, ex. « Le 1er du '
              'mois ») ne sont pas évaluées ici.',
              style: const TextStyle(fontSize: 10, color: AgriColors.outline),
            ),
          ],
          if (p.determinable && p.enAttente > 0) ...[
            const SizedBox(height: AgriSpacing.sm),
            const Text(
              'Valider un traitement rémanent bloque la vente de cette bande '
              "jusqu'à la fin du délai d'attente.",
              style: TextStyle(fontSize: 10, color: AgriColors.errorDeep),
            ),
            const SizedBox(height: AgriSpacing.xs),
            ElevatedButton.icon(
              key: const Key('bouton-valider-traitements'),
              onPressed: _validationEnCours ? null : _validerTraitements,
              icon: const Icon(SymbolesAgri.check_circle, size: 16),
              label: const Text(
                "Valider l'Administration de tous ces Traitements Aujourd'hui",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
              ),
            ),
          ],
          if (p.determinable && p.traitements.isNotEmpty) ...[
            const SizedBox(height: AgriSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: p.enAttente > 0
                      ? AgriColors.errorBg
                      : AgriColors.brandEmerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AgriRadius.full),
                ),
                child: Text(
                  'Indice Rouge : ${p.enAttente} soin(s) en attente',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: p.enAttente > 0 ? AgriColors.errorDeep : AgriColors.brandEmerald,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ligneTraitement(TraitementPrevu t) {
    final standard = t.standard;
    final details = [
      if ((standard.productRecommended ?? '').isNotEmpty)
        standard.productRecommended!,
      if ((standard.dosage ?? '').isNotEmpty) standard.dosage!,
    ].join(' — ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            height: 22,
            width: 22,
            child: Checkbox(
              value: t.dejaAdministre || _traitementsCoches.contains(standard.id),
              onChanged: t.dejaAdministre
                  ? null
                  : (coche) => setState(() {
                      if (coche == true) {
                        _traitementsCoches.add(standard.id);
                      } else {
                        _traitementsCoches.remove(standard.id);
                      }
                    }),
            ),
          ),
          const SizedBox(width: AgriSpacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: standard.treatment,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                      decoration: t.dejaAdministre
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  if (details.isNotEmpty)
                    TextSpan(
                      text: ' ($details)',
                      style: const TextStyle(color: AgriColors.outline),
                    ),
                ],
              ),
              style: const TextStyle(fontSize: AgriTypography.xs),
            ),
          ),
          if (t.remanenceJours > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AgriColors.errorBg,
                borderRadius: BorderRadius.circular(AgriRadius.full),
              ),
              child: Text(
                'Rémanence ${t.remanenceJours}j',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.errorDeep,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `AvecProphylaxieDuJour::validerTraitements()` : refus d'un jour à venir, puis l'écriture idempotente du dépôt,
  /// puis les toasts du web (succès « N traitement(s) enregistré(s) au registre vétérinaire. », ou avertissement
  /// quand rien n'était à enregistrer). Le bouton reste actif sans case cochée, comme au web.
  Future<void> _validerTraitements() async {
    // ⚠️ F0.93 : garde de l'écran (un second appel avant le setState), EN PLUS du dépôt, qui recalcule le protocole
    // sous transaction.
    if (_validationEnCours) return;
    final bande = _bande;
    if (bande == null || _protocole == null) return;

    final aujourdhui = DateTime(_maintenant.year, _maintenant.month, _maintenant.day);
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
      codeEspece: 'aviculture',
      quand: _jour,
      idsBareme: Set.of(_traitementsCoches),
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

  Widget _boutons() {
    return Container(
      padding: const EdgeInsets.only(top: AgriSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            key: const Key('bouton-enregistrer'),
            onPressed: _bande == null ? null : _enregistrer,
            icon: const Icon(SymbolesAgri.save, size: 16),
            label: const Text(
              'Enregistrer ce Jour',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Enregistre la fiche du jour et fait entrer les plateaux au stock local ; toast du web « Jour enregistré avec
  /// succès. ».
  ///
  /// ⚠️⚠️ **LE STOCK MONTE TOUT DE SUITE, PAS SEULEMENT APRÈS SYNCHRONISATION.** Le serveur produit bien l'effet à
  /// la réception (ticket 14.59), mais un poste peut rester des jours hors ligne : d'ici là, sa propre caisse
  /// refuserait de vendre des plateaux qu'il vient de récolter.
  Future<void> _enregistrer() async {
    final bande = _bande;
    if (bande == null) {
      ToastAgri.afficher(
        context,
        "Aucune bande active au stade Ponte. Créez d'abord une bande.",
        type: TypeToast.erreur,
      );
      return;
    }

    // ⚠️ La création se détermine AVANT l'écriture : après, la fiche existe toujours, et l'incrément se ferait à
    // chaque correction du même jour.
    final creation = await widget.depot.chargerJour(bande.id, _jour) == null;

    try {
      await widget.depot.enregistrer(
        lotId: bande.id,
        jour: _jour,
        achat: _achat,
        ne: _ne,
        mort: _totalMorts,
        don: _totalDons,
        ponteTotal: _oeufsRecoltes,
        ponteCasses: _oeufsCasses,
        poidsMoyen: FicheJournaliereRepository.poidsMoyen(
          poidsTotalG: _poidsTotalPese,
          tailleEchantillon: _effectifFinal,
        ),
      );
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7, Q3) — `saveDay()` : fiche d'un exercice clos, motif R4 en toast d'erreur ; les plateaux
      // n'entrent pas au stock (rien n'a été écrit).
      if (mounted) ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    }

    await widget.production.entrerAuStock(
      bande: bande,
      recoltes: _oeufsRecoltes,
      casses: _oeufsCasses,
      creation: creation,
    );

    if (!mounted) return;

    ToastAgri.afficher(context, 'Jour enregistré avec succès.');

    await _chargerJour();
  }

  // ── Tableau du mois ───────────────────────────────────────────────────────

  /// 🔴→✅ Ticket U11 — le tableau du mois du Blade : TOUS les jours du mois en cours (`range(1, daysInMonth)`), la
  /// ligne du jour choisi surlignée, une ligne touchée charge son jour (`loadDay`). Cellules de
  /// [JourPondeuses.cellules] ; SRH / TS / OS / Stock Final sur la seule ligne du jour choisi (U10) ; « Traitements &
  /// Rappels » = [MoisPondeuses.traitementsDuJour]. La note du Blade ferme la carte.
  Widget _tableauMensuel() {
    final jours = _mois?.jours ?? const <JourPondeuses>[];
    final jourChoisi = JournalStocks.jour(_jour);
    final indexChoisi = jours.indexWhere((j) => j.jour == jourChoisi);

    String grandLivre(int i, double Function(LigneGrandLivreOeufs) champ) {
      final l = _stockDuJour;
      if (l == null || i != indexChoisi) return '—';
      return PmpService.flottant(champ(l));
    }

    ColonneMensuelle cellule(
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
      valeur: (i) => jours[i].cellules[rang],
    );

    return TableauMensuel(
      key: const Key('tableau-mois-pondeuses'),
      libelleDate: 'Date / Jour',
      nombreDeJours: jours.length,
      jourActif: indexChoisi < 0 ? null : indexChoisi,
      zebre: false,
      invite: null,
      pied:
          'Colonnes SRH/TS/OS/Stock Final : valeurs précises uniquement pour le jour sélectionné (reconstruction '
          'historique jour par jour non disponible avant le Sprint 6 — grand livre de mouvements de stock).',
      clePied: const Key('note-grand-livre'),
      dateDe: (i) => jours[i].date,
      onOuvrirJour: (i) => _ouvrirJour(jours[i].jour),
      groupes: [
        GroupeColonnes(
          libelle: 'Cheptel du Jour',
          colonnes: [
            cellule('Eff. Début', 0, largeur: 1.2),
            // `text-error-deep font-bold` quand des morts sont comptés.
            cellule(
              'Morts',
              1,
              couleur: (i) => (jours[i].fiche?.mort ?? 0) > 0 ? AgriColors.errorDeep : null,
              grasSelon: (i) => (jours[i].fiche?.mort ?? 0) > 0,
            ),
            cellule('Taux Mort %', 2, largeur: 1.2),
            cellule('Eff. Fin', 3, gras: true),
          ],
        ),
        GroupeColonnes(
          libelle: 'Suivi de la Ponte & Récolte',
          colonnes: [
            cellule('Total (OR)', 4, largeur: 1.2),
            cellule('Taux Ponte %', 5, largeur: 1.3),
            cellule('Cassés (OF)', 6, largeur: 1.2),
            cellule('Comm. (OR-OF)', 7, largeur: 1.5, gras: true),
          ],
        ),
        // Ticket U10 — grand livre d'œufs : le jour sélectionné seulement, comme le web.
        GroupeColonnes(
          libelle: 'Stock Œufs & Plateaux (30)',
          colonnes: [
            ColonneMensuelle(
              libelle: 'SRH',
              largeur: 1.5,
              couleur: (_) => AgriColors.outline,
              valeur: (i) => grandLivre(i, (l) => l.srh),
            ),
            ColonneMensuelle(
              libelle: 'TS',
              largeur: 1.5,
              couleur: (_) => AgriColors.outline,
              valeur: (i) => grandLivre(i, (l) => l.ts),
            ),
            ColonneMensuelle(
              libelle: 'OS',
              largeur: 1.5,
              couleur: (_) => AgriColors.outline,
              valeur: (i) => grandLivre(i, (l) => l.os),
            ),
            ColonneMensuelle(
              libelle: 'Stock Final',
              largeur: 1.3,
              gras: true,
              couleur: (_) => AgriColors.brandEmerald,
              valeur: (i) => grandLivre(i, (l) => l.stockFinal),
            ),
          ],
        ),
      ],
      colonnesSimples: [
        ColonneMensuelle(
          libelle: 'Traitements & Rappels',
          largeur: 3,
          aGauche: true,
          couleur: (_) => AgriColors.outline,
          valeur: (i) => jours[i].traitements,
        ),
      ],
    );
  }

  /// ⚠️ CHARGE LA JOURNÉE DANS LE FORMULAIRE (`loadDay`).
  Future<void> _ouvrirJour(DateTime jour) async {
    setState(() => _jour = DateTime(jour.year, jour.month, jour.day));
    await _chargerJour();
  }
}

class _Cellule extends StatelessWidget {
  const _Cellule(
    this.texte, {
    super.key,
    this.centre = false,
    this.droite = false,
    this.gras = false,
    this.taille = AgriTypography.xs,
    this.couleur = AgriColors.onSurface,
  });

  final String texte;
  final bool centre;
  final bool droite;
  final bool gras;
  final double taille;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.xs),
      child: Text(
        texte,
        textAlign: centre
            ? TextAlign.center
            : droite
            ? TextAlign.right
            : TextAlign.start,
        style: TextStyle(
          fontSize: taille,
          fontWeight: gras ? FontWeight.bold : FontWeight.normal,
          color: couleur,
        ),
      ),
    );
  }
}
