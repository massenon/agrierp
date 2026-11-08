<?php

namespace Database\Seeders;

use App\Services\Elevage\ReleveTerrainService;
use Illuminate\Database\Seeder;

/**
 * Ticket RELEVES-1 — propositions « À valider » de l'onglet « Relevés de terrain ». Idempotent : la même méthode que la
 * migration (`ReleveTerrainService::semerParDefaut`), jamais d'écrasement d'une ligne existante.
 */
class ReleveTerrainSeeder extends Seeder
{
    public function run(): void
    {
        ReleveTerrainService::semerParDefaut();
    }
}
