<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
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
 */
class ReinitialisationDonnees extends Component
{
    public string $confirmation = '';

    public const MOT_DE_CONFIRMATION = 'REINITIALISER';

    public function getReglagesProperty(): ?CompanySetting
    {
        return CompanySetting::first();
    }

    public function getModeDemoActifProperty(): bool
    {
        return (bool) ($this->reglages?->demo_mode_enabled ?? false);
    }

    /**
     * Active ou désactive le mode démonstration.
     *
     * ⚠️ LA BASCULE ELLE-MÊME EST JOURNALISÉE : ouvrir l'accès à une opération
     * destructrice est un acte administratif qui doit laisser une trace, au
     * même titre que l'effacement.
     */
    public function basculerModeDemo(): void
    {
        $this->authorize('manage-parametres');

        $reglages = $this->reglages;

        if ($reglages === null) {
            return;
        }

        $actif = ! $reglages->demo_mode_enabled;
        $reglages->update(['demo_mode_enabled' => $actif]);

        AuditLog::record(
            $actif ? 'demo_mode.enabled' : 'demo_mode.disabled',
            'parametres',
        );

        unset($this->reglages, $this->modeDemoActif);

        $this->dispatch(
            'toast',
            message: $actif
                ? 'Mode démonstration activé — l\'onglet de réinitialisation est accessible.'
                : 'Mode démonstration désactivé.',
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
                message: 'Réinitialisation refusée : le mode démonstration n\'est pas activé.',
                type: 'error',
            );

            return;
        }

        if ($this->confirmation !== self::MOT_DE_CONFIRMATION) {
            $this->addError('confirmation', 'Saisissez '.self::MOT_DE_CONFIRMATION.' pour confirmer.');

            return;
        }

        $supprimees = app(ReinitialisationDonneesService::class)->executer();
        $total = array_sum($supprimees);

        $this->confirmation = '';
        $this->dispatch('close-modal', name: 'modal-reinitialisation');

        // Le nombre réel est annoncé : « données réinitialisées » sans chiffre
        // laisserait l'administrateur sans moyen de vérifier ce qui s'est passé.
        $this->dispatch(
            'toast',
            message: $total > 0
                ? "Réinitialisation effectuée — {$total} enregistrement(s) supprimé(s)."
                : 'Aucune donnée d\'activité à supprimer.',
            type: 'success',
        );
    }

    public function render()
    {
        return view('livewire.parametres.reinitialisation-donnees');
    }
}
