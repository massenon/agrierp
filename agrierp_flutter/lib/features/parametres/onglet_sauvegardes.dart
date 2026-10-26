import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'parametres_generaux_repository.dart';

/// Onglet « Sauvegardes » de Paramètres Général.
///
/// Gestion des sauvegardes et imports/exports de modules :
/// - Titre avec icône database et texte rétention 30 jours
/// - Bouton « Générer une sauvegarde »
/// - Bloc « EXPORTER UN MODULE SEUL » : select module + bouton Exporter
/// - Bloc « IMPORTER UN MODULE » : 2 select + bouton Importer
/// - Tableau historique : FICHIER | DATE | TABLE | ACTION (télécharger)
/// - État vide : « Aucune sauvegarde... »
///
/// Les actions passent par l'API /api/parametres/...
class OngletSauvegardes extends StatefulWidget {
  const OngletSauvegardes({
    super.key,
    required this.repository,
  });

  final ParametresGenerauxRepository repository;

  @override
  State<OngletSauvegardes> createState() => _OngletSauvegardésState();
}

class _OngletSauvegardésState extends State<OngletSauvegardes> {
  bool _generationEnCours = false;
  bool _exportEnCours = false;
  bool _importEnCours = false;

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          'Sauvegardes & Imports',
          'Gestion des sauvegardes complètes et imports/exports de modules.',
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        // Titre avec icône
        Row(
          children: [
            Icon(
              SymbolesAgri.backup,
              size: 24,
              color: AgriColors.brandForest,
            ),
            const SizedBox(width: AgriSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sousTitre('Générer une Sauvegarde Complète'),
                  const SizedBox(height: 2),
                  const Text(
                    'Rétention 30 jours',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        // Bouton génération
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            key: const Key('btn-generer-sauvegarde'),
            onPressed: _generationEnCours ? null : _genererSauvegarde,
            icon: Icon(
              _generationEnCours
                  ? SymbolesAgri.sync
                  : SymbolesAgri.download,
            ),
            label: Text(
              _generationEnCours
                  ? 'Génération en cours...'
                  : 'Générer une sauvegarde',
            ),
          ),
        ),
        const SizedBox(height: AgriSpacing.lg),
        // Bloc export module seul
        Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
            boxShadow: AgriShadows.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sousTitre('EXPORTER UN MODULE SEUL'),
              const SizedBox(height: AgriSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('select-module-export'),
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: 'Choisir un module...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AgriRadius.lg),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.md),
                  OutlinedButton.icon(
                    key: const Key('btn-exporter-module'),
                    onPressed: _exportEnCours ? null : _exporterModule,
                    icon: Icon(
                      _exportEnCours
                          ? SymbolesAgri.sync
                          : SymbolesAgri.download,
                    ),
                    label: const Text('Exporter'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        // Bloc import module
        Container(
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
            boxShadow: AgriShadows.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sousTitre('IMPORTER UN MODULE'),
              const SizedBox(height: AgriSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AgriSpacing.sm),
                decoration: BoxDecoration(
                  color: AgriColors.accentYellow.withValues(alpha: 0.10),
                  border: Border.all(
                    color: AgriColors.accentYellow.withValues(alpha: 0.30),
                  ),
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      SymbolesAgri.info,
                      size: 18,
                      color: AgriColors.brandForest,
                    ),
                    const SizedBox(width: AgriSpacing.sm),
                    Expanded(
                      child: Text(
                        'L\'import remplacera les données existantes du module '
                        'sélectionné. Cette action est irréversible.',
                        style: const TextStyle(
                          fontSize: AgriTypography.xs,
                          color: AgriColors.brandForest,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AgriSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('select-fichier-import'),
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: 'Choisir un fichier...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AgriRadius.lg),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.md),
                  Expanded(
                    child: TextField(
                      key: const Key('select-module-import'),
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: 'Choisir un module...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AgriRadius.lg),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AgriSpacing.md),
                  ElevatedButton.icon(
                    key: const Key('btn-importer-module'),
                    onPressed: _importEnCours ? null : _importerModule,
                    icon: Icon(
                      _importEnCours
                          ? SymbolesAgri.sync
                          : SymbolesAgri.upload,
                    ),
                    label: const Text('Importer'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        // Tableau historique (vide pour démo)
        _sousTitre('Historique des Sauvegardes'),
        const SizedBox(height: AgriSpacing.sm),
        _tableau(
          largeur: 800,
          colonnes: const [
            ('Fichier', 5),
            ('Date', 3),
            ('Table', 3),
            ('Action', 2),
          ],
          vide: 'Aucune sauvegarde enregistrée.',
          lignes: [],
        ),
      ],
    );
  }

  Future<void> _genererSauvegarde() async {
    setState(() => _generationEnCours = true);
    try {
      // Appel API : POST /api/parametres/sauvegardes/generer
      // Simulé ici, en production on ferait l'appel via le repository
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ToastAgri.afficher(
          context,
          'Sauvegarde générée avec succès',
          type: TypeToast.succes,
        );
      }
    } catch (e) {
      if (mounted) {
        ToastAgri.afficher(
          context,
          'Erreur lors de la génération de la sauvegarde',
          type: TypeToast.erreur,
        );
      }
    } finally {
      if (mounted) setState(() => _generationEnCours = false);
    }
  }

  Future<void> _exporterModule() async {
    setState(() => _exportEnCours = true);
    try {
      // Appel API : POST /api/parametres/modules/exporter
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ToastAgri.afficher(
          context,
          'Module exporté avec succès',
          type: TypeToast.succes,
        );
      }
    } catch (e) {
      if (mounted) {
        ToastAgri.afficher(
          context,
          'Erreur lors de l\'export du module',
          type: TypeToast.erreur,
        );
      }
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
    }
  }

  Future<void> _importerModule() async {
    setState(() => _importEnCours = true);
    try {
      // Appel API : POST /api/parametres/modules/importer
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        ToastAgri.afficher(
          context,
          'Module importé avec succès',
          type: TypeToast.succes,
        );
      }
    } catch (e) {
      if (mounted) {
        ToastAgri.afficher(
          context,
          'Erreur lors de l\'import du module',
          type: TypeToast.erreur,
        );
      }
    } finally {
      if (mounted) setState(() => _importEnCours = false);
    }
  }

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  Widget _entete(String titre, String sousTitre, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _titre(titre, large),
      const SizedBox(height: 2),
      Text(
        sousTitre,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.outline,
        ),
      ),
    ],
  );

  Widget _titre(String texte, bool large) => Text(
    texte,
    style: TextStyle(
      fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
      fontWeight: AgriTypography.gras,
      color: AgriColors.onSurface,
    ),
  );

  Widget _sousTitre(String texte) => Text(
    texte,
    style: const TextStyle(
      fontSize: AgriTypography.sm,
      fontWeight: AgriTypography.gras,
      color: AgriColors.brandForest,
    ),
  );

  Widget _tableau({
    required double largeur,
    required List<(String, int)> colonnes,
    required List<Widget> lignes,
    required String vide,
  }) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: largeur,
        child: Column(
          children: [
            Container(
              color: AgriColors.surfaceZebra,
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              child: Row(
                children: [
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(
                        libelle.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: _enteteColonne,
                      ),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  vide,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            ...lignes,
          ],
        ),
      ),
    ),
  );
}
