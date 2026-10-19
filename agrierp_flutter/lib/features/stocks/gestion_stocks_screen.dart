import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'stocks_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/gestion-stocks.html` → Gestion Stocks.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** En-tête, quatre KPI,
/// puis les **trois onglets** dans SON ordre : Tableau & Valorisation ·
/// Journal des Mouvements · Ajustement / Correction.
///
/// ⚠️⚠️ **TOUTE LA VALORISATION EST HORS DE PORTÉE DU POSTE.** Le PMP se
/// calcule côté serveur par moyenne pondérée des **lignes d'achat** ;
/// `purchase_lines` ne descend pas, et `products` ne porte aucune colonne de
/// coût. PMP unitaire, valeur de ligne, valorisation totale et écarts en FCFA
/// affichent donc un tiret motivé. Les estimer depuis le prix de VENTE
/// donnerait une valorisation supérieure au coût — un actif gonflé au bilan.
class GestionStocksScreen extends StatefulWidget {
  const GestionStocksScreen({super.key, required this.depot});

  final StocksRepository depot;

  @override
  State<GestionStocksScreen> createState() => _GestionStocksScreenState();
}

class _GestionStocksScreenState extends State<GestionStocksScreen> {
  /// Les trois onglets de la maquette, dans son ordre.
  static const onglets = [
    'Tableau & Valorisation',
    'Journal des Mouvements',
    'Ajustement / Correction',
  ];

  String _onglet = onglets.first;
  String _recherche = '';
  String _categorie = '';

  DonneesStocks? _donnees;

