import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/champs_date_agri.dart';
import '../../core/widgets/modale_agri.dart';
import 'caisse_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/pos-interface.html` → Caisse (POS) Desktop.
///
/// DISPOSITION DE LA MAQUETTE : colonne gauche (recherche, filtres de
/// catégorie, grille de produits) et panneau droit de 35 % « Panier de Vente »
/// — client, lignes, sous-total, remise, total, mode de règlement, montant reçu
/// et monnaie à rendre, puis « Valider la Vente ».
///
/// ⚠️ **LA BANDE EST OBLIGATOIRE POUR TOUT PRODUIT LIÉ À UNE ESPÈCE.** C'est
/// elle qui permet le contrôle de rémanence vétérinaire ET l'imputation du
/// revenu à la bande réellement vendue. La demander au moment de l'ajout est le
/// seul instant où le caissier la connaît : la reconstruire après coup
/// exigerait une heuristique.
///
/// ÉCARTS ASSUMÉS PAR RAPPORT À LA MAQUETTE :
/// 1. **Client : « Client Anonyme » uniquement.** La table `customers` ne fait
///    pas partie du contrat de synchronisation — le poste n'a donc aucun
///    fichier client à proposer. Afficher une liste vide ou inventer des noms
///    serait pire ; le champ est présent, expliqué, et désactivé.
/// 2. **« Crédit / À terme » et « Déduire de l'avance » retirés de la liste
///    des règlements.** Tous deux supposent un client identifié et un suivi de
///    créance ou d'avance que le poste ne porte pas. Les laisser produirait des
///    ventes à crédit sans débiteur — une créance envers personne.
/// 3. « Ajouter Produit Ferme » et « Livraison concernée » non repris : le
///    premier crée un référentiel (le serveur fait autorité), le second dépend
///    d'un module de livraison absent du contrat.
/// 4. **Champ « Date de la vente » AJOUTÉ au panier (ticket F0.89)**, absent de
///    la maquette (aucun champ de date, ni au panier ni dans « Vente à la
///    Pièce »). Décision CLIENT du 14/10/2026 : un SEUL champ, au PANIER, sous
///    le client — exactement comme le POS web (15.32). Ce n'est pas une dérive
///    de portage : ne pas le « corriger » vers la maquette.
class CaisseScreen extends StatefulWidget {
  const CaisseScreen({super.key, required this.depot});

  final CaisseRepository depot;

  @override
  State<CaisseScreen> createState() => _CaisseScreenState();
}

class _CaisseScreenState extends State<CaisseScreen> {
  List<Product> _catalogue = const [];
  final List<LignePanier> _panier = [];

  String _recherche = '';

  /// Catégories servies par le serveur — jamais codées en dur.
  ///
  /// ⚠️ La maquette liste sept intitulés (« Aviculture », « Cuniculture »…) en
  /// dur dans son HTML. Les recopier ferait diverger le poste du catalogue dès
  /// qu'une catégorie serait ajoutée cote serveur : un produit deviendrait
  /// invisible, filtré par une catégorie qui n'existe plus au poste.
  List<ProductCategory> _categories = const [];

  /// `null` = « Tous », le premier filtre de la maquette.
  String? _categorieChoisie;
  String _modePaiement = 'especes';
  double _remise = 0;
  double? _especesRecues;
  bool _enCours = false;

  /// F0.89 — jour de la vente choisi au panier ; défaut aujourd'hui (horloge du dépôt).
  late DateTime _dateVente = widget.depot.aujourdhui();

  /// Refus de la date choisie, affiché SOUS le champ dès le choix (comme `updatedDateVente`).
  String? _refusDate;

  /// Modes réellement acceptés — voir l'écart n° 2 du docblock.
  static const _modes = {
    'especes': 'Espèces',
    'mobile_money': 'Mobile Money',
    'virement': 'Virement bancaire',
  };

