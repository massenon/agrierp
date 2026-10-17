<?php

namespace App\Livewire\Elevage\Concerns;

use App\Models\LivestockDailyEntry;
use App\Models\VeterinaryRecord;
use Illuminate\Support\Collection;

/**
 * 🔴→✅ COLONNE « TRAITEMENTS & PROPHYLAXIE » DES TABLEAUX MENSUELS — fiches Lapins, Porcs, Pondeuses, Escargots.
 *
 * La colonne ne lisait que le produit de traitement de la fiche (`treatment_product_id`), jamais renseigné par
 * les écrans : les traitements validés depuis « Traitements & Prophylaxie » (registre vétérinaire, ticket 15.35)
 * n'y apparaissaient JAMAIS. Elle lit désormais les soins ACTIFS du registre de la bande à cette date, puis le
 * produit de la fiche, puis les symptômes ; « — » s'il n'y a rien.
 *
 * Exige du composant : `lotsDuTableauMensuel()` (identifiants des bandes affichées dans le tableau).
 */
trait AvecSoinsDuMois
{
    /** @return Collection<string, Collection<int, VeterinaryRecord>> soins actifs du mois, par date `Y-m-d` */
    public function getSoinsDuMoisProperty(): Collection
    {
        $lots = array_values(array_filter($this->lotsDuTableauMensuel()));

        if ($lots === []) {
            return collect();
        }

        return VeterinaryRecord::whereIn('lot_id', $lots)
            ->where('is_active', true)
            ->whereBetween('record_date', [now()->startOfMonth()->toDateString(), now()->endOfMonth()->toDateString()])
            ->orderBy('created_at')
            ->get()
            ->groupBy(fn (VeterinaryRecord $r) => $r->record_date->format('Y-m-d'));
    }

    public function traitementsDuJour(string $date, ?LivestockDailyEntry $entry): string
    {
        $libelles = ($this->soinsDuMois->get($date) ?? collect())
            ->map(fn (VeterinaryRecord $r) => trim($r->action_type.($r->product_used ? ' ('.$r->product_used.')' : '')))
            ->filter()
            ->unique()
            ->values();

        if ($entry?->treatmentProduct?->name) {
            $libelles->push($entry->treatmentProduct->name);
        }

        if ($libelles->isNotEmpty()) {
            return $libelles->unique()->implode(', ');
        }

        return $entry?->symptomes ?: '—';
    }
}
