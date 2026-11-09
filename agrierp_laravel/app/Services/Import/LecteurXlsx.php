<?php

namespace App\Services\Import;

use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

/**
 * Ticket IMPORT-1 — LECTURE D'UN CLASSEUR xlsx D'IMPORTATION (`phpoffice/phpspreadsheet`, embarqué par `maatwebsite/excel`).
 *
 * Contrôles du FICHIER (refus entier, avant toute ligne) : taille, signature zip, lisibilité, feuille de métadonnées
 * « Modele » (modèle ET version reconnus), feuille « Données », en-têtes EXACTS (une colonne manquante ou renommée est nommée),
 * nombre de lignes. Les lignes entièrement vides sont ignorées (un classeur de milliers de lignes vides ne compte pas).
 *
 * Aucune formule n'est évaluée : une cellule de formule est lue comme son texte (jamais de calcul, jamais d'accès externe).
 */
class LecteurXlsx
{
    public const TAILLE_MAX_OCTETS = 5 * 1024 * 1024;

    public const LIGNES_MAX = 5000;

    /** Lignes physiques parcourues au plus (un classeur « formaté » jusqu'en bas ne doit pas peser sur le serveur). */
    public const LIGNES_PARCOURUES_MAX = 20000;

    public const FEUILLE_DONNEES = 'Données';

    public const FEUILLE_INSTRUCTIONS = 'Instructions';

    public const FEUILLE_LISTES = 'Listes';

    public const FEUILLE_META = 'Modele';

    /**
     * @return array{lignes: array<int, array<string, string>>, lues: int}  `lignes` : numéro de ligne du fichier → clé de colonne → texte
     *
     * @throws ImportRefuse
     */
    public function lire(string $chemin, ModuleImport $module): array
    {
        $taille = @filesize($chemin);
        if ($taille === false || ! is_readable($chemin)) {
            throw new ImportRefuse("Le fichier est illisible : choisissez-le de nouveau.");
        }
        if ($taille > self::TAILLE_MAX_OCTETS) {
            throw new ImportRefuse('Le fichier dépasse '.(self::TAILLE_MAX_OCTETS / 1024 / 1024).' Mo ('.number_format($taille / 1024 / 1024, 1, ',', ' ').' Mo) : réduisez le nombre de lignes.');
        }
        if ($taille === 0 || @file_get_contents($chemin, false, null, 0, 2) !== 'PK') {
            throw new ImportRefuse("Ce fichier n'est pas un classeur Excel (.xlsx) lisible. Utilisez le modèle « {$module->libelle()} » téléchargé à l'étape 2.");
        }

        try {
            $lecteur = IOFactory::createReader('Xlsx');
            $lecteur->setReadEmptyCells(false);
            $classeur = $lecteur->load($chemin);
        } catch (\Throwable) {
            throw new ImportRefuse("Ce fichier n'est pas un classeur Excel (.xlsx) lisible. Utilisez le modèle « {$module->libelle()} » téléchargé à l'étape 2.");
        }

        try {
            $this->verifierModele($classeur, $module);
            $feuille = $classeur->getSheetByName(self::FEUILLE_DONNEES);
            if ($feuille === null) {
                throw new ImportRefuse('La feuille « '.self::FEUILLE_DONNEES."» est introuvable : n'en changez pas le nom, téléchargez le modèle « {$module->libelle()} » à jour.");
            }

            $positions = $this->positionsDesColonnes($feuille, $module);

            return $this->lireLignes($feuille, $module, $positions);
        } finally {
            $classeur->disconnectWorksheets();
        }
    }

