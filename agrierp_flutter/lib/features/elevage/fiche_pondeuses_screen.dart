import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/tableau_mensuel.dart';
import 'fiche_journaliere_repository.dart';
import 'ration_volaille.dart';
import 'production_oeufs_service.dart';
import 'soins_repository.dart';
import '../stocks/journal_stocks.dart';
import '../stocks/pmp_service.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/fiche-volailles-pondeuses.html` → Saisie Journalière Ponte
/// & Cheptel.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** Sections dans SON
/// ordre, libellés au mot près :
///   1. 4 cartes KPI (Effectif Pondeuses Vivantes · Taux de Ponte Moyen ·
///      Stock Plateaux (30 œufs) · Taux de Mortalité) ;
///   2. en-tête « Saisie Journalière Ponte & Cheptel — Jour N (jj/mm/aaaa) » ;
///   3. Entrées & Ventes (Achats / Entrées du jour · Nés / Transferts du jour ·
///      Ventes (POS)) ;
///   4. **Workflow Récolte & Stock d'Œufs** ;
///   5. Morts par catégorie — 4 stades ;
///   6. Dons par catégorie — mêmes catégories que les morts (🔁 15.56, décision client du 17/10/2026) ;
///   7. Effectif Final du Jour + Taux de Mortalité du Jour ;
///   8. Rationnement & Provende Servie par Stade ;
///   9. Pesée ;
///  10. Traitements & Prophylaxie Avicole ;
///  11. Attribution Bâtiments & Parcs Volailles Traités ;
///  12. Réinitialiser · Enregistrer ce Jour.
///
/// ⚠️ **« VENTES » EST EN LECTURE SEULE**, comme dans la maquette : la valeur
/// vient de la CAISSE. La rendre saisissable ouvrirait deux sources pour un
/// même chiffre.
///
/// ⚠️ **L'EFFECTIF PAR STADE N'EST PAS VENTILÉ ICI.** La maquette le répartit
/// (achats au Poussin Ponte, ventes déduites de la Pondeuse, chaque stade
/// perdant ses propres morts) à partir des effectifs par stade de la VEILLE —
/// que ni `livestock_daily_entries` ni le contrat de synchronisation ne portent
/// pour l'aviculture. L'effectif total est donc porté par la ligne du stade de
/// la bande et les autres restent à zéro, **dit à l'écran** plutôt que réparti
/// au jugé. Même écart que sur la fiche Lapins.
class FichePondeusesScreen extends StatefulWidget {
  const FichePondeusesScreen({
    super.key,
    required this.depot,
    required this.soins,
    required this.production,
  });

  final FicheJournaliereRepository depot;
  final SoinsRepository soins;
  final ProductionOeufsService production;

  @override
  State<FichePondeusesScreen> createState() => _FichePondeusesScreenState();
}

class _FichePondeusesScreenState extends State<FichePondeusesScreen> {
  /// Stades de la maquette, dans SON ordre — Morts, Dons et Rationnement
  /// partagent les mêmes quatre.
  /// 🔁 F0.99 — catégories des MORTS du web (`fiche-pondeuses.blade.php`), libellés et ordre exacts.
  static const _stades = ['Pondeuse / Repro', 'Poulette', 'Poussin'];

  List<LivestockLot> _bandes = const [];
  LivestockLot? _bande;
  DateTime _jour = DateTime.now();
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
  double _poidsTotalPese = 0;
  Product? _produitOeufs;

  /// Journées du mois pour la bande choisie — le tableau de bas de fiche.
  List<LivestockDailyEntry> _fichesDuMois = const [];

  /// Ticket U10 — grand livre des stocks et produit œufs du web, relus à chaque chargement du jour.
  JournalStocks? _journal;
  String? _produitGrandLivre;

  ProtocoleDuJour? _protocole;
  final _traitementsCoches = <String>{};
  final _observations = TextEditingController();
  bool _validationEnCours = false;

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  @override
  void dispose() {
    _observations.dispose();
    super.dispose();
  }

  Future<void> _initialiser() async {
    final toutes = await widget.depot.bandesActives();

    // ⚠️⚠️ **ESPECE ET STADE, comme le serveur** (`aviculture` + stade
    // `ponte`). Le stade seul ne suffit pas : une bande d'ESCARGOTS au stade
    // « ponte » serait apparue sur la fiche Pondeuses, avec un taux de ponte
    // calcule dessus. Le garde-fou du stock d'oeufs (ticket 14.59) aurait tenu,
    // mais l'ecran aurait menti.
    final bandes = toutes
        .where((b) => b.speciesCode == 'aviculture' && b.stage == 'ponte')
        .toList();
    final rations = await widget.depot.rations('aviculture');
    final produit = await widget.production.produitOeufs();

    if (!mounted) return;

    setState(() {
      _bandes = bandes;
      _bande = bandes.isEmpty ? null : bandes.first;
      _rations = rations;
      _produitOeufs = produit;
    });

    await _chargerJour();
  }

