import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import 'administration_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// Ouvre « Archiver un Document » (`existant == null`) ou « Modifier — Archivage des
/// Documents » (`archivage-documents.html`).
///
/// ⚠️⚠️ **L'ENREGISTREMENT EST LOCAL, PUIS SYNCHRONISÉ** (ticket F0.79), comme les
/// courriers : le document est écrit tout de suite, `pending`, et le serveur — maître de la
/// règle — le valide à la synchronisation. ⚠️ **Le statut (Valide / Bientôt expiré / Expiré)
/// n'est ni saisi ni envoyé** : il se déduit de la date d'expiration.
///
/// ⚠️ « Date d'archivage » n'est PAS dans la modale de la maquette, mais le serveur l'exige
/// (`archived_date` requis) : le poste la propose, préremplie au jour courant à la création.
/// ⚠️ Pas de pièce jointe : ni la maquette ni le schéma n'en ont.
///
/// Retourne `true` si un document a été écrit.
Future<bool> ouvrirFicheArchive({
  required BuildContext context,
  required AdministrationRepository depot,
  ArchivedDocument? existant,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    constructeur: (_) => _ModaleArchive(depot: depot, existant: existant),
  );
  return ok == true;
}

/// « Confirmer l'archivage » d'un document. Retourne `true` si le retrait a eu lieu.
///
/// ⚠️ **RETIRER N'EFFACE RIEN CÔTÉ SERVEUR** (`is_active = false`) : le texte est celui de
/// la maquette.
Future<bool> confirmerRetraitArchive({
  required BuildContext context,
  required AdministrationRepository depot,
  required ArchivedDocument document,
}) async {
  final ok = await afficherModale<bool>(
    context: context,
    confirmation: true,
    constructeur: (_) =>
        _ModaleRetraitArchive(depot: depot, document: document),
  );
  return ok == true;
}

class _ModaleArchive extends StatefulWidget {
  const _ModaleArchive({required this.depot, required this.existant});

  final AdministrationRepository depot;
  final ArchivedDocument? existant;

  @override
  State<_ModaleArchive> createState() => _ModaleArchiveState();
}

class _ModaleArchiveState extends State<_ModaleArchive> {
  late String _categorie = widget.existant?.category ?? '';
  late DateTime? _dateArchivage = widget.existant == null
      ? _aujourdhui()
      : widget.existant!.archivedDate;
  late DateTime? _echeance = widget.existant?.expiryDate;
  late final TextEditingController _titre = TextEditingController(
    text: widget.existant?.title ?? '',
  );
  Map<String, String> _erreurs = const {};

  bool get _creation => widget.existant == null;

  static DateTime _aujourdhui() {
    final n = HeureBenin.maintenant();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _titre.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final saisie = FormulaireArchive(
      titre: _titre.text,
      categorie: _categorie,
      dateArchivage: _dateArchivage,
      echeance: _echeance,
    );

    final erreurs = AdministrationRepository.validerArchive(saisie);
    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      return;
    }

    if (_creation) {
      await widget.depot.creerArchive(saisie);
    } else {
      await widget.depot.modifierArchive(widget.existant!.id, saisie);
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
              key: Key('archive-erreur-$cle'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.errorDeep,
              ),
            ),
          ),
      ],
    ),
  );

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<DateTime?> _choisir(DateTime? depart) => showDatePicker(
    context: context,
    initialDate: depart ?? HeureBenin.maintenant(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  @override
  Widget build(BuildContext context) {
    // ⚠️ Le serveur accepte toute catégorie (texte libre) : une valeur reçue qui n'est pas
    // dans la liste proposée reste choisie et affichée, jamais écrasée ni perdue.
    final categories = [
      ...AdministrationRepository.categoriesProposees,
      if (_categorie.isNotEmpty &&
          !AdministrationRepository.categoriesProposees.contains(_categorie))
        _categorie,
    ];

    return ModaleAgri(
      titre: _creation
          ? 'Archiver un Document'
          : 'Modifier — Archivage des Documents',
      contenu: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bloc(
            'Nom du document *',
            'titre',
            TextField(
              key: const Key('archive-titre'),
              controller: _titre,
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          _bloc(
            'Catégorie *',
            'categorie',
            DropdownButtonFormField<String>(
              key: const Key('archive-categorie'),
              initialValue: _categorie.isEmpty ? null : _categorie,
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
                for (final c in categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _categorie = v ?? ''),
            ),
          ),
          _bloc(
            "Date d'archivage",
            'dateArchivage',
            OutlinedButton(
              key: const Key('archive-date-archivage'),
              onPressed: () async {
                final choisie = await _choisir(_dateArchivage);
                if (choisie != null) setState(() => _dateArchivage = choisie);
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _dateArchivage == null
                      ? 'jj/mm/aaaa'
                      : _jour(_dateArchivage!),
                ),
              ),
            ),
          ),
          _bloc(
            "Date d'expiration",
            'echeance',
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('archive-echeance'),
                    onPressed: () async {
                      final choisie = await _choisir(_echeance);
                      if (choisie != null) setState(() => _echeance = choisie);
                    },
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _echeance == null ? 'jj/mm/aaaa' : _jour(_echeance!),
                      ),
                    ),
                  ),
                ),
                if (_echeance != null)
                  IconButton(
                    key: const Key('archive-echeance-effacer'),
                    tooltip: 'Effacer',
                    onPressed: () => setState(() => _echeance = null),
                    icon: const Icon(SymbolesAgri.close, size: 18),
                  ),
              ],
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
          key: const Key('archive-enregistrer'),
          libelle: 'Enregistrer',
          onPressed: _valider,
        ),
      ],
    );
  }
}

class _ModaleRetraitArchive extends StatelessWidget {
  const _ModaleRetraitArchive({required this.depot, required this.document});

  final AdministrationRepository depot;
  final ArchivedDocument document;

  @override
  Widget build(BuildContext context) {
    return ModaleConfirmation(
      titre: "Confirmer l'archivage",
      detail: Text(
        document.title,
        key: const Key('retrait-archive-cible'),
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
          key: const Key('retrait-archive-confirmer'),
          libelle: 'Archiver',
          onPressed: () async {
            await depot.retirerArchive(document.id);
            if (context.mounted) Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }
}
