<?php

namespace App\Livewire\Elevage\Concerns;

use App\Actions\ValidateProphylaxisTreatmentsAction;
use App\Models\AuditLog;
use App\Services\ProtocoleDuJour;
use App\Services\ProtocoleDuJourService;
use Carbon\Carbon;

/**
 * Ticket 15.35 — SECTION « TRAITEMENTS & PROPHYLAXIE » DES FICHES LAPINS ET PORCS.
 *
 * Câble sur la fiche le moteur qui existait (ticket 3.11 : soins, rémanence,
 * blocage de vente) mais que les fiches n'appelaient pas : elles affichaient un
 * marqueur « Prévu : Sprint 3, ticket 3.11 » périmé. Le comportement est celui
 * du poste (F0.12, `SoinsRepository.protocoleDuJour`), pas une invention :
 * protocole du jour issu du barème `prophylaxis_schedule_standards`, quatre états
 * (Libre / N Prévu(s) / Validé / Effectué / Indéterminé), entrées calendaires
 * comptées et annoncées comme non évaluées, validation qui écrit le soin et sa
 * rémanence.
 *
 * La classe qui l'utilise fournit `lots` (propriété calculée), `selectedDate`
 * et `observations` — la fiche travaille sur sa PREMIÈRE bande active, comme
 * `saveDay()`.
 */
trait AvecProphylaxieDuJour
{
    /** @var array<int, string> identifiants du barème cochés pour le jour affiché */
    public array $traitementsCoches = [];

    /**
     * Ticket 15.41 — LA bande sur laquelle travaille la fiche. Par défaut la PREMIÈRE bande active (comportement
     * historique, fiche porcs inchangée) ; une fiche qui sait choisir sa bande (lapins) redéfinit cette méthode.
     */
    protected function bandeDeLaFiche()
    {
        return $this->lots->first();
    }

    public function getProtocoleDuJourProperty(): ?ProtocoleDuJour
    {
        $bande = $this->bandeDeLaFiche();

        if (! $bande) {
            return null;
        }

        return app(ProtocoleDuJourService::class)->pourBande($bande->load('species'), Carbon::parse($this->selectedDate));
    }

    /**
     * ⚠️ Les cases repartent VIDES à chaque changement de jour : conserver un
     * cochage d'un autre jour ferait valider un soin qui n'a pas été administré.
     */
    public function updatedSelectedDate(): void
    {
        $this->traitementsCoches = [];
    }

    public function validerTraitements(): void
    {
        $this->authorize('manage-elevage');

        $bande = $this->bandeDeLaFiche();

        if (! $bande) {
            $this->dispatch('toast', message: 'Aucune bande active : aucun traitement à valider.', type: 'error');

            return;
        }

        $jour = Carbon::parse($this->selectedDate)->startOfDay();

        // Un traitement n'est pas administré à l'avance. (Garde ajoutée par ce ticket,
        // absente du poste — à confirmer : voir README 15.35, décisions ouvertes.)
        if ($jour->isAfter(today())) {
            $this->dispatch('toast', message: 'Un traitement ne peut pas être validé pour un jour à venir.', type: 'error');

            return;
        }

        $crees = app(ValidateProphylaxisTreatmentsAction::class)->execute(
            $bande,
            $jour,
            array_values(array_map('strval', $this->traitementsCoches)),
            $this->observations,
        );

        $this->traitementsCoches = [];

        if ($crees->isEmpty()) {
            $this->dispatch('toast', message: 'Aucun traitement à enregistrer (déjà validés, ou non prévus ce jour-là).', type: 'warning');

            return;
        }

        AuditLog::record('prophylaxis.validated', 'elevage');

        $this->dispatch('toast', message: $crees->count().' traitement(s) enregistré(s) au registre vétérinaire.', type: 'success');
    }
}
