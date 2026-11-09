<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\ModuleConfig;
use App\Services\ClotureExerciceService;
use App\Services\DemarrageService;
use Livewire\Attributes\On;
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

    /**
     * @param  bool  $auto  vrai : l'assistant s'ouvre de lui-même (tableau de bord) ; faux : il est monté, fermé, pour que
     *                      « Relancer l'assistant » du bouton d'aide (ticket AIDE-1) puisse le rouvrir de n'importe quel écran.
     */
    public function mount(bool $auto = true): void
    {
        // Module éteint par défaut (Modules Actifs, carte « Assistant de démarrage »).
        $this->afficher = $auto
            && ModuleConfig::isEnabled(ModuleConfig::ASSISTANT_DEMARRAGE)
            && auth()->user()?->can('manage-parametres')
            && CompanySetting::query()->value('onboarding_completed_at') === null
            && ! session()->has(self::CLE_SESSION)
            // Une ferme déjà en place (toutes les étapes obligatoires constatées) n'a rien à lire.
            && ! app(DemarrageService::class)->obligatoiresFaites();
    }

    /**
     * Ticket AIDE-1 — « Relancer l'assistant de démarrage » (bouton d'aide). Rouvre la fenêtre MÊME si elle a été reportée
     * (`demarrage_reporte`) ou si le démarrage est terminé.
     *
     * ⚠️ Rien n'est écrit : ni `onboarding_completed_at` (jamais remis à vide), ni la session. Mêmes conditions que
     * l'ouverture automatique, hors « déjà terminé / déjà reporté / ferme en place » : module allumé et droit
     * `manage-parametres`. Sans l'un des deux, l'événement est ignoré en silence (le bouton n'est de toute façon pas rendu).
     */
    #[On('relancer-assistant')]
    public function relancer(): void
    {
        if (! ModuleConfig::isEnabled(ModuleConfig::ASSISTANT_DEMARRAGE) || ! auth()->user()?->can('manage-parametres')) {
            return;
        }

        $this->afficher = true;
        $this->dispatch('open-modal', name: 'modal-demarrage');
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

        // Ticket AIDE-1 : relancé après la fin, « Terminer » referme sans réécrire la date de fin ni l'audit.
        if (CompanySetting::current()->onboarding_completed_at === null) {
            CompanySetting::current()->update(['onboarding_completed_at' => now()]);
            AuditLog::record('onboarding.completed', 'parametres');
        }

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