  double get _sousTotal => _panier.fold(0, (s, l) => s + l.montant);
  double get _total => _sousTotal - _remise;
  double? get _monnaie =>
      _especesRecues == null ? null : _especesRecues! - _total;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final produits = await widget.depot.catalogue();
    final categories = await widget.depot.categories();
    if (mounted) {
      setState(() {
        _catalogue = produits;
        _categories = categories;
      });
    }
  }

  List<Product> get _produitsFiltres {
    var produits = _catalogue;

    // ⚠️ LES DEUX FILTRES SE CUMULENT, comme dans la maquette : chercher un
    // nom dans une catégorie choisie doit rester possible.
    final categorie = _categorieChoisie;
    if (categorie != null) {
      produits = produits.where((p) => p.categoryId == categorie).toList();
    }

    if (_recherche.trim().isEmpty) return produits;
    final q = _recherche.toLowerCase();
    return produits
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _ajouter(Product produit) async {
    String? lotId;

    // ⚠️ Produit lié à une espèce : la bande est EXIGÉE, comme à la caisse web.
    if (produit.speciesId != null) {
      final bandes = await widget.depot.bandesDe(produit.speciesId!);
      if (!mounted) return;

      if (bandes.isEmpty) {
        _dire(
          'Aucune bande pour ce produit sur ce poste. Lancez une '
          'synchronisation.',
          erreur: true,
        );
        return;
      }

      lotId = await afficherModale<String>(
        context: context,
        constructeur: (_) => _DialogueBande(bandes: bandes),
      );

      // Annuler la désignation annule l'ajout : jamais de ligne sans bande
      // pour un produit qui en exige une.
      if (lotId == null) return;
    }

    if (!mounted) return;

    final saisie = await afficherModale<(int, double)>(
      context: context,
      constructeur: (_) => _DialogueQuantite(produit: produit),
    );

    if (saisie == null || !mounted) return;

    setState(() {
      _panier.add(
        LignePanier(
          produit: produit,
          quantite: saisie.$1,
          montant: saisie.$2,
          lotId: lotId,
        ),
      );
    });
  }

  /// Modale « Vente Enregistrée » — `pos-interface.html`, l. 275-280.
  ///
  /// ⚠️⚠️ **UNE MODALE, PAS UN BANDEAU FUGACE.** La maquette confirme la vente
  /// par une modale portant sa RÉFÉRENCE. Un `SnackBar` disparaît en trois
  /// secondes : un caissier qui se retourne vers son client ne l'a pas vue, et
  /// n'a plus aucun moyen de retrouver la référence de la vente qu'il vient
  /// d'encaisser. C'est exactement l'instant où il en a besoin.
  ///
  /// ⚠️ **« Télécharger la Facture » N'EST PAS REPRIS**, et c'est dit à
  /// l'écran : la facture PDF est produite par le serveur, à partir du plan
  /// comptable et des mentions légales que le poste ne porte pas. Un bouton qui
  /// ne produirait rien serait pire que son absence.
  Future<void> _confirmerVente(Sale vente) async {
    // ⚠️ `modal-sale-success` de `pos-interface.html` l.? — gabarit de
    // CONFIRMATION : centré, icône de 52 px, sans ✕, boutons empilés sur
    // toute la largeur, voile `bg-black/60`.
    await afficherModale<void>(
      context: context,
      confirmation: true,
      constructeur: (contexte) => ModaleConfirmation(
        key: const Key('modale-vente-enregistree'),
        icone: SymbolesAgri.check_circle,
        titre: 'Vente Enregistrée',
        message:
            'Enregistrée sur ce poste — elle partira à la prochaine '
            'synchronisation.',
        detail: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Référence : ${vente.id}',
              key: const Key('reference-vente'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontFamily: 'monospace',
                color: AgriColors.onSurface,
              ),
            ),
            const SizedBox(height: AgriSpacing.sm),
            // ⚠️ La facture PDF est produite par le serveur : le poste ne
            // peut pas la fabriquer, et le dire évite de la chercher.
            const Text(
              'La facture PDF est produite par le serveur : elle sera '
              "téléchargeable depuis l'application web une fois la vente "
              'synchronisée.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: AgriColors.outline),
            ),
          ],
        ),
        actions: [
          BoutonModalePrimaire(
            key: const Key('bouton-nouvelle-vente'),
            libelle: 'Nouvelle Vente',
            onPressed: () => Navigator.of(contexte).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _valider() async {
    if (_panier.isEmpty || _enCours) return;

    setState(() => _enCours = true);

    try {
      final vente = await widget.depot.enregistrerVente(
        panier: List.of(_panier),
        modePaiement: _modePaiement,
        remise: _remise,
        especesRecues: _especesRecues,
        dateVente: _dateVente,
      );

      if (!mounted) return;

      setState(() {
        _panier.clear();
        _remise = 0;
        _especesRecues = null;
        // Après une vente, le champ revient à aujourd'hui (comme le POS web) : une date
        // antérieure ne doit jamais « coller » à la vente suivante.
        _dateVente = widget.depot.aujourdhui();
        _refusDate = null;
      });

      await _confirmerVente(vente);

      await _charger();
    } on VenteRefusee catch (e) {
      // ⚠️ Le refus sanitaire est montré tel quel, sans reformulation : le
      // caissier doit pouvoir citer le motif à son responsable.
      if (mounted) {
        // F0.89 — un refus de DATE se relit aussi sous le champ.
        final refusDate = await widget.depot.refusDeDate(_dateVente);
        if (!mounted) return;
        setState(() => _refusDate = refusDate);
        _dire(e.message, erreur: true);
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _dire(String message, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: erreur
            ? AgriColors.errorDeep
            : AgriColors.brandEmerald,
        duration: Duration(seconds: erreur ? 8 : 4),
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 65, child: _colonneProduits()),
          const VerticalDivider(width: 1),
          SizedBox(width: 340, child: _panneauPanier()),
        ],
      ),
    );
  }

  Widget _colonneProduits() {
    final produits = _produitsFiltres;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AgriSpacing.md),
          child: TextField(
            key: const Key('recherche-produit'),
            onChanged: (v) => setState(() => _recherche = v),
            style: const TextStyle(fontSize: AgriTypography.xs),
            decoration: const InputDecoration(
              hintText: 'Rechercher un produit...',
              hintStyle: TextStyle(fontSize: AgriTypography.xs),
              prefixIcon: Icon(SymbolesAgri.search, size: 18),
            ),
          ),
        ),
        _filtresCategories(),
        Expanded(
          child: produits.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AgriSpacing.lg),
                    child: Text(
                      'Aucun produit sur ce poste.\n'
                      'Le catalogue provient du serveur : lancez une synchronisation.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        color: AgriColors.outline,
                      ),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(AgriSpacing.md),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 108,
                    crossAxisSpacing: AgriSpacing.sm,
                    mainAxisSpacing: AgriSpacing.sm,
                  ),
                  itemCount: produits.length,
                  itemBuilder: (_, i) => _carteProduit(produits[i]),
                ),
        ),
      ],
    );
  }

  /// Filtres de catégorie — « Tous » puis les catégories du serveur.
  ///
  /// ⚠️ SANS EUX, LE CAISSIER FAIT DÉFILER TOUT LE CATALOGUE. La maquette les
  /// place juste sous la recherche ; ils étaient annoncés dans la description
  /// de cet écran mais n'avaient jamais été construits.
  Widget _filtresCategories() {
    if (_categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md),
        children: [
          _puceCategorie(null, 'Tous'),
          for (final c in _categories) _puceCategorie(c.id, c.label),
        ],
      ),
    );
  }

  Widget _puceCategorie(String? id, String libelle) {
    final actif = _categorieChoisie == id;

    return Padding(
      padding: const EdgeInsets.only(right: AgriSpacing.xs),
      child: InkWell(
        key: Key('categorie-${id ?? 'tous'}'),
        onTap: () => setState(() => _categorieChoisie = id),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: actif ? AgriColors.brandEmerald : Colors.white,
            border: Border.all(
              color: actif
                  ? AgriColors.brandEmerald
                  : AgriColors.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            libelle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: actif ? Colors.white : AgriColors.brandForest,
            ),
          ),
        ),
      ),
    );
  }

  Widget _carteProduit(Product produit) {
    final rupture = produit.stockQty <= 0;

    return InkWell(
      key: Key('produit-${produit.sku}'),
      onTap: () => _ajouter(produit),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(AgriSpacing.sm),
        decoration: BoxDecoration(
          color: AgriColors.surfaceCard,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              produit.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: AgriColors.brandForest,
              ),
            ),
            // ⚠️ LES DEUX TEXTES SONT SOUPLES. Une unite longue (« plateau »)
            // faisait deborder la carte : le libelle etait alors rogne a
            // l'ecran, sans que rien ne le signale hors des tests.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    produit.sku,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AgriColors.outline,
                    ),
                  ),
                ),
                // ⚠️ Le stock est AFFICHÉ, jamais bloquant : au comptoir la
                // marchandise est déjà dans les mains du client.
                Flexible(
                  child: Text(
                    '${_nombre(produit.stockQty)} ${produit.unit}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: rupture
                          ? AgriColors.errorDeep
                          : AgriColors.brandEmerald,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _panneauPanier() {
    return Container(
      color: AgriColors.surfaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AgriSpacing.md),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Panier de Vente',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AgriColors.brandEmerald,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${_panier.length}',
                    key: const Key('compteur-panier'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AgriSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CLIENT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
                const SizedBox(height: AgriSpacing.xs),
                // ⚠️ Le fichier client ne fait pas partie du contrat de
                // synchronisation : le champ est présent mais désactivé,
                // plutôt qu'une liste vide ou des noms inventés.
                const TextField(
                  enabled: false,
                  decoration: InputDecoration(
                    hintText: 'Client Anonyme',
                    helperText: 'Fichier client non synchronisé sur ce poste',
                    helperStyle: TextStyle(fontSize: 9),
                  ),
                ),
                const SizedBox(height: AgriSpacing.sm),
                _champDateVente(),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _lignesPanier()),
          const Divider(height: 1),
          _totaux(),
        ],
      ),
    );
  }

  /// 🔴→✅ TICKET F0.89 — « Date de la vente » (écart ASSUMÉ n° 4 du docblock).
  ///
  /// Même famille que le champ de période du Grand Livre (F0.85) : un clic ouvre le
  /// calendrier, la date s'affiche en JJ/MM/AAAA. Bornes INDICATIVES (comme le POS web) : du
  /// début du plus ancien exercice ouvert connu à aujourd'hui ; le dépôt juge, le serveur
  /// re-juge. Un refus s'affiche SOUS le champ dès le choix, sans attendre la validation.
  Widget _champDateVente() => ChampDateFormulaire(
    cle: const Key('date-vente'),
    etiquette: 'Date de la vente',
    valeur: _dateVente,
    caisse: true,
    onTap: _choisirDateVente,
    erreur: _refusDate,
    cleErreur: const Key('date-vente-erreur'),
    // `text-[10px] text-outline mt-xs` du POS web (15.32), mot pour mot : au poste, l'écriture et la créance sont
    // datées par le serveur à la synchronisation, le stock et la fiche dès maintenant.
    aide: _dateVente.isBefore(widget.depot.aujourdhui())
        ? 'Vente antérieure : écriture, stock, créance et fiche seront datés du ${_jourFr(_dateVente)}.'
        : null,
    cleAide: const Key('date-vente-aide'),
  );

  Future<void> _choisirDateVente() async {
    final bornes = await widget.depot.bornesDateVente();
    if (!mounted) return;

    final dernier = bornes.dernier;
    var premier = bornes.premier ?? DateTime(2000);
    // Exercice ouvert qui commencerait après aujourd'hui : le calendrier exige premier ≤ dernier.
    if (premier.isAfter(dernier)) premier = dernier;

    var initial = _dateVente;
    if (initial.isBefore(premier)) initial = premier;
    if (initial.isAfter(dernier)) initial = dernier;

    final choisie = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: premier,
      lastDate: dernier,
    );
    if (choisie == null || !mounted) return;

    final refus = await widget.depot.refusDeDate(choisie);
    if (!mounted) return;

    setState(() {
      _dateVente = DateTime(choisie.year, choisie.month, choisie.day);
      _refusDate = refus;
    });
  }

  static String _jourFr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _lignesPanier() {
    if (_panier.isEmpty) {
      // ⚠️ DÉFILANT AUSSI. Sur une fenêtre courte, le bloc des totaux comprime
      // cette zone jusqu'à ce que l'état vide ne tienne plus — Flutter le
      // tronque alors en silence en release. Un écran de caisse doit rester
      // lisible quelle que soit la hauteur de la fenêtre.
      return const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AgriSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                SymbolesAgri.shopping_cart,
                size: 48,
                color: AgriColors.outlineVariant,
              ),
              SizedBox(height: AgriSpacing.sm),
              Text(
                'Le panier est vide.\nSélectionnez un produit pour commencer.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AgriSpacing.md),
      itemCount: _panier.length,
      separatorBuilder: (_, _) => const SizedBox(height: AgriSpacing.sm),
      itemBuilder: (_, i) {
        final ligne = _panier[i];

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ligne.produit.name,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                  Text(
                    '${ligne.quantite} × ${_nombre(ligne.prixUnitaire)} FCFA',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AgriColors.outline,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${_nombre(ligne.montant)} FCFA',
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              key: Key('retirer-$i'),
              icon: const Icon(SymbolesAgri.close, size: 16),
              color: AgriColors.errorDeep,
              onPressed: () => setState(() => _panier.removeAt(i)),
            ),
          ],
        );
      },
    );
  }

  Widget _totaux() {
    // ⚠️ DÉFILANT, ET PAS SEULEMENT POUR LE CONFORT. Sur une fenêtre courte
    // (800 x 600 reste une taille plausible au comptoir), ce bloc déborde :
    // Flutter tronque alors le bas — c'est-à-dire le bouton « Valider la
    // Vente ». Une caisse dont le bouton de validation disparaît selon la
    // hauteur de la fenêtre est inutilisable, et rien ne le signale à
    // l'exécution en release.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AgriSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ligneTotal('Sous-total', '${_nombre(_sousTotal)} FCFA'),
          const SizedBox(height: AgriSpacing.xs),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Remise (FCFA)',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.outline,
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: TextField(
                  key: const Key('remise'),
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: AgriTypography.xs),
                  onChanged: (v) =>
                      setState(() => _remise = double.tryParse(v) ?? 0),
                ),
              ),
            ],
          ),
          const Divider(),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total à Payer',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AgriColors.brandForest,
                  ),
                ),
              ),
              Text(
                '${_nombre(_total)} FCFA',
                key: const Key('total-a-payer'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AgriColors.brandEmerald,
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          DropdownButtonFormField<String>(
            key: const Key('mode-reglement'),
            initialValue: _modePaiement,
            decoration: const InputDecoration(labelText: 'Mode de Règlement'),
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.onSurface,
            ),
            items: [
              for (final e in _modes.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _modePaiement = v ?? 'especes'),
          ),
          const SizedBox(height: AgriSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('montant-recu'),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: AgriTypography.xs),
                  decoration: const InputDecoration(labelText: 'Montant Reçu'),
                  onChanged: (v) =>
                      setState(() => _especesRecues = double.tryParse(v)),
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MONNAIE À RENDRE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AgriColors.outline,
                      ),
                    ),
                    const SizedBox(height: AgriSpacing.xs),
                    Text(
                      _monnaie == null ? '—' : '${_nombre(_monnaie!)} FCFA',
                      key: const Key('monnaie'),
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        // Un rendu négatif signale un paiement insuffisant.
                        color: (_monnaie ?? 0) < 0
                            ? AgriColors.errorDeep
                            : AgriColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AgriSpacing.sm),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              key: const Key('valider-vente'),
              onPressed: (_panier.isEmpty || _enCours) ? null : _valider,
              icon: const Icon(SymbolesAgri.point_of_sale, size: 18),
              label: const Text('Valider la Vente'),
              style: FilledButton.styleFrom(
                backgroundColor: AgriColors.brandEmerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligneTotal(String libelle, String valeur) {
    return Row(
      children: [
        Expanded(
          child: Text(
            libelle,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
        ),
        Text(
          valeur,
          style: const TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Séparateur de milliers par espace insécable fine, usage francophone.
  static String _nombre(double v) {
    final entier = v.round().abs().toString();
    final morceaux = <String>[];

    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }

    return '${v.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }
}

/// Désignation de la bande vendue — exigée pour tout produit lié à une espèce.
class _DialogueBande extends StatelessWidget {
  const _DialogueBande({required this.bandes});

  final List<LivestockLot> bandes;

  @override
  Widget build(BuildContext context) {
    return ModaleAgri(
      titre: 'Bande source',
      largeur: LargeurModale.sm,
      contenu: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Obligatoire pour un sujet vivant : elle permet le contrôle de '
              'rémanence vétérinaire et l\'imputation du revenu à la bande.',
              style: TextStyle(fontSize: 11, color: AgriColors.outline),
            ),
            const SizedBox(height: AgriSpacing.sm),
            for (final b in bandes)
              ListTile(
                key: Key('bande-${b.code}'),
                dense: true,
                title: Text(
                  b.code,
                  style: const TextStyle(fontSize: AgriTypography.xs),
                ),
                subtitle: Text(
                  '${b.currentQuantity} sujets',
                  style: const TextStyle(fontSize: 10),
                ),
                onTap: () => Navigator.of(context).pop(b.id),
              ),
          ],
        ),
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Quantité et montant de la ligne.
///
/// ⚠️ LE MONTANT EST SAISI, PAS DÉDUIT D'UN PRIX UNITAIRE : les produits en
/// fourchette se négocient au montant, et repartir d'un prix unitaire arrondi
/// ferait dériver le total de la vente.
class _DialogueQuantite extends StatefulWidget {
  const _DialogueQuantite({required this.produit});

  final Product produit;

  @override
  State<_DialogueQuantite> createState() => _DialogueQuantiteState();
}

class _DialogueQuantiteState extends State<_DialogueQuantite> {
  int _quantite = 1;
  double _montant = 0;

  @override
  void initState() {
    super.initState();
    // Amorce au prix plancher du catalogue, que le caissier ajuste ensuite
    // dans la fourchette négociée.
    _montant = widget.produit.priceMin ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.produit;
    final fourchette = p.priceMin != null && p.priceMax != null
        ? 'Fourchette : ${p.priceMin!.round()} – ${p.priceMax!.round()} FCFA'
        : null;

    return ModaleAgri(
      // ⚠️ « Vente à la Pièce » est l'intitulé de l'opération dans la
      // maquette ; le nom du produit vient dessous. Les deux libellés
      // restent séparés : les fusionner en remplacerait deux par un
      // troisième, qui n'existe nulle part.
      surtitre: 'Vente à la Pièce',
      titre: p.name,
      contenu: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fourchette != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  fourchette,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            const SizedBox(height: AgriSpacing.sm),
            TextFormField(
              key: const Key('saisie-quantite'),
              initialValue: '1',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nombre de sujets / Quantité',
              ),
              onChanged: (v) =>
                  setState(() => _quantite = int.tryParse(v) ?? 0),
            ),
            const SizedBox(height: AgriSpacing.sm),
            TextFormField(
              key: const Key('saisie-montant'),
              initialValue: _montant.round().toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Montant Global de la Vente (FCFA)',
              ),
              onChanged: (v) =>
                  setState(() => _montant = double.tryParse(v) ?? 0),
            ),
          ],
        ),
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BoutonModalePrimaire(
          key: const Key('confirmer-ligne'),
          libelle: 'Ajouter au panier',
          // Une quantité ou un montant nuls ne produisent pas de ligne.
          onPressed: (_quantite <= 0 || _montant <= 0)
              ? null
              : () => Navigator.of(context).pop((_quantite, _montant)),
        ),
      ],
    );
  }
}
