import 'package:flutter/material.dart';

import '../../core/export/document_officiel.dart';
import '../../core/theme/symboles_agri.dart';
import '../stocks/pmp_service.dart';
import 'categorie_ration_porc.dart';
import 'effectif_par_categorie.dart';
import 'elements_fiche.dart';
import 'fiche_categories_vue.dart';
import 'fiche_journaliere_repository.dart';
import 'mois_fiche.dart';
import 'soins_repository.dart';

/// `fiche-porcs.blade.php` (web, `FichePorcs`) → Fiches Porcs - Porciculture.
///
/// 🔴→✅ **TICKET U12a — LE BLADE EST LA RÉFÉRENCE DE MISE EN PAGE** (doctrine, article 5), et non plus la maquette
/// `fiche-porcs.html`. La mise en page, commune à la fiche Lapins (ticket 15.42 = miroir de 15.41), est dans
/// [FicheCategoriesVue] ; cet écran en porte les libellés, mot pour mot, et l'ordre des catégories du Blade.
///
/// Emplacements (14.12) : `repro` = Reproducteur ; `sevre` = Porcelet ; `jeune` = Porc Marchand. D11 : l'achat
/// gonfle le Reproducteur.
///
/// ⚠️⚠️ **SEULE FICHE À PESER EN KILOS.** La colonne de stockage reste `weight_sample_avg_g` — le poids MOYEN par
/// sujet, en grammes : la conversion se fait dans les DEUX sens (ticket 14.60). « Poids Moyen Constaté » : « — »
/// sans pesée (🔴→✅ U12a : le web affichait « 0 Kg »).
class FichePorcsScreen extends StatelessWidget {
  const FichePorcsScreen({
    super.key,
    required this.depot,
    required this.soins,
    this.imprimer,
    this.onOuvrirTransferts,
    this.onCommanderStock,
    this.maintenant,
  });

  final FicheJournaliereRepository depot;
  final SoinsRepository soins;
  final Future<String?> Function(DocumentOfficiel document, DateTime maintenant)? imprimer;
  final VoidCallback? onOuvrirTransferts;
  final VoidCallback? onCommanderStock;
  final DateTime Function()? maintenant;

  /// Les libellés de `fiche-porcs.blade.php`.
  static final config = ConfigFicheCategories(
    espece: EspeceFiche.porcs,
    especeChaine: EffectifParCategorie.porcs,
    icone: SymbolesAgri.pets,
    titre: 'Fiches Porcs - Porciculture',
    sousTitre: 'Fiche de suivi mensuel du cheptel porcin — engraissement, maternité et reproduction.',
    cartes: const [
      ('Effectif Porcins Vivants', SymbolesAgri.pets, CarteFiche.emerald),
      ('Truies Gestantes / Verrats', SymbolesAgri.favorite, CarteFiche.blue),
      ('Porcelets sous Mère', SymbolesAgri.child_care, CarteFiche.maize),
      ('Taux de Mortalité', SymbolesAgri.trending_down, CarteFiche.red),
    ],
    aucuneBande: 'Aucune bande active en porciculture pour le moment.',
    toastAucuneBande: "Aucune bande active en porciculture. Créez d'abord une bande.",
    titreSaisie: 'Saisie Journalière du Cheptel Porcin',
    libelleNes: 'Nés (Mise bas porcelets)',
    categoriesMorts: const [
      ('repro', 'Reproducteur (Truie/Verrat)'),
      ('jeune', 'Porc marchand / Engraiss.'),
      ('sevre', 'Porcelet'),
    ],
    categoriesDons: const [('repro', 'Reproducteur'), ('jeune', 'Porc marchand'), ('sevre', 'Porcelet')],
    libellePassage: 'Passage de stade (Porcelet → Porc Marchand)',
    suffixePassage: '(hors maquette)',
    categoriesDepart: const [('repro', 'Reproducteur'), ('sevre', 'Porcelet'), ('jeune', 'Porc Marchand')],
    texteAncien: (c) => 'Reproducteur ${c.repro}, Porcelet ${c.sevre}, Porc Marchand ${c.jeune}',
    libellesEffectifs: const ['Verrats', 'Truies Gestantes', 'Porcelets', 'Engraissement'],
    titreRationnement: 'Rationnement & Provende Servie par Stade Porcin (en Grammes g/j)',
    enteteRation: 'Stade Physiologique',
    // D15 (décision client à confirmer) : libellé de la maquette « Porc Marchand » ; le barème n'est pas renommé.
    libellesRation: const {
      CategorieRationPorc.porcelet: 'Porcelet',
      CategorieRationPorc.marchand: 'Porc Marchand',
      CategorieRationPorc.reproducteur: 'Reproducteur',
    },
    // `number_format(ration, 0, ',', ' ') g/j (number_format(ration / 1000, 1) Kg)` pour le Reproducteur.
    rationAffichee: (l) => l.cle == CategorieRationPorc.reproducteur
        ? '${PmpService.francs(l.ration.toDouble())} g/j '
              '(${PmpService.nombre(l.ration / 1000, 1, virgule: '.', milliers: ',')} Kg)'
        : '${l.ration} g/j',
    ligneRationMiseEnAvant: CategorieRationPorc.reproducteur,
    filiere: 'porcine',
    peseeEnKg: true,
    titreTraitements: 'Suivi Clinique & Prophylaxie',
    libelleObservations: 'Observations',
    indiceObservations: 'ex : RAS',
    ventilation: '(Reproducteur / Porc Marchand / Porcelet)',
    colonnesEffectif: const ['Truies Gest.', 'Verrats', 'Porcelets', 'Engraiss.'],
    libellePoids: 'Poids Général (Kg)',
  );

  @override
  Widget build(BuildContext context) => FicheCategoriesVue(
    config: config,
    depot: depot,
    soins: soins,
    imprimer: imprimer,
    onOuvrirTransferts: onOuvrirTransferts,
    onCommanderStock: onCommanderStock,
    maintenant: maintenant,
  );
}
