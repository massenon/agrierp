import 'package:flutter/material.dart';

import '../../core/database/app_database.dart' show ChartOfAccount;
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/modale_agri.dart';
import 'comptabilite_repository.dart';

/// Ticket CP-1 — LES DEUX MODALES DE `Comptabilite\PlanComptable` : « Nouveau Compte » / « Modifier le Compte »
/// (`modal-create-plan-comptable`) et la confirmation d'archivage.
///
/// Retourne `true` quand une écriture a eu lieu (le compte est créé ou modifié `pending`, puis envoyé ; le serveur applique les
/// mêmes règles que le web — numéro unique, classe 1 à 9 — et peut refuser avec son motif).

Future<bool> ouvrirCompte({
  required BuildContext context,
  required ComptabiliteRepository depot,
  ChartOfAccount? existant,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleCompte(depot: depot, existant: existant),
  );
  return ok == true;
}

Future<bool> confirmerArchivageCompte({
  required BuildContext context,
  required ComptabiliteRepository depot,
  required ChartOfAccount compte,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    confirmation: true,
    constructeur: (contexte) => _ModaleArchivageCompte(depot: depot, compte: compte),
  );
  return ok == true;
}

class _ModaleCompte extends StatefulWidget {
  const _ModaleCompte({required this.depot, required this.existant});

  final ComptabiliteRepository depot;
  final ChartOfAccount? existant;

  @override
  State<_ModaleCompte> createState() => _ModaleCompteState();
}

class _ModaleCompteState extends State<_ModaleCompte> {
  late final TextEditingController _code = TextEditingController(text: widget.existant?.code ?? '');
  late final TextEditingController _libelle = TextEditingController(text: widget.existant?.label ?? '');
  late String _classe = widget.existant?.accountClass?.toString() ?? '';
  Map<String, String> _erreurs = const {};

  @override
  void dispose() {
    _code.dispose();
    _libelle.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    try {
      if (widget.existant == null) {
        await widget.depot.creerCompte(code: _code.text, libelle: _libelle.text, classe: _classe);
      } else {
        await widget.depot.modifierCompte(widget.existant!.id, code: _code.text, libelle: _libelle.text, classe: _classe);
      }
    } on SaisieCompteRefusee catch (e) {
      setState(() => _erreurs = e.erreurs);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _champ(String etiquette, Widget champ, String cle) => Padding(
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
        if (_erreurs[cle] != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(_erreurs[cle]!, key: Key('compte-erreur-$cle'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ModaleAgri(
    titre: widget.existant == null ? 'Nouveau Compte' : 'Modifier le Compte',
    contenu: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_erreurs['formulaire'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AgriSpacing.md),
            child: Text(_erreurs['formulaire']!, key: const Key('compte-erreur-formulaire'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
          ),
        _champ(
          'Numéro de compte *',
          TextField(
            key: const Key('compte-code'),
            controller: _code,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'ex : 411'),
          ),
          'code',
        ),
        _champ(
          'Intitulé *',
          TextField(
            key: const Key('compte-libelle'),
            controller: _libelle,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'ex : Clients'),
          ),
          'label',
        ),
        _champ(
          'Classe *',
          DropdownButtonFormField<String>(
            key: const Key('compte-classe'),
            initialValue: _classe,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
            items: [
              const DropdownMenuItem(value: '', child: Text('-- Sélectionner --')),
              for (final (valeur, libelle) in classesSyscohada) DropdownMenuItem(value: valeur, child: Text(libelle)),
            ],
            onChanged: (v) => setState(() => _classe = v ?? ''),
          ),
          'class',
        ),
      ],
    ),
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(key: const Key('compte-enregistrer'), libelle: 'Enregistrer', onPressed: _enregistrer),
    ],
  );
}

class _ModaleArchivageCompte extends StatefulWidget {
  const _ModaleArchivageCompte({required this.depot, required this.compte});

  final ComptabiliteRepository depot;
  final ChartOfAccount compte;

  @override
  State<_ModaleArchivageCompte> createState() => _ModaleArchivageCompteState();
}

class _ModaleArchivageCompteState extends State<_ModaleArchivageCompte> {
  String? _refus;

  Future<void> _archiver() async {
    try {
      await widget.depot.archiverCompte(widget.compte.id);
    } on SaisieCompteRefusee catch (e) {
      setState(() => _refus = e.erreurs.values.first);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => ModaleConfirmation(
    titre: "Confirmer l'archivage",
    message:
        '${widget.compte.code} — ${widget.compte.label} sera marqué(e) comme archivé(e) (statut inactif). '
        "Aucune suppression définitive n'est effectuée."
        '${_refus == null ? '' : '\n\n$_refus'}',
    icone: SymbolesAgri.archive,
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(
        key: const Key('compte-archiver-confirmer'),
        libelle: 'Archiver',
        couleur: AgriColors.errorRed,
        onPressed: _archiver,
      ),
    ],
  );
}
