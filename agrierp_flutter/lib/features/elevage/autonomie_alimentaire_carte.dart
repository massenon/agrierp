import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../stocks/pmp_service.dart';
import 'jour_categories.dart';

/// `resources/views/components/autonomie-alimentaire.blade.php` — UN SEUL composant, comme au web : fiches Lapins /
/// Porcs et tiroir de « Bandes & Sujets ». Aucun produit suivi, rupture, consommation inconnue, alerte critique, ou
/// autonomie en jours. ⚠️ N'EMPÊCHE JAMAIS un enregistrement : c'est une information, pas un contrôle.
///
/// [filiere] complète le message « aucun produit de provende … » (`de la filière Lapins`, `lapins`…).
class CarteAutonomieAlimentaire extends StatelessWidget {
  const CarteAutonomieAlimentaire({
    super.key,
    required this.autonomie,
    required this.filiere,
    this.onCommanderStock,
  });

  final AutonomieAlimentaire autonomie;
  final String filiere;

  /// « Commander Stock » (`/achats-commandes` au web).
  final VoidCallback? onCommanderStock;

  @override
  Widget build(BuildContext context) {
    final a = autonomie;
    Widget alerte(String titre, String texte) => Container(
      key: const Key('autonomie-alimentaire'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.errorBg,
        border: Border.all(color: AgriColors.errorDeep.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        boxShadow: AgriShadows.sm,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: AgriSpacing.sm,
        runSpacing: AgriSpacing.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(SymbolesAgri.warning, size: 22, color: AgriColors.errorDeep),
              const SizedBox(width: AgriSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        fontSize: AgriTypography.sm,
                        fontWeight: AgriTypography.gras,
                        color: AgriColors.errorDeep,
                      ),
                    ),
                    Text(texte, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep)),
                  ],
                ),
              ),
            ],
          ),
          ElevatedButton(
            key: const Key('commander-stock'),
            onPressed: onCommanderStock,
            style: ElevatedButton.styleFrom(
              backgroundColor: AgriColors.errorRed,
              foregroundColor: AgriColors.surfaceCard,
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.full)),
            ),
            child: const Text(
              'Commander Stock',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras),
            ),
          ),
        ],
      ),
    );
    Widget simple(List<InlineSpan> morceaux, Color fond, Color bord) => Container(
      key: const Key('autonomie-alimentaire'),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: fond,
        border: Border.all(color: bord),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Text.rich(
        TextSpan(children: morceaux),
        style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.brandForest),
      ),
    );
    const gras = TextStyle(fontWeight: AgriTypography.gras);
    final nom = a.produit?.name;
    final stock = a.stockKg == null ? '' : PmpService.flottant(a.stockKg!);
    final jours = a.jours == null ? '' : PmpService.flottant(a.jours!);

    if (!a.disponible) {
      return Container(
        key: const Key('autonomie-alimentaire'),
        padding: const EdgeInsets.all(AgriSpacing.sm),
        decoration: BoxDecoration(
          color: AgriColors.errorBg,
          border: Border.all(color: AgriColors.errorDeep.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(SymbolesAgri.warning, size: 18, color: AgriColors.errorDeep),
                SizedBox(width: AgriSpacing.xs),
                Expanded(
                  child: Text(
                    'Autonomie alimentaire : aucun stock de provende suivi',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.errorDeep,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              "Aucun produit de provende $filiere n'existe en catalogue avec un stock suivi : créez-le et "
              'approvisionnez-vous. La fiche s\'enregistre quand même.',
              style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorDeep),
            ),
          ],
        ),
      );
    }
    if (a.rupture) {
      return alerte(
        'Autonomie alimentaire : rupture de stock',
        'Le stock de $nom est épuisé ($stock Kg) : approvisionnez-vous. La fiche s\'enregistre quand même.',
      );
    }
    if (a.inconnu) {
      return simple(
        [
          const TextSpan(text: 'Autonomie alimentaire : '),
          const TextSpan(text: '—', style: gras),
          TextSpan(
            text: ' ($nom, $stock Kg en stock) — la consommation du jour est inconnue tant que les effectifs par '
                'catégorie le sont.',
          ),
        ],
        AgriColors.surfaceZebra,
        AgriColors.outlineVariant,
      );
    }
    if (a.critique) {
      return alerte(
        'Alerte critique - Autonomie alimentaire',
        'Le stock de $nom ne couvre plus que $jours jours de consommation théorique du cheptel actif ! '
            'Approvisionnez-vous.',
      );
    }
    return simple(
      [
        const TextSpan(text: 'Autonomie alimentaire : '),
        TextSpan(text: '$jours jours', style: gras),
        TextSpan(text: ' ($nom, $stock Kg en stock).'),
      ],
      AgriColors.brandEmerald.withValues(alpha: 0.05),
      AgriColors.brandEmerald.withValues(alpha: 0.2),
    );
  }
}
