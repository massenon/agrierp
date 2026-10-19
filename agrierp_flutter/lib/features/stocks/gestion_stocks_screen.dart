import 'package:flutter/material.dart';

import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import '../rapports/rapports_exports_screen.dart' show Editeur;
import 'journal_stocks.dart';
import 'pmp_service.dart';
import 'stocks_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/gestion-stocks.html` → Gestion Stocks.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** En-tête, quatre KPI,
/// puis les **trois onglets** dans SON ordre : Tableau & Valorisation ·
/// Journal des Mouvements · Ajustement / Correction.
///
/// 🔴→✅ **TICKET U8 — LA VALORISATION EST CELLE DU WEB.** Le PMP se calcule
/// par moyenne pondérée des **lignes d'achat**, qui descendent au poste depuis
/// U4 (D-U4) : PMP unitaire, valeur de ligne, valorisation totale, écarts en
/// FCFA et valeur du journal reprennent EXACTEMENT `GestionStocks` (Livewire)
/// et son Blade, via [PmpService] (`Product::computePmp()`). « — » seulement
/// là où le web en met un : produit sans PMP (jamais acheté). Jamais une
/// estimation depuis le prix de VENTE — un actif gonflé au bilan.
///
/// 🔴→✅ **TICKET U9 — LE GRAND LIVRE DESCEND.** `stock_movements` est tiré
/// au poste : « Rotation du Stock », « Écarts d'Inventaire » (saisis au web,
/// ici ou sur un autre poste) et le Journal des Mouvements reprennent les
/// formules du web ([JournalStocks]) ; les saisies de ce poste en attente
/// d'envoi y sont projetées, jamais comptées deux fois. Le tableau suit le
/// Blade : tri par NOM, pastille « Critique » / « Normal », mention « Entrée
/// non saisie » sous un stock négatif, colonnes alignées comme au web.
///
/// 🔴→✅ **TICKET U10 — LES DERNIERS GESTES DU WEB.** « Exporter » produit le PDF du web
/// (`exportStocksPdf()`, vue `exports.gestion-stocks`) ; « Ajouter Stock » ouvre la modale du web et écrit le fait
/// en attente d'envoi ([StocksRepository.ajouterStock], rejoué par le serveur comme `submitAjouterStock()`) ; le lien
/// « Configurer les Seuils d'Alerte » ouvre les Seuils d'Alerte ([onConfigurerSeuils]) et l'icône Modifier
/// l'édition du produit ([onModifierProduit]), comme les deux `route()` du Blade. Les deux gestes d'écriture sont
/// réservés au droit `manage-stocks` ([peutGerer], `@can` du Blade).
class GestionStocksScreen extends StatefulWidget {
  const GestionStocksScreen({
    super.key,
    required this.depot,
    this.imprimer,
    this.peutGerer = false,
    this.onConfigurerSeuils,
    this.onModifierProduit,
  });

  final StocksRepository depot;

  /// Éditeur injecté — `EditeursRapports.imprimer` en production, un espion en test. `null` : « Exporter » inerte.
  final Editeur? imprimer;

  /// `@can('manage-stocks')` du Blade : « Ajouter Stock » et l'icône Modifier.
  final bool peutGerer;

  /// `route('stocks.seuils')` : l'écran des Seuils d'Alerte (onglet du Catalogue Produits au poste).
  final VoidCallback? onConfigurerSeuils;

  /// `route('stocks.produits.modifier', $id)` : l'édition du produit.
  final ValueChanged<String>? onModifierProduit;

  /// Légende de « Rotation du Stock », construite comme dans le Blade : le périmètre du ratio se lit en même temps
  /// que le ratio. Sans rotation : la légende de `x-kpi-card :pending`.
  static String legendeRotation(RotationStock r) {
    if (r.rotation == null) {
      return 'Disponible après un stock valorisable non nul sur le mois';
    }
    return '${r.couverture == null ? '' : 'Couvre ${PmpService.nombre(r.couverture!, 0)} % des ventes du mois — '}'
        "les marchandises produites à la ferme n'ont pas de coût d'achat";
  }

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