    private function verifierModele(Spreadsheet $classeur, ModuleImport $module): void
    {
        $meta = $classeur->getSheetByName(self::FEUILLE_META);
        $modele = $meta ? LectureValeurs::texte($meta->getCell('B1')->getValue()) : '';
        $version = $meta ? LectureValeurs::texte($meta->getCell('B2')->getValue()) : '';

        if ($modele === '') {
            throw new ImportRefuse("Ce fichier n'est pas un modèle LogiAgriERP : téléchargez le modèle « {$module->libelle()} » (version {$module->version()}) à l'étape 2.");
        }

        if ($modele !== $module->cle()) {
            $autre = ImportMasseService::module($modele);
            $nom = $autre ? "« {$autre->libelle()} »" : "« {$modele} »";

            throw new ImportRefuse("Ce fichier n'est pas le modèle « {$module->libelle()} » (version {$module->version()}) : c'est le modèle {$nom}. Téléchargez le modèle à jour.");
        }

        if ((string) $module->version() !== $version) {
            throw new ImportRefuse("Ce fichier est le modèle « {$module->libelle()} » en version {$version} ; la version {$module->version()} est attendue : téléchargez le modèle à jour.");
        }
    }

    /**
     * @return array<string, int> clé de colonne → index (base 1) de la colonne dans le fichier
     */
    private function positionsDesColonnes(Worksheet $feuille, ModuleImport $module): array
    {
        $presentes = [];
        $dernier = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::columnIndexFromString($feuille->getHighestDataColumn(1));
        for ($c = 1; $c <= $dernier; $c++) {
            $entete = LectureValeurs::texte($feuille->getCell([$c, 1])->getValue());
            if ($entete !== '') {
                $presentes[$entete] ??= $c;
            }
        }

        $positions = [];
        $manquantes = [];
        foreach ($module->colonnes() as $colonne) {
            if (isset($presentes[$colonne->entete()])) {
                $positions[$colonne->cle] = $presentes[$colonne->entete()];
            } else {
                $manquantes[] = '« '.$colonne->entete().' »';
            }
        }

        if ($manquantes !== []) {
            throw new ImportRefuse(
                (count($manquantes) > 1 ? 'Colonnes manquantes ou renommées' : 'Colonne manquante ou renommée')
                .' dans la feuille « '.self::FEUILLE_DONNEES.' » : '.implode(', ', $manquantes)
                .'. Ne renommez pas les en-têtes : téléchargez le modèle « '.$module->libelle().' » à jour.'
            );
        }

        return $positions;
    }

    /**
     * @param  array<string, int>  $positions
     * @return array{lignes: array<int, array<string, string>>, lues: int}
     */
    private function lireLignes(Worksheet $feuille, ModuleImport $module, array $positions): array
    {
        $derniere = $feuille->getHighestDataRow();
        if ($derniere > self::LIGNES_PARCOURUES_MAX) {
            throw new ImportRefuse('Le classeur compte plus de '.number_format(self::LIGNES_PARCOURUES_MAX, 0, ',', ' ').' lignes : supprimez les lignes vides ou découpez le fichier.');
        }

        $lignes = [];
        $dernierIndex = max($positions);
        $dernierCol = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex($dernierIndex);

        // Par tranches, sans créer de cellule vide (`rangeToArray`, sans calcul de formule ni mise en forme).
        for ($debut = 2; $debut <= $derniere; $debut += 500) {
            $fin = min($derniere, $debut + 499);
            $tranche = $feuille->rangeToArray('A'.$debut.':'.$dernierCol.$fin, null, false, false, false);

            foreach ($tranche as $i => $cellules) {
                $ligne = [];
                $vide = true;
                foreach ($positions as $cle => $c) {
                    // Aucune formule n'est évaluée : le texte de la formule est ce qui est lu.
                    $texte = LectureValeurs::texte($cellules[$c - 1] ?? null);
                    if ($texte !== '') {
                        $vide = false;
                    }
                    $ligne[$cle] = $texte;
                }
                if ($vide) {
                    continue;
                }

                $lignes[$debut + $i] = $ligne;
                if (count($lignes) > self::LIGNES_MAX) {
                    throw new ImportRefuse('Le fichier dépasse '.number_format(self::LIGNES_MAX, 0, ',', ' ').' lignes : découpez-le en plusieurs fichiers.');
                }
            }
        }

        if ($lignes === []) {
            throw new ImportRefuse('Le fichier ne contient aucune ligne à importer : remplissez la feuille « '.self::FEUILLE_DONNEES.' » sous les en-têtes.');
        }

        return ['lignes' => $lignes, 'lues' => count($lignes)];
    }
}
