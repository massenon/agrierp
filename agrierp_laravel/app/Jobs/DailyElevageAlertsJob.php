<?php

namespace App\Jobs;

use App\Services\AlertesElevageService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

/**
 * Ticket 15.49 — émission quotidienne des alertes de la cloche (stock sous seuil, mortalité anormale, soins
 * planifiés à venir ou en retard, échecs de reproduction). Toute la règle vit dans `AlertesElevageService`.
 */
class DailyElevageAlertsJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function handle(AlertesElevageService $alertes): void
    {
        $alertes->emettre();
    }
}
