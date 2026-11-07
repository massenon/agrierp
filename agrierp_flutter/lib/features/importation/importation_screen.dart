import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/zone_depot.dart';
import 'importation_repository.dart';

/// Fichier choisi par l'utilisateur (injecté en test).
typedef FichierChoisi = ({String nom, Uint8List octets});

/// Sélecteur par défaut : un classeur .xlsx.
Future<FichierChoisi?> choisirClasseurXlsx() async {
  final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], dialogTitle: 'Choisir le fichier à importer (.xlsx)');
  if (r == null || r.files.isEmpty || r.files.first.path == null) return null;
  return (nom: r.files.first.name, octets: Uint8List.fromList(await File(r.files.first.path!).readAsBytes()));
}

/// Écrit un fichier dans « Documents\AgriERP » et rend son chemin (l'écran l'annonce : aucune boîte de dialogue, comme les exports).
Future<String> enregistrerDansDocuments(String nom, List<int> octets) async {
  final racine = await getApplicationDocumentsDirectory();
  final dossier = Directory(p.join(racine.path, 'AgriERP'));
  if (!dossier.existsSync()) dossier.createSync(recursive: true);
  final chemin = p.join(dossier.path, nom);
  File(chemin).writeAsBytesSync(octets);
  return chemin;
}

/// Ticket IMPORT-1 — ÉCRAN « IMPORTATION EN MASSE », portage de `livewire/stocks/importation-masse.blade.php`.
///
/// ⚠️ Absent du prototype : construit d'abord sur le web (Doctrine, article 0), porté à l'identique — mêmes six étapes, mêmes
/// libellés (lus dans le Blade par `importation_parite_web_test.dart`), mêmes états, mêmes motifs. Il fonctionne hors ligne :
/// les lignes valides s'écrivent `pending` par les dépôts propriétaires et partent à la prochaine synchronisation.
/// ⚠️ Pas de glisser-déposer au poste (il demanderait une dépendance de plus) : le clic ouvre le sélecteur de fichiers.
class ImportationScreen extends StatefulWidget {
  const ImportationScreen({
    super.key,
    required this.depot,
    required this.role,
    this.choisirFichier = choisirClasseurXlsx,
    this.enregistrer = enregistrerDansDocuments,
  });

  final ImportationRepository depot;
  final String role;
  final Future<FichierChoisi?> Function() choisirFichier;
  final Future<String> Function(String nom, List<int> octets) enregistrer;

  @override
  State<ImportationScreen> createState() => _ImportationScreenState();
}

class _ImportationScreenState extends State<ImportationScreen> {
  static const parPage = 25;

  ModuleImportation? _module;
  int _etape = 1;
  ApercuImportation? _apercu;
  String _filtre = 'tous';
  int _page = 1;
  String? _erreur;
  String? _information;
  bool _occupe = false;

  void _reinitialiser() {
    _module = null;
    _etape = 1;
    _apercu = null;
    _filtre = 'tous';
    _page = 1;
    _erreur = null;
    _information = null;
  }

  Future<void> _telechargerModele() async {
    final m = _module!;
    final octets = await widget.depot.genererModele(m);
    final chemin = await widget.enregistrer(m.nomDeFichier, octets);
    if (!mounted) return;
    setState(() => _information = 'Modèle enregistré : $chemin');
  }

  Future<void> _deposer() async {
    final f = await widget.choisirFichier();
    if (f == null) return;
    await _analyserFichier(f);
  }

