<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * MAIL1 (décision du client, 21/10/2026) — les anciennes adresses `@olouwachegoun.bj` déjà enregistrées en base
 * deviennent `@fermeolouwachegoun.com`. Migration de DONNÉES, idempotente.
 *
 * Les valeurs attendues sont des littéraux écrits à la main. Les tests qui comptent le plus sont ceux des
 * REFUS : l'unicité de `users.email`, l'audit qui ne se réécrit pas, le secret SMTP qui n'est jamais touché.
 */
class MigrationAdressesEmailTest extends TestCase
{
    use RefreshDatabase;

    private const ANCIEN = '2026-01-15 08:00:00';

    private function migrer(): void
    {
        $migration = require database_path('migrations/2026_10_21_000001_migrer_les_adresses_email_du_domaine.php');
        $migration->up();
    }

    private function utilisateur(string $username, string $email): string
    {
        $id = (string) Str::uuid();
        DB::table('users')->insert([
            'id' => $id, 'name' => $username, 'username' => $username, 'email' => $email,
            'password' => 'hash-intact', 'is_active' => 1, 'created_at' => self::ANCIEN, 'updated_at' => self::ANCIEN,
        ]);

        return $id;
    }

    private function client(string $nom, ?string $email): string
    {
        $id = (string) Str::uuid();
        DB::table('customers')->insert([
            'id' => $id, 'name' => $nom, 'phone' => '0100000000', 'email' => $email, 'is_active' => 1,
            'created_at' => self::ANCIEN, 'updated_at' => self::ANCIEN,
        ]);

        return $id;
    }

    private function fournisseur(string $nom, ?string $email): string
    {
        $id = (string) Str::uuid();
        DB::table('suppliers')->insert([
            'id' => $id, 'name' => $nom, 'category' => 'Aliments', 'phone' => '0100000001', 'email' => $email,
            'is_active' => 1, 'created_at' => self::ANCIEN, 'updated_at' => self::ANCIEN,
        ]);

        return $id;
    }

    private function parametres(array $valeurs): string
    {
        $id = (string) Str::uuid();
        DB::table('company_settings')->insert(array_merge([
            'id' => $id, 'company_name' => 'Ferme', 'created_at' => self::ANCIEN, 'updated_at' => self::ANCIEN,
        ], $valeurs));

        return $id;
    }

    public function test_les_adresses_de_tous_les_ecrans_changent_de_domaine(): void
    {
        $compta = $this->utilisateur('compta', 'compta@olouwachegoun.bj');
        $caisse = $this->utilisateur('caisse', 'Caisse@OLOUWACHEGOUN.BJ');
        $autre = $this->utilisateur('externe', 'externe@gmail.com');
        $cli = $this->client('Mama', 'mama@olouwachegoun.bj');
        $cliSans = $this->client('Sans', null);
        $cliAutre = $this->client('Autre', 'autre@resto.bj');
        $four = $this->fournisseur('Provenderie', 'achats@olouwachegoun.bj');
        $param = $this->parametres([
            'email' => 'dg@olouwachegoun.bj',
            'smtp_user' => 'notifications@olouwachegoun.bj',
            'smtp_from_address' => 'envoi@Olouwachegoun.BJ',
            'smtp_host' => 'smtp.olouwachegoun.bj',
            'smtp_password_encrypted' => 'secret@olouwachegoun.bj',
        ]);

        $this->migrer();

        $this->assertSame('compta@fermeolouwachegoun.com', DB::table('users')->where('id', $compta)->value('email'));
        $this->assertSame('Caisse@fermeolouwachegoun.com', DB::table('users')->where('id', $caisse)->value('email'));
        $this->assertSame('externe@gmail.com', DB::table('users')->where('id', $autre)->value('email'));
        $this->assertSame('mama@fermeolouwachegoun.com', DB::table('customers')->where('id', $cli)->value('email'));
        $this->assertNull(DB::table('customers')->where('id', $cliSans)->value('email'));
        $this->assertSame('autre@resto.bj', DB::table('customers')->where('id', $cliAutre)->value('email'));
        $this->assertSame('achats@fermeolouwachegoun.com', DB::table('suppliers')->where('id', $four)->value('email'));

        $ligne = DB::table('company_settings')->where('id', $param)->first();
        $this->assertSame('dg@fermeolouwachegoun.com', $ligne->email);
        $this->assertSame('notifications@fermeolouwachegoun.com', $ligne->smtp_user);
        $this->assertSame('envoi@fermeolouwachegoun.com', $ligne->smtp_from_address);
        // Un nom de serveur n'est pas une adresse e-mail (pas de « @ ») : on n'y touche pas.
        $this->assertSame('smtp.olouwachegoun.bj', $ligne->smtp_host);
        // Le mot de passe chiffré n'est JAMAIS lu ni réécrit.
        $this->assertSame('secret@olouwachegoun.bj', $ligne->smtp_password_encrypted);
        // Autres colonnes de la ligne intactes.
        $this->assertSame('hash-intact', DB::table('users')->where('id', $compta)->value('password'));
    }

