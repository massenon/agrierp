<?php

namespace App\Services;

use App\Models\AuditLog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.58 (Sprint 14) — IMPORT D'UN MODULE DEPUIS UNE SAUVEGARDE.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  ⚠️⚠️ LE RISQUE, ET LA DÉCISION QUI EN DÉCOULE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Exécuter un fichier SQL téléversé revient à **accepter des instructions
 * arbitraires sur la base** : `DROP TABLE`, `UPDATE users SET password = …`,
 * `DELETE FROM accounting_entries`. Un import « qui marche » en faisant tourner
 * le fichier tel quel serait la faille la plus grave de toute l'application.
 *
 * ⚠️ **RIEN N'EST JAMAIS EXÉCUTÉ TEL QUEL.** Le fichier est ANALYSÉ, et seules
 * les instructions `INSERT INTO` sont retenues — et uniquement vers les tables
 * du module choisi. Tout le reste est **compté et rejeté**, jamais ignoré en
 * silence : un fichier contenant un `DROP` doit alerter, pas passer inaperçu.
 *
 * ⚠️ **LA TABLE CIBLE EST VÉRIFIÉE CONTRE LA LISTE DU MODULE**, jamais déduite
 * du fichier. Sans cela, un export « Stocks » contenant un `INSERT INTO users`
 * créerait un compte administrateur.
 *
 * ⚠️ **LES VALEURS SONT LIÉES, JAMAIS CONCATÉNÉES** : l'instruction reconstruite
 * passe par des paramètres liés, si bien qu'une valeur hostile reste une valeur.
 */
class ImportModuleService
{
    /** Instructions autorisées — tout le reste est rejeté. */
    private const MOTIF_INSERT = '/^INSERT INTO [`"]?(?<table>[a-z0-9_]+)[`"]?\s*\((?<colonnes>.+?)\)\s*VALUES\s*\((?<valeurs>.+)\);?$/is';

    /** Tables du journal servies au poste par `updated_at` : réhorodatées à l'import (ticket 15.28-bis). */
    private const TABLES_JOURNAL_REHORODATEES = ['accounting_entries', 'accounting_entry_lines'];

    /**
     * @return array{inserees: int, rejetees: int, motifs: array<int, string>}
     */
    public function importer(string $contenuSql, string $module, bool $remplacer = true): array
    {
        $definition = SauvegardeService::modules()[$module] ?? null;

        if ($definition === null) {
            return ['inserees' => 0, 'rejetees' => 0, 'motifs' => ['Module inconnu.']];
        }

        $autorisees = $definition['tables'];
        $inserees = 0;
        $rejetees = 0;
        $motifs = [];

        $instructions = $this->decouper($contenuSql);

        // ⚠️ SUSPENSION DES CLÉS ÉTRANGÈRES À L'EXTÉRIEUR DE LA TRANSACTION.
        // SQLite applique `PRAGMA foreign_keys` uniquement HORS transaction :
        // l'imbrication inverse compile, s'exécute, et ne suspend rien du tout —
        // l'import échouait alors sur la première référence croisée, sans que
        // l'ordre des appels ne trahisse le problème à la lecture.
        Schema::withoutForeignKeyConstraints(function () use (
            $instructions, $autorisees, $remplacer, &$inserees, &$rejetees, &$motifs
        ) {
            DB::transaction(function () use (
                $instructions, $autorisees, $remplacer, &$inserees, &$rejetees, &$motifs
            ) {
                if ($remplacer) {
                    // ⚠️ VIDAGE AVANT INSERTION, dans la MÊME transaction : une
                    // fusion produirait des doublons sur des clés déjà connues,
                    // et un vidage hors transaction laisserait le module vide si
                    // l'insertion échouait ensuite.
                    // ⚠️ ORDRE DE DÉCLARATION : les listes de modules sont
                    // ordonnées enfants d'abord, parents ensuite (voir
                    // `SauvegardeService::modules()`). Vider à l'envers
                    // supprimerait une catégorie encore référencée par ses
                    // produits.
                    foreach ($autorisees as $table) {
                        if (Schema::hasTable($table)) {
                            DB::table($table)->delete();
                        }
                    }
                }

                foreach ($instructions as $instruction) {
                    if (! preg_match(self::MOTIF_INSERT, $instruction, $correspondance)) {
                        $rejetees++;
                        $motifs[] = $this->resumer($instruction);

                        continue;
                    }

                    $table = $correspondance['table'];

                    // ⚠️ La table doit appartenir au module CHOISI. Un export
                    // « Stocks » contenant un `INSERT INTO users` créerait un
                    // compte administrateur.
                    if (! in_array($table, $autorisees, true) || ! Schema::hasTable($table)) {
                        $rejetees++;
                        $motifs[] = "Table hors du module : {$table}";

                        continue;
                    }

                    $colonnes = $this->colonnes($correspondance['colonnes']);
                    $valeurs = $this->valeurs($correspondance['valeurs']);

                    if (count($colonnes) !== count($valeurs)) {
                        $rejetees++;
                        $motifs[] = "Colonnes et valeurs de tailles différentes ({$table})";

                        continue;
                    }

                    // Valeurs LIÉES : une valeur hostile reste une valeur.
                    $ligne = array_combine($colonnes, $valeurs);

                    // 🔴→✅ TICKET 15.28-bis — UNE ÉCRITURE RESTAURÉE DOIT ÊTRE SERVIE AU POSTE.
                    // ⚠️⚠️ Le tirage `/api/sync/pull` ne sert que `updated_at > since`. Réinsérer
                    // une écriture avec l'ANCIEN `updated_at` du fichier la laissait invisible
                    // pour un poste qui l'avait purgée (elle figure pourtant dans
                    // `accounting_entry_ids`), ou qui gardait ses lignes d'avant la sauvegarde.
                    // Pour ces DEUX tables seulement, l'horodatage est l'instant de l'import.
                    // Les autres modules gardent celui du fichier : aucune règle n'est inventée.
                    if (in_array($table, self::TABLES_JOURNAL_REHORODATEES, true)) {
                        $ligne['updated_at'] = now()->format('Y-m-d H:i:s');
                    }

                    DB::table($table)->insert($ligne);
                    $inserees++;
                }
            });
        });

        AuditLog::record('module.imported', 'parametres');

        return [
            'inserees' => $inserees,
            'rejetees' => $rejetees,
            'motifs' => array_slice(array_unique($motifs), 0, 5),
        ];
    }

