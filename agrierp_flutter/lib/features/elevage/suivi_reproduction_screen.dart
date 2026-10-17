import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import 'sujets_repository.dart';
import 'suivi_reproduction_repository.dart';

/// `prototype_html/suivi-reproduction.html` → Suivi Reproduction.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** Quatre cartes KPI,
/// puis les **quatre onglets** dans SON ordre : Lapins · Volailles · Porcs ·
/// Escargots. Chaque onglet porte son titre, son sous-titre, son bandeau
/// « Rappel du cycle » et son tableau.
///
/// ⚠️⚠️ **LA SAILLIE SE DÉCLARE AU POSTE** (ticket F0.35) : c'est l'acte qui
/// se fait au clapier, hors ligne. Palpation, mise bas et sevrage restent web
/// — ce sont des CORRECTIONS d'un cycle que le serveur a pu faire évoluer
/// entre-temps, et « dernier écrivain gagne » ne convient pas à une gestation
/// de trois mois. L'écran le dit plutôt que de laisser deviner.
class SuiviReproductionScreen extends StatefulWidget {
  const SuiviReproductionScreen({
    super.key,
    required this.depot,
    this.onOuvrirSujet,
  });

  final SuiviReproductionRepository depot;

  /// Ouvre la fiche d'un sujet. `null` : les références restent du texte.
  ///
  /// ⚠️ Une référence n'est cliquable QUE si un sujet porte ce nom : « R1 » peut
  /// être une cage, une lapine jamais enregistrée comme sujet, ou un reproducteur.
  /// Un lien vers une fiche inexistante serait pire que du texte.
  final void Function(String sujetId)? onOuvrirSujet;

  @override
  State<SuiviReproductionScreen> createState() =>
      _SuiviReproductionScreenState();
}

