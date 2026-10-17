<?php

namespace Tests\Feature;

use App\Livewire\Administration\DocumentsAdministratifs;
use App\Models\AdministrativeDocument;
use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\DocumentAdministratifService;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.25 — documents administratifs : service partagé `DocumentAdministratifService`,
 * page web (`DocumentsAdministratifs`) ET `/sync/push` (table `administrative_documents`).
 */
class DocumentsAdministratifsTest extends TestCase
{
    use RefreshDatabase;

    private const AUJOURDHUI = '2026-10-09 15:30:00';

    private User $secretaire;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow(self::AUJOURDHUI);

        Permission::findOrCreate('manage-administration', 'web');
        Role::findOrCreate('secretaire', 'web')->givePermissionTo('manage-administration');
        Role::findOrCreate('caissier', 'web');

        foreach (['secretaire', 'caissier'] as $role) {
            $u = User::create([
                'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@olouwachegoun.bj',
                'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
            ]);
            $u->assignRole($role);
            $this->{$role} = $u;
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function fiche(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'title' => 'Attestation de travail',
            'type' => 'Attestation',
            'beneficiary' => 'Koffi Adjovi',
            'doc_date' => '2026-10-01',
            'status' => 'signe',
            'is_active' => true,
        ], $remplace);
    }

    private function pousser(User $u, ...$fiches): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            'administrative_documents' => $fiches,
        ])->assertOk();
    }

    private function documentExistant(bool $actif = true, string $titre = 'Existant', string $statut = 'en_attente'): AdministrativeDocument
    {
        $d = new AdministrativeDocument();
        $d->fill([
            'title' => $titre, 'type' => 'Certificat', 'beneficiary' => 'Tout le personnel',
            'doc_date' => '2026-01-05', 'status' => $statut, 'is_active' => $actif,
        ]);
        $d->save();

        return $d;
    }

    // ── Page web ────────────────────────────────────────────────────────────

    public function test_la_page_web_enregistre_un_document_avec_son_audit(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(DocumentsAdministratifs::class)
            ->set('title', 'Note de service')
            ->set('type', 'Note interne')
            ->set('beneficiary', 'Tout le personnel')
            ->set('docDate', '2026-10-02')
            ->set('status', 'signe')
            ->call('saveDocument')
            ->assertHasNoErrors();

        $d = AdministrativeDocument::firstWhere('title', 'Note de service');
        $this->assertNotNull($d);
        $this->assertSame('Note interne', $d->type);
        $this->assertSame('Tout le personnel', $d->beneficiary);
        $this->assertSame('2026-10-02', $d->doc_date->format('Y-m-d'));
        $this->assertSame('signe', $d->status);
        $this->assertTrue((bool) $d->is_active);
        $this->assertSame(1, AuditLog::where('action', 'administrative_document.created')->count());
    }

    public function test_la_page_web_prend_en_attente_par_defaut(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(DocumentsAdministratifs::class)
            ->set('title', 'Lettre')->set('type', 'Correspondance')->set('beneficiary', 'Mairie')
            ->call('saveDocument')->assertHasNoErrors();

        $this->assertSame('en_attente', AdministrativeDocument::firstWhere('title', 'Lettre')->status);
    }

    public function test_la_page_web_modifie_sans_doublon_et_avec_son_audit(): void
    {
        $this->actingAs($this->secretaire);
        $d = $this->documentExistant();

        Livewire::test(DocumentsAdministratifs::class)
            ->call('editDocument', $d->id)
            ->set('title', 'Titre corrigé')
            ->set('status', 'signe')
            ->call('saveDocument')
            ->assertHasNoErrors();

        $this->assertSame('Titre corrigé', $d->fresh()->title);
        $this->assertSame('signe', $d->fresh()->status);
        $this->assertSame(1, AdministrativeDocument::count());
        $this->assertSame(1, AuditLog::where('action', 'administrative_document.updated')->count());
    }

    public function test_la_page_web_retire_sans_rien_effacer_et_sans_doubler_l_audit(): void
    {
        $this->actingAs($this->secretaire);
        $d = $this->documentExistant();

        Livewire::test(DocumentsAdministratifs::class)->call('archiveDocument', $d->id);
        Livewire::test(DocumentsAdministratifs::class)->call('archiveDocument', $d->id);

        $this->assertFalse((bool) $d->fresh()->is_active);
        $this->assertSame(1, AdministrativeDocument::count(), 'retirer ne supprime pas');
        $this->assertSame(1, AuditLog::where('action', 'administrative_document.archived')->count(), 'déjà retiré : succès sans nouvelle trace');
    }

    public function test_la_page_web_refuse_un_role_sans_le_droit(): void
    {
        $this->actingAs($this->caissier);
        $d = $this->documentExistant();

        Livewire::test(DocumentsAdministratifs::class)
            ->set('title', 'T')->set('type', 'Certificat')->set('beneficiary', 'B')
            ->call('saveDocument')->assertForbidden();
        Livewire::test(DocumentsAdministratifs::class)->call('archiveDocument', $d->id)->assertForbidden();

        $this->assertSame(1, AdministrativeDocument::count());
        $this->assertTrue((bool) $d->fresh()->is_active);
    }

    public function test_la_page_web_refuse_les_champs_invalides(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(DocumentsAdministratifs::class)
            ->set('title', str_repeat('a', 256))
            ->set('type', '')
            ->set('beneficiary', str_repeat('b', 151))
            ->set('docDate', 'pas-une-date')
            ->set('status', 'archive')
            ->call('saveDocument')
            ->assertHasErrors(['title', 'type', 'beneficiary', 'docDate', 'status']);

        Livewire::test(DocumentsAdministratifs::class)
            ->set('title', '')->set('type', 'Certificat')->set('beneficiary', '')->set('docDate', '')
            ->call('saveDocument')
            ->assertHasErrors(['title', 'beneficiary', 'docDate']);

        $this->assertSame(0, AdministrativeDocument::count());
    }

    public function test_la_page_web_refuse_un_statut_vide(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(DocumentsAdministratifs::class)
            ->set('title', 'T')->set('type', 'Certificat')->set('beneficiary', 'B')->set('status', '')
            ->call('saveDocument')
            ->assertHasErrors(['status']);

        $this->assertSame(0, AdministrativeDocument::count());
    }

    public function test_la_page_web_accepte_les_longueurs_limites(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(DocumentsAdministratifs::class)
            ->set('title', str_repeat('a', 255))->set('type', 'Attestation')->set('beneficiary', str_repeat('b', 150))
            ->call('saveDocument')->assertHasNoErrors();

        $this->assertSame(1, AdministrativeDocument::count());
    }

    public function test_la_page_web_ne_connait_pas_un_id_inconnu(): void
    {
        $this->actingAs($this->secretaire);

        $this->expectException(ModelNotFoundException::class);
        Livewire::test(DocumentsAdministratifs::class)->call('archiveDocument', (string) Str::uuid());
    }

    // ── /sync/push ──────────────────────────────────────────────────────────

    public function test_le_poste_enregistre_un_document_avec_son_uuid(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->secretaire, $f);

        $this->assertSame([$f['id']], $r->json('administrative_documents.accepted'));
        $this->assertSame([], $r->json('administrative_documents.rejected'));
        $cree = AdministrativeDocument::find($f['id']);
        $this->assertNotNull($cree, "le serveur garde l'UUID du poste");
        $this->assertSame('Attestation de travail', $cree->title);
        $this->assertSame('Attestation', $cree->type);
        $this->assertSame('Koffi Adjovi', $cree->beneficiary);
        $this->assertSame('2026-10-01', $cree->doc_date->format('Y-m-d'));
        $this->assertSame('signe', $cree->status);
        $this->assertTrue((bool) $cree->is_active);
        $this->assertSame(1, AuditLog::where('action', 'administrative_document.created')->count());
        $this->assertSame(0, $r->json('referentiels_ignored'), '`administrative_documents` n\'est plus un référentiel ignoré');
    }

    public function test_sans_statut_un_document_cree_est_en_attente(): void
    {
        $f = $this->fiche();
        unset($f['status']);
        $r = $this->pousser($this->secretaire, $f);

        $this->assertSame([$f['id']], $r->json('administrative_documents.accepted'));
        $this->assertSame('en_attente', AdministrativeDocument::find($f['id'])->status);

        $g = $this->fiche(['status' => null]);
        $this->assertSame([$g['id']], $this->pousser($this->secretaire, $g)->json('administrative_documents.accepted'));
        $this->assertSame('en_attente', AdministrativeDocument::find($g['id'])->status);

        // Laravel convertit '' en null avant le contrôleur : un statut vide vaut un statut absent.
        $h = $this->fiche(['status' => '']);
        $this->assertSame([$h['id']], $this->pousser($this->secretaire, $h)->json('administrative_documents.accepted'));
        $this->assertSame('en_attente', AdministrativeDocument::find($h['id'])->status);
    }

    public function test_une_modification_sans_statut_garde_le_statut_existant(): void
    {
        $d = $this->documentExistant(true, 'Existant', 'signe');
        $f = $this->fiche(['id' => $d->id, 'title' => 'Titre révisé']);
        unset($f['status']);
        $r = $this->pousser($this->secretaire, $f);

        $this->assertSame([$d->id], $r->json('administrative_documents.accepted'));
        $this->assertSame('Titre révisé', $d->fresh()->title);
        $this->assertSame('signe', $d->fresh()->status, 'un statut absent ne rétrograde pas un document signé');
    }

    public function test_un_renvoi_du_meme_id_modifie_sans_doublon(): void
    {
        $f = $this->fiche(['status' => 'en_attente']);
        $this->pousser($this->secretaire, $f);
        $r = $this->pousser($this->secretaire, array_merge($f, ['title' => 'Titre révisé', 'status' => 'signe']));

        $this->assertSame([$f['id']], $r->json('administrative_documents.accepted'));
        $this->assertSame(1, AdministrativeDocument::count());
        $d = AdministrativeDocument::find($f['id']);
        $this->assertSame('Titre révisé', $d->title);
        $this->assertSame('signe', $d->status);
        $this->assertSame(1, AuditLog::where('action', 'administrative_document.updated')->count());
    }

    public function test_le_poste_retire_et_le_renvoi_est_un_succes_idempotent(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $retrait = ['id' => $f['id'], 'is_active' => false];

        $r1 = $this->pousser($this->secretaire, $retrait);
        $r2 = $this->pousser($this->secretaire, $retrait);

        $this->assertSame([$f['id']], $r1->json('administrative_documents.accepted'));
        $this->assertSame([$f['id']], $r2->json('administrative_documents.accepted'));
        $this->assertSame([], $r2->json('administrative_documents.rejected'));
        $this->assertFalse((bool) AdministrativeDocument::find($f['id'])->is_active);
        $this->assertSame(1, AdministrativeDocument::count(), 'retirer ne supprime pas');
        $this->assertSame(1, AuditLog::where('action', 'administrative_document.archived')->count(), 'une seule trace pour le retrait');
    }

    public function test_retirer_un_id_inconnu_est_refuse_avec_motif(): void
    {
        $inconnu = (string) Str::uuid();
        $r = $this->pousser($this->secretaire, ['id' => $inconnu, 'is_active' => false]);

        $this->assertSame([], $r->json('administrative_documents.accepted'));
        $this->assertSame($inconnu, $r->json('administrative_documents.rejected.0.id'));
        $this->assertStringContainsString('inconnu', $r->json('administrative_documents.rejected.0.reason'));
        $this->assertSame(0, AdministrativeDocument::count());
        $this->assertSame(0, AuditLog::where('action', 'administrative_document.archived')->count());
    }

    public function test_un_document_retire_ne_se_modifie_plus(): void
    {
        $d = $this->documentExistant(false);
        $r = $this->pousser($this->secretaire, $this->fiche(['id' => $d->id, 'title' => 'Tentative']));

        $this->assertSame([], $r->json('administrative_documents.accepted'));
        $this->assertStringContainsString('retiré', $r->json('administrative_documents.rejected.0.reason'));
        $this->assertSame('Existant', $d->fresh()->title);
        $this->assertFalse((bool) $d->fresh()->is_active);
    }

    public function test_sans_le_droit_manage_administration_rien_n_est_ecrit(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->caissier, $f);

        $this->assertSame([], $r->json('administrative_documents.accepted'));
        $this->assertSame($f['id'], $r->json('administrative_documents.rejected.0.id'));
        $this->assertStringContainsString('rôle', $r->json('administrative_documents.rejected.0.reason'));
        $this->assertSame(0, AdministrativeDocument::count());
        $this->assertSame(0, AuditLog::where('action', 'administrative_document.created')->count());

        // Même refus pour un retrait et pour une modification.
        $d = $this->documentExistant();
        $this->pousser($this->caissier, ['id' => $d->id, 'is_active' => false]);
        $this->assertTrue((bool) $d->fresh()->is_active);
        $this->pousser($this->caissier, $this->fiche(['id' => $d->id, 'title' => 'Piraté']));
        $this->assertSame('Existant', $d->fresh()->title);
    }

    public function test_les_champs_invalides_sont_refuses_avec_motif(): void
    {
        $r = $this->pousser(
            $this->secretaire,
            $this->fiche(['title' => str_repeat('a', 256)]),
            $this->fiche(['title' => '']),
            $this->fiche(['type' => '']),
            $this->fiche(['beneficiary' => str_repeat('b', 151)]),
            $this->fiche(['beneficiary' => '']),
            $this->fiche(['doc_date' => 'bientot']),
            $this->fiche(['doc_date' => null]),
            $this->fiche(['status' => 'archive']),
            $this->fiche(['id' => 'pas-un-uuid']),
        );

        $this->assertSame([], $r->json('administrative_documents.accepted'));
        $this->assertCount(9, $r->json('administrative_documents.rejected'));
        foreach ($r->json('administrative_documents.rejected') as $refus) {
            $this->assertNotSame('', trim($refus['reason']));
        }
        $this->assertSame(0, AdministrativeDocument::count());
    }

    public function test_les_longueurs_limites_sont_acceptees(): void
    {
        $f = $this->fiche(['title' => str_repeat('a', 255), 'beneficiary' => str_repeat('b', 150)]);
        $this->assertSame([$f['id']], $this->pousser($this->secretaire, $f)->json('administrative_documents.accepted'));
    }

    public function test_un_envoi_partiel_n_empeche_pas_les_autres_et_ne_fait_pas_de_500(): void
    {
        $bon1 = $this->fiche(['title' => 'Premier']);
        $mauvais = $this->fiche(['status' => 'archive']);
        $bon2 = $this->fiche(['title' => 'Troisième']);

        $r = $this->pousser($this->secretaire, $bon1, $mauvais, $bon2);

        $this->assertSame([$bon1['id'], $bon2['id']], $r->json('administrative_documents.accepted'));
        $this->assertSame([$mauvais['id']], array_column($r->json('administrative_documents.rejected'), 'id'));
        $this->assertSame(2, AdministrativeDocument::count());
        $this->assertNull(AdministrativeDocument::find($mauvais['id']));
    }

    public function test_une_ligne_qui_n_est_pas_un_objet_est_refusee_sans_500(): void
    {
        $r = $this->actingAs($this->secretaire, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            'administrative_documents' => ['n-importe-quoi', $this->fiche()],
        ])->assertOk();

        $this->assertCount(1, $r->json('administrative_documents.accepted'));
        $this->assertCount(1, $r->json('administrative_documents.rejected'));
    }

    public function test_la_reponse_porte_toujours_la_cle_meme_sans_envoi(): void
    {
        $r = $this->actingAs($this->secretaire, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test'])->assertOk();

        $this->assertSame(['accepted' => [], 'rejected' => []], $r->json('administrative_documents'));
    }

    public function test_l_audit_du_service_est_le_meme_pour_le_web_et_le_poste(): void
    {
        $service = app(DocumentAdministratifService::class);
        $payload = ['title' => 'A', 'type' => 'Certificat', 'beneficiary' => 'B', 'doc_date' => '2026-10-01', 'status' => 'signe'];
        $d = $service->creer($payload);
        $service->modifier($d, ['title' => 'B'] + $payload);
        $this->assertTrue($service->archiver($d));
        $this->assertFalse($service->archiver($d->fresh()), 'déjà retiré : faux');

        foreach (['created', 'updated', 'archived'] as $suite) {
            $this->assertSame(1, AuditLog::where('action', 'administrative_document.'.$suite)->count());
        }
    }

    // ── Tirage ──────────────────────────────────────────────────────────────

    public function test_le_tirage_sert_les_champs_en_jour_avec_is_active_et_updated_at(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);

        $lignes = collect(
            $this->actingAs($this->secretaire, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('administrative_documents'),
        );
        $ligne = $lignes->firstWhere('id', $f['id']);

        $this->assertNotNull($ligne);
        $this->assertSame('Attestation de travail', $ligne['title']);
        $this->assertSame('Attestation', $ligne['type']);
        $this->assertSame('Koffi Adjovi', $ligne['beneficiary']);
        $this->assertSame('2026-10-01', $ligne['doc_date']);
        $this->assertSame('signe', $ligne['status']);
        $this->assertTrue($ligne['is_active']);
        $this->assertNotEmpty($ligne['updated_at']);
        $this->assertNotFalse(Carbon::parse($ligne['updated_at']));
    }

    public function test_un_document_retire_descend_avec_is_active_faux_depuis_since(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $this->pousser($this->secretaire, ['id' => $f['id'], 'is_active' => false]);

        $depuis = $this->actingAs($this->secretaire, 'sanctum')
            ->getJson('/api/sync/pull?since='.urlencode(now()->subMinute()->toIso8601String()))
            ->assertOk()->json('administrative_documents');
        $ligne = collect($depuis)->firstWhere('id', $f['id']);
        $this->assertNotNull($ligne, 'le retrait récent descend');
        $this->assertFalse($ligne['is_active']);

        $initial = $this->actingAs($this->secretaire, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('administrative_documents');
        $this->assertNull(collect($initial)->firstWhere('id', $f['id']), 'premier tirage : seuls les actifs');
    }

    public function test_les_actifs_descendent_toujours_en_entier_meme_avec_since(): void
    {
        $ancien = $this->documentExistant(true, 'Ancien actif');
        AdministrativeDocument::whereKey($ancien->id)->update(['updated_at' => now()->subYear()]);

        $depuis = $this->actingAs($this->secretaire, 'sanctum')
            ->getJson('/api/sync/pull?since='.urlencode(now()->subMinute()->toIso8601String()))
            ->assertOk()->json('administrative_documents');

        $this->assertNotNull(collect($depuis)->firstWhere('id', $ancien->id), 'actif non modifié depuis since : servi quand même');
    }

    public function test_un_retire_ancien_ne_redescend_pas_apres_since(): void
    {
        $ancien = $this->documentExistant(false, 'Ancien retiré');
        AdministrativeDocument::whereKey($ancien->id)->update(['updated_at' => now()->subYear()]);

        $depuis = $this->actingAs($this->secretaire, 'sanctum')
            ->getJson('/api/sync/pull?since='.urlencode(now()->subMinute()->toIso8601String()))
            ->assertOk()->json('administrative_documents');

        $this->assertNull(collect($depuis)->firstWhere('id', $ancien->id));
    }

    // ── Lecture sans ambiguïté de `is_active` (même règle que mails et archived_documents) ──

    public function test_is_active_faux_sous_forme_0_ou_chaine_0_retire_aussi(): void
    {
        foreach ([0, '0'] as $faux) {
            $f = $this->fiche();
            $this->pousser($this->secretaire, $f);
            $r = $this->pousser($this->secretaire, array_merge($f, ['title' => 'Ne doit pas passer', 'is_active' => $faux]));

            $this->assertSame([$f['id']], $r->json('administrative_documents.accepted'));
            $this->assertFalse((bool) AdministrativeDocument::find($f['id'])->is_active, 'is_active='.var_export($faux, true));
            $this->assertNotSame('Ne doit pas passer', AdministrativeDocument::find($f['id'])->title, 'un retrait ne lit pas les autres champs');
        }
    }

    public function test_is_active_null_est_traite_comme_absent(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $r = $this->pousser($this->secretaire, array_merge($f, ['title' => 'Titre révisé', 'is_active' => null]));

        $this->assertSame([$f['id']], $r->json('administrative_documents.accepted'));
        $this->assertTrue((bool) AdministrativeDocument::find($f['id'])->is_active);
        $this->assertSame('Titre révisé', AdministrativeDocument::find($f['id'])->title);
    }

    public function test_is_active_illisible_est_refuse_avec_motif_sans_rien_ecrire(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);

        foreach (['oui', 'false', 2, []] as $bizarre) {
            $r = $this->pousser($this->secretaire, array_merge($f, ['title' => 'Ne doit pas passer', 'is_active' => $bizarre]));

            $this->assertSame([], $r->json('administrative_documents.accepted'), json_encode($bizarre));
            $this->assertStringContainsString('is_active', $r->json('administrative_documents.rejected.0.reason'));
        }
        $this->assertTrue((bool) AdministrativeDocument::find($f['id'])->is_active);
        $this->assertNotSame('Ne doit pas passer', AdministrativeDocument::find($f['id'])->title);
    }
}
