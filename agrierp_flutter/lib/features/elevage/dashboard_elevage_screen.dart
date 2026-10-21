import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'bilan_technico_economique_repository.dart';
import 'bilan_technico_economique_vue.dart';
import 'dashboard_elevage_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Dashboard Élevage — le maître est `Livewire\Elevage\DashboardElevage` et sa vue
/// `dashboard-elevage.blade.php` (Doctrine, article 5 ; ticket H6).
///
/// ⚠️⚠️ **LE BLADE FAIT FOI.** Les **cinq onglets** dans son ordre et avec ses icônes, puis, dans
/// chaque panneau, ses titres, cartes, blocs et tableaux. Les AJOUTS du poste absents du web
/// (courbes GMQ, cartes et filtre d'espèce de l'onglet GMQ, sélecteur, horizons et cartes de
/// prévision, liste des rappels VMS, note « 2026 vs 2025 »…) sont CONSERVÉS par décision client du
/// 19/10/2026, en plus du Blade : ils seront construits au web (ticket H11).
///
/// ⚠️ **L'ONGLET « RENTABILITÉ » EST PORTÉ (ticket F0.63)** : voir [BilanTechnicoEconomiqueVue].
class DashboardElevageScreen extends StatefulWidget {
  const DashboardElevageScreen({
    super.key,
    required this.depot,
    this.quand,
    this.onOuvrirSoins,
  });

  final DashboardElevageRepository depot;

  /// Instant de calcul (tests) ; `null` = maintenant.
  final DateTime? quand;

  /// Lien « Voir le calendrier complet → » du Blade : ouvre Soins et vaccins.
  final VoidCallback? onOuvrirSoins;

  /// Les cinq onglets du Blade, dans son ordre, avec ses icônes.
  ///
  /// ⚠️ `monitoring` (Material Symbols) n'existe pas dans `Icons` : `ssid_chart`, axes et ligne
  /// brisée, est le glyphe le plus proche.
  static const onglets = <(String, IconData)>[
    ('Synthèse Globale', SymbolesAgri.dashboard),
    ('GMQ & Croissance', SymbolesAgri.ssid_chart),
    // Libellé « Rentabilité » : décision client du 17/10/2026 (prototype : « Bilan Technico-Économique »).
    ('Rentabilité', SymbolesAgri.account_balance_wallet),
    ('Analyse Sanitaire', SymbolesAgri.coronavirus),
    ('Prévision de Croissance', SymbolesAgri.query_stats),
  ];

  /// Colonnes du tableau « GMQ & Croissance » du Blade (`<th>`), dans son ordre.
  static const colonnesGmq = <(String, int)>[
    ('Bande', 3),
    ('Filière', 3),
    ('Poids Initial (g)', 2),
    ('Poids Actuel (g)', 2),
    ('Jours', 1),
    ('GMQ (g/jour)', 2),
  ];

  /// Colonnes du tableau « Prévision de Croissance » du Blade, dans son ordre.
  static const colonnesPrevision = <(String, int)>[
    ('Bande', 3),
    ('Poids Actuel (g)', 2),
    ('Tendance (g/j)', 2),
    ('Projection à 30 jours (g)', 2),
  ];

  /// Colonnes du tableau « Analyse Sanitaire » du Blade, dans son ordre.
  static const colonnesSanitaire = <(String, int)>[
    ('Filière', 3),
    ('Nb Traitements (mois)', 2),
    ('Coût Total', 2),
    ('Taux de Morbidité %', 2),
  ];

  @override
  State<DashboardElevageScreen> createState() => _DashboardElevageScreenState();
}

class _DashboardElevageScreenState extends State<DashboardElevageScreen> {
  static const onglets = DashboardElevageScreen.onglets;

  String _onglet = onglets.first.$1;

  /// Filtre d'espèce des onglets GMQ et Sanitaire — « all » dans la maquette.
  String _espece = 'all';