  Future<void> _chargerJour() async {
    final bande = _bande;
    if (bande == null) {
      setState(() => _chargement = false);
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
    final produit = await widget.production.produitOeufs();
    final mois = await widget.depot.fichesDuMois(bande.id, quand: _jour);
    final grandLivre = await widget.production.grandLivre();

    if (!mounted) return;

    setState(() {
      _effectifPrecedent = precedent;
      _fichesDuMois = mois;
      _journal = grandLivre.journal;
      _produitGrandLivre = grandLivre.produit;
      _achat = fiche?.achat ?? 0;
      _ne = fiche?.ne ?? 0;
      _vente = fiche?.vente ?? 0;
      _transfertEntree = fiche?.transfertEntree ?? 0;
      _transfertSortie = fiche?.transfertSortie ?? 0;
      _oeufsRecoltes = fiche?.ponteTotal ?? 0;
      _oeufsCasses = fiche?.ponteCasses ?? 0;
      _poidsTotalPese = 0;
      _produitOeufs = produit;
      _protocole = protocole;
      // Les cases repartent vides à chaque changement de jour ou de bande.
      _traitementsCoches.clear();
      _observations.clear();
      // ⚠️ Les morts et dons enregistrés ne sont pas ventilés par stade en
      // base : la fiche ne porte qu'un total. Les compteurs repartent donc de
      // zéro plutôt que d'afficher une répartition inventée.
      for (final cle in _stades) {
        _morts[cle] = 0;
        _dons[cle] = 0;
      }
      _mortEnregistre = (fiche?.mort ?? 0) > 0 ? fiche!.mort : null;
      _donEnregistre = (fiche?.don ?? 0) > 0 ? fiche!.don : null;
      _chargement = false;
    });
  }

  // ── Calculs, repris de la maquette ────────────────────────────────────────

  /// Morts du jour : la répartition saisie, sinon le total déjà enregistré (`mortDuJour` du web).
  int get _totalMorts {
    final saisis = _morts.values.fold(0, (a, b) => a + b);
    return saisis > 0 ? saisis : (_mortEnregistre ?? 0);
  }

  /// 🔁 15.56 — dons du jour : la répartition saisie, sinon le total déjà enregistré (`donDuJour` du web).
  /// Un don réduit l'effectif ; le serveur le sort du stock du produit de la bande à la réception.
  int get _totalDons {
    final saisis = _dons.values.fold(0, (a, b) => a + b);
    return saisis > 0 ? saisis : (_donEnregistre ?? 0);
  }

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
  /// $commercialisables)` — SRH = solde de FERME des œufs avant le jour choisi, TS = SRH + plateaux du formulaire,
  /// OS = sorties de vente du jour, Stock Final = TS − OS, en plateaux. `null` tant que le grand livre n'est pas lu.
  LigneGrandLivreOeufs? get _stockDuJour =>
      _journal?.ligneOeufs(_produitGrandLivre, _jour, _commercialisables);

  double? get _tauxPonte => ProductionOeufsService.tauxDePonte(
    recoltes: _oeufsRecoltes,
    effectif: _effectifFinal,
  );

  double? get _tauxMortalite => FicheJournaliereRepository.tauxMortalite(
    effectifPrecedent: _effectifPrecedent,
    mort: _totalMorts,
  );

  double? get _poidsMoyen => FicheJournaliereRepository.poidsMoyen(
    poidsTotalG: _poidsTotalPese,
    tailleEchantillon: _effectifFinal,
  );

  /// 🔁 15.57 — lignes du rationnement, règle commune au web (`RationVolaille`) : l'effectif final va à la
  /// première ligne « pondeuse » du barème ; aucune ligne ne correspond → « — », jamais 0 g.
  List<LigneRationVolaille> get _lignesRation =>
      RationVolaille.lignes(_rations, RationVolaille.pondeuse, _effectifFinal);

  // ── Rendu ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _enTete(),
            const SizedBox(height: AgriSpacing.lg),
            _cartesKpi(),
            const SizedBox(height: AgriSpacing.lg),
            if (_bande == null && !_chargement)
              _messageAucuneBande()
            else
              _carte(
                titre: 'Saisie Journalière Ponte & Cheptel — ${_libelleJour()}',
                icone: SymbolesAgri.edit_note,
                enfant: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _entreesEtVentes(),
                    const SizedBox(height: AgriSpacing.md),
                    _workflowOeufs(),
                    const SizedBox(height: AgriSpacing.md),
                    if (_mortEnregistre != null) ...[
                      Container(
                        key: const Key('morts-enregistres'),
                        padding: const EdgeInsets.all(AgriSpacing.xs),
                        decoration: BoxDecoration(
                          color: AgriColors.accentYellow.withValues(alpha: 0.2),
                          border: Border.all(color: AgriColors.accentYellow),
                          borderRadius: BorderRadius.circular(AgriRadius.lg),
                        ),
                        child: Text(
                          '$_mortEnregistre mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : '
                          "ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.",
                          style: const TextStyle(fontSize: 11, color: AgriColors.brandForest),
                        ),
                      ),
                      const SizedBox(height: AgriSpacing.xs),
                    ],
                    _blocCategories(
                      titre: 'Morts par catégorie',
                      icone: SymbolesAgri.dangerous,
                      couleur: AgriColors.errorDeep,
                      fond: AgriColors.errorBg.withValues(alpha: 0.3),
                      valeurs: _morts,
                    ),
                    const SizedBox(height: AgriSpacing.md),
                    if (_donEnregistre != null) ...[
                      Container(
                        key: const Key('dons-enregistres'),
                        padding: const EdgeInsets.all(AgriSpacing.xs),
                        decoration: BoxDecoration(
                          color: AgriColors.accentYellow.withValues(alpha: 0.2),
                          border: Border.all(color: AgriColors.accentYellow),
                          borderRadius: BorderRadius.circular(AgriRadius.lg),
                        ),
                        child: Text(
                          '$_donEnregistre don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : '
                          "ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.",
                          style: const TextStyle(fontSize: 11, color: AgriColors.brandForest),
                        ),
                      ),
                      const SizedBox(height: AgriSpacing.xs),
                    ],
                    _blocCategories(
                      titre: 'Dons par catégorie',
                      icone: SymbolesAgri.card_giftcard,
                      couleur: AgriColors.brandEmerald,
                      fond: AgriColors.brandEmerald.withValues(alpha: 0.05),
                      valeurs: _dons,
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
                    _traitements(),
                    const SizedBox(height: AgriSpacing.md),
                    _attributionBatiments(),
                    const SizedBox(height: AgriSpacing.md),
                    _boutons(),
                  ],
                ),
              ),
            const SizedBox(height: AgriSpacing.lg),
            _tableauMensuel(),
            // Ticket U10 — note du Blade sous le tableau du mois.
            if (_bande != null)
              const Padding(
                padding: EdgeInsets.only(top: AgriSpacing.sm),
                child: Text(
                  'Colonnes SRH/TS/OS/Stock Final : valeurs précises uniquement pour le jour sélectionné '
                  '(reconstruction historique jour par jour non disponible avant le Sprint 6 — grand livre de '
                  'mouvements de stock).',
                  key: Key('note-grand-livre'),
                  style: TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _libelleJour() {
    final j = _jour.day.toString().padLeft(2, '0');
    final m = _jour.month.toString().padLeft(2, '0');
    return 'Jour ${_jour.day} ($j/$m/${_jour.year})';
  }

  Widget _enTete() {
    return Row(
      children: [
        const Icon(SymbolesAgri.egg, color: AgriColors.brandEmerald, size: 26),
        const SizedBox(width: AgriSpacing.xs),
        const Expanded(
          child: Text(
            'Fiches Pondeuses - Aviculture',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AgriColors.brandForest,
            ),
          ),
        ),
        if (_bandes.length > 1)
          DropdownButton<String>(
            value: _bande?.id,
            underline: const SizedBox.shrink(),
            items: _bandes
                .map((b) => DropdownMenuItem(value: b.id, child: Text(b.code)))
                .toList(),
            onChanged: (id) async {
              setState(() => _bande = _bandes.firstWhere((b) => b.id == id));
              await _chargerJour();
            },
          ),
      ],
    );
  }

  /// « 2. CARTES KPI DYNAMIQUES DU MOIS » — quatre cartes, dans l'ordre de la
  /// maquette, chacune avec sa bordure gauche colorée et son icône.
  Widget _cartesKpi() {
    return LayoutBuilder(
      builder: (context, contraintes) {
        // Maquette : `grid-cols-2 md:grid-cols-4`.
        final colonnes = AgriBreakpoints.moyen(context) ? 4 : 2;
        final largeur =
            (contraintes.maxWidth - (colonnes - 1) * AgriSpacing.md) / colonnes;

        return Wrap(
          spacing: AgriSpacing.md,
          runSpacing: AgriSpacing.md,
          children: [
            _carteKpi(
              largeur: largeur,
              libelle: 'Effectif Pondeuses Vivantes',
              valeur: '$_effectifFinal',
              icone: SymbolesAgri.pets,
              couleur: AgriColors.brandEmerald,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Taux de Ponte Moyen',
              valeur: _tauxPonte == null
                  ? '—'
                  : '${_tauxPonte!.toStringAsFixed(1)}%',
              icone: SymbolesAgri.egg,
              couleur: AgriColors.infoBlue,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Stock Plateaux (30 œufs)',
              // ⚠️ Le stock réel du produit, pas les plateaux du jour : la
              // carte annonce un STOCK. Un tiret si le produit « Œufs » est
              // absent du catalogue — mieux qu'un zéro qui se lirait
              // « plus un seul plateau ».
              valeur: _produitOeufs == null
                  ? '—'
                  : '${_produitOeufs!.stockQty.round()} Plateaux',
              icone: SymbolesAgri.grid_view,
              couleur: AgriColors.accentYellow,
              couleurIcone: AgriColors.brandForest,
            ),
            _carteKpi(
              largeur: largeur,
              libelle: 'Taux de Mortalité',
              valeur: _tauxMortalite == null
                  ? '—'
                  : '${_tauxMortalite!.toStringAsFixed(1)}%',
              icone: SymbolesAgri.trending_down,
              couleur: AgriColors.errorRed,
            ),
          ],
        );
      },
    );
  }

  /// Une carte KPI : bordure fine sur trois côtés, **filet coloré de 4 px à
  /// gauche** (`border-l-4` de la maquette), coins arrondis.
  ///
  /// ⚠️ LE FILET EST UN ENFANT, PAS UNE BORDURE. Flutter refuse un
  /// `borderRadius` sur une bordure aux couleurs non uniformes — ce que la
  /// maquette obtient sans peine en CSS. Le rendu visé est identique ; c'est
  /// la seule façon de l'obtenir sans renoncer ni aux coins arrondis ni au
  /// filet coloré.
  Widget _carteKpi({
    required double largeur,
    required String libelle,
    required String valeur,
    required IconData icone,
    required Color couleur,
    Color? couleurIcone,
  }) => SizedBox(
    width: largeur,
    child: CarteKpi(
      libelle: libelle,
      valeur: valeur,
      icone: icone,
      couleurLisere: couleur,
      couleurIcone: couleurIcone ?? AgriColors.brandEmerald,
    ),
  );

  /// Tableau mensuel — `fiche-volailles-pondeuses.html`, bas de page.
  ///
  /// Groupes de la maquette, dans son ordre : **Cheptel du Jour** (Eff. Début,
  /// Morts, Taux Mort %, Eff. Fin) · **Suivi de la Ponte & Récolte** (Total
  /// (OR), Taux Ponte %, Cassés (OF), Comm. (OR-OF)) · **Stock Œufs & Plateaux
  /// (30)** (Stock Hier (SRH), Total Stock (TS), Sortie Vente (OS), Stock
  /// Final) · **Traitements & Rappels**.
  ///
  /// 🔴→✅ **TICKET U10 — LES QUATRE COLONNES DU GRAND LIVRE D'ŒUFS SONT CELLES DU WEB.** `stock_movements`
  /// descend au poste depuis U9 : SRH, TS, OS et Stock Final de la ligne du JOUR SÉLECTIONNÉ sont ceux de
  /// [_stockDuJour] (`$isToday ? $this->stockToday[…] : '—'` du Blade) ; les autres lignes gardent « — », comme au
  /// web (« valeurs précises uniquement pour le jour sélectionné »).
  Widget _tableauMensuel() {
    if (_bande == null) return const SizedBox.shrink();

    int effectifDebut(LivestockDailyEntry f) =>
        f.effectifFinal + f.mort + f.vente - f.achat - f.ne;

    return TableauMensuel(
      libelleDate: 'Date / Jour',
      nombreDeJours: _fichesDuMois.length,
      jourActif: _indexDuJourCourant(),
      dateDe: (i) {
        final d = _fichesDuMois[i].entryDate;
        final j = d.day.toString().padLeft(2, '0');
        final m = d.month.toString().padLeft(2, '0');
        return 'Jour ${d.day} ($j/$m)';
      },
      onOuvrirJour: (i) => _ouvrirJour(_fichesDuMois[i].entryDate),
      groupes: [
        GroupeColonnes(
          libelle: 'Cheptel du Jour',
          colonnes: [
            ColonneMensuelle(
              libelle: 'Eff. Début',
              largeur: 1.2,
              valeur: (i) => '${effectifDebut(_fichesDuMois[i])}',
            ),
            ColonneMensuelle(
              libelle: 'Morts',
              valeur: (i) => '${_fichesDuMois[i].mort}',
            ),
            ColonneMensuelle(
              libelle: 'Taux Mort %',
              largeur: 1.2,
              valeur: (i) {
                final depart = effectifDebut(_fichesDuMois[i]);
                if (depart <= 0) return '—';
                return ((_fichesDuMois[i].mort / depart) * 100).toStringAsFixed(
                  1,
                );
              },
            ),
            ColonneMensuelle(
              libelle: 'Eff. Fin',
              gras: true,
              valeur: (i) => '${_fichesDuMois[i].effectifFinal}',
            ),
          ],
        ),
        GroupeColonnes(
          libelle: 'Suivi de la Ponte & Récolte',
          colonnes: [
            ColonneMensuelle(
              libelle: 'Total (OR)',
              largeur: 1.2,
              valeur: (i) => '${_fichesDuMois[i].ponteTotal ?? 0}',
            ),
            ColonneMensuelle(
              libelle: 'Taux Ponte %',
              largeur: 1.3,
              valeur: (i) {
                final f = _fichesDuMois[i];
                final taux = ProductionOeufsService.tauxDePonte(
                  recoltes: f.ponteTotal ?? 0,
                  effectif: f.effectifFinal,
                );
                return taux == null ? '—' : taux.toStringAsFixed(1);
              },
            ),
            ColonneMensuelle(
              libelle: 'Cassés (OF)',
              largeur: 1.2,
              valeur: (i) => '${_fichesDuMois[i].ponteCasses ?? 0}',
            ),
            ColonneMensuelle(
              libelle: 'Comm. (OR-OF)',
              largeur: 1.5,
              gras: true,
              valeur: (i) {
                final f = _fichesDuMois[i];
                return '${ProductionOeufsService.commercialisables(recoltes: f.ponteTotal ?? 0, casses: f.ponteCasses ?? 0)}';
              },
            ),
          ],
        ),
        // Ticket U10 — grand livre d'œufs : le jour sélectionné seulement, comme le web (voir docblock).
        GroupeColonnes(
          libelle: 'Stock Œufs & Plateaux (30)',
          colonnes: [
            ColonneMensuelle(
              libelle: 'SRH',
              largeur: 1.5,
              valeur: (i) => _celluleGrandLivre(i, (l) => l.srh),
            ),
            ColonneMensuelle(
              libelle: 'TS',
              largeur: 1.5,
              valeur: (i) => _celluleGrandLivre(i, (l) => l.ts),
            ),
            ColonneMensuelle(
              libelle: 'OS',
              largeur: 1.5,
              valeur: (i) => _celluleGrandLivre(i, (l) => l.os),
            ),
            ColonneMensuelle(
              libelle: 'Stock Final',
              largeur: 1.3,
              valeur: (i) => _celluleGrandLivre(i, (l) => l.stockFinal),
            ),
          ],
        ),
      ],
      colonnesSimples: const [
        ColonneMensuelle(
          libelle: 'Traitements & Rappels',
          largeur: 2.0,
          // ⚠️ Le registre vétérinaire est une autre table : le rattacher jour
          // par jour demanderait une requête par ligne. Signalé, pas approximé.
          valeur: _sansGrandLivre,
        ),
      ],
    );
  }

  static String _sansGrandLivre(int _) => '—';

  /// Cellule SRH / TS / OS / Stock Final de la ligne [i] : la valeur du jour sélectionné (flottant PHP affiché tel
  /// quel, `{{ $this->stockToday['srh'] }}`), « — » sur toute autre ligne.
  String _celluleGrandLivre(int i, double Function(LigneGrandLivreOeufs) champ) {
    final l = _stockDuJour;
    if (l == null || i != _indexDuJourCourant()) return '—';
    return PmpService.flottant(champ(l));
  }

  /// 🔴→✅ Ticket U10 — bloc « Stock Œufs & Plateaux (30) — Jour Sélectionné » du Blade, entre la pesée et les
  /// traitements : quatre encadrés « Stock Hier (SRH) », « Total Stock (TS) », « Sortie Vente (OS) », « Stock
  /// Final » (le dernier sur fond vert pâle), valeurs de [_stockDuJour].
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
            const Icon(
              SymbolesAgri.inventory_2,
              size: 16,
              color: AgriColors.brandEmerald,
            ),
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
            Expanded(
              child: encadre('stock-srh', 'Stock Hier (SRH)', v((l) => l.srh)),
            ),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(
              child: encadre('stock-ts', 'Total Stock (TS)', v((l) => l.ts)),
            ),
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

  int? _indexDuJourCourant() {
    for (var i = 0; i < _fichesDuMois.length; i++) {
      final d = _fichesDuMois[i].entryDate;
      if (d.year == _jour.year &&
          d.month == _jour.month &&
          d.day == _jour.day) {
        return i;
      }
    }
    return null;
  }

  /// ⚠️ CHARGE LA JOURNÉE DANS LE FORMULAIRE, comme l'invite de la maquette.
  Future<void> _ouvrirJour(DateTime jour) async {
    setState(() => _jour = jour);
    await _chargerJour();
  }

  Widget _messageAucuneBande() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.lg),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: const Column(
        children: [
          Icon(SymbolesAgri.sync_problem, size: 32, color: AgriColors.outline),
          SizedBox(height: AgriSpacing.sm),
          Text(
            'Aucune bande active au stade Ponte sur ce poste.',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AgriColors.brandForest,
            ),
          ),
          SizedBox(height: AgriSpacing.xs),
          Text(
            'Lancez une synchronisation pour recevoir les bandes du serveur.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AgriColors.outline),
          ),
        ],
      ),
    );
  }

  Widget _carte({
    required String titre,
    required IconData icone,
    required Widget enfant,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icone, color: AgriColors.brandEmerald, size: 20),
                const SizedBox(width: AgriSpacing.xs),
                Expanded(
                  child: Text(
                    titre,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: AgriSpacing.sm),
            enfant,
          ],
        ),
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
            suffixe: '(POS)',
            valeur: '$_vente',
          ),
        ),
      ],
    );
  }

  Widget _champNombre({
    required String libelle,
    required String cle,
    required int valeur,
    required ValueChanged<int> surChangement,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: TextFormField(
            key: Key('champ-$cle-$valeur'),
            initialValue: valeur == 0 ? '' : '$valeur',
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14),
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ⚠️ LE LIBELLE PEUT PASSER A LA LIGNE. « Commercialisables ($OR -
        // OF$) » sur une colonne au quart de l'ecran deborde sinon — la
        // maquette, elle, replie naturellement le texte.
        Wrap(
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
        const SizedBox(height: 4),
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
            style: const TextStyle(fontSize: 14, color: AgriColors.outline),
          ),
        ),
      ],
    );
  }

  /// « Workflow Récolte & Stock d'Œufs (Combine les fiches officielles de la
  /// ferme) » — le bloc ambre de la maquette.
  Widget _workflowOeufs() {
    final plateaux = _plateaux;

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.30),
        ),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(SymbolesAgri.egg, size: 18, color: Color(0xFFB45309)),
              SizedBox(width: AgriSpacing.xs),
              Expanded(
                child: Text(
                  "WORKFLOW RÉCOLTE & STOCK D'ŒUFS (COMBINE LES FICHES OFFICIELLES DE LA FERME)",
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF78350F),
                  ),
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
                  libelle: r'Total Œufs Récoltés ($OR$)',
                  cle: 'oeufs-pondus',
                  valeur: _oeufsRecoltes,
                  surChangement: (v) => setState(() => _oeufsRecoltes = v),
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _champNombre(
                  libelle: r'Œufs Cassés / Fêlés ($OF$)',
                  cle: 'oeufs-casses',
                  valeur: _oeufsCasses,
                  surChangement: (v) => setState(() => _oeufsCasses = v),
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _champLecture(
                  libelle: r'Commercialisables ($OR - OF$)',
                  valeur: '$_commercialisables',
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _champLecture(
                  libelle: 'Taux de Ponte Calculé (%)',
                  valeur: _tauxPonte == null
                      ? '—'
                      : '${_tauxPonte!.toStringAsFixed(1)} %',
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _encartOeufs(
                  'Plateaux Nets Générés (30 œufs/plateau) : ',
                  '${plateaux.plateaux} Plateaux (${plateaux.vrac} œufs vrac)',
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: _encartOeufs(
                  'Incrémentation Automatique du Stock : ',
                  '+${plateaux.plateaux} Plateaux au Stock Produits',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _encartOeufs(String libelle, String valeur) {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AgriColors.brandForest,
          ),
          children: [
            TextSpan(text: libelle),
            TextSpan(
              text: valeur,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AgriColors.brandEmerald,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blocCategories({
    required String titre,
    required IconData icone,
    required Color couleur,
    required Color fond,
    required Map<String, int> valeurs,
  }) {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: fond,
        border: Border.all(color: couleur.withValues(alpha: 0.2)),
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
            color: Colors.white,
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
                      fontSize: 14,
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
        // ⚠️ Jamais en dessous de zéro : un effectif négatif n'existe pas.
        valeurs[categorie] = (actuel + pas).clamp(0, 1 << 30);
      }),
      child: Container(
        width: 30,
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

  Widget _effectif() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.brandEmerald.withValues(alpha: 0.06),
        border: Border.all(
          color: AgriColors.brandEmerald.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EFFECTIF FINAL DU JOUR (CALCULÉ DYNAMIQUE)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const Text(
                  '= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)',
                  style: TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_effectifFinal',
                  key: const Key('effectif-final'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AgriColors.brandEmerald,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TAUX DE MORTALITÉ DU JOUR (%)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const Text(
                  '= (Morts du Jour ÷ Effectif J-1) × 100',
                  style: TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
                const SizedBox(height: 4),
                Text(
                  _tauxMortalite == null
                      ? '—'
                      : '${_tauxMortalite!.toStringAsFixed(1)} %',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AgriColors.errorDeep,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// « Rationnement & Provende Servie par Stade (en Grammes g/j) ».
  ///
  /// Colonnes de la maquette : Stade / Tranche d'Âge · Effectif · Ration
  /// Normative · Provende Servie (g).
  ///
  /// ⚠️ LES GRAMMAGES ET LES LIBELLÉS VIENNENT DU RÉFÉRENTIEL SYNCHRONISÉ,
  /// jamais du code : ils sont éditables depuis Paramètres > Élevage.
  Widget _rationnement() {
    if (_rations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.surfaceZebra,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: const Text(
          "Aucune ration normative reçue pour l'aviculture — synchronisez le "
          'poste avant de servir la provende.',
          style: TextStyle(fontSize: 11, color: AgriColors.outline),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(SymbolesAgri.restaurant, size: 18, color: AgriColors.brandEmerald),
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
          ),
          const SizedBox(height: AgriSpacing.sm),
          Table(
            border: TableBorder.all(color: AgriColors.outlineVariant),
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1.8),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: AgriColors.surfaceZebra),
                children: [
                  _CelluleEntete("Stade / Tranche d'Âge"),
                  _CelluleEntete('Effectif'),
                  _CelluleEntete('Ration Normative'),
                  _CelluleEntete('Provende Servie (g)'),
                ],
              ),
              for (final l in _lignesRation)
                TableRow(
                  children: [
                    _Cellule(l.libelle),
                    _Cellule(
                      l.effectif == null ? '—' : '${l.effectif}',
                      centre: true,
                    ),
                    _Cellule('${l.ration.round()} g/j', centre: true),
                    _Cellule(
                      l.totalG == null ? '—' : '${l.totalG!.round()} g',
                      centre: true,
                      gras: true,
                    ),
                  ],
                ),
              TableRow(
                decoration: BoxDecoration(
                  color: AgriColors.brandEmerald.withValues(alpha: 0.08),
                ),
                children: [
                  const _Cellule(
                    'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
                    gras: true,
                  ),
                  const _Cellule(''),
                  const _Cellule(''),
                  _Cellule(
                    RationVolaille.totalAffiche(
                      RationVolaille.totalG(_lignesRation),
                    ),
                    key: const Key('total-provende'),
                    centre: true,
                    gras: true,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          // ⚠️ L'écart est dit à l'écran, pas masqué par une répartition
          // inventée entre les quatre stades.
          if (RationVolaille.rattachee(_lignesRation))
            const Text(
              "L'effectif n'est pas encore ventilé par stade : la fiche du jour "
              "n'en porte que le total. La ligne du stade de la bande (Pondeuse) le reçoit "
              'entièrement.',
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
      ),
    );
  }

  Widget _pesee() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'POIDS GÉNÉRAL PESÉ (G)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const Text(
                  '(Pré-rempli de J-1)',
                  style: TextStyle(fontSize: 9, color: AgriColors.outline),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 40,
                  child: TextFormField(
                    key: Key('champ-pesee-${_poidsTotalPese.round()}'),
                    initialValue: _poidsTotalPese == 0
                        ? ''
                        : '${_poidsTotalPese.round()}',
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'ex : 1800',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (t) => setState(
                      () => _poidsTotalPese = double.tryParse(t) ?? 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          Expanded(
            child: _champLecture(
              libelle: 'Taille Échantillon',
              suffixe: '(Auto = Effectif Final)',
              valeur: '$_effectifFinal',
            ),
          ),
          const SizedBox(width: AgriSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'POIDS MOYEN CONSTATÉ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 40,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AgriColors.surfaceZebra,
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                  ),
                  child: Text(
                    _poidsMoyen == null ? '—' : '${_poidsMoyen!.round()} g',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandEmerald,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Traitements & Prophylaxie Avicole ─────────────────────────────────────

  String _etatProphylaxie(ProtocoleDuJour p) {
    if (!p.determinable) return 'Indéterminé';
    if (p.traitements.isEmpty) return 'Libre';
    return p.enAttente == 0 ? 'Validé / Effectué' : 'Prévus';
  }

  Color _couleurEtat(ProtocoleDuJour p) {
    if (!p.determinable) return AgriColors.outline;
    if (p.traitements.isEmpty) return AgriColors.brandEmerald;
    return p.enAttente == 0 ? AgriColors.brandEmerald : AgriColors.accentYellow;
  }

  Widget _traitements() {
    final protocole = _protocole;

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.infoBlue.withValues(alpha: 0.05),
        border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(SymbolesAgri.vaccines, size: 18, color: AgriColors.infoBlue),
              const SizedBox(width: AgriSpacing.xs),
              const Expanded(
                child: Text(
                  'Traitements & Prophylaxie Avicole Automatiques Prévus pour ce Jour',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AgriTypography.xs,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
              if (protocole != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _couleurEtat(protocole).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _etatProphylaxie(protocole),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _couleurEtat(protocole) == AgriColors.accentYellow
                          ? AgriColors.brandForest
                          : _couleurEtat(protocole),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          if (protocole == null)
            const Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            if (!protocole.determinable)
              Text(
                'Protocole non calculable au poste — '
                '${protocole.motifIndetermine ?? ''}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AgriColors.errorDeep,
                ),
              )
            else if (protocole.traitements.isEmpty)
              const Text(
                '— Aucun traitement récurrent programmé pour ce jour —',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              )
            else
              ...protocole.traitements.map(_ligneTraitement),
            if (protocole.calendairesNonEvalues > 0)
              Padding(
                padding: const EdgeInsets.only(top: AgriSpacing.xs),
                child: Text(
                  '${protocole.calendairesNonEvalues} entrée(s) du protocole '
                  'suivent le calendrier et ne sont pas évaluées ici.',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            const SizedBox(height: AgriSpacing.sm),
            TextField(
              controller: _observations,
              maxLines: 2,
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: const InputDecoration(
                labelText: "Observations Cliniques / Notes de l'Animalier",
                hintText:
                    "ex : Ponte en hausse, consommations d'eau conformes...",
                hintStyle: TextStyle(fontSize: 11),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AgriSpacing.sm),
            if (protocole.determinable && protocole.enAttente > 0) ...[
              const Text(
                'Valider un traitement rémanent bloque la vente de cette bande '
                "jusqu'à la fin du délai d'attente.",
                style: TextStyle(fontSize: 10, color: AgriColors.errorDeep),
              ),
              const SizedBox(height: AgriSpacing.xs),
              FilledButton.icon(
                key: const Key('bouton-valider-traitements'),
                onPressed: _traitementsCoches.isEmpty || _validationEnCours
                    ? null
                    : _validerTraitements,
                icon: const Icon(SymbolesAgri.check_circle_outline, size: 16),
                label: const Text(
                  "Valider l'Administration de Tous les Traitements du Jour",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: AgriSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    protocole.enAttente > 0
                        ? SymbolesAgri.error_outline
                        : SymbolesAgri.check_circle_outline,
                    size: 13,
                    color: protocole.enAttente > 0
                        ? AgriColors.errorDeep
                        : AgriColors.brandEmerald,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Indice Rouge : ${protocole.enAttente} soin(s) en attente',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: protocole.enAttente > 0
                          ? AgriColors.errorDeep
                          : AgriColors.brandEmerald,
                    ),
                  ),
                ],
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
      padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 22,
            width: 22,
            child: Checkbox(
              value:
                  t.dejaAdministre || _traitementsCoches.contains(standard.id),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  standard.treatment,
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                    decoration: t.dejaAdministre
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    '($details)',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AgriColors.outline,
                    ),
                  ),
              ],
            ),
          ),
          if (t.remanenceJours > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AgriColors.errorBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Rémanence ${t.remanenceJours}j',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.errorDeep,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _validerTraitements() async {
    // ⚠️ F0.93 : garde de l'écran (un second appel avant le setState),
    // EN PLUS du dépôt, qui recalcule le protocole sous transaction.
    if (_validationEnCours) return;
    final bande = _bande;
    if (bande == null || _protocole == null) return;

    setState(() => _validationEnCours = true);

    // ⚠️⚠️ F0.93 — PAS de boucle sur l'instantané `_protocole` : le dépôt
    // RECALCULE le protocole à l'instant de l'écriture (comme le serveur,
    // 15.35) ; valider deux fois = un seul soin, une seule rémanence.
    await widget.soins.validerTraitementsDuJour(
      bande: bande,
      codeEspece: 'aviculture',
      quand: _jour,
      idsBareme: Set.of(_traitementsCoches),
      observations: _observations.text,
    );

    if (!mounted) return;
    setState(() => _validationEnCours = false);
    await _chargerJour();
  }

  /// « Attribution Bâtiments & Parcs Volailles Traités (Cochés par défaut) ».
  ///
  /// ⚠️⚠️ MÊME CONSTAT QUE POUR LES CAGES DE LA FICHE LAPINS : la maquette
  /// liste trois bâtiments **en dur**, aucune table ne les porte — ni serveur
  /// ni poste — et le Blade Laravel omet la section. Le conteneur est rendu à
  /// sa place, son contenu dit la vérité.
  Widget _attributionBatiments() {
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(SymbolesAgri.home_work, size: 18, color: AgriColors.brandEmerald),
              SizedBox(width: AgriSpacing.xs),
              Expanded(
                child: Text(
                  'Attribution Bâtiments & Parcs Volailles Traités (Cochés par défaut)',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          const Text(
            "Aucun référentiel de bâtiments n'existe encore : ni le serveur ni "
            "le poste n'en tiennent la liste. La section reste à sa place, "
            "vide, en attendant l'arbitrage du client.",
            style: TextStyle(
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
              color: AgriColors.outline,
            ),
          ),
        ],
      ),
    );
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
          OutlinedButton(
            key: const Key('bouton-reinitialiser'),
            onPressed: _bande == null ? null : _reinitialiserJour,
            style: OutlinedButton.styleFrom(
              foregroundColor: AgriColors.outline,
              side: const BorderSide(color: AgriColors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
            ),
            child: const Text(
              'Réinitialiser',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          FilledButton.icon(
            key: const Key('bouton-enregistrer'),
            onPressed: _bande == null ? null : _enregistrer,
            icon: const Icon(SymbolesAgri.save, size: 18),
            label: const Text(
              'Enregistrer ce Jour',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _reinitialiserJour() {
    setState(() {
      _achat = 0;
      _ne = 0;
      _oeufsRecoltes = 0;
      _oeufsCasses = 0;
      _poidsTotalPese = 0;
      for (final cle in _stades) {
        _morts[cle] = 0;
        _dons[cle] = 0;
      }
    });
  }

  /// Enregistre la fiche du jour et fait entrer les plateaux au stock local.
  ///
  /// ⚠️⚠️ **LE STOCK MONTE TOUT DE SUITE, PAS SEULEMENT APRÈS SYNCHRONISATION.**
  /// Le serveur produit bien l'effet à la réception (ticket 14.59), mais un
  /// poste peut rester des jours hors ligne : d'ici là, sa propre caisse
  /// refuserait de vendre des plateaux qu'il vient de récolter.
  Future<void> _enregistrer() async {
    final bande = _bande;
    if (bande == null) return;

    // ⚠️ La création se détermine AVANT l'écriture : après, la fiche existe
    // toujours, et l'incrément se ferait à chaque correction du même jour.
    final creation = await widget.depot.chargerJour(bande.id, _jour) == null;

    await widget.depot.enregistrer(
      lotId: bande.id,
      jour: _jour,
      achat: _achat,
      ne: _ne,
      mort: _totalMorts,
      don: _totalDons,
      ponteTotal: _oeufsRecoltes,
      ponteCasses: _oeufsCasses,
      poidsMoyen: _poidsMoyen,
    );

    final plateaux = await widget.production.entrerAuStock(
      bande: bande,
      recoltes: _oeufsRecoltes,
      casses: _oeufsCasses,
      creation: creation,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          plateaux > 0
              ? 'Jour enregistré — +$plateaux plateaux au stock.'
              : 'Jour enregistré.',
        ),
      ),
    );

    await _chargerJour();
  }
}

class _CelluleEntete extends StatelessWidget {
  const _CelluleEntete(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        texte.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: AgriColors.outline,
        ),
      ),
    );
  }
}

class _Cellule extends StatelessWidget {
  const _Cellule(this.texte, {super.key, this.centre = false, this.gras = false});

  final String texte;
  final bool centre;
  final bool gras;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        texte,
        textAlign: centre ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: 11,
          fontWeight: gras ? FontWeight.bold : FontWeight.normal,
          color: gras ? AgriColors.brandForest : AgriColors.onSurface,
        ),
      ),
    );
  }
}
