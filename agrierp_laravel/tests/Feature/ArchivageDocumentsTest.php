<?php

namespace Tests\Feature;

use App\Livewire\Administration\ArchivageDocuments;
use App\Models\ArchivedDocument;
use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\ArchiveDocumentService;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.24 — archivage des documents : statut d'échéance (défaut Carbon 3 corrigé),
 * service partagé `ArchiveDocumentService`, page web (`ArchivageDocuments`) ET `/sync/push`
 * (table `archived_documents`).
 */
class ArchivageDocumentsTest extends TestCase
{
    use RefreshDatabase;

    private const AUJOURDHUI = '2026-10-09 15:30:00';

    private User $secretaire;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();

        // Un instant fixe, l'après-midi : c'est là que la différence fractionnaire de Carbon 3
        // (+200 j à 15 h 30 = 199,35 j) trompe un calcul en jours « signés » ou arrondis.
        Carbon::setTestNow(self::AUJOURDHUI);

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

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function fiche(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'title' => 'Registre du Commerce (RCCM)',
            'category' => 'Juridique',
            'archived_date' => '2026-09-01',
            'expiry_date' => '2027-09-01',
            'is_active' => true,
        ], $remplace);
    }

    private function pousser(User $u, array ...$fiches): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            'archived_documents' => $fiches,
        ])->assertOk();
    }

    private function archiveExistante(?string $echeance, bool $actif = true, string $titre = 'Existant'): ArchivedDocument
    {
        $d = new ArchivedDocument();
        $d->fill([
            'title' => $titre, 'category' => 'Fiscal', 'archived_date' => '2026-01-05',
            'expiry_date' => $echeance, 'is_active' => $actif,
        ]);
        $d->save();

        return $d;
    }

    private function dansJours(int $jours): string
    {
        return now()->addDays($jours)->format('Y-m-d');
    }

    // ── Statut d'échéance (défaut Carbon 3) ─────────────────────────────────

    public function test_une_echeance_a_plus_200_jours_est_valide(): void
    {
        $this->assertSame('valide', $this->archiveExistante($this->dansJours(200))->status);
    }

    public function test_une_echeance_a_plus_10_jours_est_bientot_expiree(): void
    {
        $this->assertSame('bientot_expire', $this->archiveExistante($this->dansJours(10))->status);
    }

    public function test_la_borne_de_30_jours_est_incluse_et_31_jours_est_valide(): void
    {
        $this->assertSame(30, ArchivedDocument::SEUIL_BIENTOT_EXPIRE_JOURS);
        $this->assertSame('bientot_expire', $this->archiveExistante($this->dansJours(30))->status);
        $this->assertSame('valide', $this->archiveExistante($this->dansJours(31))->status);
    }

    public function test_la_borne_ne_depend_pas_de_l_heure_de_la_journee(): void
    {
        foreach (['00:00:01', '08:00:00', '12:00:00', '23:59:59'] as $heure) {
            Carbon::setTestNow('2026-10-09 '.$heure);
            $this->assertSame('bientot_expire', ArchivedDocument::statutPour(Carbon::parse('2026-11-08')), "+30 j à $heure");
            $this->assertSame('valide', ArchivedDocument::statutPour(Carbon::parse('2026-11-09')), "+31 j à $heure");
        }
    }

    public function test_une_echeance_aujourd_hui_ou_hier_est_expiree(): void
    {
        // Règle déjà appliquée par le web et par la maquette : une pièce « expire le » jour J
        // n'est plus valable ce jour-là.
        $this->assertSame('expire', $this->archiveExistante($this->dansJours(0))->status);
        $this->assertSame('expire', $this->archiveExistante($this->dansJours(-1))->status);
        $this->assertSame('expire', $this->archiveExistante($this->dansJours(-400))->status);
    }

    public function test_sans_echeance_une_archive_est_valide_et_jamais_expiree(): void
    {
        $ancienne = new ArchivedDocument();
        $ancienne->fill(['title' => 'Titre foncier', 'category' => 'Foncier', 'archived_date' => '2001-01-01', 'expiry_date' => null, 'is_active' => true]);
        $ancienne->save();

        $this->assertSame('valide', $ancienne->status);
        $this->assertSame('valide', ArchivedDocument::statutPour(null));
    }

    public function test_la_carte_expirant_sous_30j_ne_compte_que_les_vraies_echeances_proches(): void
    {
        $this->archiveExistante($this->dansJours(200), true, 'Loin');
        $this->archiveExistante($this->dansJours(10), true, 'Proche');
        $this->archiveExistante($this->dansJours(30), true, 'Borne');
        $this->archiveExistante($this->dansJours(31), true, 'Juste après');
        $this->archiveExistante($this->dansJours(-1), true, 'Périmée');
        $this->archiveExistante(null, true, 'Sans échéance');
        $this->archiveExistante($this->dansJours(5), false, 'Retirée');

        $this->actingAs($this->secretaire);
        $kpis = Livewire::test(ArchivageDocuments::class)->instance()->kpis;

        $this->assertSame(6, $kpis['documents_archives'], 'les retirées ne comptent pas');
        $this->assertSame(2, $kpis['expirant_30j'], 'seuls +10 j et +30 j');
    }

    public function test_le_badge_et_le_filtre_de_la_page_suivent_le_meme_statut(): void
    {
        $this->archiveExistante($this->dansJours(200), true, 'Loin');
        $this->archiveExistante($this->dansJours(10), true, 'Proche');
        $this->archiveExistante($this->dansJours(-3), true, 'Périmée');
        $this->actingAs($this->secretaire);

        $badgeBientot = 'bg-accent-yellow/20 text-brand-forest border-accent-yellow';
        $badgeValide = 'bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30';
        $badgeExpire = 'bg-error-bg text-error-deep border-error-deep/30';

        $page = Livewire::test(ArchivageDocuments::class);
        $html = $page->html();
        // Un seul badge de chaque sorte : un document par statut.
        $this->assertSame(1, substr_count($html, $badgeBientot));
        $this->assertSame(1, substr_count($html, $badgeValide));
        $this->assertSame(1, substr_count($html, $badgeExpire));

        $titres = fn (string $filtre) => Livewire::test(ArchivageDocuments::class)
            ->set('statusFilter', $filtre)->instance()->documents->pluck('title')->all();
        $this->assertSame(['Loin'], $titres('Valide'));
        $this->assertSame(['Proche'], $titres('Bientôt expiré'));
        $this->assertSame(['Périmée'], $titres('Expiré'));
    }

    // ── Page web ────────────────────────────────────────────────────────────

    public function test_la_page_web_archive_un_document_avec_son_audit(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(ArchivageDocuments::class)
            ->set('title', 'Agrément vétérinaire')
            ->set('category', 'Sanitaire')
            ->set('archivedDate', '2026-10-01')
            ->set('expiryDate', '2027-10-01')
            ->call('saveDocument')
            ->assertHasNoErrors();

        $d = ArchivedDocument::firstWhere('title', 'Agrément vétérinaire');
        $this->assertNotNull($d);
        $this->assertSame('Sanitaire', $d->category);
        $this->assertTrue((bool) $d->is_active);
        $this->assertSame('2026-10-01', $d->archived_date->format('Y-m-d'));
        $this->assertSame('2027-10-01', $d->expiry_date->format('Y-m-d'));
        $this->assertSame(1, AuditLog::where('action', 'archived_document.created')->count());
    }

    public function test_la_page_web_accepte_une_archive_sans_echeance(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(ArchivageDocuments::class)
            ->set('title', 'Titre foncier')->set('category', 'Foncier')->set('archivedDate', '2026-10-01')->set('expiryDate', '')
            ->call('saveDocument')->assertHasNoErrors();

        $this->assertNull(ArchivedDocument::firstWhere('title', 'Titre foncier')->expiry_date);
    }

    public function test_la_page_web_modifie_sans_doublon_et_avec_son_audit(): void
    {
        $this->actingAs($this->secretaire);
        $d = $this->archiveExistante('2027-01-01');

        Livewire::test(ArchivageDocuments::class)
            ->call('editDocument', $d->id)
            ->set('title', 'Titre corrigé')
            ->call('saveDocument')
            ->assertHasNoErrors();

        $this->assertSame('Titre corrigé', $d->fresh()->title);
        $this->assertSame(1, ArchivedDocument::count());
        $this->assertSame(1, AuditLog::where('action', 'archived_document.updated')->count());
    }

    public function test_la_page_web_retire_sans_rien_effacer_et_sans_doubler_l_audit(): void
    {
        $this->actingAs($this->secretaire);
        $d = $this->archiveExistante('2027-01-01');

        Livewire::test(ArchivageDocuments::class)->call('deleteDocument', $d->id);
        Livewire::test(ArchivageDocuments::class)->call('deleteDocument', $d->id);

        $this->assertFalse((bool) $d->fresh()->is_active);
        $this->assertSame(1, ArchivedDocument::count(), 'retirer ne supprime pas');
        $this->assertSame(1, AuditLog::where('action', 'archived_document.deleted')->count(), 'déjà retiré : succès sans nouvelle trace');
    }

    public function test_la_page_web_refuse_un_role_sans_le_droit(): void
    {
        $this->actingAs($this->caissier);
        $d = $this->archiveExistante('2027-01-01');

        Livewire::test(ArchivageDocuments::class)
            ->set('title', 'T')->set('category', 'Fiscal')->set('archivedDate', '2026-10-01')
            ->call('saveDocument')->assertForbidden();
        Livewire::test(ArchivageDocuments::class)->call('deleteDocument', $d->id)->assertForbidden();

        $this->assertSame(1, ArchivedDocument::count());
        $this->assertTrue((bool) $d->fresh()->is_active);
    }

    public function test_la_page_web_refuse_les_champs_invalides(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(ArchivageDocuments::class)
            ->set('title', str_repeat('a', 256))
            ->set('category', '')
            ->set('archivedDate', 'pas-une-date')
            ->set('expiryDate', 'jamais')
            ->call('saveDocument')
            ->assertHasErrors(['title', 'category', 'archivedDate', 'expiryDate']);

        Livewire::test(ArchivageDocuments::class)
            ->set('title', '')->set('category', 'Fiscal')->set('archivedDate', '')
            ->call('saveDocument')
            ->assertHasErrors(['title', 'archivedDate']);

        $this->assertSame(0, ArchivedDocument::count());
    }

    public function test_la_page_web_accepte_le_titre_de_255_caracteres(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(ArchivageDocuments::class)
            ->set('title', str_repeat('a', 255))->set('category', 'Autre')->set('archivedDate', '2026-10-01')
            ->call('saveDocument')->assertHasNoErrors();

        $this->assertSame(1, ArchivedDocument::count());
    }

    public function test_la_page_web_refuse_une_echeance_avant_l_archivage(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(ArchivageDocuments::class)
            ->set('title', 'T')->set('category', 'Fiscal')->set('archivedDate', '2026-10-05')->set('expiryDate', '2026-10-04')
            ->call('saveDocument')
            ->assertHasErrors(['expiryDate']);
        $this->assertSame(0, ArchivedDocument::count());

        // Égalité acceptée (`after_or_equal`).
        Livewire::test(ArchivageDocuments::class)
            ->set('title', 'T')->set('category', 'Fiscal')->set('archivedDate', '2026-10-05')->set('expiryDate', '2026-10-05')
            ->call('saveDocument')
            ->assertHasNoErrors();
        $this->assertSame(1, ArchivedDocument::count());
    }

    public function test_la_page_web_ne_connait_pas_un_id_inconnu(): void
    {
        $this->actingAs($this->secretaire);

        $this->expectException(ModelNotFoundException::class);
        Livewire::test(ArchivageDocuments::class)->call('deleteDocument', (string) Str::uuid());
    }

    // ── /sync/push ──────────────────────────────────────────────────────────

    public function test_le_poste_archive_un_document_avec_son_uuid(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->secretaire, $f);

        $this->assertSame([$f['id']], $r->json('archived_documents.accepted'));
        $this->assertSame([], $r->json('archived_documents.rejected'));
        $cree = ArchivedDocument::find($f['id']);
        $this->assertNotNull($cree, "le serveur garde l'UUID du poste");
        $this->assertSame('Registre du Commerce (RCCM)', $cree->title);
        $this->assertSame('2027-09-01', $cree->expiry_date->format('Y-m-d'));
        $this->assertTrue((bool) $cree->is_active);
        $this->assertDatabaseHas('audit_logs', ['action' => 'archived_document.created']);
        $this->assertSame(0, $r->json('referentiels_ignored'), '`archived_documents` n\'est plus un référentiel ignoré');
    }

    public function test_le_poste_archive_sans_echeance(): void
    {
        $f = $this->fiche(['expiry_date' => null]);
        $r = $this->pousser($this->secretaire, $f);

        $this->assertSame([$f['id']], $r->json('archived_documents.accepted'));
        $this->assertNull(ArchivedDocument::find($f['id'])->expiry_date);
    }

    public function test_un_renvoi_du_meme_id_modifie_sans_doublon(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $r = $this->pousser($this->secretaire, array_merge($f, ['title' => 'Titre révisé', 'expiry_date' => '2028-01-01']));

        $this->assertSame([$f['id']], $r->json('archived_documents.accepted'));
        $this->assertSame(1, ArchivedDocument::count());
        $d = ArchivedDocument::find($f['id']);
        $this->assertSame('Titre révisé', $d->title);
        $this->assertSame('2028-01-01', $d->expiry_date->format('Y-m-d'));
        $this->assertDatabaseHas('audit_logs', ['action' => 'archived_document.updated']);
    }

    public function test_le_poste_retire_et_le_renvoi_est_un_succes_idempotent(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $retrait = ['id' => $f['id'], 'is_active' => false];

        $r1 = $this->pousser($this->secretaire, $retrait);
        $r2 = $this->pousser($this->secretaire, $retrait);

        $this->assertSame([$f['id']], $r1->json('archived_documents.accepted'));
        $this->assertSame([$f['id']], $r2->json('archived_documents.accepted'));
        $this->assertSame([], $r2->json('archived_documents.rejected'));
        $this->assertFalse((bool) ArchivedDocument::find($f['id'])->is_active);
        $this->assertSame(1, ArchivedDocument::count(), 'retirer ne supprime pas');
        $this->assertSame(1, AuditLog::where('action', 'archived_document.deleted')->count());
    }

    public function test_retirer_un_id_inconnu_est_refuse_avec_motif(): void
    {
        $inconnu = (string) Str::uuid();
        $r = $this->pousser($this->secretaire, ['id' => $inconnu, 'is_active' => false]);

        $this->assertSame([], $r->json('archived_documents.accepted'));
        $this->assertSame($inconnu, $r->json('archived_documents.rejected.0.id'));
        $this->assertStringContainsString('inconnu', $r->json('archived_documents.rejected.0.reason'));
        $this->assertSame(0, ArchivedDocument::count());
    }

    public function test_un_document_retire_ne_se_modifie_plus(): void
    {
        $d = $this->archiveExistante('2027-01-01', false);
        $r = $this->pousser($this->secretaire, $this->fiche(['id' => $d->id, 'title' => 'Tentative']));

        $this->assertSame([], $r->json('archived_documents.accepted'));
        $this->assertStringContainsString('retiré', $r->json('archived_documents.rejected.0.reason'));
        $this->assertSame('Existant', $d->fresh()->title);
    }

    public function test_sans_le_droit_manage_administration_rien_n_est_ecrit(): void
    {
        $f = $this->fiche();
        $r = $this->pousser($this->caissier, $f);

        $this->assertSame([], $r->json('archived_documents.accepted'));
        $this->assertSame($f['id'], $r->json('archived_documents.rejected.0.id'));
        $this->assertStringContainsString('rôle', $r->json('archived_documents.rejected.0.reason'));
        $this->assertSame(0, ArchivedDocument::count());
        $this->assertSame(0, AuditLog::where('action', 'archived_document.created')->count());

        // Même refus pour un retrait.
        $d = $this->archiveExistante('2027-01-01');
        $this->pousser($this->caissier, ['id' => $d->id, 'is_active' => false]);
        $this->assertTrue((bool) $d->fresh()->is_active);
    }

    public function test_les_champs_invalides_sont_refuses_avec_motif(): void
    {
        $r = $this->pousser(
            $this->secretaire,
            $this->fiche(['title' => str_repeat('a', 256)]),
            $this->fiche(['title' => '']),
            $this->fiche(['category' => '']),
            $this->fiche(['archived_date' => 'bientot']),
            $this->fiche(['archived_date' => null]),
            $this->fiche(['expiry_date' => 'jamais']),
            $this->fiche(['id' => 'pas-un-uuid']),
        );

        $this->assertSame([], $r->json('archived_documents.accepted'));
        $this->assertCount(7, $r->json('archived_documents.rejected'));
        foreach ($r->json('archived_documents.rejected') as $refus) {
            $this->assertNotSame('', trim($refus['reason']));
        }
        $this->assertSame(0, ArchivedDocument::count());
    }

    public function test_une_echeance_avant_l_archivage_est_refusee_avec_motif(): void
    {
        $f = $this->fiche(['archived_date' => '2026-10-05', 'expiry_date' => '2026-10-04']);
        $r = $this->pousser($this->secretaire, $f);

        $this->assertSame([], $r->json('archived_documents.accepted'));
        $this->assertSame($f['id'], $r->json('archived_documents.rejected.0.id'));
        $this->assertNotSame('', trim($r->json('archived_documents.rejected.0.reason')));
        $this->assertNull(ArchivedDocument::find($f['id']));

        $egale = $this->fiche(['archived_date' => '2026-10-05', 'expiry_date' => '2026-10-05']);
        $this->assertSame([$egale['id']], $this->pousser($this->secretaire, $egale)->json('archived_documents.accepted'));
    }

    public function test_un_envoi_partiel_n_empeche_pas_les_autres_et_ne_fait_pas_de_500(): void
    {
        $bon1 = $this->fiche(['title' => 'Premier']);
        $mauvais = $this->fiche(['category' => '']);
        $bon2 = $this->fiche(['title' => 'Troisième']);

        $r = $this->pousser($this->secretaire, $bon1, $mauvais, $bon2);

        $this->assertSame([$bon1['id'], $bon2['id']], $r->json('archived_documents.accepted'));
        $this->assertSame([$mauvais['id']], array_column($r->json('archived_documents.rejected'), 'id'));
        $this->assertSame(2, ArchivedDocument::count());
        $this->assertNull(ArchivedDocument::find($mauvais['id']));
    }

    public function test_une_ligne_qui_n_est_pas_un_objet_est_refusee_sans_500(): void
    {
        $r = $this->actingAs($this->secretaire, 'sanctum')->postJson('/api/sync/push', [
            'device_id' => 'poste-test',
            'archived_documents' => ['n-importe-quoi', $this->fiche()],
        ])->assertOk();

        $this->assertCount(1, $r->json('archived_documents.accepted'));
        $this->assertCount(1, $r->json('archived_documents.rejected'));
    }

    public function test_l_audit_du_service_est_le_meme_pour_le_web_et_le_poste(): void
    {
        $service = app(ArchiveDocumentService::class);
        $d = $service->creer([
            'title' => 'A', 'category' => 'Autre', 'archived_date' => '2026-10-01', 'expiry_date' => null,
        ]);
        $service->modifier($d, ['title' => 'B', 'category' => 'Autre', 'archived_date' => '2026-10-01', 'expiry_date' => null]);
        $this->assertTrue($service->archiver($d));
        $this->assertFalse($service->archiver($d->fresh()), 'déjà retiré : faux');

        foreach (['created', 'updated', 'deleted'] as $suite) {
            $this->assertSame(1, AuditLog::where('action', 'archived_document.'.$suite)->count());
        }
    }

    // ── Tirage ──────────────────────────────────────────────────────────────

    public function test_le_tirage_sert_les_champs_en_jour_avec_is_active_et_updated_at(): void
    {
        $f = $this->fiche(['archived_date' => '2026-09-01', 'expiry_date' => '2027-09-01']);
        $this->pousser($this->secretaire, $f);
        $sans = $this->fiche(['title' => 'Sans échéance', 'expiry_date' => null]);
        $this->pousser($this->secretaire, $sans);

        $lignes = collect(
            $this->actingAs($this->secretaire, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('archived_documents'),
        );
        $ligne = $lignes->firstWhere('id', $f['id']);

        $this->assertNotNull($ligne);
        $this->assertSame('Registre du Commerce (RCCM)', $ligne['title']);
        $this->assertSame('Juridique', $ligne['category']);
        $this->assertSame('2026-09-01', $ligne['archived_date']);
        $this->assertSame('2027-09-01', $ligne['expiry_date']);
        $this->assertTrue($ligne['is_active']);
        $this->assertNotEmpty($ligne['updated_at']);
        $this->assertNull($lignes->firstWhere('id', $sans['id'])['expiry_date']);
        $this->assertArrayNotHasKey('status', $ligne, 'le statut se calcule au poste, il ne descend pas');
    }

    public function test_un_document_retire_descend_avec_is_active_faux_depuis_since(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $this->pousser($this->secretaire, ['id' => $f['id'], 'is_active' => false]);

        $depuis = $this->actingAs($this->secretaire, 'sanctum')
            ->getJson('/api/sync/pull?since='.urlencode(now()->subMinute()->toIso8601String()))
            ->assertOk()->json('archived_documents');
        $ligne = collect($depuis)->firstWhere('id', $f['id']);
        $this->assertNotNull($ligne, 'le retrait récent descend');
        $this->assertFalse($ligne['is_active']);

        $initial = $this->actingAs($this->secretaire, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json('archived_documents');
        $this->assertNull(collect($initial)->firstWhere('id', $f['id']), 'premier tirage : seuls les actifs');
    }

    public function test_les_actifs_descendent_toujours_en_entier_meme_avec_since(): void
    {
        $ancien = $this->archiveExistante('2027-01-01', true, 'Ancien actif');
        ArchivedDocument::whereKey($ancien->id)->update(['updated_at' => now()->subYear()]);

        $depuis = $this->actingAs($this->secretaire, 'sanctum')
            ->getJson('/api/sync/pull?since='.urlencode(now()->subMinute()->toIso8601String()))
            ->assertOk()->json('archived_documents');

        $this->assertNotNull(collect($depuis)->firstWhere('id', $ancien->id), 'actif non modifié depuis since : servi quand même');
    }

    public function test_un_retire_ancien_ne_redescend_pas_apres_since(): void
    {
        $ancien = $this->archiveExistante('2027-01-01', false, 'Ancien retiré');
        ArchivedDocument::whereKey($ancien->id)->update(['updated_at' => now()->subYear()]);

        $depuis = $this->actingAs($this->secretaire, 'sanctum')
            ->getJson('/api/sync/pull?since='.urlencode(now()->subMinute()->toIso8601String()))
            ->assertOk()->json('archived_documents');

        $this->assertNull(collect($depuis)->firstWhere('id', $ancien->id));
    }

    // ── Ticket 15.25 : lecture sans ambiguïté de `is_active` ────────────────

    public function test_is_active_faux_sous_forme_0_ou_chaine_0_retire_aussi(): void
    {
        foreach ([0, '0'] as $faux) {
            $f = $this->fiche();
            $this->pousser($this->secretaire, $f);
            $r = $this->pousser($this->secretaire, array_merge($f, ['title' => 'Ne doit pas passer', 'is_active' => $faux]));

            $this->assertSame([$f['id']], $r->json('archived_documents.accepted'));
            $this->assertFalse((bool) ArchivedDocument::find($f['id'])->is_active, 'is_active='.var_export($faux, true));
            $this->assertNotSame('Ne doit pas passer', ArchivedDocument::find($f['id'])->title, 'un retrait ne lit pas les autres champs');
        }
    }

    public function test_is_active_null_est_traite_comme_absent(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);
        $r = $this->pousser($this->secretaire, array_merge($f, ['title' => 'Titre révisé', 'is_active' => null]));

        $this->assertSame([$f['id']], $r->json('archived_documents.accepted'));
        $this->assertTrue((bool) ArchivedDocument::find($f['id'])->is_active);
        $this->assertSame('Titre révisé', ArchivedDocument::find($f['id'])->title);
    }

    public function test_is_active_illisible_est_refuse_avec_motif_sans_rien_ecrire(): void
    {
        $f = $this->fiche();
        $this->pousser($this->secretaire, $f);

        foreach (['oui', 'false', 2, []] as $bizarre) {
            $r = $this->pousser($this->secretaire, array_merge($f, ['title' => 'Ne doit pas passer', 'is_active' => $bizarre]));

            $this->assertSame([], $r->json('archived_documents.accepted'), json_encode($bizarre));
            $this->assertStringContainsString('is_active', $r->json('archived_documents.rejected.0.reason'));
        }
        $this->assertTrue((bool) ArchivedDocument::find($f['id'])->is_active);
        $this->assertNotSame('Ne doit pas passer', ArchivedDocument::find($f['id'])->title);
    }
}
