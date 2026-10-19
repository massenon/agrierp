import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import 'parametres_elevage_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/parametres-elevage.html` → Paramètres Élevage.
///
/// ⚠️⚠️ **QUATRE ONGLETS EN LECTURE SEULE.** Rations, calendriers de
/// prophylaxie, types de provende et préfixes de numérotation sont des
/// référentiels du serveur : il ignore tout envoi les concernant et le compte
/// dans `referentiels_ignored`. Une ration corrigée ici disparaîtrait au
/// tirage suivant sans un mot. Les boutons « Ajouter », « Modifier »,
/// « Supprimer » et « Exporter PDF » de la maquette (l.115-121, l.150-155,
/// l.190-196) ne sont donc pas portés — le motif est affiché à l'écran.
///
/// ⚠️ **CET ÉCRAN NE CRÉE RIEN : IL MONTRE CE QUE LE POSTE APPLIQUE DÉJÀ.**
/// Les rations pilotent la provende du Dashboard Élevage, le calendrier
/// alimente les traitements prévus de Soins et Vaccins. Jusqu'ici, l'éleveur
/// voyait les conséquences sans pouvoir consulter la règle.
class ParametresElevageScreen extends StatefulWidget {
  const ParametresElevageScreen({super.key, required this.depot});

  final ParametresElevageRepository depot;

  @override
  State<ParametresElevageScreen> createState() =>
      _ParametresElevageScreenState();
}

class _ParametresElevageScreenState extends State<ParametresElevageScreen> {
  /// Les quatre onglets, dans l'ordre de la maquette (l.93-105).
  static const onglets = <(String, IconData)>[
    ('Fiche de Rationnement (g/j)', SymbolesAgri.restaurant),
    ('Calendriers de Prophylaxie', SymbolesAgri.event_repeat),
    ('Types de Provende', SymbolesAgri.inventory_2),
    ('Numérotation Bandes & Sujets', SymbolesAgri.tag),
  ];

  String _onglet = onglets.first.$1;
  EspeceProphylaxie _espece = EspeceProphylaxie.lapins;

  DonneesParametresElevage? _donnees;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
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
              key: Key('onglet-parametres-$titre'),
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
        'Fiche de Rationnement des Animaux',
        SymbolesAgri.restaurant,
        'Consommation journalière théorique par tête exprimée en '
            'Grammes (g/j).',
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 900,
        colonnes: const [
          ('Espèce', 3),
          ("Stade Physiologique / Tranche d'Âge", 5),
          ('Ration Normative (g / tête / jour)', 4),
          ('Actions', 2),
        ],
        vide: '— Aucune ration synchronisée —',
        lignes: [
          for (var i = 0; i < d.rations.length; i++)
            _ligne(i, [
              (Text(d.rations[i].especeLisible, style: _cellule), 3),
              (
                Text(
                  d.rations[i].ration.stageLabel,
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                5,
              ),
              (
                Text(
                  _grammes(d.rations[i].ration.rationGPerDay),
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandForest,
                  ),
                ),
                4,
              ),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      _mentionReferentiel(
        'Les rations se corrigent depuis la surface web. Le serveur refuse '
        "toute modification venue d'un poste : elle disparaîtrait au tirage "
        'suivant, sans un mot.',
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
          'Calendriers de Prophylaxie & Traitements Récurrents',
          SymbolesAgri.event_repeat,
          'Programme médical type par espèce. Alimente "Traitements Prévus" '
              'et les alertes du Dashboard.',
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        // Sous-onglets d'espèce — maquette l.159-164.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AgriSpacing.md,
            vertical: 8,
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
                        vertical: 4,
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
                        borderRadius: BorderRadius.circular(999),
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
            ('Jour / Période', 3),
            ('Traitement Prévu', 4),
            ('Produit Conseillé', 4),
            ('Posologie', 3),
            ('Délai Rémanence', 3),
            ('Actions', 2),
          ],
          vide: '— Aucune échéance pour cette espèce —',
          lignes: [
            for (var i = 0; i < lignes.length; i++)
              _ligne(i, [
                (
                  Text(
                    lignes[i].entree.periodLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                    ),
                  ),
                  3,
                ),
                (
                  Text(
                    lignes[i].entree.treatment,
                    overflow: TextOverflow.ellipsis,
                    style: _cellule,
                  ),
                  4,
                ),
                (
                  Text(
                    lignes[i].entree.productRecommended ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: _cellule,
                  ),
                  4,
                ),
                (Text(lignes[i].entree.dosage ?? '—', style: _cellule), 3),
                (_remanence(lignes[i]), 3),
                (_actionInerte(), 2),
              ]),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _mentionReferentiel(
          'Le protocole se modifie depuis la surface web. Sur un sujet '
          'sanitaire, deux protocoles divergents seraient pires que pas de '
          'protocole du tout.',
        ),
      ],
    );
  }

