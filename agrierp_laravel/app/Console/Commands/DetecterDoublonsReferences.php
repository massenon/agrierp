<?php

namespace App\Console\Commands;

use App\Models\AccountingEntry;
use Illuminate\Console\Command;

/**
 * Ticket 15.20a — DÉTECTION (lecture seule) des numéros d'écriture en doublon.
 *
 * Avant le correctif, `generateReference()` redonnait `OD-AAAA-0001` à toute écriture dont la référence
 * finissait par un libellé. Ce rapport liste ce qui existe déjà. Il NE RENUMÉROTE RIEN : changer le
 * numéro d'une pièce déjà passée (et possiblement déjà imprimée, déclarée, citée dans un rapprochement)
 * est une décision du client et du cabinet, jamais un effet de bord d'un correctif.
 *
 * Code de sortie : 0 si aucun doublon, 1 sinon (utilisable dans une vérification planifiée).
 */
class DetecterDoublonsReferences extends Command
{
    protected $signature = 'comptabilite:doublons-references {--detail : liste chaque écriture (date, libellé, id)}';

    protected $description = 'Liste les numéros d\'écriture comptable en doublon (lecture seule, ne modifie rien)';

    public function handle(): int
    {
        $groupes = [];

        foreach (AccountingEntry::query()->orderBy('entry_date')->orderBy('created_at')->get(['id', 'entry_date', 'reference', 'is_active']) as $e) {
            // Le NUMÉRO est le début de la référence (« OD-2026-0001 — libellé »), jamais sa fin.
            if (preg_match('/^([A-Z]{2,}-\d{4}-\d+)/', (string) $e->reference, $m)) {
                $groupes[$m[1]][] = $e;
            }
        }

        $doublons = array_filter($groupes, fn ($g) => count($g) > 1);
        ksort($doublons);

        if ($doublons === []) {
            $this->info('Aucun numéro d\'écriture en doublon.');

            return self::SUCCESS;
        }

        $enTrop = 0;

        foreach ($doublons as $numero => $ecritures) {
            $enTrop += count($ecritures) - 1;
            $this->line($numero.' : '.count($ecritures).' écritures');

            if ($this->option('detail')) {
                foreach ($ecritures as $e) {
                    $this->line('    '.$e->entry_date?->format('Y-m-d').'  '.$e->id.'  '.$e->reference.($e->is_active ? '' : '  [archivée]'));
                }
            }
        }

        $this->newLine();
        $this->warn(count($doublons).' numéro(s) en doublon');
        $this->warn($enTrop.' écriture(s) en trop. Aucune écriture n\'a été modifiée.');
        $this->line('Renuméroter est une décision du client et du cabinet : voir le ticket 15.20a.');

        return self::FAILURE;
    }
}
