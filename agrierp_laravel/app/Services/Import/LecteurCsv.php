<?php

namespace App\Services\Import;

/**
 * Ticket IMPORT-5 — LECTURE D'UN FICHIER CSV DE REPLI (quand Excel n'est pas disponible : tableur libre, export d'un autre logiciel).
 *
 * ⚠️ Même architecture, mêmes règles et mêmes messages que [LecteurXlsx] : le CSV est ramené au MÊME tableau « numéro de ligne →
 * clé de colonne → texte » ; tout ce qui suit (validation ligne par ligne, clé naturelle, création seule, rapport) est inchangé.
 * Le rapport téléchargeable reste un classeur xlsx.
 *
 * Ce que le CSV n'a PAS : la feuille « Modele » (ni le nom du module ni la version ne se contrôlent : le module est celui choisi à
 * l'étape 1, les en-têtes EXACTS du modèle font foi) ni formats de cellule (un zéro initial de téléphone, une date réécrite par
 * le tableur sont à la charge de l'utilisateur : une date qui n'est pas AAAA-MM-JJ est refusée avec son motif).
 *
 * Lecture : UTF-8 (avec ou sans BOM) ; à défaut Windows-1252 (l'export « CSV » d'Excel en français) ; séparateur `;`, `,` ou
 * tabulation, reconnu sur la ligne d'en-têtes (à égalité : `;`) ; guillemets doublés ; un champ entre guillemets peut contenir un
 * saut de ligne. Le numéro de ligne est celui de l'ENREGISTREMENT (l'en-tête est la ligne 1).
 */
class LecteurCsv
{
    /**
     * @return array{lignes: array<int, array<string, string>>, lues: int}
     *
     * @throws ImportRefuse
     */
    public function lire(string $chemin, ModuleImport $module): array
    {
        $taille = @filesize($chemin);
        if ($taille === false || ! is_readable($chemin)) {
            throw new ImportRefuse('Le fichier est illisible : choisissez-le de nouveau.');
        }
        if ($taille > LecteurXlsx::TAILLE_MAX_OCTETS) {
            throw new ImportRefuse('Le fichier dépasse '.(LecteurXlsx::TAILLE_MAX_OCTETS / 1024 / 1024).' Mo ('.number_format($taille / 1024 / 1024, 1, ',', ' ').' Mo) : réduisez le nombre de lignes.');
        }

        $texte = (string) file_get_contents($chemin);
        if (str_starts_with($texte, "\xEF\xBB\xBF")) {
            $texte = substr($texte, 3);
        }
        if (trim($texte) === '' || str_contains($texte, "\0")) {
            throw new ImportRefuse("Ce fichier n'est pas un fichier CSV lisible. Utilisez le modèle « {$module->libelle()} » téléchargé à l'étape 2.");
        }
        if (! mb_check_encoding($texte, 'UTF-8')) {
            $texte = mb_convert_encoding($texte, 'UTF-8', 'Windows-1252');
        }

        $enregistrements = $this->enregistrements($texte);
        $entetes = array_map(fn (string $c) => LectureValeurs::texte($c), $enregistrements[0] ?? []);

        $positions = [];
        $manquantes = [];
        foreach ($module->colonnes() as $colonne) {
            $p = array_search($colonne->entete(), $entetes, true);
            if ($p === false) {
                $manquantes[] = '« '.$colonne->entete().' »';
            } else {
                $positions[$colonne->cle] = $p;
            }
        }
        if ($manquantes !== []) {
            throw new ImportRefuse(
                (count($manquantes) > 1 ? 'Colonnes manquantes ou renommées' : 'Colonne manquante ou renommée')
                .' dans la première ligne du fichier CSV : '.implode(', ', $manquantes)
                .'. Ne renommez pas les en-têtes : téléchargez le modèle « '.$module->libelle().' » à jour.'
            );
        }

        if (count($enregistrements) > LecteurXlsx::LIGNES_PARCOURUES_MAX) {
            throw new ImportRefuse('Le fichier compte plus de '.number_format(LecteurXlsx::LIGNES_PARCOURUES_MAX, 0, ',', ' ').' lignes : supprimez les lignes vides ou découpez le fichier.');
        }

        $lignes = [];
        foreach ($enregistrements as $i => $cellules) {
            if ($i === 0) {
                continue;
            }
            $ligne = [];
            $vide = true;
            foreach ($positions as $cle => $p) {
                $t = LectureValeurs::texte($cellules[$p] ?? null);
                if ($t !== '') {
                    $vide = false;
                }
                $ligne[$cle] = $t;
            }
            if ($vide) {
                continue;
            }
            $lignes[$i + 1] = $ligne;
            if (count($lignes) > LecteurXlsx::LIGNES_MAX) {
                throw new ImportRefuse('Le fichier dépasse '.number_format(LecteurXlsx::LIGNES_MAX, 0, ',', ' ').' lignes : découpez-le en plusieurs fichiers.');
            }
        }

        if ($lignes === []) {
            throw new ImportRefuse('Le fichier ne contient aucune ligne à importer : remplissez le fichier sous les en-têtes.');
        }

        return ['lignes' => $lignes, 'lues' => count($lignes)];
    }

    /** @return array<int, array<int, string>> */
    private function enregistrements(string $texte): array
    {
        $texte = str_replace(["\r\n", "\r"], "\n", $texte);
        $fin = strpos($texte, "\n");
        $premiere = $fin === false ? $texte : substr($texte, 0, $fin);
        $separateur = ';';
        $meilleur = -1;
        foreach ([';', ',', "\t"] as $candidat) {
            $n = substr_count($premiere, $candidat);
            if ($n > $meilleur) {
                $meilleur = $n;
                $separateur = $candidat;
            }
        }

        $enregistrements = [];
        $champ = '';
        $ligne = [];
        $guillemets = false;
        $longueur = strlen($texte);
        for ($i = 0; $i < $longueur; $i++) {
            $c = $texte[$i];
            if ($guillemets) {
                if ($c === '"') {
                    if (($texte[$i + 1] ?? '') === '"') {
                        $champ .= '"';
                        $i++;
                    } else {
                        $guillemets = false;
                    }
                } else {
                    $champ .= $c;
                }
            } elseif ($c === '"' && $champ === '') {
                $guillemets = true;
            } elseif ($c === $separateur) {
                $ligne[] = $champ;
                $champ = '';
            } elseif ($c === "\n") {
                $ligne[] = $champ;
                $enregistrements[] = $ligne;
                $ligne = [];
                $champ = '';
            } else {
                $champ .= $c;
            }
        }
        if ($champ !== '' || $ligne !== []) {
            $ligne[] = $champ;
            $enregistrements[] = $ligne;
        }

        return $enregistrements;
    }
}