  /// Délai de rémanence, en jours.
  ///
  /// ⚠️ **ZÉRO JOUR SE DIT, ET N'EST PAS UN TROU** : une vitamine sans délai
  /// d'attente autorise la vente le jour même. Le confondre avec l'absence
  /// d'information ferait hésiter l'éleveur sur une bande vendable.
  Widget _remanence(LigneProphylaxie l) => Text(
    '${l.entree.withdrawalDays} j',
    style: TextStyle(
      fontSize: AgriTypography.xs,
      fontWeight: l.entree.withdrawalDays > 0
          ? AgriTypography.gras
          : AgriTypography.normal,
      color: l.entree.withdrawalDays > 0
          ? AgriColors.errorDeep
          : AgriColors.outline,
    ),
  );

  // ── Onglet 3 : Types de Provende ──────────────────────────────────────────

  Widget _ongletProvende(DonneesParametresElevage d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        'Catalogue des Types de Provende',
        SymbolesAgri.inventory_2,
        "Gestion des types d'aliments servis en ferme avec conditionnement "
            'et prix indicatif au Kilogramme.',
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 1000,
        colonnes: const [
          ("Nom du Type d'Aliment", 5),
          ('Espèce Cible', 3),
          ('Poids Sac Standard (Kg)', 3),
          ('Prix Indicatif (FCFA / Kg)', 3),
          ('Actions', 2),
        ],
        vide: '— Aucun type de provende synchronisé —',
        lignes: [
          for (var i = 0; i < d.provendes.length; i++)
            _ligne(i, [
              (
                Text(
                  d.provendes[i].type.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                5,
              ),
              (
                Text(
                  d.provendes[i].type.speciesLabel ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              (
                Text(
                  _nombre(d.provendes[i].type.standardBagWeightKg),
                  style: _cellule,
                ),
                3,
              ),
              (
                Text(_nombre(d.provendes[i].type.pricePerKg), style: _cellule),
                3,
              ),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ LE POIDS DU SAC EST ICI, ET IL MANQUE AILLEURS. L'autonomie
      // alimentaire du Dashboard Élevage porte un tiret faute de savoir ce que
      // pèse un sac : la donnée existe donc — 25 kg — mais RIEN NE RELIE ce
      // type d'aliment au produit stocké. « Aliment Ponte (Pondeuse) » et
      // « Aliment ponte 25kg » sont deux lignes de deux tables, sans clé
      // commune. Les rapprocher sur la ressemblance des noms serait inventer
      // une donnée de gestion.
      _mentionReferentiel(
        "Le poids du sac vit ici, mais aucun lien n'existe entre un type "
        "d'aliment et le produit correspondant au stock : l'autonomie "
        'alimentaire du Dashboard Élevage reste donc un tiret. Arbitrage '
        'client : relier les deux tables.',
      ),
    ],
  );

  // ── Onglet 4 : Numérotation Bandes & Sujets ───────────────────────────────

  Widget _ongletNumerotation(DonneesParametresElevage d, bool large) {
    final n = d.numerotation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          'Numérotation des Bandes & Sujets Par Espèce',
          SymbolesAgri.tag,
          'Formatage des identifiants générés sur le terrain (ex: BANDE B1, '
              "BANDE B2...) et préfixes individuels par catégorie d'animaux.",
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        if (n == null)
          _mentionReferentiel(
            "Préfixes non synchronisés — aucun tirage n'a encore eu lieu. "
            "Afficher « R » ou « T » par défaut ferait croire à une "
            "convention confirmée alors qu'elle n'a jamais été lue.",
            cle: 'numerotation-non-synchronisee',
          )
        else
          Container(
            key: const Key('grille-numerotation'),
            padding: const EdgeInsets.all(AgriSpacing.lg),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _prefixe(
                  "Format d'Affichage du Nom de Bande (Terrain / Toutes Espèces)",
                  n.bandeFormat,
                  apercu: _serie(n.bandeFormat, ['1', '2', '3']),
                ),
                _groupe('Cuniculture (Lapins)', SymbolesAgri.cruelty_free, [
                  _prefixe(
                    'Lapines Reproductrices (R1..Rn)',
                    n.lapinePrefix,
                    apercu: _serie(n.lapinePrefix, ['1', '2', '3']),
                  ),
                  _prefixe(
                    'Mâles Saillisseurs (M1..Mn)',
                    n.malePrefix,
                    apercu: _serie(n.malePrefix, ['1', '2', '3']),
                  ),
                ]),
                _groupe('Porciculture (Porcs)', SymbolesAgri.pets, [
                  _prefixe(
                    'Truies Reproductrices (T1..Tn)',
                    n.truiePrefix,
                    apercu: _serie(n.truiePrefix, ['1', '2', '3']),
                  ),
                  _prefixe(
                    'Verrats Reproducteurs (V1..Vn)',
                    n.verratPrefix,
                    apercu: _serie(n.verratPrefix, ['1', '2', '3']),
                  ),
                  _prefixe(
                    'Portées de Porcelets',
                    n.porteePrefix,
                    apercu: _serie(n.porteePrefix, ['1', '2', '3']),
                  ),
                ]),
                _groupe('Aviculture (Volailles & Pondeuses)', SymbolesAgri.egg, [
                  _prefixe(
                    'Préfixe Lots Volailles / Pondeuses',
                    n.volaillePrefix,
                    apercu: _serie(n.volaillePrefix, ['-1', '-2']),
                  ),
                  _prefixe(
                    'Préfixe Bâtiments / Parcs Volailles',
                    n.parcPrefix,
                    apercu: _serie(n.parcPrefix, ['A', 'B'], separateur: ' '),
                  ),
                ]),
                _groupe('Héliciculture (Escargots)', SymbolesAgri.bug_report, [
                  _prefixe(
                    'Préfixe Parcs / Fosses Escargots',
                    n.escargotPrefix,
                    apercu: _serie(n.escargotPrefix, [
                      'F1',
                      'F2',
                    ], separateur: ' '),
                  ),
                ]),
              ],
            ),
          ),
        const SizedBox(height: AgriSpacing.md),
        _mentionReferentiel(
          'Ces préfixes nomment les animaux sur le terrain : les changer '
          'depuis un poste ferait diverger deux registres de la même ferme. '
          'La modification se fait sur la surface web.',
        ),
      ],
    );
  }

  /// Un préfixe et son aperçu — la maquette montre la série engendrée
  /// (« R1, R2, R3... »), pas seulement la valeur.
  Widget _prefixe(String libelle, String? valeur, {required String apercu}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AgriSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              libelle.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: AgriTypography.gras,
                color: AgriColors.brandForest,
              ),
            ),
            const SizedBox(height: AgriSpacing.xs),
            Container(
              width: 260,
              height: 44,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
              decoration: BoxDecoration(
                color: AgriColors.surfaceZebra,
                border: Border.all(color: AgriColors.outlineVariant),
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
              child: Text(
                valeur ?? '—',
                style: const TextStyle(
                  fontSize: AgriTypography.sm,
                  fontWeight: AgriTypography.gras,
                  fontFamily: 'monospace',
                  color: AgriColors.brandEmerald,
                ),
              ),
            ),
            const SizedBox(height: AgriSpacing.xs),
            Text(
              'Aperçu : $apercu',
              style: const TextStyle(fontSize: 10, color: AgriColors.outline),
            ),
          ],
        ),
      );

  Widget _groupe(String titre, IconData icone, List<Widget> enfants) => Padding(
    padding: const EdgeInsets.only(top: AgriSpacing.sm),
    child: Container(
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
                  color: AgriColors.brandEmerald,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          ...enfants,
        ],
      ),
    ),
  );

  /// La série engendrée par un préfixe — « R » → « R1, R2, R3... ».
  ///
  /// ⚠️ **L'ESPACE N'EST PAS UNE RÈGLE GÉNÉRALE, IL EST DANS LA MAQUETTE.**
  /// Elle écrit « R1 » et « BANDE B1 » sans espace, « PARC A » et « FOSSE F1 »
  /// avec. Déduire le séparateur du préfixe donnerait « FOSSEF1 » — un
  /// identifiant que personne n'écrit sur une cage.
  static String _serie(
    String? prefixe,
    List<String> suites, {
    String separateur = '',
  }) {
    if (prefixe == null || prefixe.isEmpty) return '—';

    return '${suites.map((s) => '$prefixe$separateur$s').join(', ')}...';
  }

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  Widget _entete(String titre, IconData icone, String sousTitre, bool large) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 24, color: AgriColors.brandEmerald),
              const SizedBox(width: AgriSpacing.xs),
              Expanded(
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
          Text(
            sousTitre,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
        ],
      );

  Widget _tableau({
    required double largeur,
    required List<(String, int)> colonnes,
    required List<Widget> lignes,
    required String vide,
  }) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: largeur,
        child: Column(
          children: [
            Container(
              color: AgriColors.surfaceZebra,
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              child: Row(
                children: [
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(libelle.toUpperCase(), style: _enteteColonne),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  vide,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            ...lignes,
          ],
        ),
      ),
    ),
  );

  Widget _ligne(int index, List<(Widget, int)> cellules) => Container(
    key: Key('ligne-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        for (final (contenu, flex) in cellules)
          Expanded(flex: flex, child: contenu),
      ],
    ),
  );

  /// ⚠️ Les actions de la maquette — modifier, supprimer, exporter — touchent
  /// un référentiel du serveur. La colonne reste, l'action est inerte.
  Widget _actionInerte() => const Opacity(
    opacity: 0.4,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Icon(SymbolesAgri.visibility, size: 16, color: AgriColors.outline),
    ),
  );

  /// ⚠️ LA CLÉ EST PARAMÉTRABLE, ET CE N'EST PAS COSMÉTIQUE. L'onglet
  /// Numérotation affiche DEUX mentions quand rien n'a été tiré — l'absence de
  /// préfixes, puis la règle de lecture seule. Deux widgets de même clé dans
  /// une même `Column` lèvent « Duplicate keys found » et l'écran ne se peint
  /// plus du tout.
  Widget _mentionReferentiel(
    String texte, {
    String cle = 'mention-referentiel',
  }) => Container(
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

  /// Grammes par tête et par jour — la maquette n'affiche pas de décimale
  /// quand la ration est ronde.
  static String _grammes(double valeur) =>
      valeur == valeur.roundToDouble() ? '${valeur.round()} g' : '$valeur g';

  static String _nombre(double? valeur) {
    if (valeur == null) return '—';
    return valeur == valeur.roundToDouble()
        ? valeur.round().toString()
        : valeur.toString();
  }
}
