<?php

namespace App\Services\Import;

use PhpOffice\PhpSpreadsheet\Cell\Coordinate;
use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\Cell\DataValidation;
use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use PhpOffice\PhpSpreadsheet\Style\NumberFormat;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

/**
 * Ticket IMPORT-1 — GÉNÈRE LE MODÈLE .xlsx À TÉLÉCHARGER, un par module, versionné.
 *
 * Quatre feuilles :
 *  - « Instructions » : nom et version du modèle, rôle de chaque colonne, formats, LIGNES D'EXEMPLE (ici et pas dans
 *    « Données » : aucune ne s'importerait par erreur), limites, avertissement « ne renommez pas les en-têtes » ;
 *  - « Données » : les en-têtes EXACTS (obligatoires marqués « * »), VIDE, avec listes déroulantes de validation
 *    (catégories, unités, filières, modes de prix…) et colonnes « téléphone » au format texte (le zéro initial ne se perd pas) ;
 *  - « Listes » : les valeurs des listes déroulantes, lues en base au moment du téléchargement ;
 *  - « Modele » (masquée) : modèle, version et empreinte SHA-256 des en-têtes, lus par `LecteurXlsx`.
 *
 * Formats : montants en FCFA ENTIERS ; nombres avec virgule ou point ; dates AAAA-MM-JJ (les trois modèles de cette
 * livraison n'en portent pas : le stock initial est daté du jour de l'importation ; les modèles à venir suivront cette règle).
 *
 * Le poste ne fabrique PAS ce fichier (voir `agrierp_flutter/CLAUDE.md`, IMPORT-1) : ses en-têtes sont une copie
 * prouvée par `importation_parite_php_test.dart`.
 */
class ModeleXlsxService
{
    /** Lignes de « Données » préparées (listes, formats) : la limite de l'importation. */
    private const LIGNES_PREPAREES = LecteurXlsx::LIGNES_MAX + 1;

    public function nomDeFichier(ModuleImport $module): string
    {
        return 'Modele_'.ucfirst($module->cle()).'_v'.$module->version().'.xlsx';
    }

    /** Écrit le modèle dans un fichier temporaire et rend son chemin (à supprimer par l'appelant). */
    public function fichier(ModuleImport $module): string
    {
        $chemin = tempnam(sys_get_temp_dir(), 'modele_').'.xlsx';
        $ecrivain = IOFactory::createWriter($this->construire($module), 'Xlsx');
        $ecrivain->save($chemin);

        return $chemin;
    }

    public function construire(ModuleImport $module): Spreadsheet
    {
        $classeur = new Spreadsheet();
        $classeur->getProperties()->setCreator('LogiAgriERP')->setTitle('Modèle d\'importation « '.$module->libelle().' », version '.$module->version());

        $instructions = $classeur->getActiveSheet();
        $instructions->setTitle(LecteurXlsx::FEUILLE_INSTRUCTIONS);
        $donnees = $classeur->createSheet();
        $donnees->setTitle(LecteurXlsx::FEUILLE_DONNEES);
        $listes = $classeur->createSheet();
        $listes->setTitle(LecteurXlsx::FEUILLE_LISTES);
        $meta = $classeur->createSheet();
        $meta->setTitle(LecteurXlsx::FEUILLE_META);

        $positions = $this->ecrireListes($listes, $module);
        $this->ecrireDonnees($donnees, $module, $positions);
        $this->ecrireInstructions($instructions, $module);
        $this->ecrireMeta($meta, $module);

        // On ouvre sur « Instructions » ; la feuille technique reste masquée.
        $classeur->setActiveSheetIndex(0);
        $meta->setSheetState(Worksheet::SHEETSTATE_HIDDEN);

        return $classeur;
    }

    /**
     * @return array<string, array{colonne: string, nombre: int}> nom de liste → colonne de « Listes » et nombre de valeurs
     */
    private function ecrireListes(Worksheet $feuille, ModuleImport $module): array
    {
        $positions = [];
        $c = 1;
        foreach ($module->listes() as $nom => $valeurs) {
            $lettre = Coordinate::stringFromColumnIndex($c);
            $feuille->setCellValueExplicit($lettre.'1', $nom, DataType::TYPE_STRING);
            $feuille->getStyle($lettre.'1')->getFont()->setBold(true);
            foreach (array_values($valeurs) as $i => $valeur) {
                $feuille->setCellValueExplicit($lettre.($i + 2), (string) $valeur, DataType::TYPE_STRING);
            }
            $feuille->getColumnDimension($lettre)->setWidth(28);
            $positions[$nom] = ['colonne' => $lettre, 'nombre' => count($valeurs)];
            $c++;
        }

        return $positions;
    }

