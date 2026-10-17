import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';

/// Une colonne du tableau mensuel.
class ColonneMensuelle {
  const ColonneMensuelle({
    required this.libelle,
    required this.valeur,
    this.largeur = 1,
    this.gras = false,
  });

  final String libelle;

  /// Valeur affichée pour une journée. Retourner `'—'` quand la donnée n'est
  /// pas disponible au poste — jamais `0`, qui se lirait comme une mesure.
  final String Function(int index) valeur;

  final double largeur;
  final bool gras;
}

/// Un groupe d'en-tête : « Entrées », « Sorties », « Effectif Final du Jour »…
class GroupeColonnes {
  const GroupeColonnes({required this.libelle, required this.colonnes});

  final String libelle;
  final List<ColonneMensuelle> colonnes;
}

/// Tableau mensuel des fiches d'espèce — `prototype_html`, bas de chaque fiche.
///
/// ⚠️⚠️ **CE TABLEAU MANQUAIT SUR LES CINQ FICHES.** La maquette termine chaque
/// fiche par le mois entier, avec ses **deux rangées d'en-têtes** (groupes puis
/// colonnes) et l'invite « Touchez un jour pour charger sa fiche dans le
/// formulaire ». Le poste s'arrêtait au formulaire : l'animalier ne pouvait ni
/// relire une journée passée ni la corriger.
///
/// ⚠️ **TOUCHER UNE LIGNE CHARGE LA JOURNÉE**, comme dans la maquette : c'est la
/// seule façon de revenir sur une saisie de la veille.
class TableauMensuel extends StatelessWidget {
  const TableauMensuel({
    super.key,
    required this.groupes,
    required this.colonnesSimples,
    this.colonnesAvant = const [],
    required this.nombreDeJours,
    required this.dateDe,
    required this.onOuvrirJour,
    this.jourActif,
    this.libelleDate = 'Date',
  });

  /// En-tête de la colonne de date (« Date / Jour » sur la fiche Pondeuses du web, F0.99).
  final String libelleDate;

  /// Colonnes regroupées sous un en-tête commun.
  final List<GroupeColonnes> groupes;

  /// Colonnes sans groupe placées AVANT les groupes, juste après la date.
  ///
  /// Aucune fiche ne s'en sert depuis F0.99 (« Lot / Souche » n'existe pas au web) ; gardé pour la
  /// mise en page de la maquette.
  final List<ColonneMensuelle> colonnesAvant;

  /// Colonnes sans groupe, placées après les groupes.
  final List<ColonneMensuelle> colonnesSimples;

  final int nombreDeJours;

  /// Libellé de date d'une ligne.
  final String Function(int index) dateDe;

  final void Function(int index) onOuvrirJour;

  /// Index de la journée actuellement chargée dans le formulaire.
  final int? jourActif;

  List<ColonneMensuelle> get _toutes => [
    ...colonnesAvant,
    for (final g in groupes) ...g.colonnes,
    ...colonnesSimples,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (nombreDeJours == 0)
            const Padding(
              padding: EdgeInsets.all(AgriSpacing.lg),
              child: Text(
                '— Aucune journée saisie ce mois-ci —',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            )
          else ...[
            // ⚠️ DÉFILEMENT HORIZONTAL PROPRE : jusqu'à treize colonnes sur la
            // fiche Lapins. Les laisser déborder rognerait les dernières sans
            // que rien ne le signale.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _largeurTotale(),
                child: Column(
                  children: [
                    _rangeeGroupes(),
                    _rangeeColonnes(),
                    for (var i = 0; i < nombreDeJours; i++) _ligne(i),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(AgriSpacing.sm),
              child: Text(
                'Touchez un jour pour charger sa fiche dans le formulaire',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: AgriColors.outline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _uniteLargeur = 74.0;
  static const _largeurDate = 118.0;

  double _largeurTotale() =>
      _largeurDate +
      _toutes.fold<double>(0, (t, c) => t + c.largeur * _uniteLargeur);

  /// Première rangée : les groupes de la maquette, chacun couvrant ses colonnes.
  Widget _rangeeGroupes() {
    return Container(
      decoration: const BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _largeurDate),
          for (final c in colonnesAvant)
            SizedBox(width: c.largeur * _uniteLargeur, child: const SizedBox()),
          for (final g in groupes)
            SizedBox(
              width: g.colonnes.fold<double>(
                0,
                (t, c) => t + c.largeur * _uniteLargeur,
              ),
              child: _cellule(g.libelle, entete: true, centre: true),
            ),
          for (final c in colonnesSimples)
            SizedBox(width: c.largeur * _uniteLargeur, child: const SizedBox()),
        ],
      ),
    );
  }

  /// Seconde rangée : les colonnes elles-mêmes. Les colonnes sans groupe y
  /// portent leur libellé.
  Widget _rangeeColonnes() {
    return Container(
      decoration: const BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(width: _largeurDate, child: _cellule(libelleDate, entete: true)),
          for (final c in _toutes)
            SizedBox(
              width: c.largeur * _uniteLargeur,
              child: _cellule(c.libelle, entete: true, centre: true),
            ),
        ],
      ),
    );
  }

  Widget _ligne(int index) {
    final actif = index == jourActif;

    return InkWell(
      key: Key('ligne-mois-$index'),
      onTap: () => onOuvrirJour(index),
      child: Container(
        decoration: BoxDecoration(
          color: actif
              ? AgriColors.brandEmerald.withValues(alpha: 0.10)
              : (index.isOdd ? AgriColors.surfaceZebra : Colors.white),
          border: const Border(
            bottom: BorderSide(color: AgriColors.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _largeurDate,
              child: _cellule(dateDe(index), gras: true),
            ),
            for (final c in _toutes)
              SizedBox(
                width: c.largeur * _uniteLargeur,
                child: _cellule(c.valeur(index), centre: true, gras: c.gras),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cellule(
    String texte, {
    bool entete = false,
    bool centre = false,
    bool gras = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Text(
        entete ? texte.toUpperCase() : texte,
        textAlign: centre ? TextAlign.center : TextAlign.start,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: entete ? 9 : 11,
          fontWeight: (entete || gras) ? FontWeight.bold : FontWeight.normal,
          color: entete ? AgriColors.outline : AgriColors.onSurface,
        ),
      ),
    );
  }
}
