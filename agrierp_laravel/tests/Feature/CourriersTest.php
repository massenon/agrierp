<?php

namespace Tests\Feature;

use App\Livewire\Administration\GestionCourriers;
use App\Models\AuditLog;
use App\Models\Correspondence;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\CourrierService;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.23 — courriers : service partagé `CourrierService`, page web
 * (`GestionCourriers`) ET `/sync/push` (table `mails`), référence robuste au-delà de 999.
 */
class CourriersTest extends TestCase
{
    use RefreshDatabase;

    private User $secretaire;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();

        Permission::findOrCreate('manage-administration', 'web');
        Role::findOrCreate('secretaire', 'web')->givePermissionTo('manage-administration');
        Role::findOrCreate('caissier', 'web');

        foreach (['secretaire', 'caissier'] as $role) {
            $u = User::create([
                'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
                'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
            ]);
            $u->assignRole($role);
            $this->{$role} = $u;
        }
    }

    private function fiche(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'type' => 'entrant',
            'subject' => 'Convocation PAEB',
            'party' => 'PAEB',
            'mail_date' => '2026-10-01',
            'is_active' => true,
        ], $remplace);
    }

    private function pousser(User $u, array ...$fiches): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            'mails' => $fiches,
        ])->assertOk();
    }

    private function courrierExistant(string $reference, bool $actif = true): Correspondence
    {
        $c = new Correspondence();
        $c->fill([
            'reference' => $reference, 'type' => 'sortant', 'subject' => 'Existant', 'party' => 'X',
            'mail_date' => '2026-01-05', 'is_active' => $actif,
        ]);
        $c->save();

        return $c;
    }

    private function prefixe(): string
    {
        return 'CR-'.now()->format('Y').'-';
    }

    // ── Référence ───────────────────────────────────────────────────────────

    public function test_la_premiere_reference_de_l_annee_est_001(): void
    {
        $this->assertSame($this->prefixe().'001', Correspondence::generateReference());
    }

    public function test_le_format_reste_sur_trois_chiffres_jusqu_a_999(): void
    {
        $this->courrierExistant($this->prefixe().'008');
        $this->assertSame($this->prefixe().'009', Correspondence::generateReference());

        $this->courrierExistant($this->prefixe().'998');
        $this->assertSame($this->prefixe().'999', Correspondence::generateReference());
    }

    public function test_apres_999_la_reference_passe_a_quatre_chiffres_sans_doublon(): void
    {
        $this->courrierExistant($this->prefixe().'999');

        $this->assertSame($this->prefixe().'1000', Correspondence::generateReference());

        // Le 1000e courrier reçoit 1000 ; le suivant 1001 (l'ancien code, qui triait en texte
        // et lisait 3 caractères, redonnait « 1000 » ou « 001 » → doublon).
        $service = app(CourrierService::class);
        $a = $service->creer($this->fiche());
        $b = $service->creer($this->fiche());
        $c = $service->creer($this->fiche());

        $this->assertSame($this->prefixe().'1000', $a->reference);
        $this->assertSame($this->prefixe().'1001', $b->reference);
        $this->assertSame($this->prefixe().'1002', $c->reference);
        $this->assertSame(4, Correspondence::distinct('reference')->count('reference'));
    }

    public function test_une_reference_prise_par_un_concurrent_est_recalculee(): void
    {
        $deja = false;
        Correspondence::creating(function (Correspondence $m) use (&$deja) {
            if (! $deja) {
                $deja = true;
                // Un autre enregistrement vient de prendre CE numéro entre le calcul et l'écriture.
                DB::table('mails')->insert([
                    'id' => (string) Str::uuid(), 'reference' => $m->reference, 'type' => 'entrant',
                    'subject' => 'Concurrent', 'party' => 'Y', 'mail_date' => '2026-01-01',
                    'is_active' => true, 'created_at' => now(), 'updated_at' => now(),
                ]);
            }
        });

        $cree = app(CourrierService::class)->creer($this->fiche());

        $this->assertSame($this->prefixe().'002', $cree->reference);
        $this->assertSame(2, Correspondence::count());
        $this->assertDatabaseHas('audit_logs', ['action' => 'mail.created']);
    }

    // ── Page web ────────────────────────────────────────────────────────────

    public function test_la_page_web_cree_un_courrier_avec_sa_reference_et_son_audit(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(GestionCourriers::class)
            ->set('type', 'sortant')
            ->set('subject', 'Demande de subvention')
            ->set('party', 'Mairie')
            ->set('mailDate', '2026-10-02')
            ->call('saveMail')
            ->assertHasNoErrors();

        $c = Correspondence::firstWhere('subject', 'Demande de subvention');
        $this->assertNotNull($c);
        $this->assertSame($this->prefixe().'001', $c->reference);
        $this->assertTrue((bool) $c->is_active);
        $this->assertSame('2026-10-02', $c->mail_date->format('Y-m-d'));
        $this->assertSame(1, AuditLog::where('action', 'mail.created')->count());
    }

    public function test_la_page_web_modifie_sans_changer_la_reference(): void
    {
        $this->actingAs($this->secretaire);
        $c = $this->courrierExistant($this->prefixe().'007');

        Livewire::test(GestionCourriers::class)
            ->call('editMail', $c->id)
            ->set('subject', 'Objet corrigé')
            ->call('saveMail')
            ->assertHasNoErrors();

        $c->refresh();
        $this->assertSame('Objet corrigé', $c->subject);
        $this->assertSame($this->prefixe().'007', $c->reference);
        $this->assertSame(1, AuditLog::where('action', 'mail.updated')->count());
        $this->assertSame(1, Correspondence::count());
    }

    public function test_la_page_web_archive_sans_rien_effacer_et_sans_doubler_l_audit(): void
    {
        $this->actingAs($this->secretaire);
        $c = $this->courrierExistant($this->prefixe().'001');

        Livewire::test(GestionCourriers::class)->call('archiveMail', $c->id);
        Livewire::test(GestionCourriers::class)->call('archiveMail', $c->id);

        $this->assertFalse((bool) $c->fresh()->is_active);
        $this->assertSame(1, Correspondence::count(), 'archiver ne supprime pas');
        $this->assertSame(1, AuditLog::where('action', 'mail.archived')->count(), 'déjà archivé : succès sans nouvelle trace');
    }

    public function test_la_page_web_refuse_un_role_sans_le_droit(): void
    {
        $this->actingAs($this->caissier);
        $c = $this->courrierExistant($this->prefixe().'001');

        Livewire::test(GestionCourriers::class)
            ->set('type', 'entrant')->set('subject', 'S')->set('party', 'P')->set('mailDate', '2026-10-02')
            ->call('saveMail')
            ->assertForbidden();
        Livewire::test(GestionCourriers::class)->call('archiveMail', $c->id)->assertForbidden();
        Livewire::test(GestionCourriers::class)->call('editMail', $c->id)->assertForbidden();

        $this->assertSame(1, Correspondence::count());
        $this->assertTrue((bool) $c->fresh()->is_active);
    }

    public function test_la_page_web_refuse_les_champs_invalides(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(GestionCourriers::class)
            ->set('type', 'autre')
            ->set('subject', str_repeat('a', 256))
            ->set('party', str_repeat('b', 151))
            ->set('mailDate', 'pas-une-date')
            ->call('saveMail')
            ->assertHasErrors(['type', 'subject', 'party', 'mailDate']);

        Livewire::test(GestionCourriers::class)
            ->set('type', '')->set('subject', '')->set('party', '')->set('mailDate', '')
            ->call('saveMail')
            ->assertHasErrors(['type', 'subject', 'party', 'mailDate']);

        $this->assertSame(0, Correspondence::count());
    }

    public function test_la_page_web_accepte_les_longueurs_limites(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(GestionCourriers::class)
            ->set('type', 'entrant')
            ->set('subject', str_repeat('a', 255))
            ->set('party', str_repeat('b', 150))
            ->set('mailDate', '2026-10-02')
            ->call('saveMail')
            ->assertHasNoErrors();

        $this->assertSame(1, Correspondence::count());
    }

    public function test_la_page_web_ne_connait_pas_un_id_inconnu(): void
    {
        $this->actingAs($this->secretaire);

        $this->expectException(ModelNotFoundException::class);
        Livewire::test(GestionCourriers::class)->call('archiveMail', (string) Str::uuid());
    }

    // ── /sync/push ──────────────────────────────────────────────────────────

    public function test_le_poste_cree_un_courrier_avec_son_uuid_et_une_reference_serveur(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->secretaire, $f);

        $this->assertSame([$f['id']], $r->json('mails.accepted'));
        $this->assertSame([], $r->json('mails.rejected'));
        $cree = Correspondence::find($f['id']);
        $this->assertNotNull($cree, "le serveur garde l'UUID du poste");
        $this->assertSame($this->prefixe().'001', $cree->reference);
        $this->assertSame('Convocation PAEB', $cree->subject);
        $this->assertTrue((bool) $cree->is_active);
        $this->assertDatabaseHas('audit_logs', ['action' => 'mail.created']);
        $this->assertSame(0, $r->json('referentiels_ignored'), '`mails` n\'est plus un référentiel ignoré');
    }

    public function test_une_reference_envoyee_par_le_poste_est_ignoree(): void
    {
        $f = $this->fiche(['reference' => 'CR-1999-777']);
        $this->pousser($this->secretaire, $f);

        $this->assertSame($this->prefixe().'001', Correspondence::find($f['id'])->reference);
    }

    public function test_un_renvoi_du_meme_id_modifie_sans_doublon_et_sans_toucher_la_reference(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $r = $this->pousser($this->secretaire, array_merge($f, ['subject' => 'Objet révisé', 'reference' => 'CR-2000-001']));

        $this->assertSame([$f['id']], $r->json('mails.accepted'));
        $this->assertSame(1, Correspondence::count());
        $c = Correspondence::find($f['id']);
        $this->assertSame('Objet révisé', $c->subject);
        $this->assertSame($this->prefixe().'001', $c->reference);
        $this->assertDatabaseHas('audit_logs', ['action' => 'mail.updated']);
    }

    public function test_le_poste_archive_et_le_renvoi_est_un_succes_idempotent(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $archive = ['id' => $f['id'], 'is_active' => false];

        $r1 = $this->pousser($this->secretaire, $archive);
        $r2 = $this->pousser($this->secretaire, $archive);

        $this->assertSame([$f['id']], $r1->json('mails.accepted'));
        $this->assertSame([$f['id']], $r2->json('mails.accepted'));
        $this->assertSame([], $r2->json('mails.rejected'));
        $this->assertFalse((bool) Correspondence::find($f['id'])->is_active);
        $this->assertSame(1, Correspondence::count(), 'archiver ne supprime pas');
        $this->assertSame(1, AuditLog::where('action', 'mail.archived')->count());
    }

    public function test_archiver_un_id_inconnu_est_refuse_avec_motif(): void
    {
        $inconnu = (string) Str::uuid();
        $r = $this->pousser($this->secretaire, ['id' => $inconnu, 'is_active' => false]);

        $this->assertSame([], $r->json('mails.accepted'));
        $this->assertSame($inconnu, $r->json('mails.rejected.0.id'));
        $this->assertStringContainsString('inconnu', $r->json('mails.rejected.0.reason'));
        $this->assertSame(0, Correspondence::count());
    }

    public function test_un_courrier_archive_ne_se_modifie_plus(): void
    {
        $c = $this->courrierExistant($this->prefixe().'001', false);
        $r = $this->pousser($this->secretaire, $this->fiche(['id' => $c->id, 'subject' => 'Tentative']));

        $this->assertSame([], $r->json('mails.accepted'));
        $this->assertStringContainsString('archivé', $r->json('mails.rejected.0.reason'));
        $this->assertSame('Existant', $c->fresh()->subject);
    }

    public function test_sans_le_droit_manage_administration_rien_n_est_ecrit(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->caissier, $f);

        $this->assertSame([], $r->json('mails.accepted'));
        $this->assertSame($f['id'], $r->json('mails.rejected.0.id'));
        $this->assertStringContainsString('rôle', $r->json('mails.rejected.0.reason'));
        $this->assertSame(0, Correspondence::count());
        $this->assertSame(0, AuditLog::where('action', 'mail.created')->count());
    }

    public function test_les_champs_invalides_sont_refuses_avec_motif(): void
    {
        $r = $this->pousser(
            $this->secretaire,
            $this->fiche(['type' => 'interne']),
            $this->fiche(['subject' => str_repeat('a', 256)]),
            $this->fiche(['party' => str_repeat('b', 151)]),
            $this->fiche(['mail_date' => 'demain-peut-etre']),
            $this->fiche(['subject' => '']),
            $this->fiche(['id' => 'pas-un-uuid']),
        );

        $this->assertSame([], $r->json('mails.accepted'));
        $this->assertCount(6, $r->json('mails.rejected'));
        foreach ($r->json('mails.rejected') as $refus) {
            $this->assertNotSame('', trim($refus['reason']));
        }
        $this->assertSame(0, Correspondence::count());
    }

    public function test_un_envoi_partiel_n_empeche_pas_les_autres_et_ne_fait_pas_de_500(): void
    {
        $bon1 = $this->fiche(['subject' => 'Premier']);
        $mauvais = $this->fiche(['type' => 'interne']);
        $bon2 = $this->fiche(['subject' => 'Troisième']);

        $r = $this->pousser($this->secretaire, $bon1, $mauvais, $bon2);

        $this->assertSame([$bon1['id'], $bon2['id']], $r->json('mails.accepted'));
        $this->assertSame([$mauvais['id']], array_column($r->json('mails.rejected'), 'id'));
        $this->assertSame(2, Correspondence::count());
        $this->assertNull(Correspondence::find($mauvais['id']));
    }

    public function test_une_ligne_qui_n_est_pas_un_objet_est_refusee_sans_500(): void
    {
        $r = $this->actingAs($this->secretaire, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            'mails' => ['n-importe-quoi', $this->fiche()],
        ])->assertOk();

        $this->assertCount(1, $r->json('mails.accepted'));
        $this->assertCount(1, $r->json('mails.rejected'));
    }

    public function test_le_poste_obtient_des_references_correctes_au_dela_de_999(): void
    {
        $this->courrierExistant($this->prefixe().'999');
        $f1 = $this->fiche();
        $f2 = $this->fiche();

        $this->pousser($this->secretaire, $f1, $f2);

        $this->assertSame($this->prefixe().'1000', Correspondence::find($f1['id'])->reference);
        $this->assertSame($this->prefixe().'1001', Correspondence::find($f2['id'])->reference);
    }

    // ── Tirage ──────────────────────────────────────────────────────────────

    public function test_le_tirage_sert_reference_is_active_et_date_au_format_jour(): void
    {
        $f = $this->fiche(['mail_date' => '2026-10-01']);
        $this->pousser($this->secretaire, $f);

        $ligne = collect(
            $this->actingAs($this->secretaire, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('mails'),
        )->firstWhere('id', $f['id']);

        $this->assertNotNull($ligne);
        $this->assertSame($this->prefixe().'001', $ligne['reference']);
        $this->assertTrue($ligne['is_active']);
        $this->assertSame('2026-10-01', $ligne['mail_date']);
        $this->assertSame('entrant', $ligne['type']);
        $this->assertNotEmpty($ligne['updated_at']);
    }

    public function test_un_courrier_archive_descend_avec_is_active_faux_depuis_since(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $this->pousser($this->secretaire, ['id' => $f['id'], 'is_active' => false]);

        $depuis = $this->actingAs($this->secretaire, 'sanctum')
            ->getJson('/api/sync/pull?since='.urlencode(now()->subMinute()->toIso8601String()))
            ->assertOk()->json('mails');
        $ligne = collect($depuis)->firstWhere('id', $f['id']);
        $this->assertNotNull($ligne, 'l\'archivage récent descend');
        $this->assertFalse($ligne['is_active']);

        $initial = $this->actingAs($this->secretaire, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('mails');
        $this->assertNull(collect($initial)->firstWhere('id', $f['id']), 'premier tirage : seuls les actifs');
    }

    // ── Ticket 15.25 : lecture sans ambiguïté de `is_active` ────────────────

    public function test_is_active_faux_sous_forme_0_ou_chaine_0_archive_aussi(): void
    {
        foreach ([0, '0'] as $faux) {
            $f = $this->fiche();
            $this->pousser($this->secretaire, $f);
            $r = $this->pousser($this->secretaire, array_merge($f, ['subject' => 'Ne doit pas passer', 'is_active' => $faux]));

            $this->assertSame([$f['id']], $r->json('mails.accepted'));
            $this->assertFalse((bool) Correspondence::find($f['id'])->is_active, 'is_active='.var_export($faux, true));
            $this->assertNotSame('Ne doit pas passer', Correspondence::find($f['id'])->subject, 'un retrait ne lit pas les autres champs');
        }
    }

    public function test_is_active_null_est_traite_comme_absent(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $r = $this->pousser($this->secretaire, array_merge($f, ['subject' => 'Objet révisé', 'is_active' => null]));

        $this->assertSame([$f['id']], $r->json('mails.accepted'));
        $this->assertTrue((bool) Correspondence::find($f['id'])->is_active);
        $this->assertSame('Objet révisé', Correspondence::find($f['id'])->subject);
    }

    public function test_is_active_illisible_est_refuse_avec_motif_sans_rien_ecrire(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);

        foreach (['oui', 'false', 2, []] as $bizarre) {
            $r = $this->pousser($this->secretaire, array_merge($f, ['subject' => 'Ne doit pas passer', 'is_active' => $bizarre]));

            $this->assertSame([], $r->json('mails.accepted'), json_encode($bizarre));
            $this->assertStringContainsString('is_active', $r->json('mails.rejected.0.reason'));
        }
        $this->assertTrue((bool) Correspondence::find($f['id'])->is_active);
        $this->assertNotSame('Ne doit pas passer', Correspondence::find($f['id'])->subject);
    }
}
