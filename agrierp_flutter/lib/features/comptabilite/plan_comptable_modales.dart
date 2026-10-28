import 'package:flutter/material.dart';

import '../../core/comptabilite/exercice_de_saisie.dart';
import '../../core/database/app_database.dart' show AccountingEntryLine, ChartOfAccount;
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/champs_date_agri.dart';
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

// ── Ticket CP-2 — « Saisie d'Écriture » / « Modifier l'Écriture » (`modal-create-journal-comptable`) ──────────────────────

/// Ouvre la saisie d'une écriture manuelle ([existante] absente) ou la modification de [existante] (deux lignes : un débit, un
/// crédit). Retourne `true` quand la DEMANDE a été écrite (le serveur écrit l'écriture et la numérote).
Future<bool> ouvrirEcriture({
  required BuildContext context,
  required ComptabiliteRepository depot,
  required List<ChartOfAccount> comptes,
  required DateTime aujourdhui,
  LigneJournal? existante,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleEcriture(depot: depot, comptes: comptes, aujourdhui: aujourdhui, existante: existante),
  );
  return ok == true;
}

/// Confirmation d'archivage d'une écriture : retourne `true` quand la demande est écrite.
Future<bool> confirmerArchivageEcriture({
  required BuildContext context,
  required ComptabiliteRepository depot,
  required LigneJournal ecriture,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    confirmation: true,
    constructeur: (_) => _ModaleArchivageEcriture(depot: depot, ecriture: ecriture),
  );
  return ok == true;
}

class _ModaleEcriture extends StatefulWidget {
  const _ModaleEcriture({required this.depot, required this.comptes, required this.aujourdhui, required this.existante});

  final ComptabiliteRepository depot;
  final List<ChartOfAccount> comptes;
  final DateTime aujourdhui;
  final LigneJournal? existante;

  @override
  State<_ModaleEcriture> createState() => _ModaleEcritureState();
}

class _ModaleEcritureState extends State<_ModaleEcriture> {
  late DateTime? _date = widget.existante?.ecriture.entryDate ?? widget.aujourdhui;
  late final TextEditingController _libelle = TextEditingController(text: widget.existante?.libelle ?? '');
  late String _debit = _compteDe((l) => l.debit > 0);
  late String _credit = _compteDe((l) => l.credit > 0);
  late final TextEditingController _montant = TextEditingController(
    text: widget.existante == null ? '' : widget.existante!.totalDebit.round().toString(),
  );
  Map<String, String> _erreurs = const {};

  String _compteDe(bool Function(AccountingEntryLine) filtre) {
    final lignes = widget.existante?.lignes.where(filtre) ?? const <AccountingEntryLine>[];
    return lignes.isEmpty ? '' : lignes.first.accountId;
  }

  @override
  void dispose() {
    _libelle.dispose();
    _montant.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    try {
      if (widget.existante == null) {
        await widget.depot.creerEcriture(date: _date, libelle: _libelle.text, debitId: _debit, creditId: _credit, montant: _montant.text);
      } else {
        await widget.depot.modifierEcriture(
          widget.existante!.ecriture.id,
          date: _date,
          libelle: _libelle.text,
          debitId: _debit,
          creditId: _credit,
          montant: _montant.text,
        );
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
            child: Text(_erreurs[cle]!, key: Key('ecriture-erreur-$cle'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
          ),
      ],
    ),
  );

  Widget _liste(String cle, String valeur, ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
    key: Key(cle),
    initialValue: valeur,
    isDense: true,
    isExpanded: true,
    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
    style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
    items: [
      const DropdownMenuItem(value: '', child: Text('-- Sélectionner --')),
      for (final c in widget.comptes) DropdownMenuItem(value: c.id, child: Text('${c.code} - ${c.label}', overflow: TextOverflow.ellipsis)),
    ],
    onChanged: (v) => setState(() => onChanged(v ?? '')),
  );

  @override
  Widget build(BuildContext context) => ModaleAgri(
    titre: widget.existante == null ? "Saisie d'Écriture" : "Modifier l'Écriture",
    contenu: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_erreurs['formulaire'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AgriSpacing.md),
            child: Text(_erreurs['formulaire']!, key: const Key('ecriture-erreur-formulaire'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
          ),
        ChampDateFormulaire(
          cle: const Key('ecriture-date'),
          etiquette: "Date de l'écriture *",
          valeur: _date,
          erreur: _erreurs['entryDate'],
          cleErreur: const Key('ecriture-erreur-entryDate'),
          onTap: () async {
            final premier = await widget.depot.premierJourSaisissable();
            if (!mounted) return;
            final bornes = ExerciceDeSaisie.calendrier(premier: premier, repli: DateTime(2000), dernier: DateTime(2100), initial: _date ?? widget.aujourdhui);
            final choisie = await showDatePicker(
              // ignore: use_build_context_synchronously
              context: this.context,
              initialDate: bornes.initial,
              firstDate: bornes.premier,
              lastDate: DateTime(2100),
            );
            if (choisie != null) setState(() => _date = choisie);
          },
        ),
        const SizedBox(height: AgriSpacing.md),
        _champ(
          'Libellé *',
          TextField(
            key: const Key('ecriture-libelle'),
            controller: _libelle,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'ex : Achat aliment ponte'),
          ),
          'label',
        ),
        _champ('Compte à débiter *', _liste('ecriture-debit', _debit, (v) => _debit = v), 'debitAccountId'),
        _champ('Compte à créditer *', _liste('ecriture-credit', _credit, (v) => _credit = v), 'creditAccountId'),
        _champ(
          'Montant (FCFA) *',
          TextField(
            key: const Key('ecriture-montant'),
            controller: _montant,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
          'amount',
        ),
      ],
    ),
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(key: const Key('ecriture-enregistrer'), libelle: 'Enregistrer', onPressed: _enregistrer),
    ],
  );
}

class _ModaleArchivageEcriture extends StatefulWidget {
  const _ModaleArchivageEcriture({required this.depot, required this.ecriture});

  final ComptabiliteRepository depot;
  final LigneJournal ecriture;

  @override
  State<_ModaleArchivageEcriture> createState() => _ModaleArchivageEcritureState();
}

class _ModaleArchivageEcritureState extends State<_ModaleArchivageEcriture> {
  String? _refus;

  Future<void> _archiver() async {
    try {
      await widget.depot.archiverEcriture(widget.ecriture.ecriture.id);
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
        '${widget.ecriture.piece.isEmpty ? 'Cette écriture' : widget.ecriture.piece} sera marqué(e) comme archivé(e) (statut inactif). '
        "Aucune suppression définitive n'est effectuée."
        '${_refus == null ? '' : '\n\n$_refus'}',
    icone: SymbolesAgri.archive,
    actions: [
      BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop(false)),
      BoutonModalePrimaire(
        key: const Key('ecriture-archiver-confirmer'),
        libelle: 'Archiver',
        couleur: AgriColors.errorRed,
        onPressed: _archiver,
      ),
    ],
  );
}
