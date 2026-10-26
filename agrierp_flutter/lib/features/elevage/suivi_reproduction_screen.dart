import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/toast_agri.dart';
import 'sujets_repository.dart';
import 'suivi_reproduction_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `livewire/elevage/suivi-reproduction.blade.php` → Suivi Reproduction.
///
/// ⚠️⚠️ **TICKET H7 : LE BLADE FAIT FOI** (doctrine, art. 5). L'écran avait été porté depuis la
/// maquette ; il suit désormais la vue web : les **quatre onglets** (`<x-tab-page>`), PUIS les
/// quatre KPI, puis le panneau de l'onglet — titre, sous-titre, rappel du cycle à quatre étapes
/// avec flèches, tableau de neuf colonnes et ses actions. Les ajouts du poste absents du web
/// (lien vers la fiche sujet, bandeau de lecture seule, bandeaux de cycle Volailles / Escargots,
/// « Bandes suivies », colonnes Sevrés / Morts S/Mère / Poids Moyen / Cages, champ Cages et
/// aperçu des échéances) sont GARDÉS — décision client du 19/10/2026 — et placés APRÈS ce que le
/// Blade affiche. `test/suivi_reproduction_blade_test.dart` lit le Blade et le vérifie.
///
/// ⚠️⚠️ **LES ACTIONS DE CYCLE SONT GRISÉES** tant que le serveur n'accepte pas la mise à jour
/// d'un cycle envoyée par un poste (voir [SuiviReproductionRepository]) : les boutons du Blade
/// sont là, aux mêmes conditions, mais un clic dit pourquoi au lieu d'écrire une saisie perdue.
class SuiviReproductionScreen extends StatefulWidget {
  const SuiviReproductionScreen({
    super.key,
    required this.depot,
    this.onOuvrirSujet,
    this.onSaisirCouvoir,
  });

  final SuiviReproductionRepository depot;

  /// Ouvre la fiche d'un sujet. `null` : les références restent du texte.
  ///
  /// ⚠️ Une référence n'est cliquable QUE si un sujet porte ce nom : « R1 » peut
  /// être une cage, une lapine jamais enregistrée comme sujet, ou un reproducteur.
  /// Un lien vers une fiche inexistante serait pire que du texte.
  final void Function(String sujetId)? onOuvrirSujet;

  /// « Saisir le Couvoir du Jour → » : ouvre la fiche de saisie de l'espèce — `aviculture`
  /// (Fiches Reproducteurs) ou `helico` (Fiches Escargots), comme les deux `route()` du Blade.
  final void Function(String codeEspece)? onSaisirCouvoir;

  @override
  State<SuiviReproductionScreen> createState() =>
      _SuiviReproductionScreenState();
}

class _SuiviReproductionScreenState extends State<SuiviReproductionScreen> {
  /// Les quatre onglets du Blade, dans son ordre, avec ses icônes.
  static const onglets = <(String, IconData)>[
    ('Lapins', SymbolesAgri.cruelty_free),
    ('Volailles', SymbolesAgri.egg),
    ('Porcs', SymbolesAgri.pets),
    ('Escargots', SymbolesAgri.bug_report),
  ];

  /// Colonnes du tableau : les neuf du Blade, dans son ordre, PUIS les ajouts du poste.
  ///
  /// ⚠️ Ticket H7 : le Blade fait foi. « Sevrés (M/F) », « Morts S/Mère », « Poids Moyen (g) »
  /// et « Cages » viennent de la maquette et n'existent pas au web : la décision du 19/10/2026
  /// les garde, en fin de tableau, dans leur ordre relatif d'origine.
  static const _colonnesLapins = <(String, int)>[
    ('Bande', 3),
    ('N° Lapine', 2),
    ('Date Saillie', 2),
    ('Mâle N°', 2),
    ('Palpation', 3),
    ('Mise Bas Attendue', 2),
    ('Nés (Vivants)', 2),
    ('Statut', 2),
    ('Action', 4),
    ('Sevrés (M/F)', 2),
    ('Morts S/Mère', 2),
    ('Poids Moyen (g)', 2),
    ('Cages', 2),
  ];

  /// Même règle chez les porcs : neuf colonnes du Blade, puis « Sevrage (J+42) » (maquette).
  static const _colonnesPorcs = <(String, int)>[
    ('Bande', 3),
    ('N° Truie', 2),
    ('Date Saillie', 2),
    ('Verrat N°', 2),
    ('Retour Chaleur', 3),
    ('Mise Bas Attendue', 2),
    ('Nés (Vivants)', 2),
    ('Statut', 2),
    ('Action', 5),
    ('Sevrage (J+42)', 2),
  ];

  String _onglet = onglets.first.$1;

  DonneesSuiviReproduction? _donnees;
  bool _chargement = true;

  /// `identifiant → id` des sujets connus du poste.
  Map<String, String> _sujets = const {};