    public function test_la_deuxieme_execution_est_sans_effet(): void
    {
        $id = $this->client('Mama', 'mama@olouwachegoun.bj');
        $this->migrer();
        $apres = DB::table('customers')->where('id', $id)->first();
        $this->assertSame('mama@fermeolouwachegoun.com', $apres->email);

        // On vieillit volontairement updated_at : une 2e exécution ne doit pas le rafraîchir (aucune ligne à changer).
        DB::table('customers')->where('id', $id)->update(['updated_at' => self::ANCIEN]);
        $this->migrer();

        $encore = DB::table('customers')->where('id', $id)->first();
        $this->assertSame('mama@fermeolouwachegoun.com', $encore->email);
        $this->assertSame(self::ANCIEN, $encore->updated_at);
    }

    public function test_updated_at_est_rafraichi_sur_les_seules_lignes_modifiees(): void
    {
        Carbon::setTestNow('2026-10-21 10:30:00');
        $change = $this->client('Mama', 'mama@olouwachegoun.bj');
        $intact = $this->client('Autre', 'autre@resto.bj');

        $this->migrer();

        $this->assertSame('2026-10-21 10:30:00', DB::table('customers')->where('id', $change)->value('updated_at'));
        $this->assertSame(self::ANCIEN, DB::table('customers')->where('id', $intact)->value('updated_at'));
        Carbon::setTestNow();
    }

    public function test_une_adresse_deja_prise_par_un_autre_compte_n_est_pas_changee_et_est_journalisee(): void
    {
        $ancien = $this->utilisateur('compta', 'compta@olouwachegoun.bj');
        $this->utilisateur('compta2', 'compta@fermeolouwachegoun.com');
        $libre = $this->utilisateur('caisse', 'caisse@olouwachegoun.bj');

        Log::shouldReceive('warning')->once()->withArgs(fn ($message) => str_contains($message, 'compta@olouwachegoun.bj'));

        $this->migrer();

        $this->assertSame('compta@olouwachegoun.bj', DB::table('users')->where('id', $ancien)->value('email'));
        $this->assertSame('caisse@fermeolouwachegoun.com', DB::table('users')->where('id', $libre)->value('email'));
        $this->assertSame(1, DB::table('users')->where('email', 'compta@fermeolouwachegoun.com')->count());
    }

    public function test_deux_anciennes_adresses_qui_ne_different_que_par_la_casse_ne_se_percutent_pas(): void
    {
        $a = $this->utilisateur('a', 'dupont@olouwachegoun.bj');
        $b = $this->utilisateur('b', 'DUPONT@OLOUWACHEGOUN.BJ');

        Log::shouldReceive('warning')->once();

        $this->migrer();

        $emails = DB::table('users')->whereIn('id', [$a, $b])->pluck('email')->all();
        $this->assertCount(2, array_unique(array_map('strtolower', $emails)));
        $this->assertSame(1, count(array_filter($emails, fn ($e) => str_ends_with(strtolower($e), '@fermeolouwachegoun.com'))));
    }

