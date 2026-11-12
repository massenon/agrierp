import 'package:flutter/material.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';

/// Variantes du `BoutonAction` — fidèles aux trois patrons de bouton mesurés
/// sur les vues Blade (`agrierp_laravel/resources/views/livewire/`).
///
/// | Variante   | Fond                       | Texte         | Bordure          |
/// |------------|----------------------------|---------------|------------------|
/// | primaire   | `brand-emerald` (#065F46)  | blanc         | aucune           |
/// | secondaire | blanc                      | `outline`     | `outline-variant`|
/// | danger     | `error-red` (#DC2626)      | blanc         | aucune           |
enum VarianteBouton { primaire, secondaire, danger }

/// Bouton d'action principal du poste — transposition fidèle du patron Blade
/// mesuré sur `agrierp_laravel/resources/views/livewire/`.
///
/// **Dimensions mesurées sur le Blade (ticket E1, 12/11/2026) :**
/// - Padding horizontal : `px-md` = `AgriSpacing.md` = 16 px
/// - Padding vertical   : `py-sm` = `AgriSpacing.sm` =  8 px
/// - Rayon de bordure   : `rounded-lg` = `AgriRadius.lg` = 8 px
/// - Taille de police   : `text-sm` = 14 px
/// - Graisse            : `font-bold`
///
/// **Usage :**
/// ```dart
/// BoutonAction(
///   label: 'Enregistrer',
///   onPressed: () => _sauvegarder(),
///   icone: Icons.save,
/// )
/// BoutonAction(
///   label: 'Annuler',
///   onPressed: () => Navigator.pop(context),
///   variante: VarianteBouton.secondaire,
/// )
/// BoutonAction(
///   label: 'Supprimer',
///   onPressed: null, // désactivé
///   variante: VarianteBouton.danger,
/// )
/// ```
///
/// ⚠️ Ce widget est POUR LES BOUTONS D'ACTION DES ÉCRANS, pas pour
/// l'authentification. `BoutonConnexion` (`login_screen.dart`) reste le
/// composant du formulaire de connexion et du verrou local.
class BoutonAction extends StatelessWidget {
  const BoutonAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icone,
    this.variante = VarianteBouton.primaire,
  });

  final String label;

  /// Callback déclenché à l'appui. `null` → bouton grisé (désactivé).
  final VoidCallback? onPressed;

  final IconData? icone;
  final VarianteBouton variante;

  // ── Constantes mesurées sur le Blade (E1) ────────────────────────────────

  /// `px-md` = 16 px
  static const double _paddingH = AgriSpacing.md;

  /// `py-sm` = 8 px
  static const double _paddingV = AgriSpacing.sm;

  /// `rounded-lg` = 8 px
  static const double _rayon = AgriRadius.lg;

  /// `text-sm` = 14 px
  static const double _taillePolicePx = 14;

  // ── Couleurs par variante ─────────────────────────────────────────────────

  Color _fond(bool actif) {
    if (!actif) return AgriColors.outlineVariant.withOpacity(0.3);
    return switch (variante) {
      VarianteBouton.primaire => AgriColors.brandEmerald,
      VarianteBouton.secondaire => AgriColors.surfaceCard,
      VarianteBouton.danger => AgriColors.errorRed,
    };
  }

  Color _texte(bool actif) {
    if (!actif) return AgriColors.outline;
    return switch (variante) {
      VarianteBouton.primaire => Colors.white,
      VarianteBouton.secondaire => AgriColors.outline,
      VarianteBouton.danger => Colors.white,
    };
  }

  BorderSide _bordure(bool actif) {
    if (variante == VarianteBouton.secondaire) {
      return BorderSide(
        color: actif ? AgriColors.outlineVariant : AgriColors.outlineVariant.withOpacity(0.5),
      );
    }
    return BorderSide.none;
  }

  @override
  Widget build(BuildContext context) {
    final actif = onPressed != null;
    final couleurTexte = _texte(actif);

    final style = ElevatedButton.styleFrom(
      backgroundColor: _fond(actif),
      foregroundColor: couleurTexte,
      disabledBackgroundColor: _fond(false),
      disabledForegroundColor: _texte(false),
      elevation: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: _paddingH,
        vertical: _paddingV,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_rayon),
        side: _bordure(actif),
      ),
      textStyle: const TextStyle(
        fontSize: _taillePolicePx,
        fontWeight: FontWeight.bold,
      ),
    );

    if (icone != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icone, size: 16),
        label: Text(label),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}
