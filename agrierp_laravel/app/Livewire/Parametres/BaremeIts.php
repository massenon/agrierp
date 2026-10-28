<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\IncomeTaxBracket;
use App\Services\PayrollCalculationService;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 14.39 (Sprint 14) — ÉDITION DU BARÈME IR-PTS / ITS.
 *
 * Le barème vit en base plutôt que dans le code : il change par loi de
 * finances, et la version réellement appliquée à un bulletin doit rester
 * visible et corrigeable par le comptable, sans redéploiement.
 *
 * ⚠️ LE RECALCUL EST AUTOMATIQUE, ET LIMITÉ AUX BULLETINS NON RÉGLÉS.
 * `GestionPaie` appelle `PayrollCalculationService` à chaque affichage : un
 * barème modifié se répercute donc immédiatement sur toute paie encore à
 * verser. En revanche, **un bulletin déjà réglé n'est jamais recalculé** — son
 * écriture comptable est passée, la trésorerie a bougé, et le salarié a été
 * payé. Le recalculer réécrirait l'histoire et ferait diverger le registre de
 * paie du grand livre, exactement le défaut corrigé au ticket 14.33 sur les
 * dépenses. Une correction rétroactive passe par une écriture au Journal.
 *
 * ⚠️ COHÉRENCE DES TRANCHES VÉRIFIÉE À L'ENREGISTREMENT. Un barème troué ou
 * chevauchant produit un impôt faux **sans lever la moindre erreur** : c'est
 * précisément le genre de défaut que ce projet a passé un sprint à traquer.
 * La première tranche part de zéro, chaque tranche reprend exactement où la
 * précédente s'arrête, et la dernière est ouverte.
 *
 * ⚠️ VERROU APRÈS PREMIÈRE ÉDITION — voir `CompanySetting::payrollSettingsEditableBy()`.
 * La première saisie est ouverte (elle entre le barème validé par le client) ;
 * toute modification ultérieure exige le rôle administrateur.
 */
#[Layout('layouts.app')]
class BaremeIts extends Component
{
    /** @var array<int, array{id: ?string, from: mixed, to: mixed, rate: mixed}> */
    public array $tranches = [];

    /** Salaire de simulation, pour voir immédiatement l'effet du barème. */
    public $brutSimule = 150_000;

    public function mount(): void
    {
        $this->chargerTranches();
    }

    private function chargerTranches(): void
    {
        $this->tranches = IncomeTaxBracket::orderBy('from_amount')->get()
            ->map(fn ($t) => [
                'id' => $t->id,
                'from' => (float) $t->from_amount,
                'to' => $t->to_amount !== null ? (float) $t->to_amount : null,
                'rate' => (float) $t->rate,
            ])
            ->values()
            ->all();

        if (empty($this->tranches)) {
            $this->tranches = [['id' => null, 'from' => 0, 'to' => null, 'rate' => 0]];
        }
    }

    public function getSettingsProperty(): CompanySetting
    {
        return CompanySetting::current();
    }

    /** Le paramétrage est-il modifiable par l'utilisateur courant ? */
    public function getEditableProperty(): bool
    {
        return $this->settings->payrollSettingsEditableBy(auth()->user());
    }

    /**
     * Effet du barème COURANT sur un salaire donné — mis à jour à chaque frappe.
     *
     * ⚠️ Calculé par le service de paie, jamais par une formule locale : le
     * comptable doit voir exactement ce que produira le bulletin, pas une
     * approximation d'écran.
     */
    public function getSimulationProperty(): array
    {
        return app(PayrollCalculationService::class)->calculer((float) ($this->brutSimule ?: 0));
    }

    public function ajouterTranche(): void
    {
        $this->authorize('view-parametres');

        $derniere = end($this->tranches);
        $depart = $derniere && $derniere['to'] !== null ? (float) $derniere['to'] : 0;

        $this->tranches[] = ['id' => null, 'from' => $depart, 'to' => null, 'rate' => 0];
    }

    public function retirerTranche(int $index): void
    {
        $this->authorize('view-parametres');

        unset($this->tranches[$index]);
        $this->tranches = array_values($this->tranches);
    }

    public function enregistrer(): void
    {
        // ⚠️ Autorisation sur l'action qui ÉCRIT : `tranches` est une propriété
        // publique, donc modifiable côté client (leçon des tickets 12.4, 14.27).
        $this->authorize('view-parametres');

        try {
            app(\App\Services\BaremeItsService::class)->remplacer($this->tranches, auth()->user());
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->addError('tranches', $e->validator->errors()->first('tranches'));

            return;
        }

        $this->chargerTranches();

        $this->dispatch('toast',
            message: 'Barème enregistré — les bulletins non encore réglés sont recalculés automatiquement. Toute modification ultérieure exigera le rôle administrateur.',
            type: 'success');
    }

    public function render()
    {
        return view('livewire.parametres.bareme-its', ['title' => 'Paramètres > Barème ITS']);
    }
}
