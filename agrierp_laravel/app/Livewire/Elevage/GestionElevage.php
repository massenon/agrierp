<?php

namespace App\Livewire\Elevage;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\ModuleConfig;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 3.2 (Sprint 3) — gestion-elevage.html → Livewire\Elevage\GestionElevage
 * Explicitement un "hub de cartes, PAS une page à onglets" (Document 05).
 *
 * Les 4 KPI interrogent réellement `livestock_lots`/`livestock_daily_entries`
 * (créées au ticket 3.1). Contrairement au Dashboard général (ticket 1.3),
 * ce ne sont PAS des bandeaux "en attente" — le mécanisme est entièrement
 * opérationnel dès maintenant, les valeurs sont juste à 0 tant qu'aucune
 * bande n'a été créée (ticket 3.3+), un état vide normal, pas un mécanisme
 * en construction.
 *
 * "Alertes Stock Aliment" reste en attente : aucune table ne suit encore
 * de stock d'aliment réel (`feed_types` est un catalogue de types/prix,
 * sans quantité en stock — le suivi de stock arrive au Sprint 6).
 *
 * La carte "Fiches Escargots" est visuellement grisée tant que
 * `modules_config.helico` est désactivé (état par défaut) — câblage réel
 * tenu depuis le ticket 3.9 (`ModuleConfig::isEnabled()`), plus une
 * simple promesse de docblock comme au ticket 3.2.
 */
#[Layout('layouts.app')]
class GestionElevage extends Component
{
    public function getHelicoEnabledProperty(): bool
    {
        return ModuleConfig::isEnabled('helico');
    }

    public function getEffectifTotalProperty(): int
    {
        return (int) LivestockLot::where('status', 'actif')->sum('current_quantity');
    }

    public function getBandesActivesProperty(): int
    {
        return LivestockLot::where('status', 'actif')->count();
    }

    public function getTauxMortaliteMoisProperty(): ?float
    {
        $lots = LivestockLot::where('status', 'actif')->pluck('id');

        if ($lots->isEmpty()) {
            return null;
        }

        $entries = LivestockDailyEntry::whereIn('lot_id', $lots)
            ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
            ->get();

        if ($entries->isEmpty()) {
            return null;
        }

        $totalMorts = $entries->sum('mort');
        $totalEffectifDepart = $entries->sum(fn ($e) => $e->previousEffectif());

        if ($totalEffectifDepart <= 0) {
            return null;
        }

        return round(($totalMorts / $totalEffectifDepart) * 100, 2);
    }

    public function render()
    {
        return view('livewire.elevage.gestion-elevage', ['title' => 'Gestion Élevage']);
    }
}