  /// ⚠️⚠️ **PORTÉS PAR L'ÉTAT, PAS PAR LA MODALE.** Créés puis libérés autour
  /// de `showDialog`, ils étaient encore reconstruits pendant l'animation de
  /// fermeture : « A TextEditingController was used after being disposed ».
  /// L'exception ne se voit qu'au rendu, une fois la saillie enregistrée —
  /// c'est-à-dire au moment le plus mal choisi.
  final _femelle = TextEditingController();
  final _male = TextEditingController();
  final _nesVivants = TextEditingController();
  final _nesMorts = TextEditingController();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _femelle.dispose();
    _male.dispose();
    _nesVivants.dispose();
    _nesMorts.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    final donnees = await widget.depot.charger();
    final sujets = await SujetsRepository(
      database: widget.depot.database,
    ).identifiants();
    if (!mounted) return;
    setState(() {
      _sujets = sujets;
      _donnees = donnees;
      _chargement = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: _chargement || _donnees == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              // ⚠️ `Builder` ET NON `LayoutBuilder` : la mise en page se
              // décide sur la largeur de l'ÉCRAN (MediaQuery), jamais sur
              // celle du contenu. Retirer les contraintes de la portée
              // interdit la rechute.
              builder: (context) {
                final large = AgriBreakpoints.large(context);

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // `<x-tab-page>` : la barre d'onglets, puis (`mt-md`) l'accordéon des KPI.
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.md),
                      // 🔴→✅ Ticket U14 — `x-kpi-accordion` : `grid-cols-2 xl:grid-cols-4` (le poste passait à quatre
                      // colonnes dès `md`).
                      _kpis(AgriBreakpoints.tresLarge(context)),
                      const SizedBox(height: AgriSpacing.md),
                      switch (_onglet) {
                        'Volailles' => _ongletCouvoir(
                          volailles: true,
                          jalons: const [
                            'Mise en Incubation J0',
                            'Éclosion Attendue J+21',
                          ],
                          resume: _donnees!.volailles,
                          // 🔴→✅ Ticket U14 — `grid-cols-2 lg:grid-cols-4` du Blade (le poste passait à `md`).
                          moyen: large,
                        ),
                        'Porcs' => _ongletCycles(
                          lapins: false,
                          cycles: _donnees!.porcs,
                        ),
                        'Escargots' => _ongletCouvoir(
                          volailles: false,
                          jalons: const [
                            'Placement Bac de Ponte J0',
                            'Éclosion Naissains Attendue J+25',
                          ],
                          resume: _donnees!.escargots,
                          moyen: large,
                        ),
                        _ => _ongletCycles(
                          lapins: true,
                          cycles: _donnees!.lapins,
                        ),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  // ── Cartes KPI ────────────────────────────────────────────────────────────

  /// `<x-kpi-accordion>` : les quatre `<x-kpi-card>` du Blade, libellés, icônes et couleurs.
  Widget _kpis(bool moyen) {
    final d = _donnees!;

    return _grille(
      colonnes: moyen ? 4 : 2,
      enfants: [
        _carteKpi(
          'Reproductrices Gestantes',
          '${d.gestantes}',
          SymbolesAgri.favorite,
          _CouleurKpi.bleu,
        ),
        _carteKpi(
          'Palpations / Échéances dues',
          '${d.palpationsDues}',
          SymbolesAgri.event,
          _CouleurKpi.mais,
        ),
        _carteKpi(
          'Mises bas / Éclosions (mois)',
          '${d.misesBasDuMois}',
          SymbolesAgri.child_care,
          _CouleurKpi.emeraude,
        ),
        _carteKpi(
          'Alertes Réforme / Pertes',
          '${d.echecs}',
          SymbolesAgri.warning,
          _CouleurKpi.rouge,
        ),
      ],
    );
  }

  /// `kpi-card.blade.php` : liseré et icône selon `color`, valeur `text-on-surface`.
  /// Ticket U14 — la grille CSS du Blade (`grid gap-md`) : colonnes de même largeur, cartes d'une rangée à la même
  /// hauteur, hauteur prise sur le CONTENU. Une `GridView` à proportions fixes débordait (« RenderFlex overflowed »)
  /// dès que la colonne rétrécissait, entre deux points de rupture.
  Widget _grille({required int colonnes, required List<Widget> enfants}) {
    final rangees = <Widget>[];
    for (var i = 0; i < enfants.length; i += colonnes) {
      if (i > 0) rangees.add(const SizedBox(height: AgriSpacing.md));
      rangees.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < colonnes; j++) ...[
                if (j > 0) const SizedBox(width: AgriSpacing.md),
                Expanded(child: i + j < enfants.length ? enfants[i + j] : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rangees);
  }

  Widget _carteKpi(
    String libelle,
    String valeur,
    IconData icone,
    _CouleurKpi couleur,
  ) => CarteKpi(
    libelle: libelle,
    valeur: valeur,
    icone: icone,
    couleurLisere: couleur.lisere,
    couleurIcone: couleur.icone,
    tailleValeur: AgriTypography.xxl,
  );

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (titre, icone) in onglets)
            InkWell(
              key: Key('onglet-repro-$titre'),
              onTap: () => setState(() => _onglet = titre),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icone,
                      size: 18,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : AgriColors.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        color: _onglet == titre
                            ? AgriColors.brandEmerald
                            : AgriColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // ── Briques d'onglet ──────────────────────────────────────────────────────

  /// `<h2>` du Blade (icône émeraude + titre) et son `<p>` de sous-titre.
  Widget _titreOnglet(
    IconData icone,
    String titre,
    String sousTitre, {
    Widget? action,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: AgriColors.brandEmerald),
                const SizedBox(width: AgriSpacing.xs),
                Flexible(
                  child: Text(
                    titre,
                    style: const TextStyle(
                      fontSize: AgriTypography.lg,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.xs),
            Text(
              sousTitre,
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ],
        ),
      ),
      ?action,
    ],
  );

  /// `components/cycle-reminder.blade.php` : icône, « Rappel du cycle : », puis les étapes
  /// séparées par une flèche ; l'étape `active` en vert.
  Widget _rappelDuCycle(List<(String, bool)> etapes, String cle) => Container(
    key: Key('rappel-cycle-$cle'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.infoBlue.withValues(alpha: 0.05),
      border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.20)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Wrap(
      spacing: AgriSpacing.md,
      runSpacing: AgriSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(SymbolesAgri.event_repeat, size: 20, color: AgriColors.infoBlue),
        const Text(
          'Rappel du cycle :',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
        Wrap(
          spacing: AgriSpacing.xs,
          runSpacing: AgriSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < etapes.length; i++) ...[
              if (i > 0)
                const Icon(
                  SymbolesAgri.arrow_forward,
                  size: 14,
                  color: AgriColors.outline,
                ),
              _etape(etapes[i].$1, active: etapes[i].$2),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _etape(String libelle, {required bool active}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 4),
    decoration: BoxDecoration(
      color: active
          ? AgriColors.brandEmerald.withValues(alpha: 0.10)
          : AgriColors.surfaceCard,
      border: Border.all(
        color: active
            ? AgriColors.brandEmerald.withValues(alpha: 0.30)
            : AgriColors.outlineVariant,
      ),
      borderRadius: BorderRadius.circular(AgriRadius.full),
    ),
    child: Text(
      libelle,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: active ? AgriColors.brandEmerald : AgriColors.brandForest,
      ),
    ),
  );

  static const _entete = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  // ── Onglets Lapins et Porcs ───────────────────────────────────────────────

  Widget _ongletCycles({
    required bool lapins,
    required List<CycleReproduction> cycles,
  }) {
    const l = SuiviReproductionRepository.cycleLapins;
    const p = SuiviReproductionRepository.cyclePorcs;
    final cle = lapins ? 'lapins' : 'porcs';
    final controle = lapins ? 'Palpation' : 'Retour Chaleur';
    final (jControle, jMiseBas, jSevrage) = lapins
        ? (l.palpation, l.miseBas, l.sevrage)
        : (p.retourChaleur, p.miseBas, p.sevrage);
    final colonnes = lapins ? _colonnesLapins : _colonnesPorcs;
    final largeur =
        colonnes.fold<int>(0, (t, c) => t + c.$2) * 50.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titreOnglet(
          lapins ? SymbolesAgri.cruelty_free : SymbolesAgri.pets,
          lapins
              ? 'Suivi Reproduction — Cuniculture (Lapins)'
              : 'Suivi Reproduction — Porciculture (Porcs)',
          'Suivi par ${lapins ? 'lapine' : 'truie'} nommée : saillie, '
              '${controle.toLowerCase()} J+$jControle, mise bas J+$jMiseBas et '
              'sevrage J+$jSevrage.',
          action: ElevatedButton.icon(
            key: Key('declarer-saillie-$cle'),
            onPressed: () => _ouvrirDeclaration(porcs: !lapins),
            icon: const Icon(SymbolesAgri.add_circle, size: 18),
            label: Text(
              lapins ? 'Déclarer une Saillie Lapin' : 'Déclarer une Saillie Porc',
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.full),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _rappelDuCycle([
          ('Saillie J0', false),
          ('$controle J+$jControle', false),
          ('Mise bas J+$jMiseBas', true),
          ('Sevrage J+$jSevrage', false),
        ], cle),
        // ⚠️ AJOUT DU POSTE, GARDÉ (décision du 19/10/2026) : « Boîte à nid J+28 » n'est pas une
        // étape du Blade. Jalon informatif, sans colonne ni action : en ligne annexe, sous le
        // rappel du web, plutôt qu'au milieu de ses quatre étapes.
        if (lapins)
          const Padding(
            key: Key('jalon-annexe-lapins'),
            padding: EdgeInsets.only(top: AgriSpacing.xs, left: AgriSpacing.md),
            child: Text(
              'Jalon intermédiaire : Boîte à nid J+28 (informatif, sans action de suivi).',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ),
        const SizedBox(height: AgriSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: LayoutBuilder(
            builder: (_, contraintes) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: max(largeur, contraintes.maxWidth),
                child: Column(
                  children: [
                    Container(
                      key: Key('entete-cycles-$cle'),
                    color: AgriColors.surfaceZebra,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AgriSpacing.sm,
                      vertical: AgriSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        for (final (libelle, flex) in colonnes)
                          Expanded(
                            flex: flex,
                            child: Text(
                              libelle.toUpperCase(),
                              style: _entete,
                              // `text-right` du Blade sur « Nés (Vivants) » et « Action ».
                              textAlign:
                                  libelle == 'Nés (Vivants)' || libelle == 'Action'
                                  ? TextAlign.right
                                  : TextAlign.left,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (cycles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AgriSpacing.lg),
                      child: Center(
                        child: Text(
                          'Aucune saillie déclarée pour le moment.',
                          style: TextStyle(
                            fontSize: AgriTypography.xs,
                            color: AgriColors.outline,
                          ),
                        ),
                      ),
                    ),
                  for (var i = 0; i < cycles.length; i++)
                    Container(
                      key: Key('cycle-$i'),
                      color: i.isOdd
                          ? AgriColors.surfaceZebra
                          : AgriColors.surfaceCard,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AgriSpacing.sm,
                        vertical: AgriSpacing.sm,
                      ),
                      child: _ligneCycle(cycles[i], colonnes, lapins: lapins),
                    ),
                ],
              ),
            ),
          ),
          ),
        ),
        // ⚠️ AJOUT DU POSTE, GARDÉ : le bandeau dit ce qui se saisit ici et ce qui reste web.
        if (!widget.depot.miseAJourCycleAccepteeParServeur) ...[
          const SizedBox(height: AgriSpacing.md),
          _mentionLectureSeule(),
        ],
      ],
    );
  }

  /// Une ligne du tableau : les neuf cellules du Blade, puis les cellules propres au poste.
  Widget _ligneCycle(
    CycleReproduction c,
    List<(String, int)> colonnes, {
    required bool lapins,
  }) {
    final e = c.evenement;
    int flex(int i) => colonnes[i].$2;

    return Row(
      children: [
        // Bande — `font-bold text-brand-forest`.
        _cellule(
          c.codeBande,
          flex: flex(0),
          gras: true,
          couleur: AgriColors.brandForest,
        ),
        // N° — `font-mono font-bold text-brand-emerald` (lien vers la fiche sujet : ajout gardé).
        _celluleRef(e.motherRef, flex: flex(1), gras: true),
        _cellule(_date(e.saillieDate), flex: flex(2)),
        // Mâle / Verrat — `font-mono`, `—` sans mâle.
        e.sireRef == null
            ? _cellule('—', flex: flex(3))
            : _celluleRef(e.sireRef!, flex: flex(3)),
        Expanded(flex: flex(4), child: _celluleControle(c)),
        // Mise Bas — la date réelle, sinon l'attendue ; en gras.
        _cellule(_date(c.miseBasAffichee), flex: flex(5), gras: true),
        _cellule(c.libelleNes, flex: flex(6), aDroite: true),
        Expanded(flex: flex(7), child: _pastilleStatut(c.statut)),
        Expanded(flex: flex(8), child: _celluleAction(c)),
        // ── Ajouts du poste (décision du 19/10/2026), après les neuf colonnes du Blade ──
        if (lapins) ...[
          // ⚠️⚠️ TROIS COLONNES SANS DONNÉE AU POSTE, ET C'EST DIT PAR UN TIRET.
          // `livestock_reproduction_events` ne porte ni sevrés, ni ventilation M/F, ni pesée :
          // elle suit un CYCLE, pas une portée. Et aucun référentiel ne modélise de cage.
          _cellule('—', flex: flex(9)),
          _cellule(e.nesMorts == null ? '—' : '${e.nesMorts}', flex: flex(10)),
          _cellule('—', flex: flex(11)),
          _cellule('—', flex: flex(12)),
        ] else
          // ⚠️ Sevrage : stocké, sinon déduit de la mise bas réelle (J+42).
          _cellule(
            e.sevrageDateExpected != null
                ? _date(e.sevrageDateExpected)
                : _dateDecalee(
                    e.miseBasDateActual,
                    SuiviReproductionRepository.cyclePorcs.sevrage,
                  ),
            flex: flex(9),
          ),
      ],
    );
  }

  /// Référence de sujet : un LIEN vers sa fiche quand un sujet porte ce nom.
  Widget _celluleRef(String ref, {required int flex, bool gras = false}) {
    final id = _sujets[ref];
    final style = TextStyle(
      fontSize: AgriTypography.xs,
      fontFamily: 'monospace',
      fontWeight: gras ? FontWeight.bold : FontWeight.normal,
      color: gras ? AgriColors.brandEmerald : AgriColors.onSurface,
    );

    if (id == null || widget.onOuvrirSujet == null) {
      return Expanded(
        flex: flex,
        child: Text(ref, overflow: TextOverflow.ellipsis, style: style),
      );
    }

    return Expanded(
      flex: flex,
      child: InkWell(
        key: Key('lien-sujet-$ref'),
        onTap: () => widget.onOuvrirSujet!(id),
        child: Text(
          ref,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(
            color: AgriColors.brandEmerald,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Widget _cellule(
    String texte, {
    required int flex,
    bool gras = false,
    bool aDroite = false,
    Color couleur = AgriColors.onSurface,
  }) => Expanded(
    flex: flex,
    child: Text(
      texte,
      overflow: TextOverflow.ellipsis,
      textAlign: aDroite ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: gras ? FontWeight.bold : FontWeight.normal,
        color: couleur,
      ),
    ),
  );

  /// Colonne « Palpation » / « Retour Chaleur » du Blade : `dd/mm/yyyy (Positif|Négatif)` une
  /// fois faite, sinon `Prévue dd/mm/yyyy` — en rouge gras dès l'échéance atteinte.
  ///
  /// ⚠️ **TROIS ÉTATS, PAS DEUX.** `palpation_date` nulle ne veut pas dire « négative » : elle
  /// veut dire « pas encore faite ». Confondre les deux ferait réformer une lapine jamais palpée.
  Widget _celluleControle(CycleReproduction c) {
    final e = c.evenement;

    if (e.palpationDate != null) {
      return Text(
        '${_date(e.palpationDate)} (${e.status == 'echec' ? 'Négatif' : 'Positif'})',
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: AgriTypography.xs),
      );
    }

    final echu = c.controleEchu(HeureBenin.maintenant());
    return Text(
      'Prévue ${_date(c.echeanceControle)}',
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: echu ? FontWeight.bold : FontWeight.normal,
        color: echu ? AgriColors.errorDeep : AgriColors.outline,
      ),
    );
  }

  /// Les quatre pastilles du Blade, avec leurs couleurs.
  Widget _pastilleStatut(StatutCycle statut) {
    final (fond, texte, bord) = switch (statut) {
      StatutCycle.reformeEchec => (
        AgriColors.errorBg,
        AgriColors.errorDeep,
        AgriColors.errorDeep.withValues(alpha: 0.30),
      ),
      StatutCycle.clos => (
        AgriColors.surfaceZebra,
        AgriColors.outline,
        AgriColors.outlineVariant,
      ),
      StatutCycle.mereAllaitante => (
        AgriColors.brandEmerald.withValues(alpha: 0.10),
        AgriColors.brandEmerald,
        AgriColors.brandEmerald.withValues(alpha: 0.30),
      ),
      StatutCycle.gestante => (
        AgriColors.infoBlue.withValues(alpha: 0.10),
        AgriColors.infoBlue,
        AgriColors.infoBlue.withValues(alpha: 0.30),
      ),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: fond,
          border: Border.all(color: bord),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Text(
          statut.libelle,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: texte,
          ),
        ),
      ),
    );
  }

  // ── Actions de cycle ──────────────────────────────────────────────────────

  /// Cellule « Action » du Blade, aux mêmes conditions : `Palpation +` / `Palpation −` (ou
  /// `Retour Chaleur`), `Saisir Mise Bas`, `Clôturer (Sevrage)`.
  Widget _celluleAction(CycleReproduction c) {
    final id = c.evenement.id;
    final controle = c.libelleControle;

    final boutons = switch (c.action) {
      ActionCycle.controle => [
        _boutonAction(
          Key('action-plus-$id'),
          '$controle +',
          AgriColors.brandEmerald,
          () => _palpation(id, positive: true),
        ),
        _boutonAction(
          Key('action-moins-$id'),
          '$controle −',
          AgriColors.errorRed,
          () => _palpation(id, positive: false),
        ),
      ],
      ActionCycle.miseBas => [
        _boutonAction(
          Key('action-mise-bas-$id'),
          'Saisir Mise Bas',
          AgriColors.brandEmerald,
          () => _ouvrirMiseBas(id),
        ),
      ],
      ActionCycle.cloture => [
        _boutonAction(
          Key('action-cloturer-$id'),
          'Clôturer (Sevrage)',
          AgriColors.brandForest,
          () => _cloturer(id),
        ),
      ],
      ActionCycle.aucune => const <Widget>[],
    };

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: boutons,
    );
  }

  /// Pastille d'action du Blade (`text-[10px] font-bold text-white px-2 py-1 rounded-full`).
  ///
  /// ⚠️⚠️ Verrou fermé : le bouton reste visible — le web l'a — mais grisé ; l'info-bulle et un
  /// toast d'avertissement disent pourquoi. Rien n'est écrit.
  Widget _boutonAction(
    Key cle,
    String libelle,
    Color couleur,
    Future<void> Function() action,
  ) {
    final ouvert = widget.depot.miseAJourCycleAccepteeParServeur;

    final pastille = InkWell(
      key: cle,
      borderRadius: BorderRadius.circular(AgriRadius.full),
      onTap: ouvert
          ? action
          : () => ToastAgri.afficher(
              context,
              SuiviReproductionRepository.motifActionsCycleFermees,
              type: TypeToast.avertissement,
            ),
      child: Opacity(
        opacity: ouvert ? 1 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: couleur,
            borderRadius: BorderRadius.circular(AgriRadius.full),
            boxShadow: AgriShadows.sm,
          ),
          child: Text(
            libelle,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );

    return ouvert
        ? pastille
        : Tooltip(
            message: SuiviReproductionRepository.motifActionsCycleFermees,
            child: pastille,
          );
  }

  Future<void> _palpation(String id, {required bool positive}) async {
    try {
      await widget.depot.enregistrerPalpation(id, positive: positive);
    } on ActionCycleIndisponible catch (e) {
      _toast(e.message, TypeToast.avertissement);
      return;
    }
    await _charger();
    _toast(SuiviReproductionRepository.messagePalpation);
  }

  Future<void> _cloturer(String id) async {
    try {
      await widget.depot.cloturerCycle(id);
    } on ActionCycleIndisponible catch (e) {
      _toast(e.message, TypeToast.avertissement);
      return;
    }
    await _charger();
    _toast(SuiviReproductionRepository.messageCloture);
  }

  /// `modal-misebas` du Blade : « Saisir la Mise Bas », Nés Vivants * / Nés Morts (0 par
  /// défaut, comme `openMiseBasModal`), Annuler / Enregistrer.
  Future<void> _ouvrirMiseBas(String id) async {
    _nesVivants.text = '0';
    _nesMorts.text = '0';
    String? erreur;

    final enregistree = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: 'Saisir la Mise Bas',
          largeur: LargeurModale.sm,
          contenu: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _champ(
                      'Nés Vivants *',
                      TextField(
                        key: const Key('mise-bas-vivants'),
                        controller: _nesVivants,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: AgriTypography.sm,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: _decoration(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(
                    child: _champ(
                      'Nés Morts',
                      TextField(
                        key: const Key('mise-bas-morts'),
                        controller: _nesMorts,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: AgriTypography.sm),
                        decoration: _decoration(),
                      ),
                    ),
                  ),
                ],
              ),
              if (erreur != null) ...[
                const SizedBox(height: AgriSpacing.md),
                Text(
                  erreur!,
                  key: const Key('mise-bas-erreur'),
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.errorDeep,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BoutonModalePrimaire(
              key: const Key('mise-bas-enregistrer'),
              libelle: 'Enregistrer',
              onPressed: () async {
                final vivants = int.tryParse(_nesVivants.text.trim());
                final morts = int.tryParse(_nesMorts.text.trim());
                if (vivants == null || morts == null) {
                  rafraichir(
                    () => erreur =
                        'Les nombres de nés vivants et de nés morts sont requis.',
                  );
                  return;
                }

                try {
                  await widget.depot.enregistrerMiseBas(
                    id,
                    nesVivants: vivants,
                    nesMorts: morts,
                  );
                  if (context.mounted) Navigator.of(context).pop(true);
                } on ArgumentError catch (e) {
                  rafraichir(() => erreur = '${e.message}');
                } on ActionCycleIndisponible catch (e) {
                  rafraichir(() => erreur = e.message);
                }
              },
            ),
          ],
        ),
      ),
    );

    if (enregistree == true) {
      await _charger();
      _toast(SuiviReproductionRepository.messageMiseBas);
    }
  }

  // ── Onglets Volailles et Escargots ────────────────────────────────────────

  /// ⚠️⚠️ **RÉSUMÉ, PAS UN SECOND FORMULAIRE.** Ces deux panneaux recouvrent exactement ce que
  /// les fiches Reproducteurs et Escargots saisissent déjà (composant Livewire, ticket 3.10) :
  /// titre, texte et trois KPI du Blade, puis le lien « Saisir le Couvoir du Jour → ».
  Widget _ongletCouvoir({
    required bool volailles,
    required List<String> jalons,
    required ResumeCouvoir resume,
    required bool moyen,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titreOnglet(
          volailles ? SymbolesAgri.egg : SymbolesAgri.bug_report,
          'Suivi Reproduction ${volailles ? 'Volailles' : 'Escargots'} — '
              'Couvoir & Éclosion',
          'La saisie quotidienne du couvoir se fait depuis la fiche journalière dédiée — '
              'résumé réel du mois affiché ci-dessous, un seul point de vérité pour cette '
              'donnée.',
        ),
        const SizedBox(height: AgriSpacing.md),
        _grille(
          colonnes: moyen ? 4 : 2,
          enfants: [
            _carteKpi(
              'Œufs Couvés (mois)',
              '${resume.couves}',
              SymbolesAgri.egg,
              _CouleurKpi.bleu,
            ),
            _carteKpi(
              'Naissains Nés (mois)',
              '${resume.nes}',
              SymbolesAgri.child_care,
              _CouleurKpi.emeraude,
            ),
            _carteKpi(
              "Taux d'Éclosion",
              resume.libelleTaux,
              SymbolesAgri.egg_alt,
              _CouleurKpi.mais,
            ),
            // ⚠️ AJOUT DU POSTE, GARDÉ (décision du 19/10/2026) : absent du Blade, après ses
            // trois cartes.
            _carteKpi(
              'Bandes suivies',
              '${resume.lots}',
              SymbolesAgri.inventory_2,
              _CouleurKpi.foret,
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            key: const Key('lien-couvoir'),
            onPressed: () =>
                widget.onSaisirCouvoir?.call(volailles ? 'aviculture' : 'helico'),
            icon: const Icon(SymbolesAgri.edit_note, size: 18),
            label: const Text(
              'Saisir le Couvoir du Jour →',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.brandEmerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.full),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
            ),
          ),
        ),
        // ⚠️ AJOUT DU POSTE, GARDÉ : le bandeau du cycle d'incubation, après le contenu du Blade.
        const SizedBox(height: AgriSpacing.md),
        _rappelDuCycle([
          for (var i = 0; i < jalons.length; i++)
            (jalons[i], i == jalons.length - 1),
        ], volailles ? 'volailles' : 'escargots'),
      ],
    );
  }

  Widget _mentionLectureSeule() => Container(
    key: const Key('mention-lecture-seule'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.accentYellow.withValues(alpha: 0.10),
      border: Border.all(
        color: AgriColors.accentYellow.withValues(alpha: 0.30),
      ),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(SymbolesAgri.info, size: 18, color: AgriColors.brandForest),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Text(
            'La saillie se déclare ici, hors ligne : elle part au prochain '
            'tirage.${widget.depot.miseAJourCycleAccepteeParServeur ? ' Palpation, mise bas et clôture aussi.' : ' ${SuiviReproductionRepository.motifActionsCycleFermees}'}',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Modale « Déclarer une Saillie » ───────────────────────────────────────

  /// `modal-saillie` du Blade (`max-width="sm"`) : Bande * (« -- Sélectionner -- » en tête),
  /// N° Lapine * / N° Truie *, Mâle Saillisseur N° / Verrat N° — FACULTATIF (`sireRef` est
  /// `nullable` : une insémination n'a pas de mâle) —, Date de Saillie *.
  ///
  /// ⚠️ AJOUTS DU POSTE, GARDÉS (décision du 19/10/2026), après les champs du Blade et chez les
  /// lapins seulement : « Cages Occupées » (désactivé) et l'aperçu des échéances.
  Future<void> _ouvrirDeclaration({required bool porcs}) async {
    final espece = porcs ? 'porciculture' : 'cuniculture';
    final bandes = await widget.depot.bandesDeclarables(espece);

    if (!mounted) return;

    _femelle.clear();
    _male.clear();
    // `newDeclaration()` : aucune bande choisie, date du jour.
    var bande = '';
    var date = HeureBenin.aujourdhui();
    String? erreur;

    final declaree = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: porcs
              ? 'Déclarer une Saillie (Porciculture)'
              : 'Déclarer une Saillie (Cuniculture)',
          largeur: LargeurModale.sm,
          contenu: Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _champ(
                  'Bande *',
                  DropdownButtonFormField<String>(
                    key: const Key('saillie-bande'),
                    // ⚠️ `w-full` du Blade : sans `isExpanded`, un code de bande long déborde
                    // de la modale `max-w-sm`.
                    isExpanded: true,
                    initialValue: bande,
                    decoration: _decoration(),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('-- Sélectionner --'),
                      ),
                      for (final b in bandes)
                        DropdownMenuItem(value: b.id, child: Text(b.code)),
                    ],
                    onChanged: (v) => bande = v ?? '',
                  ),
                ),
                const SizedBox(height: AgriSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _champ(
                        porcs ? 'N° Truie *' : 'N° Lapine *',
                        TextField(
                          key: const Key('saillie-femelle'),
                          controller: _femelle,
                          style: const TextStyle(
                            fontSize: AgriTypography.sm,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: AgriColors.brandEmerald,
                          ),
                          decoration: _decoration(
                            exemple: porcs ? 'ex : T3' : 'ex : R8',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AgriSpacing.sm),
                    Expanded(
                      child: _champ(
                        porcs ? 'Verrat N°' : 'Mâle Saillisseur N°',
                        TextField(
                          key: const Key('saillie-male'),
                          controller: _male,
                          style: const TextStyle(
                            fontSize: AgriTypography.sm,
                            fontFamily: 'monospace',
                          ),
                          decoration: _decoration(
                            exemple: porcs ? 'ex : V1' : 'ex : M2',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AgriSpacing.md),
                ChampDateFormulaire(
                  cle: const Key('saillie-date'),
                  etiquette: 'Date de Saillie *',
                  valeur: date,
                  onTap: () async {
                    final choisie = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: HeureBenin.maintenant(),
                    );
                    if (choisie != null) rafraichir(() => date = choisie);
                  },
                ),
                if (!porcs) ...[
                  const SizedBox(height: AgriSpacing.md),
                  // ⚠️⚠️ CHAMP PRÉSENT ET DÉSACTIVÉ : aucune table ne modélise de
                  // sous-division « cage » — le composant Livewire l'avait déjà
                  // constaté au ticket 3.10. Le laisser saisissable perdrait la
                  // valeur en silence.
                  _champ(
                    'Cages Occupées',
                    TextField(
                      key: const Key('saillie-cages'),
                      enabled: false,
                      decoration: _decoration().copyWith(
                        hintText: 'Référentiel des cages absent du schéma',
                      ),
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.md),
                  _apercuEcheances(date),
                ],
                if (erreur != null) ...[
                  const SizedBox(height: AgriSpacing.md),
                  Text(
                    erreur!,
                    key: const Key('saillie-erreur'),
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.errorDeep,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BoutonModalePrimaire(
              key: const Key('saillie-enregistrer'),
              libelle: 'Enregistrer la Saillie',
              onPressed: () async {
                // `saveDeclaration()` : `lotId` et `motherRef` requis, `sireRef` nullable.
                // ⚠️ Le web n'a pas de traduction (`lang/` absent) : il affiche les messages
                // anglais par défaut de Laravel. Le poste les dit en français.
                if (bande.isEmpty) {
                  rafraichir(() => erreur = 'La bande est requise.');
                  return;
                }
                if (_femelle.text.trim().isEmpty) {
                  rafraichir(
                    () => erreur =
                        'Le numéro de la ${porcs ? 'truie' : 'lapine'} est requis.',
                  );
                  return;
                }

                try {
                  await widget.depot.declarerSaillie(
                    lotId: bande,
                    numeroFemelle: _femelle.text.trim(),
                    numeroMale: _male.text.trim().isEmpty
                        ? null
                        : _male.text.trim(),
                    dateSaillie: date,
                  );
                  if (context.mounted) Navigator.of(context).pop(true);
                } on ArgumentError catch (e) {
                  rafraichir(() => erreur = '${e.message}');
                }
              },
            ),
          ],
        ),
      ),
    );

    if (declaree == true) {
      await _charger();
      _toast(SuiviReproductionRepository.messageSaillie);
    }
  }

  /// « Ligne du temps automatique calculée » de la maquette (ajout du poste, gardé).
  Widget _apercuEcheances(DateTime saillie) {
    const c = SuiviReproductionRepository.cycleLapins;

    return Container(
      key: const Key('apercu-echeances'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.infoBlue.withValues(alpha: 0.10),
        border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(SymbolesAgri.calculate, size: 14, color: AgriColors.brandForest),
              SizedBox(width: 4),
              // ⚠️ `Expanded` : le titre de l'aperçu se replie, comme le
              // `<p class="font-bold flex items-center gap-xs">` du navigateur.
              Expanded(
                child: Text(
                  'Ligne du temps automatique calculée :',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _echeance('Palpation (J+14)', saillie, c.palpation),
              ),
              // ⚠️ « Boîte à nid J+28 » : jalon informatif, sans colonne dédiée
              // (même constat côté Livewire).
              Expanded(child: _echeance('Boîte à nid (J+28)', saillie, 28)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _echeance('Mise bas (J+30)', saillie, c.miseBas)),
              Expanded(child: _echeance('Sevrage (J+60)', saillie, c.sevrage)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _echeance(String libelle, DateTime origine, int jours) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text.rich(
      TextSpan(
        text: '$libelle : ',
        children: [
          TextSpan(
            text: _date(HeureBenin.plusJours(origine, jours)),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 10, color: AgriColors.brandForest),
    ),
  );

  /// `<label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">` + champ.
  Widget _champ(String etiquette, Widget champ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
        child: Text(
          etiquette.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
      ),
      champ,
    ],
  );

  InputDecoration _decoration({String? exemple}) => InputDecoration(
    isDense: true,
    hintText: exemple,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: 12,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      borderSide: const BorderSide(color: AgriColors.outlineVariant),
    ),
  );

  /// Toasts du web (`$dispatch('toast', …)`) : composant unique `ToastAgri`.
  void _toast(String message, [TypeToast type = TypeToast.succes]) {
    if (!mounted) return;
    ToastAgri.afficher(context, message, type: type);
  }

  // ── Formats ───────────────────────────────────────────────────────────────

  static String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _dateDecalee(DateTime? origine, int jours) =>
      origine == null ? '—' : _date(HeureBenin.plusJours(origine, jours));
}

/// Les variantes `color` de `kpi-card.blade.php` : liseré et icône.
enum _CouleurKpi {
  emeraude(AgriColors.brandEmerald, AgriColors.brandEmerald),
  mais(AgriColors.accentYellow, AgriColors.brandForest),
  rouge(AgriColors.errorRed, AgriColors.errorRed),
  bleu(AgriColors.infoBlue, AgriColors.infoBlue),
  foret(AgriColors.brandForest, AgriColors.brandForest);

  const _CouleurKpi(this.lisere, this.icone);

  final Color lisere;
  final Color icone;
}
