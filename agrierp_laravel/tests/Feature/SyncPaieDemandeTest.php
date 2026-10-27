<?php

namespace Tests\Feature;

use App\Livewire\RH\GestionPaie;
use App\Models\AccountingEntry;
use App\Models\AttendanceRecord;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Employee;
use App\Models\FiscalYear;
use App\Models\Payslip;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket RH-4 — LA PAIE SE VALIDE AU POSTE PAR UNE DEMANDE, RÉGLÉE ICI.
 *
 * Le poste n'envoie que (employé, période, instant) ; `ReglementPaieService` — le point de passage unique, partagé avec
 * `GestionPaie::validerReglement` — crée le bulletin, décrémente la trésorerie, passe l'écriture 661, trace l'audit.
 * Un renvoi est acquitté sans second bulletin ; un exercice clos ou un employé archivé refuse avec son motif ; les
 * colonnes RH des bulletins et le barème ne descendent qu'aux comptes RH.
 */
class SyncPaieDemandeTest extends TestCase
{
    use RefreshDatabase;

    private User $rh;

    private Employee $employe;

    private const DEMANDE = '99999999-9999-4999-8999-999999999999';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->rh = User::create([
            'name' => 'RH', 'username' => 'rh', 'email' => 'rh@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->rh->assignRole('admin');

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);
        foreach ([['531', 'Caisse', 5], ['431', 'Sécurité sociale (CNSS)', 4], ['661', 'Charges de personnel', 6],
            ['664', 'Charges sociales patronales', 6], ['4472', 'ITS', 4], ['4473', 'VPS', 4]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        \App\Models\CompanySetting::create([
            'company_name' => 'FERME ÉCOLE OLOUWACHEGOUN', 'vps_rate' => 4, 'cnss_employee_rate' => 3.6,
            'cnss_employer_pension_rate' => 6.4, 'cnss_employer_family_rate' => 9, 'cnss_employer_risk_rate' => 2,
        ]);
        (new \Database\Seeders\IncomeTaxBracketsSeeder())->run();
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 1_000_000, 'is_active' => true]);

        $this->employe = Employee::create([
            'first_name' => 'Kossi', 'last_name' => 'ADJOVI', 'position' => 'Ouvrier', 'base_salary' => 100_000,
            'hire_date' => now()->subYear()->format('Y-m-d'), 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function demande(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::DEMANDE, 'employee_id' => $this->employe->id, 'period_month' => now()->format('Y-m'),
            'requested_at' => now()->subMinutes(5)->toIso8601String(),
        ], $remplacements);
    }

    private function pousser(array $demandes, ?User $qui = null): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($qui ?? $this->rh, 'sanctum')->postJson('/api/sync/push', ['payslip_requests' => $demandes]);
    }

    public function test_une_demande_du_poste_regle_la_paie_comme_le_web(): void
    {
        // Une absence du mois, archivée : elle ne retient rien (règle du web).
        AttendanceRecord::create(['employee_id' => $this->employe->id, 'attendance_date' => now()->startOfMonth()->toDateString(), 'status' => 'absent', 'is_active' => false]);

        $this->pousser([$this->demande()])->assertOk()->assertJsonPath('payslip_requests.accepted.0', self::DEMANDE);

        $bulletin = Payslip::firstOrFail();
        $this->assertEquals(100_000, (float) $bulletin->gross_salary);
        $this->assertEquals(0, (float) $bulletin->absence_deduction);
        $this->assertEquals(3_600, (float) $bulletin->cnss_deduction);
        $this->assertEquals(92_760, (float) $bulletin->net_salary, 'même calcul que CyclePaieComptableTest (web)');
        $this->assertNotNull($bulletin->accounting_entry_id, 'l\'écriture 661 est passée');
        $this->assertEquals(1_000_000 - 92_760, (float) TreasuryAccount::first()->balance);
        $this->assertSame(1, AuditLog::where('action', 'payslip.paid')->count());
        $this->assertSame(1, AccountingEntry::count());
    }

    public function test_le_web_et_le_poste_passent_par_le_meme_service(): void
    {
        $this->actingAs($this->rh);
        Livewire::test(GestionPaie::class)->call('validerReglement', $this->employe->id);
        $web = Payslip::firstOrFail();

        // La demande du poste pour la même période est acquittée sans second bulletin ni seconde écriture.
        $this->pousser([$this->demande()])->assertOk()->assertJsonPath('payslip_requests.accepted.0', self::DEMANDE);

        $this->assertSame(1, Payslip::count());
        $this->assertSame(1, AccountingEntry::count());
        $this->assertSame($web->id, Payslip::first()->id);
    }

