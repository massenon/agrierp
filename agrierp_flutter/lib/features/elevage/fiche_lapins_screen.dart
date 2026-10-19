import 'package:flutter/material.dart';

import '../../core/export/document_officiel.dart';
import '../../core/theme/symboles_agri.dart';
import 'categorie_ration_lapin.dart';
import 'effectif_par_categorie.dart';
import 'elements_fiche.dart';
import 'fiche_categories_vue.dart';
import 'fiche_journaliere_repository.dart';
import 'mois_fiche.dart';
import 'soins_repository.dart';

/// `fiche-lapins.blade.php` (web, `FicheLapins`) → Fiches Lapins - Cuniculture.
///
/// 🔴→✅ **TICKET U12a — LE BLADE EST LA RÉFÉRENCE DE MISE EN PAGE** (doctrine, article 5), et non plus la maquette
/// `fiche-lapins.html`. La mise en page, commune à la fiche Porcs (même Blade à l'espèce près), est dans
/// [FicheCategoriesVue] ; cet écran en porte les libellés, mot pour mot, et l'ordre des catégories du Blade.
///
/// Glossaire de la décision client du 17/10/2026 (F0.96) : Reproducteur (`repro`) / Jeune (`jeune`, 60 g/j) /
/// Sous-mères (`sevre`, Lapereau d'avant). Le sevrage du jour (Sous-mères → Jeune) est le passage de stade.
///
/// ⚠️ **« VENTES » EST EN LECTURE SEULE**, comme au web : la valeur vient de la CAISSE.
class FicheLapinsScreen extends StatelessWidget {
  const FicheLapinsScreen({
    super.key,
    required this.depot,
    required this.soins,
    this.imprimer,
    this.onOuvrirTransferts,
    this.onCommanderStock,
    this.maintenant,
  });

  final FicheJournaliereRepository depot;

  /// ⚠️ REQUIS, PAS OPTIONNEL. Sans lui la section « Traitements & Prophylaxie » serait masquée en silence — un
  /// protocole invisible se lit comme un protocole vide.
  final SoinsRepository soins;
  final Future<String?> Function(DocumentOfficiel document, DateTime maintenant)? imprimer;
  final VoidCallback? onOuvrirTransferts;
  final VoidCallback? onCommanderStock;
  final DateTime Function()? maintenant;

  /// Les libellés de `fiche-lapins.blade.php`.
  static final config = ConfigFicheCategories(
    espece: EspeceFiche.lapins,
    especeChaine: EffectifParCategorie.lapins,
    icone: SymbolesAgri.cruelty_free,
    titre: 'Fiches Lapins - Cuniculture',
    sousTitre: 'Fiche de suivi mensuel du cheptel — transcription fidèle du registre de la ferme.',
    cartes: const [
      ('Effectif Total Vivant', SymbolesAgri.pets, CarteFiche.emerald),
      ('Géniteurs (M/F)', SymbolesAgri.favorite, CarteFiche.blue),
      ('Naissances du Mois', SymbolesAgri.child_care, CarteFiche.maize),
      ('Taux de Mortalité', SymbolesAgri.trending_down, CarteFiche.red),
    ],
    aucuneBande: 'Aucune bande active en cuniculture pour le moment.',
    toastAucuneBande: "Aucune bande active en cuniculture. Créez d'abord une bande.",
    titreSaisie: 'Saisie Journalière du Cheptel',
    libelleNes: 'Nés (Mise bas)',
    categoriesMorts: const [('repro', 'Reproducteur'), ('jeune', 'Jeune'), ('sevre', 'Sous-mères')],
    categoriesDons: const [('repro', 'Reproducteur'), ('jeune', 'Jeune'), ('sevre', 'Sous-mères')],
    libellePassage: 'Sevrage du jour (Sous-mères → Jeune)',
    categoriesDepart: const [('repro', 'Reproducteur'), ('jeune', 'Jeune'), ('sevre', 'Sous-mères')],
    texteAncien: (c) => 'Reproducteur ${c.repro}, Jeune ${c.jeune}, Sous-mères ${c.sevre}',
    libellesEffectifs: const ['Effectif Mâles', 'Effectif Femelles', 'Jeunes', 'S/Mères'],
    titreRationnement: 'Rationnement & Provende Servie par Catégorie (en Grammes g/j)',
    enteteRation: 'Catégorie',
    libellesRation: const {
      CategorieRationLapin.reproducteur: 'Reproducteur',
      CategorieRationLapin.chair: 'Jeune',
      CategorieRationLapin.sousMeres: 'Sous-mères',
    },
    rationAffichee: (l) => '${l.ration} g/j',
    ligneRationMiseEnAvant: CategorieRationLapin.chair,
    filiere: 'cuniculture',
    peseeEnKg: false,
    titreTraitements: 'Traitements & Prophylaxie',
    libelleObservations: 'Observations / Notes Additionnelles',
    indiceObservations: "ex : RAS, légère perte d'appétit cage C3...",
    ventilation: '(Reproducteur / Jeune / Sous-mères)',
    colonnesEffectif: const ['M', 'F', 'Jeunes', 'S/Mères'],
    libellePoids: 'Poids Général (g)',
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
