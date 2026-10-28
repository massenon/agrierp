<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Services\ClotureExerciceService;
use App\Services\DemarrageService;
use Livewire\Component;

/**
 * Ticket 15.51 — ASSISTANT DE DÉMARRAGE (hors maquette, demandé par le client).
 *
 * S'ouvre sur le tableau de bord de l'administrateur tant qu'une étape obligatoire manque et que l'assistant
 * n'a pas été marqué terminé. ⚠️ NON
 * BLOQUANT : « Plus tard » le referme pour la session, rien n'empêche de travailler. Les étapes sont lues dans la
 * base (`DemarrageService`), jamais cochées à la main.
 *
 * Seule action propre à l'assistant : ouvrir le PREMIER exercice. Aucun écran ne le permettait (seule la clôture
 * crée l'exercice suivant, constat du ticket 13.4) ; la règle est celle de `FiscalYearSeeder` — année civile.
 */
class AssistantDemarrage extends Component
{
    public bool $afficher = false;

    public const CLE_SESSION = 'demarrage_reporte';

    public function mount(): void
    {
        $this->afficher = auth()->user()?->can('manage-parametres')
            && CompanySetting::query()->value('onboarding_completed_at') === null
            && ! session()->has(self::CLE_SESSION)
            // Une ferme déjà en place (toutes les étapes obligatoires constatées) n'a rien à lire.
            && ! app(DemarrageService::class)->obligatoiresFaites();
    }

    public function reporter(): void
    {
        session()->put(self::CLE_SESSION, true);
        $this->afficher = false;
        $this->dispatch('close-modal', name: 'modal-demarrage');
    }

    public function ouvrirExercice(): void
    {
        $this->authorize('manage-comptabilite');

        try {
            $exercice = app(ClotureExerciceService::class)->ouvrirPremierExercice();
        } catch (\DomainException $e) {
            $this->dispatch('toast', type: 'error', message: $e->getMessage());

            return;
        }

        $annee = $exercice->year;
        $this->dispatch('toast', type: 'success', message: "Exercice {$annee} ouvert (du 01/01/{$annee} au 31/12/{$annee}).");
    }

    public function terminer(): void
    {
        $this->authorize('manage-parametres');

        if (! app(DemarrageService::class)->obligatoiresFaites()) {
            $this->dispatch('toast', type: 'error', message: 'Des étapes obligatoires restent à faire.');

            return;
        }

        CompanySetting::current()->update(['onboarding_completed_at' => now()]);
        AuditLog::record('onboarding.completed', 'parametres');

        $this->afficher = false;
        $this->dispatch('close-modal', name: 'modal-demarrage');
        $this->dispatch('toast', type: 'success', message: 'Démarrage terminé.');
    }

    public function render()
    {
        return view('livewire.parametres.assistant-demarrage', [
            'etapes' => $this->afficher ? app(DemarrageService::class)->etapes() : [],
        ]);
    }
}
