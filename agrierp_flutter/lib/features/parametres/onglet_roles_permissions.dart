import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import 'parametres_generaux_repository.dart';
import 'parametres_generaux_screen.dart';

/// Onglet « Rôles & Permissions » de Paramètres Général.
///
/// Affiche une matrice de droits d'accès : rôles en lignes, modules en colonnes,
/// avec des icônes pour indiquer les permissions accordées. Lecture seule au poste.
///
/// Étapes de conception :
/// 1. 4 KPI Cards : nombre de rôles, utilisateurs assignés, modules couverts, dernière sauvegarde
/// 2. Matrice 11 colonnes : Rôle + 9 modules + Actions
/// 3. Boutons inerts (export PDF, nouveau rôle)
/// 4. Mention poste : les actions se font sur le web
class OngletRolesPermissions extends StatelessWidget {
  const OngletRolesPermissions({
    super.key,
    required this.donnees,
  });

  final DonneesParametresGeneraux donnees;

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          'Rôles & Permissions',
          "Matrice de droits d'accès et sauvegardes de la base de données.",
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        _grilleKpis(large, [
          CarteKpi(
            libelle: 'Rôles configurés',
            valeur: '${donnees.roles.length}',
            couleurLisere: AgriColors.brandEmerald,
            icone: SymbolesAgri.shield,
          ),
          CarteKpi(
            libelle: 'Utilisateurs assignés',
            valeur: '${donnees.utilisateurs.length}',
            couleurLisere: AgriColors.infoBlue,
            icone: SymbolesAgri.group,
            couleurIcone: AgriColors.infoBlue,
          ),
          CarteKpi(
            libelle: 'Modules couverts',
            valeur: '${ParametresGenerauxScreen.permissionsMatrice.length}',
            couleurLisere: AgriColors.brandForest,
            icone: SymbolesAgri.apps,
            couleurIcone: AgriColors.brandForest,
          ),
          const CarteKpi(
            libelle: 'Dernière sauvegarde',
            valeur: '—',
            legende: 'Sauvegardes gardées sur le serveur',
            couleurLisere: AgriColors.outline,
            icone: SymbolesAgri.backup,
            couleurIcone: AgriColors.outline,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        _sousTitre("Matrice des Droits d'Accès"),
        const SizedBox(height: AgriSpacing.sm),
        _tableau(
          largeur: 1180,
          colonnes: ParametresGenerauxScreen.colonnesMatrice,
          vide: '— Aucun rôle synchronisé —',
          lignes: [
            for (var i = 0; i < donnees.roles.length; i++)
              _ligne(i, [
                (
                  Text(
                    donnees.roles[i].name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandEmerald,
                    ),
                  ),
                  4,
                ),
                for (final permission
                    in ParametresGenerauxScreen.permissionsMatrice)
                  (_droit(_accorde(donnees.roles[i], permission)), 2),
                (_actionInerte(), 2),
              ]),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _mentionPoste(
          'La matrice montre les rôles que le SERVEUR applique réellement, avec '
          'leurs permissions — la maquette, elle, en dessine cinq nommés. Cet '
          'écart est un arbitrage client ouvert. Créer ou modifier un rôle, comme '
          'générer une sauvegarde, se fait sur la surface web.',
          cle: 'roles',
        ),
      ],
    );
  }

  /// Un rôle accorde-t-il ce module ?
  ///
  /// ⚠️ `admin` porte toutes les permissions nommées : rien n'est présumé, la
  /// liste descend telle quelle du serveur.
  bool _accorde(RolesApplicatif role, String? permission) {
    // Le tableau de bord n'a pas de permission : il est l'écran commun.
    if (permission == null) return true;

    final accordees = (role.permissions ?? '')
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);

    return accordees.contains(permission);
  }

  Widget _droit(bool accorde) => Align(
    alignment: Alignment.centerLeft,
    child: Icon(
      accorde ? SymbolesAgri.check_circle : SymbolesAgri.remove,
      size: 16,
      color: accorde ? AgriColors.brandEmerald : AgriColors.outline,
    ),
  );

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

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

  Widget _grilleKpis(bool large, List<Widget> cartes) =>
      GrilleKpi(colonnes: large ? cartes.length : 2, children: cartes);

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

  Widget _ligne(int index, List<(Widget, int)> cellules) => Container(
    key: Key('ligne-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        for (final (contenu, flex) in cellules)
          Expanded(flex: flex, child: contenu),
      ],
    ),
  );

  Widget _actionInerte() => const Opacity(
    opacity: 0.4,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Icon(SymbolesAgri.visibility, size: 16, color: AgriColors.outline),
    ),
  );

  Widget _mentionPoste(
    String texte, {
    required String cle,
    Color couleur = AgriColors.accentYellow,
  }) => Container(
    key: Key('mention-$cle'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: 0.10),
      border: Border.all(
        color: couleur.withValues(alpha: 0.30),
      ),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(SymbolesAgri.info, size: 18, color: AgriColors.brandForest),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    ),
  );
}
