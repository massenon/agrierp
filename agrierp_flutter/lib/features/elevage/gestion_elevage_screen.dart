import 'package:flutter/material.dart';

import '../../core/auth/permissions_poste.dart';
import '../../core/theme/agri_tokens.dart';
import '../parametres/parametres_generaux_repository.dart';

/// `prototype_html/gestion-elevage.html` → point d'entrée des fiches d'espèce.
///
/// ⚠️⚠️ **POURQUOI CET ÉCRAN EXISTE.** La barre latérale de la maquette ne liste
/// **aucune** fiche d'espèce : elle porte « Gestion Élevage », et c'est depuis
/// cet écran que les fiches s'ouvrent. Le poste avait pris le raccourci inverse
/// — cinq entrées de fiches directement dans la barre — ce qui **ajoutait** des
/// entrées que la maquette n'a pas. Reproduire le chemin de la maquette est la
/// seule façon de tenir sa structure.
///
/// ⚠️ Les cartes portent les espèces **réellement embarquées** par le poste.
/// Les autres écrans du hub web (transformation, enregistrement de sujets,
/// bandes) n'y figurent pas : le poste ne les embarque pas, et une carte qui
/// n'ouvre rien serait pire qu'absente.
///
/// ⚠️⚠️ **ET SEULEMENT LES ESPÈCES QUE LA FERME EXPLOITE.** `modules_config`
/// éteint l'héliciculture sur cette ferme, et la maquette masque en
/// conséquence tous ses blocs `data-module="helico"`. Le poste, lui, proposait
/// « Fiches Escargots » à une ferme qui n'élève pas d'escargots : la carte
/// menait à une fiche vide, sans dire pourquoi. Le filtre est lu au tirage, il
/// n'est pas recopié ici.
class GestionElevageScreen extends StatefulWidget {
  const GestionElevageScreen({
    super.key,
    required this.onOuvrir,
    required this.modules,
  });

  final void Function(EcranPoste) onOuvrir;

  /// Source unique des espèces actives — jamais une constante locale.
  final ParametresGenerauxRepository modules;

  @override
  State<GestionElevageScreen> createState() => _GestionElevageScreenState();
}

class _GestionElevageScreenState extends State<GestionElevageScreen> {
  /// ⚠️ **DEUX FICHES POUR UNE SEULE ESPÈCE** : pondeuses et reproducteurs
  /// relèvent tous deux de l'aviculture. Éteindre le module doit faire
  /// disparaître les DEUX — c'est pourquoi le code d'espèce est porté par la
  /// fiche, et non déduit de son titre.
  static const _fiches = <(IconData, String, String, EcranPoste, ModuleEspece)>[
    (
      Icons.pets,
      'Fiches Lapins',
      'Cuniculture — saisie journalière du cheptel',
      EcranPoste.ficheElevage,
      ModuleEspece.cuniculture,
    ),
    (
      Icons.egg,
      'Fiches Pondeuses',
      'Aviculture ponte — récolte et stock d\'œufs',
      EcranPoste.fichePondeuses,
      ModuleEspece.aviculture,
    ),
    (
      Icons.egg_alt,
      'Fiches Reproducteurs',
      'Aviculture hors ponte — couvoir et chair',
      EcranPoste.ficheReproducteurs,
      ModuleEspece.aviculture,
    ),
    (
      Icons.savings,
      'Fiches Porcs',
      'Porciculture — pesée en kilos',
      EcranPoste.fichePorcs,
      ModuleEspece.porciculture,
    ),
    (
      Icons.bug_report,
      'Fiches Escargots',
      'Héliciculture — pondoirs et hygrométrie',
      EcranPoste.ficheEscargots,
      ModuleEspece.helico,
    ),
  ];

  Set<String>? _especes;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final especes = await widget.modules.especesActives();
    if (!mounted) return;
    setState(() => _especes = especes);
  }

  @override
  Widget build(BuildContext context) {
    final especes = _especes;

    // ⚠️ RIEN NE S'AFFICHE TANT QUE LE FILTRE N'EST PAS LU : montrer les cinq
    // cartes puis en retirer une sous le doigt de l'utilisateur serait pire
    // qu'une seconde d'attente.
    if (especes == null) {
      return const Scaffold(
        backgroundColor: AgriColors.surfaceBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final fiches = _fiches.where((f) => especes.contains(f.$5.code)).toList();

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AgriSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.pets, color: AgriColors.brandEmerald, size: 26),
                SizedBox(width: AgriSpacing.xs),
                Expanded(
                  child: Text(
                    'Gestion Élevage',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AgriColors.brandForest,
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              'Ouvrez la fiche journalière de chaque espèce.',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.outline,
              ),
            ),
            const SizedBox(height: AgriSpacing.lg),
            if (fiches.isEmpty)
              const Text(
                "— Aucune espèce activée pour cette ferme —",
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            for (final (icone, titre, sous, ecran, _) in fiches) ...[
              _carte(icone, titre, sous, ecran),
              const SizedBox(height: AgriSpacing.md),
            ],
            // Ticket 15.46 — écran dédié des transferts (accès rapide du hub web).
            _carte(
              Icons.swap_horiz,
              'Transferts entre Bandes',
              "Portées, sevrés, regroupements ; rattachement à la bande d'origine",
              EcranPoste.transfertsBandes,
            ),
          ],
        ),
      ),
    );
  }

  /// Carte de navigation — même forme que celles du hub web : icône encadrée,
  /// titre, sous-titre, chevron.
  Widget _carte(IconData icone, String titre, String sous, EcranPoste ecran) {
    return InkWell(
      key: Key('carte-${ecran.name}'),
      onTap: () => widget.onOuvrir(ecran),
      child: Container(
        padding: const EdgeInsets.all(AgriSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AgriColors.brandEmerald.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AgriRadius.lg),
              ),
              child: Icon(icone, color: AgriColors.brandEmerald, size: 24),
            ),
            const SizedBox(width: AgriSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.brandForest,
                    ),
                  ),
                  Text(
                    sous,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AgriColors.outline,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AgriColors.outline),
          ],
        ),
      ),
    );
  }
}
