<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalClosureRequest;
use App\Models\FiscalYear;
use App\Models\PeriodicClosure;
use App\Models\User;
use App\Services\AccountingEntryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket CP-4 — LA CLÔTURE D'EXERCICE SE DEMANDE AU POSTE (décision du client : « oui, le poste doit le faire »).
 *
 * Le poste n'écrit que la DEMANDE (`fiscal_closure_requests`) ; `ClotureExerciceService` — le point de passage du web
 * (`ClotureExercice`, `AssistantDemarrage`) — la rejoue : mêmes gardes, mêmes écritures, mêmes motifs. Chiffres calculés à la main.
 */
class SyncClotureExerciceTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $comptable;

    private User $caissier;

    private ChartOfAccount $caisse;

    private ChartOfAccount $capital;

    private ChartOfAccount $vente;

    protected function setUp(): void
    {
        parent::setUp();
        // La clôture de 2026 n'est admise qu'après son échéance (EX4/Q2) : on se place en février 2027.
        \Carbon\Carbon::setTestNow('2027-02-15 10:00:00');
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = $this->compte('admin');
        $this->comptable = $this->compte('comptable');
        $this->caissier = $this->compte('caissier');

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        $compte = fn ($code, $libelle, $classe) => ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true]);
        $compte('131', 'Résultat - Bénéfice', 1);
        $compte('139', 'Résultat - Perte', 1);
        $this->capital = $compte('101', 'Capital', 1);
        $this->caisse = $compte('531', 'Caisse', 5);
        $this->vente = $compte('701', 'Ventes', 7);

        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->capital->id, 1_000_000, '2026-03-01');
    }

    protected function tearDown(): void
    {
        \Carbon\Carbon::setTestNow();
        parent::tearDown();
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function demande(string $kind, array $payload = [], ?string $id = null): array
    {
        return ['id' => $id ?? (string) Str::uuid(), 'kind' => $kind, 'payload' => $payload];
    }

    private function envoyer(User $u, array ...$demandes)
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test', 'fiscal_closure_requests' => $demandes]);
    }

    private function vendre(float $montant): void
    {
        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->vente->id, $montant, '2026-06-10');
    }

    public function test_la_cloture_complete_se_joue_etape_par_etape_comme_au_web(): void
    {
        $this->vendre(300_000);

        // Étape 3 d'emblée : refusée avec le motif du web (étape 1 d'abord).
        $r = $this->envoyer($this->comptable, $this->demande('cloturer_exercice', ['year' => 2026]))->assertOk();
        $this->assertStringContainsString('Étape 1 non confirmée', $r->json('fiscal_closure_requests.rejected.0.reason'));
        $this->assertSame('ouvert', FiscalYear::where('year', 2026)->value('status'));

        $this->envoyer($this->comptable, $this->demande('confirmer_etape1', ['year' => 2026]))->assertOk()
            ->assertJsonCount(1, 'fiscal_closure_requests.accepted');
        $this->assertNotNull(FiscalYear::where('year', 2026)->value('step1_confirmed_at'));

        $r = $this->envoyer($this->comptable, $this->demande('cloturer_exercice', ['year' => 2026]))->assertOk();
        $this->assertStringContainsString('Étape 2 non faite : 1 compte(s)', $r->json('fiscal_closure_requests.rejected.0.reason'));

        $this->envoyer($this->comptable, $this->demande('solder_comptes_gestion', ['year' => 2026]))->assertOk()
            ->assertJsonCount(1, 'fiscal_closure_requests.accepted');
        $this->assertSame(1, AccountingEntry::where('source_type', 'closing')->count());

        $this->envoyer($this->comptable, $this->demande('cloturer_exercice', ['year' => 2026]))->assertOk()
            ->assertJsonCount(1, 'fiscal_closure_requests.accepted');

        $this->assertSame('cloture', FiscalYear::where('year', 2026)->value('status'));
        $this->assertSame('ouvert', FiscalYear::where('year', 2027)->value('status'));
        $this->assertSame(1, AccountingEntry::where('source_type', 'ran')->count());
        $this->assertSame(0, AccountingEntry::where('fiscal_year_id', FiscalYear::where('year', 2026)->value('id'))->where('is_locked', false)->count());
    }

    public function test_solder_sans_rien_a_solder_est_un_succes_pas_un_refus(): void
    {
        $this->envoyer($this->comptable, $this->demande('solder_comptes_gestion', ['year' => 2026]))->assertOk()
            ->assertJsonCount(1, 'fiscal_closure_requests.accepted')
            ->assertJsonCount(0, 'fiscal_closure_requests.rejected');
        $this->assertSame(0, AccountingEntry::where('source_type', 'closing')->count());
    }

    public function test_une_demande_rejouee_est_acquittee_sans_etre_rejouee_meme_apres_une_reouverture(): void
    {
        $etape1 = $this->demande('confirmer_etape1', ['year' => 2026]);
        $cloture = $this->demande('cloturer_exercice', ['year' => 2026]);
        $this->envoyer($this->comptable, $etape1)->assertOk();
        $this->envoyer($this->comptable, $cloture)->assertOk()->assertJsonCount(1, 'fiscal_closure_requests.accepted');

        // L'administrateur rouvre l'exercice entre-temps ; l'acquittement s'était perdu, le poste renvoie la clôture.
        $this->envoyer($this->admin, $this->demande('rouvrir_exercice', ['year' => 2026]))->assertOk()
            ->assertJsonCount(1, 'fiscal_closure_requests.accepted');
        $this->assertSame('ouvert', FiscalYear::where('year', 2026)->value('status'));

        $this->envoyer($this->comptable, $cloture)->assertOk()
            ->assertJsonPath('fiscal_closure_requests.accepted.0', $cloture['id']);

        $this->assertSame('ouvert', FiscalYear::where('year', 2026)->value('status'), 'la demande renvoyée ne reclôture pas');
        $this->assertSame(1, FiscalClosureRequest::where('id', $cloture['id'])->count());
    }

    public function test_une_demande_refusee_n_est_pas_consignee_et_n_ecrit_rien(): void
    {
        $d = $this->demande('cloturer_exercice', ['year' => 2026]);
        $this->envoyer($this->comptable, $d)->assertOk()->assertJsonCount(1, 'fiscal_closure_requests.rejected');

        $this->assertSame(0, FiscalClosureRequest::count());
        $this->assertSame(0, AccountingEntry::where('source_type', 'ran')->count());
        $this->assertNull(FiscalYear::where('year', 2027)->first());
    }

    public function test_la_cloture_avant_l_echeance_est_refusee_avec_le_motif_du_web(): void
    {
        \Carbon\Carbon::setTestNow('2026-11-15 10:00:00');
        $this->envoyer($this->comptable, $this->demande('confirmer_etape1', ['year' => 2026]))->assertOk();

        $r = $this->envoyer($this->comptable, $this->demande('cloturer_exercice', ['year' => 2026]))->assertOk();

        $this->assertStringContainsString("ne peut être clôturé qu'après son échéance du 31/12/2026", $r->json('fiscal_closure_requests.rejected.0.reason'));
    }

    public function test_l_exercice_precedent_ouvert_bloque_la_cloture(): void
    {
        FiscalYear::create(['year' => 2027, 'start_date' => '2027-01-01', 'end_date' => '2027-12-31', 'status' => 'ouvert']);
        \Carbon\Carbon::setTestNow('2028-02-15 10:00:00');

        $r = $this->envoyer($this->comptable, $this->demande('cloturer_exercice', ['year' => 2027]))->assertOk();

        $this->assertStringContainsString("L'exercice 2026 est encore ouvert", $r->json('fiscal_closure_requests.rejected.0.reason'));
    }

    public function test_un_exercice_deja_clos_ou_inexistant_est_refuse(): void
    {
        FiscalYear::where('year', 2026)->update(['status' => 'cloture']);

        $r = $this->envoyer($this->comptable, $this->demande('cloturer_exercice', ['year' => 2026]))->assertOk();
        $this->assertStringContainsString('déjà clos', $r->json('fiscal_closure_requests.rejected.0.reason'));

        $r = $this->envoyer($this->comptable, $this->demande('cloturer_exercice', ['year' => 2019]))->assertOk();
        $this->assertStringContainsString("Aucun exercice 2019 n'existe", $r->json('fiscal_closure_requests.rejected.0.reason'));
    }

    public function test_un_a_nouveau_desequilibre_est_refuse_avec_les_montants(): void
    {
        // Compte hors classes 1 à 7 (classe 8) : l'étape 2 ne le solde pas, l'à-nouveau serait déséquilibré.
        $hao = ChartOfAccount::create(['code' => '811', 'label' => 'Valeurs comptables des cessions', 'class' => 8, 'is_active' => true]);
        app(AccountingEntryService::class)->recordManual($hao->id, $this->capital->id, 50_000, '2026-04-01');
        $this->envoyer($this->comptable, $this->demande('confirmer_etape1', ['year' => 2026]))->assertOk();

        $r = $this->envoyer($this->comptable, $this->demande('cloturer_exercice', ['year' => 2026]))->assertOk();

        $this->assertStringContainsString("L'à-nouveau de l'exercice 2027 serait déséquilibré", $r->json('fiscal_closure_requests.rejected.0.reason'));
    }

    public function test_la_cloture_d_un_mois_verrouille_puis_se_deverrouille_par_l_administrateur(): void
    {
        $d = $this->demande('cloturer_periode', ['period' => '2026-03']);
        $this->envoyer($this->comptable, $d)->assertOk()->assertJsonCount(1, 'fiscal_closure_requests.accepted');
        $this->assertTrue(PeriodicClosure::isDateLocked('2026-03-15'));

        // Un autre envoi pour le même mois : refusé, « déjà clôturé ».
        $r = $this->envoyer($this->comptable, $this->demande('cloturer_periode', ['period' => '2026-03']))->assertOk();
        $this->assertSame('Ce mois est déjà clôturé.', $r->json('fiscal_closure_requests.rejected.0.reason'));

        $r = $this->envoyer($this->comptable, $this->demande('decloturer_periode', ['period' => '2026-03']))->assertOk();
        $this->assertStringContainsString("réservée à l'Administrateur", $r->json('fiscal_closure_requests.rejected.0.reason'));
        $this->assertTrue(PeriodicClosure::isDateLocked('2026-03-15'));

        $closure = PeriodicClosure::where('period', '2026-03')->firstOrFail();
        $this->envoyer($this->admin, $this->demande('decloturer_periode', ['closure_id' => $closure->id]))->assertOk()
            ->assertJsonCount(1, 'fiscal_closure_requests.accepted');
        $this->assertFalse(PeriodicClosure::isDateLocked('2026-03-15'));

        $r = $this->envoyer($this->admin, $this->demande('decloturer_periode', ['closure_id' => $closure->id]))->assertOk();
        $this->assertSame("Ce mois n'est pas clôturé.", $r->json('fiscal_closure_requests.rejected.0.reason'));
    }

    public function test_un_mois_deseequilibre_ne_se_cloture_pas(): void
    {
        // Ligne seule (écriture déséquilibrée posée hors service) : la balance du mois porte un écart.
        $e = AccountingEntry::first();
        \App\Models\AccountingEntryLine::where('entry_id', $e->id)->where('debit', '>', 0)->update(['debit' => 1_000_500]);

        $r = $this->envoyer($this->comptable, $this->demande('cloturer_periode', ['period' => '2026-03']))->assertOk();

        $this->assertStringContainsString('Balance déséquilibrée (écart de', $r->json('fiscal_closure_requests.rejected.0.reason'));
        $this->assertSame(0, PeriodicClosure::count());
    }

    public function test_un_mois_illisible_est_refuse(): void
    {
        $r = $this->envoyer($this->comptable, $this->demande('cloturer_periode', ['period' => 'mars']))->assertOk();
        $this->assertStringContainsString('illisible', $r->json('fiscal_closure_requests.rejected.0.reason'));
    }

    public function test_la_reouverture_est_reservee_a_l_administrateur_et_contrepasse_le_report(): void
    {
        $this->envoyer($this->comptable, $this->demande('confirmer_etape1', ['year' => 2026]))->assertOk();
        $this->envoyer($this->comptable, $this->demande('cloturer_exercice', ['year' => 2026]))->assertOk();

        $r = $this->envoyer($this->comptable, $this->demande('rouvrir_exercice', ['year' => 2026]))->assertOk();
        $this->assertStringContainsString("réservée à l'Administrateur", $r->json('fiscal_closure_requests.rejected.0.reason'));
        $this->assertSame('cloture', FiscalYear::where('year', 2026)->value('status'));

        $this->envoyer($this->admin, $this->demande('rouvrir_exercice', ['year' => 2026]))->assertOk()
            ->assertJsonCount(1, 'fiscal_closure_requests.accepted');

        $this->assertSame('ouvert', FiscalYear::where('year', 2026)->value('status'));
        $this->assertSame(1, AccountingEntry::where('source_type', 'ran_reversal')->count());
    }

    public function test_rouvrir_un_exercice_non_clos_est_refuse(): void
    {
        $r = $this->envoyer($this->admin, $this->demande('rouvrir_exercice', ['year' => 2026]))->assertOk();
        $this->assertSame("L'exercice 2026 n'est pas clôturé.", $r->json('fiscal_closure_requests.rejected.0.reason'));
    }

    public function test_l_exercice_suivant_s_ouvre_des_le_premier_decembre_pas_avant(): void
    {
        \Carbon\Carbon::setTestNow('2026-11-20 10:00:00');
        $r = $this->envoyer($this->comptable, $this->demande('ouvrir_exercice_suivant', ['year' => 2027]))->assertOk();
        $this->assertStringContainsString("ne peut s'ouvrir qu'à partir du 01/12/2026", $r->json('fiscal_closure_requests.rejected.0.reason'));
        $this->assertNull(FiscalYear::where('year', 2027)->first());

        \Carbon\Carbon::setTestNow('2026-12-03 10:00:00');
        $this->envoyer($this->comptable, $this->demande('ouvrir_exercice_suivant', ['year' => 2027]))->assertOk()
            ->assertJsonCount(1, 'fiscal_closure_requests.accepted');

        $f = FiscalYear::where('year', 2027)->firstOrFail();
        $this->assertSame('2027-01-01', $f->start_date->toDateString());
        $this->assertSame('ouvert', $f->status);
    }

    public function test_le_premier_exercice_s_ouvre_avec_manage_comptabilite_et_une_seule_fois(): void
    {
        \Illuminate\Support\Facades\DB::table('accounting_entry_lines')->delete();
        \Illuminate\Support\Facades\DB::table('accounting_entries')->delete();
        \Illuminate\Support\Facades\DB::table('accounting_reference_sequences')->delete();
        FiscalYear::query()->delete();
        $annee = (int) now()->format('Y');

        $this->envoyer($this->comptable, $this->demande('ouvrir_exercice', ['year' => $annee]))->assertOk()
            ->assertJsonCount(1, 'fiscal_closure_requests.accepted');
        $this->assertSame("{$annee}-01-01", FiscalYear::where('year', $annee)->firstOrFail()->start_date->toDateString());

        $r = $this->envoyer($this->comptable, $this->demande('ouvrir_exercice', ['year' => $annee]))->assertOk();
        $this->assertSame("L'exercice {$annee} existe déjà.", $r->json('fiscal_closure_requests.rejected.0.reason'));

        $r = $this->envoyer($this->comptable, $this->demande('ouvrir_exercice', ['year' => $annee - 3]))->assertOk();
        $this->assertStringContainsString("n'est pas celui de l'année en cours", $r->json('fiscal_closure_requests.rejected.0.reason'));
    }

    public function test_un_role_sans_le_droit_est_refuse_pour_chaque_geste(): void
    {
        foreach ([
            ['cloturer_periode', ['period' => '2026-03']], ['confirmer_etape1', ['year' => 2026]], ['solder_comptes_gestion', ['year' => 2026]],
            ['cloturer_exercice', ['year' => 2026]], ['ouvrir_exercice_suivant', ['year' => 2027]], ['decloturer_periode', ['period' => '2026-03']],
            ['rouvrir_exercice', ['year' => 2026]], ['ouvrir_exercice', ['year' => 2027]],
        ] as [$kind, $payload]) {
            $r = $this->envoyer($this->caissier, $this->demande($kind, $payload));
            // Le plancher `view-comptabilite` ou le droit du geste : jamais une écriture.
            $this->assertSame(0, count($r->json('fiscal_closure_requests.accepted') ?? []), $kind);
        }

        $this->assertSame(0, FiscalClosureRequest::count());
        $this->assertSame(0, PeriodicClosure::count());
        $this->assertSame('ouvert', FiscalYear::where('year', 2026)->value('status'));
    }

    public function test_une_demande_illisible_est_refusee(): void
    {
        $r = $this->envoyer($this->comptable, ['id' => 'pas-un-uuid', 'kind' => 'cloturer_exercice', 'payload' => []], $this->demande('inconnu'))->assertOk();

        $this->assertCount(2, $r->json('fiscal_closure_requests.rejected'));
        $this->assertSame('Demande de clôture illisible.', $r->json('fiscal_closure_requests.rejected.0.reason'));
    }

    public function test_le_tirage_sert_les_exercices_et_les_mois_clotures_au_comptable(): void
    {
        $this->envoyer($this->comptable, $this->demande('cloturer_periode', ['period' => '2026-03']))->assertOk();
        $this->envoyer($this->comptable, $this->demande('confirmer_etape1', ['year' => 2026]))->assertOk();

        $r = $this->actingAs($this->comptable, 'sanctum')->getJson('/api/sync/pull?page=1')->assertOk();

        $this->assertSame('2026-03', $r->json('periodic_closures.0.period'));
        $this->assertNotNull($r->json('periodic_closures.0.closed_at'));
        $annee = collect($r->json('fiscal_years'))->firstWhere('year', 2026);
        $this->assertNotNull($annee['step1_confirmed_at']);

        // Le caissier n'a pas `view-comptabilite` : pas de mois clôturés.
        $c = $this->actingAs($this->caissier, 'sanctum')->getJson('/api/sync/pull?page=1')->assertOk();
        $this->assertArrayNotHasKey('periodic_closures', $c->json());
    }
}
