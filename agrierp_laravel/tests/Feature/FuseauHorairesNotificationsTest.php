<?php

namespace Tests\Feature;

use App\Actions\RaiseFeedAutonomyAlertAction;
use App\Livewire\Dashboard\Index as DashboardIndex;
use App\Models\AuditLog;
use App\Models\Notification;
use App\Models\Product;
use App\Models\ProductCategory;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket 15.20a — FUSEAU HORAIRE DES `created_at` ÉCRITS PAR LA BASE.
 *
 * `.env` fixe `APP_TIMEZONE=Africa/Porto-Novo` (UTC+1). `notifications.created_at` et
 * `audit_logs.created_at` n'étaient pas écrits par Eloquent (`$timestamps = false`) mais par la base
 * (`useCurrent()` = CURRENT_TIMESTAMP, en UTC). Toute comparaison `whereDate('created_at', now())`
 * confrontait donc deux dates de fuseaux différents : entre 00:00 et 01:00 heure du Bénin, « aujourd'hui »
 * côté application était déjà « demain » par rapport à la ligne tout juste écrite — la déduplication
 * de `RaiseFeedAutonomyAlertAction` ne reconnaissait plus sa propre alerte et en empilait une par
 * enregistrement. Invisible 23 h sur 24.
 *
 * Ces tests figent l'instant avec `Carbon::setTestNow` : 23:30 UTC = 00:30 le lendemain au Bénin.
 */
class FuseauHorairesNotificationsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $this->assertSame('Africa/Porto-Novo', config('app.timezone'), 'Ces tests supposent la configuration réelle du projet.');

        // 2026-10-09 23:30 UTC == 2026-10-10 00:30 à Porto-Novo.
        Carbon::setTestNow(Carbon::parse('2026-10-09 23:30:00', 'UTC'));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function aliment(): Product
    {
        DB::table('feed_types')->insert([
            'id' => (string) Str::uuid(), 'name' => 'Aliment lapins', 'standard_bag_weight_kg' => 25,
            'price_per_kg' => 290, 'is_active' => true, 'created_at' => now(), 'updated_at' => now(),
        ]);
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);

        return Product::create([
            'sku' => 'ALI-004', 'name' => 'Aliment lapins reproducteur 25kg', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 7_250, 'price_max' => 8_250,
            'tva_rate' => 0, 'stock_qty' => 4, 'alert_threshold' => 8, 'is_active' => true,
        ]);
    }

    public function test_l_instant_de_test_est_bien_apres_minuit_au_benin(): void
    {
        $this->assertSame('2026-10-10 00:30', now()->format('Y-m-d H:i'));
        $this->assertSame('2026-10-09', Carbon::now('UTC')->toDateString());
    }

    public function test_la_deduplication_de_l_alerte_tient_entre_minuit_et_une_heure_au_benin(): void
    {
        $action = app(RaiseFeedAutonomyAlertAction::class);
        $aliment = $this->aliment();

        $action->execute($aliment, 40);
        $action->execute($aliment, 40);
        $action->execute($aliment, 40);

        $this->assertSame(1, Notification::where('type', 'stock_low')->count(), 'Une seule alerte par produit et par jour.');
    }

    public function test_une_notification_est_horodatee_dans_le_fuseau_de_l_application(): void
    {
        $n = Notification::create([
            'target_role' => 'animalier', 'type' => 'system', 'severity' => 'info',
            'title' => 'T', 'message' => 'M', 'is_read' => false,
        ]);

        $this->assertSame('2026-10-10 00:30', $n->fresh()->created_at->format('Y-m-d H:i'));
    }

    public function test_une_ligne_d_audit_est_horodatee_dans_le_fuseau_de_l_application(): void
    {
        $a = AuditLog::record('test.action', 'comptabilite');

        $this->assertSame('2026-10-10 00:30', $a->fresh()->created_at->format('Y-m-d H:i'));
    }

    public function test_les_activites_du_jour_du_tableau_de_bord_voient_l_action_de_00h30(): void
    {
        AuditLog::record('test.action', 'comptabilite');

        $this->assertCount(1, (new DashboardIndex)->getActivitesJourProperty(), 'Une action de 00:30 est « du jour ».');
    }

    /** Même requête que `DailyProphylaxyReminderJob::issueNotificationIfNotAlreadySent`. */
    public function test_la_deduplication_du_rappel_de_prophylaxie_tient_a_00h30(): void
    {
        Notification::create([
            'target_role' => 'animalier', 'type' => 'prophylaxis_due', 'severity' => 'info',
            'title' => 'Traitement dû aujourd\'hui — L1', 'message' => 'Vaccin X', 'is_read' => false,
        ]);

        $dejaEnvoye = Notification::where('type', 'prophylaxis_due')
            ->where('title', 'Traitement dû aujourd\'hui — L1')
            ->whereDate('created_at', today())
            ->exists();

        $this->assertTrue($dejaEnvoye);
    }

    public function test_une_date_explicite_n_est_pas_ecrasee(): void
    {
        $n = Notification::create([
            'target_role' => 'animalier', 'type' => 'system', 'severity' => 'info',
            'title' => 'T', 'message' => 'M', 'is_read' => false,
        ]);
        $n->created_at = Carbon::parse('2026-01-05 08:00:00');
        $n->save();

        $this->assertSame('2026-01-05 08:00', $n->fresh()->created_at->format('Y-m-d H:i'));
    }
}
