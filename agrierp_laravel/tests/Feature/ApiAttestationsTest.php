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
                'name' => ucfirst($u), 'username' => $u, 'email' => $u.'@fermeolouwachegoun.com',
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

    // ───────────── ATT-2 : civilité, signataires et règle de signature depuis le poste ─────────────

    public function test_la_civilite_et_les_signataires_du_poste_arrivent_a_la_fabrique(): void
    {
        $espion = \Mockery::mock(AttestationService::class)->makePartial();
        $espion->shouldReceive('generer')->once()->withArgs(function (...$a) {
            return $a[0] === 'stagiaire'
                && $a[2] === 'CDI'
                && $a[3] === '2024-01-01'
                && $a[5] === 'Très assidu.'                       // « appreciation » du poste devient la note
                && $a[7] === 'Mme'                                // la civilité n'est PLUS avalée
                && $a[8] === ['sig2' => ['nom' => 'KPOHAZOUNDE Jean', 'fonction' => 'Chef ATDA Pôle 5']];
        })->andReturn(['octets' => '%PDF-1.4 essai', 'fichier' => 'attestation-adjovi-felicite.pdf']);
        $this->app->instance(AttestationService::class, $espion);

        $this->avec('rh')->postJson('/api/attestations', [
            'type' => 'stagiaire', 'person_id' => $this->stagiaire->id,
            'start_date' => '2024-01-01', 'end_date' => '2026-05-31',
            'appreciation' => 'Très assidu.', 'civilite' => 'Mme',
            'sig2_nom' => 'KPOHAZOUNDE Jean', 'sig2_fonction' => 'Chef ATDA Pôle 5',
        ])->assertOk();
    }

    public function test_une_civilite_inconnue_est_refusee(): void
    {
        $this->avec('rh')->postJson('/api/attestations', [
            'type' => 'stagiaire', 'person_id' => $this->stagiaire->id, 'civilite' => 'Dr',
        ])->assertStatus(422)->assertJsonValidationErrors('civilite');
        $this->assertSame(0, AuditLog::where('action', 'like', 'attestation.generated%')->count());
    }

    public function test_le_tirage_sert_la_regle_de_signature_et_les_signataires(): void
    {
        $m = collect($this->avec('caisse')->getJson('/api/sync/pull')->assertOk()->json('attestation_templates'))->firstWhere('type', 'stagiaire');

        $this->assertSame(12, $m['seuil_signature_mois']);
        $this->assertSame('Hassimiyou O. OLOUKOUNLE', $m['sig1_nom']);
        $this->assertSame('Examinateur', $m['sig2_titre']);
        $this->assertTrue($m['sig1_court']);
        $this->assertFalse($m['sig2_court']);
        $this->assertTrue($m['sig3_long']);
        $this->assertTrue($m['appreciation_imprimee']);
    }

    public function test_la_regle_de_signature_s_enregistre_depuis_le_poste(): void
    {
        $this->avec('rh')->putJson('/api/attestation-templates/stagiaire', [
            'seuil_signature_mois' => 6, 'sig2_court' => true, 'sig2_nom' => 'KPOHAZOUNDE Jean',
            'sig3_fonction' => 'Président FN-CCPB', 'appreciation_imprimee' => false,
        ])->assertOk();

        $m = AttestationTemplate::forType('stagiaire')->fresh();
        $this->assertSame(6, $m->seuil_signature_mois);
        $this->assertTrue($m->sig2_court);
        $this->assertSame('KPOHAZOUNDE Jean', $m->sig2_nom);
        $this->assertSame('Président FN-CCPB', $m->sig3_fonction);
        $this->assertFalse($m->appreciation_imprimee);
        $this->assertSame($m->body_text, AttestationTemplate::CORPS_STAGIAIRE, 'le texte n\'est pas touché quand il n\'est pas envoyé');
    }

    public function test_un_intitule_vide_du_poste_est_enregistre_sans_erreur(): void
    {
        // Le poste envoie '' pour le Directeur (pas d'intitulé) ; le middleware le lit `null`, la colonne est NON NULLABLE.
        $this->avec('rh')->putJson('/api/attestation-templates/stagiaire', [
            'sig1_titre' => '', 'sig1_fonction' => '', 'appreciation_text' => '',
        ])->assertOk();

        $m = AttestationTemplate::forType('stagiaire')->fresh();
        $this->assertSame('', $m->sig1_titre);
        $this->assertNull($m->appreciation_text, 'vide = la phrase standard du modèle');
    }

    public function test_un_seuil_invalide_ne_change_rien(): void
    {
        $rh = $this->avec('rh');
        foreach ([0, 121, 'abc'] as $mauvais) {
            $rh->putJson('/api/attestation-templates/stagiaire', ['seuil_signature_mois' => $mauvais])
                ->assertStatus(422)->assertJsonValidationErrors('seuil_signature_mois');
        }

        $this->assertSame(12, AttestationTemplate::forType('stagiaire')->seuil_signature_mois);
    }

    public function test_un_lecteur_ne_change_pas_la_regle_de_signature(): void
    {
        $this->avec('lecteur')->putJson('/api/attestation-templates/stagiaire', ['seuil_signature_mois' => 3])->assertStatus(403);

        $this->assertSame(12, AttestationTemplate::forType('stagiaire')->seuil_signature_mois);
    }

    // ───────────── ATT-3 : le poste fabrique le PDF, le serveur attribue le numéro et journalise ─────────────

    private const EMISSION_1 = '11111111-1111-4111-8111-111111111111';

    private const EMISSION_2 = '22222222-2222-4222-8222-222222222222';

    public function test_une_emission_du_poste_recoit_son_numero_et_laisse_sa_trace(): void
    {
        \Carbon\Carbon::setTestNow('2026-10-24 10:00:00');
        $rh = $this->avec('rh');

        $r = $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_1, 'type' => 'stagiaire'])->assertOk();

        $this->assertSame('N°01/2026/FEO/DG', $r->json('numero'));
        $this->assertFalse($r->json('deja_enregistree'));
        $this->assertDatabaseHas('audit_logs', ['action' => 'attestation.generated.stagiaire', 'entity_id' => self::EMISSION_1]);

        $this->assertSame('N°02/2026/FEO/DG', $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_2, 'type' => 'employe'])->json('numero'));
        $this->assertSame(['employe' => 1, 'stagiaire' => 1], app(AttestationService::class)->compteurs());
    }

    public function test_une_emission_rejouee_rend_le_meme_numero_et_ne_compte_qu_une_fois(): void
    {
        \Carbon\Carbon::setTestNow('2026-10-24 10:00:00');
        $rh = $this->avec('rh');
        $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_1, 'type' => 'stagiaire'])->assertOk();
        $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_2, 'type' => 'stagiaire'])->assertOk();

        $rejeu = $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_1, 'type' => 'stagiaire'])->assertOk();

        $this->assertSame('N°01/2026/FEO/DG', $rejeu->json('numero'), 'le numéro de la première émission, pas le suivant');
        $this->assertTrue($rejeu->json('deja_enregistree'));
        $this->assertSame(2, AuditLog::where('action', 'like', 'attestation.generated%')->count());
    }

    public function test_une_emission_faite_hors_ligne_garde_son_instant_et_jamais_dans_le_futur(): void
    {
        \Carbon\Carbon::setTestNow('2026-10-24 10:00:00');
        $rh = $this->avec('rh');

        $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_1, 'type' => 'stagiaire', 'issued_at' => '2026-10-20T08:30:00Z'])->assertOk();
        $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_2, 'type' => 'stagiaire', 'issued_at' => '2027-01-01T00:00:00Z'])->assertOk();

        $this->assertSame('2026-10-20', AuditLog::where('entity_id', self::EMISSION_1)->first()->created_at->format('Y-m-d'));
        $this->assertSame('2026-10-24', AuditLog::where('entity_id', self::EMISSION_2)->first()->created_at->format('Y-m-d'), 'horloge du poste en avance : maintenant');
    }

    public function test_une_emission_faite_hors_ligne_et_recue_tard_ne_reprend_jamais_un_numero_deja_donne(): void
    {
        \Carbon\Carbon::setTestNow('2026-10-24 10:00:00');
        $rh = $this->avec('rh');
        $premier = $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_2, 'type' => 'stagiaire'])->assertOk()->json('numero');
        // Émise plus tôt (poste hors ligne) mais REÇUE après : un rang déduit des dates redonnerait 01.
        $tard = $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_1, 'type' => 'stagiaire', 'issued_at' => '2026-10-01T08:00:00Z'])->assertOk()->json('numero');

        $this->assertSame('N°01/2026/FEO/DG', $premier);
        $this->assertSame('N°02/2026/FEO/DG', $tard);
        $this->assertSame($premier, $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_2, 'type' => 'stagiaire'])->json('numero'), 'le numéro est figé');
    }

    public function test_les_attestations_du_web_et_celles_du_poste_se_suivent_dans_la_meme_numerotation(): void
    {
        \Carbon\Carbon::setTestNow('2026-10-24 10:00:00');
        $rh = $this->avec('rh');
        $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_1, 'type' => 'stagiaire'])->assertOk();

        $this->assertSame('N°02/2026/FEO/DG', app(AttestationService::class)->prochainNumero(), 'le web continue la suite du poste');
        $this->assertSame('N°02/2026/FEO/DG', $rh->postJson('/api/attestations/emissions', ['id' => self::EMISSION_2, 'type' => 'employe'])->json('numero'));
    }

    public function test_une_emission_exige_le_droit_rh_et_des_champs_valides(): void
    {
        $this->avec('caisse')->postJson('/api/attestations/emissions', ['id' => self::EMISSION_1, 'type' => 'stagiaire'])->assertStatus(403);
        $this->assertSame(0, AuditLog::where('action', 'like', 'attestation.generated%')->count());
    }

    public function test_une_emission_invalide_est_refusee_sans_trace(): void
    {
        $rh = $this->avec('rh');
        foreach ([['id' => 'pas-un-uuid', 'type' => 'stagiaire'], ['id' => self::EMISSION_1, 'type' => 'inconnu'], ['type' => 'stagiaire']] as $corps) {
            $rh->postJson('/api/attestations/emissions', $corps)->assertStatus(422);
        }
        $this->assertSame(0, AuditLog::where('action', 'like', 'attestation.generated%')->count());
    }

    public function test_la_route_d_emission_est_fermee_sans_jeton(): void
    {
        $this->postJson('/api/attestations/emissions', ['id' => self::EMISSION_1, 'type' => 'stagiaire'])->assertStatus(401);
    }

    public function test_la_date_de_l_attestation_est_acceptee_et_controlee(): void
    {
        $this->avec('rh')->postJson('/api/attestations', [
            'type' => 'stagiaire', 'person_id' => $this->stagiaire->id,
            'start_date' => '2026-02-01', 'end_date' => '2026-05-31', 'date_attestation' => '2026-06-15',
        ])->assertOk();

        $this->avec('rh')->postJson('/api/attestations', [
            'type' => 'stagiaire', 'person_id' => $this->stagiaire->id,
            'date_attestation' => 'pas-une-date',
        ])->assertStatus(422)->assertJsonValidationErrors('date_attestation');
    }

    public function test_la_date_de_l_attestation_se_lit_dans_le_gabarit_et_l_apercu_web(): void
    {
        $service = app(\App\Services\AttestationService::class);
        $vue = file_get_contents(resource_path('views/exports/attestation.blade.php'));
        $this->assertStringContainsString("{{ \$entete['lieu'] }}, le {{ \$dateLieu }}", $vue);
        $this->assertSame('15 juin 2026', $service::dateLongue(\Carbon\Carbon::parse('2026-06-15')));

        $page = file_get_contents(resource_path('views/livewire/rh/attestations.blade.php'));
        $this->assertStringContainsString('wire:model.live="dateAttestation"', $page);
        $this->assertStringContainsString("Date de l'attestation", $page);
    }
}