    public function test_une_demande_rejouee_ne_regle_pas_deux_fois(): void
    {
        $this->pousser([$this->demande()])->assertOk();
        $this->pousser([$this->demande()])->assertOk()->assertJsonPath('payslip_requests.accepted.0', self::DEMANDE);

        $this->assertSame(1, Payslip::count());
        $this->assertEquals(1_000_000 - 92_760, (float) TreasuryAccount::first()->balance, 'la trésorerie n\'est décrémentée qu\'une fois');
    }

    public function test_un_exercice_clos_refuse_avec_son_motif_et_n_ecrit_rien(): void
    {
        FiscalYear::query()->update(['status' => 'cloture']);

        $reponse = $this->pousser([$this->demande()])->assertOk();

        $this->assertSame([], $reponse->json('payslip_requests.accepted'));
        $this->assertStringStartsWith('Règlement refusé : ', $reponse->json('payslip_requests.rejected.0.reason'));
        $this->assertSame(0, Payslip::count());
        $this->assertEquals(1_000_000, (float) TreasuryAccount::first()->balance);
    }

    public function test_un_employe_archive_refuse(): void
    {
        $this->employe->update(['is_active' => false]);

        $reponse = $this->pousser([$this->demande()])->assertOk();

        $this->assertSame([], $reponse->json('payslip_requests.accepted'));
        $this->assertStringContainsString(\App\Services\ReglementPaieService::MESSAGE_EMPLOYE_ARCHIVE, $reponse->json('payslip_requests.rejected.0.reason'));
    }

    public function test_sans_le_role_rh_la_demande_est_refusee(): void
    {
        $caisse = User::create(['name' => 'Caisse', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $caisse->assignRole('caissier');

        $reponse = $this->pousser([$this->demande()], $caisse)->assertOk();

        $this->assertSame([], $reponse->json('payslip_requests.accepted'));
        $this->assertSame(0, Payslip::count());
    }

    /** Le tirage PAGINÉ (celui du poste), page par page, fusionné : seul lui filtre par permission. */
    private function tirage(User $compte): array
    {
        // Ce qui s'écrit pendant le tirage descend au suivant (recouvrement du curseur) : on avance l'horloge.
        \Carbon\Carbon::setTestNow(now()->addMinutes(3));
        $fusion = [];
        $jeton = null;
        $page = 1;
        do {
            $corps = $this->actingAs($compte, 'sanctum')->getJson('/api/sync/pull?'.http_build_query(array_filter([
                'page' => $page++, 'curseur_page' => $jeton,
            ], fn ($v) => $v !== null)))->assertOk()->json();
            foreach ($corps as $cle => $valeur) {
                if (is_array($valeur) && array_is_list($valeur)) {
                    $fusion[$cle] = array_merge($fusion[$cle] ?? [], $valeur);
                } elseif (! array_key_exists($cle, $fusion)) {
                    $fusion[$cle] = $valeur;
                }
            }
            $jeton = $corps['page_suivante'] ?? null;
        } while ($jeton !== null && $page < 50);

        return $fusion;
    }

    public function test_les_colonnes_rh_des_bulletins_et_le_bareme_ne_descendent_qu_aux_comptes_rh(): void
    {
        $this->pousser([$this->demande()])->assertOk();

        $rh = $this->tirage($this->rh);
        $bulletin = collect($rh['payslips'])->first();
        $this->assertSame($this->employe->id, $bulletin['employee_id']);
        $this->assertSame(now()->startOfMonth()->toDateString(), $bulletin['period_month']);
        $this->assertEquals(100_000, $bulletin['gross_salary']);
        $this->assertEquals(3_600, $bulletin['cnss_deduction']);
        $this->assertArrayHasKey('its_deduction', $bulletin);
        $this->assertArrayHasKey('charges_patronales', $bulletin);
        $this->assertNotEmpty($rh['income_tax_brackets']);
        $this->assertEquals(3.6, $rh['company_settings']['cnss_employee_rate']);

        // `view-rapports` sans `view-rh` (le comptable du seeder) : la vue réduite, rien de plus (protection S3).
        $compta = User::create(['name' => 'Compta', 'username' => 'compta', 'email' => 'compta@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $compta->assignRole('comptable');
        $this->assertFalse($compta->can('view-rh'), 'le comptable du seeder ne lit pas la RH');
        $reduit = $this->tirage($compta);
        $this->assertSame(['id', 'employee_name', 'net_salary', 'created_at'], array_keys(collect($reduit['payslips'])->first()));
        $this->assertArrayNotHasKey('income_tax_brackets', $reduit);
    }
}
