<?php

namespace App\Services;

use App\Models\LivestockLot;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\VeterinaryRecord;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;

/**
 * Ticket 15.35 — LA RÈGLE DU JOUR DE CYCLE, EN UN SEUL EXEMPLAIRE.
 *
 * Elle était écrite en dur dans `DailyProphylaxyReminderJob`. Les fiches
 * Lapins et Porcs en ont besoin à leur tour ; une seconde copie d'une règle
 * sanitaire finit toujours par diverger de la première. Le job ET les fiches
 * passent désormais ici — c'est aussi la règle du poste Flutter
 * (`SoinsRepository.protocoleDuJour`, F0.12), dont ce service est la
 * contrepartie serveur.
 *
 * LA RÈGLE (reprise du job, rien d'inventé) :
 *   - J1 = le jour de référence lui-même ;
 *   - jour de référence = la DERNIÈRE saillie pour une bande au stade
 *     `reproduction`, la date de mise en lot sinon ;
 *   - une bande en reproduction sans saillie connue est INDÉTERMINÉE ;
 *   - un traitement est dû si `cycle_day_start <= J <= cycle_day_end` ;
 *   - les entrées « Le 1er du mois » (bornes nulles) ne sont JAMAIS évaluées :
 *     leur base de calcul est le jour calendaire, pas le cycle (décision client
 *     non tranchée — comportement actuel conservé), mais elles sont COMPTÉES
 *     pour que l'écran puisse dire qu'il ne les évalue pas.
 *
 * 🔴 DÉFAUT DU JOB CORRIGÉ À L'EXTRACTION. L'ancien calcul
 * `$reference->diffInDays(now()) + 1` renvoie un FLOTTANT sous Carbon 3
 * (5,25 à 06 h 00 pour un J5) : les entrées d'un jour unique (bornes 5 et 5)
 * ne correspondaient jamais, seuls les intervalles larges avaient une chance.
 * Le calcul se fait maintenant en jours CALENDAIRES entiers (minuit à minuit).
 */
class ProtocoleDuJourService
{
    /**
     * Jour de cycle de la bande à la date donnée ; `null` si non calculable.
     * Peut valoir 0 ou moins avant le jour de référence (cycle pas commencé).
     */
    public function jourDeCycle(LivestockLot $bande, ?CarbonInterface $quand = null): ?int
    {
        $reference = $this->dateDeReference($bande);

        if (! $reference) {
            return null;
        }

        $jour = Carbon::instance($quand ?? now())->startOfDay();

        // Les deux dates sont à minuit : l'écart est un entier de jours ; l'arrondi
        // ne fait que neutraliser le flottant renvoyé par Carbon 3.
        return (int) round($reference->diffInDays($jour, false)) + 1;
    }

    /** Pourquoi le jour de cycle est inconnu — à afficher tel quel. */
    public function motifIndetermine(LivestockLot $bande): string
    {
        return $bande->stage === 'reproduction'
            ? 'Bande en reproduction : le cycle se compte depuis la dernière saillie, et aucune saillie n\'est enregistrée pour cette bande.'
            : 'Date de mise en lot inconnue : le jour du cycle ne peut pas être calculé.';
    }

    /**
     * Entrées actives du barème dues ce jour de cycle, pour une espèce.
     *
     * @return Collection<int, ProphylaxisScheduleStandard>
     */
    public function traitementsDus(string $codeEspece, int $jourDeCycle): Collection
    {
        return ProphylaxisScheduleStandard::where('species_code', $codeEspece)
            ->where('is_active', true)
            ->whereNotNull('cycle_day_start')
            ->where('cycle_day_start', '<=', $jourDeCycle)
            ->where('cycle_day_end', '>=', $jourDeCycle)
            ->orderBy('cycle_day_start')
            ->orderBy('treatment')
            ->get();
    }

    /** Entrées calendaires (bornes nulles) que le moteur n'évalue pas — COMPTÉES, jamais masquées. */
    public function calendairesNonEvalues(string $codeEspece): int
    {
        return ProphylaxisScheduleStandard::where('species_code', $codeEspece)
            ->where('is_active', true)
            ->whereNull('cycle_day_start')
            ->count();
    }

    /** Le protocole complet d'une bande à une date, avec l'état de chaque traitement. */
    public function pourBande(LivestockLot $bande, ?CarbonInterface $quand = null): ProtocoleDuJour
    {
        $codeEspece = $bande->species->code;
        $calendaires = $this->calendairesNonEvalues($codeEspece);
        $jourDeCycle = $this->jourDeCycle($bande, $quand);

        if ($jourDeCycle === null) {
            // Ticket #45 — bande indéterminée (reproduction sans saillie) : le cycle n'est pas
            // calculable, mais l'animalier peut quand même administrer des traitements. On expose
            // tous les traitements du barème avec bornes non nulles et l'état « déjà administré »
            // du jour, comme pour une bande déterminée — le motif reste affiché.
            $jour = Carbon::instance($quand ?? now())->startOfDay();
            $faits = $this->soinsDuJour($bande, $jour);
            $traitements = $this->tousLesTraitementsCycles($codeEspece)
                ->map(fn (ProphylaxisScheduleStandard $standard) => [
                    'standard' => $standard,
                    'deja_administre' => $faits->contains($standard->treatment),
                ])
                ->values();

            return new ProtocoleDuJour($traitements, null, $this->motifIndetermine($bande), $calendaires);
        }

        $jour = Carbon::instance($quand ?? now())->startOfDay();
        $faits = $this->soinsDuJour($bande, $jour);

        $traitements = $this->traitementsDus($codeEspece, $jourDeCycle)
            ->map(fn (ProphylaxisScheduleStandard $standard) => [
                'standard' => $standard,
                'deja_administre' => $faits->contains($standard->treatment),
            ])
            ->values();

        return new ProtocoleDuJour($traitements, $jourDeCycle, null, $calendaires);
    }

    /**
     * Libellés des soins consignés pour cette bande ce jour-là.
     *
     * ⚠️ Le rapprochement se fait sur le LIBELLÉ du traitement
     * (`veterinary_records.action_type` = `prophylaxis_schedule_standards.treatment`),
     * comme au poste : `veterinary_records` ne porte aucune référence explicite
     * au barème, et en ajouter une changerait le contrat de `/api/sync/*`
     * (la table est poussée ET tirée). Un soin archivé ne compte pas.
     *
     * @return Collection<int, string>
     */
    private function soinsDuJour(LivestockLot $bande, CarbonInterface $jour): Collection
    {
        return VeterinaryRecord::where('lot_id', $bande->id)
            ->where('is_active', true)
            ->whereDate('record_date', $jour->toDateString())
            ->pluck('action_type');
    }

    /** Tous les traitements actifs du barème ayant des bornes de cycle (hors calendaires). */
    private function tousLesTraitementsCycles(string $codeEspece): Collection
    {
        return ProphylaxisScheduleStandard::where('species_code', $codeEspece)
            ->where('is_active', true)
            ->whereNotNull('cycle_day_start')
            ->orderBy('cycle_day_start')
            ->orderBy('treatment')
            ->get();
    }

    private function dateDeReference(LivestockLot $bande): ?Carbon
    {
        $reference = $bande->stage === 'reproduction'
            ? $bande->reproductionEvents()->latest('saillie_date')->value('saillie_date')
            : $bande->created_date;

        return $reference ? Carbon::parse($reference)->startOfDay() : null;
    }
}
