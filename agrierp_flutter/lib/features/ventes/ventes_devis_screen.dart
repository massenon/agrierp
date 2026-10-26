import 'package:flutter/material.dart';

import '../../core/export/pdf_recu.dart';
import '../../core/theme/agri_tokens.dart';
import '../rapports/rapports_exports_screen.dart' show Editeur;
import 'avoirs_repository.dart';
import 'caisse_repository.dart';
import 'caisse_screen.dart';
import 'devis_onglet.dart';
import 'devis_repository.dart';
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
    required this.devis,
    this.imprimer,
    this.peutGerer = true,
    this.peutExporter = true,
    this.peutConvertir = false,
    this.peutVoirFacturation = false,
    this.surVoirFacturation,
    this.enregistrerPdf,
  });

  final VentesDevisRepository depot;
  final CaisseRepository caisse;

  /// Onglet « Retours et Avoirs » (ticket AV1) : les demandes de retour du poste.
  final AvoirsRepository avoirs;

  /// Onglet « Historique des Ventes » (ticket AV2) : l'historique de la ferme, l'annulation et le ticket PDF.
  final HistoriqueVentesRepository historique;

  /// Ticket DEV — l'onglet « Devis Prestations » (table `quotes`, saisie ET tirée) ; mêmes droits `manage-ventes` /
  /// `export-ventes` que les autres onglets.
  final DevisRepository devis;

  /// Éditeur PDF de « Exporter » (onglet Devis), injecté — `EditeursRapports.imprimer` en production.
  final Editeur? imprimer;

  /// `manage-ventes` du rôle de la session : enregistrer un retour, marquer un avoir traité, annuler une vente.
  final bool peutGerer;

  /// `export-ventes` : « Télécharger PDF » du détail d'une vente.
  final bool peutExporter;

  /// Ticket DEV3 — `manage-facturation` (en plus de `manage-ventes`) : « Convertir en Facture » de l'onglet Devis.
  final bool peutConvertir;

  /// Ticket DEV3 — `view-facturation` : « Voir la facture » d'un devis facturé, qui ouvre [surVoirFacturation].
  final bool peutVoirFacturation;

  /// Ticket DEV3 — ouvre l'écran « Facturation & MeCeF » (`route('facturation.index')` au web).
  final VoidCallback? surVoirFacturation;

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
              // Ticket DEV — « Devis & Proforma » : saisie, cycle de vie et archivage (`devis_onglet.dart`).
              'Devis Prestations' => DevisOnglet(
                depot: widget.devis,
                peutGerer: widget.peutGerer,
                peutExporter: widget.peutExporter,
                peutConvertir: widget.peutConvertir,
                peutVoirFacturation: widget.peutVoirFacturation,
                surVoirFacturation: widget.surVoirFacturation,
                imprimer: widget.imprimer,
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
}
