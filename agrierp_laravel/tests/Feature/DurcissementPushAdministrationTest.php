<?php

namespace Tests\Feature;

use App\Livewire\Administration\ArchivageDocuments;
use App\Livewire\Administration\DocumentsAdministratifs;
use App\Models\AdministrativeDocument;
use App\Models\ArchivedDocument;
use App\Models\Correspondence;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\CorbeilleService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * Ticket 15.26 — durcissement de `/sync/push` pour courriers, archives et documents
 * administratifs : `is_active` = 1 / "1", longueurs `max:100`, clé d'envoi qui n'est pas une
 * liste, restauration depuis la corbeille.
 */
class DurcissementPushAdministrationTest extends TestCase
{
    use RefreshDatabase;

    private User $secretaire;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-09 15:30:00');
        Permission::findOrCreate('manage-administration', 'web');
        Role::findOrCreate('secretaire', 'web')->givePermissionTo('manage-administration');
        $this->secretaire = User::create([
            'name' => 'Secretaire', 'username' => 'secretaire', 'email' => 'secretaire@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->secretaire->assignRole('secretaire');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function courrier(array $r = []): array
    {
        return array_merge(['id' => (string) Str::uuid(), 'type' => 'entrant', 'subject' => 'Objet', 'party' => 'PAEB', 'mail_date' => '2026-10-01'], $r);
    }

    private function archive(array $r = []): array
    {
        return array_merge(['id' => (string) Str::uuid(), 'title' => 'Titre', 'category' => 'Juridique', 'archived_date' => '2026-09-01', 'expiry_date' => null], $r);
    }

    private function document(array $r = []): array
    {
        return array_merge(['id' => (string) Str::uuid(), 'title' => 'Titre', 'type' => 'Attestation', 'beneficiary' => 'B', 'doc_date' => '2026-10-01', 'status' => 'signe'], $r);
    }

    private function pousser(array $corps)
    {
        return $this->actingAs($this->secretaire, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test'] + $corps);
    }

    // ── is_active = 1 / "1" : pas de retrait, modification acceptée ─────────

    public function test_is_active_1_et_chaine_1_sont_une_modification_sur_les_trois_tables(): void
    {
        $c = $this->courrier();
        $a = $this->archive();
        $d = $this->document();
        $this->pousser(['mails' => [$c], 'archived_documents' => [$a], 'administrative_documents' => [$d]])->assertOk();

        foreach ([1, '1'] as $vrai) {
            $r = $this->pousser([
                'mails' => [array_merge($c, ['subject' => "Révisé $vrai", 'is_active' => $vrai])],
                'archived_documents' => [array_merge($a, ['title' => "Révisé $vrai", 'is_active' => $vrai])],
                'administrative_documents' => [array_merge($d, ['title' => "Révisé $vrai", 'is_active' => $vrai])],
            ])->assertOk();

            $this->assertSame([$c['id']], $r->json('mails.accepted'));
            $this->assertSame([$a['id']], $r->json('archived_documents.accepted'));
            $this->assertSame([$d['id']], $r->json('administrative_documents.accepted'));
            $this->assertTrue((bool) Correspondence::find($c['id'])->is_active);
            $this->assertTrue((bool) ArchivedDocument::find($a['id'])->is_active);
            $this->assertTrue((bool) AdministrativeDocument::find($d['id'])->is_active);
            $this->assertSame("Révisé $vrai", Correspondence::find($c['id'])->subject);
            $this->assertSame("Révisé $vrai", ArchivedDocument::find($a['id'])->title);
            $this->assertSame("Révisé $vrai", AdministrativeDocument::find($d['id'])->title);
        }
    }

    // ── Longueurs ───────────────────────────────────────────────────────────

    public function test_le_push_accepte_100_et_refuse_101_caracteres_pour_type_et_categorie(): void
    {
        $ok = $this->document(['type' => str_repeat('t', 100)]);
        $trop = $this->document(['type' => str_repeat('t', 101)]);
        $okA = $this->archive(['category' => str_repeat('c', 100)]);
        $tropA = $this->archive(['category' => str_repeat('c', 101)]);

        $r = $this->pousser(['administrative_documents' => [$ok, $trop], 'archived_documents' => [$okA, $tropA]])->assertOk();

        $this->assertSame([$ok['id']], $r->json('administrative_documents.accepted'));
        $this->assertSame([$trop['id']], array_column($r->json('administrative_documents.rejected'), 'id'));
        $this->assertNotSame('', trim($r->json('administrative_documents.rejected.0.reason')));
        $this->assertSame([$okA['id']], $r->json('archived_documents.accepted'));
        $this->assertSame([$tropA['id']], array_column($r->json('archived_documents.rejected'), 'id'));
        $this->assertNotSame('', trim($r->json('archived_documents.rejected.0.reason')));
        $this->assertNull(AdministrativeDocument::find($trop['id']));
        $this->assertNull(ArchivedDocument::find($tropA['id']));
    }

    public function test_la_page_web_accepte_100_et_refuse_101_caracteres_pour_type_et_categorie(): void
    {
        $this->actingAs($this->secretaire);

        Livewire::test(DocumentsAdministratifs::class)
            ->set('title', 'T')->set('type', str_repeat('t', 101))->set('beneficiary', 'B')
            ->call('saveDocument')->assertHasErrors(['type']);
        Livewire::test(DocumentsAdministratifs::class)
            ->set('title', 'T')->set('type', str_repeat('t', 100))->set('beneficiary', 'B')
            ->call('saveDocument')->assertHasNoErrors();

        Livewire::test(ArchivageDocuments::class)
            ->set('title', 'T')->set('category', str_repeat('c', 101))->set('archivedDate', '2026-10-01')
            ->call('saveDocument')->assertHasErrors(['category']);
        Livewire::test(ArchivageDocuments::class)
            ->set('title', 'T')->set('category', str_repeat('c', 100))->set('archivedDate', '2026-10-01')
            ->call('saveDocument')->assertHasNoErrors();

        $this->assertSame(1, AdministrativeDocument::count());
        $this->assertSame(1, ArchivedDocument::count());
    }

    public function test_les_regles_ne_depassent_jamais_la_longueur_des_colonnes(): void
    {
        // Colonnes : mails.subject 255, mails.party 150, archived_documents.title 255 / category 100,
        // administrative_documents.title 255 / type 100 / beneficiary 150.
        $max = fn (array $regles, string $champ) => collect($regles[$champ])->first(fn ($x) => str_starts_with($x, 'max:'));

        $courrier = app(\App\Services\CourrierService::class)->regles();
        $archive = app(\App\Services\ArchiveDocumentService::class)->regles();
        $doc = app(\App\Services\DocumentAdministratifService::class)->regles();

        $this->assertSame('max:255', $max($courrier, 'subject'));
        $this->assertSame('max:150', $max($courrier, 'party'));
        $this->assertSame('max:255', $max($archive, 'title'));
        $this->assertSame('max:100', $max($archive, 'category'));
        $this->assertSame('max:255', $max($doc, 'title'));
        $this->assertSame('max:100', $max($doc, 'type'));
        $this->assertSame('max:150', $max($doc, 'beneficiary'));
    }

    // ── Clé d'envoi qui n'est pas une liste ─────────────────────────────────

    public static function clesDEnvoi(): array
    {
        $cles = [
            'livestock_daily_entries', 'sales', 'stock_adjustments', 'veterinary_records', 'expenses',
            'livestock_reproduction_events', 'purchases', 'attendance_records', 'products', 'suppliers',
            'customers', 'mails', 'archived_documents', 'administrative_documents', 'supplier_payments',
            'purchase_returns', 'supplier_refunds', 'customer_advances', 'advance_imputations',
            // référentiels ignorés
            'product_categories', 'receivables', 'customer_reminders', 'feed_types', 'elevage_numbering',
            'purchase_orders', 'payables', 'employees', 'internships', 'chart_of_accounts', 'fiscal_years',
            'accounting_entries', 'accounting_entry_lines', 'company_settings', 'modules_config', 'roles',
            'users', 'audit_logs', 'notifications', 'lot_revenues', 'animals', 'livestock_species',
            'attestation_templates', 'attestation_counts',
            // Ticket U2 — objectifs de GMQ.
            'growth_standards',
        ];

        $jeux = [];
        foreach ($cles as $cle) {
            foreach (['chaine' => 'x', 'nombre' => 5, 'booleen' => true] as $nom => $valeur) {
                $jeux["$cle ($nom)"] = [$cle, $valeur];
            }
        }

        return $jeux;
    }

    #[DataProvider('clesDEnvoi')]
    public function test_une_cle_qui_n_est_pas_une_liste_ne_donne_jamais_500_et_n_affecte_pas_les_autres(string $cle, mixed $valeur): void
    {
        $bon = $this->courrier();
        $r = $this->pousser([$cle => $valeur, 'mails' => $cle === 'mails' ? $valeur : [$bon]]);

        $r->assertOk();
        $this->assertNotEmpty($r->json("cles_invalides.$cle"), 'la clé fautive est signalée avec un motif');
        if ($cle !== 'mails') {
            $this->assertSame([$bon['id']], $r->json('mails.accepted'), 'les autres clés sont traitées');
            $this->assertNotNull(Correspondence::find($bon['id']));
        }
    }

    public function test_une_cle_valide_ne_produit_aucune_cle_invalide(): void
    {
        $r = $this->pousser(['mails' => [$this->courrier()]])->assertOk();

        $this->assertSame([], $r->json('cles_invalides'));
    }

    // ── Corbeille : la restauration est visible au tirage ───────────────────

    public function test_restaurer_un_document_administratif_le_remet_actif_et_le_tirage_depuis_since_le_sert(): void
    {
        $d = $this->document();
        $this->pousser(['administrative_documents' => [$d]])->assertOk();
        $this->pousser(['administrative_documents' => [['id' => $d['id'], 'is_active' => false]]])->assertOk();

        Carbon::setTestNow('2026-10-09 16:30:00');
        $this->assertTrue(app(CorbeilleService::class)->restaurer('documents', $d['id']));

        $modele = AdministrativeDocument::find($d['id']);
        $this->assertTrue((bool) $modele->is_active);
        $this->assertSame('2026-10-09 16:30:00', $modele->updated_at->format('Y-m-d H:i:s'), 'updated_at avance à la restauration');

        $depuis = $this->actingAs($this->secretaire, 'sanctum')
            ->getJson('/api/sync/pull?since='.urlencode(Carbon::parse('2026-10-09 16:00:00')->toIso8601String()))
            ->assertOk()->json('administrative_documents');
        $ligne = collect($depuis)->firstWhere('id', $d['id']);
        $this->assertNotNull($ligne);
        $this->assertTrue($ligne['is_active']);
    }
}