    /** @param array<string, array{colonne: string, nombre: int}> $listes */
    private function ecrireDonnees(Worksheet $feuille, ModuleImport $module, array $listes): void
    {
        foreach ($module->colonnes() as $i => $colonne) {
            $lettre = Coordinate::stringFromColumnIndex($i + 1);
            $cellule = $lettre.'1';
            $feuille->setCellValueExplicit($cellule, $colonne->entete(), DataType::TYPE_STRING);
            $feuille->getStyle($cellule)->applyFromArray([
                'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF']],
                'fill' => ['fillType' => Fill::FILL_SOLID, 'startColor' => ['rgb' => $colonne->obligatoire ? '14532D' : '4B7A5A']],
                'alignment' => ['vertical' => Alignment::VERTICAL_CENTER, 'wrapText' => true],
            ]);
            $feuille->getColumnDimension($lettre)->setWidth(max(16, mb_strlen($colonne->entete()) + 6));

            $plage = $lettre.'2:'.$lettre.self::LIGNES_PREPAREES;

            // Format texte : un zéro initial de téléphone ou d'IFU ne se perd pas.
            if ($colonne->type === 'telephone') {
                $feuille->getStyle($plage)->getNumberFormat()->setFormatCode(NumberFormat::FORMAT_TEXT);
            } elseif ($colonne->type === 'entier') {
                $feuille->getStyle($plage)->getNumberFormat()->setFormatCode('0');
            }

