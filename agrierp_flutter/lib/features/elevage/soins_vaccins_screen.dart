import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import 'soins_repository.dart';
import 'soins_vaccins_repository.dart';

/// `prototype_html/soins-vaccins-hub.html` → Soins et vaccins.
///
/// ⚠️⚠️ **HUB À TROIS ONGLETS, DANS L'ORDRE DE LA MAQUETTE** : Registre
/// Vétérinaire · Calendrier Vétérinaire · Suivi Sanitaire. Le hub charge ses
/// trois pages (`vms-registre`, `vms-calendrier`, `vms-suivi`) dans des
/// `<iframe>` ; la barre latérale ne porte qu'une entrée. Le poste reproduit
/// cette structure, sans ajouter d'entrée de menu que la maquette n'a pas.
///
/// ⚠️ **LE BOUTON « TESTER RÉMANENCE » N'EST PAS REPRIS.** C'est un widget de
/// démonstration explicitement marqué comme tel dans la maquette (« Activer
/// une rémanence de démonstration ») : il crée un blocage sanitaire fictif.
/// Son absence est un choix, pas un oubli.
class SoinsVaccinsScreen extends StatefulWidget {
  const SoinsVaccinsScreen({
    super.key,
    required this.depot,
    required this.soins,
  });

  final SoinsVaccinsRepository depot;
  final SoinsRepository soins;

  @override
  State<SoinsVaccinsScreen> createState() => _SoinsVaccinsScreenState();
}

