<?php

namespace App\Livewire\Ventes;

use App\Actions\CloturesCaisse\ValiderClotureCaisseAction;
use App\Models\CashClosure;
use App\Models\Sale;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\ValidationException;
use Livewire\Component;

/**
 * Sprint C — Clôture de caisse (C1).
 *
 * Affiche le récapitulatif des ventes du jour par mode de paiement,
 * permet de saisir le fond de caisse et le montant compté, calcule l'écart
 * en temps réel et valide la clôture via ValiderClotureCaisseAction.
 *
 * Droits : `manage-ventes` uniquement (caissier / gérant).
 */
class ClotureCaisse extends Component
{
    public string $closureDate;
    public string $fondDeCaisse  = '0';
    public string $montantCompte = '0';

    /** Récapitulatif chargé au montage et actualisé sur changement de date. */
    public float $ventesEspeces     = 0;
    public float $ventesMobileMoney = 0;
    public float $ventesVirement    = 0;

    public ?string $messageSucces = null;
    public ?string $messageErreur = null;

    /** Clôture déjà effectuée pour la date sélectionnée (depuis le web). */
    public bool $dejaValidee = false;

    public function mount(): void
    {
        abort_unless(Gate::allows('manage-ventes'), 403);
        $this->closureDate = now()->toDateString();
        $this->chargerVentes();
    }

    public function updatedClosureDate(): void
    {
        $this->chargerVentes();
        $this->messageSucces = null;
        $this->messageErreur = null;
    }

    /** Recalcule l'écart en temps réel sans écriture. */
    public function getEcartProperty(): float
    {
        $fond    = (float) str_replace(',', '.', $this->fondDeCaisse);
        $compte  = (float) str_replace(',', '.', $this->montantCompte);
        return round($compte - ($fond + $this->ventesEspeces + $this->ventesMobileMoney + $this->ventesVirement), 2);
    }

    public function valider(ValiderClotureCaisseAction $action): void
    {
        $this->authorize('manage-ventes');

        $this->messageSucces = null;
        $this->messageErreur = null;

        $fond   = (float) str_replace(',', '.', $this->fondDeCaisse);
        $compte = (float) str_replace(',', '.', $this->montantCompte);

        try {
            $cloture = $action->execute(
                closureDate:  $this->closureDate,
                fondDeCaisse: $fond,
                montantCompte: $compte,
                userId:       auth()->id(),
                deviceId:     null,  // web : device_id = null
            );

            $this->dejaValidee  = true;
            $this->messageSucces = 'Clôture de caisse validée avec succès.';
            $this->chargerVentes();
        } catch (ValidationException $e) {
            $this->messageErreur = collect($e->errors())->flatten()->first();
        } catch (\Throwable $e) {
            $this->messageErreur = 'Une erreur inattendue est survenue.';
        }
    }

    private function chargerVentes(): void
    {
        $q = Sale::whereDate('sold_at', $this->closureDate)
            ->where('status', '!=', 'annulee');

        $this->ventesEspeces     = (float) (clone $q)->where('payment_mode', 'especes')->sum('total');
        $this->ventesMobileMoney = (float) (clone $q)->where('payment_mode', 'mobile_money')->sum('total');
        $this->ventesVirement    = (float) (clone $q)->where('payment_mode', 'virement')->sum('total');

        $this->dejaValidee = CashClosure::where('closure_date', $this->closureDate)
            ->whereNull('device_id')
            ->whereIn('statut', ['en_cours', 'validée'])
            ->exists();
    }

    public function render()
    {
        $historique = CashClosure::with('createdByUser')
            ->whereNull('device_id')
            ->orderByDesc('closure_date')
            ->limit(10)
            ->get();

        return view('livewire.ventes.cloture-caisse', [
            'historique' => $historique,
        ]);
    }
}
