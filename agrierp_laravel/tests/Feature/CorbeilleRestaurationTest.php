<?php

namespace Tests\Feature;

use App\Livewire\Parametres\Restauration;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\FeedRationStandard;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\User;
use App\Services\CorbeilleService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.55 (Sprint 14) — CORBEILLE & RESTAURATION.
 *
 * Le projet imposait déjà l'archivage logique, mais **rien ne permettait de
 * revoir ni de restaurer** un enregistrement archivé : en pratique, une archive
 * valait une suppression.
 *
 * Les deux tests qui comptent le plus sont des EXCLUSIONS : une écriture
 * comptable et un compte utilisateur ne doivent jamais pouvoir être « restaurés »
 * depuis une corbeille.
 */
class CorbeilleRestaurationTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private Supplier $fournisseur;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-parametres', 'manage-parametres'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-parametres', 'manage-parametres']);
        Role::findOrCreate('caissier', 'web');

        $this->admin = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');

        $this->fournisseur = Supplier::create([
            'name' => 'Provenderie du Plateau', 'phone' => '+22997000000', 'is_active' => true,
        ]);
    }

    /** Un enregistrement actif n'est pas dans la corbeille. */
    public function test_an_active_record_is_not_in_the_trash(): void
    {
        $this->assertEquals(0, app(CorbeilleService::class)->compte());
    }

    /** Un enregistrement archivé y apparaît, avec un titre lisible. */
    public function test_an_archived_record_appears_with_a_readable_title(): void
    {
        $this->fournisseur->update(['is_active' => false]);

        $elements = app(CorbeilleService::class)->elements();

        $this->assertCount(1, $elements);
        $this->assertEquals('Fournisseur', $elements[0]['libelle_type']);
        // ⚠️ Un UUID seul ne permet pas de décider si l'on veut restaurer.
        $this->assertEquals('Provenderie du Plateau', $elements[0]['titre']);
    }

    /** La restauration remet réellement l'élément en service. */
    public function test_restoring_brings_the_record_back(): void
    {
        $this->fournisseur->update(['is_active' => false]);

        $this->assertTrue(
            app(CorbeilleService::class)->restaurer('fournisseurs', $this->fournisseur->id)
        );

        $this->assertTrue((bool) $this->fournisseur->fresh()->is_active);
        $this->assertEquals(0, app(CorbeilleService::class)->compte());
    }

    /** La restauration se journalise : sinon nul ne peut l'expliquer. */
    public function test_restoring_is_journalled(): void
    {
        $this->fournisseur->update(['is_active' => false]);
        app(CorbeilleService::class)->restaurer('fournisseurs', $this->fournisseur->id);

        $this->assertEquals(1, AuditLog::where('action', 'corbeille.restored')->count());
    }

    /**
     * ⚠️⚠️ L'EXCLUSION LA PLUS IMPORTANTE. Une écriture comptable archivée ne
     * doit JAMAIS apparaître : une écriture ne se supprime pas, elle se
     * contre-passe. La restaurer modifierait un grand livre — possiblement d'un
     * exercice clos — sans contrepartie, et le Bilan cesserait d'être équilibré.
     */
    public function test_an_accounting_entry_never_appears_in_the_trash(): void
    {
        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);
        $compte = ChartOfAccount::create(['code' => '601', 'label' => 'Achats', 'class' => 6, 'is_active' => true]);
        $contre = ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);

        $ecriture = app(\App\Services\AccountingEntryService::class)
            ->recordManual($compte->id, $contre->id, 10_000, now()->format('Y-m-d'), 'OD-TEST');

        $ecriture->update(['is_active' => false]);

        $types = array_column(app(CorbeilleService::class)->elements(), 'type');

        $this->assertNotContains('ecritures', $types);
        $this->assertEquals(1, AccountingEntry::count(), "l'ecriture existe toujours en base");
        $this->assertArrayNotHasKey('ecritures', CorbeilleService::registre());
    }

    /**
     * ⚠️ Un compte utilisateur désactivé n'y figure pas non plus : sa
     * réactivation existe sur son propre écran, avec son contrôle de rôle.
     * L'exposer ici créerait une seconde porte d'entrée.
     */
    public function test_a_user_never_appears_in_the_trash(): void
    {
        $this->admin->update(['is_active' => false]);

        $this->assertEquals(0, app(CorbeilleService::class)->compte());
        $this->assertArrayNotHasKey('utilisateurs', CorbeilleService::registre());
    }

    /**
     * ⚠️ LE TYPE EST VÉRIFIÉ CONTRE LE REGISTRE, jamais interprété comme un nom
     * de classe : accepter une classe fournie par l'appelant permettrait de
     * réactiver n'importe quel modèle, y compris les exclus.
     */
    public function test_an_unknown_type_is_refused(): void
    {
        $this->assertFalse(
            app(CorbeilleService::class)->restaurer('App\\Models\\User', $this->admin->id)
        );
        $this->assertFalse(
            app(CorbeilleService::class)->restaurer('utilisateurs', $this->admin->id)
        );
    }

    /** Restaurer un élément déjà actif échoue plutôt que de mentir. */
    public function test_restoring_an_active_record_fails_rather_than_lying(): void
    {
        $this->assertFalse(
            app(CorbeilleService::class)->restaurer('fournisseurs', $this->fournisseur->id)
        );
    }

    /** Le filtre par type restreint réellement la liste. */
    public function test_the_type_filter_narrows_the_list(): void
    {
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Aliment ponte', 'category_id' => $categorie->id,
            'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 0, 'is_active' => false,
        ]);
        $this->fournisseur->update(['is_active' => false]);

        $service = app(CorbeilleService::class);

        $this->assertCount(2, $service->elements());
        $this->assertCount(1, $service->elements('produits'));
        $this->assertEquals($produit->id, $service->elements('produits')[0]['id']);
    }

    /**
     * ⚠️ AUTORISATION EN PREMIÈRE LIGNE DE LA MÉTHODE QUI ÉCRIT — masquer
     * l'onglet ne suffit pas.
     */
    public function test_a_non_admin_cannot_restore(): void
    {
        $caissier = User::create([
            'name' => 'Caissière', 'username' => 'caisse', 'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');
        $this->actingAs($caissier);

        $this->fournisseur->update(['is_active' => false]);

        // ⚠️ La garde est posée sur la LECTURE comme sur l'ÉCRITURE : le rendu
        // lui-même est refusé, si bien que Livewire ne peut même pas construire
        // son instantané. On vérifie donc la GARANTIE — rien n'est restauré —
        // plutôt que le type d'exception, qui dépend du harnais.
        $refuse = false;

        try {
            Livewire::test(Restauration::class)
                ->call('restaurer', 'fournisseurs', $this->fournisseur->id);
        } catch (\Throwable $e) {
            $refuse = true;
        }

        $this->assertTrue($refuse, "l'ecran doit refuser un non-administrateur");
        $this->assertFalse((bool) $this->fournisseur->fresh()->is_active,
            'le fournisseur reste archive');
        $this->assertEquals(0, AuditLog::where('action', 'corbeille.restored')->count());

        // Et la garde vient bien de la permission, pas d'un hasard.
        $this->assertFalse($caissier->can('manage-parametres'));
    }

    /** L'administrateur, lui, restaure depuis l'écran. */
    public function test_an_admin_restores_from_the_screen(): void
    {
        $this->actingAs($this->admin);
        $this->fournisseur->update(['is_active' => false]);

        Livewire::test(Restauration::class)
            ->call('restaurer', 'fournisseurs', $this->fournisseur->id)
            ->assertDispatched('toast');

        $this->assertTrue((bool) $this->fournisseur->fresh()->is_active);
    }

    /**
     * 🔴→✅ LES QUATRE SUPPRESSIONS PHYSIQUES SONT DEVENUES DES ARCHIVAGES.
     * Une ration effacée disparaissait aussi du poste Desktop au tirage suivant.
     */
    public function test_a_ration_is_archived_and_restorable(): void
    {
        $ration = FeedRationStandard::create([
            'species_code' => 'cuniculture',
            'stage_label' => 'Lapin Sevré',
            'ration_g_per_day' => 30,
            'is_active' => true,
        ]);

        $ration->update(['is_active' => false]);

        $this->assertDatabaseHas('feed_ration_standards', ['id' => $ration->id]);
        $this->assertCount(1, app(CorbeilleService::class)->elements('rations'));

        app(CorbeilleService::class)->restaurer('rations', $ration->id);

        $this->assertTrue((bool) $ration->fresh()->is_active);
    }
}
