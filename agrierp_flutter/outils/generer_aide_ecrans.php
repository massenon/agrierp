<?php

/**
 * Ticket AIDE-1 — produit `lib/core/aide/aide_ecrans.dart` depuis la SOURCE UNIQUE des textes d'aide du web,
 * `agrierp_laravel/lang/fr/aide_ecrans.php`.
 *
 *     php outils/generer_aide_ecrans.php            # depuis agrierp_flutter/
 *     AGRIERP_LARAVEL=/chemin/agrierp_laravel php outils/generer_aide_ecrans.php
 *
 * À relancer après TOUTE modification de `lang/fr/aide_ecrans.php` : `test/aide_ecrans_parite_test.dart` exécute ce fichier
 * PHP et compare mot pour mot — un texte changé d'un seul côté fait rougir ce test.
 *
 * C'est ICI, et nulle part ailleurs, que la correspondance « écran du poste ↔ chemin de la route web » est écrite
 * (`CHEMINS`). Les 32 premières lignes sont celles de `test/chassis_web_test.dart` (le test de parité le vérifie).
 */

$racine = dirname(__DIR__);
$laravel = getenv('AGRIERP_LARAVEL') ?: dirname($racine).'/agrierp_laravel';
$source = $laravel.'/lang/fr/aide_ecrans.php';
if (! is_file($source)) {
    fwrite(STDERR, "Source introuvable : $source\n");
    exit(1);
}
$aide = require $source;

/** EcranPoste => chemin de la route web dont le poste reprend le texte. */
const CHEMINS = [
    'tableauDeBord' => '/dashboard',
    'gestionElevage' => '/gestion-elevage',
    'dashboardElevage' => '/elevage-dashboard',
    'suiviReproduction' => '/suivi-reproduction',
    'soinsEtVaccins' => '/soins-vaccins-hub',
    'transformation' => '/transformation',
    'parametresElevage' => '/parametres-elevage',
    'ficheElevage' => '/fiche-lapins',
    'fichePondeuses' => '/fiche-volailles-pondeuses',
    'ficheReproducteurs' => '/fiche-volailles-reproducteurs',
    'fichePorcs' => '/fiche-porcs',
    'ficheEscargots' => '/fiche-escargots',
    'transfertsBandes' => '/transferts-bandes',
    'gestionBandes' => '/gestion-bandes',
    'enregistrerSujets' => '/enregistrer-sujets',
    'ventesEtDevis' => '/ventes-devis',
    'clientsEtCreances' => '/creances-clients',
    'achatsEtCommandes' => '/achats-commandes',
    'fournisseurs' => '/fournisseurs',
    'saisieDepenses' => '/saisie-depenses',
    'gestionStocks' => '/gestion-stocks',
    'catalogueProduits' => '/catalogue-produits',
    'facturation' => '/facturation',
    'personnelEtStages' => '/personnel-stages',
    'administrationEtDocument' => '/administration',
    'comptabilite' => '/comptabilite-hub',
    'parametresGeneraux' => '/parametres-hub',
    'rapportsEtExports' => '/rapports-exports',
    'monProfil' => '/mon-profil',
    'notifications' => '/notifications',
    'aideEtAPropos' => '/aide-a-propos',
    'contactEditeur' => '/contact-editeur',
    // Écrans du poste hors du châssis web ci-dessus.
    'ficheSujet' => '/sujets/{animal}',
    'registreReproducteurs' => '/registre-reproducteurs',
    // La caisse est l'onglet « Enregistrer Vente » du hub Ventes & Devis : elle lit l'aide du hub.
    'caisse' => '/ventes-devis',
];

/** EcranPoste sans route web : leur aide est dans `poste_seul`. */
const POSTE_SEUL = ['synchronisation', 'parametres'];

function d(string $s): string
{
    return "'".str_replace(['\\', "'", '$'], ['\\\\', "\\'", '\\$'], $s)."'";
}

function puces(array $puces): string
{
    return "[\n".implode('', array_map(fn ($p) => '        '.d($p).",\n", $puces)).'      ]';
}