  /// CONF-2 : un fichier déposé par glisser-déposer suit le MÊME chemin que le clic (`_analyserFichier` : mêmes refus, mêmes messages).
  Future<void> _analyserFichier(FichierChoisi f) async {
    if (_occupe || _module == null) return;
    final m = _module!;
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    try {
      final apercu = await widget.depot.analyser(m, f.octets, f.nom);
      if (!mounted) return;
      setState(() {
        _apercu = apercu;
        _etape = 4;
        _filtre = 'tous';
        _page = 1;
        _occupe = false;
      });
    } on ImportationRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _occupe = false;
      });
    }
  }

  Future<void> _confirmer() async {
    final a = _apercu!;
    Navigator.of(context).pop();
    setState(() => _occupe = true);
    try {
      await widget.depot.importer(a, widget.role);
      if (!mounted) return;
      setState(() {
        _etape = 6;
        _filtre = 'tous';
        _page = 1;
        _occupe = false;
        _information = "Importation terminée : le rapport est affiché.";
      });
    } on ImportationRefusee catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _occupe = false;
      });
    }
  }

  Future<void> _ouvrirConfirmation() async {
    final a = _apercu!;
    await afficherModale<void>(
      context: context,
      constructeur: (ctx) => ModaleAgri(
        titre: "5 · Confirmer l'importation",
        contenu: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${a.valides} ${a.valides > 1 ? 'lignes valides vont' : 'ligne valide va'} être écrite${a.valides > 1 ? 's' : ''} dans « ${a.module.libelle} ».',
              style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
            ),
            const SizedBox(height: AgriSpacing.xs),
            Text(
              '${a.ignorees} ignorée(s) et ${a.refusees} refusée(s) ne sont pas écrites. '
              "${a.module.cle == 'stocks' ? 'Chaque stock initial entre par un mouvement « Stock initial ». ' : ''}"
              "L'écriture se fait ligne par ligne : une ligne refusée n'arrête pas les autres.",
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ],
        ),
        actions: [
          BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(ctx).pop()),
          BoutonModalePrimaire(libelle: "Confirmer l'importation", onPressed: _confirmer),
        ],
      ),
    );
  }

  Future<void> _telechargerRapport() async {
    final a = _apercu!;
    final chemin = await widget.enregistrer(widget.depot.nomDuRapport(a), widget.depot.rapport(a));
    if (!mounted) return;
    setState(() => _information = 'Rapport enregistré : $chemin');
  }

  @override
  Widget build(BuildContext context) {
    final modules = ImportationRepository.modulesAutorises(widget.role);
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(SymbolesAgri.upload_file, color: AgriColors.brandEmerald, size: 26),
                SizedBox(width: AgriSpacing.xs),
                Expanded(
                  child: Text(
                    'Importation en masse',
                    style: TextStyle(fontSize: AgriTypography.xl, fontWeight: FontWeight.w900, color: AgriColors.brandForest),
                  ),
                ),
              ],
            ),
            const Text(
              "Créez vos produits avec leur stock initial, vos clients ou vos fournisseurs à partir d'un tableur Excel (.xlsx) : "
              "téléchargez le modèle, remplissez-le, déposez-le, vérifiez l'aperçu, puis confirmez.",
              style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
            const SizedBox(height: AgriSpacing.md),
            _etapes(),
            const SizedBox(height: AgriSpacing.md),
            if (_information != null) _bandeau(_information!, AgriColors.brandEmerald, const Key('importation-information')),
            if (_erreur != null) _bandeau(_erreur!, AgriColors.errorRed, const Key('importation-erreur')),
            if (_occupe) const Padding(padding: EdgeInsets.all(AgriSpacing.md), child: LinearProgressIndicator()),
            if (_etape == 1) _choixModule(modules),
            if (_etape == 2 && _module != null) _modele(_module!),
            if (_etape == 3 && _module != null) _depot(_module!),
            if ((_etape == 4 || _etape == 6) && _apercu != null) ..._apercuOuRapport(_apercu!),
          ],
        ),
      ),
    );
  }

  Widget _bandeau(String texte, Color couleur, Key cle) => Container(
    key: cle,
    margin: const EdgeInsets.only(bottom: AgriSpacing.sm),
    padding: const EdgeInsets.all(AgriSpacing.md),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: 0.1),
      border: Border.all(color: couleur.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Text(texte, style: TextStyle(fontSize: AgriTypography.sm, color: couleur)),
  );

  Widget _etapes() {
    const noms = {1: 'Module', 2: 'Modèle', 3: 'Fichier', 4: 'Aperçu', 5: 'Confirmation', 6: 'Rapport'};
    return Wrap(
      key: const Key('importation-etapes'),
      spacing: AgriSpacing.xs,
      runSpacing: AgriSpacing.xs,
      children: [
        for (final e in noms.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 4),
            decoration: BoxDecoration(
              color: e.key == _etape ? AgriColors.brandEmerald : (e.key < _etape ? AgriColors.brandEmerald.withValues(alpha: 0.1) : Colors.white),
              border: Border.all(color: e.key == _etape ? AgriColors.brandEmerald : AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${e.key} ${e.value.toUpperCase()}',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: e.key == _etape ? Colors.white : AgriColors.brandForest,
              ),
            ),
          ),
      ],
    );
  }

  Widget _choixModule(List<ModuleImportation> modules) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('1 · QUE VOULEZ-VOUS IMPORTER ?', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.bold, color: AgriColors.brandForest)),
      const SizedBox(height: AgriSpacing.sm),
      Wrap(
        spacing: AgriSpacing.md,
        runSpacing: AgriSpacing.md,
        children: [
          for (final m in modules)
            SizedBox(
              width: 300,
              child: InkWell(
                key: Key('module-${m.cle}'),
                onTap: () => setState(() {
                  _reinitialiser();
                  _module = m;
                  _etape = 2;
                }),
                child: Container(
                  padding: const EdgeInsets.all(AgriSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AgriColors.outlineVariant),
                    borderRadius: BorderRadius.circular(AgriRadius.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_icone(m.cle), color: AgriColors.brandEmerald, size: 28),
                      const SizedBox(height: AgriSpacing.xs),
                      Text(m.libelle, style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.bold, color: AgriColors.onSurface)),
                      Text(m.description, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      const Text(
        "Seuls les modules que votre rôle permet d'importer sont proposés. Employés, plan comptable et barème de rationnement viendront dans une prochaine phase.",
        style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
      ),
    ],
  );

  static IconData _icone(String cle) => switch (cle) {
    'stocks' => SymbolesAgri.inventory_2,
    'clients' => SymbolesAgri.groups,
    _ => SymbolesAgri.local_shipping,
  };

  Widget _carte(Widget enfant) => Container(
    padding: const EdgeInsets.all(AgriSpacing.lg),
    constraints: const BoxConstraints(maxWidth: 760),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: enfant,
  );

  Widget _modele(ModuleImportation m) => Align(
    alignment: Alignment.centerLeft,
    child: _carte(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('2 · TÉLÉCHARGER LE MODÈLE « ${m.libelle.toUpperCase()} »', style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.bold, color: AgriColors.brandForest)),
          const SizedBox(height: AgriSpacing.xs),
          Text(
            'Le modèle (version ${m.version}) contient une feuille « Instructions » (rôle de chaque colonne, formats, exemples), la feuille « Données » à remplir et les listes à utiliser.',
            style: const TextStyle(fontSize: AgriTypography.sm),
          ),
          const SizedBox(height: AgriSpacing.sm),
          const Text("• Ne renommez pas les en-têtes : un fichier modifié est refusé avec la colonne en cause.", style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
          const Text("• Les montants sont des francs CFA entiers ; la création est SEULE : une fiche déjà présente est ignorée, jamais modifiée.", style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
          const Text('• Jusqu\'à 5 000 lignes et 5 Mo par fichier.', style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
          const SizedBox(height: AgriSpacing.md),
          Wrap(
            spacing: AgriSpacing.sm,
            runSpacing: AgriSpacing.sm,
            children: [
              FilledButton.icon(
                key: const Key('importation-telecharger-modele'),
                style: FilledButton.styleFrom(backgroundColor: AgriColors.brandEmerald),
                onPressed: _telechargerModele,
                icon: const Icon(SymbolesAgri.download, size: 18),
                label: const Text('Télécharger le modèle'),
              ),
              OutlinedButton.icon(
                key: const Key('importation-vers-depot'),
                onPressed: () => setState(() {
                  _etape = 3;
                  _erreur = null;
                }),
                icon: const Icon(SymbolesAgri.arrow_forward, size: 18),
                label: const Text("J'ai le modèle rempli : déposer mon fichier"),
              ),
              TextButton(key: const Key('importation-changer-module'), onPressed: () => setState(_reinitialiser), child: const Text('Changer de module')),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _depot(ModuleImportation m) => Align(
    alignment: Alignment.centerLeft,
    child: _carte(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('3 · DÉPOSER LE FICHIER « ${m.libelle.toUpperCase()} »', style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.bold, color: AgriColors.brandForest)),
          const SizedBox(height: AgriSpacing.sm),
          ZoneDepot(
            key: const Key('importation-depot-glisser'),
            actif: !_occupe,
            surFichier: _analyserFichier,
            enfant: (_, survol) => InkWell(
              key: const Key('importation-zone-depot'),
              onTap: _occupe ? null : _deposer,
              child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AgriSpacing.lg),
              // Survol : bordure et fond d'accent (`border-brand-emerald bg-brand-emerald/10` du Blade).
              decoration: BoxDecoration(
                color: survol ? AgriColors.brandEmerald.withValues(alpha: 0.10) : null,
                border: Border.all(color: survol ? AgriColors.brandEmerald : AgriColors.outlineVariant, width: 2),
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
              child: Column(
                children: [
                  const Icon(SymbolesAgri.upload_file, color: AgriColors.brandEmerald, size: 36),
                  const SizedBox(height: AgriSpacing.xs),
                  const Text('Glissez votre fichier .xlsx ici, ou cliquez pour le choisir', style: TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.bold)),
                  Text(
                    'Modèle « ${m.libelle} », version ${m.version} — 5 Mo et 5 000 lignes au plus',
                    style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
                  ),
                ],
              ),
            ),
            ),
          ),
          const SizedBox(height: AgriSpacing.md),
          Wrap(
            spacing: AgriSpacing.sm,
            children: [
              OutlinedButton(key: const Key('importation-retour-modele'), onPressed: () => setState(() => _etape = 2), child: const Text('Retour au modèle')),
              TextButton(onPressed: () => setState(_reinitialiser), child: const Text('Changer de module')),
            ],
          ),
        ],
      ),
    ),
  );

  List<LigneImportation> _filtrees(ApercuImportation a) =>
      _filtre == 'tous' ? a.lignes : a.lignes.where((l) => l.statut == _filtre).toList();

  List<Widget> _apercuOuRapport(ApercuImportation a) {
    final termine = a.termine;
    final filtrees = _filtrees(a);
    final pages = filtrees.isEmpty ? 1 : (filtrees.length / parPage).ceil();
    final page = _page.clamp(1, pages);
    final visibles = filtrees.skip((page - 1) * parPage).take(parPage).toList();
    final filtres = <String, String>{
      'tous': 'Toutes les lignes',
      'refusee': 'Refusées seulement',
      'ignoree': 'Ignorées seulement',
      if (termine) 'creee': 'Créées seulement' else 'valide': 'Valides seulement',
    };

    return [
      Text(
        termine ? "6 · RAPPORT D'IMPORTATION" : "4 · APERÇU — RIEN N'EST ENCORE ÉCRIT",
        style: const TextStyle(fontSize: AgriTypography.sm, fontWeight: FontWeight.bold, color: AgriColors.brandForest),
      ),
      Text(
        "Fichier « ${a.nomFichier} » · modèle « ${a.module.libelle} » version ${a.module.version}.",
        style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
      ),
      const SizedBox(height: AgriSpacing.sm),
      if (!termine && a.bloquant != null)
        _bandeau('${a.bloquant} L\'importation ne peut pas être confirmée.', AgriColors.errorRed, const Key('importation-bloque')),
      Wrap(
        spacing: AgriSpacing.md,
        runSpacing: AgriSpacing.md,
        children: [
          SizedBox(width: 220, child: CarteKpi(libelle: 'Lignes lues', valeur: '${a.lues}', couleurLisere: AgriColors.brandForest, icone: SymbolesAgri.list_alt)),
          SizedBox(
            width: 220,
            child: CarteKpi(
              libelle: termine ? 'Créées' : 'Valides',
              valeur: '${termine ? a.creees : a.valides}',
              couleurLisere: AgriColors.brandEmerald,
              icone: SymbolesAgri.check_circle,
            ),
          ),
          SizedBox(width: 220, child: CarteKpi(libelle: 'Ignorées (déjà présentes)', valeur: '${a.ignorees}', couleurLisere: AgriColors.accentYellow, icone: SymbolesAgri.category)),
          SizedBox(width: 220, child: CarteKpi(libelle: 'Refusées', valeur: '${a.refusees}', couleurLisere: AgriColors.errorRed, icone: SymbolesAgri.error)),
        ],
      ),
      if (termine && a.module.cle == 'stocks')
        const Padding(
          padding: EdgeInsets.only(top: AgriSpacing.sm),
          child: Text(
            "Un produit déjà au catalogue est IGNORÉ : son stock initial n'a pas été ajouté (deux déclarations du même article sont le même stock physique ; un écart se corrige par un inventaire).",
            style: TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
          ),
        ),
      const SizedBox(height: AgriSpacing.sm),
      Wrap(
        spacing: AgriSpacing.xs,
        children: [
          for (final f in filtres.entries)
            ChoiceChip(
              key: Key('importation-filtre-${f.key}'),
              label: Text(f.value),
              selected: _filtre == f.key,
              onSelected: (_) => setState(() {
                _filtre = f.key;
                _page = 1;
              }),
            ),
        ],
      ),
      const SizedBox(height: AgriSpacing.sm),
      _tableau(a, visibles),
      const SizedBox(height: AgriSpacing.sm),
      Row(
        children: [
          Expanded(
            child: Text(
              '${filtrees.length} ${filtrees.length > 1 ? 'lignes' : 'ligne'} — page $page sur $pages',
              key: const Key('importation-pagination'),
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline),
            ),
          ),
          OutlinedButton(key: const Key('importation-page-precedente'), onPressed: page <= 1 ? null : () => setState(() => _page = page - 1), child: const Text('Précédent')),
          const SizedBox(width: AgriSpacing.xs),
          OutlinedButton(key: const Key('importation-page-suivante'), onPressed: page >= pages ? null : () => setState(() => _page = page + 1), child: const Text('Suivant')),
        ],
      ),
      const SizedBox(height: AgriSpacing.lg),
      Wrap(
        spacing: AgriSpacing.sm,
        runSpacing: AgriSpacing.sm,
        children: [
          if (!termine) ...[
            OutlinedButton(key: const Key('importation-changer-fichier'), onPressed: () => setState(() => _etape = 3), child: const Text('Changer de fichier')),
            FilledButton.icon(
              key: const Key('importation-importer'),
              style: FilledButton.styleFrom(backgroundColor: AgriColors.brandEmerald),
              onPressed: (a.valides == 0 || a.bloquant != null || _occupe) ? null : _ouvrirConfirmation,
              icon: const Icon(SymbolesAgri.task_alt, size: 18),
              label: Text('Importer ${a.valides} ${a.valides > 1 ? 'lignes' : 'ligne'}'),
            ),
            TextButton(key: const Key('importation-abandonner'), onPressed: () => setState(_reinitialiser), child: const Text('Abandonner')),
          ] else ...[
            FilledButton.icon(
              key: const Key('importation-telecharger-rapport'),
              style: FilledButton.styleFrom(backgroundColor: AgriColors.brandEmerald),
              onPressed: _telechargerRapport,
              icon: const Icon(SymbolesAgri.download, size: 18),
              label: const Text('Télécharger le rapport'),
            ),
            if (a.refusees > 0)
              OutlinedButton(
                key: const Key('importation-corriger'),
                onPressed: () => setState(() {
                  final m = a.module;
                  _reinitialiser();
                  _module = m;
                  _etape = 3;
                }),
                child: const Text('Corriger le fichier puis ré-importer'),
              ),
            TextButton(key: const Key('importation-nouvel-import'), onPressed: () => setState(_reinitialiser), child: const Text('Nouvel import')),
          ],
        ],
      ),
    ];
  }

  Widget _tableau(ApercuImportation a, List<LigneImportation> lignes) {
    const entetes = ['Ligne', 'Désignation', 'Valeurs lues', 'Résultat', 'Motif'];
    TableRow rangee(List<Widget> cellules, {bool entete = false}) => TableRow(
      decoration: BoxDecoration(color: entete ? AgriColors.surfaceZebra : null, border: const Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
      children: cellules,
    );
    Widget cellule(String t, {bool gras = false, Color? couleur, Key? cle}) => Padding(
      padding: const EdgeInsets.all(AgriSpacing.sm),
      child: Text(t, key: cle, style: TextStyle(fontSize: AgriTypography.xs, fontWeight: gras ? FontWeight.bold : null, color: couleur)),
    );
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AgriColors.outlineVariant), borderRadius: BorderRadius.circular(AgriRadius.lg)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 900),
          child: Table(
            columnWidths: const {0: FixedColumnWidth(60), 1: FlexColumnWidth(2), 2: FlexColumnWidth(3), 3: FixedColumnWidth(170), 4: FlexColumnWidth(4)},
            children: [
              rangee([for (final e in entetes) cellule(e.toUpperCase(), gras: true, couleur: AgriColors.outline)], entete: true),
              if (lignes.isEmpty)
                rangee([cellule(''), cellule('Aucune ligne pour ce filtre.'), cellule(''), cellule(''), cellule('')])
              else
                for (final l in lignes)
                  rangee([
                    cellule('${l.ligne}', gras: true),
                    cellule(l.designation.isEmpty ? '—' : l.designation),
                    cellule(l.brut == null ? '—' : _valeurs(l.brut!), couleur: AgriColors.outline),
                    cellule(
                      ImportationRepository.libelleDeStatut(l.statut, termine: a.termine).toUpperCase(),
                      gras: true,
                      couleur: l.statut == ImportationRepository.refusee ? AgriColors.errorRed : AgriColors.brandForest,
                      cle: Key('importation-ligne-${l.ligne}-statut'),
                    ),
                    cellule(l.motif ?? '', cle: Key('importation-ligne-${l.ligne}-motif')),
                  ]),
            ],
          ),
        ),
      ),
    );
  }

  static String _valeurs(Map<String, String> brut) {
    final t = brut.values.where((v) => v.isNotEmpty).join(' · ');
    return t.length > 90 ? '${t.substring(0, 87)}...' : t;
  }
}
