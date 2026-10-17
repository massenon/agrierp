<?php

namespace Tests\Feature;

use App\Models\AttestationTemplate;
use App\Models\AuditLog;
use App\Models\Employee;
use App\Models\Internship;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\AttestationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 15.13 — les attestations depuis le poste : le PDF est produit et
 * journalisé par le serveur, les modèles et le compteur descendent au tirage.
 */
class ApiAttestationsTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private Employee $employe;

    private Internship $stagiaire;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-rh', 'manage-rh'] as $p) {
            Permission::findOrCreate($p, 'web');
        }
        Role::findOrCreate('rh', 'web')->givePermissionTo(['view-rh', 'manage-rh']);
        Role::findOrCreate('lecteur-rh', 'web')->givePermissionTo('view-rh');
        Role::findOrCreate('caissier', 'web');

        foreach ([['rh', 'rh'], ['lecteur', 'lecteur-rh'], ['caisse', 'caissier']] as [$u, $role]) {
            User::create([
                'name' => ucfirst($u), 'username' => $u, 'email' => $u.'@olouwachegoun.bj',
                'password' => bcrypt(self::MDP), 'is_active' => true,
            ])->assignRole($role);
        }

        $this->employe = Employee::create([
            'first_name' => 'Jean', 'last_name' => 'AGOSSOU', 'position' => 'Animalier',
            'hire_date' => '2024-03-01', 'status' => 'actif', 'is_active' => true,
        ]);
        $this->stagiaire = Internship::create([
            'first_name' => 'Félicité', 'last_name' => 'ADJOVI', 'school' => 'Agronomie',
            'start_date' => '2026-02-01', 'end_date' => '2026-05-31',
        ]);
    }

    private function jeton(string $u): string
    {
        return $this->postJson('/api/auth/login', [
            'identifiant' => $u, 'password' => self::MDP, 'device_name' => 'poste-'.$u,
        ])->json('token');
    }

    private function avec(string $u)
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->jeton($u));
    }

    public function test_une_attestation_de_travail_est_un_pdf_et_laisse_sa_trace(): void
    {
        $r = $this->avec('rh')->postJson('/api/attestations', [
            'type' => 'employe', 'person_id' => $this->employe->id, 'contract_type' => 'CDI',
            'start_date' => '2024-03-01',
        ])->assertOk();

        $this->assertSame('application/pdf', $r->headers->get('Content-Type'));
        $this->assertStringStartsWith('%PDF', $r->getContent());
        $this->assertStringContainsString('attestation-agossou-jean.pdf', $r->headers->get('Content-Disposition'));
        $this->assertDatabaseHas('audit_logs', ['action' => 'attestation.generated.employe']);
    }

    public function test_une_attestation_de_stage_se_journalise_sous_son_propre_type(): void
    {
        $this->avec('rh')->postJson('/api/attestations', [
            'type' => 'stagiaire', 'person_id' => $this->stagiaire->id,
            'start_date' => '2026-02-01', 'end_date' => '2026-05-31',
        ])->assertOk();

        $this->assertDatabaseHas('audit_logs', ['action' => 'attestation.generated.stagiaire']);
        $this->assertDatabaseMissing('audit_logs', ['action' => 'attestation.generated.employe']);
    }

    public function test_le_texte_est_celui_du_service_partage_avec_la_page_web(): void
    {
        $texte = app(AttestationService::class)->corps(
            'employe', $this->employe, 'CDD', '2024-03-01', null,
        );

        $this->assertStringContainsString('AGOSSOU Jean', $texte);
        $this->assertStringContainsString('Animalier', $texte);
        $this->assertStringContainsString('CDD', $texte);
        $this->assertStringContainsString('01/03/2024', $texte);
        // Pas de date de fin : « ce jour », jamais une phrase brisée.
        $this->assertStringContainsString('au ce jour', $texte);
    }

    public function test_sans_droit_rh_la_generation_est_refusee_et_non_journalisee(): void
    {
        $this->avec('caisse')->postJson('/api/attestations', [
            'type' => 'employe', 'person_id' => $this->employe->id,
        ])->assertForbidden();

        $this->assertSame(0, AuditLog::where('action', 'like', 'attestation.generated%')->count());
    }

    public function test_une_personne_inconnue_est_refusee_sans_trace(): void
    {
        $this->avec('rh')->postJson('/api/attestations', [
            'type' => 'employe', 'person_id' => '00000000-0000-0000-0000-000000000000',
        ])->assertStatus(422)->assertJsonValidationErrors('person_id');

        $this->assertSame(0, AuditLog::where('action', 'like', 'attestation.generated%')->count());
    }

    public function test_un_type_invalide_est_refuse(): void
    {
        $this->avec('rh')->postJson('/api/attestations', [
            'type' => 'autre', 'person_id' => $this->employe->id,
        ])->assertStatus(422)->assertJsonValidationErrors('type');
    }

    public function test_la_route_est_fermee_sans_jeton(): void
    {
        $this->postJson('/api/attestations', [])->assertStatus(401);
        $this->putJson('/api/attestation-templates/employe', [])->assertStatus(401);
    }

    public function test_le_tirage_sert_les_deux_modeles_meme_sur_une_ferme_neuve(): void
    {
        $this->assertDatabaseCount('attestation_templates', 0);

        $modeles = collect($this->avec('caisse')->getJson('/api/sync/pull')->assertOk()->json('attestation_templates'));

        $this->assertEqualsCanonicalizing(['employe', 'stagiaire'], $modeles->pluck('type')->all());
        $this->assertStringContainsString('[NOM]', $modeles->firstWhere('type', 'employe')['body_text']);
    }

    public function test_le_compteur_porte_sur_tout_l_historique_et_non_sur_cent_lignes(): void
    {
        // 150 générations : au-delà des 100 lignes d'audit que le poste détient.
        for ($i = 0; $i < 150; $i++) {
            AuditLog::create(['action' => 'attestation.generated.stagiaire', 'module' => 'rh']);
        }
        AuditLog::create(['action' => 'attestation.generated.employe', 'module' => 'rh']);
        AuditLog::create(['action' => 'sale.created', 'module' => 'ventes']);

        $c = $this->avec('caisse')->getJson('/api/sync/pull')->json('attestation_counts');

        $this->assertSame(150, $c['stagiaire']);
        $this->assertSame(1, $c['employe']);
    }

    public function test_un_modele_s_enregistre_avec_le_droit_manage_rh(): void
    {
        $this->avec('rh')->putJson('/api/attestation-templates/employe', [
            'body_text' => 'Texte neuf pour [NOM].',
        ])->assertOk();

        $this->assertSame('Texte neuf pour [NOM].', AttestationTemplate::forType('employe')->body_text);
        $this->assertDatabaseHas('audit_logs', ['action' => 'attestation_template.updated']);
    }

    public function test_lire_les_attestations_ne_donne_pas_le_droit_de_changer_les_modeles(): void
    {
        $avant = AttestationTemplate::forType('employe')->body_text;

        $this->avec('lecteur')->putJson('/api/attestation-templates/employe', [
            'body_text' => 'Texte détourné',
        ])->assertForbidden();

        $this->assertSame($avant, AttestationTemplate::forType('employe')->body_text);
    }

    public function test_un_modele_vide_ou_d_un_type_inconnu_est_refuse(): void
    {
        $this->avec('rh')->putJson('/api/attestation-templates/employe', ['body_text' => ''])
            ->assertStatus(422)->assertJsonValidationErrors('body_text');
        $this->avec('rh')->putJson('/api/attestation-templates/inconnu', ['body_text' => 'x'])
            ->assertNotFound();
    }
}
