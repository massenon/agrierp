<?php

namespace Tests\Feature;

use App\Jobs\DailyElevageAlertsJob;
use App\Models\CompanySetting;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\VeterinaryCalendarEvent;
use App\Services\AlertesElevageService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * Ticket 15.49 — LA CLOCHE REÇOIT ENFIN LES ALERTES QUE LES ÉCRANS AFFICHAIENT.
 *
 * Et les écritures hors des valeurs autorisées par la colonne (`warning`, `error`, `backup.reminder`), qui
 * échouaient en MySQL strict mais passaient en silence sur SQLite, sont refusées par le modèle.
 */
class AlertesClocheTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $bande;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 06:05:00');
        $espece = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        $this->bande = LivestockLot::create([
            'code' => 'LAP-A', 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 100, 'current_quantity' => 100,
            'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function emettre(): int
    {
        return app(AlertesElevageService::class)->emettre();
    }

    public function test_une_gravite_ou_un_type_hors_de_la_colonne_est_refuse(): void
    {
        foreach ([['type' => 'system', 'severity' => 'warning'], ['type' => 'backup.reminder', 'severity' => 'info']] as $fautive) {
            try {
                Notification::create($fautive + ['title' => 'x', 'message' => 'x']);
                $this->fail('Écriture hors liste acceptée : '.json_encode($fautive));
            } catch (\InvalidArgumentException) {
            }
        }

        $this->assertSame(0, Notification::count());
        $this->assertSame('Élevage', (new Notification(['type' => 'sale_under_withdrawal']))->category);
    }

    public function test_un_produit_sous_son_seuil_est_signale_une_seule_fois_par_jour(): void
    {
        $categorie = new ProductCategory();
        $categorie->id = '11111111-1111-4111-8111-111111111111';
        $categorie->label = 'Aliments';
        $categorie->is_active = true;
        $categorie->save();
        foreach ([['ALI-1', 'Provende lapin', 4, 10], ['ALI-2', 'Provende porc', 50, 10]] as [$sku, $nom, $stock, $seuil]) {
            Product::create([
                'sku' => $sku, 'name' => $nom, 'category_id' => $categorie->id, 'unit' => 'sac',
                'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => $stock, 'alert_threshold' => $seuil,
                'is_active' => true,
            ]);
        }

        $this->emettre();
        $this->emettre();

        $alertes = Notification::where('type', 'stock_low')->get();
        $this->assertCount(1, $alertes, 'seule la provende lapin (4 ≤ 10) est sous son seuil, signalée une fois');
        $this->assertSame('moyen', $alertes->first()->severity);
        $this->assertStringContainsString('4 sac en stock pour un seuil d\'alerte de 10', $alertes->first()->message);
    }

    public function test_une_mortalite_anormale_est_signalee_et_une_bande_archivee_ne_l_est_pas(): void
    {
        // Veille 100, 6 morts le 13/10 : 6 % ≥ 5 %.
        LivestockDailyEntry::create([
            'lot_id' => $this->bande->id, 'entry_date' => '2026-10-13',
            'achat' => 0, 'ne' => 0, 'mort' => 6, 'vente' => 0, 'don' => 0, 'effectif_final' => 94,
        ]);
        $archivee = LivestockLot::create([
            'code' => 'LAP-ARCH', 'species_id' => $this->bande->species_id, 'stage' => 'croissance',
            'initial_quantity' => 10, 'current_quantity' => 2,
            'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => false,
        ]);
        LivestockDailyEntry::create([
            'lot_id' => $archivee->id, 'entry_date' => '2026-10-13',
            'achat' => 0, 'ne' => 0, 'mort' => 8, 'vente' => 0, 'don' => 0, 'effectif_final' => 2,
        ]);

        $this->emettre();

        $alertes = Notification::where('type', 'high_mortality')->get();
        $this->assertCount(1, $alertes);
        $this->assertSame('Mortalité anormale — Bande LAP-A', $alertes->first()->title);
        $this->assertStringContainsString('6 % de mortalité le 13/10/2026', $alertes->first()->message);
    }

    public function test_les_soins_planifies_a_venir_et_en_retard_sont_rappeles(): void
    {
        foreach ([
            ['Vaccin RHD', '2026-10-15', 'planned'],     // demain : à venir
            ['Déparasitage', '2026-10-10', 'planned'],   // dépassé : en retard
            ['Vitamines', '2026-10-25', 'planned'],      // hors fenêtre de 3 jours
            ['Vaccin myxo', '2026-10-15', 'done'],       // déjà fait
        ] as [$tache, $date, $statut]) {
            VeterinaryCalendarEvent::create(['lot_id' => $this->bande->id, 'task_type' => $tache, 'scheduled_date' => $date, 'status' => $statut]);
        }

        $this->emettre();

        $titres = Notification::where('type', 'prophylaxis_due')->orderBy('title')->pluck('severity', 'title')->all();
        $this->assertSame([
            'Soin en retard — Déparasitage' => 'critique',
            'Soin à venir — Vaccin RHD' => 'moyen',
        ], $titres);
    }

    /** R-SOINS-01 — le délai vient du réglage de l'exploitant, plus d'une constante. */
    public function test_le_delai_de_rappel_regle_par_l_exploitant_est_applique(): void
    {
        foreach ([['Vaccin RHD', '2026-10-15'], ['Vitamines', '2026-10-25'], ['Pesée', '2026-10-14']] as [$tache, $date]) {
            VeterinaryCalendarEvent::create(['lot_id' => $this->bande->id, 'task_type' => $tache, 'scheduled_date' => $date, 'status' => 'planned']);
        }

        CompanySetting::create(['company_name' => 'Ferme', 'rappel_soins_jours' => 0]);
        $this->assertSame(['Pesée'], app(AlertesElevageService::class)->soinsAVenir()->pluck('task_type')->all(),
            '0 jour : le jour même seulement');

        CompanySetting::query()->update(['rappel_soins_jours' => 11]);
        $this->assertSame(['Pesée', 'Vaccin RHD', 'Vitamines'],
            app(AlertesElevageService::class)->soinsAVenir()->pluck('task_type')->all(), '11 jours : jusqu\'au 25/10');
    }

    public function test_sans_reglage_le_delai_par_defaut_est_de_trois_jours(): void
    {
        $this->assertSame(3, app(AlertesElevageService::class)->joursRappelSoins());
    }

    public function test_le_delai_se_regle_dans_parametres_elevage_entre_0_et_30_jours(): void
    {
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $compte = fn (string $role) => tap(\App\Models\User::create([
            'name' => $role, 'username' => $role, 'email' => $role.'@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]), fn ($u) => $u->assignRole($role));
        CompanySetting::create(['company_name' => 'Ferme']);

        $this->actingAs($compte('animalier'));
        \Livewire\Livewire::test(\App\Livewire\Elevage\ParametresElevage::class)
            ->assertSet('rappelSoinsJours', 3)
            ->set('rappelSoinsJours', 31)->call('saveRappelSoins')->assertHasErrors('rappelSoinsJours')
            ->set('rappelSoinsJours', 7)->call('saveRappelSoins')->assertHasNoErrors();
        $this->assertSame(7, CompanySetting::first()->rappel_soins_jours);

        $this->actingAs($compte('caissier'));
        \Livewire\Livewire::test(\App\Livewire\Elevage\ParametresElevage::class)
            ->set('rappelSoinsJours', 1)->call('saveRappelSoins')->assertForbidden();
        $this->assertSame(7, CompanySetting::first()->rappel_soins_jours);
    }

    public function test_un_echec_de_reproduction_est_signale_une_seule_fois(): void
    {
        LivestockReproductionEvent::create([
            'lot_id' => $this->bande->id, 'mother_ref' => 'L-12', 'saillie_date' => '2026-09-20',
            'palpation_date' => '2026-10-02', 'status' => 'echec',
        ]);

        $this->emettre();
        Carbon::setTestNow('2026-10-15 06:05:00');
        $this->emettre();

        $alertes = Notification::where('type', 'reproduction_echec')->get();
        $this->assertCount(1, $alertes);
        $this->assertSame('Échec de reproduction — L-12', $alertes->first()->title);
        $this->assertSame('Élevage', $alertes->first()->category);
    }

    public function test_la_tache_quotidienne_emet_les_alertes_et_est_planifiee(): void
    {
        VeterinaryCalendarEvent::create(['lot_id' => $this->bande->id, 'task_type' => 'Vaccin RHD', 'scheduled_date' => '2026-10-14', 'status' => 'planned']);

        (new DailyElevageAlertsJob())->handle(app(AlertesElevageService::class));

        $this->assertSame(1, Notification::where('type', 'prophylaxis_due')->count());
        $this->assertTrue(
            collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())
                ->contains(fn ($e) => str_contains((string) $e->description, 'DailyElevageAlertsJob')),
            'la tâche doit être planifiée',
        );
    }
}
