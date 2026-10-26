import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'parametres_elevage_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `parametres-elevage.blade.php` (composant `App\Livewire\Elevage\ParametresElevage`) → Paramètres Élevage.
///
/// ⚠️⚠️ **LE BLADE FAIT FOI** (doctrine, article 5 ; tickets H9 et H9b). Onglets, titres, sous-titres, colonnes
/// (dans l'ordre), formats des cellules, boutons, modales (titres « Saisir / Modifier … », champs, exemples,
/// options, « Annuler » / « Enregistrer »), confirmation de suppression et messages des toasts sont ceux du web,
/// vérifiés en LISANT le Blade et le composant par `test/parametres_elevage_blade_test.dart`.
///
/// ⚠️⚠️ **DÉCISION CLIENT D-H9 (19/10/2026) : MODIFIABLE AU POSTE COMME AU WEB.** Les quatre onglets étaient en
/// lecture seule tant que le serveur ignorait les envois ; depuis H9b, chaque enregistrement est écrit en
/// `pending` et part à la synchronisation (`RecordParametresElevageFromDeviceAction`, droit `manage-elevage`).
/// Supprimer = ARCHIVER (`is_active = false`) : la ligne quitte la liste, comme au web (ticket 14.55).
///
/// ➕ AJOUT DU POSTE : l'état d'envoi d'une ligne (« En attente d'envoi », « Refusé par le serveur » et son
/// motif). Le web écrit directement ; le poste ne laisse pas passer une saisie non acquittée pour appliquée.
///
/// ⚠️ Sans le droit `manage-elevage` ([peutModifier] faux), les boutons d'ajout, de modification, de
/// suppression et d'enregistrement sont MASQUÉS : la saisie serait refusée à l'envoi.
class ParametresElevageScreen extends StatefulWidget {
  const ParametresElevageScreen({
    super.key,
    required this.depot,
    this.peutModifier = false,
  });

  final ParametresElevageRepository depot;

  /// Droit `manage-elevage` du rôle de la session (`PermissionsPoste.peut`).
  final bool peutModifier;

  @override
  State<ParametresElevageScreen> createState() =>
      _ParametresElevageScreenState();
}

class _ParametresElevageScreenState extends State<ParametresElevageScreen> {
  /// Les quatre onglets, dans l'ordre du Blade (`x-tab-page :tabs`).
  static const onglets = <(String, IconData)>[
    ('Fiche de Rationnement (g/j)', SymbolesAgri.restaurant),
    ('Calendriers de Prophylaxie', SymbolesAgri.event_repeat),
    ('Types de Provende', SymbolesAgri.inventory_2),
    ('Numérotation Bandes & Sujets', SymbolesAgri.tag),
  ];

  /// Messages des toasts du composant (`dispatch('toast', message: …)`).
  static const _rationEnregistree = 'Ration enregistrée avec succès.';
  static const _echeanceEnregistree = 'Échéance enregistrée avec succès.';
  static const _provendeEnregistree =
      'Type de provende enregistré avec succès.';
  static const _numerotationEnregistree =
      'Formats de numérotation enregistrés avec succès.';
  static const _rappelEnregistre = 'Délai de rappel des soins enregistré.';
  static const _parametreArchive =
      'Paramètre archivé — restaurable depuis Paramètres > Restauration.';

  static const _selectionner = '-- Sélectionner --';

  /// Libellés du formulaire de numérotation, dans l'ordre du Blade, par clé du serveur.
  static const _libellesNumerotation = <String, String>{
    'bande_format':
        "Format d'Affichage du Nom de Bande (Terrain / Toutes Espèces)",
    'lapine_prefix': 'Lapines Reproductrices',
    'male_prefix': 'Mâles Saillisseurs',
    'truie_prefix': 'Truies Reproductrices',
    'verrat_prefix': 'Verrats Reproducteurs',
    'portee_prefix': 'Portées de Porcelets',
    'volaille_prefix': 'Préfixe Lots Volailles / Pondeuses',
    'parc_prefix': 'Préfixe Bâtiments / Parcs Volailles',
    'escargot_prefix': 'Préfixe Parcs / Fosses Escargots',
  };

  String _onglet = onglets.first.$1;
  EspeceProphylaxie _espece = EspeceProphylaxie.lapins;

  DonneesParametresElevage? _donnees;

  final _formats = <String, TextEditingController>{
    for (final cle in _libellesNumerotation.keys) cle: TextEditingController(),
  };
  final _rappel = TextEditingController();
  String? _erreurNumerotation;
  String? _erreurRappel;

  // Champs des modales.
  final _stade = TextEditingController();
  final _grammes = TextEditingController();
  final _periode = TextEditingController();
  final _traitement = TextEditingController();
  final _produit = TextEditingController();
  final _dose = TextEditingController();
  final _delaiRemanence = TextEditingController();
  final _nom = TextEditingController();
  final _sac = TextEditingController();
  final _prix = TextEditingController();

  @override
  void initState() {
    super.initState();
    _charger(formulaires: true);
  }