    public function test_le_compte_admin_garde_l_adresse_de_contact(): void
    {
        $admin = $this->utilisateur('admin', 'dg@olouwachegoun.bj');
        $autre = $this->utilisateur('directeur', 'dg2@olouwachegoun.bj');

        $this->migrer();

        $this->assertSame('contact@fermeolouwachegoun.com', DB::table('users')->where('id', $admin)->value('email'));
        $this->assertSame('dg2@fermeolouwachegoun.com', DB::table('users')->where('id', $autre)->value('email'));
    }

    public function test_dg_d_un_compte_qui_n_est_pas_admin_devient_dg_au_nouveau_domaine(): void
    {
        $id = $this->utilisateur('directeur', 'dg@olouwachegoun.bj');

        $this->migrer();

        $this->assertSame('dg@fermeolouwachegoun.com', DB::table('users')->where('id', $id)->value('email'));
    }

    public function test_l_audit_n_est_pas_reecrit(): void
    {
        // Aujourd'hui `audit_logs` n'a aucune colonne au nom d'adresse : on en ajoute une pour prouver que
        // l'EXCLUSION (et non le hasard des noms) protège l'historique.
        Schema::table('audit_logs', fn ($t) => $t->string('contact_email')->nullable());
        $id = (string) Str::uuid();
        DB::table('audit_logs')->insert([
            'id' => $id, 'action' => 'Connexion échouée pour dg@olouwachegoun.bj', 'module' => 'auth@olouwachegoun.bj',
            'ip_address' => '127.0.0.1', 'created_at' => self::ANCIEN, 'contact_email' => 'dg@olouwachegoun.bj',
        ]);

        $this->migrer();

        $ligne = DB::table('audit_logs')->where('id', $id)->first();
        $this->assertSame('Connexion échouée pour dg@olouwachegoun.bj', $ligne->action);
        $this->assertSame('auth@olouwachegoun.bj', $ligne->module);
        $this->assertSame('dg@olouwachegoun.bj', $ligne->contact_email);
    }

    public function test_les_notifications_et_les_jetons_de_reinitialisation_sont_convertis(): void
    {
        $idNotif = (string) Str::uuid();
        DB::table('notifications')->insert([
            'id' => $idNotif, 'type' => 'system', 'severity' => 'info', 'title' => 'Bienvenue',
            'message' => 'Écrivez à contact@olouwachegoun.bj pour toute question.', 'is_read' => 0, 'created_at' => self::ANCIEN,
        ]);
        DB::table('password_reset_tokens')->insert(['email' => 'compta@olouwachegoun.bj', 'token' => 't', 'created_at' => self::ANCIEN]);

        $this->migrer();

        $this->assertSame('Écrivez à contact@fermeolouwachegoun.com pour toute question.', DB::table('notifications')->where('id', $idNotif)->value('message'));
        $this->assertSame(['compta@fermeolouwachegoun.com'], DB::table('password_reset_tokens')->pluck('email')->all());
    }

    public function test_la_reinitialisation_des_donnees_n_est_pas_concernee(): void
    {
        // La reprise (ReinitialisationDonneesService) ne relance jamais la migration : une adresse à l'ancien
        // domaine qui lui survit n'est convertie que par `php artisan migrate`.
        $source = file_get_contents(app_path('Services/ReinitialisationDonneesService.php'));
        $this->assertStringNotContainsString('migrer_les_adresses_email', $source);
        $this->assertStringNotContainsString('olouwachegoun', strtolower(str_replace('fermeolouwachegoun', '', $source)));
    }
}
