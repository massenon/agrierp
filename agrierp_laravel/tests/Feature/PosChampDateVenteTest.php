<?php

namespace Tests\Feature;

use App\Livewire\Ventes\PosInterface;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Models\PeriodicClosure;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Receivable;
use App\Models\Role;
use App\Models\Sale;
use App\Models\StockMovement;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Models\VeterinaryWithdrawalPeriod;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.32 — CHAMP « DATE DE LA VENTE » AU PANIER DU POS WEB.
 *
 * Décision client du 14/10/2026 : UN SEUL champ, au panier. Écart ASSUMÉ avec la
 * maquette (`pos-interface.html` n'a aucun champ date). Les gardes sont ceux de 15.30
 * (`VerifySaleDateAction`) ; ici on prouve que le CHAMP les atteint, que le refus
 * s'affiche SOUS le champ, et que tout ce qui dépend de la vente porte la date choisie.
 * Date de test figée : 14/10/2026 12:00. J-3 = 11/10/2026.
 */
class PosChampDateVenteTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    private Product $poulet;

    private LivestockLot $bande;

    private Customer $client;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('caissier', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes']);

        $user = User::create(['name' => 'Caissière', 'email' => 'champdate@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026')]);
        $user->assignRole($role);
        $this->actingAs($user);

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);

        foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['701', 'Ventes', 7]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'AVI-001', 'name' => 'Oeufs', 'category_id' => $categorie->id, 'unit' => 'u',
            'pricing_mode' => 'fourchette', 'price_min' => 4_000, 'price_max' => 8_000,
            'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true,
        ]);

        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'AVI', 'is_active' => true]);
        $this->poulet = Product::create([
            'sku' => 'AVI-002', 'name' => 'Poulet goliath', 'category_id' => $categorie->id,
            'species_id' => $espece->id, 'unit' => 'u', 'pricing_mode' => 'fourchette',
            'price_min' => 3_000, 'price_max' => 4_000, 'tva_rate' => 0, 'stock_qty' => 200, 'is_active' => true,
        ]);
        $this->bande = LivestockLot::create([
            'code' => 'AVI-2026-01', 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 50, 'current_quantity' => 50, 'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
        ]);
        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'is_active' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function panier(string $mode = 'especes', ?string $date = null, bool $volaille = false)
    {
        $produit = $volaille ? $this->poulet : $this->produit;

        $composant = Livewire::test(PosInterface::class)
            ->set('paymentMode', $mode)
            ->set('cart', [[
                'product_id' => $produit->id, 'name' => $produit->name, 'unit' => 'u',
                'qty' => $volaille ? 6 : 2, 'montant' => 12_000,
                'lot_id' => $volaille ? $this->bande->id : null, 'lot_code' => $volaille ? $this->bande->code : null,
            ]]);

        if ($mode === 'credit') {
            $composant->set('customerId', $this->client->id);
        }
        if ($date !== null) {
            $composant->set('dateVente', $date);
        }

        return $composant;
    }

    private function fiche(string $jour, array $mouvements = []): LivestockDailyEntry
    {
        $fiche = new LivestockDailyEntry(array_merge(
            ['lot_id' => $this->bande->id, 'entry_date' => $jour, 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0],
            $mouvements,
        ));
        $fiche->effectif_final = LivestockDailyEntry::computeEffectifFinal(
            $fiche->previousEffectif(), (int) $fiche->achat, (int) $fiche->ne, (int) $fiche->mort, (int) $fiche->vente, (int) $fiche->don,
        );
        $fiche->save();

        return $fiche;
    }

    // ------------------------------------------------------------------ le champ

    public function test_le_champ_est_au_panier_avec_son_libelle_et_aujourd_hui_par_defaut(): void
    {
        Livewire::test(PosInterface::class)
            ->assertSet('dateVente', '2026-10-14')
            ->assertSee('Date de la vente')
            ->assertSeeHtml('type="date"');
    }

    public function test_le_champ_est_borne_a_aujourd_hui_et_a_l_exercice_ouvert(): void
    {
        Livewire::test(PosInterface::class)
            ->assertSeeHtml('max="2026-10-14"')
            ->assertSeeHtml('min="2026-01-01"');

        // L'exercice ouvert s'arrête avant aujourd'hui : le sélecteur ne le dépasse pas.
        FiscalYear::query()->update(['end_date' => '2026-10-10']);

        Livewire::test(PosInterface::class)->assertSeeHtml('max="2026-10-10"');
    }

    public function test_le_champ_n_est_pas_une_modale_conditionnelle(): void
    {
        $vue = file_get_contents(resource_path('views/livewire/ventes/pos-interface.blade.php'));

        $this->assertStringNotContainsString('@if($showModal', $vue);
        $this->assertSame(1, substr_count($vue, 'wire:model.live="dateVente"'));
        // Un seul champ : la modale « Vente à la Pièce » (par ligne) n'en porte pas.
        $debut = strpos($vue, 'name="modal-weight"');
        $modale = substr($vue, $debut, strpos($vue, 'name="modal-add-client"') - $debut);
        $this->assertStringNotContainsString('dateVente', $modale);
    }

    // ------------------------------------------------------------------ vente à J-3

    public function test_une_vente_a_j_moins_3_date_ecriture_stock_et_sold_at(): void
    {
        $this->panier('especes', '2026-10-11')->call('validateSale')->assertHasNoErrors();

        $vente = Sale::firstOrFail();
        $this->assertSame('2026-10-11 12:00', $vente->sold_at->format('Y-m-d H:i'), 'Jour choisi, heure courante.');
        $this->assertSame('2026-10-11', AccountingEntry::firstOrFail()->entry_date->format('Y-m-d'));
        $this->assertSame('2026-10-11', StockMovement::where('reference_id', $vente->id)->firstOrFail()->movement_date->format('Y-m-d'));
        $this->assertEquals(48, $this->produit->fresh()->stock_qty);
        $this->assertEquals(12_000, TreasuryAccount::firstOrFail()->balance);
    }

    public function test_une_vente_a_credit_a_j_moins_3_echoit_30_jours_apres_le_jour_choisi(): void
    {
        $this->panier('credit', '2026-10-11')->call('validateSale')->assertHasNoErrors();

        $this->assertSame('2026-11-10', Receivable::firstOrFail()->due_date->format('Y-m-d'), 'J-3 + 30 jours, pas aujourd\'hui + 30.');
        $this->assertSame('2026-10-11', AccountingEntry::firstOrFail()->entry_date->format('Y-m-d'));
    }

    public function test_une_vente_a_j_moins_3_recalcule_la_fiche_du_jour_et_les_suivantes(): void
    {
        $this->fiche('2026-10-11', ['mort' => 1]);   // 49
        $this->fiche('2026-10-12', ['mort' => 2]);   // 47
        $this->fiche('2026-10-14', ['achat' => 3]);  // 50
        $this->bande->update(['current_quantity' => 50]);

        $this->panier('especes', '2026-10-11', true)->call('validateSale')->assertHasNoErrors();

        $effectifs = LivestockDailyEntry::where('lot_id', $this->bande->id)->orderBy('entry_date')->get()
            ->mapWithKeys(fn ($f) => [Carbon::parse($f->entry_date)->toDateString() => (int) $f->effectif_final])->all();

        // Recalcul indépendant : 50 - (1+6) = 43 ; 43 - 2 = 41 ; 41 + 3 = 44.
        $this->assertSame(['2026-10-11' => 43, '2026-10-12' => 41, '2026-10-14' => 44], $effectifs);
        $this->assertSame(6, (int) LivestockDailyEntry::where('entry_date', '2026-10-11')->value('vente'));
        $this->assertSame(44, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_le_ticket_porte_la_date_choisie(): void
    {
        $this->panier('especes', '2026-10-11')->call('validateSale')->assertHasNoErrors();

        $html = view('exports.sale-ticket', ['sale' => Sale::with(['customer', 'lines.product'])->firstOrFail()])->render();

        $this->assertStringContainsString('11/10/2026 12:00', $html);
        $this->assertStringNotContainsString('14/10/2026', $html);
    }

    // ------------------------------------------------------------------ rémanence : enregistrée et signalée

    public function test_la_remanence_d_une_vente_anterieure_est_signalee_sans_refus(): void
    {
        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->bande->id, 'product_used' => 'Ivermectine',
            'start_date' => '2026-10-08', 'withdrawal_days' => 7, 'end_date' => '2026-10-15',
        ]);

        $this->panier('especes', '2026-10-11', true)->call('validateSale')->assertHasNoErrors();

        $this->assertSame(1, Sale::count(), 'Enregistrée, jamais refusée pour ce motif.');
        $this->assertSame(1, Notification::where('type', 'sale_under_withdrawal')->count());
        $this->assertSame(1, AuditLog::where('action', 'sale.under_withdrawal_received')->count());
    }

    public function test_une_vente_anterieure_hors_remanence_ne_declenche_aucune_fausse_alerte(): void
    {
        // Traitement commencé APRÈS la vente (12/10) : la vente du 11/10 était légale.
        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->bande->id, 'product_used' => 'Ivermectine',
            'start_date' => '2026-10-12', 'withdrawal_days' => 7, 'end_date' => '2026-10-19',
        ]);

        $this->panier('especes', '2026-10-11', true)->call('validateSale')->assertHasNoErrors();

        $this->assertSame(1, Sale::count());
        $this->assertSame(0, Notification::where('type', 'sale_under_withdrawal')->count());
    }

    public function test_la_vente_du_jour_d_une_bande_sous_remanence_reste_refusee(): void
    {
        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->bande->id, 'product_used' => 'Ivermectine',
            'start_date' => '2026-10-08', 'withdrawal_days' => 7, 'end_date' => '2026-10-15',
        ]);

        $this->panier('especes', null, true)->call('validateSale');

        $this->assertSame(0, Sale::count(), 'Comportement du jour inchangé : le blocage reste dur.');
    }

    public function test_l_ajout_au_panier_d_une_bande_sous_remanence_n_est_refuse_que_pour_le_jour(): void
    {
        VeterinaryWithdrawalPeriod::create([
            'lot_id' => $this->bande->id, 'product_used' => 'Ivermectine',
            'start_date' => '2026-10-08', 'withdrawal_days' => 7, 'end_date' => '2026-10-15',
        ]);

        $ajout = fn (string $date) => Livewire::test(PosInterface::class)
            ->set('dateVente', $date)
            ->set('weightProductId', $this->poulet->id)
            ->set('weightQty', 2)->set('weightPrice', 7_000)->set('weightLotId', $this->bande->id)
            ->call('confirmWeightAdd');

        $this->assertCount(0, $ajout('2026-10-14')->get('cart'), 'Jour même : refusé.');
        $this->assertCount(1, $ajout('2026-10-11')->get('cart'), 'Jour antérieur : ajouté, signalé à la validation.');
    }

    // ------------------------------------------------------------------ refus, message sous le champ

    public function test_une_date_future_est_refusee_avec_son_message_sous_le_champ(): void
    {
        $this->panier('especes', '2026-10-15')->call('validateSale')
            ->assertHasErrors(['dateVente'])
            ->assertSee('Vente refusée : la date du 15/10/2026 est dans le futur.');

        $this->assertSame(0, Sale::count());
        $this->assertEquals(50, $this->produit->fresh()->stock_qty);
    }

    public function test_un_mois_cloture_est_refuse_avec_son_message(): void
    {
        PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now()]);

        $this->panier('especes', '2026-07-28')->call('validateSale')
            ->assertHasErrors(['dateVente'])
            ->assertSee('le mois 2026-07 est clôturé');

        $this->assertSame(0, Sale::count());
    }

    public function test_un_exercice_clos_est_refuse_avec_son_message(): void
    {
        FiscalYear::create(['year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'cloture']);

        $this->panier('especes', '2025-06-10')->call('validateSale')
            ->assertHasErrors(['dateVente'])
            ->assertSee('Vente refusée : l\'exercice 2025 est clôturé : aucune saisie ne peut être datée du 10/06/2025.');

        $this->assertSame(0, Sale::count());
    }

    public function test_une_date_sans_exercice_est_refusee_avec_son_message(): void
    {
        $this->panier('especes', '2024-03-10')->call('validateSale')
            ->assertHasErrors(['dateVente'])
            ->assertSee('aucun exercice comptable ne couvre le 10/03/2024');

        $this->assertSame(0, Sale::count());
    }

    public function test_le_refus_s_affiche_des_le_choix_de_la_date_sans_valider_la_vente(): void
    {
        Livewire::test(PosInterface::class)
            ->set('dateVente', '2026-10-15')
            ->assertHasErrors(['dateVente'])
            ->assertSee('est dans le futur')
            ->set('dateVente', '2026-10-11')
            ->assertHasNoErrors(['dateVente'])
            ->assertSee('Vente antérieure : écriture, stock, créance et fiche seront datés du 11/10/2026.');
    }

    // ------------------------------------------------------------------ vente du jour inchangée

    public function test_la_vente_du_jour_est_inchangee(): void
    {
        $this->panier('credit')->call('validateSale')->assertHasNoErrors();

        $vente = Sale::firstOrFail();
        $this->assertSame('2026-10-14 12:00:00', $vente->sold_at->format('Y-m-d H:i:s'), 'now() comme avant.');
        $this->assertSame('2026-10-14', AccountingEntry::firstOrFail()->entry_date->format('Y-m-d'));
        $this->assertSame('2026-11-13', Receivable::firstOrFail()->due_date->format('Y-m-d'));
        $this->assertSame(0, Notification::where('type', 'sale_under_withdrawal')->count());
    }

    public function test_la_vente_du_jour_n_est_pas_bloquee_par_la_cloture_du_mois_courant(): void
    {
        PeriodicClosure::create(['period' => '2026-10', 'closed_at' => now()]);

        $this->panier('especes')->call('validateSale')->assertHasNoErrors();

        $this->assertSame(1, Sale::count());
    }

    public function test_apres_la_vente_le_champ_revient_a_aujourd_hui(): void
    {
        $this->panier('especes', '2026-10-11')->call('validateSale')->assertSet('dateVente', '2026-10-14');
    }

    public function test_une_double_soumission_ne_cree_qu_une_vente(): void
    {
        $this->panier('especes', '2026-10-11')->call('validateSale')->call('validateSale');

        $this->assertSame(1, Sale::count());
        $this->assertSame(1, AccountingEntry::count());
        $this->assertEquals(48, $this->produit->fresh()->stock_qty);
    }

    // ------------------------------------------------------------------ droits : rien d'inventé (QA6 non tranché)

    public function test_aucune_nouvelle_ability_n_est_inventee_pour_antidater(): void
    {
        $source = file_get_contents(app_path('Livewire/Ventes/PosInterface.php'));

        preg_match_all("/authorize\('([^']+)'\)/", $source, $m);
        $this->assertSame(['manage-ventes'], array_values(array_unique($m[1])));
    }

    public function test_un_utilisateur_sans_manage_ventes_ne_peut_pas_vendre_meme_avec_une_date(): void
    {
        $lecteur = User::create(['name' => 'Lecteur', 'email' => 'lecteur@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026')]);
        $lecteur->givePermissionTo('view-ventes');
        $this->actingAs($lecteur);

        $this->panier('especes', '2026-10-11')->call('validateSale')->assertForbidden();

        $this->assertSame(0, Sale::count());
    }
}
