import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/comptabilite/exercice_choisi.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/lecture_seule.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/pagination_agri.dart';
import '../../core/widgets/toast_agri.dart';
import '../../core/comptabilite/exercice_de_saisie.dart';
import '../stocks/pmp_service.dart';
import 'depenses_repository.dart';
import 'modale_depense.dart';

/// « Saisie des Dépenses » — `resources/views/livewire/achats/saisie-depenses.blade.php` (maître, article 5).
///
/// 🔴→✅ Ticket DEP5 (PRD `docs/prd/depenses-multilignes.md`) — UNE DÉPENSE, PLUSIEURS LIGNES. L'écran suit son Blade,
/// section par section :
///   1. en-tête : icône `request_page`, « Saisie des Dépenses », sous-titre du Blade ;
///   2. trois `x-kpi-card` : « Dépenses du mois » (`… FCFA`, émeraude), « Charges Fixes » (maïs) et « Charges
///      Variables » (bleu), ces deux-là « en attente » comme au web ;
///   3. la barre « Rechercher... » (300 ms, sur le résumé ET les libellés des lignes), « Toutes les pièces » /
///      « Comptabilisée » / « Sans pièce », puis le bouton « Nouvelle Dépense » qui ouvre la MODALE à lignes dynamiques
///      ([ModaleDepense]) — la saisie n'est plus un formulaire en page ;
///   4. le tableau Date · Libellé · Total · Mode · Pièce · Actions : le libellé est le RÉSUMÉ (« Provende ponte (+2
///      autres) »), se déplie sur les lignes (Libellé · Compte de Charge · Montant) puis la trésorerie, le centre de coût,
///      le fournisseur, le bénéficiaire et l'auteur ; « Pièce » = le numéro RELU de l'écriture liée, « Comptabilisée »
///      si ce poste n'a pas le journal, « Sans pièce » ; « Modifier » seulement sans pièce (une dépense comptabilisée est
///      immuable), « Archiver » (modale `x-modal-confirm-delete`), « Aucune dépense pour le moment. ».
///
/// Toasts du web : « Dépense enregistrée avec succès. » (succès), « Dépense archivée — trésorerie réintégrée et
/// charge annulée. » (avertissement).
///
/// ➕ Ajout du poste, gardé : sous la date, l'état d'envoi d'une saisie de ce poste (« À envoyer » ; « Refusée » ou
/// « Archivage refusé » suivi du REFUS DE LA PIÈCE du serveur mot pour mot, `ecriture_refus`) — le web n'a pas de file
/// d'envoi et dit le refus tout de suite.
///
/// ⚠️ « Charges Fixes / Variables » : arbitrage client en attente (aucun champ Fixe/Variable, ni au web ni ici).
class SaisieDepensesScreen extends StatefulWidget {
  const SaisieDepensesScreen({super.key, required this.depot});

  final DepensesRepository depot;

  /// `wire:model.live.debounce.300ms` du champ « Rechercher... ».
  static const delaiRecherche = Duration(milliseconds: 300);

  /// `pending-since` des deux cartes en attente du Blade.
  static const legendeEnAttente =
      'Disponible après Aucun champ Fixe/Variable dans le formulaire source';

  @override
  State<SaisieDepensesScreen> createState() => _SaisieDepensesScreenState();
}

class _SaisieDepensesScreenState extends State<SaisieDepensesScreen> {
  List<LigneDepense> _depenses = const [];
  double? _totalDuMois;

  /// Dépenses dépliées sur leurs lignes (`x-data="{ ouvert: false }"` par dépense du Blade).
  final Set<String> _ouvertes = {};

  /// Ticket EX7 (EF9) — page affichée (25 dépenses), dans l'exercice affiché.
  int _page = 1;

  final _recherche = TextEditingController();
  String _rechercheAppliquee = '';
  String _piece = '';
  Timer? _attenteRecherche;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _attenteRecherche?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    // Ticket EX7 (EF9) — les dépenses de l'exercice AFFICHÉ ; « Dépenses du mois » sur son mois de référence.
    final etat = PorteeExerciceChoisi.lire(context);
    final depenses = await widget.depot.depenses(
      recherche: _rechercheAppliquee,
      piece: _piece,
      bornes: etat?.bornes,
    );
    final total = await widget.depot.totalDuMois(etat?.moisDeReference ?? HeureBenin.maintenant());

    if (!mounted) return;

