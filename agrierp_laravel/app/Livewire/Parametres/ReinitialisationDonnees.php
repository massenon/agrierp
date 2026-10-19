<?php

namespace App\Livewire\Parametres;

use App\Models\CompanySetting;
use App\Services\ReinitialisationDonneesService;
use Livewire\Component;

/**
 * Ticket 14.56 (Sprint 14) — RÉINITIALISATION DES DONNÉES DE TEST.
 *
 * ⚠️ **ÉCRAN HORS MAQUETTE**, demandé par le client. À valider au prochain
 * point, comme les autres ajouts.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  TROIS VERROUS, ET AUCUN N'EST DÉCORATIF
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 1. ⚠️ **LA BASCULE EST FAUSSE PAR DÉFAUT.** L'onglet n'apparaît pas tant que
 *    le mode démonstration n'a pas été activé délibérément. Une exploitation en
 *    production ne porte donc aucun bouton d'effacement accessible.
 *
 * 2. ⚠️ **UN MOT DE CONFIRMATION DOIT ÊTRE SAISI** (« REINITIALISER »). Une
 *    modale à un seul bouton se clique par réflexe ; recopier un mot oblige à
 *    lire ce qu'on s'apprête à faire. C'est la même logique que la suppression
 *    d'un dépôt sur les forges.
 *
 * 3. ⚠️ **L'AUTORISATION EST VÉRIFIÉE SUR LA MÉTHODE QUI ÉCRIT**, pas seulement
 *    à l'affichage de l'onglet — règle des deux niveaux appliquée partout ici.
 *
 * ⚠️ ET LE PLUS IMPORTANT : l'écran dit que l'opération vide **toutes** les
 * données d'activité, pas seulement celles du jeu de démonstration —
 * l'application ne sait pas les distinguer (voir `ReinitialisationDonneesService`).
 *
 * 🔁 Ticket R-1 (demande du client : « sur le web et le poste ») — le poste déclenche la MÊME action par
 * `Api\ReinitialisationDonneesController` : même droit, mêmes verrous, même service. Verrous et messages vivent
 * dans le service, lus par les deux.
 */
class ReinitialisationDonnees extends Component
{
    public string $confirmation = '';

    /** Ticket R-1 — le mot vit dans le service, partagé avec la route du poste. */
    public const MOT_DE_CONFIRMATION = ReinitialisationDonneesService::MOT_DE_CONFIRMATION;

    public function getReglagesProperty(): ?CompanySetting
    {
        return CompanySetting::first();
    }

    public function getModeDemoActifProperty(): bool
    {
        return (bool) ($this->reglages?->demo_mode_enabled ?? false);
    }

    /**
     * Active ou désactive le mode démonstration (journalisé : voir
     * `ReinitialisationDonneesService::basculerModeDemo()`, partagé avec le poste — ticket R-1).
     */
    public function basculerModeDemo(): void
    {
        $this->authorize('manage-parametres');

        $actif = ReinitialisationDonneesService::basculerModeDemo();

        if ($actif === null) {
            return;
        }

        unset($this->reglages, $this->modeDemoActif);

        $this->dispatch(
            'toast',
            message: ReinitialisationDonneesService::messageBascule($actif),
            type: $actif ? 'warning' : 'success',
        );
    }

    public function reinitialiser(): void
    {
        $this->authorize('manage-parametres');

        // ⚠️ LA BASCULE EST REVÉRIFIÉE ICI. L'onglet masqué ne suffit pas :
        // un appel direct au composant contournerait l'affichage.
        if (! $this->modeDemoActif) {
            $this->dispatch(
                'toast',
                message: ReinitialisationDonneesService::REFUS_MODE_DEMO,
                type: 'error',
            );

            return;
        }

        if ($this->confirmation !== self::MOT_DE_CONFIRMATION) {
            $this->addError('confirmation', ReinitialisationDonneesService::messageConfirmation());

            return;
        }

        $supprimees = app(ReinitialisationDonneesService::class)->executer();
        $total = array_sum($supprimees);

        $this->confirmation = '';
        $this->dispatch('close-modal', name: 'modal-reinitialisation');

        // Le nombre réel est annoncé (voir `ReinitialisationDonneesService::messageResultat()`).
        $this->dispatch(
            'toast',
            message: ReinitialisationDonneesService::messageResultat($total),
            type: 'success',
        );
    }

    public function render()
    {
        return view('livewire.parametres.reinitialisation-donnees');
    }
}