    /**
     * Découpe le fichier en instructions.
     *
     * Les commentaires (`--`) et les lignes vides sont écartés ; les points-
     * virgules à l'intérieur d'une chaîne ne coupent pas l'instruction, sans
     * quoi un libellé contenant « ; » casserait l'import.
     *
     * @return array<int, string>
     */
    private function decouper(string $sql): array
    {
        $instructions = [];
        $courante = '';
        $dansChaine = false;
        $longueur = strlen($sql);

        for ($i = 0; $i < $longueur; $i++) {
            $caractere = $sql[$i];

            if ($caractere === "'" && ($i === 0 || $sql[$i - 1] !== '\\')) {
                $dansChaine = ! $dansChaine;
            }

            if ($caractere === ';' && ! $dansChaine) {
                $instructions[] = $courante.';';
                $courante = '';

                continue;
            }

            $courante .= $caractere;
        }

        if (trim($courante) !== '') {
            $instructions[] = $courante;
        }

        return collect($instructions)
            ->map(fn ($i) => trim(preg_replace('/^\s*--.*$/m', '', $i)))
            ->filter(fn ($i) => $i !== '' && $i !== ';')
            ->values()
            ->all();
    }

    /** @return array<int, string> */
    private function colonnes(string $brut): array
    {
        return collect(explode(',', $brut))
            ->map(fn ($c) => trim(trim(trim($c), '`"')))
            ->filter()
            ->values()
            ->all();
    }

    /**
     * Découpe la liste de valeurs en respectant les chaînes.
     *
     * @return array<int, string|null>
     */
    private function valeurs(string $brut): array
    {
        $valeurs = [];
        $courante = '';
        $dansChaine = false;
        $longueur = strlen($brut);

        for ($i = 0; $i < $longueur; $i++) {
            $caractere = $brut[$i];

            if ($caractere === "'" && ($i === 0 || $brut[$i - 1] !== '\\')) {
                $dansChaine = ! $dansChaine;
                $courante .= $caractere;

                continue;
            }

            if ($caractere === ',' && ! $dansChaine) {
                $valeurs[] = $this->nettoyer($courante);
                $courante = '';

                continue;
            }

            $courante .= $caractere;
        }

        if (trim($courante) !== '') {
            $valeurs[] = $this->nettoyer($courante);
        }

        return $valeurs;
    }

    private function nettoyer(string $valeur): ?string
    {
        $valeur = trim($valeur);

        if (strcasecmp($valeur, 'NULL') === 0) {
            return null;
        }

        if (str_starts_with($valeur, "'") && str_ends_with($valeur, "'")) {
            $valeur = substr($valeur, 1, -1);

            // Restitution des échappements des deux dialectes.
            return str_replace(["\\'", "''", '\\"', '\\\\'], ["'", "'", '"', '\\'], $valeur);
        }

        return $valeur;
    }

    /** Résumé d'une instruction rejetée — le motif doit être lisible. */
    private function resumer(string $instruction): string
    {
        $premierMot = strtoupper(strtok(trim($instruction), " \t\n"));

        return 'Instruction refusée : '.($premierMot !== false ? $premierMot : '?');
    }
}
