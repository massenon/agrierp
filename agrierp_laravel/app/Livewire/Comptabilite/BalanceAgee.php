<?php

namespace App\Livewire\Comptabilite;

use App\Services\AgedBalanceService;
use Illuminate\Support\Carbon;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.66 (Sprint 14) — BALANCE ÂGÉE (clients et fournisseurs).
 *
 * ⚠️⚠️ **ÉCRAN HORS MAQUETTE, ASSUMÉ ET DIT.** `prototype_html` ne porte
 * aucune balance âgée : le mot « âgée » n'y apparaît que sur des écrans de
 * STOCK (ancienneté des lots), jamais sur les créances. Cet écran répond à un
 * besoin exprimé par le client comptable — il ne convertit pas une maquette.
 *
 * ⚠️ **AUCUN ÉCRAN DU PROTOTYPE N'EST MODIFIÉ.** La Balance générale reste
 * intacte : y greffer un onglet aurait déplacé des éléments existants, ce que
 * la règle de conformité interdit. D'où un écran séparé.
 *
 * ⚠️ **LECTURE SEULE.** Aucune méthode mutante, donc aucun `authorize()` à
 * l'intérieur : la route porte `can:view-comptabilite`. Une balance âgée ne
 * modifie rien — elle sert à décider qui relancer.
 *
 * Le calcul vit dans `AgedBalanceService`, avec ses deux règles : l'âge se
 * compte depuis l'ÉCHÉANCE (pas l'émission), et c'est le RESTE DÛ qui est
 * ventilé (pas le montant initial).
 */
#[Layout('layouts.app')]
class BalanceAgee extends Component
{
    /** Date d'arrêté — une balance âgée se lit toujours à une date donnée. */
    #[Url]
    public string $arrete = '';

    /** `creances` ou `dettes`. */
    #[Url]
    public string $volet = 'creances';

    public function mount(): void
    {
        if ($this->arrete === '') {
            $this->arrete = now()->toDateString();
        }
    }

    public function getDonneesProperty(): array
    {
        $service = app(AgedBalanceService::class);
        $date = Carbon::parse($this->arrete);

        return $this->volet === 'dettes'
            ? $service->dettes($date)
            : $service->creances($date);
    }

    /** @return array<int, string> */
    public function getTranchesProperty(): array
    {
        return array_keys(AgedBalanceService::TRANCHES);
    }

    public function render()
    {
        return view('livewire.comptabilite.balance-agee', [
            'title' => 'Comptabilité > Balance Âgée',
        ]);
    }
}
