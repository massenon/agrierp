import 'package:flutter/material.dart';

import '../auth/permissions_poste.dart';
import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket H1 — BOUTON FLOTTANT ET PANNEAU « ACCÈS RAPIDE », transposés de `layouts/app.blade.php:219-247` (le
/// maître). 🔴 Ils n'existaient pas au poste : les fiches d'espèce n'étaient atteignables que par Gestion Élevage.
///
/// Web :
/// - bouton : `fixed bottom:88px right:16px z-[60] w-12 h-12 rounded-full bg-brand-emerald hover:bg-brand-forest
///   text-white shadow-lg`, icône `apps` 24 px, title « Accès rapide Élevage & Modules » ;
/// - voile : `fixed inset-0 bg-black/40` (un clic ferme) ;
/// - tiroir : `fixed top-0 right-0 h-full w-72 max-w-[85vw] bg-white shadow-2xl`, glissé depuis la droite en 300 ms ;
/// - en-tête : `px-md py-md border-b border-outline-variant bg-brand-forest`, icône `apps` `text-brand-maize` 20 px,
///   « Accès Rapide » `text-white font-bold text-sm`, fermeture `close` `text-white/80` ;
/// - entrées : `flex items-center gap-sm px-sm py-sm rounded-lg text-on-surface hover:bg-surface-zebra`, icône
///   22 px, libellé `text-sm font-semibold` ; séparateurs `border-t border-outline-variant my-xs`.
///
/// ⚠️ Le web n'applique AUCUN filtre de rôle au panneau : toutes les entrées sont affichées, et c'est la route qui
/// refuse. Au poste, `GardeEcran` refuse de même l'écran interdit.
///
/// ⚠️ Le second bouton flottant du web, « Visite guidée » (`help`, bleu), n'a AUCUN gestionnaire : il est inerte.
/// Il n'est pas porté tant qu'il ne fait rien (un bouton mort au poste serait pire qu'un bouton absent).
class AccesRapide {
  AccesRapide._();

  /// Les trois groupes du web, dans l'ordre, avec leur couleur d'icône. Libellés EXACTS du web, même là où ils
  /// diffèrent de la barre latérale (« Fiche Lapins » au singulier, « Rapports et Exports »).
  static const groupes = <(Color, List<(IconData, String, EcranPoste)>)>[
    (
      AgriColors.brandEmerald,
      [
        (SymbolesAgri.cruelty_free, 'Fiche Lapins', EcranPoste.ficheElevage),
        (SymbolesAgri.egg, 'Fiche Pondeuses', EcranPoste.fichePondeuses),
        (SymbolesAgri.egg_alt, 'Fiche Volailles Reproducteurs', EcranPoste.ficheReproducteurs),
        (SymbolesAgri.pets, 'Fiche Porcs', EcranPoste.fichePorcs),
        (SymbolesAgri.bug_report, 'Fiche Escargots', EcranPoste.ficheEscargots),
      ],
    ),
    (
      AgriColors.infoBlue,
      [
        (SymbolesAgri.favorite, 'Suivi Reproduction', EcranPoste.suiviReproduction),
        (SymbolesAgri.vaccines, 'Calendrier Soins & Vaccins', EcranPoste.soinsEtVaccins),
      ],
    ),
    (
      AgriColors.brandForest,
      [
        (SymbolesAgri.point_of_sale, 'Ventes & Devis', EcranPoste.ventesEtDevis),
        (SymbolesAgri.inventory_2, 'Gestion Stocks', EcranPoste.gestionStocks),
        (SymbolesAgri.dashboard, 'Tableau de Bord', EcranPoste.tableauDeBord),
        (SymbolesAgri.receipt, 'Saisie Dépenses', EcranPoste.saisieDepenses),
        (SymbolesAgri.account_balance, 'Comptabilité', EcranPoste.comptabilite),
        (SymbolesAgri.picture_as_pdf, 'Rapports et Exports', EcranPoste.rapportsEtExports),
      ],
    ),
  ];

  /// Ouvre le tiroir ; [onNaviguer] reçoit l'écran choisi, APRÈS la fermeture du tiroir.
  static Future<void> ouvrir(BuildContext context, {required void Function(EcranPoste) onNaviguer}) async {
    final choix = await showGeneralDialog<EcranPoste>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      // `bg-black/40`.
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (contexte, _, _) => const _Panneau(),
      transitionBuilder: (_, animation, _, enfant) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: enfant,
      ),
    );
    if (choix != null) onNaviguer(choix);
  }
}

/// Bouton flottant `apps`, à placer dans un `Stack` au-dessus du contenu (`bottom:88px right:16px`).
class BoutonAccesRapide extends StatelessWidget {
  const BoutonAccesRapide({super.key, required this.onNaviguer});

  final void Function(EcranPoste) onNaviguer;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: AgriSpacing.md,
      bottom: 88,
      child: Tooltip(
        message: 'Accès rapide Élevage & Modules',
        child: Material(
          key: const Key('bouton-acces-rapide'),
          color: AgriColors.brandEmerald,
          shape: const CircleBorder(),
          elevation: 6,
          child: InkWell(
            customBorder: const CircleBorder(),
            hoverColor: AgriColors.brandForest,
            onTap: () => AccesRapide.ouvrir(context, onNaviguer: onNaviguer),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(SymbolesAgri.apps, size: 24, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panneau extends StatelessWidget {
  const _Panneau();

  @override
  Widget build(BuildContext context) {
    final largeur = MediaQuery.sizeOf(context).width;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        key: const Key('panneau-acces-rapide'),
        color: Colors.white,
        elevation: 24,
        child: SizedBox(
          // `w-72 max-w-[85vw]`.
          width: largeur * 0.85 < 288 ? largeur * 0.85 : 288,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(AgriSpacing.md),
                decoration: const BoxDecoration(
                  color: AgriColors.brandForest,
                  border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
                ),
                child: Row(
                  children: [
                    const Icon(SymbolesAgri.apps, size: 20, color: AgriColors.accentYellow),
                    const SizedBox(width: AgriSpacing.xs),
                    const Expanded(
                      child: Text(
                        'Accès Rapide',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AgriTypography.sm),
                      ),
                    ),
                    IconButton(
                      key: const Key('acces-rapide-fermer'),
                      tooltip: 'Fermer',
                      iconSize: 20,
                      color: Colors.white.withValues(alpha: 0.80),
                      icon: const Icon(SymbolesAgri.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AgriSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var g = 0; g < AccesRapide.groupes.length; g++) ...[
                        if (g > 0)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: AgriSpacing.xs),
                            child: Divider(height: 1, thickness: 1, color: AgriColors.outlineVariant),
                          ),
                        for (final (icone, libelle, ecran) in AccesRapide.groupes[g].$2)
                          _entree(context, AccesRapide.groupes[g].$1, icone, libelle, ecran),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entree(BuildContext context, Color couleur, IconData icone, String libelle, EcranPoste ecran) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
      child: InkWell(
        key: Key('acces-rapide-${ecran.name}'),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        hoverColor: AgriColors.surfaceZebra,
        onTap: () => Navigator.of(context).pop(ecran),
        child: Padding(
          padding: const EdgeInsets.all(AgriSpacing.sm),
          child: Row(
            children: [
              Icon(icone, size: 22, color: couleur),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(
                child: Text(
                  libelle,
                  style: const TextStyle(
                    fontSize: AgriTypography.sm,
                    fontWeight: FontWeight.w600,
                    color: AgriColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