            if ($colonne->type === 'liste' && $colonne->liste !== null && ($listes[$colonne->liste]['nombre'] ?? 0) > 0) {
                $liste = $listes[$colonne->liste];
                $validation = new DataValidation();
                $validation->setType(DataValidation::TYPE_LIST);
                // Les unités sont une proposition (champ libre au web) : un avertissement, jamais un blocage.
                $validation->setErrorStyle($colonne->liste === 'unites' ? DataValidation::STYLE_WARNING : DataValidation::STYLE_STOP);
                $validation->setAllowBlank(! $colonne->obligatoire);
                $validation->setShowDropDown(true);
                $validation->setShowErrorMessage(true);
                $validation->setErrorTitle($colonne->libelle);
                $validation->setError('Choisissez une valeur de la liste déroulante.');
                $validation->setFormula1("'".LecteurXlsx::FEUILLE_LISTES."'!\$".$liste['colonne'].'$2:$'.$liste['colonne'].'$'.($liste['nombre'] + 1));
                $feuille->setDataValidation($plage, $validation);
            }
        }

        $feuille->getRowDimension(1)->setRowHeight(30);
        $feuille->freezePane('A2');
    }

    private function ecrireInstructions(Worksheet $feuille, ModuleImport $module): void
    {
        $colonnes = $module->colonnes();
        $ligne = 1;

        $feuille->setCellValueExplicit('A1', 'Modèle « '.$module->libelle().' » — version '.$module->version(), DataType::TYPE_STRING);
        $feuille->getStyle('A1')->getFont()->setBold(true)->setSize(14);
        $ligne = 3;

        $ecrire = function (string $a, string $b = '') use ($feuille, &$ligne): void {
            $feuille->setCellValueExplicit('A'.$ligne, $a, DataType::TYPE_STRING);
            if ($b !== '') {
                $feuille->setCellValueExplicit('B'.$ligne, $b, DataType::TYPE_STRING);
            }
            $ligne++;
        };
        $titre = function (string $texte) use ($feuille, &$ligne): void {
            $ligne++;
            $feuille->setCellValueExplicit('A'.$ligne, $texte, DataType::TYPE_STRING);
            $feuille->getStyle('A'.$ligne)->getFont()->setBold(true);
            $ligne++;
        };

        $ecrire('Modèle', $module->libelle());
        $feuille->setCellValueExplicit('A'.$ligne, 'Version du modèle', DataType::TYPE_STRING);
        $feuille->setCellValue('B'.$ligne, $module->version());
        $ligne++;
        $ecrire('Généré le', now()->format('d/m/Y H:i'));

        $titre('Comment remplir ce modèle');
        $ecrire('1.', 'Remplissez la feuille « '.LecteurXlsx::FEUILLE_DONNEES.' », une ligne par fiche, sous les en-têtes. Les lignes d\'exemple ci-dessous NE sont PAS importées.');
        $ecrire('2.', 'NE RENOMMEZ PAS les en-têtes et ne supprimez aucune colonne ni la feuille « '.LecteurXlsx::FEUILLE_DONNEES.' ». Les colonnes marquées d\'une étoile (*) sont obligatoires.');
        $ecrire('3.', 'Déposez ensuite le fichier à l\'étape 3 de l\'écran « Importation en masse » : un aperçu ligne par ligne s\'affiche AVANT toute écriture.');
        $ecrire('Création seule', 'Une fiche déjà présente est IGNORÉE, jamais modifiée. Importer deux fois le même fichier ne crée aucun doublon.');
        foreach ($module->notes() as $note) {
            $ecrire('•', $note);
        }

        $titre('Formats');
        $ecrire('Montants', 'Francs CFA ENTIERS, sans décimale ni séparateur de milliers (exemple : 4500).');
        $ecrire('Nombres', 'Quantités et pourcentages : virgule ou point (exemple : 8,5).');
        $ecrire('Dates', 'Format AAAA-MM-JJ (exemple : 2026-11-08). Aucune date n\'est demandée par ce modèle.');
        $ecrire('Téléphones', 'Texte : les cellules du modèle sont déjà au format texte, le zéro initial est conservé.');
        $ecrire('Limites', number_format(LecteurXlsx::LIGNES_MAX, 0, ',', ' ').' lignes et '.(LecteurXlsx::TAILLE_MAX_OCTETS / 1024 / 1024).' Mo au plus par fichier. Fichier .xlsx uniquement.');

        $titre('Les colonnes');
        foreach (['Colonne', 'Obligatoire', 'Format', 'Explication'] as $i => $entete) {
            $cellule = Coordinate::stringFromColumnIndex($i + 1).$ligne;
            $feuille->setCellValueExplicit($cellule, $entete, DataType::TYPE_STRING);
            $feuille->getStyle($cellule)->getFont()->setBold(true);
        }
        $ligne++;
        foreach ($colonnes as $colonne) {
            $feuille->setCellValueExplicit('A'.$ligne, $colonne->entete(), DataType::TYPE_STRING);
            $feuille->setCellValueExplicit('B'.$ligne, $colonne->obligatoire ? 'Oui' : 'Non', DataType::TYPE_STRING);
            $feuille->setCellValueExplicit('C'.$ligne, $colonne->formatLisible(), DataType::TYPE_STRING);
            $feuille->setCellValueExplicit('D'.$ligne, $colonne->aide, DataType::TYPE_STRING);
            $ligne++;
        }

        $titre('Exemples de lignes remplies (non importées)');
        foreach ($colonnes as $i => $colonne) {
            $cellule = Coordinate::stringFromColumnIndex($i + 1).$ligne;
            $feuille->setCellValueExplicit($cellule, $colonne->entete(), DataType::TYPE_STRING);
            $feuille->getStyle($cellule)->getFont()->setBold(true);
        }
        $ligne++;
        foreach ($module->exemples() as $exemple) {
            foreach ($colonnes as $i => $colonne) {
                $feuille->setCellValueExplicit(Coordinate::stringFromColumnIndex($i + 1).$ligne, (string) ($exemple[$colonne->cle] ?? ''), DataType::TYPE_STRING);
            }
            $ligne++;
        }

        foreach (range(1, max(4, count($colonnes))) as $i) {
            $feuille->getColumnDimension(Coordinate::stringFromColumnIndex($i))->setWidth($i === 1 ? 30 : 26);
        }
    }

    private function ecrireMeta(Worksheet $feuille, ModuleImport $module): void
    {
        $lignes = [
            ['modele', $module->cle()],
            ['version', $module->version()],
            ['empreinte', $module->empreinte()],
            ['genere_le', now()->format('Y-m-d H:i')],
        ];
        foreach ($lignes as $i => [$cle, $valeur]) {
            $feuille->setCellValueExplicit('A'.($i + 1), $cle, DataType::TYPE_STRING);
            if (is_int($valeur)) {
                $feuille->setCellValue('B'.($i + 1), $valeur);
            } else {
                $feuille->setCellValueExplicit('B'.($i + 1), $valeur, DataType::TYPE_STRING);
            }
        }
    }
}
