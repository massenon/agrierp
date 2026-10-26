<?php

namespace Tests\Feature;

use App\Models\ChartOfAccount;
use App\Models\CostCenter;
use App\Models\FiscalYear;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use Carbon\Carbon;
use Database\Seeders\RolesAndPermissionsSeeder;

/**
 * Ticket DEP1 à DEP3 (DEP6 : + 401 Fournisseurs, centre de coût obligatoire) — décor commun des tests de « Saisie des Dépenses » à plusieurs lignes : un administrateur, un
 * exercice 2026 ouvert, le plan (531 caisse, 521 banque, 601, 602, 605, 614, 628 en classe 6, 411 en classe 4),
 * une caisse de 500 000 F et une banque de 800 000 F, un centre de coût, un fournisseur.
 *
 * ⚠️ Toute date est FIGÉE : aucun test ne dépend du jour où la suite tourne. Les montants attendus sont calculés à la main.
 */
trait DecorDepenses
{
    protected User $admin;

    protected TreasuryAccount $caisse;

    protected TreasuryAccount $banque;

    protected CostCenter $filiere;

    protected Supplier $fournisseur;

    /** @var array<string, ChartOfAccount> */
    protected array $plan = [];

    protected function preparerDecorDepenses(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-06-20 09:00', 'Africa/Porto-Novo'));

        $this->seed(RolesAndPermissionsSeeder::class);
        $this->admin = User::create([
            'name' => 'Direction', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');
        $this->actingAs($this->admin);

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);

        foreach ([
            ['531', 'Caisse', 5], ['521', 'Banque', 5], ['411', 'Clients', 4], ['401', 'Fournisseurs', 4],
            ['601', 'Achats de marchandises', 6], ['602', 'Produits vétérinaires', 6], ['605', 'Énergie', 6],
            ['614', 'Transports', 6], ['628', 'Autres charges', 6],
        ] as [$code, $libelle, $classe]) {
            $this->plan[$code] = ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }

        $this->caisse = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 500_000, 'is_active' => true]);
        $this->banque = TreasuryAccount::create(['type' => 'banque', 'label' => 'Banque', 'account_code' => '521', 'balance' => 800_000, 'is_active' => true]);
        $this->filiere = CostCenter::create(['label' => 'Cuniculture', 'type' => 'filiere', 'is_active' => true]);
        $this->fournisseur = Supplier::create(['name' => 'Agri-Bénin', 'is_active' => true]);
    }

    /**
     * Le document d'une dépense à plusieurs lignes : l'exemple du PRD (60 000 F = 45 000 + 10 000 + 5 000).
     *
     * @param  array<string, mixed>  $remplacements
     * @return array<string, mixed>
     */
    protected function document(array $remplacements = []): array
    {
        return array_merge([
            'expense_date' => '2026-06-15',
            'treasury_account_id' => $this->caisse->id,
            'payment_mode' => 'caisse',
            // Ticket DEP6 (DEP-Q1) — le centre de coût est OBLIGATOIRE à la saisie.
            'cost_center_id' => $this->filiere->id,
            'lines' => [
                ['label' => 'Provende ponte', 'charge_account_id' => $this->plan['601']->id, 'amount' => 45_000],
                ['label' => 'Vermifuge', 'charge_account_id' => $this->plan['602']->id, 'amount' => 10_000],
                ['label' => 'Sac d\'aliment bis', 'charge_account_id' => $this->plan['601']->id, 'amount' => 5_000],
            ],
        ], $remplacements);
    }
}