function ecran(array $a): string
{
    return 'AideEcran(titre: '.d($a['titre']).', puces: '.puces($a['puces']).')';
}

$sortie = "// GÉNÉRÉ par `php outils/generer_aide_ecrans.php` depuis agrierp_laravel/lang/fr/aide_ecrans.php — NE PAS ÉDITER À LA MAIN.\n";
$sortie .= <<<'DART'
//
// Ticket AIDE-1 — TEXTES D'AIDE DU POSTE : les mêmes, mot pour mot, que ceux du web (source unique côté web). Le panneau du
// bouton flottant d'aide (`core/widgets/aide_flottante.dart`) les lit ici. `test/aide_ecrans_parite_test.dart` exécute le
// vrai PHP du web et compare : un texte modifié d'un seul côté fait rougir ce test.
import '../auth/permissions_poste.dart';

/// L'aide courte d'un écran : son titre et 3 à 5 puces.
class AideEcran {
  const AideEcran({required this.titre, required this.puces});

  final String titre;
  final List<String> puces;
}

/// Une étape de la visite guidée.
class EtapeVisite {
  const EtapeVisite({required this.titre, required this.texte});

  final String titre;
  final String texte;
}

class AideEcrans {
  AideEcrans._();


DART;

$sortie .= "  /// Écran du poste → chemin de la route web dont il reprend l'aide (`lang/fr/aide_ecrans.php`, clé `ecrans`).\n";
$sortie .= "  static const cheminsWeb = <EcranPoste, String>{\n";
foreach (CHEMINS as $ecran => $chemin) {
    $sortie .= "    EcranPoste.$ecran: ".d($chemin).",\n";
    if (! isset($aide['ecrans'][$chemin])) {
        fwrite(STDERR, "Chemin sans aide : $chemin\n");
        exit(1);
    }
}
$sortie .= "  };\n\n";

$sortie .= "  /// Aide de chaque écran du poste.\n  static const parEcran = <EcranPoste, AideEcran>{\n";
foreach (CHEMINS as $ecran => $chemin) {
    $sortie .= "    EcranPoste.$ecran: ".ecran($aide['ecrans'][$chemin]).",\n";
}
foreach (POSTE_SEUL as $ecran) {
    $sortie .= "    EcranPoste.$ecran: ".ecran($aide['poste_seul'][$ecran]).",\n";
}
$sortie .= "  };\n\n";

$sortie .= "  /// Écrans du poste sans route web (clé `poste_seul`).\n  static const posteSeul = <EcranPoste>{".implode(', ', array_map(fn ($e) => "EcranPoste.$e", POSTE_SEUL))."};\n\n";

$sortie .= "  /// Aide d'un écran absent de [parEcran] : jamais de panneau vide.\n  static const parDefaut = ".ecran($aide['defaut']).";\n\n";
$sortie .= "  static AideEcran pour(EcranPoste ecran) => parEcran[ecran] ?? parDefaut;\n\n";

$sortie .= "  /// Libellés du panneau (clé `panneau`).\n  static const panneau = <String, String>{\n";
foreach ($aide['panneau'] as $k => $v) {
    $sortie .= '    '.d($k).': '.d($v).",\n";
}
$sortie .= "  };\n\n";

$libelles = array_diff_key($aide['visite'], ['etapes' => 1]);
$sortie .= "  /// Libellés de la visite guidée (clé `visite`, hors étapes).\n  static const libellesVisite = <String, String>{\n";
foreach ($libelles as $k => $v) {
    $sortie .= '    '.d($k).': '.d($v).",\n";
}
$sortie .= "  };\n\n";

$sortie .= "  /// Les 4 étapes de la visite guidée.\n  static const etapesVisite = <EtapeVisite>[\n";
foreach ($aide['visite']['etapes'] as $e) {
    $sortie .= '    EtapeVisite(titre: '.d($e['titre']).', texte: '.d($e['texte'])."),\n";
}
$sortie .= "  ];\n}\n";

$cible = $racine.'/lib/core/aide/aide_ecrans.dart';
file_put_contents($cible, $sortie);
echo "Écrit : $cible\n";
