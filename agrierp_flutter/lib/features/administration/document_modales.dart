import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import 'administration_repository.dart';

/// Ouvre « Générer un Document » (`existant == null`) ou « Modifier — Documents
/// Administratifs » (`documents-administratifs.html`).
///
/// ⚠️⚠️ **L'ENREGISTREMENT EST LOCAL, PUIS SYNCHRONISÉ** (ticket F0.80), comme les courriers
/// (F0.78) et les documents archivés (F0.79) : la ligne est écrite tout de suite, `pending`, et
/// le serveur — maître de la règle — la valide à la synchronisation.
///
/// ⚠️⚠️ **AUCUN FICHIER N'EST GÉNÉRÉ**, malgré le libellé de la maquette : c'est une ligne de
/// registre (titre, type, bénéficiaire, date, statut), comme sur la page web. La mention de
/// l'onglet le dit.
///
/// ⚠️ « Titre du document * » n'est PAS dans la modale de la maquette (où le titre est la
/// valeur choisie dans « Type de document »), mais le serveur l'exige (`title` requis) et la
/// page web le demande : le poste le propose. ⚠️ « Statut » vient aussi de la page web.
///
/// Retourne `true` si un document a été écrit.
Future<bool> ouvrirFicheDocument({
  required BuildContext context,
  required AdministrationRepository depot,
  AdministrativeDocument? existant,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleDocument(depot: depot, existant: existant),
  );
  return ok == true;
}

/// « Confirmer l'archivage » d'un document. Retourne `true` si le retrait a eu lieu.
///
/// ⚠️ **RETIRER N'EFFACE RIEN CÔTÉ SERVEUR** (`is_active = false`) : le texte est celui de
/// la maquette.
Future<bool> confirmerRetraitDocument({
  required BuildContext context,
  required AdministrationRepository depot,
  required AdministrativeDocument document,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    confirmation: true,
    constructeur: (_) =>
        _ModaleRetraitDocument(depot: depot, document: document),
  );
  return ok == true;
}

class _ModaleDocument extends StatefulWidget {
  const _ModaleDocument({required this.depot, required this.existant});

  final AdministrationRepository depot;
  final AdministrativeDocument? existant;

  @override
  State<_ModaleDocument> createState() => _ModaleDocumentState();
}

class _ModaleDocumentState extends State<_ModaleDocument> {
  late String _type = widget.existant?.type ?? '';
  late String _statut =
      widget.existant?.status ?? AdministrationRepository.statutEnAttente;
  late DateTime? _date = widget.existant == null
      ? _aujourdhui()
      : widget.existant!.docDate;
  late final TextEditingController _titre = TextEditingController(
    text: widget.existant?.title ?? '',
  );
  late final TextEditingController _beneficiaire = TextEditingController(
    text: widget.existant?.beneficiary ?? '',
  );
  Map<String, String> _erreurs = const {};

  bool get _creation => widget.existant == null;

  static DateTime _aujourdhui() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _titre.dispose();
    _beneficiaire.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final saisie = FormulaireDocument(
      titre: _titre.text,
      type: _type,
      beneficiaire: _beneficiaire.text,
      date: _date,
      statut: _statut,
    );

    final erreurs = AdministrationRepository.validerDocument(saisie);
    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      return;
    }

    if (_creation) {
      await widget.depot.creerDocument(saisie);
    } else {
      await widget.depot.modifierDocument(widget.existant!.id, saisie);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  static const _styleLibelle = TextStyle(
    fontSize: AgriTypography.xs,
    fontWeight: FontWeight.bold,
  );

  Widget _bloc(String libelle, String cle, Widget champ) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(libelle, style: _styleLibelle),
        const SizedBox(height: AgriSpacing.xs),
        champ,
        if (_erreurs[cle] != null)
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: Text(
              _erreurs[cle]!,
              key: Key('document-erreur-$cle'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.errorDeep,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _texte(String cle, TextEditingController controleur) => TextField(
    key: Key(cle),
    controller: controleur,
    style: const TextStyle(fontSize: AgriTypography.xs),
    decoration: const InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
    ),
  );

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<DateTime?> _choisir(DateTime? depart) => showDatePicker(
    context: context,
    initialDate: depart ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  @override
  Widget build(BuildContext context) {
    // ⚠️ Le serveur accepte tout type (texte libre) : une valeur reçue qui n'est pas dans la
    // liste proposée reste choisie et affichée, jamais écrasée ni perdue.
    final types = [
      ...AdministrationRepository.typesProposes,
      if (_type.isNotEmpty &&
          !AdministrationRepository.typesProposes.contains(_type))
        _type,
    ];

    return ModaleAgri(
      titre: _creation
          ? 'Générer un Document'
          : 'Modifier — Documents Administratifs',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bloc(
            'Titre du document *',
            'titre',
            _texte('document-titre', _titre),
          ),
          _bloc(
            'Type de document *',
            'type',
            DropdownButtonFormField<String>(
              key: const Key('document-type'),
              initialValue: _type.isEmpty ? null : _type,
              isExpanded: true,
              isDense: true,
              hint: const Text('-- Sélectionner --'),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.onSurface,
              ),
              items: [
                for (final t in types)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => _type = v ?? ''),
            ),
          ),
          _bloc(
            'Bénéficiaire *',
            'beneficiaire',
            _texte('document-beneficiaire', _beneficiaire),
          ),
          _bloc(
            'Date *',
            'date',
            OutlinedButton(
              key: const Key('document-date'),
              onPressed: () async {
                final choisie = await _choisir(_date);
                if (choisie != null) setState(() => _date = choisie);
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_date == null ? 'jj/mm/aaaa' : _jour(_date!)),
              ),
            ),
          ),
          _bloc(
            'Statut',
            'statut',
            DropdownButtonFormField<String>(
              key: const Key('document-statut'),
              initialValue: _statut,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.onSurface,
              ),
              items: const [
                DropdownMenuItem(
                  value: AdministrationRepository.statutEnAttente,
                  child: Text('En attente'),
                ),
                DropdownMenuItem(
                  value: AdministrationRepository.statutSigne,
                  child: Text('Signé'),
                ),
              ],
              onChanged: (v) => setState(
                () => _statut = v ?? AdministrationRepository.statutEnAttente,
              ),
            ),
          ),
        ],
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('document-enregistrer'),
          libelle: 'Enregistrer',
          onPressed: _valider,
        ),
      ],
    );
  }
}

class _ModaleRetraitDocument extends StatelessWidget {
  const _ModaleRetraitDocument({required this.depot, required this.document});

  final AdministrationRepository depot;
  final AdministrativeDocument document;

  @override
  Widget build(BuildContext context) {
    return ModaleConfirmation(
      titre: "Confirmer l'archivage",
      detail: Text(
        document.title,
        key: const Key('retrait-document-cible'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: AgriTypography.sm,
          fontWeight: FontWeight.bold,
          color: AgriColors.brandForest,
        ),
      ),
      message:
          "L'enregistrement sera marqué comme archivé (statut inactif). "
          "Aucune suppression définitive n'est effectuée.",
      icone: Icons.archive,
      couleurIcone: AgriColors.errorDeep,
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('retrait-document-confirmer'),
          libelle: 'Archiver',
          onPressed: () async {
            await depot.retirerDocument(document.id);
            if (context.mounted) Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }
}
