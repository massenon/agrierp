import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'ajouter_produit_screen.dart';
import 'produits_repository.dart';
import 'stocks_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/catalogue-produits.html` → Catalogue Produits.
///
/// ⚠️⚠️ **HUB À DEUX ONGLETS** : « Voir le Catalogue » (`catalogue-view.html`)
/// et « Seuils d'Alerte » (`seuils-alerte.html`), chargés en `<iframe>` par le
/// hub. La barre latérale ne porte qu'une entrée.
///
/// ⚠️⚠️ **LE CATALOGUE EST EN LECTURE SEULE, SAUF LA CRÉATION ET LA MODIFICATION
/// D'UN PRODUIT (ticket F0.67, enregistrées localement puis synchronisées).**
/// `products` s'écrit au poste depuis 15.15 / F0.67 (création, modification par `ProduitsRepository`) ;
/// `product_categories` reste un **référentiel** du serveur (`referentiels_ignored`). L'archivage d'un produit
/// et la modification d'un seuil DANS CET ONGLET ne sont pas encore portés (tickets ST-1 / ST-2 de
/// `docs/INVENTAIRE_LECTURE_SEULE_POSTE.md`) : ces boutons de la maquette sont présents et inertes, avec leur raison.
///
/// ⚠️ **CE N'EST PAS LE MÊME DÉPÔT QU'UN SECOND LECTEUR** : l'écran réutilise
/// `StocksRepository`, déjà lecteur de ces deux tables (ticket F0.38). Deux
/// lectures parallèles des mêmes tables finiraient par diverger — le projet en
/// a déjà fait les frais avec le GMQ.
class CatalogueProduitsScreen extends StatefulWidget {
  const CatalogueProduitsScreen({
    super.key,
    required this.depot,
    this.produits,
    this.ongletInitial,
    this.produitAModifier,
  });

  final StocksRepository depot;

  /// Ticket U10 — onglet ouvert à l'arrivée : « Seuils d'Alerte » depuis le lien « Configurer les Seuils
  /// d'Alerte » de Gestion des Stocks (`route('stocks.seuils')` au web). `null` : « Voir le Catalogue ».
  final String? ongletInitial;

  /// Ticket U10 — produit dont l'édition s'ouvre à l'arrivée : l'icône Modifier de Gestion des Stocks
  /// (`route('stocks.produits.modifier', $id)`). Comme au web, l'enregistrement ou l'annulation ramène au
  /// catalogue (`redirect('/catalogue-produits')`).
  final String? produitAModifier;

  /// Création / modification d'un produit (ticket F0.67). `null` : catalogue en
  /// consultation seule, boutons inertes (poste sans session ni dépôt).
  final ProduitsRepository? produits;

  @override
  State<CatalogueProduitsScreen> createState() =>
      _CatalogueProduitsScreenState();
}