  DonneesDashboardElevage? _donnees;
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    final donnees = await widget.depot.charger(quand: widget.quand);
    if (!mounted) return;
    setState(() {
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
                      _entete(large),
                      const SizedBox(height: AgriSpacing.md),
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.lg),
                      switch (_onglet) {
                        'GMQ & Croissance' => _ongletGmq(large),
                        'Rentabilité' => _ongletBilan(),
                        'Analyse Sanitaire' => _ongletSanitaire(large),
                        'Prévision de Croissance' => _ongletPrevision(),
                        _ => _ongletSynthese(large),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  // ── En-tête et onglets ────────────────────────────────────────────────────

  Widget _entete(bool large) => Container(
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
              SymbolesAgri.dashboard,
              size: 26,
              color: AgriColors.brandEmerald,
            ),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              'Dashboard Élevage',
              style: TextStyle(
                fontSize: large ? 24 : 20,
                fontWeight: FontWeight.bold,
                color: AgriColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          'Pilotage consolidé : autonomie alimentaire, croissance (GMQ) '
          'et rentabilité par bande.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ],
    ),
  );

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (titre, icone) in onglets)
            InkWell(
              key: Key('onglet-$titre'),
              onTap: () => setState(() => _onglet = titre),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: 10,
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

  // ── Onglet 1 : Synthèse Globale ───────────────────────────────────────────

  Widget _ongletSynthese(bool large) {
    final d = _donnees!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GrilleKpi(colonnes: large ? 4 : 2, children: [
            _carteKpi(
              libelle: 'Effectif Total Vivant',
              valeur: DashboardElevageRepository.milliers(
                d.effectifTotal.toDouble(),
              ),
              legende: 'Toutes espèces actives',
              icone: SymbolesAgri.pets,
              barre: AgriColors.brandEmerald,
            ),
            // ⚠️⚠️ NON CALCULABLE, ET DÉJÀ CONSTATÉ CÔTÉ WEB (carte marquée
            // `pending`). Le stock d'aliment se compte en SACS ; le poids du
            // sac ne vit que dans le nom du produit (« Aliment ponte 25kg »),
            // jamais dans une colonne. Lire « 25 » dans un libellé serait
            // inventer une donnée de gestion.
            _carteKpi(
              libelle: 'Autonomie Aliment Min.',
              valeur: '—',
              legende: 'Conditionnement (kg/unité) absent du catalogue',
              icone: SymbolesAgri.inventory_2,
              barre: AgriColors.accentYellow,
              couleurIcone: AgriColors.brandForest,
            ),
            // GMQ CUMULÉ consolidé (moyenne des bandes actives), écrit comme PHP écrit un flottant.
            _carteKpi(
              libelle: 'GMQ Moyen',
              valeur: d.gmqMoyen == null
                  ? '—'
                  : '${DashboardElevageRepository.nombrePhp(d.gmqMoyen!)} g/j',
              legende: d.gmqMoyen == null
                  ? 'Moins de 2 pesées enregistrées'
                  : 'Consolidé, toutes bandes',
              icone: SymbolesAgri.trending_up,
              barre: AgriColors.infoBlue,
              couleurIcone: AgriColors.infoBlue,
            ),
            // Ticket H6 : sept jours (`now()->subDays(6)` → `now()`), dénominateur
            // `previousEffectif()`, « 0,0 % » sans dénominateur — comme le web.
            _carteKpi(
              libelle: 'Mortalité Cumulée (7j)',
              valeur: DashboardElevageRepository.pourcent(d.mortalite7j),
              legende: 'Alerte si > 10%/semaine',
              icone: SymbolesAgri.health_and_safety,
              barre: AgriColors.errorRed,
              couleurIcone: AgriColors.errorRed,
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.lg),
        _cartesEspeces(large),
        const SizedBox(height: AgriSpacing.lg),
        _resumeEtRappels(large),
        const SizedBox(height: AgriSpacing.lg),
        _courbeEspeces(),
      ],
    );
  }

  /// Icônes du semis des espèces (`livestock_species.icon`), par code.
  static const _iconesEspeces = {
    'cuniculture': SymbolesAgri.cruelty_free,
    'aviculture': SymbolesAgri.egg,
    'porciculture': SymbolesAgri.pets,
    'helico': SymbolesAgri.bug_report,
  };

  Widget _cartesEspeces(bool large) {
    final cartes = _donnees!.especes.map((carte) {
      return Container(
        key: Key('carte-espece-${carte.code}'),
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.surfaceCard,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  _iconesEspeces[carte.code] ?? SymbolesAgri.pets,
                  size: 20,
                  color: AgriColors.brandEmerald,
                ),
                const SizedBox(width: AgriSpacing.xs),
                Flexible(
                  child: Text(
                    carte.titre,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AgriSpacing.sm),
            for (final (libelle, valeur, critique) in carte.lignes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        libelle,
                        style: const TextStyle(
                          fontSize: AgriTypography.xs,
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: AgriSpacing.xs),
                    Text(
                      valeur,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        // « Autonomie aliment » : `text-outline` dans le Blade.
                        color: critique
                            ? AgriColors.errorDeep
                            : valeur == '—'
                            ? AgriColors.outline
                            : AgriColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }).toList();

    if (!large) {
      return Column(
        children: [
          for (final c in cartes) ...[
            c,
            const SizedBox(height: AgriSpacing.md),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cartes.length; i++) ...[
          if (i > 0) const SizedBox(width: AgriSpacing.md),
          Expanded(child: cartes[i]),
        ],
      ],
    );
  }

  /// Grille 65 % / 35 % du Blade : « GMQ par Bande — Résumé » et « Rappels VMS à venir ».
  Widget _resumeEtRappels(bool large) {
    final d = _donnees!;
    final avecGmq = d.lignesGmq.where((l) => l.gmq != null).toList();

    final resume = _bloc(
      titre: 'GMQ par Bande — Résumé',
      cle: 'bloc-resume-gmq',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Le graphique de croissance du prototype est remplacé par un '
            'tableau réel (aucune librairie de graphiques disponible côté vue à '
            "ce stade) — voir l'onglet « GMQ & Croissance » pour le détail "
            'complet.',
            style: TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
          const SizedBox(height: AgriSpacing.sm),
          if (avecGmq.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AgriSpacing.lg),
              child: Text(
                'Aucune donnée de croissance suffisante pour le moment (2 '
                'pesées minimum par bande).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            )
          else
            for (final (i, l) in avecGmq.indexed)
              Container(
                key: Key('resume-gmq-${l.code}${_suffixeDoublon(avecGmq.map((b) => b.code), i)}'),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AgriColors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l.code,
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        color: AgriColors.brandForest,
                      ),
                    ),
                    Text(
                      '${DashboardElevageRepository.nombrePhp(l.gmq!)} g/j',
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: l.gmq! < 0
                            ? AgriColors.errorDeep
                            : AgriColors.brandEmerald,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );

    final rappels = _bloc(
      titre: 'Rappels VMS à venir',
      cle: 'bloc-rappels-vms',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // AJOUT du poste conservé (décision client du 19/10/2026) : la liste calculée des
          // rappels des 7 prochains jours, au-dessus du texte et du lien du Blade.
          if (d.rappels.isEmpty)
            const Text(
              '— Aucun rappel dans les 7 prochains jours —',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontStyle: FontStyle.italic,
                color: AgriColors.outline,
              ),
            )
          else
            for (final r in d.rappels.take(6)) ...[
              Container(
                padding: const EdgeInsets.all(AgriSpacing.sm),
                decoration: BoxDecoration(
                  color: r.enRetard
                      ? AgriColors.errorBg
                      : AgriColors.accentYellow.withValues(alpha: 0.10),
                  border: Border.all(
                    color: r.enRetard
                        ? AgriColors.errorDeep.withValues(alpha: 0.20)
                        : AgriColors.accentYellow.withValues(alpha: 0.30),
                  ),
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      r.enRetard ? SymbolesAgri.warning : SymbolesAgri.event,
                      size: 18,
                      color: r.enRetard
                          ? AgriColors.errorDeep
                          : AgriColors.brandForest,
                    ),
                    const SizedBox(width: AgriSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.libelle,
                            style: const TextStyle(
                              fontSize: AgriTypography.xs,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            r.echeance,
                            style: const TextStyle(
                              fontSize: AgriTypography.xs,
                              color: AgriColors.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AgriSpacing.sm),
            ],
          // Texte et lien du Blade.
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AgriSpacing.md),
            child: Text(
              'Le calendrier complet (réel) est disponible dans Soins et '
              'Vaccins.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ),
          Center(
            child: InkWell(
              key: const Key('lien-calendrier-soins'),
              onTap: widget.onOuvrirSoins,
              child: const Text(
                'Voir le calendrier complet →',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandEmerald,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!large) {
      return Column(
        children: [
          resume,
          const SizedBox(height: AgriSpacing.md),
          rappels,
        ],
      );
    }

    // ⚠️ 65 % / 35 % — `lg:grid-cols-[65%_35%]` du Blade.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 65, child: resume),
        const SizedBox(width: AgriSpacing.md),
        Expanded(flex: 35, child: rappels),
      ],
    );
  }

  /// AJOUT du poste conservé (décision client du 19/10/2026) : courbe hebdomadaire du GMQ cumulé
  /// par espèce, absente du web (ticket H11).
  Widget _courbeEspeces() => _bloc(
    titre: 'Croissance (GMQ) par Espèce - 4 dernières semaines',
    enfant: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 192,
          child: CustomPaint(
            painter: _CourbesGmqPainter(_donnees!.gmqParEspeceParSemaine),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: AgriSpacing.sm),
        Row(
          children: [
            _legende(AgriColors.brandEmerald, 'Cuniculture'),
            const SizedBox(width: AgriSpacing.lg),
            _legende(AgriColors.infoBlue, 'Aviculture'),
            const SizedBox(width: AgriSpacing.lg),
            _legende(AgriColors.accentYellow, 'Porciculture'),
          ],
        ),
      ],
    ),
  );

  /// Titre `<h2>` d'un panneau du Blade : icône émeraude et texte `text-lg font-bold`.
  Widget _titrePanneau(String titre, IconData icone) => Row(
    key: const Key('titre-panneau'),
    children: [
      Icon(icone, size: 22, color: AgriColors.brandEmerald),
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
  );

  // ── Onglet 2 : GMQ & Croissance ───────────────────────────────────────────

  Widget _ongletGmq(bool large) {
    final d = _donnees!;
    final lignes = _espece == 'all'
        ? d.lignesGmq
        : d.lignesGmq.where((l) => l.codeEspece == _espece).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Titre et aide du Blade ; le filtre d'espèce est un AJOUT du poste conservé.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _titrePanneau('GMQ & Croissance', SymbolesAgri.ssid_chart),
                  const SizedBox(height: AgriSpacing.xs),
                  const Text(
                    'GMQ (g/j) = (Poids Final − Poids Initial) ÷ Nombre de '
                    'Jours entre les deux pesées, calculé par bande à partir '
                    'des pesées déjà saisies dans les fiches journalières.',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AgriSpacing.sm),
            _filtreEspece(),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        // AJOUTS du poste conservés (décision client du 19/10/2026) : cartes par espèce et courbe
        // de la bande suivie, sur le MÊME GMQ cumulé que le tableau du Blade.
        GrilleKpi(colonnes: large ? 4 : 2, children: [
            _carteGmq(
              'GMQ Moyen Lapins',
              d.gmqParEspece['cuniculture'],
              'cuniculture',
              AgriColors.brandEmerald,
            ),
            _carteGmq(
              'GMQ Moyen Volailles Chair',
              d.gmqParEspece['aviculture'],
              'aviculture',
              AgriColors.accentYellow,
            ),
            _carteGmq(
              'GMQ Moyen Porcs',
              d.gmqParEspece['porciculture'],
              'porciculture',
              AgriColors.errorRed,
            ),
            _carteKpi(
              libelle: 'Lots Suivis (Pesées ≥ 2)',
              valeur: '${d.lotsSuivis}',
              legende: '',
              icone: SymbolesAgri.checklist,
              barre: AgriColors.infoBlue,
              couleurIcone: AgriColors.infoBlue,
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.lg),
        _bloc(
          titre: d.bandeSuivie == null
              ? 'Évolution du GMQ — 8 dernières semaines'
              : 'Évolution du GMQ — ${d.bandeSuivie} (8 dernières semaines)',
          enfant: SizedBox(
            height: 192,
            child: CustomPaint(
              painter: _CourbesGmqPainter({'suivie': d.evolutionGmq}),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.lg),
        _tableauGmq(lignes),
      ],
    );
  }

  Widget _filtreEspece() => Container(
    key: const Key('filtre-espece'),
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _espece,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          fontWeight: FontWeight.bold,
          color: AgriColors.onSurface,
        ),
        items: const [
          DropdownMenuItem(value: 'all', child: Text('Toutes les Espèces')),
          DropdownMenuItem(
            value: 'cuniculture',
            child: Text('Cuniculture (Lapins)'),
          ),
          DropdownMenuItem(
            value: 'aviculture',
            child: Text('Aviculture (Volailles)'),
          ),
          DropdownMenuItem(
            value: 'porciculture',
            child: Text('Porciculture (Porcs)'),
          ),
        ],
        onChanged: (v) => setState(() => _espece = v ?? 'all'),
      ),
    ),
  );

  Widget _carteGmq(String libelle, double? valeur, String code, Color barre) {
    // Ticket U2 (D-U2) — objectif lu dans `growth_standards` (même règle que le web) ; sans barème : « — ».
    final objectif = _donnees!.objectifsGmq[code];
    final legende = objectif == null
        ? 'Objectif : —'
        : 'Objectif : ${objectif.$1}-${objectif.$2} g/j';

    return _carteKpi(
      libelle: libelle,
      valeur: valeur == null ? '—' : '${valeur.toStringAsFixed(0)} g/j',
      legende: valeur == null ? 'Moins de 2 pesées enregistrées' : legende,
      icone: SymbolesAgri.trending_up,
      barre: barre,
    );
  }

  static const _enteteGmq = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  /// En-tête d'un tableau du Blade (`bg-surface-zebra`, `text-[10px] uppercase`) : colonne 1 à
  /// gauche, les suivantes à droite (`text-right`).
  Widget _enteteTableau(List<(String, int)> colonnes, {int aGauche = 1}) =>
      Container(
    color: AgriColors.surfaceZebra,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        for (final (i, (libelle, flex)) in colonnes.indexed)
          Expanded(
            flex: flex,
            child: Text(
              libelle.toUpperCase(),
              textAlign: i < aGauche ? TextAlign.left : TextAlign.right,
              style: _enteteGmq,
            ),
          ),
      ],
    ),
  );

  /// Ligne d'un tableau du Blade : zébrée une ligne sur deux.
  Widget _ligneTableau(Key cle, int i, List<Widget> cellules) => Container(
    key: cle,
    decoration: BoxDecoration(
      color: i.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
      border: const Border(
        bottom: BorderSide(color: AgriColors.outlineVariant),
      ),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(children: cellules),
  );

  Widget _cellule(
    String texte,
    int flex, {
    TextAlign alignement = TextAlign.right,
    FontWeight? graisse,
    Color? couleur,
  }) => Expanded(
    flex: flex,
    child: Text(
      texte,
      textAlign: alignement,
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: graisse,
        color: couleur,
      ),
    ),
  );

  Widget _videTableau(String texte) => Padding(
    padding: const EdgeInsets.all(AgriSpacing.lg),
    child: Text(
      texte,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        color: AgriColors.outline,
      ),
    ),
  );

  BoxDecoration _cadreTableau() => BoxDecoration(
    color: AgriColors.surfaceCard,
    border: Border.all(color: AgriColors.outlineVariant),
    borderRadius: BorderRadius.circular(AgriRadius.lg),
    boxShadow: AgriShadows.sm,
  );

  /// Tableau « GMQ & Croissance » du Blade : six colonnes, une ligne par bande active.
  Widget _tableauGmq(List<LigneGmq> lignes) {
    const c = DashboardElevageScreen.colonnesGmq;
    String nombre(double? v) =>
        v == null ? '—' : DashboardElevageRepository.nombrePhp(v);

    return Container(
      decoration: _cadreTableau(),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 980,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _enteteTableau(c, aGauche: 2),
              if (lignes.isEmpty) _videTableau('Aucune bande active pour le moment.'),
              for (final (i, l) in lignes.indexed)
                _ligneTableau(Key('ligne-gmq-${l.code}${_suffixeDoublon(lignes.map((b) => b.code), i)}'), i, [
                  _cellule(
                    l.code,
                    c[0].$2,
                    alignement: TextAlign.left,
                    graisse: FontWeight.bold,
                    couleur: AgriColors.brandForest,
                  ),
                  _cellule(l.libelleEspece, c[1].$2, alignement: TextAlign.left),
                  _cellule(nombre(l.poidsInitial), c[2].$2),
                  _cellule(nombre(l.poidsActuel), c[3].$2),
                  _cellule(l.jours == null ? '—' : '${l.jours}', c[4].$2),
                  _cellule(
                    l.gmq == null
                        ? 'Pesées insuffisantes'
                        : '${DashboardElevageRepository.nombrePhp(l.gmq!)} g/j',
                    c[5].$2,
                    graisse: FontWeight.bold,
                    couleur: l.gmq != null && l.gmq! < 0
                        ? AgriColors.errorDeep
                        : AgriColors.brandEmerald,
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── Onglet 3 : Bilan Technico-Économique ──────────────────────────────────

  /// ⚠️ MÊME BASE LOCALE que le tableau de bord : le bilan se lit sur les mêmes
  /// tables, et un second dépôt parallèle finirait par diverger.
  Widget _ongletBilan() => BilanTechnicoEconomiqueVue(
    depot: BilanTechnicoEconomiqueRepository(database: widget.depot.database),
  );

  // ── Onglet 4 : Analyse Sanitaire ──────────────────────────────────────────

  Widget _ongletSanitaire(bool large) {
    final d = _donnees!;
    const c = DashboardElevageScreen.colonnesSanitaire;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titrePanneau(
          'Analyse Sanitaire — Fréquence des Maladies',
          SymbolesAgri.coronavirus,
        ),
        const SizedBox(height: AgriSpacing.md),
        // Les trois cartes du Blade : soins du mois des bandes actives.
        GrilleKpi(colonnes: large ? 3 : 2, children: [
            _carteKpi(
              libelle: 'Traitements Administrés (mois)',
              valeur: '${d.traitementsDuMois}',
              legende: '',
              icone: SymbolesAgri.vaccines,
              barre: AgriColors.brandEmerald,
            ),
            _carteKpi(
              libelle: 'Coût Sanitaire Total (mois)',
              valeur:
                  '${DashboardElevageRepository.milliers(d.coutSanitaireDuMois)} FCFA',
              legende: '',
              icone: SymbolesAgri.payments,
              barre: AgriColors.errorRed,
              couleurIcone: AgriColors.errorRed,
            ),
            _carteKpi(
              libelle: 'Traitement le Plus Fréquent',
              valeur: d.traitementLePlusFrequent ?? '—',
              legende: '',
              icone: SymbolesAgri.star,
              barre: AgriColors.infoBlue,
              couleurIcone: AgriColors.infoBlue,
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        Container(
          decoration: _cadreTableau(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _enteteTableau(c),
              for (final (i, l) in d.sanitaire.indexed)
                _ligneTableau(Key('ligne-sanitaire-${l.code}${_suffixeDoublon(d.sanitaire.map((b) => b.code), i)}'), i, [
                  _cellule(
                    l.libelleEspece,
                    c[0].$2,
                    alignement: TextAlign.left,
                    graisse: FontWeight.bold,
                    couleur: AgriColors.brandForest,
                  ),
                  _cellule('${l.nombreDeTraitements}', c[1].$2),
                  _cellule(
                    '${DashboardElevageRepository.milliers(l.coutTotal)} FCFA',
                    c[2].$2,
                  ),
                  // ⚠️ TOUJOURS UN TIRET, JAMAIS « 0,0 % » : le taux de morbidité se lit sur
                  // `infirmary_records`, table absente de la base du poste (D-H8, ticket H8b).
                  _cellule('—', c[3].$2),
                ]),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        // AJOUT du poste conservé (décision client du 19/10/2026).
        const Text(
          '⚠️ La comparaison « 2026 vs 2025 » de la maquette demande '
          'l\'historique de l\'an dernier, que le tirage ne descend pas.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontStyle: FontStyle.italic,
            color: AgriColors.outline,
          ),
        ),
      ],
    );
  }

  // ── Onglet 5 : Prévision de Croissance ────────────────────────────────────

  /// Horizons proposés par la maquette (`prev-horizon`), en jours.
  static const horizons = <int>[7, 14, 30, 60];

  String? _bandePrevision;
  int _horizon = 14;

  static String _milliers(double v) {
    final entier = v.round().abs().toString();
    final groupes = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      groupes.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${v.round() < 0 ? '-' : ''}${groupes.join(' ')}';
  }

  Widget _ongletPrevision() {
    final d = _donnees!;
    final large = AgriBreakpoints.large(context);

    // ⚠️ La bande retenue peut avoir disparu après une actualisation : retomber
    // sur la première plutôt que de laisser une sélection orpheline.
    final selection = d.previsions.isEmpty
        ? null
        : d.previsions.firstWhere(
            (p) => p.bandeId == _bandePrevision,
            orElse: () => d.previsions.first,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Titre, méthode et tableau du Blade.
        _titrePanneau('Prévision de Croissance', SymbolesAgri.query_stats),
        const SizedBox(height: AgriSpacing.xs),
        const Text(
          "Régression linéaire simple sur l'historique des pesées (minimum 3 "
          'points requis).',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _tableauPrevision(d.lignesPrevision),
        const SizedBox(height: AgriSpacing.lg),
        // AJOUTS du poste conservés (décision client du 19/10/2026) : sélecteur de bande,
        // horizons, trois cartes et projection par horizon — même régression que le tableau.
        const Text(
          'Calcul du poste : droite de régression sur toutes les pesées de la '
          'bande (trois au minimum), comme le serveur.',
          key: Key('prevision-regle'),
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        if (selection == null) ...[
          _bloc(
            titre: 'Paramètres de la projection',
            icone: SymbolesAgri.tune,
            enfant: const Padding(
              padding: EdgeInsets.all(AgriSpacing.lg),
              child: Text(
                '— Trois pesées au minimum sont nécessaires pour projeter —',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          _cartesPrevision(null, large),
        ] else ...[
          _bloc(
            titre: 'Paramètres de la projection',
            icone: SymbolesAgri.tune,
            enfant: Wrap(
              spacing: AgriSpacing.md,
              runSpacing: AgriSpacing.md,
              children: [
                _champPrevision(
                  'Bande',
                  largeur: 340,
                  DropdownButtonFormField<String>(
                    key: const Key('prevision-bande'),
                    initialValue: selection.bandeId,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final p in d.previsions)
                        DropdownMenuItem(
                          value: p.bandeId,
                          child: Text('${p.code} (${p.libelleEspece})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _bandePrevision = v),
                  ),
                ),
                _champPrevision(
                  'Poids Actuel Constaté (g)',
                  _lectureSeule(
                    'prevision-poids-actuel',
                    selection.poidsActuel.toStringAsFixed(0),
                  ),
                ),
                _champPrevision(
                  'GMQ Observé (g/jour)',
                  _lectureSeule(
                    'prevision-gmq',
                    selection.gmqObserve.toStringAsFixed(1),
                  ),
                ),
                _champPrevision(
                  'Horizon de Projection',
                  DropdownButtonFormField<int>(
                    key: const Key('prevision-horizon'),
                    initialValue: _horizon,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final h in horizons)
                        DropdownMenuItem(value: h, child: Text('$h jours')),
                    ],
                    onChanged: (v) => setState(() => _horizon = v ?? _horizon),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          _cartesPrevision(selection, large),
          const SizedBox(height: AgriSpacing.md),
          _bloc(
            titre: 'Courbe de Croissance — Historique et Projection',
            icone: SymbolesAgri.show_chart,
            enfant: _tableauProjection(selection),
          ),
        ],
      ],
    );
  }

  /// Tableau « Prévision de Croissance » du Blade : une ligne par bande active ; sous trois
  /// pesées, une seule cellule « Historique insuffisant… » sur les trois colonnes de valeurs.
  Widget _tableauPrevision(List<LignePrevision> lignes) {
    const c = DashboardElevageScreen.colonnesPrevision;
    final valeurs = c[1].$2 + c[2].$2 + c[3].$2;

    return Container(
      decoration: _cadreTableau(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _enteteTableau(c),
          if (lignes.isEmpty) _videTableau('Aucune bande active pour le moment.'),
          for (final (i, l) in lignes.indexed)
            _ligneTableau(Key('ligne-prevision-${l.code}${_suffixeDoublon(lignes.map((b) => b.code), i)}'), i, [
              _cellule(
                l.code,
                c[0].$2,
                alignement: TextAlign.left,
                graisse: FontWeight.bold,
                couleur: AgriColors.brandForest,
              ),
              if (l.insuffisant)
                Expanded(
                  flex: valeurs,
                  child: const Text(
                    'Historique insuffisant (3 pesées minimum requises)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontStyle: FontStyle.italic,
                      color: AgriColors.outline,
                    ),
                  ),
                )
              else ...[
                _cellule('${l.poidsActuel}', c[1].$2),
                _cellule(
                  '${DashboardElevageRepository.nombrePhp(l.tendance!)} g/j',
                  c[2].$2,
                  graisse: FontWeight.bold,
                  couleur: l.tendance! < 0
                      ? AgriColors.errorDeep
                      : AgriColors.brandEmerald,
                ),
                _cellule(
                  DashboardElevageRepository.nombrePhp(l.projection30j!),
                  c[3].$2,
                  graisse: FontWeight.bold,
                ),
              ],
            ]),
        ],
      ),
    );
  }

  /// Les trois cartes de la maquette, TOUJOURS rendues.
  ///
  /// ⚠️ Sans bande projetable, la maquette les montre à « — » : une carte que le
  /// poste ne peut pas calculer est un tiret expliqué, jamais omise ni à zéro.
  Widget _cartesPrevision(Prevision? p, bool large) => GrilleKpi(colonnes: large ? 3 : 1, children: [
      _carteKpi(
        libelle: 'Poids Projeté',
        valeur: p == null ? '—' : '${_milliers(p.projeter(_horizon))} g',
        legende: p == null
            ? 'Trois pesées au minimum'
            : 'À $_horizon jours, ${p.nbPesees} pesées retenues',
        icone: SymbolesAgri.trending_up,
        barre: AgriColors.brandEmerald,
      ),
      // ⚠️⚠️ AUCUN POIDS CIBLE N'EXISTE hors de la maquette : ses 2 200 g,
      // 2 500 g et 60 000 g sont des valeurs de démonstration codées dans le
      // JavaScript, ni Laravel ni le poste n'en paramètrent. Un tiret expliqué,
      // jamais un chiffre inventé (ARBITRAGE CLIENT).
      _carteKpi(
        libelle: 'Poids Cible de Commercialisation',
        valeur: '—',
        legende: "Aucun poids cible n'est paramétré",
        icone: SymbolesAgri.flag,
        barre: AgriColors.accentYellow,
        couleurIcone: AgriColors.outline,
      ),
      _carteKpi(
        libelle: "Date Estimée d'Atteinte de la Cible",
        valeur: '—',
        legende: 'Dépend du poids cible',
        icone: SymbolesAgri.event,
        barre: AgriColors.accentYellow,
        couleurIcone: AgriColors.outline,
      ),
    ],
  );

  Widget _champPrevision(
    String libelle,
    Widget champ, {
    double largeur = 220,
  }) => SizedBox(
    width: largeur,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        champ,
      ],
    ),
  );

  Widget _lectureSeule(String cle, String valeur) => InputDecorator(
    key: Key(cle),
    decoration: const InputDecoration(
      border: OutlineInputBorder(),
      isDense: true,
      filled: true,
      fillColor: AgriColors.surfaceZebra,
    ),
    child: Text(valeur, style: const TextStyle(fontSize: AgriTypography.xs)),
  );

  /// ⚠️ LA COURBE EST RENDUE EN TABLEAU, faute de librairie de graphiques : une
  /// ligne par horizon de la maquette, de l'actuel à +60 jours.
  Widget _tableauProjection(Prevision p) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        color: AgriColors.surfaceZebra,
        padding: const EdgeInsets.all(AgriSpacing.sm),
        child: const Row(
          children: [
            Expanded(child: Text('ÉCHÉANCE', style: _enteteGmq)),
            Expanded(
              child: Text(
                'POIDS (G)',
                textAlign: TextAlign.right,
                style: _enteteGmq,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(AgriSpacing.sm),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                "Aujourd'hui",
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Text(
                _milliers(p.poidsActuel),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: AgriTypography.xs),
              ),
            ),
          ],
        ),
      ),
      for (final h in horizons)
        Padding(
          key: Key('prevision-ligne-$h'),
          padding: const EdgeInsets.all(AgriSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '+ $h jours',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: h == _horizon
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _milliers(p.projeter(h)),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: h == _horizon
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  // ── Briques communes ──────────────────────────────────────────────────────

  Widget _carteKpi({
    required String libelle,
    required String valeur,
    required String legende,
    required IconData icone,
    required Color barre,
    Color couleurIcone = AgriColors.brandEmerald,
  }) => CarteKpi(
    libelle: libelle,
    valeur: valeur,
    legende: legende,
    icone: icone,
    couleurLisere: barre,
    couleurIcone: couleurIcone,
  );

  Widget _bloc({
    required String titre,
    required Widget enfant,
    IconData? icone,
    String? cle,
  }) => Container(
    key: cle == null ? null : Key(cle),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icone != null) ...[
              Icon(icone, size: 18, color: AgriColors.brandEmerald),
              const SizedBox(width: AgriSpacing.xs),
            ],
            Expanded(
              child: Text(
                titre,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandForest,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        enfant,
      ],
    ),
  );

  Widget _legende(Color couleur, String libelle) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
      ),
      const SizedBox(width: AgriSpacing.xs),
      Text(
        libelle,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.outline,
        ),
      ),
    ],
  );
}

/// Courbes de GMQ hebdomadaire — une par espèce, aux couleurs de la maquette.
///
/// ⚠️ **UNE SEMAINE SANS DEUX PESÉES NE TRACE RIEN.** La valeur est `null` et
/// le segment est simplement absent : relier deux points de part et d'autre
/// d'un trou dessinerait une croissance qui n'a pas été mesurée.
class _CourbesGmqPainter extends CustomPainter {
  _CourbesGmqPainter(this.series);

  final Map<String, List<double?>> series;

  static const _couleurs = {
    'cuniculture': AgriColors.brandEmerald,
    'aviculture': AgriColors.infoBlue,
    'porciculture': AgriColors.accentYellow,
    'suivie': AgriColors.brandEmerald,
  };

  @override
  void paint(Canvas canvas, Size size) {
    const margeBas = 24.0;
    final base = size.height - margeBas;

    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = AgriColors.outlineVariant
        ..strokeWidth = 1,
    );

    final toutes = series.values.expand((s) => s).whereType<double>().toList();
    if (toutes.isEmpty) {
      final texte = TextPainter(
        text: const TextSpan(
          text: '— Pas encore assez de pesées pour tracer une courbe —',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontStyle: FontStyle.italic,
            color: AgriColors.outline,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      texte.paint(
        canvas,
        Offset((size.width - texte.width) / 2, base / 2 - texte.height / 2),
      );
      return;
    }

    final maximum = toutes.reduce((a, b) => a > b ? a : b);
    final longueur = series.values
        .map((s) => s.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (longueur < 1) return;

    final pas = longueur == 1 ? 0.0 : (size.width - 30) / (longueur - 1);

    Offset position(int i, double valeur) => Offset(
      15 + pas * i,
      maximum <= 0 ? base - 10 : base - (valeur / maximum) * (base - 15),
    );

    for (final entree in series.entries) {
      final trait = Paint()
        ..color = _couleurs[entree.key] ?? AgriColors.outline
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;

      for (var i = 0; i < entree.value.length - 1; i++) {
        final a = entree.value[i];
        final b = entree.value[i + 1];
        if (a == null || b == null) continue;
        canvas.drawLine(position(i, a), position(i + 1, b), trait);
      }

      for (var i = 0; i < entree.value.length; i++) {
        final v = entree.value[i];
        if (v == null) continue;
        canvas.drawCircle(position(i, v), 3.5, Paint()..color = trait.color);
      }
    }

    for (var i = 0; i < longueur; i++) {
      final texte = TextPainter(
        text: TextSpan(
          text: 'S${i + 1}',
          style: const TextStyle(fontSize: 9, color: AgriColors.outline),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      texte.paint(canvas, Offset(15 + pas * i - texte.width / 2, base + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _CourbesGmqPainter ancien) =>
      ancien.series != series;
}

/// Suffixe d'une clé de ligne quand deux bandes portent le même code (`-2`, `-3`…) ; vide pour la première.
///
/// 🔴→✅ « Duplicate keys found » : deux bandes de même code (ex. `AVI-2026-01`) donnaient deux lignes de clé
/// identique, ce qui arrête le dessin de l'écran entier sans aucune erreur de compilation. La première garde sa clé
/// d'origine (les tests la retrouvent), les suivantes reçoivent un rang.
String _suffixeDoublon(Iterable<String> codes, int index) {
  final liste = codes.toList();
  final rang = liste.sublist(0, index + 1).where((c) => c == liste[index]).length;
  return rang <= 1 ? '' : '-$rang';
}
