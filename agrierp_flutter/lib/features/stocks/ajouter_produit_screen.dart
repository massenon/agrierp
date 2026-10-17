import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import 'produits_repository.dart';

/// `prototype_html/ajouter-produit.html` → « Ajouter un Produit » / « Modifier le
/// Produit » (Laravel : `Livewire\Stocks\AjouterProduit`).
///
/// ⚠️⚠️ **ENREGISTREMENT LOCAL, SYNCHRONISÉ ENSUITE.** Le produit est écrit tout de
/// suite dans la base du poste (`pending`) : le poste est hors ligne par nature. Le
/// serveur le valide à la synchronisation et attribue le SKU définitif ; un refus se
/// lit à l'écran de synchronisation.
///
/// ⚠️ **LA QUANTITÉ N'EST SAISISSABLE QU'À LA CRÉATION** (« Stock Initial »). En
/// modification le champ est absent : un stock se corrige par un ajustement
/// d'inventaire, qui laisse une trace — éditer la quantité à la main changerait un
/// solde sans mouvement.
///
/// ⚠️ **ÉCART ASSUMÉ AVEC LE GABARIT DU PROTOTYPE** : `ajouter-produit.html` porte un
/// seul « Prix unitaire (FCFA) » ; la règle métier est « Fourchette » ou « Sur
/// devis », comme la modale de `catalogue-view.html` et comme Laravel.
class AjouterProduitScreen extends StatefulWidget {
  const AjouterProduitScreen({
    super.key,
    required this.depot,
    this.produitId,
    required this.onTermine,
  });

  final ProduitsRepository depot;

  /// `null` : création.
  final String? produitId;

  /// Appelé au retour (annulation ou enregistrement réussi).
  final void Function({required bool enregistre}) onTermine;

  @override
  State<AjouterProduitScreen> createState() => _AjouterProduitScreenState();
}

class _AjouterProduitScreenState extends State<AjouterProduitScreen> {
  final _nom = TextEditingController();
  final _unite = TextEditingController(text: 'u');
  final _prixMin = TextEditingController();
  final _prixMax = TextEditingController();
  final _stock = TextEditingController(text: '0');
  final _seuil = TextEditingController(text: '0');
  final _tva = TextEditingController(text: '0');
  final _description = TextEditingController();

  List<ProductCategory> _categories = const [];
  List<EspeceElevage> _especes = const [];
  String _categorie = '';
  String _espece = '';
  String _mode = 'fourchette';

  Map<String, String> _erreurs = const {};
  String? _echec;
  bool _charge = false;
  bool _envoi = false;

  bool get _creation => widget.produitId == null;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final c in [
      _nom,
      _unite,
      _prixMin,
      _prixMax,
      _stock,
      _seuil,
      _tva,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    final categories = await widget.depot.categories();
    final especes = await widget.depot.especes();
    final existant = _creation
        ? null
        : await widget.depot.produit(widget.produitId!);
    if (!mounted) return;

    setState(() {
      _categories = categories;
      _especes = especes;
      if (existant != null) {
        _nom.text = existant.name;
        _unite.text = existant.unit;
        _categorie = existant.categoryId ?? '';
        _espece = existant.speciesId ?? '';
        _mode = existant.pricingMode == 'fourchette' ? 'fourchette' : 'quote';
        _prixMin.text = _texte(existant.priceMin);
        _prixMax.text = _texte(existant.priceMax);
        _seuil.text = _texte(existant.alertThreshold) == ''
            ? '0'
            : _texte(existant.alertThreshold);
        _tva.text = _texte(existant.tvaRate);
        _description.text = existant.description ?? '';
      }
      _charge = true;
    });
  }

