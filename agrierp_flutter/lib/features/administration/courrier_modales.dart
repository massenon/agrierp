import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import 'administration_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Ouvre « Nouveau Courrier » (`existant == null`) ou « Modifier — Gestion des Courriers ».
///
/// ⚠️⚠️ **L'ENREGISTREMENT EST LOCAL, PUIS SYNCHRONISÉ** (ticket F0.78), comme les clients
/// et les fournisseurs : le courrier est écrit tout de suite, `pending`, et le serveur —
/// maître de la règle — le valide à la synchronisation. ⚠️ **La référence `CR-AAAA-NNN`
/// n'est jamais inventée ici** : le serveur l'attribue, le tableau affiche « — » jusque-là.
///
/// ⚠️ Pas de pièce jointe : ni la maquette ni le schéma n'en ont.
///
/// Retourne `true` si un courrier a été écrit.
Future<bool> ouvrirFicheCourrier({
  required BuildContext context,
  required AdministrationRepository depot,
  Mail? existant,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleCourrier(depot: depot, existant: existant),
  );
  return ok == true;
}

/// « Confirmer l'archivage » d'un courrier. Retourne `true` si l'archivage a eu lieu.
///
/// ⚠️ **ARCHIVER N'EFFACE RIEN** (`is_active = false`) : le texte est celui de la maquette.
Future<bool> confirmerArchivageCourrier({
  required BuildContext context,
  required AdministrationRepository depot,
  required Mail courrier,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    confirmation: true,
    constructeur: (_) =>
        _ModaleArchivageCourrier(depot: depot, courrier: courrier),
  );
  return ok == true;
}

class _ModaleCourrier extends StatefulWidget {
  const _ModaleCourrier({required this.depot, required this.existant});

  final AdministrationRepository depot;
  final Mail? existant;

  @override
  State<_ModaleCourrier> createState() => _ModaleCourrierState();
}

class _ModaleCourrierState extends State<_ModaleCourrier> {
  late String _type = widget.existant?.type ?? '';
  late DateTime? _date = widget.existant?.mailDate;
  late final TextEditingController _objet = TextEditingController(
    text: widget.existant?.subject ?? '',
  );
  late final TextEditingController _partie = TextEditingController(
    text: widget.existant?.party ?? '',
  );
  Map<String, String> _erreurs = const {};

  bool get _creation => widget.existant == null;

  @override
  void dispose() {
    _objet.dispose();
    _partie.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final saisie = FormulaireCourrier(
      type: _type,
      objet: _objet.text,
      partie: _partie.text,
      date: _date,
    );

    final erreurs = AdministrationRepository.validerCourrier(saisie);
    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      return;
    }

    if (_creation) {
      await widget.depot.creerCourrier(saisie);
    } else {
      await widget.depot.modifierCourrier(widget.existant!.id, saisie);
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
              key: Key('courrier-erreur-$cle'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.errorDeep,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _texte(String cle, TextEditingController c) => TextField(
    key: Key('courrier-$cle'),
    controller: c,
    style: const TextStyle(fontSize: AgriTypography.xs),
    decoration: const InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
    ),
  );

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return ModaleAgri(
      titre: _creation
          ? 'Nouveau Courrier'
          : 'Modifier — Gestion des Courriers',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bloc(
            'Type *',
            'type',
            DropdownButtonFormField<String>(
              key: const Key('courrier-type'),
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
              items: const [
                DropdownMenuItem(value: 'entrant', child: Text('Entrant')),
                DropdownMenuItem(value: 'sortant', child: Text('Sortant')),
              ],
              onChanged: (v) => setState(() => _type = v ?? ''),
            ),
          ),
          _bloc('Objet *', 'objet', _texte('objet', _objet)),
          _bloc(
            'Expéditeur / Destinataire *',
            'partie',
            _texte('partie', _partie),
          ),
          _bloc(
            'Date *',
            'date',
            OutlinedButton(
              key: const Key('courrier-date'),
              onPressed: () async {
                final choisie = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (choisie != null) setState(() => _date = choisie);
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_date == null ? 'jj/mm/aaaa' : _jour(_date!)),
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
          key: const Key('courrier-enregistrer'),
          libelle: 'Enregistrer',
          onPressed: _valider,
        ),
      ],
    );
  }
}

class _ModaleArchivageCourrier extends StatelessWidget {
  const _ModaleArchivageCourrier({required this.depot, required this.courrier});

  final AdministrationRepository depot;
  final Mail courrier;

  @override
  Widget build(BuildContext context) {
    // La maquette nomme le courrier par sa référence ; tant que le serveur ne l'a pas
    // attribuée, c'est l'objet qui le désigne (jamais une référence inventée).
    final cible = courrier.reference ?? courrier.subject;

    return ModaleConfirmation(
      titre: "Confirmer l'archivage",
      detail: Text(
        cible,
        key: const Key('archivage-courrier-cible'),
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
      icone: SymbolesAgri.archive,
      couleurIcone: AgriColors.errorDeep,
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BoutonModalePrimaire(
          key: const Key('archivage-courrier-confirmer'),
          libelle: 'Archiver',
          onPressed: () async {
            await depot.archiverCourrier(courrier.id);
            if (context.mounted) Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }
}