  /// Quantité de la modale « Ajouter Stock » (ticket U10) : gardée par l'écran, la modale se ferme en animation.
  final _quantiteAjout = TextEditingController();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _physique.dispose();
    _quantiteAjout.dispose();
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gestion des Stocks',
                style: TextStyle(
                  fontSize: large ? 24 : 20,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.onSurface,
                ),
              ),
              const SizedBox(height: AgriSpacing.xs),
              // Ticket U9 — sous-titre du Blade.
              const Text(
                'Espace unifié : inventaire, mouvements et ajustements.',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AgriSpacing.sm),
        // 🔴→✅ Ticket U10 — lien du Blade (`route('stocks.seuils')`), à droite de l'en-tête.
        InkWell(
          key: const Key('stocks-configurer-seuils'),
          onTap: widget.onConfigurerSeuils,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                SymbolesAgri.notification_important,
                size: 16,
                color: AgriColors.brandForest,
              ),
              SizedBox(width: AgriSpacing.xs),
              Text(
                "Configurer les Seuils d'Alerte",
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  color: AgriColors.brandForest,
                ),
              ),
            ],
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
      // Ticket U8 — `number_format($kpis['valorisation'], 0, ',', ' ').' FCFA'`
      // et la légende du Blade. Le bouton « Recalculer PMP » de la maquette
      // n'est pas repris : le web ne l'a pas (le PMP se lit à chaque affichage).
      _carteKpi(
        'Valorisation Stocks',
        '${PmpService.francs(d.valorisation)} FCFA',
        AgriColors.brandEmerald,
        icone: SymbolesAgri.payments,
        legende: 'Basée sur le PMP réel (achats)',
      ),
      // Ticket U9 — `$kpis['alertes'].' réf.'` : produits actifs dont le seuil
      // est strictement positif et atteint (`urgence` du web).
      _carteKpi(
        'Alertes de Seuil',
        '${d.alertesDeSeuil} réf.',
        AgriColors.errorRed,
        icone: SymbolesAgri.warning,
      ),
      // 🔴→✅ Ticket U9 — `StockRotationService::pourLeMois()` sur le grand
      // livre descendu ([JournalStocks.rotation]) ; sans stock valorisable
      // sur le mois, la carte « en attente » du web (`x-kpi-card :pending`).
      // 🔴→✅ Ticket U10 — la carte « en attente » est celle de `x-kpi-card :pending` : tiret estompé
      // (`text-outline/50`) et sablier `hourglass_empty` devant « Disponible après … ».
      _carteKpi(
        'Rotation du Stock',
        d.rotation.rotation == null
            ? '—'
            : '${PmpService.nombre(d.rotation.rotation!, 1)} fois/mois',
        AgriColors.infoBlue,
        icone: SymbolesAgri.sync,
        legende: GestionStocksScreen.legendeRotation(d.rotation),
        enAttente: d.rotation.rotation == null,
      ),
      // 🔴→✅ Ticket U9 — tous les écarts du mois de la ferme (web, ce poste,
      // autres postes), plus ceux de ce poste en attente d'envoi ; légende du
      // Blade.
      _carteKpi(
        "Écarts d'Inventaire",
        '${PmpService.francs(d.ecartsDuMois)} FCFA',
        AgriColors.accentYellow,
        icone: SymbolesAgri.rule,
        couleurIcone: AgriColors.brandForest,
        legende: 'Ajustements du mois',
      ),
    ],
  );

  /// `x-kpi-card` du web : libellé, icône de la variante (couleur de la variante, `text-brand-forest` pour
  /// `maize`), valeur, légende ; `:pending` → tiret estompé et sablier (ticket U10).
  Widget _carteKpi(
    String libelle,
    String valeur,
    Color barre, {
    required IconData icone,
    Color? couleurIcone,
    String legende = '',
    bool enAttente = false,
  }) => CarteKpi(
    key: Key('kpi-$libelle'),
    libelle: libelle,
    valeur: valeur,
    legende: legende,
    icone: icone,
    couleurIcone: couleurIcone ?? barre,
    couleurValeur: enAttente
        ? AgriColors.outline.withValues(alpha: 0.5)
        : AgriColors.onSurface,
    iconeLegende: enAttente ? SymbolesAgri.hourglass_empty : null,
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
    final lignes = StocksRepository.filtrer(
      d.lignes,
      recherche: _recherche,
      categorie: _categorie,
    );

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
                    hintText: 'Désignation ou SKU...',
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
                        DropdownMenuItem(value: c.id, child: Text(c.label)),
                    ],
                    onChanged: (v) => setState(() => _categorie = v ?? ''),
                  ),
                ),
              ),
              // ⚠️ « Importer » n'existe pas au web (`GestionStocks` : aucun
              // import réel, « zéro placeholder ») : le poste ne l'affiche
              // plus (ticket U9, article 5 — le web est maître).
              // 🔴→✅ Ticket U10 — `exportStocksPdf()` : le tableau FILTRÉ (recherche + catégorie), en PDF.
              OutlinedButton.icon(
                key: const Key('stocks-exporter'),
                onPressed: widget.imprimer == null
                    ? null
                    : () => _exporter(lignes, d),
                icon: const Icon(SymbolesAgri.picture_as_pdf, size: 16),
                label: const Text(
                  'Exporter',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AgriColors.onSurface,
                  side: const BorderSide(color: AgriColors.outlineVariant),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.md,
                    vertical: AgriSpacing.sm,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                  ),
                ),
              ),
              // 🔴→✅ Ticket U10 — `@can('manage-stocks')` puis `openAddStockModal()`.
              if (widget.peutGerer)
                ElevatedButton.icon(
                  key: const Key('stocks-ajouter'),
                  onPressed: () => _ouvrirAjouterStock(d),
                  icon: const Icon(SymbolesAgri.add_circle, size: 16),
                  label: const Text(
                    'Ajouter Stock',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AgriColors.brandEmerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AgriSpacing.md,
                      vertical: AgriSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AgriRadius.lg),
                    ),
                  ),
                ),
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
              width: 1140,
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
                          // Décision client du 19/10/2026 : accentués comme le Blade (« Désignation » en `uppercase`), plus la maquette.
                          child: Text('DÉSIGNATION', style: _enteteColonne),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('CATÉGORIE', style: _enteteColonne),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'STOCK',
                            textAlign: TextAlign.right,
                            style: _enteteColonne,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'PMP UNIT.',
                            textAlign: TextAlign.right,
                            style: _enteteColonne,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'VALEUR',
                            textAlign: TextAlign.right,
                            style: _enteteColonne,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: EdgeInsets.only(left: AgriSpacing.md),
                            child: Text('URGENCE', style: _enteteColonne),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'ACTIONS',
                            textAlign: TextAlign.right,
                            style: _enteteColonne,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (lignes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AgriSpacing.lg),
                      child: Text(
                        'Aucun produit pour le moment.',
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

  /// Une ligne du tableau, cellule par cellule comme le Blade (ticket U9) : code en chasse fixe, désignation en
  /// gras vert forêt, catégorie, stock aligné à droite (rouge gras et « Entrée non saisie » s'il est négatif), PMP,
  /// valeur en gras, pastille d'urgence, action.
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
            key: Key('code-$index'),
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            l.produit.name,
            key: Key('designation-$index'),
            overflow: TextOverflow.ellipsis,
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
            l.categorie,
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        // `rtrim(rtrim(number_format($stock, 2, '.', ''), '0'), '.').' '.$unit` ; un stock négatif en rouge gras,
        // avec la mention « Entrée non saisie » (ticket 14.30), jamais une pastille.
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${PmpService.quantite(l.produit.stockQty)} ${l.produit.unit}',
                key: Key('stock-$index'),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: l.stockNegatif
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: l.stockNegatif
                      ? AgriColors.errorDeep
                      : AgriColors.onSurface,
                ),
              ),
              if (l.stockNegatif)
                Text(
                  'ENTRÉE NON SAISIE',
                  key: Key('entree-non-saisie-$index'),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.errorDeep,
                  ),
                ),
            ],
          ),
        ),
        // Ticket U8 — `number_format($row['pmp'], 0, ',', ' ')` et
        // `number_format($row['valeur'], 0, ',', ' ')`, « — » sans PMP.
        Expanded(
          flex: 2,
          child: Text(
            l.pmp == null ? '—' : PmpService.francs(l.pmp!),
            key: Key('pmp-$index'),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: AgriTypography.xs),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            l.valeur == null ? '—' : PmpService.francs(l.valeur!),
            key: Key('valeur-$index'),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(left: AgriSpacing.md),
            child: _pastilleUrgence(l, index),
          ),
        ),
        // 🔴→✅ Ticket U10 — l'action du web : `@can('manage-stocks')`, puis l'édition du produit
        // (`route('stocks.produits.modifier', $id)`), « Modifier le produit ».
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: widget.peutGerer
                ? IconButton(
                    key: Key('modifier-stock-$index'),
                    tooltip: 'Modifier le produit',
                    onPressed: widget.onModifierProduit == null
                        ? null
                        : () => widget.onModifierProduit!(l.produit.id),
                    icon: const Icon(SymbolesAgri.edit, size: 16),
                    color: AgriColors.outline,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    ),
  );

  /// 🔴→✅ Ticket U9 — les DEUX pastilles du Blade : « Critique » (fond rouge plein, texte blanc, icône
  /// `priority_high`) quand le seuil est atteint, « Normal » (vert sur fond vert pâle) sinon. Le poste affichait
  /// « Sous seuil » et « Négatif », que le web n'a pas : le stock négatif se lit dans la colonne Stock.
  Widget _pastilleUrgence(LigneStock l, int index) {
    final critique = l.urgence;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: Key('urgence-$index'),
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: critique
              ? AgriColors.errorRed
              : AgriColors.brandEmerald.withValues(alpha: 0.10),
          border: Border.all(
            color: critique
                ? AgriColors.errorRed
                : AgriColors.brandEmerald.withValues(alpha: 0.30),
          ),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (critique) ...[
              const Icon(SymbolesAgri.priority_high, size: 13, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              critique ? 'Critique' : 'Normal',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: critique ? Colors.white : AgriColors.brandEmerald,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Onglet 2 : Journal des Mouvements ─────────────────────────────────────

  Widget _ongletJournal(DonneesStocks d) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // 🔴→✅ Ticket U9 — le journal est celui du web : les 100 derniers
      // mouvements du grand livre de la ferme (descendu), plus les saisies de
      // ce poste en attente d'envoi.
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
                        child: Text(
                          'QUANTITE',
                          textAlign: TextAlign.right,
                          style: _enteteColonne,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'VALEUR',
                          textAlign: TextAlign.right,
                          style: _enteteColonne,
                        ),
                      ),
                    ],
                  ),
                ),
                if (d.journal.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AgriSpacing.lg),
                    child: Text(
                      'Aucun mouvement enregistré pour le moment.',
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontStyle: FontStyle.italic,
                        color: AgriColors.outline,
                      ),
                    ),
                  ),
                for (var i = 0; i < d.journal.length; i++)
                  _ligneMouvement(d.journal[i], i),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  /// Une ligne du journal, cellule par cellule comme le Blade (ticket U9).
  Widget _ligneMouvement(LigneJournal l, int index) {
    final m = l.mouvement;
    final (type, couleurType) = switch (m.type) {
      'entree' => ('Entrée', AgriColors.brandEmerald),
      'sortie' => ('Sortie', AgriColors.errorRed),
      _ => ('Ajustement', AgriColors.accentYellow),
    };
    final sortie = m.type == 'sortie';

    return Container(
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
              l.dateHeure,
              style: const TextStyle(fontSize: AgriTypography.xs),
            ),
          ),
          // `strtoupper(substr($reference_id, 0, 8))`, « — » sans pièce.
          Expanded(
            flex: 2,
            child: Text(
              l.reference,
              key: Key('reference-mouvement-$index'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              l.designation ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: AgriColors.brandForest,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              type,
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: couleurType,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              l.motif,
              key: Key('motif-mouvement-$index'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AgriTypography.xs),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              l.quantite,
              key: Key('quantite-mouvement-$index'),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: sortie ? AgriColors.errorRed : AgriColors.brandEmerald,
              ),
            ),
          ),
          // Ticket U8 — `number_format(abs(quantité) × PMP, 0, ',', ' ').' FCFA'`
          // du Blade ; « — » sans PMP.
          Expanded(
            flex: 2,
            child: Text(
              l.valeurAffichee,
              key: Key('valeur-mouvement-$index'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: AgriTypography.xs),
            ),
          ),
        ],
      ),
    );
  }

  // ── Onglet 3 : Ajustement / Correction ────────────────────────────────────

  Widget _ongletAjustement(DonneesStocks d) {
    final choisi = d.lignes
        .where((l) => l.produit.id == _produitChoisi)
        .map((l) => l.produit)
        .firstOrNull;

    final theorique = choisi?.stockQty ?? 0;
    final ecart = StocksRepository.ecartCalcule(
      theorique: choisi?.stockQty,
      physique: double.tryParse(_physique.text.trim()),
    );

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
                        '${PmpService.quantite(l.produit.stockQty)})',
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
                      valeur: PmpService.quantite(theorique),
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
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          // 🔴→✅ Ticket U10 — l'encadré du Blade (`bg-surface-zebra rounded-lg p-sm text-center`) :
          // `{{ $adjDiff > 0 ? '+' : '' }}{{ $adjDiff }}`, soit « 0 » tant que rien n'est saisi (jamais « — »),
          // rouge si négatif, vert si positif, vert forêt à zéro.
          Container(
            padding: const EdgeInsets.all(AgriSpacing.sm),
            decoration: BoxDecoration(
              color: AgriColors.surfaceZebra,
              borderRadius: BorderRadius.circular(AgriRadius.lg),
            ),
            child: Column(
              children: [
                Text(
                  'Écart calculé'.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.outline,
                  ),
                ),
                Text(
                  StocksRepository.ecartAffiche(ecart),
                  key: const Key('adj-ecart'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: ecart < 0
                        ? AgriColors.errorDeep
                        : ecart > 0
                        ? AgriColors.brandEmerald
                        : AgriColors.brandForest,
                  ),
                ),
              ],
            ),
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

  // ── Exporter, Ajouter Stock (ticket U10) ──────────────────────────────────

  /// « Exporter » — `exportStocksPdf()` : le tableau tel qu'il est filtré à l'écran.
  Future<void> _exporter(List<LigneStock> lignes, DonneesStocks d) async {
    final editeur = widget.imprimer;
    if (editeur == null) return;
    final maintenant = d.maintenant ?? HeureBenin.maintenant();
    final message = await editeur(
      StocksRepository.documentTableau(lignes, maintenant),
      maintenant,
    );
    // Le web ne dit rien après un export réussi : seul un échec de l'éditeur s'affiche.
    if (message != null && mounted) {
      ToastAgri.afficher(context, message, type: TypeToast.erreur);
    }
  }

  /// `modal-ajouter-stock` du Blade (`max-width="sm"`), champ pour champ : « Date du Nouveau Stock * » (aujourd'hui
  /// par défaut, `mount()`), « Produit * » (produits actifs par nom), « Quantité Ajoutée * » ; erreurs sous les
  /// champs Produit et Quantité (`@error` du Blade) ; « Annuler » / « Enregistrer » ; toast « Stock ajouté avec
  /// succès. ».
  Future<void> _ouvrirAjouterStock(DonneesStocks d) async {
    // `openAddStockModal()` : produit et quantité remis à vide, date du jour.
    var date = HeureBenin.maintenant();
    String? produit;
    final quantite = _quantiteAjout..clear();
    var erreurs = <String, String>{};

    final enregistre = await afficherModale<bool>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, rafraichir) => ModaleAgri(
          titre: 'Ajouter Stock',
          largeur: LargeurModale.sm,
          contenu: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _etiquette('Date du Nouveau Stock *'),
              InkWell(
                key: const Key('ajout-date'),
                onTap: () async {
                  final choisie = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(HeureBenin.maintenant().year + 5, 12, 31),
                  );
                  if (choisie != null) rafraichir(() => date = choisie);
                },
                child: InputDecorator(
                  decoration: _decoration(),
                  child: Text(
                    '${date.day.toString().padLeft(2, '0')}/'
                    '${date.month.toString().padLeft(2, '0')}/${date.year}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: AgriSpacing.md),
              _etiquette('Produit *'),
              DropdownButtonFormField<String>(
                key: const Key('ajout-produit'),
                initialValue: produit,
                isExpanded: true,
                decoration: _decoration(),
                hint: const Text(
                  '-- Sélectionner un produit --',
                  style: TextStyle(fontSize: 14),
                ),
                items: [
                  for (final l in d.lignes)
                    DropdownMenuItem(
                      value: l.produit.id,
                      child: Text(
                        l.produit.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
                onChanged: (v) => rafraichir(() => produit = v),
              ),
              if (erreurs['produit'] != null)
                _erreurChamp('ajout-erreur-produit', erreurs['produit']!),
              const SizedBox(height: AgriSpacing.md),
              _etiquette('Quantité Ajoutée *'),
              TextField(
                key: const Key('ajout-quantite'),
                controller: quantite,
                keyboardType: TextInputType.number,
                decoration: _decoration().copyWith(hintText: 'ex : 20'),
                style: const TextStyle(fontSize: 14),
              ),
              if (erreurs['quantite'] != null)
                _erreurChamp('ajout-erreur-quantite', erreurs['quantite']!),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(
              libelle: 'Annuler',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BoutonModalePrimaire(
              key: const Key('ajout-enregistrer'),
              libelle: 'Enregistrer',
              onPressed: () async {
                final refus = StocksRepository.validerAjout(
                  date: date,
                  productId: produit,
                  quantite: quantite.text,
                );
                if (refus.isNotEmpty) {
                  rafraichir(() => erreurs = refus);
                  return;
                }
                try {
                  await widget.depot.ajouterStock(
                    date: date,
                    productId: produit,
                    quantite: quantite.text,
                  );
                } on ArgumentError catch (e) {
                  rafraichir(() => erreurs = {'produit': '${e.message}'});
                  return;
                }
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
        ToastAgri.afficher(context, 'Stock ajouté avec succès.');
      }
    }
  }

  /// `<p class="invalid-feedback">` du Blade.
  Widget _erreurChamp(String cle, String texte) => Padding(
    padding: const EdgeInsets.only(top: AgriSpacing.xs),
    child: Text(
      texte,
      key: Key(cle),
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        color: AgriColors.errorDeep,
      ),
    ),
  );

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
}
