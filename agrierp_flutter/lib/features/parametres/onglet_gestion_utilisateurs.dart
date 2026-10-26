import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/carte_kpi.dart';
import 'parametres_generaux_repository.dart';

/// Onglet « Gestion des Utilisateurs » de Paramètres Général.
///
/// Affiche une liste des utilisateurs avec leurs informations :
/// - 2 KPI Cards : utilisateurs actifs, rôles définis
/// - Tableau : NOM | EMAIL | RÔLE | STATUT | ACTIONS
/// - Lecture seule au poste (création/suppression sur le web)
class OngletGestionUtilisateurs extends StatelessWidget {
  const OngletGestionUtilisateurs({
    super.key,
    required this.donnees,
    this.repository,
  });

  final DonneesParametresGeneraux donnees;

  /// Optionnel : repository pour les appels API
  final ParametresGenerauxRepository? repository;

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          'Gestion des Utilisateurs',
          "Administration des comptes d'accès à AgriERP.",
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        _grilleKpis(large, [
          CarteKpi(
            libelle: 'Utilisateurs actifs',
            valeur: '${donnees.utilisateursActifs}',
            couleurLisere: AgriColors.brandEmerald,
            icone: SymbolesAgri.group,
          ),
          CarteKpi(
            libelle: 'Rôles définis',
            valeur: '${donnees.roles.length}',
            couleurLisere: AgriColors.infoBlue,
            icone: SymbolesAgri.badge,
            couleurIcone: AgriColors.infoBlue,
          ),
        ]),
        const SizedBox(height: AgriSpacing.md),
        _tableau(
          largeur: 900,
          colonnes: const [
            ('Nom', 5),
            ('Email', 5),
            ('Rôle', 4),
            ('Statut', 3),
            ('Actions', 2),
          ],
          vide: '— Aucun utilisateur synchronisé —',
          lignes: [
            for (var i = 0; i < donnees.utilisateurs.length; i++)
              _ligne(i, [
                (
                  Text(
                    donnees.utilisateurs[i].name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                    ),
                  ),
                  5,
                ),
                (
                  Text(
                    donnees.utilisateurs[i].email ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: _cellule,
                  ),
                  5,
                ),
                (
                  Text(
                    donnees.utilisateurs[i].role ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: _cellule,
                  ),
                  4,
                ),
                (
                  _pastille(
                    donnees.utilisateurs[i].isActive ? 'Actif' : 'Désactivé',
                    couleur: donnees.utilisateurs[i].isActive
                        ? AgriColors.brandEmerald
                        : AgriColors.outline,
                  ),
                  3,
                ),
                (_actionInerte(), 2),
              ]),
          ],
        ),
        const SizedBox(height: AgriSpacing.md),
        _mentionPoste(
          'La liste dit qui travaille sur la ferme — jamais comment se '
          'connecter : aucun mot de passe ni jeton ne descend. Créer un compte, '
          'archiver un utilisateur ou réinitialiser un mot de passe se fait sur '
          'la surface web.',
          cle: 'utilisateurs',
        ),
      ],
    );
  }

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

  Widget _pastille(String libelle, {Color couleur = AgriColors.brandEmerald}) =>
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          libelle,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: AgriTypography.gras,
            color: couleur,
          ),
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