class _CatalogueProduitsScreenState extends State<CatalogueProduitsScreen> {
  /// Les deux onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Voir le Catalogue', SymbolesAgri.category),
    ("Seuils d'Alerte", SymbolesAgri.notifications_active),
  ];

  late String _onglet = onglets.any((o) => o.$1 == widget.ongletInitial)
      ? widget.ongletInitial!
      : onglets.first.$1;
  String _categorie = 'Tous';
  String _recherche = '';
  String _statut = '';

  /// Bascule grille / liste de la maquette.
  bool _grille = true;

  DonneesStocks? _donnees;

  /// Sous-page « Ajouter / Modifier un Produit » ouverte : `''` création, sinon l'id.
  late String? _formulaire = widget.produitAModifier;

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

    if (_formulaire != null && widget.produits != null) {
      return Scaffold(
        backgroundColor: AgriColors.surfaceBg,
        body: AjouterProduitScreen(
          depot: widget.produits!,
          produitId: _formulaire!.isEmpty ? null : _formulaire,
          onTermine: ({required bool enregistre}) {
            setState(() => _formulaire = null);
            if (enregistre) _charger();
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
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
                      if (_onglet == "Seuils d'Alerte")
                        _ongletSeuils(d, large)
                      else
                        _ongletCatalogue(d, large),
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
    child: Row(
      children: [
        for (final (titre, icone) in onglets)
          InkWell(
            key: Key('onglet-catalogue-$titre'),
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
  );

  // ── Onglet 1 : Voir le Catalogue ──────────────────────────────────────────

  Widget _ongletCatalogue(DonneesStocks d, bool large) {
    final terme = _recherche.trim().toLowerCase();

    final lignes = d.lignes.where((l) {
      if (_categorie != 'Tous' && l.categorie != _categorie) return false;
      if (terme.isEmpty) return true;
      return l.produit.name.toLowerCase().contains(terme) ||
          l.produit.sku.toLowerCase().contains(terme);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          titre: 'Catalogue Produits',
          icone: SymbolesAgri.category,
          sousTitre:
              "Vue d'ensemble visuelle de l'offre commerciale de la ferme.",
          large: large,
        ),
        const SizedBox(height: AgriSpacing.md),
        _barreOutils(d),
        const SizedBox(height: AgriSpacing.md),
        _mentionLectureSeule(),
        const SizedBox(height: AgriSpacing.md),
        if (lignes.isEmpty)
          Container(
            padding: const EdgeInsets.all(AgriSpacing.lg),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: const Text(
              '— Aucun produit pour ces critères —',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontStyle: FontStyle.italic,
                color: AgriColors.outline,
              ),
            ),
          )
        else if (_grille)
          _grilleProduits(lignes, large)
        else
          _listeProduits(lignes),
      ],
    );
  }

  Widget _barreOutils(DonneesStocks d) => Container(
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
              child: TextField(
                key: const Key('catalogue-recherche'),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(SymbolesAgri.search, size: 18),
                  hintText: 'Rechercher un produit ou un SKU...',
                  hintStyle: TextStyle(fontSize: AgriTypography.xs),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: AgriTypography.xs),
                onChanged: (v) => setState(() => _recherche = v),
              ),
            ),
            const SizedBox(width: AgriSpacing.sm),
            // Bascule grille / liste de la maquette.
            IconButton(
              key: const Key('vue-grille'),
              onPressed: () => setState(() => _grille = true),
              icon: Icon(
                SymbolesAgri.grid_view,
                size: 20,
                color: _grille ? AgriColors.brandEmerald : AgriColors.outline,
              ),
            ),
            IconButton(
              key: const Key('vue-liste'),
              onPressed: () => setState(() => _grille = false),
              icon: Icon(
                SymbolesAgri.view_list,
                size: 20,
                color: _grille ? AgriColors.outline : AgriColors.brandEmerald,
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.sm),
        // ⚠️⚠️ **LES PASTILLES VIENNENT DES CATÉGORIES REÇUES, PAS D'UNE
        // LISTE FIGÉE.** La maquette en code six en dur — Cuniculture,
        // Aviculture, Porciculture, Maraîchage, Transformation,
        // Équipements — et **oublie « Aliments » et « Médicaments »**, qui
        // existent bel et bien au catalogue : neuf produits, dont toute la
        // provende, seraient restés hors de tout filtre. Recopier la liste
        // aurait reproduit l'oubli.
        Wrap(
          spacing: AgriSpacing.xs,
          runSpacing: AgriSpacing.xs,
          children: [
            // Un libellé n'a qu'une pastille : deux catégories « Aliments » donnaient deux clés identiques.
            for (final c in <String>{'Tous', ...d.categories.map((c) => c.label)})
              InkWell(
                key: Key('pastille-$c'),
                onTap: () => setState(() => _categorie = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _categorie == c
                        ? AgriColors.brandEmerald
                        : AgriColors.surfaceCard,
                    border: Border.all(color: AgriColors.outlineVariant),
                    borderRadius: BorderRadius.circular(AgriRadius.full),
                  ),
                  child: Text(
                    c,
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: FontWeight.bold,
                      color: _categorie == c
                          ? Colors.white
                          : AgriColors.brandForest,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _grilleProduits(List<LigneStock> lignes, bool large) => GridView.count(
    crossAxisCount: large ? 4 : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: 1.5,
    children: [
      for (var i = 0; i < lignes.length; i++)
        Container(
          key: Key('carte-produit-$i'),
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lignes[i].produit.sku,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.outline,
                ),
              ),
              const SizedBox(height: AgriSpacing.xs),
              Text(
                lignes[i].produit.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.onSurface,
                ),
              ),
              const SizedBox(height: AgriSpacing.xs),
              Text(
                lignes[i].categorie,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
              const Spacer(),
              Text(
                _tarif(lignes[i]),
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.w800,
                  color: AgriColors.brandEmerald,
                ),
              ),
              Text(
                'Stock : ${_nombre(lignes[i].produit.stockQty)} '
                '${lignes[i].produit.unit}',
                style: TextStyle(
                  fontSize: 11,
                  color: lignes[i].sousSeuil
                      ? AgriColors.errorDeep
                      : AgriColors.outline,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  Widget _listeProduits(List<LigneStock> lignes) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: LayoutBuilder(
      builder: (_, contraintes) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(940, contraintes.maxWidth),
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
                  Expanded(flex: 2, child: Text('SKU', style: _enteteColonne)),
                  Expanded(
                    flex: 4,
                    child: Text('DÉSIGNATION', style: _enteteColonne),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('CATÉGORIE', style: _enteteColonne),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('STOCK', style: _enteteColonne),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('TARIF', style: _enteteColonne),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('ACTIONS', style: _enteteColonne),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < lignes.length; i++)
              Container(
                key: Key('ligne-produit-$i'),
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
                        lignes[i].produit.sku,
                        style: const TextStyle(
                          fontSize: AgriTypography.xs,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        lignes[i].produit.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AgriTypography.xs),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        lignes[i].categorie,
                        style: const TextStyle(fontSize: AgriTypography.xs),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${_nombre(lignes[i].produit.stockQty)} '
                        '${lignes[i].produit.unit}',
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          color: lignes[i].sousSeuil
                              ? AgriColors.errorDeep
                              : AgriColors.onSurface,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _tarif(lignes[i]),
                        style: const TextStyle(fontSize: AgriTypography.xs),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          key: Key('modifier-produit-$i'),
                          tooltip: 'Modifier',
                          onPressed: widget.produits == null
                              ? null
                              : () => setState(
                                  () => _formulaire = lignes[i].produit.id,
                                ),
                          icon: const Icon(SymbolesAgri.edit, size: 16),
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
    ),
  );

  /// Tarif tel que le catalogue le porte.
  ///
  /// ⚠️ **TROIS MODES, PAS DEUX.** `fixe` affiche un prix, `fourchette` une
  /// plage, et un produit **sur devis** n'a pas de prix du tout — afficher
  /// « 0 F » le ferait vendre pour rien à la caisse.
  static String _tarif(LigneStock l) {
    final min = l.produit.priceMin;
    final max = l.produit.priceMax;

    if (l.produit.pricingMode == 'fourchette' && min != null && max != null) {
      return '${_nombre(min)} – ${_nombre(max)} F';
    }
    if (min != null) return '${_nombre(min)} F';
    return 'Sur devis';
  }

  /// ⚠️⚠️ **LE SERVEUR IGNORE TOUT ENVOI SUR LES RÉFÉRENTIELS**, et les compte
  /// dans `referentiels_ignored`. Un produit créé ici, ou un seuil modifié,
  /// serait jeté sans un mot, puis effacé par le tirage suivant. Les boutons
  /// restent — c'est la maquette — mais désactivés et expliqués.
  Widget _mentionLectureSeule() => Container(
    key: const Key('catalogue-lecture-seule'),
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
        const Expanded(
          child: Text(
            'Produits, catégories et seuils sont des référentiels tenus par '
            "le serveur. Un produit créé ou modifié ici est enregistré tout de "
            "suite, puis envoyé à la synchronisation : le serveur le valide et "
            "attribue son SKU définitif. Les seuils restent en consultation.",
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.brandForest,
            ),
          ),
        ),
        const SizedBox(width: AgriSpacing.sm),
        OutlinedButton.icon(
          key: const Key('nouveau-produit'),
          onPressed: widget.produits == null
              ? null
              : () => setState(() => _formulaire = ''),
          icon: const Icon(SymbolesAgri.add_circle, size: 18),
          label: const Text(
            'Nouveau Produit',
            style: TextStyle(
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
      ],
    ),
  );

  // ── Onglet 2 : Seuils d'Alerte ────────────────────────────────────────────

  Widget _ongletSeuils(DonneesStocks d, bool large) {
    // ⚠️ Un produit SANS seuil n'est ni « normal » ni « critique » : il n'est
    // pas surveillé. Le confondre avec « normal » ferait croire à une veille
    // qui n'existe pas.
    final surveilles = d.lignes
        .where((l) => l.produit.alertThreshold != null)
        .toList();

    final lignes = surveilles.where((l) {
      if (_statut == 'Normal') return !l.sousSeuil;
      if (_statut == 'Critique') return l.sousSeuil;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          titre: "Seuils d'Alerte",
          icone: SymbolesAgri.notifications_active,
          sousTitre: 'Surveillance des niveaux de réapprovisionnement.',
          large: large,
        ),
        const SizedBox(height: AgriSpacing.md),
        // ⚠️ `IntrinsicHeight` : la barre de couleur de la carte s'étire sur
        // toute sa hauteur (`CrossAxisAlignment.stretch`), ce qui exige une
        // hauteur bornée. Dans une grille elle l'était ; dans une simple
        // rangée de colonne défilante, non — et la mise en page levait
        // « BoxConstraints forces an infinite height », visible au seul rendu.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _carteKpi(
                  'Produits sous seuil',
                  '${d.alertesDeSeuil}',
                  AgriColors.errorRed,
                ),
              ),
              const SizedBox(width: AgriSpacing.md),
              Expanded(
                child: _carteKpi(
                  'Seuils configurés',
                  '${surveilles.length}',
                  AgriColors.infoBlue,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            key: const Key('filtre-statut-seuil'),
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _statut,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.onSurface,
                ),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Tous les statuts')),
                  DropdownMenuItem(value: 'Normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'Critique', child: Text('Critique')),
                ],
                onChanged: (v) => setState(() => _statut = v ?? ''),
              ),
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
                      flex: 4,
                      child: Text('PRODUIT', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('STOCK ACTUEL', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('SEUIL CONFIGURÉ', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('STATUT', style: _enteteColonne),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('ACTIONS', style: _enteteColonne),
                    ),
                  ],
                ),
              ),
              if (lignes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AgriSpacing.lg),
                  child: Text(
                    '— Aucun produit surveillé pour ce statut —',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontStyle: FontStyle.italic,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
              for (var i = 0; i < lignes.length; i++)
                Container(
                  key: Key('seuil-$i'),
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
                        flex: 4,
                        child: Text(
                          lignes[i].produit.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _nombre(lignes[i].produit.stockQty),
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _nombre(lignes[i].produit.alertThreshold!),
                          style: const TextStyle(fontSize: AgriTypography.xs),
                        ),
                      ),
                      Expanded(flex: 2, child: _pastilleStatut(lignes[i])),
                      const Expanded(
                        flex: 2,
                        child: Opacity(
                          opacity: 0.4,
                          child: Icon(
                            SymbolesAgri.edit,
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
        const SizedBox(height: AgriSpacing.md),
        // ⚠️ Un produit sans seuil est hors surveillance, et le dire évite de
        // croire à une veille complète.
        Text(
          '${d.lignes.length - surveilles.length} produit(s) sans seuil '
          'configuré : ils ne déclenchent aucune alerte.',
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontStyle: FontStyle.italic,
            color: AgriColors.outline,
          ),
        ),
      ],
    );
  }

  Widget _pastilleStatut(LigneStock l) {
    final (libelle, couleur) = l.sousSeuil
        ? ('Critique', AgriColors.errorDeep)
        : ('Normal', AgriColors.brandEmerald);

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
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: couleur,
          ),
        ),
      ),
    );
  }

  // ── Briques communes ──────────────────────────────────────────────────────

  Widget _entete({
    required String titre,
    required String sousTitre,
    required IconData icone,
    required bool large,
  }) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icone, size: 26, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              titre,
              style: TextStyle(
                fontSize: large ? 24 : 20,
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
  );

  Widget _carteKpi(String libelle, String valeur, Color barre) => CarteKpi(
    key: Key('kpi-$libelle'),
    libelle: libelle,
    valeur: valeur,
    couleurLisere: barre,
  );

  static String _nombre(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);
}
