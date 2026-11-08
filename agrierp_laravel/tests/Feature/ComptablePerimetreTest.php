<?php

namespace Tests\Feature;

use App\Livewire\Facturation\Facturation;
use App\Livewire\Parametres\DonneesEntreprise;
use App\Livewire\Parametres\GestionUtilisateurs;
use App\Livewire\Parametres\RolesPermissions;
use App\Livewire\Ventes\HistoriqueVentes;
use App\Livewire\Ventes\PosInterface;
use App\Livewire\Ventes\RetoursAvoirs;
use App\Livewire\Ventes\VentesDevisHub;
use App\Models\CreditNote;
use App\Models\Permission;
use App\Models\Role;
use App\Models\Sale;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * Ticket CONF-4 (DV-20) — PÉRIMÈTRE DU COMPTABLE, « LE MÊME QUE DANS AGRIERP » (décision du client, 08/11/2026).
 *
 * Le comptable GÈRE la comptabilité, les exercices, la TVA et les rapports ; LIT les ventes, les achats et les stocks ; CONSULTE
 * et RETRANSMET les factures ; CRÉE des AVOIRS. Il ne peut NI annuler une vente, NI encaisser en caisse, NI gérer l'élevage, les
 * utilisateurs ou les réglages.
 *
 * ⚠️ LE PIÈGE QUE CE TEST PROTÈGE : l'avoir et l'annulation passaient par `manage-ventes`, le droit de la CAISSE. Donner
 * `manage-ventes` au comptable lui aurait ouvert le POS. Le droit fin `correct-invoices` (Gates `avoir-client` et
 * `retransmettre-facture`) sépare la correction de l'encaissement : annulation et caisse restent à `manage-ventes` SEUL.
 *
 * Les rôles viennent du VRAI seeder, jamais d'une liste écrite ici. Garde-fous par mutation : voir les tests « source » en bas
 * (une garde ramenée à `manage-ventes` seul, ou une porte ouverte au comptable, fait rougir au moins un test).
 */
class ComptablePerimetreTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    private User $comptable;

    private User $caissier;

    private User $animalier;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);

        // Décor de ventes (exercice, plan, produits) ; son administrateur de test est remplacé par les vrais comptes.
        $this->decorVentes();
        $this->reglerEmecef();

        $this->admin = $this->compte('admin');
        $this->comptable = $this->compte('comptable');
        $this->caissier = $this->compte('caissier');
        $this->animalier = $this->compte('animalier');
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => 'Compte '.$role, 'username' => 'c-'.$role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function venteNormalisee(): Sale
    {
        $this->fauxEmecefSucces('uid-origine');
        $vente = $this->venteAFacturer();
        app(\App\Services\Mecef\FacturationMecefService::class)->facturer($vente);

        return $vente->fresh();
    }

    private function retourner(string $venteId, float $qte = 1, float $montant = 5900)
    {
        return Livewire::test(RetoursAvoirs::class)
            ->set('saleId', $venteId)->set('productId', $this->taxable->id)->set('qty', $qte)->set('amount', $montant)
            ->set('reason', 'Produit détérioré')->set('decision', 'reintegre')
            ->call('saveReturn');
    }

    /** @return array<int, string> */
    private function droits(string $role): array
    {
        return Role::findByName($role, 'web')->permissions->pluck('name')->sort()->values()->all();
    }

    // ------------------------------------------------------------------ 1. La matrice seedée

    public function test_le_seeder_donne_au_comptable_le_perimetre_de_dv20_et_ne_touche_pas_aux_autres_roles(): void
    {
        $this->assertSame(
            ['close-fiscal-year', 'correct-invoices', 'export-rapports', 'manage-comptabilite', 'view-achats', 'view-comptabilite',
                'view-facturation', 'view-rapports', 'view-stocks', 'view-ventes'],
            $this->droits('comptable'),
        );

        // Aucun droit d'écriture hors comptabilité : ni caisse, ni achats, ni stocks, ni élevage, ni utilisateurs, ni réglages.
        foreach (['manage-ventes', 'manage-achats', 'manage-stocks', 'manage-elevage', 'manage-users', 'manage-parametres',
            'manage-facturation', 'manage-rh', 'manage-administration', 'manage-modules', 'export-ventes', 'view-parametres'] as $interdit) {
            $this->assertFalse($this->comptable->can($interdit), "le comptable ne doit pas avoir {$interdit}");
        }

        // Le nouveau droit existe, l'administrateur a TOUT (Permission::all()), caissier et animalier sont inchangés.
        $this->assertTrue(Permission::where('name', 'correct-invoices')->exists());
        $this->assertTrue($this->admin->can('correct-invoices'));
        $this->assertSame(
            Permission::pluck('name')->sort()->values()->all(),
            $this->droits('admin'),
        );
        // CONF-5 (DV-06) : le caissier lit et réimprime ses factures (`view-facturation`), sans aucun droit d'écriture de facturation.
        $this->assertSame(['export-ventes', 'manage-ventes', 'view-facturation', 'view-ventes'], $this->droits('caissier'));
        $this->assertFalse($this->caissier->can('correct-invoices'));
        $this->assertSame(['archive-elevage', 'export-elevage', 'manage-elevage', 'view-elevage'], $this->droits('animalier'));
        $this->assertFalse($this->animalier->can('correct-invoices'));
    }

    public function test_les_deux_portes_de_correction_s_ouvrent_aux_bons_droits_et_a_eux_seuls(): void
    {
        // Avoir : manage-ventes (caissier) OU correct-invoices (comptable) ; pas l'animalier.
        $this->assertTrue($this->caissier->can('avoir-client'));
        $this->assertTrue($this->comptable->can('avoir-client'));
        $this->assertTrue($this->admin->can('avoir-client'));
        $this->assertFalse($this->animalier->can('avoir-client'));

        // Retransmettre une facture : manage-facturation (admin) OU correct-invoices (comptable) ; ni caissier ni animalier.
        $this->assertTrue($this->admin->can('retransmettre-facture'));
        $this->assertTrue($this->comptable->can('retransmettre-facture'));
        $this->assertFalse($this->caissier->can('retransmettre-facture'));
        $this->assertFalse($this->animalier->can('retransmettre-facture'));
    }

    // ------------------------------------------------------------------ 2. Web : ce que le comptable LIT

    public function test_le_comptable_ouvre_en_lecture_les_ventes_les_achats_les_stocks_la_facturation_et_les_rapports(): void
    {
        $this->actingAs($this->comptable);

        foreach (['/ventes-devis', '/creances-clients', '/achats-commandes', '/fournisseurs', '/saisie-depenses', '/gestion-stocks',
            '/catalogue-produits', '/seuils-alerte', '/facturation', '/rapports-exports', '/rapport-mensuel',
            '/comptabilite-hub', '/dashboard'] as $url) {
            $this->get($url)->assertOk();
        }
    }

    public function test_le_hub_ventes_n_offre_pas_la_caisse_au_comptable_mais_la_lecture(): void
    {
        $this->actingAs($this->comptable);

        $page = $this->get('/ventes-devis')->assertOk();
        $page->assertSee('Historique des Ventes')->assertSee('Devis Prestations')->assertSee('Retours et Avoirs');
        $page->assertDontSee('Enregistrer Vente');

        // Même en forçant l'onglet (URL ou `$set` forgé) : la caisse n'est jamais montée.
        Livewire::test(VentesDevisHub::class)->set('tab', 'vente')
            ->assertSet('tab', 'historique')->assertDontSee('Enregistrer Vente');
        $this->get('/ventes-devis?tab=vente')->assertOk()->assertDontSee('Enregistrer Vente');

        // Le caissier garde la caisse comme premier onglet.
        $this->actingAs($this->caissier);
        $this->get('/ventes-devis')->assertOk()->assertSee('Enregistrer Vente');
    }

    // ------------------------------------------------------------------ 3. Web : ce que le comptable NE PEUT PAS

    public function test_le_comptable_est_refuse_en_caisse_et_ne_peut_pas_annuler_une_vente(): void
    {
        $vente = $this->venteAFacturer([], 0, 'especes', ['facture_type' => 'simple', 'aib_taux' => 'N/A']);
        $this->actingAs($this->comptable);

        Livewire::test(PosInterface::class)->assertForbidden();

        Livewire::test(HistoriqueVentes::class)->set('cancellingSaleId', $vente->id)->call('cancelSale')->assertForbidden();
        $this->assertSame('validee', $vente->fresh()->status, 'la vente n\'est pas annulée');

        // Le caissier, lui, annule toujours (inchangé).
        $this->actingAs($this->caissier);
        Livewire::test(HistoriqueVentes::class)->set('cancellingSaleId', $vente->id)->call('cancelSale')->assertOk();
        $this->assertSame('annulee', $vente->fresh()->status);
    }

    public function test_le_comptable_ne_voit_pas_le_bouton_d_annulation_le_caissier_le_voit(): void
    {
        $this->venteAFacturer([], 0, 'especes', ['facture_type' => 'simple', 'aib_taux' => 'N/A']);

        $this->actingAs($this->comptable);
        Livewire::test(HistoriqueVentes::class)->assertDontSeeHtml('confirmCancel(');

        $this->actingAs($this->caissier);
        Livewire::test(HistoriqueVentes::class)->assertSeeHtml('confirmCancel(');
    }

    public function test_le_comptable_ne_gere_ni_l_elevage_ni_les_utilisateurs_ni_les_reglages_ni_l_inventaire(): void
    {
        $this->actingAs($this->comptable);

        foreach (['/gestion-elevage', '/gestion-bandes', '/parametres-elevage', '/parametres-hub', '/mode-hors-ligne',
            '/importation-masse', '/produits/ajouter', '/personnel-stages', '/administration', '/bareme-its'] as $url) {
            $this->get($url)->assertForbidden();
        }

        Livewire::test(GestionUtilisateurs::class)->assertForbidden();
        Livewire::test(RolesPermissions::class)->assertForbidden();
        Livewire::test(DonneesEntreprise::class)->assertForbidden();
    }

    public function test_le_comptable_lit_les_stocks_sans_pouvoir_les_ajuster(): void
    {
        $this->actingAs($this->comptable);

        $stock = $this->taxable->fresh()->stock_qty;
        Livewire::test(\App\Livewire\Stocks\GestionStocks::class)->assertOk()
            ->call('submitAjouterStock')->assertForbidden();
        Livewire::test(\App\Livewire\Stocks\GestionStocks::class)->call('validateAdjustment')->assertForbidden();
        $this->assertEquals($stock, $this->taxable->fresh()->stock_qty);
    }

    public function test_le_comptable_lit_les_achats_sans_rien_y_ecrire(): void
    {
        $this->actingAs($this->comptable);

        Livewire::test(\App\Livewire\Achats\EnregistrerAchat::class)->call('submitAchat')->assertForbidden();
        Livewire::test(\App\Livewire\Achats\SaisieDepenses::class)->call('submitExpense')->assertForbidden();
    }

    public function test_le_comptable_ne_peut_pas_convertir_un_devis_en_facture_ni_encaisser_une_creance(): void
    {
        $this->actingAs($this->comptable);

        Livewire::test(\App\Livewire\Ventes\Devis::class)->call('convertToInvoice', (string) Str::uuid())->assertForbidden();
        Livewire::test(\App\Livewire\Ventes\SuiviDettes::class)->call('confirmPayment')->assertForbidden();
    }

    // ------------------------------------------------------------------ 4. Web : ce qu'il PEUT (avoir, retransmission)

    public function test_le_comptable_cree_un_avoir_et_le_marque_traite(): void
    {
        $vente = $this->venteAFacturer([], 0, 'especes', ['facture_type' => 'simple', 'aib_taux' => 'N/A']);
        $this->actingAs($this->comptable);

        $this->retourner($vente->id)->assertHasNoErrors();

        $avoir = CreditNote::firstOrFail();
        $this->assertSame('en_attente', $avoir->status);
        $this->assertNotNull($avoir->accounting_entry_id, 'l\'avoir est comptabilisé comme au caissier');
        $this->assertEquals(101, $this->taxable->fresh()->stock_qty, 'produit réintégré');

        Livewire::test(RetoursAvoirs::class)->call('markAsTreated', $avoir->id);
        $this->assertSame('traite', $avoir->fresh()->status);
    }

    public function test_le_comptable_retransmet_la_facture_d_une_vente_et_la_facture_d_avoir(): void
    {
        // Facture normalisée refusée par la DGI : elle reste en attente, le comptable la retransmet depuis « Facturation ».
        Http::fake([self::URL.'/*' => Http::response('', 503)]);
        $vente = $this->venteAFacturer();
        app(\App\Services\Mecef\FacturationMecefService::class)->facturer($vente);
        $this->assertNotSame('transmise', $vente->fresh()->mecef_status);

        Http::swap(new \Illuminate\Http\Client\Factory);
        $this->fauxEmecefSucces('uid-retransmis');
        $this->actingAs($this->comptable);
        Livewire::test(Facturation::class)->call('retryMecef', $vente->id)
            ->assertDispatched('toast', fn ($n, $p) => $p['type'] === 'success');
        $this->assertSame('transmise', $vente->fresh()->mecef_status);

        // Facture d'avoir en échec : le comptable la retransmet depuis « Retours et Avoirs ».
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake([self::URL.'/*' => Http::response('', 503)]);
        $this->retourner($vente->id)->assertHasNoErrors();
        $avoir = CreditNote::firstOrFail();
        $this->assertSame('en_attente', $avoir->mecef_status);

        Http::swap(new \Illuminate\Http\Client\Factory);
        $this->fauxEmecefSucces('uid-avoir');
        Livewire::test(RetoursAvoirs::class)->call('retryMecef', $avoir->id)
            ->assertDispatched('toast', fn ($n, $p) => $p['type'] === 'success');
        $this->assertSame('transmise', $avoir->fresh()->mecef_status);
    }

    public function test_le_caissier_n_a_pas_gagne_la_retransmission_des_factures_et_le_comptable_ne_gagne_pas_la_conversion_des_devis(): void
    {
        $vente = $this->venteAFacturer();

        $this->actingAs($this->caissier);
        Livewire::test(Facturation::class)->call('retryMecef', $vente->id)->assertForbidden();

        // Convertir un devis exige `manage-ventes` ET `manage-facturation` : ni l'un ni l'autre n'est donné au comptable.
        $this->assertFalse($this->comptable->can('manage-facturation'));
        $this->assertFalse($this->comptable->can('manage-ventes'));
    }

    // ------------------------------------------------------------------ 5. API de synchronisation

    /** @return array<int, string> */
    private function tirees(User $u): array
    {
        return \App\Http\Controllers\Api\SyncController::tablesServies($u);
    }

    public function test_le_tirage_sert_au_comptable_les_tables_de_lecture_dont_il_a_le_droit_et_rien_de_plus(): void
    {
        $servies = $this->tirees($this->comptable);

        foreach (['quotes', 'credit_notes', 'customer_advances', 'customer_reminders', 'purchase_orders', 'supplier_credits',
            'expense_categories', 'stock_movements', 'sales', 'sale_lines', 'purchases', 'accounting_entries', 'fixed_assets'] as $table) {
            $this->assertContains($table, $servies, "le comptable doit recevoir {$table}");
        }

        foreach (['employees', 'mails', 'permissions', 'corbeille', 'livestock_transfers', 'veterinary_records', 'internships'] as $table) {
            $this->assertNotContains($table, $servies, "le comptable ne doit pas recevoir {$table}");
        }

        // Le caissier ne reçoit toujours ni le journal ni les achats détaillés (inchangé).
        $this->assertNotContains('accounting_entries', $this->tirees($this->caissier));
        $this->assertNotContains('purchase_orders', $this->tirees($this->caissier));
    }

    private function pousser(User $u, array $corps)
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test'] + $corps)->assertOk();
    }

    private function avoirPoste(Sale $vente): array
    {
        return [
            'id' => (string) Str::uuid(), 'sale_id' => $vente->id, 'product_id' => $this->taxable->id, 'qty' => 1, 'amount' => 5900,
            'reason' => 'Retour du poste', 'decision' => 'reintegre', 'status' => 'en_attente', 'credit_date' => now()->toDateString(),
        ];
    }

    public function test_l_avoir_envoye_par_le_poste_du_comptable_est_accepte_celui_de_l_animalier_refuse(): void
    {
        $vente = $this->venteAFacturer([], 0, 'especes', ['facture_type' => 'simple', 'aib_taux' => 'N/A']);

        $avoir = $this->avoirPoste($vente);
        $this->pousser($this->comptable, ['credit_notes' => [$avoir]])->assertJsonPath('credit_notes.accepted.0', $avoir['id']);
        $this->assertSame(1, CreditNote::count());

        $refuse = $this->avoirPoste($vente);
        $r = $this->pousser($this->animalier, ['credit_notes' => [$refuse]]);
        $this->assertSame([], $r->json('credit_notes.accepted'));
        $this->assertStringContainsString('ne permet pas', $r->json('credit_notes.rejected.0.reason'));
        $this->assertSame(1, CreditNote::count(), 'rien d\'écrit pour l\'animalier');
    }

    public function test_une_annulation_de_vente_venant_du_comptable_est_refusee_avec_un_motif_francais(): void
    {
        $vente = $this->venteAFacturer([], 0, 'especes', ['facture_type' => 'simple', 'aib_taux' => 'N/A']);

        $r = $this->pousser($this->comptable, ['sales' => [[
            'id' => $vente->id, 'status' => 'annulee', 'customer_id' => $vente->customer_id, 'payment_mode' => 'especes',
            'subtotal' => 11800, 'discount' => 0, 'total' => 11800, 'lines' => [],
        ]]]);

        $this->assertSame([], $r->json('sales.accepted'));
        $motif = $r->json('sales.rejected.0.reason');
        $this->assertStringContainsString("ne permet pas d'annuler une vente", $motif);
        $this->assertStringContainsString('avoir', $motif);
        $this->assertSame('validee', $vente->fresh()->status);
        $this->assertSame(0, (int) DB::table('stock_movements')->where('reference_type', 'like', '%annul%')->count());

        // Une vente ordinaire (non annulée) venant du comptable reçoit le refus général « enregistrer une vente ».
        $r = $this->pousser($this->comptable, ['sales' => [[
            'id' => (string) Str::uuid(), 'status' => 'validee', 'payment_mode' => 'especes', 'subtotal' => 100, 'total' => 100, 'lines' => [],
        ]]]);
        $this->assertStringContainsString('enregistrer une vente', $r->json('sales.rejected.0.reason'));
    }

    // ------------------------------------------------------------------ 6. Migration (bases déjà déployées)

    private function migration(): object
    {
        return require database_path('migrations/2026_11_08_000002_accorder_perimetre_comptable_conf4.php');
    }

    public function test_la_migration_accorde_le_perimetre_aux_roles_existants_sans_rien_retirer_et_se_rejoue_sans_effet(): void
    {
        // Base « de production » d'avant CONF-4 : le droit fin n'existe pas, le comptable n'a que la comptabilité et les rapports.
        $avant = ['view-comptabilite', 'manage-comptabilite', 'close-fiscal-year', 'view-rapports', 'export-rapports'];
        Role::findByName('comptable', 'web')->syncPermissions($avant);
        Role::findByName('admin', 'web')->revokePermissionTo('correct-invoices');
        Permission::where('name', 'correct-invoices')->delete();
        $caissierAvant = $this->droits('caissier');
        $animalierAvant = $this->droits('animalier');
        // Un droit ajouté à la main par l'administrateur à ce comptable : il ne doit JAMAIS être retiré.
        Permission::findOrCreate('manage-rh', 'web');
        Role::findByName('comptable', 'web')->givePermissionTo('manage-rh');
        $this->assertFalse(Permission::where('name', 'correct-invoices')->exists());

        $this->migration()->up();

        $comptable = $this->droits('comptable');
        $this->assertSame(
            collect([...$avant, 'manage-rh', 'view-ventes', 'view-achats', 'view-stocks', 'view-facturation', 'correct-invoices'])->sort()->values()->all(),
            $comptable,
        );
        $this->assertTrue(Role::findByName('admin', 'web')->hasPermissionTo('correct-invoices'));
        $this->assertSame($caissierAvant, $this->droits('caissier'), 'caissier inchangé');
        $this->assertSame($animalierAvant, $this->droits('animalier'), 'animalier inchangé');

        // Rejouée : aucun changement, aucun doublon.
        $this->migration()->up();
        $this->assertSame($comptable, $this->droits('comptable'));
        $this->assertSame(1, Permission::where('name', 'correct-invoices')->count());
        $this->assertSame(1, DB::table('role_has_permissions')
            ->where('role_id', Role::findByName('comptable', 'web')->id)
            ->where('permission_id', Permission::where('name', 'correct-invoices')->value('id'))->count());
    }

    public function test_la_migration_ne_plante_pas_sans_aucun_role_et_cree_le_droit(): void
    {
        DB::table('role_has_permissions')->delete();
        DB::table('model_has_roles')->delete();
        Role::query()->delete();
        Permission::where('name', 'correct-invoices')->delete();

        $this->migration()->up();
        $this->migration()->up();

        $this->assertSame(1, Permission::where('name', 'correct-invoices')->count());
    }

    // ------------------------------------------------------------------ 7. Gardes qui lisent les sources (mutations)

    private function source(string $relatif): string
    {
        return file_get_contents(base_path($relatif));
    }

    public function test_source_les_gardes_d_avoir_et_de_retransmission_portent_le_droit_fin_et_la_caisse_reste_a_manage_ventes_seul(): void
    {
        $retours = $this->source('app/Livewire/Ventes/RetoursAvoirs.php');
        $this->assertSame(3, substr_count($retours, "authorize('avoir-client')"), 'saveReturn, retryMecef, markAsTreated');
        $this->assertStringNotContainsString("authorize('manage-ventes')", $retours);

        $this->assertStringContainsString("authorize('retransmettre-facture')", $this->source('app/Livewire/Facturation/Facturation.php'));

        $provider = $this->source('app/Providers/AppServiceProvider.php');
        $this->assertMatchesRegularExpression("/Gate::define\\('avoir-client'.*'manage-ventes', 'correct-invoices'/", $provider);
        $this->assertMatchesRegularExpression("/Gate::define\\('retransmettre-facture'.*'manage-facturation', 'correct-invoices'/", $provider);

        $sync = $this->source('app/Http/Controllers/Api/SyncController.php');
        $this->assertStringContainsString("'credit_notes' => 'avoir-client',", $sync);
        $this->assertStringContainsString("'sales' => 'manage-ventes',", $sync);
        $this->assertStringContainsString("can('avoir-client')", $sync);

        // L'annulation et la caisse : `manage-ventes` SEUL, jamais le droit fin.
        $historique = $this->source('app/Livewire/Ventes/HistoriqueVentes.php');
        $this->assertStringContainsString("authorize('manage-ventes')", $historique);
        $this->assertStringNotContainsString('avoir-client', $historique);
        $this->assertStringNotContainsString('correct-invoices', $historique);
        $pos = $this->source('app/Livewire/Ventes/PosInterface.php');
        $this->assertStringNotContainsString('correct-invoices', $pos);
        $this->assertStringNotContainsString('avoir-client', $pos);
        $this->assertStringContainsString("Gate::allows('manage-ventes'), 403", $pos);

        // Aucune porte du reste de l'application ne s'ouvre au droit fin.
        foreach (['app/Livewire/Ventes/Devis.php', 'app/Livewire/Ventes/SuiviDettes.php', 'app/Livewire/Ventes/ListeClients.php'] as $f) {
            $this->assertStringNotContainsString('correct-invoices', $this->source($f), $f);
        }
    }
}
