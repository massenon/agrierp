<?php

namespace App\Console\Commands;

use App\Models\AuditLog;
use App\Services\ViderSessionsService;
use Illuminate\Console\Command;

/** Ticket 15.54 — vide toutes les sessions web et révoque les jetons des postes (cPanel, maintenance). */
class ViderSessions extends Command
{
    protected $signature = 'agrierp:vider-sessions {--force : ne pas demander de confirmation}';

    protected $description = 'Déconnecte tous les utilisateurs : sessions web vidées, jetons des postes révoqués';

    public function handle(ViderSessionsService $service): int
    {
        if (! $this->option('force') && ! $this->confirm('Tous les utilisateurs et tous les postes seront déconnectés. Continuer ?')) {
            $this->info('Rien n\'a été fait.');

            return self::SUCCESS;
        }

        $resultat = $service->vider();
        AuditLog::record('sessions.videes', 'administration');

        $this->info("{$resultat['sessions']} session(s) web supprimée(s), {$resultat['jetons']} jeton(s) de poste révoqué(s).");

        return self::SUCCESS;
    }
}
