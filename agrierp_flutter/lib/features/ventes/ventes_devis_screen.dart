import 'package:flutter/material.dart';

import '../../core/export/pdf_recu.dart';
import '../../core/theme/agri_tokens.dart';
import 'avoirs_repository.dart';
import 'caisse_repository.dart';
import 'caisse_screen.dart';
import 'historique_ventes_onglet.dart';
import 'historique_ventes_repository.dart';
import 'retours_avoirs_onglet.dart';
import 'ventes_devis_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/ventes-devis.html` → Ventes & Devis.
///
/// ⚠️⚠️ **HUB À QUATRE ONGLETS, DANS L'ORDRE DE LA MAQUETTE** : Enregistrer
/// Vente · Devis Prestations · Historique des Ventes · Retours et Avoirs. Le
/// hub charge quatre `<iframe>` (`pos-interface`, `devis`,
/// `historique-ventes`, `retours-avoirs`) ; la barre latérale ne porte qu'une
/// entrée.
///
/// 🔴→✅ **L'ENTRÉE DE MENU OUVRAIT DIRECTEMENT LA CAISSE**, sautant le hub :
/// l'utilisateur n'avait aucun chemin vers l'historique de ses propres ventes.
/// La caisse est désormais le PREMIER ONGLET de ce hub, comme dans la
/// maquette — l'écran lui-même est inchangé.
class VentesDevisScreen extends StatefulWidget {
  const VentesDevisScreen({
    super.key,
    required this.depot,
    required this.caisse,
    required this.avoirs,
    required this.historique,
    this.peutGerer = true,
    this.peutExporter = true,
    this.enregistrerPdf,
  });

  final VentesDevisRepository depot;
  final CaisseRepository caisse;

  /// Onglet « Retours et Avoirs » (ticket AV1) : les demandes de retour du poste.
  final AvoirsRepository avoirs;

  /// Onglet « Historique des Ventes » (ticket AV2) : l'historique de la ferme, l'annulation et le ticket PDF.
  final HistoriqueVentesRepository historique;

  /// `manage-ventes` du rôle de la session : enregistrer un retour, marquer un avoir traité, annuler une vente.
  final bool peutGerer;

  /// `export-ventes` : « Télécharger PDF » du détail d'une vente.
  final bool peutExporter;

  /// Écrit le PDF du ticket (`LivraisonPdf.enregistrer` par défaut, un espion en test).
  final Future<String> Function(PdfRecu pdf)? enregistrerPdf;

  @override
  State<VentesDevisScreen> createState() => _VentesDevisScreenState();
}

class _VentesDevisScreenState extends State<VentesDevisScreen> {
  /// Les quatre onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Enregistrer Vente', SymbolesAgri.point_of_sale),
    ('Devis Prestations', SymbolesAgri.description),
    ('Historique des Ventes', SymbolesAgri.receipt_long),
    ('Retours et Avoirs', SymbolesAgri.assignment_return),
  ];

  String _onglet = onglets.first.$1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _barreOnglets(),
          Expanded(
            child: switch (_onglet) {
              'Devis Prestations' => _ongletIndisponible(
                titre: 'Devis Prestations',
                icone: SymbolesAgri.description,
                sousTitre: 'Devis et proformas adressés aux clients.',
                raison:
                    'Un devis se négocie au bureau, avec la fiche du client '
                    'sous les yeux : ni le catalogue de devis ni le fichier '
                    'clients ne descendent au poste. Le proposer ici sans '
                    'client à qui l\'adresser produirait un document '
                    'incomplet.',
                cle: 'devis-non-embarque',
              ),
              // Ticket AV2 — l'historique de la ferme, identique au Blade (`historique_ventes_onglet.dart`).
              'Historique des Ventes' => HistoriqueVentesOnglet(
                depot: widget.historique,
                peutGerer: widget.peutGerer,
                peutExporter: widget.peutExporter,
                enregistrer: widget.enregistrerPdf,
                // `<a href="{{ route('ventes.devis-hub') }}">` : le hub, sur son premier onglet.
                onNouvelleVente: () => setState(() => _onglet = onglets.first.$1),
              ),
              // Ticket AV1 — les retours et avoirs : la demande part, le serveur fait les effets.
              'Retours et Avoirs' => RetoursAvoirsOnglet(depot: widget.avoirs, peutGerer: widget.peutGerer),
              _ => CaisseScreen(depot: widget.caisse),
            },
          ),
        ],
      ),
    );
  }

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (titre, icone) in onglets)
            InkWell(
              key: Key('onglet-ventes-$titre'),
              onTap: () => setState(() => _onglet = titre),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icone,
                      size: 18,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : AgriColors.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: FontWeight.bold,
                        color: _onglet == titre
                            ? AgriColors.brandEmerald
                            : AgriColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // ── Onglets non embarqués ─────────────────────────────────────────────────

  Widget _ongletIndisponible({
    required String titre,
    required String sousTitre,
    required String raison,
    required IconData icone,
    required String cle,
  }) => SingleChildScrollView(
    padding: const EdgeInsets.all(AgriSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: AgriSpacing.md),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AgriColors.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icone, size: 26, color: AgriColors.brandEmerald),
                  const SizedBox(width: AgriSpacing.xs),
                  Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AgriColors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AgriSpacing.xs),
              Text(
                sousTitre,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AgriSpacing.md),
        Container(
          key: Key(cle),
          padding: const EdgeInsets.all(AgriSpacing.md),
          decoration: BoxDecoration(
            color: AgriColors.surfaceCard,
            border: Border.all(color: AgriColors.outlineVariant),
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '— Module non embarqué au poste —',
                style: TextStyle(
                  fontSize: AgriTypography.xs,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
              const SizedBox(height: AgriSpacing.sm),
              Text(
                raison,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: AgriColors.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
