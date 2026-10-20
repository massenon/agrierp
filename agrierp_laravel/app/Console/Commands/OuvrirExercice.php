<?php

namespace App\Console\Commands;

use App\Models\FiscalYear;
use App\Models\Notification;
use App\Services\OuvertureExerciceService;
use Illuminate\Console\Command;

/**
 * Ticket EX3 (PRD exercices comptables, R2) — OUVERTURE DE L'EXERCICE DE L'ANNÉE, le 1er janvier à 00:00 heure du Bénin
 * (planifiée dans `routes/console.php`, lancée par l'unique cron `schedule:run` de l'hébergement).
 *
 * Idempotente : l'exercice déjà ouvert (par le bouton de décembre, ou par le filet d'une première saisie) est laissé tel
 * quel. Un refus (deux exercices déjà ouverts, année précédente absente) n'est jamais silencieux : l'administrateur
 * reçoit une notification, car la caisse refusera tout ce qui est daté de cette année tant qu'elle n'est pas ouverte.
 */
class OuvrirExercice extends Command
{
    protected $signature = 'agrierp:ouvrir-exercice';

    protected $description = "Ouvre l'exercice comptable de l'année en cours (01/01 → 31/12) s'il n'existe pas encore";

    public function handle(OuvertureExerciceService $ouverture): int
    {
        $annee = (int) now()->setTimezone('Africa/Porto-Novo')->format('Y');

        if (FiscalYear::where('year', $annee)->exists()) {
            $this->info("L'exercice {$annee} existe déjà : rien à faire.");

            return self::SUCCESS;
        }

        try {
            $ouverture->ouvrir($annee, OuvertureExerciceService::TACHE);
        } catch (\DomainException $e) {
            Notification::create([
                'target_role' => 'admin',
                'type' => 'system',
                'severity' => 'critique',
                'title' => "Exercice {$annee} non ouvert",
                'message' => $e->getMessage().' Tant qu\'il ne l\'est pas, toute saisie datée de '.$annee.' est refusée.',
                'icon' => 'event_busy',
                'link_url' => '/cloture-exercice',
            ]);
            $this->error($e->getMessage());

            return self::FAILURE;
        }

        $this->info("Exercice {$annee} ouvert (du 01/01/{$annee} au 31/12/{$annee}).");

        return self::SUCCESS;
    }
}