    setState(() {
      _depenses = depenses;
      _totalDuMois = total;
    });
  }

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
            _indicateurs(),
            const SizedBox(height: AgriSpacing.lg),
            _barreFiltres(),
            const SizedBox(height: AgriSpacing.md),
            _tableau(),
          ],
        ),
      ),
    );
  }

  /// `border-b border-outline-variant pb-md mb-lg` : icône `request_page` 26 px émeraude dans le titre
  /// (`text-xl lg:text-2xl font-bold text-on-surface`), sous-titre `text-xs text-outline`.
  Widget _enTete() {
    final large = AgriBreakpoints.large(context);
    return Container(
      padding: const EdgeInsets.only(bottom: AgriSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                SymbolesAgri.request_page,
                size: 26,
                color: AgriColors.brandEmerald,
              ),
              const SizedBox(width: AgriSpacing.xs),
              Flexible(
                child: Text(
                  'Saisie des Dépenses',
                  style: TextStyle(
                    fontSize: large ? 24 : 20,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          const Text(
            "Enregistrement des charges d'exploitation courantes de la ferme (SYSCOHADA Classe 6).",
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// `grid grid-cols-1 sm:grid-cols-3 gap-md` — les trois `x-kpi-card` du Blade, dans son ordre et ses couleurs.
  Widget _indicateurs() {
    final total = _totalDuMois;
    // `grid-cols-1 sm:grid-cols-3` : trois cartes dès `sm`, une colonne en dessous ; `GrilleKpi` : même hauteur par rangée.
    return GrilleKpi(
      colonnes: AgriBreakpoints.petit(context) ? 3 : 1,
      children: [
        _carteKpi(
          'Dépenses du mois',
          // `number_format($kpis['depenses_mois'], 0, ',', ' ').' FCFA'` ; « — » tant que rien n'est lu.
          total == null ? '—' : '${PmpService.francs(total)} FCFA',
          AgriColors.brandEmerald,
          SymbolesAgri.payments,
        ),
        _carteKpi(
          'Charges Fixes',
          '—',
          AgriColors.accentYellow,
          SymbolesAgri.event_repeat,
          couleurIcone: AgriColors.brandForest,
          enAttente: true,
        ),
        _carteKpi(
          'Charges Variables',
          '—',
          AgriColors.infoBlue,
          SymbolesAgri.trending_down,
          enAttente: true,
        ),
      ],
    );
  }

  /// `x-kpi-card` : liseré et icône de la variante (`text-brand-forest` pour `maize`) ; `:pending` → tiret estompé
  /// (`text-outline/50`) et sablier `hourglass_empty` devant « Disponible après … ».
  Widget _carteKpi(
    String libelle,
    String valeur,
    Color couleur,
    IconData icone, {
    Color? couleurIcone,
    bool enAttente = false,
  }) => CarteKpi(
    key: Key('kpi-$libelle'),
    libelle: libelle,
    valeur: valeur,
    icone: icone,
    couleurLisere: couleur,
    couleurIcone: couleurIcone ?? couleur,
    couleurValeur: enAttente
        ? AgriColors.outline.withValues(alpha: 0.5)
        : AgriColors.onSurface,
    legende: enAttente ? SaisieDepensesScreen.legendeEnAttente : null,
    iconeLegende: enAttente ? SymbolesAgri.hourglass_empty : null,
  );

  /// `bg-white border rounded-lg p-md flex flex-wrap items-center gap-sm` : « Rechercher... » (icône `search`,
  /// `flex-1 min-w-[180px]`), la liste des pièces, puis le bouton « Nouvelle Dépense ».
  Widget _barreFiltres() {
    final verrou = LectureSeule.motif(context);
    return Container(
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      // `flex flex-wrap items-center gap-sm` : sous le point de rupture `md` (768 px) la recherche prend toute la ligne, la liste
      // des pièces et le bouton passent dessous.
      child: LayoutBuilder(
        builder: (context, contraintes) {
          final recherche = SizedBox(
              height: 36,
              child: TextField(
                key: const Key('depenses-recherche'),
                controller: _recherche,
                onChanged: _rechercher,
                style: const TextStyle(fontSize: AgriTypography.xs),
                decoration: InputDecoration(
                  hintText: 'Rechercher...',
                  isDense: true,
                  prefixIcon: const Icon(
                    SymbolesAgri.search,
                    size: 18,
                    color: AgriColors.outline,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                    borderSide: const BorderSide(
                      color: AgriColors.outlineVariant,
                    ),
                  ),
                ),
              ),
            );
          final filtre = Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('depenses-filtre-piece'),
                value: _piece,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.onSurface,
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Toutes les pièces'),
                  ),
                  for (final f in DepensesRepository.filtresPiece)
                    DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) {
                  _piece = v ?? '';
                  _page = 1;
                  _charger();
                },
              ),
            ),
          );
          final bouton = LectureSeule.infobulle(
            verrou,
            FilledButton.icon(
              key: const Key('bouton-nouvelle-depense'),
              onPressed: verrou != null ? null : _nouvelle,
              icon: const Icon(SymbolesAgri.add_circle, size: 18),
              label: const Text('Nouvelle Dépense'),
              style: FilledButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: AgriTypography.sm,
                  fontWeight: FontWeight.bold,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.lg,
                  vertical: AgriSpacing.sm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
              ),
            ),
          );
          if (!AgriBreakpoints.moyen(context)) {
            return Wrap(
              spacing: AgriSpacing.sm,
              runSpacing: AgriSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [SizedBox(width: contraintes.maxWidth, child: recherche), filtre, bouton],
            );
          }
          return Row(
            children: [
              Expanded(child: recherche),
              const SizedBox(width: AgriSpacing.sm),
              filtre,
              const SizedBox(width: AgriSpacing.sm),
              bouton,
            ],
          );
        },
      ),
    );
  }

  void _rechercher(String texte) {
    _attenteRecherche?.cancel();
    _attenteRecherche = Timer(SaisieDepensesScreen.delaiRecherche, () {
      _rechercheAppliquee = texte;
      _page = 1;
      _charger();
    });
  }

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  /// Le tableau du Blade (`table.rtable`) : en-tête `bg-surface-zebra`, six colonnes (Date · Libellé · Total · Mode ·
  /// Pièce · Actions), zébrage une ligne sur deux.
  Widget _tableau() {
    return Container(
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        boxShadow: AgriShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AgriColors.surfaceZebra,
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.md,
              vertical: AgriSpacing.sm,
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('DATE', style: _enteteColonne)),
                Expanded(
                  flex: 4,
                  child: Text('LIBELLÉ', style: _enteteColonne),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'TOTAL',
                    textAlign: TextAlign.right,
                    style: _enteteColonne,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: EdgeInsets.only(left: AgriSpacing.md),
                    child: Text('MODE', style: _enteteColonne),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text('PIÈCE', style: _enteteColonne),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ACTIONS',
                    textAlign: TextAlign.right,
                    style: _enteteColonne,
                  ),
                ),
              ],
            ),
          ),
          if (_depenses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AgriSpacing.lg),
              child: Text(
                'Aucune dépense pour le moment.',
                key: Key('depenses-vide'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AgriTypography.base,
                  color: AgriColors.outline,
                ),
              ),
            ),
          for (final (i, l) in (PorteeExerciceChoisi.lire(context) == null ? _depenses : PaginationAgri.tranche(_depenses, _page)).indexed)
            _ligne(l, i),
          // Ticket EX7 (EF9) — `<x-pagination>` du web, sous le tableau.
          if (PorteeExerciceChoisi.lire(context) case final etat?)
            PaginationAgri(
              nom: 'depenses',
              total: _depenses.length,
              page: _page,
              annee: etat.annee,
              onPage: (p) => setState(() => _page = p),
            ),
        ],
      ),
    );
  }

  Widget _ligne(LigneDepense l, int index) {
    final d = l.depense;
    final ouverte = _ouvertes.contains(d.id);
    String deux(int n) => n.toString().padLeft(2, '0');
    const corps = TextStyle(fontSize: AgriTypography.xs);
    return Container(
      key: Key('depense-ligne-$index'),
      decoration: BoxDecoration(
        color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
        border: const Border(
          top: BorderSide(color: AgriColors.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${deux(d.expenseDate.day)}/${deux(d.expenseDate.month)}/${d.expenseDate.year}',
                      style: corps,
                    ),
                    ..._etatEnvoi(l),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                // `<button x-on:click="ouvert = !ouvert">` : le libellé-résumé déplie les lignes.
                child: Tooltip(
                  message: 'Voir les lignes',
                  child: InkWell(
                  key: Key('depense-deplier-$index'),
                  onTap: () => setState(() {
                    if (!_ouvertes.remove(d.id)) _ouvertes.add(d.id);
                  }),
                  child: Row(
                    children: [
                      Icon(
                        ouverte ? SymbolesAgri.expand_less : SymbolesAgri.expand_more,
                        size: 18,
                        color: AgriColors.onSurface,
                      ),
                      const SizedBox(width: AgriSpacing.xs),
                      Expanded(
                        child: Text(
                          d.label,
                          key: Key('depense-libelle-$index'),
                          style: corps.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${PmpService.francs(d.amount)} FCFA',
                  key: Key('depense-montant-$index'),
                  textAlign: TextAlign.right,
                  style: corps.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(left: AgriSpacing.md),
                  child: Text(
                    DepensesRepository.modesDePaiement[d.paymentMode] ?? '—',
                    key: Key('depense-mode-$index'),
                    style: corps,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _badgePiece(l),
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Une dépense comptabilisée est IMMUABLE : pas de crayon (le web ne l'affiche pas non plus).
                    if (!l.comptabilisee)
                      _action(
                        cle: 'depense-modifier-${d.id}',
                        infobulle: 'Modifier',
                        icone: SymbolesAgri.edit,
                        couleur: AgriColors.brandEmerald,
                        surAppui: () => _modifier(l),
                        verrou: LectureSeule.motif(context),
                      ),
                    _action(
                      cle: 'depense-archiver-${d.id}',
                      infobulle: 'Archiver',
                      icone: SymbolesAgri.delete,
                      couleur: AgriColors.outline,
                      surAppui: () => _archiver(d),
                      verrou: LectureSeule.motif(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (ouverte) _detail(l, index),
        ],
      ),
    );
  }

  /// Le détail déplié (`<tr x-show="ouvert">` du Blade) : un sous-tableau Libellé · Compte de Charge · Montant, puis
  /// « Trésorerie : … · Centre de coût : … · Fournisseur : … · Bénéficiaire : … · Saisie par : … ».
  Widget _detail(LigneDepense l, int index) {
    const corps = TextStyle(fontSize: AgriTypography.xs);
    String ou(String? v) => v == null || v.isEmpty ? '—' : v;
    return Container(
      key: Key('depense-detail-$index'),
      margin: const EdgeInsets.only(top: AgriSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
      color: AgriColors.surfaceZebra,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(flex: 4, child: Text('LIBELLÉ', style: _enteteColonne)),
              Expanded(flex: 4, child: Text('COMPTE DE CHARGE', style: _enteteColonne)),
              Expanded(
                flex: 2,
                child: Text('MONTANT', textAlign: TextAlign.right, style: _enteteColonne),
              ),
            ],
          ),
          for (final (i, ligne) in l.lignes.indexed)
            Container(
              key: Key('depense-$index-ligne-$i'),
              padding: const EdgeInsets.symmetric(vertical: AgriSpacing.xs),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
              ),
              child: Row(
                children: [
                  Expanded(flex: 4, child: Text(ligne.libelle, style: corps)),
                  Expanded(flex: 4, child: Text(ligne.compte, style: corps)),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${PmpService.francs(ligne.montant)} FCFA',
                      textAlign: TextAlign.right,
                      style: corps.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AgriSpacing.xs),
          Text(
            'Trésorerie : ${ou(l.tresorerie)}'
            ' · Centre de coût : ${ou(l.centreCout)}'
            ' · Fournisseur : ${ou(l.fournisseur)}'
            ' · Bénéficiaire : ${ou(l.depense.beneficiary)}'
            ' · Saisie par : ${ou(l.auteur)}',
            key: Key('depense-detail-resume-$index'),
            style: const TextStyle(fontSize: 11, color: AgriColors.outline),
          ),
        ],
      ),
    );
  }

  /// `inline-flex px-sm py-[2px] rounded-full text-[11px] font-bold border` : le numéro de la pièce (émeraude) — ou
  /// « Comptabilisée » quand ce poste n'a pas le journal pour le relire —, sinon « Sans pièce » (maïs).
  Widget _badgePiece(LigneDepense l) {
    final comptabilisee = l.comptabilisee;
    return Container(
      key: Key('depense-piece-${l.depense.id}'),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: comptabilisee
            ? AgriColors.brandEmerald.withValues(alpha: 0.10)
            : AgriColors.accentYellow.withValues(alpha: 0.20),
        border: Border.all(
          color: comptabilisee
              ? AgriColors.brandEmerald.withValues(alpha: 0.30)
              : AgriColors.accentYellow,
        ),
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      child: Text(
        comptabilisee ? (l.numeroPiece ?? 'Comptabilisée') : 'Sans pièce',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: comptabilisee ? AgriColors.brandEmerald : AgriColors.brandForest,
        ),
      ),
    );
  }

  /// ➕ Ajout du poste : l'état d'envoi d'une saisie de ce poste, sous sa date ; une saisie refusée porte le REFUS DE LA
  /// PIÈCE du serveur, mot pour mot.
  List<Widget> _etatEnvoi(LigneDepense l) {
    final d = l.depense;
    if (d.syncStatus == SyncStatus.synced) return const [];
    final refusee = d.syncStatus == SyncStatus.conflict;
    return [
      const SizedBox(height: 2),
      Container(
        key: Key('depense-etat-${d.id}'),
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: refusee
              ? AgriColors.errorBg
              : AgriColors.accentYellow.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Text(
          !refusee
              ? 'À envoyer'
              : d.isActive
              ? 'Refusée'
              : 'Archivage refusé',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: refusee ? AgriColors.errorDeep : AgriColors.brandForest,
          ),
        ),
      ),
      if (refusee)
        Text(
          l.motifRefus ?? 'Refus sans motif communiqué.',
          key: Key('depense-motif-${d.id}'),
          style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
        ),
    ];
  }

  Widget _action({
    required String cle,
    required String infobulle,
    required IconData icone,
    required Color couleur,
    required VoidCallback surAppui,
    String? verrou,
  }) => Tooltip(
    // Ticket EX7 (EF10) — exercice affiché clos : grisé, le motif remplace l'info-bulle.
    message: verrou ?? infobulle,
    child: InkWell(
      key: Key(cle),
      onTap: verrou == null ? surAppui : null,
      borderRadius: BorderRadius.circular(AgriRadius.full),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icone, size: 18, color: verrou == null ? couleur : AgriColors.outlineVariant),
      ),
    ),
  );

  /// `nouvelleDepense()` du web : la modale « Nouvelle Dépense » s'ouvre sur une ligne vide.
  Future<void> _nouvelle() async {
    final enregistree = await ModaleDepense.ouvrir(context, depot: widget.depot);
    await _apresModale(enregistree);
  }

  /// `editExpense($id)` : la modale « Modifier la Dépense », remplie avec la dépense et ses lignes. Refus avant
  /// d'ouvrir, comme le web : exercice clos (motif R4 de sa date), dépense comptabilisée (immuable : on l'archive puis on
  /// la saisit à nouveau), dépense archivée.
  Future<void> _modifier(LigneDepense l) async {
    final refus = await widget.depot.refusAvantModification(l.depense);
    if (!mounted) return;
    if (refus != null) {
      ToastAgri.afficher(context, refus, type: TypeToast.erreur);
      return;
    }
    final enregistree = await ModaleDepense.ouvrir(context, depot: widget.depot, enModification: l);
    await _apresModale(enregistree);
  }

  Future<void> _apresModale(bool? enregistree) async {
    if (enregistree != true) return;
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(context, DepensesRepository.toastEnregistree);
  }

  /// `archiveExpense($id)` derrière `x-modal-confirm-delete` : icône `archive` `text-error-deep`, « Confirmer
  /// l'archivage », le libellé de la dépense, « Annuler » puis « Archiver » (`bg-error-red`).
  Future<void> _archiver(Expense d) async {
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        icone: SymbolesAgri.archive,
        couleurIcone: AgriColors.errorDeep,
        titre: "Confirmer l'archivage",
        message:
            '${d.label} sera marqué(e) comme archivé(e) (statut inactif). '
            "Aucune suppression définitive n'est effectuée.",
        actions: [
          BoutonModaleSecondaire(
            libelle: 'Annuler',
            onPressed: () => Navigator.of(contexte).pop(false),
          ),
          BoutonModalePrimaire(
            key: const Key('archivage-depense-confirmer'),
            libelle: 'Archiver',
            couleur: AgriColors.errorRed,
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    try {
      await widget.depot.archiver(d.id);
    } on RefusExercice catch (e) {
      // Ticket EX6 (EF7) — `archiveExpense()` : dépense d'un exercice clos, motif R4 en toast d'erreur.
      if (!mounted) return;
      ToastAgri.afficher(context, e.motif, type: TypeToast.erreur);
      return;
    }
    await _charger();
    if (!mounted) return;
    ToastAgri.afficher(
      context,
      DepensesRepository.toastArchivee,
      type: TypeToast.avertissement,
    );
  }
}
