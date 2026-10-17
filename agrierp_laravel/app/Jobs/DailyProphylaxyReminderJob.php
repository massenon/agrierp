<?php

namespace App\Jobs;

use App\Models\LivestockLot;
use App\Models\Notification;
use App\Models\ProphylaxisScheduleStandard;
use App\Services\ProtocoleDuJourService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

/**
 * GAP CRITIQUE TROUVÉ ET COMBLÉ (question directe sur les Cron Jobs) —
 * `RAPPEL_DE_PROPHYLAXIE_DU_JOUR.md` spécifie ce mécanisme en détail
 * depuis longtemps dans la documentation, mais aucun fichier
 * `app/Jobs/` n'existait nulle part dans ce projet avant ce ticket —
 * `LISTE_DES_CRON_JOBS_CPANEL.md` listait cette tâche comme "obligatoire"
 * sans qu'elle ait jamais été construite.
 *
 * Pour chaque bande active (`livestock_lots.status='actif'` +
 * `modules_config.is_enabled=true` pour son espèce), calcule le jour du
 * cycle depuis la date de référence (dernière saillie si reproduction,
 * sinon date de mise en lot) et cherche un traitement dû dans
 * `prophylaxis_schedule_standards` pour ce jour précis.
 *
 * ⚠️ ÉCART DE SCHÉMA HONNÊTEMENT COMBLÉ : la spécification suppose un
 * `cycle_day` entier directement comparable — `prophylaxis_schedule_standards.period_label`
 * n'était qu'un texte libre ("Le 5e jour", "J1"). `cycle_day_start`/
 * `cycle_day_end` ajoutés dans ce même ticket pour porter cette
 * comparaison réellement.
 *
 * ⚠️ 2 ENTRÉES NON COUVERTES, DOCUMENTÉES PLUTÔT QUE FORCÉES : "Le 1er du
 * mois" (cuniculture, porciculture) a `cycle_day_start`/`end` à `null` —
 * son calcul est basé sur le jour calendaire du mois, pas sur le jour du
 * cycle depuis la mise en lot (base de calcul différente). Ces 2 entrées
 * sont explicitement ignorées par ce job (jamais un jour de cycle deviné
 * à tort), un futur mécanisme calendaire séparé resterait à construire
 * si nécessaire.
 *
 * 🔁 TICKET 15.35 — LA RÈGLE DU JOUR DE CYCLE A ÉTÉ EXTRAITE dans
 * `App\Services\ProtocoleDuJourService` (J1 = jour de référence ; dernière
 * saillie pour la reproduction ; « Le 1er du mois » non évalué), pour que les
 * fiches Lapins et Porcs appliquent la MÊME règle. Au passage, un défaut du
 * calcul d'origine a été corrigé : `diffInDays(now()) + 1` est un flottant sous
 * Carbon 3, donc les entrées d'un jour unique ne correspondaient jamais.
 *
 * ⚠️ ÉVÉNEMENT REVERB NON DÉCLENCHÉ, HONNÊTEMENT : la spécification
 * mentionne `event(new ProphylaxyReminderIssued(...))` pour un badge mis
 * à jour "sans rechargement de page" — aucune infrastructure Reverb
 * réelle n'existe dans ce projet (déjà documenté au ticket 13.1,
 * `FeedAutonomyAlertTest`, même gap). La `Notification` est bien créée
 * réellement (persistée, visible à la prochaine requête/rechargement) —
 * seul le push instantané reste non câblé, pas la notification
 * elle-même.
 */
class DailyProphylaxyReminderJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function handle(): void
    {
        $protocole = app(ProtocoleDuJourService::class);

        $activeLots = LivestockLot::where('status', 'actif')
            ->where('is_active', true)
            ->whereHas('species', fn ($q) => $q->where('is_enabled', true))
            ->with(['species', 'reproductionEvents'])
            ->get();

        foreach ($activeLots as $lot) {
            // Ticket 15.35 — la règle du jour de cycle vit dans
            // `ProtocoleDuJourService`, partagée avec les fiches Lapins et Porcs.
            // `null` = bande indéterminable (pas de date de référence) : ignorée.
            $cycleDay = $protocole->jourDeCycle($lot);

            if ($cycleDay === null) {
                continue;
            }

            foreach ($protocole->traitementsDus($lot->species->code, $cycleDay) as $treatment) {
                $this->issueNotificationIfNotAlreadySent($lot, $treatment);
            }
        }
    }

    private function issueNotificationIfNotAlreadySent(LivestockLot $lot, ProphylaxisScheduleStandard $treatment): void
    {
        $title = "Traitement dû aujourd'hui — {$lot->code}";

        $alreadySent = Notification::where('type', 'prophylaxis_due')
            ->where('title', $title)
            ->where('message', 'like', "%{$treatment->treatment}%")
            ->whereDate('created_at', today())
            ->exists();

        if ($alreadySent) {
            return;
        }

        Notification::create([
            'target_role' => 'animalier',
            'type' => 'prophylaxis_due',
            'severity' => 'warning',
            'title' => $title,
            'message' => "{$treatment->treatment} — {$treatment->product_recommended}, {$treatment->dosage} — Bande {$lot->code}, {$lot->species->label}",
            'icon' => 'vaccines',
            'link_url' => route('elevage.bandes', ['search' => $lot->code]),
            'is_read' => false,
        ]);

        // ⚠️ event(new ProphylaxyReminderIssued($lot, $treatment)) volontairement
        // omis — aucune infrastructure Reverb réelle dans ce projet, voir
        // docblock de classe. La notification persistée ci-dessus reste
        // pleinement réelle.
    }
}