class _SoinsVaccinsScreenState extends State<SoinsVaccinsScreen> {
  /// Les trois onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Registre Vétérinaire', Icons.medical_information),
    ('Calendrier Vétérinaire', Icons.event_repeat),
    ('Suivi Sanitaire', Icons.monitor_heart),
  ];

  /// Les six types d'action de la modale, dans l'ordre de la maquette.
  static const typesAction = [
    'Vaccination',
    'Traitement curatif',
    'Vermifuge',
    'Vitamines',
    'Antistress',
    'Hépato-protection',
  ];

  String _onglet = onglets.first.$1;
  String _recherche = '';
  String _categorie = '';
  String _filiere = '';

  DonneesSoinsVaccins? _donnees;
  bool _chargement = true;

  final _produit = TextEditingController();
  final _dose = TextEditingController();
  final _veterinaire = TextEditingController();
  final _symptomes = TextEditingController();
  final _cout = TextEditingController();
  final _remanence = TextEditingController();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final c in [
      _produit,
      _dose,
      _veterinaire,
      _symptomes,
      _cout,
      _remanence,
    ]) {
      c.dispose();
    }
    super.dispose();
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
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.lg),
                      switch (_onglet) {
                        'Calendrier Vétérinaire' => _ongletCalendrier(),
                        'Suivi Sanitaire' => _ongletSuivi(),
                        _ => _ongletRegistre(large),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

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
              key: Key('onglet-vms-$titre'),
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

  // ── Onglet 1 : Registre Vétérinaire ───────────────────────────────────────

  Widget _ongletRegistre(bool large) {
    final d = _donnees!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          titre: 'Registre Vétérinaire',
          icone: Icons.vaccines,
          sousTitre:
              'Carnet médical numérique : vaccinations, traitements et '
              'vermifuges du cheptel.',
          action: ElevatedButton.icon(
            key: const Key('nouveau-soin'),
            onPressed: _ouvrirNouveauSoin,
            icon: const Icon(Icons.add_circle, size: 18),
            label: const Text(
              'Nouveau Soin',
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
        const SizedBox(height: AgriSpacing.lg),
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AgriSpacing.md,
          crossAxisSpacing: AgriSpacing.md,
          childAspectRatio: large ? 2.6 : 1.7,
          children: [
            _carteKpi(
              'Interventions (mois)',
              '${d.interventionsDuMois}',
              Icons.vaccines,
              AgriColors.brandEmerald,
            ),
            _carteKpi(
              'Vaccinations planifiées',
              '${d.vaccinationsPlanifiees}',
              Icons.event,
              AgriColors.infoBlue,
              couleurIcone: AgriColors.infoBlue,
            ),
            // ⚠️⚠️ TIRET, PAS ZÉRO : `infirmary_records` ne descend pas au
            // poste. « 0 » se lirait « aucun animal isolé », alors que la
            // vérité est « le poste ne reçoit pas l'infirmerie ».
            _carteKpi(
              'Animaux en quarantaine',
              '—',
              Icons.coronavirus,
              AgriColors.accentYellow,
              couleurIcone: AgriColors.brandForest,
              legende: 'Infirmerie non synchronisée',
            ),
            _carteKpi(
              'Coût sanitaire (mois)',
              '${d.coutDuMois.round()} F',
              Icons.payments,
              AgriColors.errorRed,
              couleurIcone: AgriColors.errorRed,
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.lg),
        _filtres(),
        const SizedBox(height: AgriSpacing.md),
        _tableauRegistre(),
      ],
    );
  }

  Widget _filtres() => Container(
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Wrap(
      spacing: AgriSpacing.sm,
      runSpacing: AgriSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            key: const Key('vms-recherche'),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Rechercher un diagnostic, un lot...',
              hintStyle: TextStyle(fontSize: AgriTypography.xs),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: AgriTypography.xs),
            onChanged: (v) => setState(() => _recherche = v),
          ),
        ),
        _menu(
          cle: 'vms-categorie',
          valeur: _categorie,
          defaut: 'Toutes catégories',
          options: const [
            'Vaccination',
            'Traitement curatif',
            'Vermifuge',
            'Vitamines',
          ],
          surChangement: (v) => setState(() => _categorie = v),
        ),
        _menu(
          cle: 'vms-filiere',
          valeur: _filiere,
          defaut: 'Toutes espèces',
          options: const ['Lapins', 'Volailles', 'Porcs'],
          surChangement: (v) => setState(() => _filiere = v),
        ),
        // ⚠️ IMPORT ET EXPORT PRÉSENTS ET INERTES. L'import CSV/Excel
        // suppose un sélecteur de fichier et un analyseur ; l'export PDF,
        // une chaîne d'édition. Ni l'un ni l'autre n'est embarqué —
        // présents et visiblement désactivés, comme le champ de recherche
        // de la barre supérieure et le bouton PDF du tableau de bord.
        _boutonInerte(Icons.upload_file, 'Importer'),
        _boutonInerte(Icons.picture_as_pdf, 'Exporter PDF'),
      ],
    ),
  );

  Widget _menu({
    required String cle,
    required String valeur,
    required String defaut,
    required List<String> options,
    required void Function(String) surChangement,
  }) => Container(
    key: Key(cle),
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: valeur,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.onSurface,
        ),
        items: [
          DropdownMenuItem(value: '', child: Text(defaut)),
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) => surChangement(v ?? ''),
      ),
    ),
  );

  Widget _boutonInerte(IconData icone, String libelle) => Opacity(
    opacity: 0.5,
    child: OutlinedButton.icon(
      onPressed: null,
      icon: Icon(icone, size: 18),
      label: Text(
        libelle,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AgriColors.brandForest,
        side: const BorderSide(color: AgriColors.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
      ),
    ),
  );

  /// Filière d'une ligne, telle que la maquette la nomme dans son filtre.
  static const _filieres = {
    'cuniculture': 'Lapins',
    'aviculture': 'Volailles',
    'porciculture': 'Porcs',
  };

  List<LigneRegistre> get _lignesFiltrees {
    final terme = _recherche.trim().toLowerCase();

    return _donnees!.registre.where((l) {
      if (_categorie.isNotEmpty && l.soin.actionType != _categorie) {
        return false;
      }
      if (_filiere.isNotEmpty && _filieres[l.codeEspece] != _filiere) {
        return false;
      }
      if (terme.isEmpty) return true;

      // ⚠️ La maquette cherche « un diagnostic, un lot » : la recherche porte
      // donc aussi sur les symptômes, pas seulement sur le libellé du soin.
      return [
        l.codeBande,
        l.soin.actionType,
        l.soin.productUsed ?? '',
        l.soin.symptomes ?? '',
      ].any((v) => v.toLowerCase().contains(terme));
    }).toList();
  }

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  Widget _tableauRegistre() {
    final lignes = _lignesFiltrees;

    return Container(
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 900,
          child: Column(
            children: [
              Container(
                color: AgriColors.surfaceZebra,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text('DATE', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('LOT / ESPÈCE', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text("TYPE D'ACTION", style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('PRODUIT', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('DOSE', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('STATUT', style: _enteteColonne),
                    ),
                    // ⚠️ **SEPT COLONNES, COMPTÉES SUR LA MAQUETTE** —
                    // `vms-registre.html`. « Actions » manquait : la colonne
                    // porte « Modifier » et « Dossier clinique », deux gestes
                    // réservés au web (référentiel et infirmerie). Elle reste,
                    // l'action est inerte.
                    Expanded(child: Text('ACTIONS', style: _enteteColonne)),
                  ],
                ),
              ),
              if (lignes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AgriSpacing.lg),
                  child: Text(
                    '— Aucun soin au registre pour ces critères —',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontStyle: FontStyle.italic,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
              for (var i = 0; i < lignes.length; i++)
                Container(
                  key: Key('soin-$i'),
                  color: i.isOdd
                      ? AgriColors.surfaceZebra
                      : AgriColors.surfaceCard,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.md,
                    vertical: AgriSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          _date(lignes[i].soin.recordDate),
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          lignes[i].codeBande,
                          style: const TextStyle(
                            fontSize: AgriTypography.xs,
                            fontWeight: FontWeight.bold,
                            color: AgriColors.brandForest,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          lignes[i].soin.actionType,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          lignes[i].soin.productUsed ?? '—',
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          lignes[i].soin.dose ?? '—',
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(flex: 2, child: _pastilleEffectue()),
                      const Expanded(
                        child: Opacity(
                          opacity: 0.4,
                          child: Icon(
                            Icons.edit,
                            size: 16,
                            color: AgriColors.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// ⚠️ **UN SEUL STATUT AU REGISTRE : « Effectué ».** La maquette en montre
  /// trois, mais `veterinary_records` ne contient que des soins ADMINISTRÉS —
  /// un soin planifié vit dans le calendrier prophylactique, onglet suivant.
  /// Afficher « Planifié » ici supposerait une table de planification que ni
  /// le poste ni le serveur ne portent.
  Widget _pastilleEffectue() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AgriColors.brandEmerald.withValues(alpha: 0.10),
        border: Border.all(
          color: AgriColors.brandEmerald.withValues(alpha: 0.30),
        ),
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      child: const Text(
        'Effectué',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AgriColors.brandEmerald,
        ),
      ),
    ),
  );

  // ── Onglet 2 : Calendrier Vétérinaire ─────────────────────────────────────

  static const _couleursEtat = {
    EtatIntervention.effectue: AgriColors.brandEmerald,
    EtatIntervention.planifie: AgriColors.accentYellow,
    EtatIntervention.enRetard: AgriColors.errorRed,
    EtatIntervention.traitementEnCours: AgriColors.infoBlue,
  };

  Widget _ongletCalendrier() {
    final d = _donnees!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          titre: 'Calendrier Vétérinaire',
          icone: Icons.event,
          sousTitre:
              'Planificateur Gantt de prophylaxie : lots d\'élevage × '
              'échéances de soins.',
          // ⚠️ « Planifier une Intervention » n'est pas repris : le calendrier
          // du poste est CALCULÉ depuis le protocole prophylactique servi par
          // le serveur. Une intervention ponctuelle ajoutée ici n'aurait ni
          // table pour la porter ni canal pour la remonter.
          action: null,
        ),
        const SizedBox(height: AgriSpacing.md),
        Wrap(
          spacing: AgriSpacing.lg,
          runSpacing: AgriSpacing.xs,
          children: [
            for (final (etat, libelle) in const [
              (EtatIntervention.effectue, 'Effectué'),
              (EtatIntervention.planifie, 'Planifié'),
              (EtatIntervention.enRetard, 'En retard'),
              (EtatIntervention.traitementEnCours, 'Traitement en cours'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _couleursEtat[etat],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.xs),
                  Text(
                    libelle,
                    style: const TextStyle(fontSize: AgriTypography.xs),
                  ),
                ],
              ),
          ],
        ),
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
              width: 200 + d.fenetre.length * 44,
              child: Column(
                children: [
                  Container(
                    color: AgriColors.surfaceZebra,
                    padding: const EdgeInsets.symmetric(
                      vertical: AgriSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 200,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AgriSpacing.md,
                            ),
                            child: Text('LOT / BANDE', style: _enteteColonne),
                          ),
                        ),
                        for (final j in d.fenetre)
                          SizedBox(
                            width: 44,
                            child: Text(
                              '${j.day}/${j.month}',
                              textAlign: TextAlign.center,
                              style: _enteteColonne,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (d.calendrier.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AgriSpacing.lg),
                      child: Text(
                        '— Aucune bande active sur ce poste —',
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          fontStyle: FontStyle.italic,
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                  for (var i = 0; i < d.calendrier.length; i++)
                    _ligneGantt(d.calendrier[i], d.fenetre, i.isOdd),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ligneGantt(
    LigneCalendrier ligne,
    List<DateTime> fenetre,
    bool zebre,
  ) {
    return Container(
      key: Key('gantt-${ligne.codeBande}'),
      color: zebre ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ligne.codeBande,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                  // ⚠️ L'INDÉTERMINATION EST DITE, pas laissée en ligne vide :
                  // une ligne vide se lirait « rien de prévu », ce qui ferait
                  // sauter des traitements.
                  if (ligne.motifIndetermine != null)
                    Text(
                      ligne.motifIndetermine!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        fontStyle: FontStyle.italic,
                        color: AgriColors.outline,
                      ),
                    ),
                ],
              ),
            ),
          ),
          for (final j in fenetre) _celluleGantt(ligne, j),
        ],
      ),
    );
  }

  Widget _celluleGantt(LigneCalendrier ligne, DateTime jour) {
    final intervention = ligne.interventions
        .where(
          (i) =>
              i.jour.year == jour.year &&
              i.jour.month == jour.month &&
              i.jour.day == jour.day,
        )
        .firstOrNull;

    return SizedBox(
      width: 44,
      child: intervention == null
          ? const SizedBox(height: 28)
          : Tooltip(
              message: intervention.traitement,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _couleursEtat[intervention.etat],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.vaccines,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }

  // ── Onglet 3 : Suivi Sanitaire ────────────────────────────────────────────

  /// ⚠️⚠️ **`infirmary_records` NE DESCEND PAS AU POSTE.** La table existe côté
  /// serveur — vérifiée présente — mais ne figure pas dans la charge du
  /// tirage. Les cinq KPI de l'infirmerie et son tableau en dépendent
  /// entièrement. L'onglet reste, et dit pourquoi : le retirer ferait diverger
  /// la structure du hub selon ce qui est embarqué.
  Widget _ongletSuivi() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        titre: 'Suivi Sanitaire',
        icone: Icons.monitor_heart,
        sousTitre: "Infirmerie, quarantaine et suivi des sujets isolés.",
        action: null,
      ),
      const SizedBox(height: AgriSpacing.md),
      Container(
        key: const Key('suivi-non-embarque'),
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: AgriColors.surfaceCard,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '— Module non embarqué au poste —',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontStyle: FontStyle.italic,
                color: AgriColors.outline,
              ),
            ),
            SizedBox(height: AgriSpacing.sm),
            Text(
              "L'infirmerie — entrées, niveau d'isolement, guérisons et "
              'décès — vit dans une table que la synchronisation ne '
              'descend pas au poste. Les cinq indicateurs de cet onglet '
              'et son tableau en dépendent entièrement : ils se lisent '
              'sur la surface web, jamais recalculés ici.',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  // ── Modale « Nouveau Soin » ───────────────────────────────────────────────

  /// ⚠️⚠️ **LA MODALE DE LA MAQUETTE, CHAMP POUR CHAMP** : Lot / Bande ·
  /// Date du Soin · Type d'Action · Produit Utilisé · Dose · Délai d'Attente /
  /// Rémanence (jours) · Vétérinaire / Animalier · Symptômes observés ·
  /// Coût (FCFA).
  ///
  /// ⚠️ **LE DÉLAI D'ATTENTE N'EST PAS UN CHAMP COMME LES AUTRES** : renseigné
  /// avec un produit, il crée la période de rémanence qui BLOQUE la vente de
  /// la bande. C'est un garde-fou de santé publique, et le dépôt l'écrit dans
  /// la même transaction que le soin — tout ou rien.
  Future<void> _ouvrirNouveauSoin() async {
    final bandes = await widget.depot.bandesActives();

    if (!mounted) return;

    if (bandes.isEmpty) {
      _message('Aucune bande active sur ce poste.');
      return;
    }

    for (final c in [
      _produit,
      _dose,
      _veterinaire,
      _symptomes,
      _cout,
      _remanence,
    ]) {
      c.clear();
    }

    var bande = bandes.first.id;
    var type = typesAction.first;
    var date = DateTime.now();
    String? erreur;

    // ⚠️ `modal-nouveau-soin` de `vms-registre.html` l.295 : panneau
    // `max-w-lg`, barre de titre avec ✕, pied séparé par un filet.
    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: 'Nouveau Soin',
          largeur: LargeurModale.lg,
          contenu: Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _etiquette('Lot / Bande *'),
                DropdownButtonFormField<String>(
                  key: const Key('soin-bande'),
                  initialValue: bande,
                  decoration: _decoration(),
                  items: [
                    for (final b in bandes)
                      DropdownMenuItem(value: b.id, child: Text(b.code)),
                  ],
                  onChanged: (v) => bande = v ?? bande,
                ),
                const SizedBox(height: AgriSpacing.md),
                _etiquette('Date du Soin *'),
                InkWell(
                  key: const Key('soin-date'),
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
                const SizedBox(height: AgriSpacing.md),
                _etiquette("Type d'Action *"),
                DropdownButtonFormField<String>(
                  key: const Key('soin-type'),
                  initialValue: type,
                  decoration: _decoration(),
                  items: [
                    for (final t in typesAction)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => type = v ?? type,
                ),
                const SizedBox(height: AgriSpacing.md),
                _champ('Produit Utilisé', _produit, 'soin-produit'),
                _champ('Dose', _dose, 'soin-dose'),
                _champ(
                  "Délai d'Attente / Rémanence (jours)",
                  _remanence,
                  'soin-remanence',
                  numerique: true,
                ),
                _champ('Vétérinaire / Animalier', _veterinaire, 'soin-vet'),
                _champ('Symptômes observés', _symptomes, 'soin-symptomes'),
                _champ('Coût (FCFA)', _cout, 'soin-cout', numerique: true),
                if (erreur != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AgriSpacing.sm),
                    child: Text(
                      erreur!,
                      key: const Key('soin-erreur'),
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        color: AgriColors.errorDeep,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BoutonModalePrimaire(
              key: const Key('soin-enregistrer'),
              libelle: 'Enregistrer',
              onPressed: () async {
                final delai = int.tryParse(_remanence.text.trim()) ?? 0;

                // ⚠️⚠️ UN DÉLAI SANS PRODUIT NE BLOQUE RIEN, et c'est la règle
                // du serveur : la rémanence n'est créée que si un produit est
                // nommé. Accepter la saisie ferait croire la bande bloquée
                // alors qu'elle resterait vendable.
                if (delai > 0 && _produit.text.trim().isEmpty) {
                  rafraichir(
                    () => erreur =
                        "Un délai d'attente exige de nommer le produit : sans "
                        'lui, la bande resterait vendable.',
                  );
                  return;
                }

                await widget.soins.enregistrer(
                  lotId: bande,
                  typeAction: type,
                  produit: _texte(_produit),
                  dose: _texte(_dose),
                  veterinaire: _texte(_veterinaire),
                  symptomes: _texte(_symptomes),
                  cout: double.tryParse(_cout.text.trim()),
                  delaiAttenteJours: delai,
                  quand: date,
                );

                if (context.mounted) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
    );

    if (enregistre == true) {
      await _charger();
      if (mounted) {
        _message('Soin enregistré. Il partira au prochain tirage.');
      }
    }
  }

  static String? _texte(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Widget _champ(
    String libelle,
    TextEditingController controleur,
    String cle, {
    bool numerique = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _etiquette(libelle),
        TextField(
          key: Key(cle),
          controller: controleur,
          keyboardType: numerique ? TextInputType.number : TextInputType.text,
          decoration: _decoration(),
          style: const TextStyle(fontSize: 14),
        ),
      ],
    ),
  );

  // ── Briques communes ──────────────────────────────────────────────────────

  Widget _entete({
    required String titre,
    required String sousTitre,
    required IconData icone,
    Widget? action,
  }) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icone, size: 26, color: AgriColors.brandEmerald),
                  const SizedBox(width: AgriSpacing.xs),
                  Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.onSurface,
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
    ),
  );

  Widget _carteKpi(
    String libelle,
    String valeur,
    IconData icone,
    Color barre, {
    Color couleurIcone = AgriColors.brandEmerald,
    String legende = '',
  }) => CarteKpi(
    libelle: libelle,
    valeur: valeur,
    legende: legende,
    icone: icone,
    couleurLisere: barre,
    couleurIcone: couleurIcone,
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

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