  // Formulaire d'ajustement.
  String? _produitChoisi;
  String _motif = '';
  final _physique = TextEditingController();
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _physique.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() {
      _donnees = donnees;
      _produitChoisi ??= donnees.lignes.isEmpty
          ? null
          : donnees.lignes.first.produit.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

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
                      _entete(large),
                      const SizedBox(height: AgriSpacing.lg),
                      _kpis(d, large),
                      const SizedBox(height: AgriSpacing.lg),
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.md),
                      switch (_onglet) {
                        'Journal des Mouvements' => _ongletJournal(d),
                        'Ajustement / Correction' => _ongletAjustement(d),
                        _ => _ongletTableau(d),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _entete(bool large) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: Row(
      children: [
        const Icon(SymbolesAgri.inventory_2, size: 26, color: AgriColors.brandEmerald),
        const SizedBox(width: AgriSpacing.xs),
        Expanded(
          // ⚠️ **« Gestion des Stocks », le titre de la PAGE.**
          // « Gestion Stocks » est le libellé de l'ENTRÉE DE MENU
          // (`sidebar.js`) : les deux existent dans la maquette, à deux
          // endroits différents. Reprendre celui du menu pour titrer la
          // page remplace un libellé validé par un autre.
          child: Text(
            'Gestion des Stocks',
            style: TextStyle(
              fontSize: large ? 24 : 20,
              fontWeight: FontWeight.bold,
              color: AgriColors.onSurface,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _kpis(DonneesStocks d, bool large) => GridView.count(
    crossAxisCount: large ? 4 : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 2.6 : 1.6,
    children: [
      // ⚠️⚠️ Sans PMP, aucune valorisation. Le bouton « Recalculer PMP » de
      // la maquette n'est pas repris : il n'y a rien à recalculer au poste.
      _carteKpi(
        'Valorisation Stocks',
        '—',
        AgriColors.brandEmerald,
        legende: "Prix de revient absent du catalogue",
      ),
      _carteKpi('Alertes de Seuil', '${d.alertesDeSeuil}', AgriColors.errorRed),
      // ⚠️ Rotation = COGS du mois ÷ stock moyen. Les deux termes viennent
      // du grand livre des mouvements, qui ne descend pas.
      _carteKpi(
        'Rotation du Stock',
        '—',
        AgriColors.infoBlue,
        legende: 'Journal des mouvements non synchronisé',
      ),
      // ⚠️ EN NOMBRE, PAS EN FRANCS : un écart se valorise au PMP.
      _carteKpi(
        "Écarts d'Inventaire",
        '${d.ecartsDInventaire}',
        AgriColors.accentYellow,
        legende: 'Saisis sur ce poste',
      ),
    ],
  );

  Widget _carteKpi(
    String libelle,
    String valeur,
    Color barre, {
    String legende = '',
  }) => CarteKpi(
    key: Key('kpi-$libelle'),
    libelle: libelle,
    valeur: valeur,
    legende: legende,
    couleurLisere: barre,
  );

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final titre in onglets)
            InkWell(
              key: Key('onglet-stocks-$titre'),
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
                child: Text(
                  titre,
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                    color: _onglet == titre
                        ? AgriColors.brandEmerald
                        : AgriColors.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  /// ⚠️⚠️ **QUATRE EN-TÊTES SANS ACCENT — C'EST LA MAQUETTE, PAS UNE FAUTE
  /// DE FRAPPE DE PORTAGE.** `gestion-stocks.html` écrit `Designation`,
  /// `Categorie`, `Reference` et `Quantite` dans ses `<th>`, alors que ses
  /// PROPRES modales écrivent `Désignation *` et `Catégorie *`.
  ///
  /// ⚠️ **INCOHÉRENCE DU PROTOTYPE, SIGNALÉE ET NON TRANCHÉE.** Sur les 102
  /// pages : `Catégorie` 16 fois contre `Categorie` 2, `Désignation` 7 contre
  /// 2, `Quantité` 4 contre 1, `Référence` 3 contre 3. Les formes accentuées
  /// dominent largement, et cette page est l'une des rares à ne pas les
  /// porter. Les accentuer ici serait pourtant harmoniser en silence une
  /// incohérence du template — c'est au client de trancher.
  /// **ARBITRAGE CLIENT** : accentuer les huit `<th>` fautifs du prototype ?
  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AgriColors.outline,
  );

  // ── Onglet 1 : Tableau & Valorisation ─────────────────────────────────────

  Widget _ongletTableau(DonneesStocks d) {
    final terme = _recherche.trim().toLowerCase();

    final lignes = d.lignes.where((l) {
      if (_categorie.isNotEmpty && l.categorie != _categorie) return false;
      if (terme.isEmpty) return true;
      return l.produit.name.toLowerCase().contains(terme) ||
          l.produit.sku.toLowerCase().contains(terme);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
                  key: const Key('stock-recherche'),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(SymbolesAgri.search, size: 18),
                    hintText: 'Rechercher un produit...',
                    hintStyle: TextStyle(fontSize: AgriTypography.xs),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: AgriTypography.xs),
                  onChanged: (v) => setState(() => _recherche = v),
                ),
              ),
              Container(
                key: const Key('stock-categorie'),
                padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
                decoration: BoxDecoration(
                  color: AgriColors.surfaceCard,
                  border: Border.all(color: AgriColors.outlineVariant),
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _categorie,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.onSurface,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Catégorie : Toutes'),
                      ),
                      for (final c in d.categories)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _categorie = v ?? ''),
                  ),
                ),
              ),
              _boutonInerte(SymbolesAgri.file_download, 'Exporter'),
              _boutonInerte(SymbolesAgri.upload_file, 'Importer'),
            ],
          ),
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
              width: 1040,
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
                          child: Text('CODE', style: _enteteColonne),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text('DESIGNATION', style: _enteteColonne),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('CATEGORIE', style: _enteteColonne),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('STOCK', style: _enteteColonne),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('PMP UNIT.', style: _enteteColonne),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('VALEUR', style: _enteteColonne),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('URGENCE', style: _enteteColonne),
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
                        '— Aucun produit pour ces critères —',
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          fontStyle: FontStyle.italic,
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                  for (var i = 0; i < lignes.length; i++)
                    _ligneStock(lignes[i], i),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ligneStock(LigneStock l, int index) => Container(
    key: Key('produit-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            l.produit.sku,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            l.produit.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            l.categorie,
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            '${_nombre(l.produit.stockQty)} ${l.produit.unit}',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
              // ⚠️ Un stock négatif se voit : c'est une entrée non saisie,
              // pas une anomalie de données.
              color: l.negatif ? AgriColors.errorDeep : AgriColors.onSurface,
            ),
          ),
        ),
        // ⚠️⚠️ PMP et VALEUR : voir le docblock de l'écran.
        const Expanded(
          flex: 2,
          child: Text('—', style: TextStyle(fontSize: AgriTypography.xs)),
        ),
        const Expanded(
          flex: 2,
          child: Text('—', style: TextStyle(fontSize: AgriTypography.xs)),
        ),
        Expanded(flex: 2, child: _pastilleUrgence(l)),
        const Expanded(
          flex: 2,
          child: Opacity(
            opacity: 0.4,
            child: Icon(SymbolesAgri.edit, size: 16, color: AgriColors.outline),
          ),
        ),
      ],
    ),
  );

  Widget _pastilleUrgence(LigneStock l) {
    final (libelle, couleur) = l.negatif
        ? ('Négatif', AgriColors.errorDeep)
        : l.sousSeuil
        ? ('Sous seuil', AgriColors.errorRed)
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

  // ── Onglet 2 : Journal des Mouvements ─────────────────────────────────────

  Widget _ongletJournal(DonneesStocks d) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // ⚠️⚠️ LE JOURNAL LOCAL EST PARTIEL, ET LE DIT. `stock_movements` —
      // le grand livre alimenté par les ventes, les achats et la
      // production — ne descend pas au poste. Présenter ces seules lignes
      // comme « le journal » ferait croire à un magasin sans mouvement.
      const Padding(
        padding: EdgeInsets.only(bottom: AgriSpacing.md),
        child: Text(
          'Ajustements d\'inventaire saisis sur ce poste. Les entrées et '
          'sorties issues des ventes, des achats et de la production '
          'vivent dans le journal du serveur, qui ne descend pas ici.',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            color: AgriColors.outline,
          ),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: AgriColors.surfaceCard,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1040,
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
                        flex: 3,
                        child: Text('DATE / HEURE', style: _enteteColonne),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('REFERENCE', style: _enteteColonne),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text('PRODUIT', style: _enteteColonne),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('TYPE', style: _enteteColonne),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text('MOTIF', style: _enteteColonne),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('QUANTITE', style: _enteteColonne),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('VALEUR', style: _enteteColonne),
                      ),
                    ],
                  ),
                ),
                if (d.mouvements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AgriSpacing.lg),
                    child: Text(
                      '— Aucun ajustement saisi sur ce poste —',
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontStyle: FontStyle.italic,
                        color: AgriColors.outline,
                      ),
                    ),
                  ),
                for (var i = 0; i < d.mouvements.length; i++)
                  _ligneMouvement(d.mouvements[i], i),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _ligneMouvement(MouvementStock m, int index) => Container(
    key: Key('mouvement-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            _horodatage(m.ajustement.movementDate),
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            m.ajustement.referenceType,
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            m.designation,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            m.ajustement.type == 'entree' ? 'Entrée' : 'Sortie',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
              color: m.ajustement.type == 'entree'
                  ? AgriColors.brandEmerald
                  : AgriColors.errorDeep,
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            m.ajustement.reason ?? '—',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            _nombre(m.ajustement.quantity),
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        // ⚠️ Sans PMP, un mouvement ne se valorise pas.
        const Expanded(
          flex: 2,
          child: Text('—', style: TextStyle(fontSize: AgriTypography.xs)),
        ),
      ],
    ),
  );

  // ── Onglet 3 : Ajustement / Correction ────────────────────────────────────

  Widget _ongletAjustement(DonneesStocks d) {
    final choisi = d.lignes
        .where((l) => l.produit.id == _produitChoisi)
        .map((l) => l.produit)
        .firstOrNull;

    final theorique = choisi?.stockQty ?? 0;
    final physique = double.tryParse(_physique.text.trim());
    final ecart = physique == null ? null : physique - theorique;

    return Container(
      padding: const EdgeInsets.all(AgriSpacing.lg),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Saisir un ajustement d'inventaire",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AgriColors.brandForest,
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          _etiquette('Produit'),
          Container(
            key: const Key('adj-produit'),
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
            decoration: BoxDecoration(
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _produitChoisi,
                isExpanded: true,
                style: const TextStyle(
                  fontSize: 14,
                  color: AgriColors.onSurface,
                ),
                items: [
                  for (final l in d.lignes)
                    DropdownMenuItem(
                      value: l.produit.id,
                      // ⚠️ Le stock théorique figure dans le libellé, comme
                      // dans la maquette : l'opérateur compare sans changer
                      // d'écran.
                      child: Text(
                        '${l.produit.name} (Théorique : '
                        '${_nombre(l.produit.stockQty)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _produitChoisi = v;
                  _erreur = null;
                }),
              ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _etiquette('Stock théorique'),
                    _champLecture(
                      key: const Key('adj-theorique'),
                      valeur: _nombre(theorique),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AgriSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _etiquette('Stock physique constaté'),
                    TextField(
                      key: const Key('adj-physique'),
                      controller: _physique,
                      keyboardType: TextInputType.number,
                      decoration: _decoration(),
                      style: const TextStyle(fontSize: 14),
                      onChanged: (_) => setState(() => _erreur = null),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AgriSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _etiquette('Écart calculé'),
                    _champLecture(
                      key: const Key('adj-ecart'),
                      valeur: ecart == null
                          ? '—'
                          : '${ecart > 0 ? '+' : ''}${_nombre(ecart)}',
                      couleur: ecart == null || ecart == 0
                          ? AgriColors.onSurface
                          : ecart > 0
                          ? AgriColors.brandEmerald
                          : AgriColors.errorDeep,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          _etiquette("Motif de l'écart"),
          Container(
            key: const Key('adj-motif'),
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm),
            decoration: BoxDecoration(
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _motif,
                isExpanded: true,
                style: const TextStyle(
                  fontSize: 14,
                  color: AgriColors.onSurface,
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text("-- Sélectionner selon le sens de l'écart --"),
                  ),
                  for (final m in StocksRepository.motifs)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => setState(() {
                  _motif = v ?? '';
                  _erreur = null;
                }),
              ),
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: AgriSpacing.sm),
            Text(
              _erreur!,
              key: const Key('adj-erreur'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.errorDeep,
              ),
            ),
          ],
          const SizedBox(height: AgriSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              key: const Key('adj-valider'),
              onPressed: _validerAjustement,
              style: ElevatedButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.lg,
                  vertical: AgriSpacing.sm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
              ),
              child: const Text(
                "Valider l'ajustement",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _validerAjustement() async {
    final produit = _produitChoisi;
    final physique = double.tryParse(_physique.text.trim());

    if (produit == null || physique == null) {
      setState(() => _erreur = 'Indiquez le stock physique constaté.');
      return;
    }

    try {
      await widget.depot.enregistrerEcart(
        productId: produit,
        stockPhysique: physique,
        motif: _motif,
      );
    } on ArgumentError catch (e) {
      setState(() => _erreur = '${e.message}');
      return;
    }

    _physique.clear();
    setState(() {
      _motif = '';
      _erreur = null;
    });
    await _charger();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Écart enregistré. Il partira au prochain tirage, et le serveur '
            'recalculera le solde depuis son propre état.',
          ),
        ),
      );
    }
  }

  // ── Briques communes ──────────────────────────────────────────────────────

  Widget _champLecture({
    required Key key,
    required String valeur,
    Color couleur = AgriColors.onSurface,
  }) => Container(
    key: key,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: 12,
    ),
    decoration: BoxDecoration(
      color: AgriColors.surfaceZebra,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Text(
      valeur,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: couleur,
      ),
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

  /// Quantité sans décimale inutile : « 45 » et non « 45.0 ».
  static String _nombre(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

  static String _horodatage(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
