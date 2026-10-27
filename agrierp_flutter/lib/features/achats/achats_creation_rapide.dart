import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import '../stocks/produits_repository.dart';
import 'fournisseurs_repository.dart';

/// Ticket AC-2 — LES BOUTONS « + » DE `EnregistrerAchat` (`saveNewSupplier`, `saveNewProduct`).
///
/// Le web crée à la volée un fournisseur (raison sociale, téléphone) ou un produit (nom, catégorie, unité) sans quitter
/// l'achat, puis le sélectionne. Le poste fait de même, EN LOCAL, `pending` : la fiche passe par les dépôts propriétaires
/// ([FournisseursRepository], [ProduitsRepository]) et le serveur la valide à la synchronisation.
///
/// ⚠️ **LA CATÉGORIE DU FOURNISSEUR** : le serveur l'exige à l'envoi (`SupplierCatalogService`) ; le formulaire du web ne
/// la demande pas, il enregistre « Autre » — le poste de même, pour que la fiche ne soit pas refusée.
/// ⚠️ **LA TARIFICATION DU PRODUIT** se complète ensuite au Catalogue (fourchette 0 – 0, TVA 0, stock 0, seuil 0, comme le
/// web).
const categorieFournisseurRapide = 'Autre';

/// « Nouveau Fournisseur » : retourne la fiche écrite, ou `null` si l'utilisateur annule.
Future<Supplier?> ouvrirNouveauFournisseurRapide({
  required BuildContext context,
  required FournisseursRepository depot,
}) => afficherModale<Supplier>(
  context: context,
  constructeur: (_) => _ModaleFournisseurRapide(depot: depot),
);

/// « Nouveau Produit » : retourne la fiche écrite, ou `null` si l'utilisateur annule.
Future<Product?> ouvrirNouveauProduitRapide({
  required BuildContext context,
  required ProduitsRepository depot,
}) => afficherModale<Product>(
  context: context,
  constructeur: (_) => _ModaleProduitRapide(depot: depot),
);

Widget _champ({
  required String etiquette,
  required Widget champ,
  String? erreur,
  Key? cleErreur,
}) => Padding(
  padding: const EdgeInsets.only(bottom: AgriSpacing.md),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
        child: Text(
          etiquette.toUpperCase(),
          style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest),
        ),
      ),
      champ,
      if (erreur != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(erreur, key: cleErreur, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
        ),
    ],
  ),
);

const _decoration = InputDecoration(isDense: true, border: OutlineInputBorder());

class _ModaleFournisseurRapide extends StatefulWidget {
  const _ModaleFournisseurRapide({required this.depot});

  final FournisseursRepository depot;

  @override
  State<_ModaleFournisseurRapide> createState() => _ModaleFournisseurRapideState();
}

class _ModaleFournisseurRapideState extends State<_ModaleFournisseurRapide> {
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  String? _refusNom;
  String? _refusTelephone;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final nom = _nom.text.trim();
    final telephone = _telephone.text.trim();
    setState(() {
      _refusNom = nom.isEmpty
          ? 'Le champ raison sociale est obligatoire.'
          : nom.length > 150
          ? 'Le champ raison sociale ne doit pas dépasser 150 caractères.'
          : null;
      _refusTelephone = telephone.isEmpty
          ? 'Le champ téléphone est obligatoire.'
          : telephone.length > 30
          ? 'Le champ téléphone ne doit pas dépasser 30 caractères.'
          : null;
    });
    if (_refusNom != null || _refusTelephone != null) return;

    final fiche = await widget.depot.creerFournisseur(
      FormulaireFournisseur(nom: nom, categorie: categorieFournisseurRapide, telephone: telephone),
    );
    if (mounted) Navigator.of(context).pop(fiche);
  }

  @override
  Widget build(BuildContext context) => ModaleAgri(
    titre: 'Nouveau Fournisseur',
    largeur: LargeurModale.sm,
    contenu: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _champ(
          etiquette: 'Raison sociale *',
          erreur: _refusNom,
          cleErreur: const Key('rapide-fournisseur-erreur-nom'),
          champ: TextField(key: const Key('rapide-fournisseur-nom'), controller: _nom, decoration: _decoration),
        ),
        _champ(
          etiquette: 'Téléphone *',
          erreur: _refusTelephone,
          cleErreur: const Key('rapide-fournisseur-erreur-telephone'),
          champ: TextField(
            key: const Key('rapide-fournisseur-telephone'),
            controller: _telephone,
            keyboardType: TextInputType.phone,
            decoration: _decoration,
          ),
        ),
      ],
    ),
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
      BoutonModalePrimaire(key: const Key('rapide-fournisseur-enregistrer'), libelle: 'Enregistrer', onPressed: _enregistrer),
    ],
  );
}