class _SuiviReproductionScreenState extends State<SuiviReproductionScreen> {
  /// Les quatre onglets de la maquette, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Lapins', Icons.cruelty_free),
    ('Volailles', Icons.egg),
    ('Porcs', Icons.pets),
    ('Escargots', Icons.bug_report),
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

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _femelle.dispose();
    _male.dispose();
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
                final moyen = AgriBreakpoints.moyen(context);

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _kpis(moyen),
                      const SizedBox(height: AgriSpacing.md),
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.md),
                      switch (_onglet) {
                        'Volailles' => _ongletCouvoir(
                          titre:
                              'Suivi Reproduction Volailles — '
                              "Lancement d'Incubation & Couvoir",
                          sousTitre:
                              "Pilotage des lots d'incubation (Ratio 1M / "
                              "5-6F), date d'éclosion attendue (J+21) et "
                              "taux d'éclosion %.",
                          jalons: const [
                            'Mise en Incubation J0',
                            'Éclosion Attendue J+21',
                          ],
                          resume: _donnees!.volailles,
                          fiche: 'Fiches Reproducteurs',
                          libelleNes: 'Poussins Nés',
                        ),
                        'Porcs' => _ongletCycles(
                          titre: 'Suivi Reproduction — Porciculture (Porcs)',
                          sousTitre:
                              'Suivi par truie (T1..Tn) : saillie, retour '
                              'chaleur J+21, mise bas J+114 (3m3s3j) et '
                              'sevrage J+42.',
                          jalons: const [
                            'Saillie J0',
                            'Retour Chaleur J+21',
                            'Mise Bas J+114 (3m3s3j)',
                            'Sevrage J+42',
                          ],
                          // ⚠️ **DIX COLONNES, COMPTÉES SUR LA MAQUETTE**
                          // — `suivi-reproduction.html`, `#panel-porcs`.
                          // « Statut Physio » et « Action » manquaient.
                          //
                          // ⚠️⚠️ **ET « Sevrage (J+42) » FIGURAIT DEUX FOIS**,
                          // soit ONZE colonnes pour dix : la correction du
                          // ticket F0.42 avait ajouté la colonne manquante
                          // sans retirer sa jumelle. Ni le contrôle de
                          // vocabulaire — le mot existe — ni un test de rendu
                          // — le tableau s'affiche — ne pouvaient le voir. Il
                          // a fallu comparer la SUITE ORDONNÉE des colonnes à
                          // celle de la maquette (ticket F0.49).
                          colonnes: const [
                            'Bande',
                            'N° Truie',
                            'Date Saillie',
                            'Verrat N°',
                            'Retour Chaleur (J+21)',
                            'Mise Bas Attendue (J+114)',
                            'Porcelets Nés',
                            'Sevrage (J+42)',
                            'Statut Physio',
                            'Action',
                          ],
                          cycles: _donnees!.porcs,
                          porcs: true,
                        ),
                        'Escargots' => _ongletCouvoir(
                          titre:
                              'Suivi Reproduction — Héliciculture (Escargots)',
                          sousTitre:
                              'Suivi des Bacs de Ponte en terre, éclosion '
                              "des naissains et taux d'éclosion %.",
                          jalons: const [
                            'Placement Bac de Ponte J0',
                            'Éclosion Naissains Attendue J+25',
                          ],
                          resume: _donnees!.escargots,
                          fiche: 'Fiches Escargots',
                          libelleNes: 'Naissains Nés',
                        ),
                        _ => _ongletCycles(
                          titre: 'Suivi Reproduction — Cuniculture (Lapins)',
                          sousTitre:
                              'Numérotation continue (R1..Rn), suivi '
                              'multi-cages, palpation J+14, mise bas J+30 '
                              'et alerte réforme.',
                          jalons: const [
                            'Saillie J0',
                            'Palpation J+14',
                            'Boîte à nid J+28',
                            'Mise bas J+30',
                            'Sevrage J+60',
                          ],
                          // ⚠️⚠️ **DOUZE COLONNES, COMPTÉES SUR LA
                          // MAQUETTE** — `#panel-lapins`. Il en manquait
                          // QUATRE : « Sevrés (M/F) », « Poids Moyen (g) »,
                          // « Cages » et « Actions Cycle ». Une colonne
                          // absente ne se voit pas : le tableau reste
                          // lisible, simplement plus étroit que celui qui
                          // a été validé.
                          colonnes: const [
                            'Bande',
                            'N° Lapine',
                            'Date Saillie',
                            'Mâle N°',
                            'Résultat Palpation',
                            'Nés (Vivants)',
                            'Sevrés (M/F)',
                            'Morts S/Mère',
                            'Poids Moyen (g)',
                            'Cages',
                            'Statut Physio',
                            'Actions Cycle',
                          ],
                          cycles: _donnees!.lapins,
                          porcs: false,
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

  Widget _kpis(bool moyen) {
    final d = _donnees!;

    return GridView.count(
      crossAxisCount: moyen ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AgriSpacing.md,
      crossAxisSpacing: AgriSpacing.md,
      childAspectRatio: moyen ? 2.6 : 1.8,
      children: [
        _carteKpi(
          'Reproductrices Gestantes',
          '${d.gestantes}',
          AgriColors.infoBlue,
          AgriColors.infoBlue,
        ),
        _carteKpi(
          'Palpations / Échéances dues',
          '${d.palpationsDues}',
          AgriColors.accentYellow,
          AgriColors.brandForest,
        ),
        _carteKpi(
          'Mises bas / Éclosions',
          '${d.misesBasDuMois}',
          AgriColors.brandEmerald,
          AgriColors.brandEmerald,
        ),
        _carteKpi(
          'Alertes Réforme / Pertes',
          '${d.echecs}',
          AgriColors.errorRed,
          AgriColors.errorDeep,
        ),
      ],
    );
  }

  Widget _carteKpi(
    String libelle,
    String valeur,
    Color barre,
    Color couleurValeur,
  ) => CarteKpi(
    libelle: libelle,
    valeur: valeur,
    couleurLisere: barre,
    couleurValeur: couleurValeur,
    tailleValeur: 20,
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

  Widget _titreOnglet(String titre, String sousTitre, {Widget? action}) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titre,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AgriColors.onSurface,
              ),
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

  /// Bandeau « Rappel du cycle » — les jalons dans l'ordre, le dernier avant
  /// la naissance étant mis en avant comme dans la maquette.
  Widget _rappelDuCycle(List<String> jalons, String cle) => Container(
    key: Key('rappel-cycle-$cle'),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.infoBlue.withValues(alpha: 0.05),
      border: Border.all(color: AgriColors.infoBlue.withValues(alpha: 0.20)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Wrap(
      spacing: AgriSpacing.xs,
      runSpacing: AgriSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.event_repeat, size: 20, color: AgriColors.infoBlue),
        const Text(
          'Rappel du cycle :',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandForest,
          ),
        ),
        for (final jalon in jalons)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color:
                  jalon.contains('Mise bas') ||
                      jalon.contains('Mise Bas') ||
                      jalon.contains('Éclosion Attendue') ||
                      jalon.contains('Éclosion Naissains')
                  ? AgriColors.brandEmerald.withValues(alpha: 0.10)
                  : AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.full),
            ),
            child: Text(
              jalon,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AgriColors.brandForest,
              ),
            ),
          ),
      ],
    ),
  );

  static const _entete = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  // ── Onglets Lapins et Porcs ───────────────────────────────────────────────

  Widget _ongletCycles({
    required String titre,
    required String sousTitre,
    required List<String> jalons,
    required List<String> colonnes,
    required List<CycleReproduction> cycles,
    required bool porcs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titreOnglet(
          titre,
          sousTitre,
          action: ElevatedButton.icon(
            key: Key('declarer-saillie-${porcs ? 'porcs' : 'lapins'}'),
            onPressed: () => _ouvrirDeclaration(porcs: porcs),
            icon: const Icon(Icons.add_circle, size: 18),
            label: Text(
              porcs
                  ? 'Déclarer une Saillie Porc'
                  : 'Déclarer une Saillie Lapin',
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
        _rappelDuCycle(jalons, porcs ? 'porcs' : 'lapins'),
        const SizedBox(height: AgriSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              // ⚠️ Douze colonnes chez les lapins : la largeur suit.
              width: 1320,
              child: Column(
                children: [
                  Container(
                    color: AgriColors.surfaceZebra,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AgriSpacing.sm,
                      vertical: AgriSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        for (final c in colonnes)
                          Expanded(
                            flex: c == 'Bande' ? 3 : 2,
                            child: Text(c.toUpperCase(), style: _entete),
                          ),
                      ],
                    ),
                  ),
                  if (cycles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AgriSpacing.lg),
                      child: Text(
                        '— Aucun cycle de reproduction reçu pour cette '
                        'filière —',
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          fontStyle: FontStyle.italic,
                          color: AgriColors.outline,
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
                      child: porcs
                          ? _ligneTruie(cycles[i])
                          : _ligneLapine(cycles[i]),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _mentionLectureSeule(),
      ],
    );
  }

  /// Référence de sujet : un LIEN vers sa fiche quand un sujet porte ce nom.
  Widget _celluleRef(String ref, {int flex = 2, bool gras = false}) {
    final id = _sujets[ref];
    if (id == null || widget.onOuvrirSujet == null) {
      return _cellule(ref, flex: flex, gras: gras);
    }

    return Expanded(
      flex: flex,
      child: InkWell(
        key: Key('lien-sujet-$ref'),
        onTap: () => widget.onOuvrirSujet!(id),
        child: Text(
          ref,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: gras ? FontWeight.bold : FontWeight.normal,
            color: AgriColors.brandEmerald,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Widget _cellule(String texte, {int flex = 2, bool gras = false}) => Expanded(
    flex: flex,
    child: Text(
      texte,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: gras ? FontWeight.bold : FontWeight.normal,
      ),
    ),
  );

  Widget _ligneLapine(CycleReproduction c) {
    final e = c.evenement;

    return Row(
      children: [
        _cellule(c.codeBande, flex: 3, gras: true),
        _celluleRef(e.motherRef, gras: true),
        _cellule(_date(e.saillieDate)),
        _celluleRef(e.sireRef ?? '—'),
        Expanded(flex: 2, child: _pastillePalpation(c)),
        // ⚠️ « Nés (Vivants) » : la maquette écrit « 8 (7) » — total puis
        // vivants. La base porte `nes_vivants` et `nes_morts` ; le total est
        // donc leur somme, jamais une colonne à part.
        _cellule(
          e.nesVivants == null
              ? '—'
              : '${(e.nesVivants ?? 0) + (e.nesMorts ?? 0)} (${e.nesVivants})',
        ),
        _cellule(e.nesMorts == null ? '—' : '${e.nesMorts}'),
        // ⚠️⚠️ **TROIS COLONNES SANS DONNÉE AU POSTE, ET C'EST DIT PAR UN
        // TIRET.** `livestock_reproduction_events` ne porte ni sevrés, ni
        // ventilation M/F, ni pesée : elle suit un CYCLE, pas une portée. Et
        // aucun référentiel ne modélise de cage — même constat qu'au champ
        // « Cages Occupées » de la modale (ticket F0.35).
        _cellule('—'),
        _cellule('—', flex: 2),
        _cellule('—'),
        Expanded(flex: 2, child: _pastilleStatut(e)),
        // ⚠️ « Actions Cycle » : « Saisir Sevrage » et « Modifier » supposent
        // un canal d'envoi que le poste n'a pas — il ne déclare que la
        // saillie (ticket F0.35). La colonne reste, l'action est inerte.
        const Expanded(
          flex: 2,
          child: Opacity(
            opacity: 0.4,
            child: Icon(Icons.edit, size: 16, color: AgriColors.outline),
          ),
        ),
      ],
    );
  }

  Widget _ligneTruie(CycleReproduction c) {
    final e = c.evenement;
    final saillie = e.saillieDate;

    return Row(
      children: [
        _cellule(c.codeBande, flex: 3, gras: true),
        _celluleRef(e.motherRef, gras: true),
        _cellule(_date(saillie)),
        _celluleRef(e.sireRef ?? '—'),
        // ⚠️ RETOUR CHALEUR ET SEVRAGE SONT CALCULÉS, PAS STOCKÉS : aucune
        // colonne ne les porte. Ils se déduisent de la saillie, exactement
        // comme les bandeaux « Rappel du cycle » l'annoncent.
        _cellule(
          _dateDecalee(
            saillie,
            SuiviReproductionRepository.cyclePorcs.retourChaleur,
          ),
        ),
        _cellule(
          e.miseBasDateExpected != null
              ? _date(e.miseBasDateExpected)
              : _dateDecalee(
                  saillie,
                  SuiviReproductionRepository.cyclePorcs.miseBas,
                ),
        ),
        _cellule(e.nesVivants == null ? '—' : '${e.nesVivants}'),
        _cellule(
          e.sevrageDateExpected != null
              ? _date(e.sevrageDateExpected)
              : _dateDecalee(
                  e.miseBasDateActual,
                  SuiviReproductionRepository.cyclePorcs.sevrage,
                ),
        ),
        Expanded(flex: 2, child: _pastilleStatut(e)),
        // ⚠️ Même colonne « Action » que chez les lapins : inerte au poste.
        const Expanded(
          flex: 2,
          child: Opacity(
            opacity: 0.4,
            child: Icon(Icons.edit, size: 16, color: AgriColors.outline),
          ),
        ),
      ],
    );
  }

  /// ⚠️ **TROIS ÉTATS, PAS DEUX.** `palpation_date` nulle ne veut pas dire
  /// « négative » : elle veut dire « pas encore faite ». Confondre les deux
  /// ferait réformer une lapine qui n'a jamais été palpée.
  Widget _pastillePalpation(CycleReproduction c) {
    final e = c.evenement;

    final (libelle, couleur) = e.palpationDate != null
        ? (e.status == 'echec'
              ? ('Négative (−)', AgriColors.errorDeep)
              : ('Positive (+)', AgriColors.brandEmerald))
        : c.palpationDue(
            DateTime.now(),
            SuiviReproductionRepository.cycleLapins.palpation,
          )
        ? ('À palper', AgriColors.accentYellow)
        : ('En attente', AgriColors.outline);

    return _pastille(libelle, couleur);
  }

  Widget _pastilleStatut(LivestockReproductionEvent e) {
    final (libelle, couleur) = switch (e.status) {
      'echec' => ('Échec de saillie', AgriColors.errorDeep),
      'termine' => ('Cycle terminé', AgriColors.outline),
      _ =>
        e.miseBasDateActual != null
            ? ('Mère Allaitante', AgriColors.brandEmerald)
            : ('Gestante', AgriColors.infoBlue),
    };

    return _pastille(libelle, couleur);
  }

  Widget _pastille(String libelle, Color couleur) => Align(
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

  // ── Onglets Volailles et Escargots ────────────────────────────────────────

  /// ⚠️⚠️ **RÉSUMÉ, PAS UN SECOND FORMULAIRE.** Ces deux panneaux de la
  /// maquette recouvrent exactement ce que les fiches Reproducteurs et
  /// Escargots saisissent déjà. Les reconstruire créerait deux formulaires
  /// pour la même donnée — le composant Livewire a refusé pour la même raison
  /// (ticket 3.10), et le poste s'aligne.
  Widget _ongletCouvoir({
    required String titre,
    required String sousTitre,
    required List<String> jalons,
    required ResumeCouvoir resume,
    required String fiche,
    required String libelleNes,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titreOnglet(titre, sousTitre),
        const SizedBox(height: AgriSpacing.md),
        _rappelDuCycle(jalons, libelleNes),
        const SizedBox(height: AgriSpacing.md),
        Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _mesure(
                      'Œufs Couvés',
                      '${resume.couves}',
                      AgriColors.onSurface,
                    ),
                  ),
                  Expanded(
                    child: _mesure(
                      libelleNes,
                      '${resume.nes}',
                      AgriColors.brandEmerald,
                    ),
                  ),
                  Expanded(
                    child: _mesure(
                      "Taux d'Éclosion",
                      // ⚠️ TIRET, PAS « 0,0 % » : sans mise en incubation, un
                      // zéro se lirait comme un échec total du couvoir.
                      resume.tauxEclosion == null
                          ? '—'
                          : '${resume.tauxEclosion!.toStringAsFixed(1)} %',
                      AgriColors.brandEmerald,
                    ),
                  ),
                  Expanded(
                    child: _mesure(
                      'Bandes suivies',
                      '${resume.lots}',
                      AgriColors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AgriSpacing.md),
              Text(
                'Agrégats du mois, lus sur les fiches journalières. '
                'La saisie se fait sur « $fiche » — il n\'existe qu\'un seul '
                'formulaire pour cette donnée.',
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mesure(String libelle, String valeur, Color couleur) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        libelle,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.outline,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        valeur,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: couleur,
        ),
      ),
    ],
  );

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
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: AgriColors.brandForest),
        SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Text(
            'La saillie se déclare ici, hors ligne : elle part au prochain '
            'tirage. Palpation, mise bas et sevrage se saisissent sur la '
            'surface web — ce sont des corrections du cycle, que le '
            'serveur a pu faire évoluer entre-temps.',
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

  /// ⚠️⚠️ **LA MODALE DE LA MAQUETTE, CHAMP POUR CHAMP.** Cuniculture :
  /// Bande · N° Lapine · Mâle Saillisseur N° · Date de Saillie · Cages
  /// Occupées, puis la « Ligne du temps automatique calculée ». Porciculture :
  /// les quatre premiers seulement, sans cages ni aperçu — c'est ce que porte
  /// `modal-saillie-porc`, et l'aperçu n'y est pas.
  Future<void> _ouvrirDeclaration({required bool porcs}) async {
    final espece = porcs ? 'porciculture' : 'cuniculture';
    final bandes = await widget.depot.bandesDeclarables(espece);

    if (!mounted) return;

    if (bandes.isEmpty) {
      _message('Aucune bande $espece active sur ce poste.');
      return;
    }

    _femelle.clear();
    _male.clear();
    var bande = bandes.first.id;
    var date = DateTime.now();
    String? erreur;

    // ⚠️ `modal-saillie-lapin` de `suivi-reproduction.html` l.388 : panneau
    // `max-w-md`, barre de titre avec ✕, pied séparé par un filet.
    final declaree = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: porcs
              ? 'Déclarer une Saillie (Porciculture)'
              : 'Déclarer une Saillie (Cuniculture)',
          contenu: Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _etiquette('Bande *'),
                DropdownButtonFormField<String>(
                  key: const Key('saillie-bande'),
                  initialValue: bande,
                  decoration: _decoration(),
                  items: [
                    for (final b in bandes)
                      DropdownMenuItem(value: b.id, child: Text(b.code)),
                  ],
                  onChanged: (v) => bande = v ?? bande,
                ),
                const SizedBox(height: AgriSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _etiquette(
                            porcs
                                ? 'N° Truie (T1..Tn) *'
                                : 'N° Lapine (R1..Rn) *',
                          ),
                          TextField(
                            key: const Key('saillie-femelle'),
                            controller: _femelle,
                            decoration: _decoration(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AgriSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _etiquette(
                            porcs ? 'Verrat N° *' : 'Mâle Saillisseur N° *',
                          ),
                          TextField(
                            key: const Key('saillie-male'),
                            controller: _male,
                            decoration: _decoration(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AgriSpacing.md),
                _etiquette('Date de Saillie *'),
                InkWell(
                  key: const Key('saillie-date'),
                  onTap: () async {
                    final choisie = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (choisie != null) rafraichir(() => date = choisie);
                  },
                  child: InputDecorator(
                    decoration: _decoration(),
                    child: Text(
                      _date(date),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                if (!porcs) ...[
                  const SizedBox(height: AgriSpacing.md),
                  _etiquette('Cages Occupées'),
                  // ⚠️⚠️ CHAMP PRÉSENT ET DÉSACTIVÉ : aucune table ne
                  // modélise de sous-division « cage » — le composant
                  // Livewire l'avait déjà constaté au ticket 3.10, et
                  // `cage-check` n'apparaît nulle part dans le JS du
                  // prototype. Le laisser saisissable perdrait la valeur en
                  // silence ; le retirer masquerait un manque du schéma.
                  TextField(
                    key: const Key('saillie-cages'),
                    enabled: false,
                    decoration: _decoration().copyWith(
                      hintText: 'Référentiel des cages absent du schéma',
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
                if (_femelle.text.trim().isEmpty || _male.text.trim().isEmpty) {
                  rafraichir(
                    () => erreur =
                        'Le numéro de la femelle et celui du mâle sont requis.',
                  );
                  return;
                }

                try {
                  await widget.depot.declarerSaillie(
                    lotId: bande,
                    numeroFemelle: _femelle.text.trim(),
                    numeroMale: _male.text.trim(),
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
      if (mounted) {
        _message('Saillie enregistrée. Elle partira au prochain tirage.');
      }
    }
  }

  /// « Ligne du temps automatique calculée » de la maquette.
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
              Icon(Icons.calculate, size: 14, color: AgriColors.brandForest),
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
              // ⚠️ « Boîte à nid J+28 » figure dans l'aperçu de la maquette,
              // mais n'entre dans aucun calcul de suivi : jalon informatif,
              // sans colonne dédiée (même constat côté Livewire).
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
            text: _date(origine.add(Duration(days: jours))),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 10, color: AgriColors.brandForest),
    ),
  );

  Widget _etiquette(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Text(
      texte.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: AgriColors.brandForest,
      ),
    ),
  );

  InputDecoration _decoration() => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: 12,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      borderSide: const BorderSide(color: AgriColors.outlineVariant),
    ),
  );

  void _message(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  // ── Formats ───────────────────────────────────────────────────────────────

  static String _date(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _dateDecalee(DateTime? origine, int jours) =>
      origine == null ? '—' : _date(origine.add(Duration(days: jours)));
}
