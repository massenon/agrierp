import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'bilan_technico_economique_repository.dart';
import 'bilan_technico_economique_vue.dart';
import 'dashboard_elevage_repository.dart';

/// `prototype_html/elevage-dashboard.html` → Dashboard Élevage.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** En-tête, puis les
/// **cinq onglets** dans SON ordre : Synthèse Globale · GMQ & Croissance ·
/// Bilan Technico-Économique · Analyse Sanitaire · Prévision de Croissance.
///
/// ⚠️ **L'ONGLET « BILAN TECHNICO-ÉCONOMIQUE » EST PORTÉ (ticket F0.63).** Il
/// disait « module non embarqué » en invoquant les achats et les centres de coût
/// — mais le bilan de Laravel n'utilise NI l'un NI l'autre : acquisition,
/// provende au prix indicatif, soins et ventes de la bande. Le motif était faux
/// depuis le départ. Voir [BilanTechnicoEconomiqueVue].
class DashboardElevageScreen extends StatefulWidget {
  const DashboardElevageScreen({super.key, required this.depot});

  final DashboardElevageRepository depot;

  @override
  State<DashboardElevageScreen> createState() => _DashboardElevageScreenState();
}

class _DashboardElevageScreenState extends State<DashboardElevageScreen> {
  /// Les cinq onglets de la maquette, dans son ordre, avec leurs icônes.
  static const onglets = <(String, IconData)>[
    ('Synthèse Globale', Icons.dashboard),
    ('GMQ & Croissance', Icons.show_chart),
    ('Bilan Technico-Économique', Icons.account_balance_wallet),
    ('Analyse Sanitaire', Icons.coronavirus),
    ('Prévision de Croissance', Icons.query_stats),
  ];

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
    final donnees = await widget.depot.charger();
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
                        'Bilan Technico-Économique' => _ongletBilan(),
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
              Icons.dashboard,
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
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AgriSpacing.md,
          crossAxisSpacing: AgriSpacing.md,
          childAspectRatio: large ? 2.0 : 1.5,
          children: [
            _carteKpi(
              libelle: 'Effectif Total Vivant',
              valeur: '${d.effectifTotal}',
              legende: 'Toutes espèces actives',
              icone: Icons.pets,
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
              icone: Icons.inventory_2,
              barre: AgriColors.accentYellow,
              couleurIcone: AgriColors.brandForest,
            ),
            _carteKpi(
              libelle: 'GMQ Moyen',
              valeur: d.gmqMoyen == null
                  ? '—'
                  : '${d.gmqMoyen!.toStringAsFixed(0)} g/j',
              legende: d.gmqMoyen == null
                  ? 'Moins de 2 pesées enregistrées'
                  : 'Consolidé, toutes bandes',
              icone: Icons.trending_up,
              barre: AgriColors.infoBlue,
              couleurIcone: AgriColors.infoBlue,
            ),
            // ⚠️ LIBELLÉ ET PÉRIODE DE LA MAQUETTE : « (mois) ». Le composant
            // Livewire a renommé la carte en « (7j) » et calcule sur sept
            // jours : même écran, deux périodes. Signalé, non tranché.
            _carteKpi(
              libelle: 'Mortalité Cumulée (mois)',
              valeur: d.mortaliteMois == null
                  ? '—'
                  : '${d.mortaliteMois!.toStringAsFixed(1)}%',
              legende: 'Alerte si > 10%/semaine',
              icone: Icons.health_and_safety,
              barre: AgriColors.errorRed,
              couleurIcone: AgriColors.errorRed,
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.lg),
        _cartesEspeces(large),
        const SizedBox(height: AgriSpacing.lg),
        _croissanceEtRappels(large),
      ],
    );
  }

  static const _iconesEspeces = {
    'Cuniculture': Icons.cruelty_free,
    'Aviculture': Icons.egg,
    'Porciculture': Icons.pets,
    'Héliciculture': Icons.bug_report,
  };

  Widget _cartesEspeces(bool large) {
    final cartes = _donnees!.especes.map((carte) {
      return Container(
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
                  _iconesEspeces[carte.titre] ?? Icons.pets,
                  size: 20,
                  color: AgriColors.brandEmerald,
                ),
                const SizedBox(width: AgriSpacing.xs),
                Text(
                  carte.titre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
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
                    Text(
                      libelle,
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        color: AgriColors.outline,
                      ),
                    ),
                    Text(
                      valeur,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        color: critique
                            ? AgriColors.errorDeep
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

  /// Grille 65 % / 35 % de la maquette.
  Widget _croissanceEtRappels(bool large) {
    final d = _donnees!;

    final courbe = _bloc(
      titre: 'Croissance (GMQ) par Espèce - 4 dernières semaines',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 192,
            child: CustomPaint(
              painter: _CourbesGmqPainter(d.gmqParEspeceParSemaine),
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

    final rappels = _bloc(
      titre: 'Rappels VMS à venir',
      enfant: d.rappels.isEmpty
          ? const Text(
              '— Aucun rappel dans les 7 prochains jours —',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontStyle: FontStyle.italic,
                color: AgriColors.outline,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                          r.enRetard ? Icons.warning : Icons.event,
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
              ],
            ),
    );

    if (!large) {
      return Column(
        children: [
          courbe,
          const SizedBox(height: AgriSpacing.md),
          rappels,
        ],
      );
    }

    // ⚠️ 65 % / 35 % — le rapport exact de la maquette, pas une moitié chacun.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 65, child: courbe),
        const SizedBox(width: AgriSpacing.md),
        Expanded(flex: 35, child: rappels),
      ],
    );
  }

  // ── Onglet 2 : GMQ & Croissance ───────────────────────────────────────────

  Widget _ongletGmq(bool large) {
    final d = _donnees!;
    final lignes = _espece == 'all'
        ? d.lignesGmq
        : d.lignesGmq.where((l) => l.codeEspece == _espece).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Titre de `analyse-croissance.html`, dont cet onglet est le contenu.
        const Padding(
          padding: EdgeInsets.only(bottom: AgriSpacing.xs),
          child: Row(
            children: [
              Icon(Icons.show_chart, size: 20, color: AgriColors.brandEmerald),
              SizedBox(width: AgriSpacing.xs),
              Text(
                'Analyse des Croissances — GMQ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.onSurface,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Gain Moyen Quotidien = (Poids actuel − Poids précédent) ÷ '
                'Jours écoulés. Calculé automatiquement à partir des pesées '
                'enregistrées.',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ),
            const SizedBox(width: AgriSpacing.sm),
            _filtreEspece(),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AgriSpacing.md,
          crossAxisSpacing: AgriSpacing.md,
          childAspectRatio: large ? 2.0 : 1.5,
          children: [
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
              icone: Icons.checklist,
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
    final objectif = DashboardElevageRepository.objectifs[code];
    final legende = objectif == null
        ? ''
        : 'Objectif : ${objectif.$1.toStringAsFixed(0)}-'
              '${objectif.$2.toStringAsFixed(0)} g/j';

    return _carteKpi(
      libelle: libelle,
      valeur: valeur == null ? '—' : '${valeur.toStringAsFixed(0)} g/j',
      legende: valeur == null ? 'Moins de 2 pesées enregistrées' : legende,
      icone: Icons.trending_up,
      barre: barre,
    );
  }

  static const _enteteGmq = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  Widget _tableauGmq(List<LigneGmq> lignes) {
    return Container(
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 980,
          child: Column(
            children: [
              Container(
                color: AgriColors.surfaceZebra,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.sm,
                  vertical: AgriSpacing.sm,
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text('BANDE', style: _enteteGmq)),
                    Expanded(flex: 2, child: Text('ESPÈCE', style: _enteteGmq)),
                    Expanded(
                      flex: 2,
                      child: Text('DERNIÈRE PESÉE', style: _enteteGmq),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'POIDS PRÉCÉDENT (G)',
                        textAlign: TextAlign.right,
                        style: _enteteGmq,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'POIDS ACTUEL (G)',
                        textAlign: TextAlign.right,
                        style: _enteteGmq,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'JOURS ÉCOULÉS',
                        textAlign: TextAlign.right,
                        style: _enteteGmq,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'GMQ (G/JOUR)',
                        textAlign: TextAlign.right,
                        style: _enteteGmq,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('STATUT VS OBJECTIF', style: _enteteGmq),
                    ),
                  ],
                ),
              ),
              if (lignes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AgriSpacing.lg),
                  child: Text(
                    '— Aucune bande ne compte deux pesées : le GMQ n\'est pas '
                    'calculable —',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontStyle: FontStyle.italic,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
              for (var i = 0; i < lignes.length; i++)
                Container(
                  key: Key('ligne-gmq-$i'),
                  color: i.isOdd
                      ? AgriColors.surfaceZebra
                      : AgriColors.surfaceCard,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.sm,
                    vertical: AgriSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          lignes[i].code,
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          lignes[i].libelleEspece,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _date(lignes[i].datePesee),
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          lignes[i].poidsPrecedent.toStringAsFixed(0),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          lignes[i].poidsActuel.toStringAsFixed(0),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${lignes[i].jours}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          lignes[i].gmq.toStringAsFixed(1),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(flex: 2, child: _pastille(lignes[i].statut)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// ⚠️ Trois statuts dans la maquette, et un quatrième nécessaire : une
  /// espèce sans barème (héliciculture) n'est ni dans la cible ni hors cible.
  /// Le JS du prototype retombe sur `{min:0, max:9999}` et affiche « Dans la
  /// cible » — un satisfecit délivré sans objectif.
  Widget _pastille(StatutGmq statut) {
    final (libelle, couleur) = switch (statut) {
      StatutGmq.sousObjectif => ('Sous objectif', AgriColors.errorDeep),
      StatutGmq.auDessusObjectif => ('Au-dessus objectif', AgriColors.infoBlue),
      StatutGmq.dansLaCible => ('Dans la cible', AgriColors.brandEmerald),
      StatutGmq.sansObjectif => ('Sans objectif défini', AgriColors.outline),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.10),
          border: Border.all(color: couleur.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Text(
          libelle,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: couleur,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: large ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AgriSpacing.md,
          crossAxisSpacing: AgriSpacing.md,
          childAspectRatio: large ? 2.6 : 1.5,
          children: [
            _carteKpi(
              libelle: 'Traitements du Mois',
              valeur: '${d.traitementsDuMois}',
              legende: '',
              icone: Icons.vaccines,
              barre: AgriColors.infoBlue,
              couleurIcone: AgriColors.infoBlue,
            ),
            _carteKpi(
              libelle: 'Coût Sanitaire du Mois',
              valeur: '${d.coutSanitaireDuMois.round()} F',
              legende: '',
              icone: Icons.payments,
              barre: AgriColors.accentYellow,
              couleurIcone: AgriColors.brandForest,
            ),
            _carteKpi(
              libelle: 'Traitement le Plus Fréquent',
              valeur: d.traitementLePlusFrequent ?? '—',
              legende: d.traitementLePlusFrequent == null
                  ? 'Aucun soin enregistré ce mois-ci'
                  : '',
              icone: Icons.coronavirus,
              barre: AgriColors.errorRed,
              couleurIcone: AgriColors.errorRed,
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.lg),
        _bloc(
          titre: 'Analyse Sanitaire — Fréquence des Maladies',
          icone: Icons.coronavirus,
          enfant: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AgriColors.surfaceZebra,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.sm,
                  vertical: AgriSpacing.sm,
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text('FILIÈRE', style: _enteteGmq),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'NB TRAITEMENTS (MOIS)',
                        textAlign: TextAlign.right,
                        style: _enteteGmq,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'COÛT TOTAL',
                        textAlign: TextAlign.right,
                        style: _enteteGmq,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'TAUX DE MORBIDITÉ %',
                        textAlign: TextAlign.right,
                        style: _enteteGmq,
                      ),
                    ),
                  ],
                ),
              ),
              for (final l in d.sanitaire)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.sm,
                    vertical: AgriSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          l.libelleEspece,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${l.nombreDeTraitements}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${l.coutTotal.round()} F',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      // ⚠️ TOUJOURS UN TIRET : le taux de morbidité se lit sur
                      // `infirmary_records`, table absente de la base du poste.
                      const Expanded(
                        flex: 2,
                        child: Text(
                          '—',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
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
        const Text(
          "Projection basée sur le GMQ moyen observé (7 derniers jours) "
          "appliqué de manière linéaire jusqu'à la date cible. Anticipez les "
          "besoins en alimentation et la date de commercialisation.",
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
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
            titre: 'Prévision de Croissance',
            icone: Icons.query_stats,
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
            icone: Icons.tune,
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
            icone: Icons.show_chart,
            enfant: _tableauProjection(selection),
          ),
        ],
      ],
    );
  }

  /// Les trois cartes de la maquette, TOUJOURS rendues.
  ///
  /// ⚠️ Sans bande projetable, la maquette les montre à « — » : une carte que le
  /// poste ne peut pas calculer est un tiret expliqué, jamais omise ni à zéro.
  Widget _cartesPrevision(Prevision? p, bool large) => GridView.count(
    crossAxisCount: large ? 3 : 1,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 2.4 : 3.2,
    children: [
      _carteKpi(
        libelle: 'Poids Projeté',
        valeur: p == null ? '—' : '${_milliers(p.projeter(_horizon))} g',
        legende: p == null
            ? 'Trois pesées au minimum'
            : 'À $_horizon jours, ${p.nbPesees} pesées retenues',
        icone: Icons.trending_up,
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
        icone: Icons.flag,
        barre: AgriColors.accentYellow,
        couleurIcone: AgriColors.outline,
      ),
      _carteKpi(
        libelle: "Date Estimée d'Atteinte de la Cible",
        valeur: '—',
        legende: 'Dépend du poids cible',
        icone: Icons.event,
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
  }) => Container(
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

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
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