class _ModaleProduitRapide extends StatefulWidget {
  const _ModaleProduitRapide({required this.depot});

  final ProduitsRepository depot;

  @override
  State<_ModaleProduitRapide> createState() => _ModaleProduitRapideState();
}

class _ModaleProduitRapideState extends State<_ModaleProduitRapide> {
  final _nom = TextEditingController();
  final _unite = TextEditingController(text: 'u');
  List<ProductCategory> _categories = const [];
  String _categorieId = '';
  String? _refusNom;
  String? _refusCategorie;
  String? _refusUnite;

  @override
  void initState() {
    super.initState();
    widget.depot.categories().then((c) {
      if (mounted) setState(() => _categories = c);
    });
  }

  @override
  void dispose() {
    _nom.dispose();
    _unite.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final nom = _nom.text.trim();
    final unite = _unite.text.trim();
    setState(() {
      _refusNom = nom.isEmpty
          ? 'Le champ nom du produit est obligatoire.'
          : nom.length > 150
          ? 'Le champ nom du produit ne doit pas dépasser 150 caractères.'
          : null;
      _refusCategorie = _categorieId.isEmpty ? 'Le champ catégorie est obligatoire.' : null;
      _refusUnite = unite.isEmpty
          ? "Le champ unité est obligatoire."
          : unite.length > 20
          ? "Le champ unité ne doit pas dépasser 20 caractères."
          : null;
    });
    if (_refusNom != null || _refusCategorie != null || _refusUnite != null) return;

    final fiche = await widget.depot.creer(
      FormulaireProduit(
        nom: nom,
        categorieId: _categorieId,
        unite: unite,
        mode: 'fourchette',
        prixMin: 0,
        prixMax: 0,
      ),
    );
    if (mounted) Navigator.of(context).pop(fiche);
  }

  @override
  Widget build(BuildContext context) => ModaleAgri(
    titre: 'Nouveau Produit',
    largeur: LargeurModale.sm,
    contenu: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _champ(
          etiquette: 'Nom du produit *',
          erreur: _refusNom,
          cleErreur: const Key('rapide-produit-erreur-nom'),
          champ: TextField(key: const Key('rapide-produit-nom'), controller: _nom, decoration: _decoration),
        ),
        _champ(
          etiquette: 'Catégorie *',
          erreur: _refusCategorie,
          cleErreur: const Key('rapide-produit-erreur-categorie'),
          champ: DropdownButtonFormField<String>(
            key: const Key('rapide-produit-categorie'),
            initialValue: _categorieId,
            isDense: true,
            isExpanded: true,
            decoration: _decoration,
            style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
            items: [
              const DropdownMenuItem(value: '', child: Text('-- Sélectionner --')),
              for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _categorieId = v ?? ''),
          ),
        ),
        _champ(
          etiquette: 'Unité',
          erreur: _refusUnite,
          cleErreur: const Key('rapide-produit-erreur-unite'),
          champ: TextField(key: const Key('rapide-produit-unite'), controller: _unite, decoration: _decoration),
        ),
        Container(
          padding: const EdgeInsets.all(AgriSpacing.sm),
          decoration: BoxDecoration(color: AgriColors.surfaceZebra, borderRadius: BorderRadius.circular(AgriRadius.lg)),
          child: const Text(
            'La tarification (Fourchette/Sur devis) se complète ensuite depuis le Catalogue Produits.',
            style: TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
        ),
      ],
    ),
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
      BoutonModalePrimaire(key: const Key('rapide-produit-enregistrer'), libelle: 'Enregistrer', onPressed: _enregistrer),
    ],
  );
}
