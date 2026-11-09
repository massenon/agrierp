import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/comptabilite/exercice_choisi.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/lecture_seule.dart';
import '../../core/widgets/pagination_agri.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'soins_repository.dart';
import 'soins_vaccins_repository.dart';
import 'suffixe_doublon.dart';
import '../../core/theme/symboles_agri.dart';

/// Soins et vaccins — maître : `resources/views/livewire/elevage/soins-vaccins-hub.blade.php` et
/// `App\Livewire\Elevage\SoinsVaccinsHub` (doctrine, article 5 : la vue Blade fait foi).
///
/// ⚠️⚠️ **HUB À TROIS ONGLETS, DANS L'ORDRE DU WEB** : Registre Vétérinaire · Calendrier Vétérinaire · Suivi
/// Sanitaire. La barre latérale ne porte qu'une entrée.
///
/// Tickets H8 et H8b (19/10/2026) — l'écran suit le Blade : registre à six colonnes, cellule « CODE (Espèce) »,
/// coût « 12 500 FCFA », modale Nouveau Soin (largeur sm, exemples, aide et libellé rouge de la rémanence,
/// zone de texte des symptômes), messages du composant ; Suivi Sanitaire COMPLET et « Planifier une
/// Intervention » (décision client D-H8 : saisis au poste, envoyés au serveur).
///
/// ➕ AJOUTS DU POSTE, GARDÉS PAR DÉCISION CLIENT (19/10/2026) — à construire au web (ticket H11), jamais à
/// retirer ici sans décision : colonne « Statut » du registre (placée APRÈS les six du Blade), filtres et
/// recherche, boutons Importer / Exporter PDF, protocole calculé et rémanences dans le calendrier (légende
/// « planifié » / « calculé »).
///
/// ⚠️ **LE BOUTON « TESTER RÉMANENCE » N'EST PAS REPRIS** : widget de démonstration de la maquette, retiré du
/// web aussi.
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
  /// Les trois onglets du hub, dans son ordre (`:tabs` de `x-tab-page`).
  static const onglets = <(String, IconData)>[
    ('Registre Vétérinaire', SymbolesAgri.medical_information),
    ('Calendrier Vétérinaire', SymbolesAgri.event_repeat),
    ('Suivi Sanitaire', SymbolesAgri.monitor_heart),
  ];

  /// Les six types d'action de la modale, dans l'ordre du Blade.
  static const typesAction = [
    'Vaccination',
    'Traitement curatif',
    'Vermifuge',
    'Vitamines',
    'Antistress',
    'Hépato-protection',
  ];

  /// Colonnes du registre : les SIX du Blade, dans son ordre, puis « Statut » (ajout du poste, gardé).
  static const colonnesRegistre = <(String, int)>[
    ('Date', 2),
    ('Lot / Espèce', 3),
    ("Type d'action", 3),
    ('Produit', 3),
    ('Dose', 2),
    ('Actions', 1),
    ('Statut', 2),
  ];

  /// Colonnes de l'infirmerie (onglet Suivi Sanitaire), celles du Blade.
  static const colonnesInfirmerie = <(String, int)>[
    ("Date d'entrée", 2),
    ('Lot / Sujet', 3),
    ('Motif', 4),
    ("Niveau d'isolement", 3),
    ('Statut', 2),
    ('Actions', 2),
  ];

  // ── Messages du composant (`dispatch('toast', …)` de `SoinsVaccinsHub.php`) ──
  static String _soinEnregistre(int remanence) => remanence > 0
      ? 'Soin enregistré — bande bloquée à la vente pendant $remanence jour(s).'
      : 'Soin enregistré avec succès.';
  static const _interventionPlanifiee = 'Intervention planifiée avec succès.';
  static const _administrationConfirmee =
      'Administration confirmée avec succès.';
  static const _entreeEnregistree =
      'Entrée infirmerie enregistrée avec succès.';
  static const _sujetReintegre = 'Sujet réintégré avec succès.';
  static const _decesDeclare = 'Décès déclaré.';
  static const _ficheArchivee = 'Fiche archivée avec succès.';

  static const _selectionner = '-- Sélectionner --';

  String _onglet = onglets.first.$1;
  String _recherche = '';
  String _categorie = '';
  String _filiere = '';
  final _accordeonsOuverts = <String>{};

  DonneesSoinsVaccins? _donnees;
  bool _chargement = true;

  /// Ticket EX7 (EF9) — pages du registre et de l'infirmerie (25 lignes), dans l'exercice affiché.
  int _pageRegistre = 1;
  int _pageInfirmerie = 1;

  final _produit = TextEditingController();
  final _dose = TextEditingController();
  final _veterinaire = TextEditingController();
  final _symptomes = TextEditingController();
  final _cout = TextEditingController();
  final _remanence = TextEditingController();
  final _intervention = TextEditingController();
  final _sujet = TextEditingController();
  final _motif = TextEditingController();

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
      _intervention,
      _sujet,
      _motif,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    // Ticket EX7 (EF9) — registre et infirmerie de l'exercice AFFICHÉ (web : `paginate(25)` dans l'exercice).
    final exercice = PorteeExerciceChoisi.lire(context);
    final donnees = await widget.depot.charger(exercice: exercice);
    if (!mounted) return;
    setState(() {
      _donnees = donnees;
      _chargement = false;
    });
  }

  void _toast(String message, {TypeToast type = TypeToast.succes}) {
    if (mounted) ToastAgri.afficher(context, message, type: type);
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
              // celle du contenu.
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
                      const SizedBox(height: AgriSpacing.md),
                      switch (_onglet) {
                        'Calendrier Vétérinaire' => _ongletCalendrier(),
                        'Suivi Sanitaire' => _ongletSuivi(),
                        _ => _ongletRegistre(),
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

  /// `x-kpi-accordion` : grille `grid-cols-2 xl:grid-cols-4` ; SOUS `md` seulement, le titre devient un bouton
  /// « (Replier / Déplier) » et la grille est repliée par défaut (`kpi-mobile-collapsed`).
  Widget _accordeonKpi(String titre, List<Widget> cartes) {
    final quatre = AgriBreakpoints.tresLarge(context);
    final grille = GrilleKpi(colonnes: quatre ? 4 : 2, children: cartes,
    );
    if (AgriBreakpoints.moyen(context)) return grille;

    final ouvert = _accordeonsOuverts.contains(titre);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('accordeon-$titre'),
          onTap: () => setState(
            () => ouvert
                ? _accordeonsOuverts.remove(titre)
                : _accordeonsOuverts.add(titre),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AgriSpacing.md,
              vertical: AgriSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Row(
              children: [
                const Icon(
                  SymbolesAgri.bar_chart,
                  size: 18,
                  color: AgriColors.brandForest,
                ),
                const SizedBox(width: AgriSpacing.xs),
                Expanded(
                  child: Text(
                    '$titre (Replier / Déplier)',
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
                Icon(ouvert ? SymbolesAgri.expand_less : SymbolesAgri.expand_more, size: 18),
              ],
            ),
          ),
        ),
        if (ouvert) ...[const SizedBox(height: AgriSpacing.sm), grille],
      ],
    );
  }

  /// Ticket EX7 (EF10) — exercice affiché clos : grisé, motif en info-bulle (`@lectureSeule` du web).
  Widget _boutonPrincipal(String cle, String libelle, VoidCallback action) =>
      LectureSeule.infobulle(LectureSeule.motif(context), ElevatedButton.icon(
        key: Key(cle),
        onPressed: LectureSeule.motif(context) == null ? action : null,
        icon: const Icon(SymbolesAgri.add_circle, size: 18),
        label: Text(
          libelle,
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
      ));

  // ── Onglet 1 : Registre Vétérinaire ───────────────────────────────────────

  Widget _ongletRegistre() {
    final d = _donnees!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          titre: 'Registre Vétérinaire',
          icone: SymbolesAgri.vaccines,
          sousTitre:
              'Carnet médical numérique : vaccinations, traitements et '
              'vermifuges du cheptel.',
          action: _boutonPrincipal(
            'nouveau-soin',
            'Nouveau Soin',
            _ouvrirNouveauSoin,
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _accordeonKpi('Résumé sanitaire', [
          _carteKpi(
            'Interventions (mois)',
            '${d.interventionsDuMois}',
            SymbolesAgri.vaccines,
            AgriColors.brandEmerald,
          ),
          _carteKpi(
            'Vaccinations planifiées',
            '${d.vaccinationsPlanifiees}',
            SymbolesAgri.event,
            AgriColors.infoBlue,
            couleurIcone: AgriColors.infoBlue,
          ),
          // 🔴→✅ H8b : lit l'infirmerie (`InfirmaryRecord::where('status', 'en_cours')`), descendue au poste.
          _carteKpi(
            'Animaux en quarantaine',
            '${d.enQuarantaine}',
            SymbolesAgri.coronavirus,
            AgriColors.accentYellow,
            couleurIcone: AgriColors.brandForest,
          ),
          _carteKpi(
            'Coût sanitaire (mois)',
            SoinsVaccinsRepository.fcfa(d.coutDuMois),
            SymbolesAgri.payments,
            AgriColors.errorRed,
            couleurIcone: AgriColors.errorRed,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        // ➕ Ajout du poste, gardé (décision client) : filtres, recherche, Importer / Exporter.
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
              prefixIcon: Icon(SymbolesAgri.search, size: 18),
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
        // ⚠️ IMPORT ET EXPORT PRÉSENTS ET INERTES (ajouts du poste gardés) : ni sélecteur de fichier ni chaîne
        // d'édition ne sont raccordés à cet écran.
        _boutonInerte(SymbolesAgri.upload_file, 'Importer'),
        _boutonInerte(SymbolesAgri.picture_as_pdf, 'Exporter PDF'),
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

  /// Filière d'une ligne, telle que le filtre la nomme.
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

      // ⚠️ « Rechercher un diagnostic, un lot » : la recherche porte aussi sur les symptômes.
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

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  static const _celluleBande = TextStyle(
    fontSize: AgriTypography.xs,
    fontWeight: FontWeight.bold,
    color: AgriColors.brandForest,
  );

  /// Gabarit commun des deux tableaux du hub (`bg-white rounded-lg border … overflow-x-auto`).
  Widget _tableau({
    required List<(String, int)> colonnes,
    required List<List<Widget>> lignes,
    required String vide,
    String prefixeCle = 'ligne',
  }) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: LayoutBuilder(
      builder: (_, contraintes) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(960, contraintes.maxWidth),
          child: Column(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: AgriColors.surfaceZebra,
                  border: Border(
                    bottom: BorderSide(color: AgriColors.outlineVariant),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              child: Row(
                children: [
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(
                        libelle.toUpperCase(),
                        // `<th class="… text-right …">Actions</th>` dans les deux tableaux du Blade.
                        textAlign: libelle == 'Actions'
                            ? TextAlign.right
                            : TextAlign.left,
                        style: _enteteColonne,
                      ),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  vide,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: AgriTypography.sm,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            for (var i = 0; i < lignes.length; i++)
              Container(
                key: Key('$prefixeCle-$i'),
                decoration: BoxDecoration(
                  color: i.isOdd
                      ? AgriColors.surfaceZebra
                      : AgriColors.surfaceCard,
                  border: const Border(
                    bottom: BorderSide(color: AgriColors.outlineVariant),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
                ),
                child: Row(
                  children: [
                    for (var c = 0; c < colonnes.length; c++)
                      Expanded(flex: colonnes[c].$2, child: lignes[i][c]),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    ),
  );

  Widget _tableauRegistre() {
    final d = _donnees!;
    final filtrees = _lignesFiltrees;
    // Ticket EX7 (EF9) — 25 soins par page dans l'exercice affiché, filtres compris (web : filtres PUIS `paginate`).
    final etat = PorteeExerciceChoisi.lire(context);
    final lignes = etat == null ? filtrees : PaginationAgri.tranche(filtrees, _pageRegistre);

    final tableau = _tableau(
      colonnes: colonnesRegistre,
      prefixeCle: 'soin',
      // Registre vide : message exact du Blade. Registre non vide que les filtres (ajout du poste) vident : le
      // dire, plutôt que de laisser croire qu'aucun soin n'existe.
      vide: d.registre.isEmpty
          ? 'Aucun soin enregistré pour le moment.'
          : '— Aucun soin au registre pour ces critères —',
      lignes: [
        for (final l in lignes)
          [
            Text(_date(l.soin.recordDate), style: _cellule),
            Text(l.lotEspece, style: _celluleBande),
            Text(l.soin.actionType, style: _cellule),
            Text(l.soin.productUsed ?? '—', style: _cellule),
            Text(l.soin.dose ?? '—', style: _cellule),
            // 🔴→✅ Ticket U3 (décision client D-U3 du 19/10/2026) — l'archivage se fait au poste comme au web :
            // bouton `title="Archiver"` (icône `delete`, 18 px, `text-outline`, `text-right`) puis la modale
            // `x-modal-confirm-delete`. L'icône était inerte : le poste ne pouvait pas archiver.
            Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                // Ticket EX7 (EF10) — exercice affiché clos : le motif remplace l'info-bulle, l'action est grisée.
                message: LectureSeule.motif(context) ?? 'Archiver',
                child: InkWell(
                  key: Key('archiver-soin-${l.soin.id}'),
                  onTap: LectureSeule.motif(context) == null ? () => _archiverSoin(l) : null,
                  child: const Padding(
                    padding: EdgeInsets.all(AgriSpacing.xs),
                    child: Icon(
                      SymbolesAgri.delete,
                      size: 18,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
              ),
            ),
            _pastilleEffectue(),
          ],
      ],
    );
    if (etat == null) return tableau;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tableau,
        PaginationAgri(
          nom: 'registre',
          total: filtrees.length,
          page: _pageRegistre,
          annee: etat.annee,
          onPage: (p) => setState(() => _pageRegistre = p),
        ),
      ],
    );
  }

  /// Ticket U3 — `archiveSoin($id)` du web, derrière sa modale `x-modal-confirm-delete` (titre « Confirmer
  /// l'archivage », icône `archive` `text-error-deep`, libellé `action_type — code de bande`, « Annuler » puis
  /// « Archiver » `bg-error-red`), toast `warning` « Fiche archivée avec succès. ».
  ///
  /// ⚠️ ARCHIVER N'EFFACE RIEN : `is_active = false`, la ligne part à l'envoi (`pending`). La rémanence créée par
  /// le soin reste en vigueur, comme au web.
  Future<void> _archiverSoin(LigneRegistre l) async {
    final libelle = '${l.soin.actionType} — ${l.codeBande}';
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        icone: SymbolesAgri.archive,
        couleurIcone: AgriColors.errorDeep,
        titre: "Confirmer l'archivage",
        message:
            '$libelle sera marqué(e) comme archivé(e) (statut inactif). '
            "Aucune suppression définitive n'est effectuée.",
        actions: [
          BoutonModaleSecondaire(
            libelle: 'Annuler',
            onPressed: () => Navigator.of(contexte).pop(false),
          ),
          BoutonModalePrimaire(
            key: const Key('archivage-soin-confirmer'),
            libelle: 'Archiver',
            couleur: AgriColors.errorRed,
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    await widget.depot.archiverSoin(l.soin.id);
    await _charger();
    _toast(_ficheArchivee, type: TypeToast.avertissement);
  }

  /// ➕ Colonne « Statut » (ajout du poste, gardé) : un seul statut, « Effectué » — `veterinary_records` ne
  /// contient que des soins ADMINISTRÉS ; une intervention à venir vit dans le calendrier.
  Widget _pastilleEffectue() => _pastille(
    'Effectué',
    fond: AgriColors.brandEmerald.withValues(alpha: 0.10),
    bord: AgriColors.brandEmerald.withValues(alpha: 0.30),
    texte: AgriColors.brandEmerald,
  );

  Widget _pastille(
    String libelle, {
    required Color fond,
    required Color bord,
    required Color texte,
  }) => Align(
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
        libelle,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: texte,
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

  Widget _pastilleLegende(Color couleur, {bool anneau = false}) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: anneau ? AgriColors.surfaceCard : couleur,
      border: anneau ? Border.all(color: couleur, width: 2) : null,
      shape: BoxShape.circle,
    ),
  );

  Widget _ongletCalendrier() {
    final d = _donnees!;
    final aujourdhui = HeureBenin.maintenant();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          titre: 'Calendrier Vétérinaire',
          icone: SymbolesAgri.event,
          sousTitre:
              "Planificateur de prophylaxie : lots d'élevage × échéances de "
              'soins (14 prochains jours).',
          action: _boutonPrincipal(
            'planifier-intervention',
            'Planifier une Intervention',
            _ouvrirPlanifier,
          ),
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
                  _pastilleLegende(_couleursEtat[etat]!),
                  const SizedBox(width: AgriSpacing.xs),
                  Text(libelle, style: _cellule),
                ],
              ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        // ➕ AJOUT DU POSTE (décision client) : la SOURCE de chaque pastille. Pleine = intervention planifiée
        // (`veterinary_calendar_events`, comme au web) ; anneau = calculée depuis le protocole prophylactique ou
        // rémanence en cours, ce que le web ne montre pas.
        Wrap(
          spacing: AgriSpacing.lg,
          runSpacing: AgriSpacing.xs,
          children: [
            Row(
              key: const Key('legende-source-planifie'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _pastilleLegende(AgriColors.outline),
                const SizedBox(width: AgriSpacing.xs),
                const Text('Intervention planifiée (saisie)', style: _cellule),
              ],
            ),
            Row(
              key: const Key('legende-source-calcule'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _pastilleLegende(AgriColors.outline, anneau: true),
                const SizedBox(width: AgriSpacing.xs),
                const Text('Calculé (protocole)', style: _cellule),
              ],
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        if (d.calendrier.isEmpty)
          Container(
            padding: const EdgeInsets.all(AgriSpacing.lg),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: const Text(
              'Aucune bande active pour le moment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AgriTypography.sm,
                color: AgriColors.outline,
              ),
            ),
          )
        else
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
                  width: max(200 + d.fenetre.length * 44, contraintes.maxWidth),
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
                              child: Text(
                                'LOT / BANDE',
                                style: _enteteColonne,
                              ),
                            ),
                          ),
                          for (final j in d.fenetre)
                            Container(
                              width: 44,
                              color: _memeJour(j, aujourdhui)
                                  ? AgriColors.brandEmerald.withValues(
                                      alpha: 0.10,
                                    )
                                  : null,
                              child: Text(
                                // `format('j/n')`.
                                '${j.day}/${j.month}',
                                textAlign: TextAlign.center,
                                style: _memeJour(j, aujourdhui)
                                    ? _enteteColonne.copyWith(
                                        color: AgriColors.brandEmerald,
                                        fontWeight: FontWeight.w800,
                                      )
                                    : _enteteColonne,
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < d.calendrier.length; i++)
                      _ligneGantt(
                        d.calendrier[i],
                        d.fenetre,
                        i.isOdd,
                        // Ticket UNI : deux bandes de même code (doublon déjà présent) ne partagent pas la même clé.
                        suffixeDoublon(d.calendrier.map((l) => l.codeBande), i),
                      ),
                  ],
                ),
              ),
            ),
            ),
          ),
      ],
    );
  }

  static bool _memeJour(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _ligneGantt(
    LigneCalendrier ligne,
    List<DateTime> fenetre,
    bool zebre,
    String suffixeCle,
  ) {
    return Container(
      key: Key('gantt-${ligne.codeBande}$suffixeCle'),
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
                  Text(ligne.codeBande, style: _celluleBande),
                  // ⚠️ L'INDÉTERMINATION DU PROTOCOLE EST DITE, pas laissée en ligne vide.
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
    final planifie = ligne.evenements
        .where((e) => _memeJour(e.jour, jour))
        .firstOrNull;
    final calculee = ligne.interventions
        .where((i) => _memeJour(i.jour, jour))
        .firstOrNull;

    return SizedBox(
      width: 44,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (planifie == null && calculee == null)
            const SizedBox(height: 28),
          // Intervention PLANIFIÉE (web) : pastille pleine, un clic confirme l'administration tant qu'elle
          // n'est pas « done » (`wire:click="confirmAdministration(…)"`).
          if (planifie != null)
            Tooltip(
              message: planifie.tache,
              child: InkWell(
                key: Key('planifie-${planifie.id}'),
                customBorder: const CircleBorder(),
                onTap: planifie.confirmable
                    ? () => _confirmerAdministration(planifie)
                    : null,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _couleursEtat[planifie.etat],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    SymbolesAgri.vaccines,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          // ➕ Intervention CALCULÉE (poste) : anneau, sans action.
          if (calculee != null)
            Padding(
              padding: EdgeInsets.only(top: planifie == null ? 0 : 2),
              child: Tooltip(
                message: '${calculee.traitement} (calculé)',
                child: Container(
                  width: planifie == null ? 28 : 20,
                  height: planifie == null ? 28 : 20,
                  decoration: BoxDecoration(
                    color: AgriColors.surfaceCard,
                    border: Border.all(
                      color: _couleursEtat[calculee.etat]!,
                      width: 2,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    SymbolesAgri.vaccines,
                    size: planifie == null ? 14 : 10,
                    color: _couleursEtat[calculee.etat],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmerAdministration(EvenementPlanifie e) async {
    await widget.depot.confirmerAdministration(e.id);
    await _charger();
    _toast(_administrationConfirmee);
  }

  // ── Onglet 3 : Suivi Sanitaire (H8b) ──────────────────────────────────────

  Widget _ongletSuivi() {
    final d = _donnees!;
    final k = d.kpisInfirmerie;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          titre: 'Suivi Sanitaire',
          icone: SymbolesAgri.monitor_heart,
          sousTitre:
              "Infirmerie d'élevage : suivi clinique des animaux en isolement, "
              'quarantaine ou observation.',
          action: _boutonPrincipal(
            'nouvelle-entree-infirmerie',
            'Nouvelle Entrée Infirmerie',
            _ouvrirNouvelleEntree,
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _accordeonKpi("KPIs de l'Infirmerie", [
          _carteKpi(
            'En Quarantaine',
            '${k.enQuarantaine}',
            SymbolesAgri.coronavirus,
            AgriColors.accentYellow,
            couleurIcone: AgriColors.brandForest,
          ),
          _carteKpi(
            'Guéris (mois)',
            '${k.guerisMois}',
            SymbolesAgri.task_alt,
            AgriColors.brandEmerald,
          ),
          _carteKpi(
            'Sous Traitement',
            '${k.sousTraitement}',
            SymbolesAgri.medication,
            AgriColors.infoBlue,
            couleurIcone: AgriColors.infoBlue,
          ),
          _carteKpi(
            'Décès (mois)',
            '${k.decesMois}',
            SymbolesAgri.heart_broken,
            AgriColors.errorRed,
            couleurIcone: AgriColors.errorRed,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          colonnes: colonnesInfirmerie,
          prefixeCle: 'infirmerie',
          vide: "Aucune entrée d'infirmerie pour le moment.",
          lignes: [
            for (final l in (PorteeExerciceChoisi.lire(context) == null ? d.infirmerie : PaginationAgri.tranche(d.infirmerie, _pageInfirmerie)))
              [
                Text(_date(l.entree.entryDate), style: _cellule),
                Text(l.lotSujet, style: _celluleBande),
                Text(l.entree.motif, style: _cellule),
                Text(l.entree.isolationLevel ?? '—', style: _cellule),
                _pastilleInfirmerie(l.entree.status),
                _actionsInfirmerie(l),
              ],
          ],
        ),
        // Ticket EX7 (EF9) — `<x-pagination>` du web, sous le tableau.
        if (PorteeExerciceChoisi.lire(context) case final etat?)
          PaginationAgri(
            nom: 'infirmerie',
            total: d.infirmerie.length,
            page: _pageInfirmerie,
            annee: etat.annee,
            onPage: (p) => setState(() => _pageInfirmerie = p),
          ),
      ],
    );
  }

  Widget _pastilleInfirmerie(String statut) => switch (statut) {
    'en_cours' => _pastille(
      'En cours',
      fond: AgriColors.accentYellow.withValues(alpha: 0.20),
      bord: AgriColors.accentYellow,
      texte: AgriColors.brandForest,
    ),
    'reintegre' => _pastille(
      'Réintégré',
      fond: AgriColors.brandEmerald.withValues(alpha: 0.10),
      bord: AgriColors.brandEmerald.withValues(alpha: 0.30),
      texte: AgriColors.brandEmerald,
    ),
    // `@else` du Blade : tout autre statut s'affiche « Décès ».
    _ => _pastille(
      'Décès',
      fond: AgriColors.errorBg,
      bord: AgriColors.errorDeep.withValues(alpha: 0.30),
      texte: AgriColors.errorDeep,
    ),
  };

  Widget _actionsInfirmerie(LigneInfirmerie l) {
    if (l.entree.status != 'en_cours') {
      return const Align(
        alignment: Alignment.centerRight,
        child: Text(
          'Clôturé',
          style: TextStyle(fontSize: 11, color: AgriColors.outline),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          key: Key('reintegrer-${l.entree.id}'),
          tooltip: LectureSeule.motif(context) ?? 'Valider la guérison et réintégrer',
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            SymbolesAgri.settings_backup_restore,
            size: 18,
            color: AgriColors.brandEmerald,
          ),
          onPressed: LectureSeule.motif(context) != null ? null : () async {
            await widget.depot.reintegrer(l.entree.id);
            await _charger();
            _toast(_sujetReintegre);
          },
        ),
        IconButton(
          key: Key('deces-${l.entree.id}'),
          tooltip: LectureSeule.motif(context) ?? 'Déclarer le décès',
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            SymbolesAgri.heart_broken,
            size: 18,
            color: AgriColors.errorDeep,
          ),
          onPressed: LectureSeule.motif(context) != null ? null : () async {
            await widget.depot.declarerDeces(l.entree.id);
            await _charger();
            _toast(_decesDeclare, type: TypeToast.avertissement);
          },
        ),
      ],
    );
  }

  // ── Modale « Nouveau Soin » ───────────────────────────────────────────────

  /// `modal-nouveau-soin` du Blade (`max-width="sm"`), champ pour champ.
  ///
  /// ⚠️ **LE DÉLAI D'ATTENTE N'EST PAS UN CHAMP COMME LES AUTRES** : renseigné avec un produit, il crée la
  /// période de rémanence qui BLOQUE la vente de la bande, dans la même transaction que le soin.
  Future<void> _ouvrirNouveauSoin() async {
    final bandes = await widget.depot.bandesActives();
    if (!mounted) return;

    for (final c in [_produit, _dose, _veterinaire, _symptomes, _cout]) {
      c.clear();
    }
    // `$this->soinRemanence = 0`.
    _remanence.text = '0';

    String? bande;
    String? type;
    var date = HeureBenin.aujourdhui();
    String? erreur;

    final delai = await afficherModale<int>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: 'Nouveau Soin',
          largeur: LargeurModale.sm,
          contenu: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _etiquette('Lot / Bande *'),
              _liste(
                cle: 'soin-bande',
                valeur: bande,
                options: [for (final b in bandes) (b.id, b.libelleAvecEspece)],
                surChangement: (v) => rafraichir(() => bande = v),
              ),
              const SizedBox(height: AgriSpacing.md),
              _champDate(
                etiquette: 'Date du Soin *',
                cle: 'soin-date',
                date: date,
                // Décision D-U6 étendue (« pas de divergence ») — le web accepte une date future (`'soinDate' =>
                // ['required', 'date']`), l'envoi aussi (`record_date` : `required|date`) : le poste de même.
                dernier: DateTime(HeureBenin.maintenant().year + 5, 12, 31),
                surChoix: (d) => rafraichir(() => date = d),
              ),
              const SizedBox(height: AgriSpacing.md),
              _etiquette("Type d'Action *"),
              _liste(
                cle: 'soin-type',
                valeur: type,
                options: [for (final t in typesAction) (t, t)],
                surChangement: (v) => rafraichir(() => type = v),
              ),
              const SizedBox(height: AgriSpacing.md),
              // `grid grid-cols-2 gap-sm`.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _champ(
                      'Produit Utilisé',
                      _produit,
                      'soin-produit',
                      exemple: 'ex : Alfamec',
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(
                    child: _champ(
                      'Dose',
                      _dose,
                      'soin-dose',
                      exemple: 'ex : 0.5ml/lapin',
                    ),
                  ),
                ],
              ),
              // Libellé ROUGE (`text-error-deep`) et aide sous le champ : c'est un blocage sanitaire.
              _etiquette(
                "Délai d'Attente / Rémanence (jours)",
                couleur: AgriColors.errorDeep,
              ),
              TextField(
                key: const Key('soin-remanence'),
                controller: _remanence,
                keyboardType: TextInputType.number,
                decoration: _decoration(),
                style: const TextStyle(fontSize: AgriTypography.sm),
              ),
              const Padding(
                padding: EdgeInsets.only(top: AgriSpacing.xs),
                child: Text(
                  'Si > 0, la bande sera automatiquement bloquée à la vente '
                  '(POS) pendant ce délai.',
                  style: TextStyle(fontSize: 9, color: AgriColors.outline),
                ),
              ),
              const SizedBox(height: AgriSpacing.md),
              _champ(
                'Vétérinaire / Animalier',
                _veterinaire,
                'soin-vet',
                exemple: 'ex : ADJOVI Bernadin',
              ),
              _champ(
                'Symptômes observés',
                _symptomes,
                'soin-symptomes',
                lignes: 2,
              ),
              _champ(
                'Coût (FCFA)',
                _cout,
                'soin-cout',
                numerique: true,
                exemple: '0',
              ),
              if (erreur != null) _erreur('soin-erreur', erreur!),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(),
            ),
            BoutonModalePrimaire(
              key: const Key('soin-enregistrer'),
              libelle: 'Enregistrer',
              onPressed: () async {
                final remanence = int.tryParse(_remanence.text.trim()) ?? 0;
                final manque = [
                  if (bande == null) 'Le champ Lot / Bande est obligatoire.',
                  if (type == null) "Le champ Type d'Action est obligatoire.",
                  // ⚠️⚠️ UN DÉLAI SANS PRODUIT NE BLOQUE RIEN (règle du serveur : la rémanence n'est créée
                  // que si un produit est nommé). Accepter la saisie ferait croire la bande bloquée.
                  if (remanence > 0 && _produit.text.trim().isEmpty)
                    "Un délai d'attente exige de nommer le produit : sans "
                        'lui, la bande resterait vendable.',
                ];
                if (manque.isNotEmpty) {
                  rafraichir(() => erreur = manque.join(' '));
                  return;
                }

                await widget.soins.enregistrer(
                  lotId: bande!,
                  typeAction: type!,
                  produit: _texte(_produit),
                  dose: _texte(_dose),
                  veterinaire: _texte(_veterinaire),
                  symptomes: _texte(_symptomes),
                  cout: double.tryParse(_cout.text.trim()),
                  delaiAttenteJours: remanence,
                  quand: date,
                );

                if (context.mounted) Navigator.of(context).pop(remanence);
              },
            ),
          ],
        ),
      ),
    );

    if (delai != null) {
      await _charger();
      _toast(_soinEnregistre(delai));
    }
  }

  // ── Modale « Planifier une Intervention » (H8b) ───────────────────────────

  /// `modal-planifier-intervention` du Blade (`savePlan()`).
  Future<void> _ouvrirPlanifier() async {
    final bandes = await widget.depot.bandesActives();
    if (!mounted) return;

    _intervention.clear();
    String? bande;
    var date = HeureBenin.aujourdhui();
    String? erreur;

    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: 'Planifier une Intervention',
          largeur: LargeurModale.sm,
          contenu: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _etiquette('Lot / Bande *'),
              _liste(
                cle: 'plan-bande',
                valeur: bande,
                options: [for (final b in bandes) (b.id, b.code)],
                surChangement: (v) => rafraichir(() => bande = v),
              ),
              const SizedBox(height: AgriSpacing.md),
              _champ(
                'Intervention *',
                _intervention,
                'plan-intervention',
                exemple: 'ex : Rappel Myxomatose',
              ),
              _champDate(
                etiquette: 'Date Prévue *',
                cle: 'plan-date',
                date: date,
                // Une intervention se PLANIFIE : aucune borne haute au web (`'date'`).
                dernier: DateTime(HeureBenin.maintenant().year + 5, 12, 31),
                surChoix: (d) => rafraichir(() => date = d),
              ),
              if (erreur != null) _erreur('plan-erreur', erreur!),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BoutonModalePrimaire(
              key: const Key('plan-planifier'),
              libelle: 'Planifier',
              onPressed: () async {
                final tache = _intervention.text.trim();
                final manque = [
                  if (bande == null) 'Le champ Lot / Bande est obligatoire.',
                  if (tache.isEmpty) 'Le champ Intervention est obligatoire.',
                  // `'planTaskType' => ['required', 'string', 'max:100']`.
                  if (tache.length > 100)
                    'Le champ Intervention dépasse le maximum autorisé (100).',
                ];
                if (manque.isNotEmpty) {
                  rafraichir(() => erreur = manque.join(' '));
                  return;
                }
                await widget.depot.planifierIntervention(
                  lotId: bande!,
                  intervention: tache,
                  datePrevue: date,
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
      _toast(_interventionPlanifiee);
    }
  }

  // ── Modale « Nouvelle Entrée Infirmerie » (H8b) ───────────────────────────

  /// `modal-nouvelle-entree-infirmerie` du Blade (`saveInfirmaryEntry()`).
  Future<void> _ouvrirNouvelleEntree() async {
    final bandes = await widget.depot.bandesActives();
    if (!mounted) return;

    _sujet.clear();
    _motif.clear();
    String? bande;
    String? isolement;
    var date = HeureBenin.aujourdhui();
    String? erreur;

    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: 'Nouvelle Entrée Infirmerie',
          largeur: LargeurModale.sm,
          contenu: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _etiquette('Lot / Bande *'),
              _liste(
                cle: 'infirmerie-bande',
                valeur: bande,
                options: [for (final b in bandes) (b.id, b.code)],
                surChangement: (v) => rafraichir(() => bande = v),
              ),
              const SizedBox(height: AgriSpacing.md),
              _champ(
                'Sujet (optionnel)',
                _sujet,
                'infirmerie-sujet',
                exemple: 'ex : #A-204',
              ),
              _champ(
                'Motif *',
                _motif,
                'infirmerie-motif',
                exemple: 'ex : Suspicion Newcastle',
              ),
              _etiquette("Niveau d'Isolement *"),
              _liste(
                cle: 'infirmerie-isolement',
                valeur: isolement,
                options: [
                  for (final n in SoinsVaccinsRepository.niveauxIsolement)
                    (n, n),
                ],
                surChangement: (v) => rafraichir(() => isolement = v),
              ),
              const SizedBox(height: AgriSpacing.md),
              _champDate(
                etiquette: "Date d'Entrée *",
                cle: 'infirmerie-date',
                date: date,
                // Ticket U6 (décision client D-U6 du 19/10/2026) — mêmes règles que le web (`'infDate' =>
                // ['required', 'date']`) : une date FUTURE est acceptée, et l'envoi l'accepte aussi. Borne du
                // sélecteur seulement, comme « Planifier une Intervention ».
                dernier: DateTime(HeureBenin.maintenant().year + 5, 12, 31),
                surChoix: (d) => rafraichir(() => date = d),
              ),
              if (erreur != null) _erreur('infirmerie-erreur', erreur!),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BoutonModalePrimaire(
              key: const Key('infirmerie-enregistrer'),
              libelle: 'Enregistrer',
              onPressed: () async {
                final motif = _motif.text.trim();
                final manque = [
                  if (bande == null) 'Le champ Lot / Bande est obligatoire.',
                  if (motif.isEmpty) 'Le champ Motif est obligatoire.',
                  // `'infMotif' => ['required', 'string', 'max:255']`.
                  if (motif.length > 255)
                    'Le champ Motif dépasse le maximum autorisé (255).',
                  if (isolement == null)
                    "Le champ Niveau d'Isolement est obligatoire.",
                  // `sujet_ref` : `max:50` à l'envoi.
                  if (_sujet.text.trim().length > 50)
                    'Le champ Sujet dépasse le maximum autorisé (50).',
                ];
                if (manque.isNotEmpty) {
                  rafraichir(() => erreur = manque.join(' '));
                  return;
                }
                await widget.depot.enregistrerEntreeInfirmerie(
                  lotId: bande!,
                  sujetRef: _sujet.text,
                  motif: motif,
                  niveauIsolement: isolement!,
                  dateEntree: date,
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
      _toast(_entreeEnregistree);
    }
  }

  // ── Briques des modales ───────────────────────────────────────────────────

  /// `<select>` du Blade, ouvert sur `<option value="">-- Sélectionner --</option>`.
  Widget _liste({
    required String cle,
    required String? valeur,
    required List<(String, String)> options,
    required ValueChanged<String?> surChangement,
  }) => DropdownButtonFormField<String>(
    key: Key(cle),
    initialValue: valeur,
    isExpanded: true,
    decoration: _decoration(),
    hint: const Text(
      _selectionner,
      style: TextStyle(fontSize: AgriTypography.sm),
    ),
    items: [
      for (final (id, libelle) in options)
        DropdownMenuItem(
          value: id,
          child: Text(libelle, style: const TextStyle(fontSize: AgriTypography.sm)),
        ),
    ],
    onChanged: surChangement,
  );

  Widget _champDate({
    required String etiquette,
    required String cle,
    required DateTime date,
    required DateTime dernier,
    required ValueChanged<DateTime> surChoix,
  }) => ChampDateFormulaire(
    cle: Key(cle),
    etiquette: etiquette,
    valeur: date,
    onTap: () async {
      final choisie = await showDatePicker(
        context: context,
        initialDate: date.isAfter(dernier) ? dernier : date,
        firstDate: DateTime(2020),
        lastDate: dernier,
      );
      if (choisie != null) surChoix(choisie);
    },
  );

  Widget _erreur(String cle, String texte) => Padding(
    padding: const EdgeInsets.only(top: AgriSpacing.sm),
    child: Text(
      texte,
      key: Key(cle),
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        color: AgriColors.errorDeep,
      ),
    ),
  );

  static String? _texte(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Widget _champ(
    String libelle,
    TextEditingController controleur,
    String cle, {
    bool numerique = false,
    String? exemple,
    int lignes = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _etiquette(libelle),
        TextField(
          key: Key(cle),
          controller: controleur,
          keyboardType: numerique
              ? TextInputType.number
              : (lignes > 1 ? TextInputType.multiline : TextInputType.text),
          minLines: lignes,
          maxLines: lignes,
          decoration: _decoration(exemple: exemple),
          style: const TextStyle(fontSize: AgriTypography.sm),
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
  }) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, size: 26, color: AgriColors.brandEmerald),
                const SizedBox(width: AgriSpacing.xs),
                Flexible(
                  child: Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 22,
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

  Widget _carteKpi(
    String libelle,
    String valeur,
    IconData icone,
    Color barre, {
    Color couleurIcone = AgriColors.brandEmerald,
  }) => CarteKpi(
    libelle: libelle,
    valeur: valeur,
    legende: '',
    icone: icone,
    couleurLisere: barre,
    couleurIcone: couleurIcone,
  );

  /// `block text-[10px] text-brand-forest font-bold uppercase mb-xs`.
  Widget _etiquette(String texte, {Color couleur = AgriColors.brandForest}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
        child: Text(
          texte.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: couleur,
          ),
        ),
      );

  InputDecoration _decoration({String? exemple}) => InputDecoration(
    isDense: true,
    hintText: exemple,
    hintStyle: const TextStyle(
      fontSize: AgriTypography.sm,
      color: AgriColors.outline,
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: 12,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      borderSide: const BorderSide(color: AgriColors.outlineVariant),
    ),
  );

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
