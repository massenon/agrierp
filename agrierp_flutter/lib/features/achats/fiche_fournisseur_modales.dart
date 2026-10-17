import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import 'fournisseurs_repository.dart';

/// Ouvre « Nouveau Fournisseur » (`existant == null`) ou « Modifier » une fiche.
///
/// ⚠️⚠️ **L'ENREGISTREMENT EST LOCAL, PUIS SYNCHRONISÉ** (ticket F0.71), comme pour les
/// produits : la fiche est écrite tout de suite, `pending`, et le serveur — qui reste
/// maître de la règle — la valide à la synchronisation. Un refus se lit à l'écran
/// Synchronisation. Rien n'exige le réseau.
///
/// Retourne `true` si une fiche a été écrite.
Future<bool> ouvrirFicheFournisseur({
  required BuildContext context,
  required FournisseursRepository depot,
  Supplier? existant,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleFiche(depot: depot, existant: existant),
  );
  return ok == true;
}

/// « Confirmer l'archivage ». Retourne `true` si la fiche a été archivée.
Future<bool> confirmerArchivageFournisseur({
  required BuildContext context,
  required FournisseursRepository depot,
  required Supplier fiche,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    confirmation: true,
    constructeur: (_) => _ModaleArchivage(depot: depot, fiche: fiche),
  );
  return ok == true;
}

class _ModaleFiche extends StatefulWidget {
  const _ModaleFiche({required this.depot, required this.existant});

  final FournisseursRepository depot;
  final Supplier? existant;

  @override
  State<_ModaleFiche> createState() => _ModaleFicheState();
}

class _ModaleFicheState extends State<_ModaleFiche> {
  late final TextEditingController _nom = TextEditingController(
    text: widget.existant?.name ?? '',
  );
  late final TextEditingController _telephone = TextEditingController(
    text: widget.existant?.phone ?? '',
  );
  late final TextEditingController _adresse = TextEditingController(
    text: widget.existant?.address ?? '',
  );
  late String _categorie = widget.existant?.category ?? '';
  Map<String, String> _erreurs = const {};

  bool get _creation => widget.existant == null;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _adresse.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final saisie = FormulaireFournisseur(
      nom: _nom.text,
      categorie: _categorie,
      telephone: _telephone.text,
      adresse: _adresse.text,
    );

    final erreurs = FournisseursRepository.validerFiche(saisie);
    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      return;
    }

    if (_creation) {
      await widget.depot.creerFournisseur(saisie);
    } else {
      await widget.depot.modifierFournisseur(widget.existant!.id, saisie);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _champ(
    String libelle,
    String cle,
    TextEditingController c, {
    String? indice,
    TextInputType? clavier,
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
          key: Key('fiche-$cle'),
          controller: c,
          keyboardType: clavier,
          style: const TextStyle(fontSize: AgriTypography.xs),
          decoration: InputDecoration(
            hintText: indice,
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: _erreurs[cle],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ModaleAgri(
      titre: _creation
          ? 'Nouveau Fournisseur'
          : 'Modifier — Fournisseurs — Ajout',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _champ(
            'Nom du fournisseur *',
            'nom',
            _nom,
            indice: 'ex : Provenderie du Plateau',
          ),
          _champ(
            'Téléphone *',
            'telephone',
            _telephone,
            indice: '+229 ..',
            clavier: TextInputType.phone,
          ),
          const Text(
            'Catégorie *',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(bottom: AgriSpacing.md),
            child: DropdownButtonFormField<String>(
              key: const Key('fiche-categorie'),
              initialValue: categoriesFournisseur.contains(_categorie)
                  ? _categorie
                  : '',
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: _erreurs['categorie'],
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('-- Sélectionner --'),
                ),
                for (final c in categoriesFournisseur)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _categorie = v ?? ''),
            ),
          ),
          _champ('Adresse', 'adresse', _adresse),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('fiche-enregistrer'),
          libelle: _creation ? 'Enregistrer' : 'Mettre à jour',
          onPressed: _valider,
        ),
      ],
    );
  }
}

class _ModaleArchivage extends StatelessWidget {
  const _ModaleArchivage({required this.depot, required this.fiche});

  final FournisseursRepository depot;
  final Supplier fiche;

  @override
  Widget build(BuildContext context) {
    return ModaleConfirmation(
      titre: "Confirmer l'archivage",
      message:
          "L'enregistrement sera marqué comme archivé (statut inactif). "
          "Aucune suppression définitive n'est effectuée.",
      icone: Icons.archive,
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('archivage-confirmer'),
          libelle: 'Archiver',
          onPressed: () async {
            await depot.archiverFournisseur(fiche.id);
            if (context.mounted) Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }
}
