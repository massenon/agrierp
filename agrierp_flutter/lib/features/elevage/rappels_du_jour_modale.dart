import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../../core/widgets/modale_agri.dart';
import 'rappels_du_jour_repository.dart';

/// Ticket POP2 — la fenêtre « Rappels du jour », IDENTIQUE au Blade `livewire/shared/rappels-du-jour.blade.php`
/// (le web est le maître ; ses libellés sont lus par `rappels_du_jour_blade_test.dart`).
///
/// [surMasquer] : « Ne plus afficher aujourd'hui » (l'appelant range la préférence du jour) ; [surOuvrirSoins] :
/// « Ouvrir Soins et vaccins » (l'appelant ouvre l'écran). Les deux ferment la fenêtre ; « Plus tard » et le ✕ aussi,
/// sans rien masquer.
Future<void> montrerRappelsDuJour(
  BuildContext context, {
  required RappelsDuJour donnees,
  required VoidCallback surMasquer,
  VoidCallback? surOuvrirSoins,
}) {
  return showDialog<void>(
    context: context,
    builder: (contexte) => ModaleAgri(
      surtitre: "Soins, vaccins et délais d'attente",
      titre: 'Rappels du jour',
      largeur: LargeurModale.xl,
      contenu: _Contenu(donnees: donnees),
      actions: [
        TextButton(
            key: const Key('rappels-ouvrir-soins'),
            onPressed: () {
              Navigator.of(contexte).pop();
              surOuvrirSoins?.call();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ouvrir Soins et vaccins'),
                SizedBox(width: AgriSpacing.xs),
                Icon(SymbolesAgri.arrow_forward, size: 16),
              ],
            ),
          ),
        TextButton(
          key: const Key('rappels-ne-plus-afficher'),
          onPressed: () {
            Navigator.of(contexte).pop();
            surMasquer();
          },
          child: const Text("Ne plus afficher aujourd'hui"),
        ),
        BoutonModalePrimaire(
          key: const Key('rappels-plus-tard'),
          libelle: 'Plus tard',
          onPressed: () => Navigator.of(contexte).pop(),
        ),
      ],
    ),
  );
}

class _Contenu extends StatelessWidget {
  const _Contenu({required this.donnees});

  final RappelsDuJour donnees;

  static const _entetes = ['Bande', 'Rappel', 'Produit', 'Date prévue', 'Échéance'];

  String _titre(UrgenceRappel u) => switch (u) {
    UrgenceRappel.retard => 'En retard',
    UrgenceRappel.aujourdhui => "Aujourd'hui",
    UrgenceRappel.avenir => 'À venir (sous ${donnees.joursRappel} jour${donnees.joursRappel > 1 ? 's' : ''})',
  };

  (Color, Color) _couleurs(UrgenceRappel u) => switch (u) {
    UrgenceRappel.retard => (AgriColors.errorBg, AgriColors.errorDeep),
    UrgenceRappel.aujourdhui => (AgriColors.accentYellow.withValues(alpha: 0.3), AgriColors.brandForest),
    UrgenceRappel.avenir => (AgriColors.brandEmerald.withValues(alpha: 0.1), AgriColors.brandEmerald),
  };

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final urgence in UrgenceRappel.values)
          if (donnees.de(urgence).isNotEmpty) ...[
            Container(
              key: Key('rappels-groupe-${urgence.name}'),
              padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: AgriSpacing.xs),
              decoration: BoxDecoration(color: _couleurs(urgence).$1, borderRadius: BorderRadius.circular(AgriRadius.base)),
              child: Text(
                '${_titre(urgence)} (${donnees.de(urgence).length})',
                style: TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: _couleurs(urgence).$2),
              ),
            ),
            const SizedBox(height: AgriSpacing.xs),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(3),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(1.5),
                4: FlexColumnWidth(2),
              },
              border: const TableBorder(horizontalInside: BorderSide(color: AgriColors.outlineVariant)),
              children: [
                TableRow(
                  children: [
                    for (final e in _entetes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AgriSpacing.xs),
                        child: Text(e, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.outline)),
                      ),
                  ],
                ),
                for (final l in donnees.de(urgence))
                  TableRow(
                    children: [
                      for (final (i, cellule) in [
                        '${l.bande} (${l.espece})',
                        '${l.libelle} · ${l.typeLibelle}',
                        l.produit,
                        l.dateTexte,
                        l.echeance,
                      ].indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AgriSpacing.xs, horizontal: 2),
                          child: Text(cellule, style: i == 0 ? style.copyWith(fontWeight: AgriTypography.gras) : style),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AgriSpacing.md),
          ],
      ],
    );
  }
}
