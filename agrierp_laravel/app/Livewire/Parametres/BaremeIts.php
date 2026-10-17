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

        if (! $this->editable) {
            $this->addError('tranches', "Le barème a déjà été arrêté le "
                .$this->settings->payroll_settings_edited_at?->format('d/m/Y à H:i')
                .". Seul un administrateur peut le modifier.");

            return;
        }

        $erreur = $this->verifierCoherence();

        if ($erreur !== null) {
            $this->addError('tranches', $erreur);

            return;
        }

        IncomeTaxBracket::query()->delete();

        foreach ($this->tranches as $tranche) {
            IncomeTaxBracket::create([
                'from_amount' => (float) $tranche['from'],
                'to_amount' => $tranche['to'] === null || $tranche['to'] === '' ? null : (float) $tranche['to'],
                'rate' => (float) $tranche['rate'],
                'is_active' => true,
            ]);
        }

        $this->settings->markPayrollSettingsEdited(auth()->user());

        AuditLog::record('payroll.brackets_updated', 'parametres');
        $this->chargerTranches();

        $this->dispatch('toast',
            message: 'Barème enregistré — les bulletins non encore réglés sont recalculés automatiquement. Toute modification ultérieure exigera le rôle administrateur.',
            type: 'success');
    }

    /**
     * Un barème troué ou chevauchant produit un impôt faux SANS lever
     * d'erreur : chaque contrôle ci-dessous correspond à une manière réelle de
     * se tromper.
     */
    private function verifierCoherence(): ?string
    {
        if (empty($this->tranches)) {
            return 'Le barème doit comporter au moins une tranche.';
        }

        $tranches = collect($this->tranches)
            ->map(fn ($t) => [
                'from' => (float) $t['from'],
                'to' => $t['to'] === null || $t['to'] === '' ? null : (float) $t['to'],
                'rate' => (float) $t['rate'],
            ])
            ->sortBy('from')
            ->values();

        if ($tranches->first()['from'] != 0.0) {
            return 'La première tranche doit partir de 0 : sans elle, les revenus les plus bas ne seraient couverts par aucune tranche.';
        }

        foreach ($tranches as $i => $tranche) {
            if ($tranche['rate'] < 0 || $tranche['rate'] > 100) {
                return 'Un taux doit être compris entre 0 et 100 %.';
            }

            $derniere = $i === $tranches->count() - 1;

            if ($derniere) {
                if ($tranche['to'] !== null) {
                    return 'La dernière tranche doit être ouverte (sans plafond) : sinon les revenus au-delà ne seraient pas imposés du tout.';
                }

                continue;
            }

            if ($tranche['to'] === null) {
                return 'Seule la dernière tranche peut être sans plafond.';
            }

            if ($tranche['to'] <= $tranche['from']) {
                return 'Le plafond d\'une tranche doit être supérieur à son plancher.';
            }

            // ⚠️ Continuité stricte : un trou laisse une portion de revenu non
            // imposée, un chevauchement la taxe deux fois. Ni l'un ni l'autre
            // ne lèverait d'erreur au calcul.
            if ((float) $tranches[$i + 1]['from'] !== (float) $tranche['to']) {
                return 'Les tranches doivent se suivre sans trou ni chevauchement : la tranche suivante doit commencer exactement à '
                    .number_format($tranche['to'], 0, ',', ' ').' FCFA.';
            }
        }

        return null;
    }

    public function render()
    {
        return view('livewire.parametres.bareme-its', ['title' => 'Paramètres > Barème ITS']);
    }
}