  static String _texte(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

  static double? _nombre(String t) =>
      double.tryParse(t.trim().replaceAll(',', '.'));

  FormulaireProduit _saisie() => FormulaireProduit(
    nom: _nom.text,
    categorieId: _categorie,
    especeId: _espece,
    unite: _unite.text,
    mode: _mode,
    prixMin: _nombre(_prixMin.text),
    prixMax: _nombre(_prixMax.text),
    stock: _nombre(_stock.text) ?? 0,
    seuil: _nombre(_seuil.text) ?? 0,
    tva: _nombre(_tva.text) ?? 0,
    description: _description.text,
  );

  Future<void> _enregistrer() async {
    final saisie = _saisie();
    final erreurs = ProduitsRepository.valider(saisie, creation: _creation);

    if (erreurs.isNotEmpty) {
      setState(() {
        _erreurs = erreurs;
        _echec = null;
      });
      return;
    }

    setState(() {
      _envoi = true;
      _erreurs = const {};
      _echec = null;
    });

    if (_creation) {
      await widget.depot.creer(saisie);
    } else {
      await widget.depot.modifier(widget.produitId!, saisie);
    }
    if (!mounted) return;
    widget.onTermine(enregistre: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_charge) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AgriSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _creation ? Icons.add_box : Icons.edit,
                    color: AgriColors.brandForest,
                  ),
                  const SizedBox(width: AgriSpacing.sm),
                  Text(
                    _creation ? 'Ajouter un Produit' : 'Modifier le Produit',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AgriSpacing.xs),
              Text(
                _creation
                    ? "Création d'une nouvelle référence dans le catalogue "
                          'produits de la ferme.'
                    : "Modification d'une référence existante du catalogue.",
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
              const SizedBox(height: AgriSpacing.lg),
              // ⚠️ `Material` ET NON `Container` décoré : un `RadioListTile` peint
              // son fond sur le Material le plus proche, qu'un fond intermédiaire
              // masquerait.
              Material(
                color: AgriColors.surfaceCard,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AgriColors.outlineVariant),
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AgriSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _champ(
                        'Nom du produit *',
                        'nom',
                        _nom,
                        indice: 'ex : Œufs de table (plateau de 30)',
                      ),
                      _liste(
                        'Catégorie *',
                        'categorie',
                        _categorie,
                        '-- Sélectionner --',
                        {for (final c in _categories) c.id: c.label},
                        (v) => setState(() => _categorie = v),
                      ),
                      _liste(
                        "Filière d'élevage (si applicable)",
                        'espece',
                        _espece,
                        '-- Aucune --',
                        {for (final e in _especes) e.id: e.label},
                        (v) => setState(() => _espece = v),
                      ),
                      _champ(
                        'Unité de comptage *',
                        'unite',
                        _unite,
                        indice: 'ex : u, sac, plateau',
                        aide:
                            'Toujours une unité de pièce/comptage — jamais une '
                            'unité de poids (kg).',
                      ),
                      _tarification(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_creation)
                            Expanded(
                              child: _champ(
                                'Stock Initial',
                                'stock',
                                _stock,
                                numerique: true,
                              ),
                            ),
                          if (_creation) const SizedBox(width: AgriSpacing.md),
                          Expanded(
                            child: _champ(
                              "Seuil d'Alerte",
                              'seuil',
                              _seuil,
                              numerique: true,
                            ),
                          ),
                          const SizedBox(width: AgriSpacing.md),
                          Expanded(
                            child: _champ(
                              'TVA (%)',
                              'tva',
                              _tva,
                              numerique: true,
                            ),
                          ),
                        ],
                      ),
                      if (!_creation)
                        const Padding(
                          padding: EdgeInsets.only(bottom: AgriSpacing.md),
                          child: Text(
                            'La quantité en stock ne se modifie pas ici : '
                            'passez par un ajustement (Gestion des Stocks).',
                            key: Key('produit-stock-ajustement'),
                            style: TextStyle(
                              fontSize: AgriTypography.xs,
                              color: AgriColors.outline,
                            ),
                          ),
                        ),
                      _champ(
                        'Description',
                        'description',
                        _description,
                        lignes: 3,
                      ),
                      if (_echec != null)
                        Container(
                          key: const Key('produit-echec'),
                          margin: const EdgeInsets.only(bottom: AgriSpacing.md),
                          padding: const EdgeInsets.all(AgriSpacing.sm),
                          decoration: BoxDecoration(
                            color: AgriColors.errorDeep.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(AgriRadius.lg),
                          ),
                          child: Text(
                            _echec!,
                            style: const TextStyle(
                              fontSize: AgriTypography.xs,
                              color: AgriColors.errorDeep,
                            ),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            key: const Key('produit-annuler'),
                            onPressed: _envoi
                                ? null
                                : () => widget.onTermine(enregistre: false),
                            child: const Text('Annuler'),
                          ),
                          const SizedBox(width: AgriSpacing.sm),
                          FilledButton(
                            key: const Key('produit-enregistrer'),
                            onPressed: _envoi ? null : _enregistrer,
                            style: FilledButton.styleFrom(
                              backgroundColor: AgriColors.brandEmerald,
                            ),
                            child: Text(
                              _creation
                                  ? 'Enregistrer'
                                  : 'Enregistrer les modifications',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarification() => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mode de Tarification *',
          style: TextStyle(
            fontSize: AgriTypography.xs,
            fontWeight: FontWeight.bold,
          ),
        ),
        RadioGroup<String>(
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v ?? _mode),
          child: Row(
            children: [
              for (final (valeur, titre) in const [
                ('fourchette', 'Fourchette'),
                ('quote', 'Sur devis'),
              ])
                Expanded(
                  child: RadioListTile<String>(
                    key: Key('produit-mode-$valeur'),
                    value: valeur,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      titre,
                      style: const TextStyle(fontSize: AgriTypography.xs),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_mode == 'fourchette')
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _champ(
                  'Prix Min (FCFA) *',
                  'prixMin',
                  _prixMin,
                  indice: 'ex : 3000',
                  numerique: true,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AgriSpacing.sm,
                  28,
                  AgriSpacing.sm,
                  0,
                ),
                child: Text('à'),
              ),
              Expanded(
                child: _champ(
                  'Prix Max (FCFA) *',
                  'prixMax',
                  _prixMax,
                  indice: 'ex : 4000',
                  numerique: true,
                ),
              ),
            ],
          )
        else
          const Text(
            'Ce produit sera vendu sur devis (ex. cages sur mesure) — aucun '
            'prix indicatif à saisir ici.',
            key: Key('produit-sur-devis'),
            style: TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
          ),
      ],
    ),
  );

  Widget _champ(
    String libelle,
    String cle,
    TextEditingController c, {
    String? indice,
    String? aide,
    bool numerique = false,
    int lignes = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
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
        TextField(
          key: Key('produit-$cle'),
          controller: c,
          maxLines: lignes,
          keyboardType: numerique ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontSize: AgriTypography.xs),
          decoration: InputDecoration(
            hintText: indice,
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: _erreurs[cle],
          ),
        ),
        if (aide != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              aide,
              style: const TextStyle(fontSize: 11, color: AgriColors.outline),
            ),
          ),
      ],
    ),
  );

  Widget _liste(
    String libelle,
    String cle,
    String valeur,
    String vide,
    Map<String, String> options,
    void Function(String) auChoix,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
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
        DropdownButtonFormField<String>(
          key: Key('produit-$cle'),
          initialValue: options.containsKey(valeur) ? valeur : '',
          isDense: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _erreurs[cle],
          ),
          items: [
            DropdownMenuItem(value: '', child: Text(vide)),
            for (final e in options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => auChoix(v ?? ''),
        ),
      ],
    ),
  );
}
