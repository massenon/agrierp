<?php

namespace App\Console\Commands;

use App\Services\CodeSecoursService;
use Illuminate\Console\Command;

/**
 * Ticket MDP-1 — génère le CODE DE SECOURS de l'administrateur, affiché UNE seule fois.
 *
 * À imprimer et ranger au coffre : il sert à `agrierp:reinitialiser-admin` quand le dernier administrateur a oublié son
 * mot de passe. Seule son empreinte est conservée ; un nouveau code REMPLACE l'ancien (confirmation demandée).
 */
class CodeSecours extends Command
{
    protected $signature = 'agrierp:code-secours {--force : remplacer le code actif sans confirmation}';

    protected $description = "Génère le code de secours de l'administrateur (affiché une seule fois : à imprimer et ranger au coffre)";

    public function handle(CodeSecoursService $service): int
    {
        if ($service->existeUnCodeActif() && ! $this->option('force')
            && ! $this->confirm("Un code de secours est déjà actif. Le remplacer ? L'ancien code ne fonctionnera plus.", false)) {
            $this->info("Rien n'a été fait : le code actif est conservé.");

            return self::SUCCESS;
        }

        $code = $service->generer();

        $this->newLine();
        $this->warn('CODE DE SECOURS DE L\'ADMINISTRATEUR — affiché UNE SEULE FOIS, il ne pourra plus être relu.');
        $this->line('');
        $this->line("    {$code}");
        $this->line('');
        $this->info('Imprimez-le et rangez-le au coffre. Il sert à : php artisan agrierp:reinitialiser-admin <identifiant>');

        return self::SUCCESS;
    }
}
