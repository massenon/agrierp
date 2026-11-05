import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/tableau_mensuel.dart';
import '../../core/widgets/toast_agri.dart';
import '../../core/export/document_officiel.dart';
import 'autonomie_alimentaire_carte.dart';
import 'effectif_par_categorie.dart';
import 'elements_fiche.dart'
    show
        BlocCategoriesFiche,
        ChampLectureFiche,
        ChampSaisieFiche,
        EncadreFiche,
        EnTeteSaisieFiche,
        FormulaireFiche,
        GrilleFiche,
        LectureSeuleDuJour,
        MoisDeFiche,
        RationPondeusesFiche,
        TitreSectionFiche,
        ouvrirBandes;
import 'fiche_journaliere_repository.dart';
import 'jour_categories.dart';
import 'mois_pondeuses.dart';
import 'stade_pondeuse.dart';
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
///   9. Effectif Final du Jour + Taux de Mortalité du Jour ; 10. Rationnement PAR STADE (VOL-2) et autonomie
///      alimentaire ; 11. Pesée ;
///  12. Stock Œufs & Plateaux (30) — Jour Sélectionné ; 13. **Traitements & Rappels** (protocole du jour,
///      « Observations ») ; 14. « Enregistrer ce Jour » ;
///  15. le tableau du mois : TOUS les jours du mois, « Traitements & Rappels » rempli ([MoisPondeuses]).
///
/// Retirés avec la maquette : « Réinitialiser » et « Attribution Bâtiments & Parcs Volailles Traités » (absents du
/// Blade), le « (COMBINE LES FICHES OFFICIELLES DE LA FERME) » du bloc œufs, « (Pré-rempli de J-1) » et « (Auto =
/// Effectif Final) » de la pesée, l'invite « Touchez un jour… » et le « Jour N » des lignes du tableau.
///
/// ⚠️ **« VENTES » EST EN LECTURE SEULE**, comme au web : la valeur vient de la CAISSE.
///
/// 🔁 **TICKET VOL-2 (décision client du 05/11/2026) — EFFECTIF PAR STADE CALCULÉ**, comme la fiche Reproducteurs (VOL-1) :
/// QUATRE stades aux libellés EXACTS du barème (Poussin ponte, Poussin en croissance, Poulette, Pondeuse) ; calcul =
/// [EffectifParCategorie] (miroir du service PHP, parité exécutée). Départ OBLIGATOIRE avant toute journée (la fiche le
/// demande au lieu de l'effectif et refuse d'enregistrer), TROIS passages de stade saisissables, ventes par stade posées par
/// la caisse (en lecture seule), rationnement [StadePondeuse.tableau]. Les ŒUFS (récolte, casse, stock) ne changent pas.
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
  /// 🔁 VOL-2 — les QUATRE stades des morts, des dons, du départ et des ventes, dans l'ordre de la chaîne, aux libellés
  /// du barème. Clés = emplacements génériques de synchronisation : `quatre` = Poussin ponte, `sevre` = Poussin en
  /// croissance, `jeune` = Poulette, `repro` = Pondeuse.
  static final _stades = [
    ('quatre', StadePondeuse.libelle(StadePondeuse.poussinPonte)),
    ('sevre', StadePondeuse.libelle(StadePondeuse.poussinCroissance)),
    ('jeune', StadePondeuse.libelle(StadePondeuse.poulette)),
    ('repro', StadePondeuse.libelle(StadePondeuse.pondeuse)),
  ];

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

  /// Ticket VOL-2 — la fiche du jour (ventes par stade, transferts par stade) et l'état de la chaîne par stade.
  LivestockDailyEntry? _fiche;
  EtatJour? _etat;

  /// Passages du jour : 1 = Poussin ponte → Poussin en croissance, 2 = → Poulette, 3 = → Pondeuse.
  int _passage1 = 0;
  int _passage2 = 0;
  int _passage3 = 0;

  /// Départ saisi (début du jour de départ), par emplacement ; `null` = pas encore saisi.
  final _depart = <String, int?>{'quatre': null, 'sevre': null, 'jeune': null, 'repro': null};

  /// Produit de provende et son stock (carte d'autonomie alimentaire, VOL-2).
  Product? _produitProvende;
  double? _stockProvendeKg;

  /// Ticket 15.46 — transferts entre bandes du jour (dérivés, jamais saisis ici) : comptés dans l'effectif.
  int _transfertEntree = 0;
  int _transfertSortie = 0;
  int _effectifPrecedent = 0;

  int _oeufsRecoltes = 0;
  int _oeufsCasses = 0;

  final _morts = <String, int>{for (final (c, _) in _stades) c: 0};

  /// 🔁 15.56 — dons par catégorie (mêmes catégories que les morts), comme le web.
  final _dons = <String, int>{for (final (c, _) in _stades) c: 0};

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

  /// Ticket EX8 (EF12) — motif R4 de la lecture seule (exercice clos), `null` quand le jour se saisit.
  LectureSeuleDuJour? _lectureSeule;

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
    final db = widget.depot.database;
    final tousProduits = await db.select(db.products).get();
    final especes = await db.select(db.livestockSpecies).get();
    final types = await db.select(db.feedTypes).get();
    final produit = AutonomieAlimentaire.produitProvende('aviculture', tousProduits, especes);

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

  Future<void> _chargerJour() async {
    final bande = _bande;
    final grandLivre = await widget.production.grandLivre();
    final produits = await widget.depot.database
        .select(widget.depot.database.products)
        .get();
    // Ticket EX8 (EF12) : le mois AFFICHÉ est celui du jour choisi (`AvecMoisDeFiche` du web).
    final mois = await MoisPondeuses.charger(
      widget.depot.database,
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
        _produitOeufs = JournalStocks.produitOeufs(produits);
        _chargement = false;
      });
      return;
    }

    setState(() => _chargement = true);

    final precedent = await widget.depot.effectifPrecedent(bande.id, _jour);
    final fiche = await widget.depot.chargerJour(bande.id, _jour);
    final etat = await widget.depot.etatCategories(bande.id, _jour);
    final protocole = await widget.soins.protocoleDuJour(
      bande: bande,
      codeEspece: 'aviculture',
      quand: _jour,
    );

    if (!mounted) return;

    setState(() {
      _effectifPrecedent = precedent;
      _fiche = fiche;
      _etat = etat;
      _mois = mois;
      _lectureSeule = lectureSeule;
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
      // VOL-2 : la ventilation STOCKÉE recharge le jour ; une fiche d'AVANT le ticket (colonnes à null) garde son total, qui
      // doit être ventilé avant d'enregistrer. Le départ saisi (aperçu) ne survit pas à un changement de jour.
      for (final (cle, _) in _stades) {
        _morts[cle] = 0;
        _dons[cle] = 0;
        _depart[cle] = null;
      }
      _mortEnregistre = null;
      _donEnregistre = null;
      _passage1 = fiche?.passage4Sevre ?? 0;
      _passage2 = fiche?.passageSevreJeune ?? 0;
      _passage3 = fiche?.passageJeuneRepro ?? 0;
      if (fiche != null) {
        if (fiche.mortRepro != null && fiche.mortSevre != null && fiche.mortJeune != null && fiche.mort4 != null) {
          _morts
            ..['repro'] = fiche.mortRepro!
            ..['sevre'] = fiche.mortSevre!
            ..['jeune'] = fiche.mortJeune!
            ..['quatre'] = fiche.mort4!;
        } else {
          _mortEnregistre = fiche.mort > 0 ? fiche.mort : null;
        }
        if (fiche.donRepro != null && fiche.donSevre != null && fiche.donJeune != null && fiche.don4 != null) {
          _dons
            ..['repro'] = fiche.donRepro!
            ..['sevre'] = fiche.donSevre!
            ..['jeune'] = fiche.donJeune!
            ..['quatre'] = fiche.don4!;
        } else {
          _donEnregistre = fiche.don > 0 ? fiche.don : null;
        }
      }
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

  EffectifCategories get _departSaisi => EffectifCategories(
    repro: _depart['repro'],
    sevre: _depart['sevre'],
    jeune: _depart['jeune'],
    quatre: _depart['quatre'],
  );

  /// Ventes du jour par stade (colonnes `vente_*` posées par la caisse) ; 0 sans fiche.
  int get _venteRepro => _fiche?.venteRepro ?? 0;
  int get _venteSevre => _fiche?.venteSevre ?? 0;
  int get _venteJeune => _fiche?.venteJeune ?? 0;
  int get _vente4 => _fiche?.vente4 ?? 0;

  /// Vente d'AVANT le ticket : le total existe, sa répartition par stade non.
  bool get _venteNonVentilee => _fiche != null && _fiche!.vente > 0 && _fiche!.venteRepro == null;

  /// `getCategoriesJourProperty()` du web : effectifs par stade CALCULÉS (jamais saisis), départ, refus, avertissements.
  CategoriesJour get _categoriesJour {
    final bande = _bande;
    final f = _fiche;
    return CategoriesJour.calculerPondeuses(
      etat: bande == null ? null : _etat,
      departSaisi: _departSaisi,
      effectifPrecedent: _effectifPrecedent,
      mouvements: MouvementsJour(
        achat: _achat,
        ne: _ne,
        venteRepro: _venteRepro,
        venteSevre: _venteSevre,
        venteJeune: _venteJeune,
        vente4: _vente4,
        mortRepro: _morts['repro'],
        mortSevre: _morts['sevre'],
        mortJeune: _morts['jeune'],
        mort4: _morts['quatre'],
        donRepro: _dons['repro'],
        donSevre: _dons['sevre'],
        donJeune: _dons['jeune'],
        don4: _dons['quatre'],
        passage4Sevre: _passage1,
        passage: _passage2,
        passageJeuneRepro: _passage3,
        transfertEntreeRepro: f?.transfertEntreeRepro ?? 0,
        transfertEntreeSevre: f?.transfertEntreeSevre ?? 0,
        transfertEntreeJeune: f?.transfertEntreeJeune ?? 0,
        transfertEntree4: f?.transfertEntree4 ?? 0,
        transfertSortieRepro: f?.transfertSortieRepro ?? 0,
        transfertSortieSevre: f?.transfertSortieSevre ?? 0,
        transfertSortieJeune: f?.transfertSortieJeune ?? 0,
        transfertSortie4: f?.transfertSortie4 ?? 0,
      ),
      effectifFinal: _effectifFinal,
      jour: _jour,
      proposition: bande == null
          ? null
          : EffectifParCategorie.departDepuisStade(
              codeEspece: bande.speciesCode,
              stade: bande.stage,
              totalDebutJour: _effectifPrecedent,
            ),
    );
  }

  /// `getAvertissementMortsProperty()` (D9) : le plancher à 0 s'applique et l'écran le dit.
  String? get _avertissementMorts => _totalMorts > _effectifPrecedent
      ? "Morts du jour ($_totalMorts) supérieurs à l'effectif de la veille ($_effectifPrecedent) : l'effectif est ramené "
            'à 0, vérifiez la saisie.'
      : null;

  /// `appliquerPropositionDepart()` : reprend la proposition d'après le stade, sur demande de l'éleveur seulement.
  void _appliquerProposition(EffectifCategories p) => setState(() {
    _depart
      ..['repro'] = p.repro
      ..['sevre'] = p.sevre
      ..['jeune'] = p.jeune
      ..['quatre'] = p.quatre;
  });


  /// Départ obligatoire (saisi UNE fois par bande, verrouillé ensuite), motifs, refus de passage, avertissements — les blocs
  /// du Blade entre les passages et l'effectif final.
  List<Widget> _departEtAvertissements() {
    final cat = _categoriesJour;
    return [
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
          "Cette journée porte des ventes d'avant la mise en place des stades, non ventilées : elle ne peut pas être ré-enregistrée.",
        ),
      const SizedBox(height: AgriSpacing.md),
    ];
  }

  /// Bloc « Effectif de départ par stade (obligatoire) » du Blade : saisi UNE fois par bande, verrouillé ensuite.
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
          'Effectif de départ par stade (obligatoire)',
          icone: SymbolesAgri.edit_note,
          couleurIcone: AgriColors.brandEmerald,
          couleur: AgriColors.brandEmerald,
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          "Cette bande n'a pas encore d'effectif de départ : saisissez l'effectif de chaque stade au DÉBUT de ce jour, "
          "avant les mouvements du jour. La somme des quatre stades doit égaler l'effectif total au début du jour "
          "($_effectifPrecedent). Il est verrouillé au premier enregistrement ; la journée ne s'enregistre pas sans lui.",
          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.xs),
        GrilleFiche(
          colonnes: 4,
          ecart: AgriSpacing.sm,
          enfants: [
            for (final (cle, libelle) in _stades)
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
                "Reprendre la proposition d'après le stade de la bande "
                '(${StadePondeuse.libelle(StadePondeuse.pondeuse)} ${cat.proposition!.repro} · '
                '${StadePondeuse.libelle(StadePondeuse.poulette)} ${cat.proposition!.jeune} · '
                '${StadePondeuse.libelle(StadePondeuse.poussinCroissance)} ${cat.proposition!.sevre} · '
                '${StadePondeuse.libelle(StadePondeuse.poussinPonte)} ${cat.proposition!.quatre})',
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
        const TitreSectionFiche('Effectif de départ par stade (verrouillé)', icone: SymbolesAgri.lock),
        const SizedBox(height: AgriSpacing.xs),
        Text(
          'Effectif de départ fixé le ${EnTeteSaisieFiche.dateLongue(cat.departDate!)} (au début de ce jour).',
          style: const TextStyle(fontSize: 10, color: AgriColors.outline),
        ),
        const SizedBox(height: AgriSpacing.xs),
        GrilleFiche(
          colonnes: 4,
          ecart: AgriSpacing.sm,
          enfants: [
            for (final (cle, libelle) in _stades)
              ChampLectureFiche(
                libelle: libelle,
                valeur: '${switch (cle) {
                  'repro' => cat.depart!.repro,
                  'sevre' => cat.depart!.sevre,
                  'jeune' => cat.depart!.jeune,
                  _ => cat.depart!.quatre,
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
          // `route('elevage.bandes')` : « Bandes & Sujets » s'ouvre (ticket BS1) ; hors du socle, le repli le dit.
          onTap: () => ouvrirBandes(context),
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
        // Ticket EX8 (EF12) — `<x-bandeau-lecture-seule>` (le bandeau d'EX7, fusion EX7 + EX8) puis
        // `<fieldset disabled>` du Blade.
        if (_lectureSeule != null && _lectureSeule!.bandeauVisible(context)) ...[
          _lectureSeule!.bandeau(_ouvrirJour),
          const SizedBox(height: AgriSpacing.md),
        ],
        FormulaireFiche(
          lectureSeule: _lectureSeule != null,
          enfant: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        if (_transfertEntree > 0 || _transfertSortie > 0) ...[
          _transfertsDuJour(),
          const SizedBox(height: AgriSpacing.md),
        ],
        _entreesEtVentes(),
        const SizedBox(height: AgriSpacing.md),
        _workflowOeufs(),
        const SizedBox(height: AgriSpacing.md),
        BlocCategoriesFiche.morts(
          categories: _stades,
          valeurs: _morts,
          dejaEnregistres: _mortEnregistre,
          finMention: "ventilez-les ci-dessous (Poussin ponte / Poussin en croissance / Poulette / Pondeuse) avant d'enregistrer.",
          onChange: (c, v) => setState(() => _morts[c] = v),
        ),
        const SizedBox(height: AgriSpacing.md),
        BlocCategoriesFiche.dons(
          categories: _stades,
          valeurs: _dons,
          dejaEnregistres: _donEnregistre,
          finMention: "ventilez-les ci-dessous (Poussin ponte / Poussin en croissance / Poulette / Pondeuse) avant d'enregistrer.",
          onChange: (c, v) => setState(() => _dons[c] = v),
        ),
        const SizedBox(height: AgriSpacing.md),
        // VOL-2 — les TROIS passages de stade du jour (Poussin ponte → Poussin en croissance → Poulette → Pondeuse).
        GrilleFiche(
          colonnes: 3,
          enfants: [
            ChampSaisieFiche(
              libelle: 'Passage du jour (Poussin ponte → Poussin en croissance)',
              cle: 'passage-1',
              valeur: _passage1,
              onChange: (v) => setState(() => _passage1 = (v ?? 0).toInt()),
            ),
            ChampSaisieFiche(
              libelle: 'Passage du jour (Poussin en croissance → Poulette)',
              cle: 'passage-2',
              valeur: _passage2,
              onChange: (v) => setState(() => _passage2 = (v ?? 0).toInt()),
            ),
            ChampSaisieFiche(
              libelle: 'Passage du jour (Poulette → Pondeuse)',
              cle: 'passage-3',
              valeur: _passage3,
              onChange: (v) => setState(() => _passage3 = (v ?? 0).toInt()),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        ..._departEtAvertissements(),
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
        ),
      ],
    ),
  );

  /// « Saisie Journalière Ponte & Cheptel » (`edit_note`), puis à droite « Bande : » (s'il y a plusieurs bandes,
  /// ticket 15.47), « Date : » et « Mois : » — la MÊME barre que les quatre autres fiches (ticket MP1 : elle en était
  /// une copie aux valeurs en dur).
  Widget _enTeteSaisie() => EnTeteSaisieFiche(
    titre: 'Saisie Journalière Ponte & Cheptel',
    jour: _jour,
    onJour: (choisie) => _ouvrirJour(choisie),
    bandes: [for (final b in _bandes) (b.id, b.code)],
    bandeId: _bande?.id,
    onBande: (id) async {
      setState(() => _bande = _bandes.firstWhere((b) => b.id == id));
      await _chargerJour();
    },
    // Ticket EX8 (EF12) — `<x-mois-de-fiche>` : consulter un mois passé.
    maintenant: _maintenant,
    onMoisPrecedent: () => _ouvrirJour(MoisDeFiche.precedent(_jour)),
    onMoisSuivant: () {
      final suivant = MoisDeFiche.suivant(_jour, _maintenant);
      if (suivant != null) _ouvrirJour(suivant);
    },
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
          // VOL-2 : la caisse range chaque vente dans le stade du PRODUIT vendu (lecture seule).
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _champLecture(
                libelle: 'Ventes',
                suffixe: '(POS, réel)',
                valeur: '$_vente',
                cle: 'champ-ventes',
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [
                    for (final (cle, libelle) in _stades)
                      '$libelle ${switch (cle) {
                        'repro' => _venteRepro,
                        'sevre' => _venteSevre,
                        'jeune' => _venteJeune,
                        _ => _vente4,
                      }}',
                  ].join(' · '),
                  key: const Key('ventes-par-stade'),
                  style: const TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
              ),
            ],
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

  /// VOL-2 — rationnement PAR STADE (`fiche-pondeuses.blade.php`, qui remplace `components/ration-volaille.blade.php`) :
  /// effectif calculé de chaque stade × la ration de sa ligne du barème ([StadePondeuse.tableau]) ; la demande de départ
  /// tient lieu d'effectif tant qu'elle n'est pas valide.
  Widget _rationnement() {
    final cat = _categoriesJour;
    final tableau = cat.repro == null
        ? null
        : StadePondeuse.tableau(_rations, {
            'repro': cat.repro,
            'sevre': cat.sevre,
            'jeune': cat.jeune,
            'quatre': cat.quatre,
          });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RationPondeusesFiche(tableau: tableau),
        const SizedBox(height: AgriSpacing.md),
        // Autonomie alimentaire sur la provende du jour : SOMME des quatre stades (information, jamais un blocage).
        CarteAutonomieAlimentaire(
          autonomie: AutonomieAlimentaire.evaluer(_produitProvende, _stockProvendeKg, tableau?.totalKg),
          filiere: 'aviculture',
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
    if (!mounted) return;

    // 🔁 VOL-2 — `saveDay()` : fiche d'AVANT le ticket (morts / dons / ventes non ventilés) : on ne devine pas le stade, on
    // le dit. (Les autres refus — jour avant le départ, départ absent ou incohérent, passage > source — sont levés par le
    // dépôt, avec les motifs du web.)
    final cat = _categoriesJour;
    if ((_mortEnregistre != null && _morts.values.fold(0, (a, b) => a + b) == 0) ||
        (_donEnregistre != null && _dons.values.fold(0, (a, b) => a + b) == 0)) {
      ToastAgri.afficher(
        context,
        "Cette fiche porte des morts ou des dons non ventilés par stade : ventilez-les (Poussin ponte / Poussin en croissance / Poulette / Pondeuse) avant d'enregistrer.",
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
        ne: _ne,
        mort: _morts.values.fold(0, (a, b) => a + b),
        don: _dons.values.fold(0, (a, b) => a + b),
        ponteTotal: _oeufsRecoltes,
        ponteCasses: _oeufsCasses,
        poidsMoyen: FicheJournaliereRepository.poidsMoyen(
          poidsTotalG: _poidsTotalPese,
          tailleEchantillon: _effectifFinal,
        ),
        ventilation: VentilationJour(
          mortRepro: _morts['repro']!,
          mortSevre: _morts['sevre']!,
          mortJeune: _morts['jeune']!,
          mort4: _morts['quatre']!,
          donRepro: _dons['repro']!,
          donSevre: _dons['sevre']!,
          donJeune: _dons['jeune']!,
          don4: _dons['quatre']!,
          passage4Sevre: _passage1,
          passage: _passage2,
          passageJeuneRepro: _passage3,
          departSaisi: cat.departRequis ? _departSaisi : null,
        ),
      );
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7, Q3) — `saveDay()` : fiche d'un exercice clos, motif R4 en toast d'erreur ; les plateaux
      // n'entrent pas au stock (rien n'a été écrit).
      if (mounted) ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    } on FicheRefusee catch (e) {
      // VOL-2 : départ, jour antérieur au départ, ventes non ventilées… — le motif du web, tel quel ; rien n'est écrit
      // et aucun œuf n'entre au stock.
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
