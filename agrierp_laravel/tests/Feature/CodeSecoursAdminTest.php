<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use App\Services\CodeSecoursService;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

/**
 * Ticket MDP-1 — CODE DE SECOURS DE L'ADMINISTRATEUR : `agrierp:code-secours` (génère, affiche UNE fois, stocke l'empreinte)
 * et `agrierp:reinitialiser-admin {identifiant}` (code masqué + mot de passe temporaire, usage unique, nouveau code,
 * limiteur 5 échecs / 15 minutes).
 */
class CodeSecoursAdminTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        RateLimiter::clear(CodeSecoursService::CLE_LIMITEUR);

        $this->admin = User::create(['name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com', 'password' => bcrypt('Oublie#2026'), 'is_active' => true]);
        $this->admin->assignRole('admin');
    }

    /** Lance la génération et rend le code lu dans la sortie de la commande. */
    private function genererLeCode(): string
    {
        \Illuminate\Support\Facades\Artisan::call('agrierp:code-secours', ['--force' => true]);
        $this->assertSame(1, preg_match('/([A-Z2-9]{4}(?:-[A-Z2-9]{4}){5})/', \Illuminate\Support\Facades\Artisan::output(), $m), 'le code est affiché, 6 groupes de 4');

        return $m[1];
    }

    public function test_le_code_a_24_caracteres_lisibles_et_seule_son_empreinte_est_stockee(): void
    {
        $code = $this->genererLeCode();

        $brut = str_replace('-', '', $code);
        $this->assertSame(24, strlen($brut));
        $this->assertSame(0, preg_match('/[01ILO]/', $brut), 'alphabet lisible : ni 0, O, 1, I, L');

        $lignes = DB::table('recovery_codes')->get();
        $this->assertCount(1, $lignes);
        $this->assertSame(hash('sha256', $brut), $lignes[0]->empreinte);
        $this->assertNull($lignes[0]->used_at);
        $this->assertStringNotContainsString($brut, json_encode(DB::table('recovery_codes')->get()), 'le code lui-même n\'est nulle part en base');
        $this->assertStringNotContainsString($brut, json_encode(AuditLog::all()->toArray()), 'ni au journal');
        $this->assertSame(1, AuditLog::where('action', 'recovery_code.generated')->count());
    }

    public function test_un_nouveau_code_remplace_l_ancien_apres_confirmation(): void
    {
        $ancien = $this->genererLeCode();

        $this->artisan('agrierp:code-secours')
            ->expectsConfirmation("Un code de secours est déjà actif. Le remplacer ? L'ancien code ne fonctionnera plus.", 'no')
            ->expectsOutputToContain('le code actif est conservé')
            ->assertSuccessful();
        $this->assertTrue(app(CodeSecoursService::class)->verifier($ancien), 'refus du remplacement : l\'ancien reste valable');

        $nouveau = $this->genererLeCode();
        $this->assertNotSame($ancien, $nouveau);
        $this->assertFalse(app(CodeSecoursService::class)->verifier($ancien));
        $this->assertTrue(app(CodeSecoursService::class)->verifier($nouveau));
        $this->assertSame(1, DB::table('recovery_codes')->whereNull('used_at')->count(), 'un seul code actif');
    }

    public function test_la_reinitialisation_reussit_marque_le_compte_revoque_trace_invalide_le_code_et_en_donne_un_nouveau(): void
    {
        $code = $this->genererLeCode();
        $this->admin->createToken('poste-bureau');
        DB::table('sessions')->insert(['id' => 'sess-admin', 'user_id' => $this->admin->id, 'payload' => 'x', 'last_activity' => time()]);

        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
            ->expectsQuestion('Code de secours (24 caractères)', strtolower($code)) // casse et tirets indifférents
            ->expectsQuestion('Nouveau mot de passe TEMPORAIRE', 'Temp#Secours2026')
            ->expectsQuestion('Confirmez le mot de passe temporaire', 'Temp#Secours2026')
            ->expectsOutputToContain('NOUVEAU CODE DE SECOURS')
            ->assertSuccessful();

        $u = $this->admin->fresh();
        $this->assertTrue($u->must_change_password);
        $this->assertTrue(Hash::check('Temp#Secours2026', $u->password));
        $this->assertSame(0, $u->tokens()->count());
        $this->assertNull(DB::table('sessions')->where('id', 'sess-admin')->first());

        $trace = AuditLog::where('action', 'user.password_reset_secours')->get();
        $this->assertCount(1, $trace);
        $this->assertSame($this->admin->id, $trace[0]->entity_id);
        $journal = json_encode(AuditLog::all()->toArray());
        $this->assertStringNotContainsString('Temp#Secours2026', $journal);
        $this->assertStringNotContainsString(str_replace('-', '', $code), $journal);

        // Le code utilisé est invalide ; un NOUVEAU code actif existe, différent.
        $this->assertFalse(app(CodeSecoursService::class)->verifier($code));
        $this->assertSame(1, DB::table('recovery_codes')->whereNull('used_at')->count());
        $this->assertSame(1, DB::table('recovery_codes')->where('used_reason', 'utilise')->count());
    }

    public function test_le_nouveau_code_affiche_est_le_code_actif_et_le_code_utilise_ne_sert_pas_deux_fois(): void
    {
        $code = $this->genererLeCode();

        // Un espion garde le code que la commande AFFICHE (celui que générerait le service réel).
        $espion = new class extends CodeSecoursService {
            public array $affiches = [];

            public function generer(): string
            {
                return $this->affiches[] = parent::generer();
            }
        };
        $this->app->instance(CodeSecoursService::class, $espion);

        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
            ->expectsQuestion('Code de secours (24 caractères)', $code)
            ->expectsQuestion('Nouveau mot de passe TEMPORAIRE', 'Temp#Secours2026')
            ->expectsQuestion('Confirmez le mot de passe temporaire', 'Temp#Secours2026')
            ->assertSuccessful();

        $this->assertCount(1, $espion->affiches, 'un seul nouveau code généré');
        $nouveau = $espion->affiches[0];
        $this->assertNotSame($code, $nouveau);
        $this->assertTrue($espion->verifier($nouveau), 'le code affiché est le code actif');

        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
            ->expectsQuestion('Code de secours (24 caractères)', $code)
            ->expectsOutputToContain('Code de secours incorrect ou déjà utilisé.')
            ->assertFailed();
    }

    public function test_un_code_faux_est_refuse_sans_rien_changer_et_journalise(): void
    {
        $this->genererLeCode();

        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
            ->expectsQuestion('Code de secours (24 caractères)', 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF')
            ->expectsOutputToContain('Code de secours incorrect ou déjà utilisé.')
            ->assertFailed();

        $u = $this->admin->fresh();
        $this->assertFalse($u->must_change_password);
        $this->assertTrue(Hash::check('Oublie#2026', $u->password));
        $this->assertSame(1, DB::table('recovery_codes')->whereNull('used_at')->count(), 'le code n\'est pas consommé');
        $this->assertSame(1, AuditLog::where('action', 'user.password_reset_secours_echec')->count());
    }

    public function test_sans_aucun_code_actif_la_commande_refuse_comme_pour_un_code_faux(): void
    {
        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
            ->expectsQuestion('Code de secours (24 caractères)', 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF')
            ->assertFailed();

        $this->assertFalse($this->admin->fresh()->must_change_password);
    }

    public function test_cinq_echecs_bloquent_la_commande_meme_avec_le_bon_code(): void
    {
        $code = $this->genererLeCode();

        foreach (range(1, 5) as $i) {
            $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
                ->expectsQuestion('Code de secours (24 caractères)', 'AAAA-BBBB-CCCC-DDDD-EEEE-'.str_pad((string) $i, 4, 'X'))
                ->assertFailed();
        }

        $this->assertSame(4, AuditLog::where('action', 'user.password_reset_secours_echec')->count());
        $this->assertSame(1, AuditLog::where('action', 'user.password_reset_secours_bloque')->count(), 'le blocage est journalisé une fois');

        // Bloquée : le BON code n'est même plus demandé.
        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
            ->expectsOutputToContain('Trop d\'échecs : la commande est bloquée')
            ->assertFailed();
        $this->assertFalse($this->admin->fresh()->must_change_password);
        $this->assertTrue(app(CodeSecoursService::class)->verifier($code), 'le code reste valable, seulement inaccessible');

        // Après 15 minutes, la commande répond de nouveau.
        $this->travel(16)->minutes();
        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
            ->expectsQuestion('Code de secours (24 caractères)', $code)
            ->expectsQuestion('Nouveau mot de passe TEMPORAIRE', 'Temp#Secours2026')
            ->expectsQuestion('Confirmez le mot de passe temporaire', 'Temp#Secours2026')
            ->assertSuccessful();
    }

    public function test_un_mot_de_passe_faible_ou_mal_confirme_ne_consomme_pas_le_code(): void
    {
        $code = $this->genererLeCode();

        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
            ->expectsQuestion('Code de secours (24 caractères)', $code)
            ->expectsQuestion('Nouveau mot de passe TEMPORAIRE', '12345678')
            ->expectsQuestion('Confirmez le mot de passe temporaire', '12345678')
            ->expectsOutputToContain("Le code de secours n'a pas été consommé.")
            ->assertFailed();

        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'admin'])
            ->expectsQuestion('Code de secours (24 caractères)', $code)
            ->expectsQuestion('Nouveau mot de passe TEMPORAIRE', 'Temp#Secours2026')
            ->expectsQuestion('Confirmez le mot de passe temporaire', 'Autre#Secours2026')
            ->assertFailed();

        $this->assertTrue(app(CodeSecoursService::class)->verifier($code));
        $this->assertFalse($this->admin->fresh()->must_change_password);
    }

    public function test_seul_un_administrateur_actif_est_reinitialisable_par_cette_commande(): void
    {
        $this->genererLeCode();
        $caissier = User::create(['name' => 'Afi', 'username' => 'afi', 'email' => 'afi@fermeolouwachegoun.com', 'password' => bcrypt('Ancien#2026'), 'is_active' => true]);
        $caissier->assignRole('caissier');

        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'afi'])->expectsOutputToContain('Aucun compte administrateur actif')->assertFailed();
        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'inconnu'])->expectsOutputToContain('Aucun compte administrateur actif')->assertFailed();

        $this->admin->update(['is_active' => false]);
        $this->artisan('agrierp:reinitialiser-admin', ['identifiant' => 'dg@fermeolouwachegoun.com'])->expectsOutputToContain('Aucun compte administrateur actif')->assertFailed();

        $this->assertFalse($caissier->fresh()->must_change_password);
    }

    public function test_le_code_survit_a_la_reinitialisation_des_donnees(): void
    {
        $this->assertContains('recovery_codes', \App\Services\ReinitialisationDonneesService::tablesPreservees());
    }

    public function test_la_verification_compare_en_temps_constant(): void
    {
        $source = file_get_contents(app_path('Services/CodeSecoursService.php'));

        $this->assertStringContainsString('hash_equals', $source);
        $this->assertStringNotContainsString("=== \$this->empreinte", $source, 'jamais de comparaison ordinaire des empreintes');
    }
}
