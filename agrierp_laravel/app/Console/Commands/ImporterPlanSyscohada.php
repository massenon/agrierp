<?php

namespace App\Console\Commands;

use App\Services\ImporterPlanSyscohadaService;
use Illuminate\Console\Command;
use InvalidArgumentException;

/**
 * Ticket 15.27 — importe (INSERTION SEULE) le plan comptable SYSCOHADA révisé officiel. Voir
 * `ImporterPlanSyscohadaService` : aucun compte existant n'est modifié ; `--dry-run` compte sans écrire.
 */
class ImporterPlanSyscohada extends Command
{
    protected $signature = 'comptabilite:importer-plan-syscohada {--dry-run : Compte les comptes à créer sans rien écrire} {--fichier= : CSV « Code;Libellé » (défaut : celui du dépôt)}';

    protected $description = 'Ajoute au plan comptable les comptes SYSCOHADA révisé absents (insertion seule, idempotent)';

    public function handle(ImporterPlanSyscohadaService $service): int
    {
        try {
            $r = $service->importer($this->option('fichier') ?: null, (bool) $this->option('dry-run'));
        } catch (InvalidArgumentException $e) {
            $this->error($e->getMessage());

            return self::FAILURE;
        }

        $this->line(($r['dry_run'] ? '[SIMULATION] ' : '').'Comptes dans le CSV : '.$r['total_csv'].' (déjà présents : '.$r['deja_presents'].')');
        $this->info(($r['dry_run'] ? 'Comptes qui seraient créés : ' : 'Comptes créés : ').$r['crees']);
        foreach ($r['par_classe'] as $classe => $n) {
            $this->line("  classe {$classe} : {$n}");
        }
        foreach ($r['libelles_longs'] as $l) {
            $this->warn("Libellé du compte {$l['code']} : {$l['longueur']} caractères (> 150), conservé entier.");
        }
        foreach ($r['libelles_a_corriger_par_le_cabinet'] as $l) {
            $this->warn("À corriger par le cabinet FAGUEZ — compte {$l['code']} : « {$l['label']} »");
        }
        $this->line('SHA-256 du fichier : '.$r['empreinte']);

        return self::SUCCESS;
    }
}
