<?php

namespace Database\Seeders;

use App\Models\FiscalYear;
use Illuminate\Database\Seeder;

/**
 * Ticket 13.4 (Sprint 13, stratégie de bascule papier→numérique) — GAP
 * CRITIQUE TROUVÉ EN RÉDIGEANT LE DOCUMENT DE MIGRATION : aucun seeder,
 * aucune route, aucun bouton n'existait nulle part dans ce projet pour
 * créer le tout premier `FiscalYear`. `FiscalYear` n'était créée que par
 * `ClotureExercice::confirmCloture()` (ticket 10.6), qui suppose qu'un
 * exercice précédent existe déjà pour en générer un nouveau — un
 * `php artisan migrate:fresh --seed` frais n'aurait donc jamais eu
 * d'exercice ouvert, et `AccountingEntryService::record()` aurait rejeté
 * (`NoOpenFiscalYearException`) absolument toute écriture comptable,
 * y compris les écritures de solde d'ouverture exigées le jour même de
 * la bascule (Document 08 §13). Comblé ici — l'exercice en cours est
 * créé au statut `ouvert`, prêt à recevoir les écritures d'ouverture
 * réelles saisies manuellement (Journal Comptable, `recordManual()`,
 * déjà prêt depuis le ticket 10.2) le jour de la bascule officielle.
 */
class FiscalYearSeeder extends Seeder
{
    public function run(): void
    {
        $year = (int) now()->format('Y');

        FiscalYear::firstOrCreate(
            ['year' => $year],
            [
                'start_date' => "{$year}-01-01",
                'end_date' => "{$year}-12-31",
                'status' => 'ouvert',
            ]
        );
    }
}