  @override
  void dispose() {
    for (final c in [
      ..._formats.values,
      _rappel,
      _stade,
      _grammes,
      _periode,
      _traitement,
      _produit,
      _dose,
      _delaiRemanence,
      _nom,
      _sac,
      _prix,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// [formulaires] : recharge aussi la numérotation et le délai de rappel dans leurs champs (ouverture, puis
  /// après leur propre enregistrement) — jamais après une autre saisie, qui effacerait une frappe en cours.
  Future<void> _charger({bool formulaires = false}) async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() {
      _donnees = donnees;
      if (formulaires) {
        final n = donnees.numerotation;
        final valeurs = <String, String?>{
          'bande_format': n?.bandeFormat,
          'lapine_prefix': n?.lapinePrefix,
          'male_prefix': n?.malePrefix,
          'truie_prefix': n?.truiePrefix,
          'verrat_prefix': n?.verratPrefix,
          'portee_prefix': n?.porteePrefix,
          'volaille_prefix': n?.volaillePrefix,
          'parc_prefix': n?.parcPrefix,
          'escargot_prefix': n?.escargotPrefix,
        };
        for (final MapEntry(key: cle, value: c) in _formats.entries) {
          c.text = valeurs[cle] ?? '';
        }
        _rappel.text = donnees.rappelSoinsJours?.toString() ?? '';
      }
    });
  }

  void _toast(String message, {TypeToast type = TypeToast.succes}) {
    if (mounted) ToastAgri.afficher(context, message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              // ⚠️ `Builder` ET NON `LayoutBuilder` : la mise en page se décide sur la largeur de l'ÉCRAN.
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
                        'Calendriers de Prophylaxie' => _ongletProphylaxie(
                          d,
                          large,
                        ),
                        'Types de Provende' => _ongletProvende(d, large),
                        'Numérotation Bandes & Sujets' => _ongletNumerotation(
                          d,
                          large,
                        ),
                        _ => _ongletRationnement(d, large),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  /// `x-tab-page` : actif bordure basse émeraude, inactif transparent ; icône 18, libellé `text-xs` gras.
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
              key: Key('onglet-parametres-$titre'),
              onTap: () => setState(() => _onglet = titre),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: AgriSpacing.sm,
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
                    const SizedBox(width: AgriSpacing.xs),
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
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

  // ── Onglet 1 : Fiche de Rationnement ──────────────────────────────────────

  Widget _ongletRationnement(DonneesParametresElevage d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        titre: 'Fiche de Rationnement des Animaux',
        icone: SymbolesAgri.restaurant,
        // `… exprimée en <strong>Grammes (g/j)</strong>.`
        sousTitre: const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    'Consommation journalière théorique par tête exprimée en ',
              ),
              TextSpan(
                text: 'Grammes (g/j)',
                style: TextStyle(fontWeight: AgriTypography.gras),
              ),
              TextSpan(text: '.'),
            ],
          ),
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        bouton: _boutonAjout(
          'Ajouter une Ration',
          'ajouter-ration',
          () => _ouvrirRation(null),
        ),
        large: large,
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ Le Blade n'a pas de ligne « vide » pour les rations (`@foreach`, sans `@empty`) : rien ne s'affiche.
      _tableau(
        largeur: 900,
        colonnes: const [
          ('Espèce', 3, false),
          ("Stade Physiologique / Tranche d'Âge", 5, false),
          ('Ration (g/tête/jour)', 3, true),
          ('Actions', 2, true),
        ],
        lignes: [
          for (var i = 0; i < d.rations.length; i++)
            _ligne(i, 'ration-${d.rations[i].ration.id}', [
              _avecEtat(
                Text(
                  d.rations[i].especeLisible,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.demiGras,
                  ),
                ),
                d.rations[i].etat,
                'ration-${d.rations[i].ration.id}',
              ),
              Text(
                d.rations[i].ration.stageLabel,
                overflow: TextOverflow.ellipsis,
                style: _cellule,
              ),
              Text(
                ParametresElevageRepository.grammes(
                  d.rations[i].ration.rationGPerDay,
                ),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandEmerald,
                ),
              ),
              _actions(
                'ration-${d.rations[i].ration.id}',
                modifier: () => _ouvrirRation(d.rations[i]),
                supprimer: () => _confirmerSuppression(
                  libelle: d.rations[i].ration.stageLabel,
                  cle: 'ration-${d.rations[i].ration.id}',
                  archiver: () =>
                      widget.depot.archiverRation(d.rations[i].ration.id),
                ),
              ),
            ]),
        ],
      ),
    ],
  );

  // ── Onglet 2 : Calendriers de Prophylaxie ─────────────────────────────────

  Widget _ongletProphylaxie(DonneesParametresElevage d, bool large) {
    final lignes = d.prophylaxiePour(_espece);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          titre: 'Calendriers de Prophylaxie & Traitements Récurrents',
          icone: SymbolesAgri.event_repeat,
          sousTitre: const Text(
            'Programme médical type par espèce.',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
          bouton: _boutonAjout(
            'Ajouter une Échéance',
            'ajouter-echeance',
            () => _ouvrirEcheance(null),
          ),
          large: large,
        ),
        const SizedBox(height: AgriSpacing.md),
        _blocRappelSoins(d),
        const SizedBox(height: AgriSpacing.md),
        // Sous-onglets d'espèce (`$set('prophySpecies', …)`).
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.md,
            vertical: AgriSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final espece in EspeceProphylaxie.values) ...[
                  InkWell(
                    key: Key('espece-${espece.name}'),
                    onTap: () => setState(() => _espece = espece),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AgriSpacing.sm,
                        vertical: AgriSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: _espece == espece
                            ? AgriColors.brandEmerald
                            : Colors.transparent,
                        border: Border.all(
                          color: _espece == espece
                              ? AgriColors.brandEmerald
                              : AgriColors.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(AgriRadius.full),
                      ),
                      child: Text(
                        espece.libelle,
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          fontWeight: AgriTypography.gras,
                          color: _espece == espece
                              ? Colors.white
                              : AgriColors.outline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.xs),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          largeur: 1100,
          colonnes: const [
            ('Jour / Période', 3, false),
            ('Traitement Prévu', 4, false),
            ('Produit Conseillé', 4, false),
            ('Posologie', 3, false),
            ('Délai Rémanence', 2, true),
            ('Actions', 2, true),
          ],
          vide: 'Aucune échéance pour cette espèce pour le moment.',
          lignes: [
            for (var i = 0; i < lignes.length; i++)
              _ligne(i, 'echeance-${lignes[i].entree.id}', [
                _avecEtat(
                  Text(
                    lignes[i].entree.periodLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.demiGras,
                    ),
                  ),
                  lignes[i].etat,
                  'echeance-${lignes[i].entree.id}',
                ),
                Text(
                  lignes[i].entree.treatment,
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                Text(
                  lignes[i].entree.productRecommended ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                Text(lignes[i].entree.dosage ?? '—', style: _cellule),
                _remanence(lignes[i]),
                _actions(
                  'echeance-${lignes[i].entree.id}',
                  modifier: () => _ouvrirEcheance(lignes[i]),
                  supprimer: () => _confirmerSuppression(
                    libelle: lignes[i].entree.treatment,
                    cle: 'echeance-${lignes[i].entree.id}',
                    archiver: () =>
                        widget.depot.archiverEcheance(lignes[i].entree.id),
                  ),
                ),
              ]),
          ],
        ),
      ],
    );
  }

  /// Délai de rémanence, `{{ $p->withdrawal_days }} j`, rouge et gras au-delà de zéro.
  ///
  /// ⚠️ **ZÉRO JOUR SE DIT, ET N'EST PAS UN TROU** : une vitamine sans délai d'attente autorise la vente le
  /// jour même.
  Widget _remanence(LigneProphylaxie l) => Text(
    '${l.entree.withdrawalDays} j',
    textAlign: TextAlign.right,
    style: TextStyle(
      fontSize: AgriTypography.xs,
      fontWeight: l.entree.withdrawalDays > 0
          ? AgriTypography.gras
          : AgriTypography.normal,
      color: l.entree.withdrawalDays > 0
          ? AgriColors.errorDeep
          : AgriColors.onSurface,
    ),
  );

  /// Règle R-SOINS-01 — formulaire `saveRappelSoins` du Blade (onglet Prophylaxie).
  Widget _blocRappelSoins(DonneesParametresElevage d) {
    final etat = d.etatRappelSoins;
    final champ = SizedBox(
      width: 96,
      child: TextField(
        key: const Key('rappel-soins'),
        controller: _rappel,
        readOnly: !widget.peutModifier,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _decoration(
          // Jamais tiré : le poste ne connaît pas le réglage de la ferme.
          exemple: d.rappelSoinsJours == null ? '—' : null,
        ),
        style: const TextStyle(
          fontSize: AgriTypography.sm,
          fontWeight: AgriTypography.gras,
          color: AgriColors.brandForest,
        ),
      ),
    );
    final texte = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette('Rappel des soins planifiés (jours avant la date)'),
        const Text(
          'La cloche signale un soin « à venir » quand il reste ce nombre de '
          'jours ou moins, puis « en retard » une fois la date dépassée. '
          '0 : le jour même.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        if (etat != null && (etat.enAttente || etat.refuse))
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: _pastilleEtat(etat, 'rappel-soins'),
          ),
      ],
    );
    final bouton = widget.peutModifier
        ? _boutonPilule(
            'Enregistrer',
            'rappel-soins-enregistrer',
            null,
            _enregistrerRappel,
          )
        : null;

    return Container(
      key: const Key('bloc-rappel-soins'),
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `flex-col sm:flex-row sm:items-end`.
          if (AgriBreakpoints.petit(context))
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: texte),
                const SizedBox(width: AgriSpacing.sm),
                champ,
                if (bouton != null) ...[
                  const SizedBox(width: AgriSpacing.sm),
                  bouton,
                ],
              ],
            )
          else ...[
            texte,
            const SizedBox(height: AgriSpacing.sm),
            champ,
            if (bouton != null) ...[
              const SizedBox(height: AgriSpacing.sm),
              Align(alignment: Alignment.centerLeft, child: bouton),
            ],
          ],
          if (_erreurRappel != null)
            _erreur('rappel-soins-erreur', _erreurRappel!),
        ],
      ),
    );
  }

  Future<void> _enregistrerRappel() async {
    final erreurs = ParametresElevageRepository.erreursRappelSoins(
      _rappel.text,
    );
    if (erreurs.isNotEmpty) {
      setState(() => _erreurRappel = erreurs.join(' '));
      return;
    }
    await widget.depot.enregistrerRappelSoins(int.parse(_rappel.text.trim()));
    _erreurRappel = null;
    await _charger(formulaires: true);
    _toast(_rappelEnregistre);
  }

  // ── Onglet 3 : Types de Provende ──────────────────────────────────────────

  Widget _ongletProvende(DonneesParametresElevage d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        titre: 'Catalogue des Types de Provende',
        icone: SymbolesAgri.inventory_2,
        sousTitre: const Text(
          "Gestion des types d'aliments servis en ferme avec conditionnement "
          'et prix indicatif au Kilogramme.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
        bouton: _boutonAjout(
          'Ajouter un Type',
          'ajouter-provende',
          () => _ouvrirProvende(null),
        ),
        large: large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1000,
        colonnes: const [
          ("Nom du Type d'Aliment", 5, false),
          ('Espèce Cible', 3, false),
          ('Poids Sac Standard (Kg)', 3, true),
          ('Prix Indicatif (FCFA/Kg)', 3, true),
          ('Actions', 2, true),
        ],
        vide: 'Aucun type de provende pour le moment.',
        lignes: [
          for (var i = 0; i < d.provendes.length; i++)
            _ligne(i, 'provende-${d.provendes[i].type.id}', [
              _avecEtat(
                Text(
                  d.provendes[i].type.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.demiGras,
                  ),
                ),
                d.provendes[i].etat,
                'provende-${d.provendes[i].type.id}',
              ),
              Text(
                d.provendes[i].type.speciesLabel ?? '—',
                overflow: TextOverflow.ellipsis,
                style: _cellule,
              ),
              Text(
                ParametresElevageRepository.sac(
                  d.provendes[i].type.standardBagWeightKg,
                ),
                textAlign: TextAlign.right,
                style: _cellule,
              ),
              Text(
                ParametresElevageRepository.prix(
                  d.provendes[i].type.pricePerKg,
                ),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.brandEmerald,
                ),
              ),
              _actions(
                'provende-${d.provendes[i].type.id}',
                modifier: () => _ouvrirProvende(d.provendes[i]),
                supprimer: () => _confirmerSuppression(
                  libelle: d.provendes[i].type.name,
                  cle: 'provende-${d.provendes[i].type.id}',
                  archiver: () =>
                      widget.depot.archiverProvende(d.provendes[i].type.id),
                ),
              ),
            ]),
        ],
      ),
    ],
  );

  // ── Onglet 4 : Numérotation Bandes & Sujets ───────────────────────────────

  Widget _ongletNumerotation(DonneesParametresElevage d, bool large) {
    final etat = d.etatNumerotation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          titre: 'Numérotation des Bandes & Sujets Par Espèce',
          icone: SymbolesAgri.tag,
          sousTitre: const Text(
            'Formatage des identifiants générés sur le terrain et préfixes '
            "individuels par catégorie d'animaux.",
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
          large: large,
        ),
        const SizedBox(height: AgriSpacing.md),
        // ⚠️ PROPRE AU POSTE : le web lit toujours sa ligne (`current()`) ; le poste peut n'avoir rien tiré.
        if (d.numerotation == null) ...[
          _mention(
            "Préfixes non synchronisés — aucun tirage n'a encore eu lieu. "
            "Afficher « R » ou « T » par défaut ferait croire à une "
            "convention confirmée alors qu'elle n'a jamais été lue.",
            cle: 'numerotation-non-synchronisee',
          ),
          const SizedBox(height: AgriSpacing.md),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            key: const Key('grille-numerotation'),
            // `max-w-3xl`.
            constraints: const BoxConstraints(maxWidth: 768),
            padding: const EdgeInsets.all(AgriSpacing.lg),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (etat != null && (etat.enAttente || etat.refuse)) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _pastilleEtat(etat, 'numerotation'),
                  ),
                  const SizedBox(height: AgriSpacing.md),
                ],
                _format('bande_format', largeur: 256),
                _groupe('Cuniculture (Lapins)', SymbolesAgri.cruelty_free, [
                  ['lapine_prefix', 'male_prefix'],
                ]),
                _groupe('Porciculture (Porcs)', SymbolesAgri.pets, [
                  ['truie_prefix', 'verrat_prefix', 'portee_prefix'],
                ]),
                _groupe('Aviculture (Volailles & Pondeuses)', SymbolesAgri.egg, [
                  ['volaille_prefix', 'parc_prefix'],
                ]),
                _groupe('Héliciculture (Escargots)', SymbolesAgri.bug_report, [
                  ['escargot_prefix'],
                ], largeurUnique: 256),
                if (_erreurNumerotation != null)
                  _erreur('numerotation-erreur', _erreurNumerotation!),
                if (widget.peutModifier) ...[
                  const SizedBox(height: AgriSpacing.lg),
                  const Divider(height: 1, color: AgriColors.outlineVariant),
                  const SizedBox(height: AgriSpacing.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      key: const Key('numerotation-enregistrer'),
                      onPressed: _enregistrerNumerotation,
                      icon: const Icon(SymbolesAgri.save, size: 18),
                      label: const Text(
                        'Enregistrer Tous les Formats de Numérotation',
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          fontWeight: AgriTypography.gras,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AgriColors.brandEmerald,
                        foregroundColor: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AgriRadius.lg),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AgriSpacing.md,
                          vertical: AgriSpacing.sm,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Les cinq préfixes individuels portent `maxlength="4"` au Blade (lapines, mâles, truies, verrats, portées).
  static const _quatreCaracteres = {
    'lapine_prefix',
    'male_prefix',
    'truie_prefix',
    'verrat_prefix',
    'portee_prefix',
  };

  Widget _format(String cle, {double? largeur}) {
    final champ = TextField(
      key: Key('format-$cle'),
      controller: _formats[cle],
      readOnly: !widget.peutModifier,
      inputFormatters: [
        if (_quatreCaracteres.contains(cle))
          LengthLimitingTextInputFormatter(4),
      ],
      decoration: _decoration(),
      style: TextStyle(
        fontSize: AgriTypography.sm,
        fontWeight: AgriTypography.gras,
        fontFamily: cle == 'bande_format' ? null : 'monospace',
        color: cle == 'bande_format'
            ? AgriColors.brandForest
            : (cle == 'lapine_prefix' || cle == 'truie_prefix'
                  ? AgriColors.brandEmerald
                  : AgriColors.onSurface),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiquette(_libellesNumerotation[cle]!),
        largeur == null ? champ : SizedBox(width: largeur, child: champ),
      ],
    );
  }

  /// Un groupe d'espèce : `border-t pt-md`, intitulé `text-xs font-bold text-brand-emerald uppercase`.
  Widget _groupe(
    String titre,
    IconData icone,
    List<List<String>> rangees, {
    double? largeurUnique,
  }) => Container(
    margin: const EdgeInsets.only(top: AgriSpacing.lg),
    padding: const EdgeInsets.only(top: AgriSpacing.md),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icone, size: 18, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              titre.toUpperCase(),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: AgriTypography.gras,
                letterSpacing: 0.8,
                color: AgriColors.brandEmerald,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.sm),
        for (final rangee in rangees)
          if (rangee.length == 1)
            _format(rangee.single, largeur: largeurUnique)
          else if (AgriBreakpoints.petit(context))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rangee.length; i++) ...[
                  if (i > 0) const SizedBox(width: AgriSpacing.md),
                  Expanded(child: _format(rangee[i])),
                ],
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rangee.length; i++) ...[
                  if (i > 0) const SizedBox(height: AgriSpacing.md),
                  _format(rangee[i]),
                ],
              ],
            ),
      ],
    ),
  );

  Future<void> _enregistrerNumerotation() async {
    final formats = {
      for (final MapEntry(key: cle, value: c) in _formats.entries) cle: c.text,
    };
    final erreurs = ParametresElevageRepository.erreursNumerotation(
      formats,
      _libellesNumerotation,
    );
    if (erreurs.isNotEmpty) {
      setState(() => _erreurNumerotation = erreurs.join(' '));
      return;
    }
    await widget.depot.enregistrerNumerotation(formats);
    _erreurNumerotation = null;
    await _charger(formulaires: true);
    _toast(_numerotationEnregistree);
  }

  // ── Modales de saisie ─────────────────────────────────────────────────────

  /// `modal-ration` : « Saisir une Ration » / « Modifier la Ration » (`newRation()` / `editRation()`).
  Future<void> _ouvrirRation(LigneRation? existante) async {
    final r = existante?.ration;
    var espece = r?.speciesCode ?? 'aviculture';
    _stade.text = r?.stageLabel ?? '';
    _grammes.text = r == null ? '' : r.rationGPerDay.round().toString();
    String? erreur;

    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: r == null ? 'Saisir une Ration' : 'Modifier la Ration',
          largeur: LargeurModale.sm,
          contenu: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _etiquette('Espèce *'),
              _liste(
                cle: 'ration-espece',
                valeur: espece,
                options: ParametresElevageRepository.especesRation,
                selection: false,
                surChangement: (v) => rafraichir(() => espece = v ?? espece),
              ),
              const SizedBox(height: AgriSpacing.md),
              _champ(
                "Stade Physiologique / Tranche d'Âge *",
                _stade,
                'ration-stade',
                exemple: 'ex : Poussin ponte (0 à 2 mois)',
              ),
              _champ(
                'Ration Normative (g/tête/jour) *',
                _grammes,
                'ration-grammes',
                exemple: 'ex : 30',
                numerique: true,
                couleur: AgriColors.brandEmerald,
              ),
              if (erreur != null) _erreur('ration-erreur', erreur!),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BoutonModalePrimaire(
              key: const Key('ration-enregistrer'),
              libelle: 'Enregistrer',
              onPressed: () async {
                final erreurs = ParametresElevageRepository.erreursRation(
                  espece: espece,
                  stade: _stade.text,
                  grammes: _grammes.text,
                );
                if (erreurs.isNotEmpty) {
                  rafraichir(() => erreur = erreurs.join(' '));
                  return;
                }
                await widget.depot.enregistrerRation(
                  id: r?.id,
                  espece: espece,
                  stade: _stade.text,
                  grammes: int.parse(_grammes.text.trim()),
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
      _toast(_rationEnregistree);
    }
  }

  /// `modal-prophylaxie` : « Échéance de Prophylaxie » / « Modifier l'Échéance ». L'espèce est celle du
  /// sous-onglet ouvert (`$this->prophySpecies`), comme au web.
  Future<void> _ouvrirEcheance(LigneProphylaxie? existante) async {
    final e = existante?.entree;
    _periode.text = e?.periodLabel ?? '';
    _traitement.text = e?.treatment ?? '';
    _produit.text = e?.productRecommended ?? '';
    _dose.text = e?.dosage ?? '';
    // `public int $prophy_withdrawal_days = 0;`
    _delaiRemanence.text = (e?.withdrawalDays ?? 0).toString();
    String? erreur;

    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: e == null ? 'Échéance de Prophylaxie' : "Modifier l'Échéance",
          largeur: LargeurModale.sm,
          contenu: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _champ(
                'Jour / Âge *',
                _periode,
                'echeance-periode',
                exemple: 'ex : Le 1er du mois OU J+14',
              ),
              _champ(
                'Traitement Prévu *',
                _traitement,
                'echeance-traitement',
                exemple: 'ex : Vaccination Newcastle',
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _champ(
                      'Produit Conseillé *',
                      _produit,
                      'echeance-produit',
                      exemple: 'ex : Superhypracox',
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(
                    child: _champ(
                      'Dose *',
                      _dose,
                      'echeance-dose',
                      exemple: "ex : 1C / 5L d'eau",
                    ),
                  ),
                ],
              ),
              _champ(
                "Délai de Rémanence (Jours d'attente)",
                _delaiRemanence,
                'echeance-remanence',
                numerique: true,
                couleur: AgriColors.errorDeep,
              ),
              if (erreur != null) _erreur('echeance-erreur', erreur!),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BoutonModalePrimaire(
              key: const Key('echeance-enregistrer'),
              libelle: 'Enregistrer',
              onPressed: () async {
                final erreurs = ParametresElevageRepository.erreursEcheance(
                  periode: _periode.text,
                  traitement: _traitement.text,
                  produit: _produit.text,
                  dose: _dose.text,
                  remanence: _delaiRemanence.text,
                );
                if (erreurs.isNotEmpty) {
                  rafraichir(() => erreur = erreurs.join(' '));
                  return;
                }
                await widget.depot.enregistrerEcheance(
                  id: e?.id,
                  espece: _espece.code,
                  periode: _periode.text,
                  traitement: _traitement.text,
                  produit: _produit.text,
                  dose: _dose.text,
                  remanence: int.parse(_delaiRemanence.text.trim()),
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
      _toast(_echeanceEnregistree);
    }
  }

  /// `modal-provende` : « Type de Provende » / « Modifier le Type de Provende ». Nouveau type : sac 25 kg,
  /// prix 250 FCFA/kg (`newProvende()`).
  Future<void> _ouvrirProvende(LigneProvende? existante) async {
    final t = existante?.type;
    final especes = _donnees?.especesProvende ?? const <OptionEspece>[];
    String? espece = t?.speciesId;
    if (espece != null && !especes.any((o) => o.id == espece)) espece = null;
    _nom.text = t?.name ?? '';
    _sac.text = t == null
        ? '25'
        : ParametresElevageRepository.saisie(t.standardBagWeightKg);
    _prix.text = t == null
        ? '250'
        : ParametresElevageRepository.saisie(t.pricePerKg);
    String? erreur;

    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: t == null
              ? 'Type de Provende'
              : 'Modifier le Type de Provende',
          largeur: LargeurModale.sm,
          contenu: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _champ(
                "Nom du Type d'Aliment *",
                _nom,
                'provende-nom',
                exemple: 'ex : Aliment Ponte',
              ),
              _etiquette('Espèce Cible *'),
              _liste(
                cle: 'provende-espece',
                valeur: espece,
                options: [for (final o in especes) (o.id, o.libelle)],
                surChangement: (v) => rafraichir(() => espece = v),
              ),
              const SizedBox(height: AgriSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _champ(
                      'Poids Sac Standard (Kg) *',
                      _sac,
                      'provende-sac',
                      decimal: true,
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.sm),
                  Expanded(
                    child: _champ(
                      'Prix Indicatif (FCFA/Kg) *',
                      _prix,
                      'provende-prix',
                      decimal: true,
                      couleur: AgriColors.brandEmerald,
                    ),
                  ),
                ],
              ),
              if (erreur != null) _erreur('provende-erreur', erreur!),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BoutonModalePrimaire(
              key: const Key('provende-enregistrer'),
              libelle: 'Enregistrer',
              onPressed: () async {
                final erreurs = ParametresElevageRepository.erreursProvende(
                  nom: _nom.text,
                  especeId: espece,
                  especes: especes,
                  sac: _sac.text,
                  prix: _prix.text,
                );
                if (erreurs.isNotEmpty) {
                  rafraichir(() => erreur = erreurs.join(' '));
                  return;
                }
                await widget.depot.enregistrerProvende(
                  id: t?.id,
                  nom: _nom.text,
                  espece: especes.firstWhere((o) => o.id == espece),
                  sacKg: double.parse(_sac.text.trim().replaceAll(',', '.')),
                  prixKg: double.parse(_prix.text.trim().replaceAll(',', '.')),
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
      _toast(_provendeEnregistree);
    }
  }

  /// `x-modal-confirm-permanent-delete` du Blade. ⚠️ Le libellé dit « Supprimer définitivement » (celui du
  /// web) mais l'effet est l'ARCHIVAGE (`deleteRation()` & co., ticket 14.55), comme au web.
  Future<void> _confirmerSuppression({
    required String libelle,
    required String cle,
    required Future<void> Function() archiver,
  }) async {
    final confirme = await afficherModale<bool>(
      context: context,
      confirmation: true,
      constructeur: (context) => ModaleConfirmation(
        key: Key('confirmer-suppression-$cle'),
        icone: SymbolesAgri.warning,
        couleurIcone: AgriColors.errorDeep,
        titre: 'Confirmer la Suppression ?',
        message: 'Vous êtes sur le point de supprimer le paramètre $libelle.',
        detail: Container(
          padding: const EdgeInsets.all(AgriSpacing.sm),
          decoration: BoxDecoration(
            color: AgriColors.errorBg.withValues(alpha: 0.5),
            border: Border.all(
              color: AgriColors.errorDeep.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(SymbolesAgri.info, size: 16, color: AgriColors.errorDeep),
              SizedBox(width: AgriSpacing.xs),
              Expanded(
                child: Text(
                  "Attention : Cette action est irréversible et retirera ce "
                  "paramètre du calcul automatique des fiches d'élevage.",
                  style: TextStyle(fontSize: 11, color: AgriColors.errorDeep),
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
          ElevatedButton(
            key: Key('supprimer-confirme-$cle'),
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.errorDeep,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
            ),
            child: const Text(
              'Oui, Supprimer définitivement',
              style: TextStyle(
                fontSize: AgriTypography.sm,
                fontWeight: AgriTypography.gras,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirme == true) {
      await archiver();
      await _charger();
      _toast(_parametreArchive, type: TypeToast.avertissement);
    }
  }

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  /// En-tête d'onglet : `flex-col lg:flex-row lg:justify-between`, titre `text-lg lg:text-xl font-bold`.
  Widget _entete({
    required String titre,
    required IconData icone,
    required Widget sousTitre,
    required bool large,
    Widget? bouton,
  }) {
    final textes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icone, size: 24, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Flexible(
              child: Text(
                titre,
                style: TextStyle(
                  fontSize: large ? AgriTypography.xl : AgriTypography.lg,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        sousTitre,
      ],
    );
    final action = widget.peutModifier ? bouton : null;
    if (action == null) return textes;

    return large
        ? Row(
            children: [
              Expanded(child: textes),
              const SizedBox(width: AgriSpacing.sm),
              action,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textes,
              const SizedBox(height: AgriSpacing.sm),
              action,
            ],
          );
  }

  /// Bouton « + Ajouter … » : `bg-brand-emerald text-white font-bold text-xs rounded-full`, icône `add_circle`.
  Widget _boutonAjout(String libelle, String cle, VoidCallback surAppui) =>
      _boutonPilule(libelle, cle, SymbolesAgri.add_circle, surAppui);

  Widget _boutonPilule(
    String libelle,
    String cle,
    IconData? icone,
    VoidCallback surAppui,
  ) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: AgriColors.brandEmerald,
      foregroundColor: Colors.white,
      elevation: 1,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
    );
    final texte = Text(
      libelle,
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        fontWeight: AgriTypography.gras,
      ),
    );
    return icone == null
        ? ElevatedButton(
            key: Key(cle),
            onPressed: surAppui,
            style: style,
            child: texte,
          )
        : ElevatedButton.icon(
            key: Key(cle),
            onPressed: surAppui,
            style: style,
            icon: Icon(icone, size: 18),
            label: texte,
          );
  }

  /// Colonnes : (libellé du Blade, flex, alignée à droite `text-right`). En-tête `text-[10px] uppercase`.
  Widget _tableau({
    required double largeur,
    required List<(String, int, bool)> colonnes,
    required List<(String, List<Widget>)> lignes,
    String? vide,
  }) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (_, contraintes) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(largeur, contraintes.maxWidth),
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
                    for (final (libelle, flex, droite) in colonnes)
                      Expanded(
                        flex: flex,
                        child: Text(
                          libelle.toUpperCase(),
                          textAlign: droite ? TextAlign.right : TextAlign.left,
                          style: _enteteColonne,
                        ),
                      ),
                  ],
                ),
              ),
            if (lignes.isEmpty && vide != null)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Center(
                  child: Text(
                    vide,
                    key: const Key('tableau-vide'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
              ),
            for (var i = 0; i < lignes.length; i++)
              _rangee(i, colonnes, lignes[i].$1, lignes[i].$2),
          ],
        ),
      ),
    ),
    ),
  );

  /// Une ligne : (clé, cellules dans l'ordre des colonnes).
  (String, List<Widget>) _ligne(int index, String cle, List<Widget> cellules) =>
      (cle, cellules);

  /// Une ligne du tableau, zébrée comme le Blade (`$i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white'`), cellules
  /// réparties selon les colonnes (flex, alignement `text-right`).
  Widget _rangee(
    int index,
    List<(String, int, bool)> colonnes,
    String cle,
    List<Widget> cellules,
  ) => Container(
    key: Key('ligne-$cle'),
    decoration: BoxDecoration(
      color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
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
        for (var i = 0; i < colonnes.length; i++)
          Expanded(
            flex: colonnes[i].$2,
            child: Align(
              alignment: colonnes[i].$3
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: cellules[i],
            ),
          ),
      ],
    ),
  );

  /// Les deux boutons d'action du Blade : « Modifier » (`edit`, bleu) puis « Supprimer » (`delete`, rouge).
  /// ⚠️ Masqués sans le droit `manage-elevage` : la colonne reste, comme l'ordre des colonnes du Blade.
  Widget _actions(
    String cle, {
    required VoidCallback modifier,
    required VoidCallback supprimer,
  }) {
    if (!widget.peutModifier) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          key: Key('modifier-$cle'),
          tooltip: 'Modifier',
          onPressed: modifier,
          icon: const Icon(SymbolesAgri.edit, size: 18, color: AgriColors.infoBlue),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          key: Key('supprimer-$cle'),
          tooltip: 'Supprimer',
          onPressed: supprimer,
          icon: const Icon(SymbolesAgri.delete, size: 18, color: AgriColors.errorDeep),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  /// Première cellule et, sous elle, l'état d'envoi s'il n'est pas `synced` (➕ ajout du poste).
  Widget _avecEtat(Widget contenu, EtatEnvoi etat, String cle) {
    if (!etat.enAttente && !etat.refuse) return contenu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        contenu,
        const SizedBox(height: AgriSpacing.xs),
        _pastilleEtat(etat, cle),
      ],
    );
  }

  /// « En attente d'envoi » (jaune) ou « Refusé par le serveur » (rouge) suivi du motif mot pour mot.
  Widget _pastilleEtat(EtatEnvoi etat, String cle) {
    final refuse = etat.refuse;
    return Column(
      key: Key('etat-$cle'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: refuse
                ? AgriColors.errorBg
                : AgriColors.accentYellow.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AgriRadius.full),
          ),
          child: Text(
            refuse ? 'Refusé par le serveur' : "En attente d'envoi",
            style: TextStyle(
              fontSize: 11,
              fontWeight: AgriTypography.gras,
              color: refuse ? AgriColors.errorDeep : AgriColors.brandForest,
            ),
          ),
        ),
        if (refuse)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              etat.motifRefus ?? 'Refus sans motif communiqué.',
              key: Key('motif-$cle'),
              style: const TextStyle(fontSize: 11, color: AgriColors.errorDeep),
            ),
          ),
      ],
    );
  }

  Widget _etiquette(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
    child: Text(
      texte.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: AgriTypography.gras,
        color: AgriColors.brandForest,
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

  Widget _champ(
    String libelle,
    TextEditingController controleur,
    String cle, {
    String? exemple,
    bool numerique = false,
    bool decimal = false,
    Color? couleur,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _etiquette(libelle),
        TextField(
          key: Key(cle),
          controller: controleur,
          keyboardType: numerique || decimal
              ? TextInputType.numberWithOptions(decimal: decimal)
              : TextInputType.text,
          inputFormatters: [
            if (numerique) FilteringTextInputFormatter.digitsOnly,
            if (decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: _decoration(exemple: exemple),
          style: TextStyle(
            fontSize: AgriTypography.sm,
            fontWeight: couleur == null
                ? AgriTypography.normal
                : AgriTypography.gras,
            color: couleur ?? AgriColors.onSurface,
          ),
        ),
      ],
    ),
  );

  /// `<select>` du Blade. [selection] : ouvert sur `<option value="">-- Sélectionner --</option>`.
  Widget _liste({
    required String cle,
    required String? valeur,
    required List<(String, String)> options,
    required ValueChanged<String?> surChangement,
    bool selection = true,
  }) => DropdownButtonFormField<String>(
    key: Key(cle),
    initialValue: valeur,
    isExpanded: true,
    decoration: _decoration(),
    hint: selection
        ? const Text(
            _selectionner,
            style: TextStyle(fontSize: AgriTypography.sm),
          )
        : null,
    items: [
      for (final (id, libelle) in options)
        DropdownMenuItem(
          value: id,
          child: Text(
            libelle,
            style: const TextStyle(fontSize: AgriTypography.sm),
          ),
        ),
    ],
    onChanged: surChangement,
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

  Widget _mention(String texte, {required String cle}) => Container(
    key: Key(cle),
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
            texte,
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
