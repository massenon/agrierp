<?php

namespace Tests\Feature;

use App\Livewire\Ventes\RetoursAvoirs;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\CreditNote;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\StockMovement;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket AV1 / AV2 — « RETOURS ET AVOIRS » ET « HISTORIQUE DES VENTES » AU POSTE.
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Le poste n'enregistre que la DEMANDE de retour (`credit_notes`) ou d'annulation (vente
 * renvoyée `annulee`) ; le serveur fait les effets par les MÊMES points de passage que le web (`AvoirClientService`,
 * `AnnulerVenteAction`). Trois refus ont été construits d'abord au web, puis repris à l'absorbeur : quantité au-delà du
 * vendu moins le déjà retourné, montant au-delà de la ligne moins le déjà crédité, exercice clos ou plan comptable
 * incomplet (rien n'est écrit).
 *
 * ⚠️ Les chiffres comptables sont RECALCULÉS INDÉPENDAMMENT (somme SQL brute des lignes d'écriture par compte).
 *
 * Données : vente de 59 000 FCFA TTC d'une plaquette d'œufs (10 × 5 900, TVA 18 %) + 4 vitamines à 5 000 (20 000, TVA 0).
 */
class AvoirsClientsSyncTest extends TestCase
{
    use RefreshDatabase;

    private Product $oeufs;

    private Product $vitamines;

    private Sale $vente;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        Carbon::setTestNow('2026-10-21 10:00:00');

        $this->caissier = $this->compte('caissier');

        FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ]);
        foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['443', 'TVA facturée', 4], ['701', 'Ventes de produits', 7]] as [$code, $libelle, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true]);
        }

        $categorie = ProductCategory::create(['label' => 'Œufs', 'is_active' => true]);
        $this->oeufs = Product::create([
            'sku' => 'OEUF-PLQ', 'name' => "Plaquette d'œufs", 'category_id' => $categorie->id, 'unit' => 'plaquette',
            'pricing_mode' => 'fourchette', 'price_min' => 2000, 'price_max' => 6000, 'tva_rate' => 18,
            'stock_qty' => 100, 'is_active' => true,
        ]);
        $this->vitamines = Product::create([
            'sku' => 'VIT-01', 'name' => 'Vitamines', 'category_id' => $categorie->id, 'unit' => 'sachet',
            'pricing_mode' => 'fourchette', 'price_min' => 5000, 'price_max' => 5000, 'tva_rate' => 0,
            'stock_qty' => 50, 'is_active' => true,
        ]);

        $this->vente = $this->vendre('2026-10-20 15:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => 'Compte '.$role, 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function vendre(string $quand, string $mode = 'especes'): Sale
    {
        $client = Customer::firstOrCreate(['name' => 'GBAGUIDI Solange'], ['phone' => '+22997333333', 'is_active' => true]);
        $vente = Sale::create([
            'customer_id' => $client->id, 'payment_mode' => $mode, 'subtotal' => 79000, 'discount' => 0, 'total' => 79000,
            'status' => 'validee', 'sold_at' => $quand,
        ]);
        SaleLine::create(['sale_id' => $vente->id, 'product_id' => $this->oeufs->id, 'qty' => 10, 'unit_price' => 5900, 'manual_total_amount' => 59000]);
        SaleLine::create(['sale_id' => $vente->id, 'product_id' => $this->vitamines->id, 'qty' => 4, 'unit_price' => 5000, 'manual_total_amount' => 20000]);

        return $vente;
    }

    /** @return array<string, mixed> */
    private function demande(array $remplace = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'sale_id' => $this->vente->id,
            'product_id' => $this->oeufs->id,
            'qty' => 2,
            'amount' => 11800,
            'reason' => 'Plaquette détériorée',
            'decision' => 'reintegre',
            'inspection_notes' => null,
            'status' => 'en_attente',
            'credit_date' => '2026-10-21 09:30:00',
        ], $remplace);
    }

    private function pousser(User $u, array $corps): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test'] + $corps)->assertOk();
    }

    /** Solde net (débit − crédit) d'un compte, recalculé en SQL brut. */
    private function net(string $code): float
    {
        $ligne = DB::selectOne(
            'select coalesce(sum(l.debit),0) - coalesce(sum(l.credit),0) as net
             from accounting_entry_lines l join chart_of_accounts c on c.id = l.account_id where c.code = ?',
            [$code]
        );

        return round((float) $ligne->net, 2);
    }

    private function retourWeb(string $produit, float $qty, float $montant, string $decision = 'reintegre')
    {
        $this->actingAs($this->caissier);

        return Livewire::test(RetoursAvoirs::class)
            ->set('saleId', $this->vente->id)->set('productId', $produit)
            ->set('qty', $qty)->set('amount', $montant)
            ->set('reason', 'Motif de test')->set('decision', $decision)
            ->call('saveReturn');
    }

    // ------------------------------------------------------------------ Web : les trois refus construits d'abord ici

    public function test_web_une_quantite_au_dela_du_vendu_est_refusee_et_rien_n_est_ecrit(): void
    {
        $this->retourWeb($this->oeufs->id, 11, 5000)->assertHasErrors(['qty']);

        $this->assertSame(0, CreditNote::count());
        $this->assertEquals(100, $this->oeufs->fresh()->stock_qty, 'aucun stock réintégré');
        $this->assertSame(0, AccountingEntry::where('source_type', 'credit_note')->count());
    }

    public function test_web_le_deja_retourne_est_deduit_du_retournable(): void
    {
        $this->retourWeb($this->oeufs->id, 6, 35400)->assertHasNoErrors();
        $this->assertSame(1, CreditNote::count());

        // 10 vendus − 6 retournés = 4 restants : 5 est refusé, avec le détail.
        $r = $this->retourWeb($this->oeufs->id, 5, 100)->assertHasErrors(['qty']);
        $this->assertStringContainsString('4 restant(s)', collect($r->errors()->get('qty'))->implode(' '));
        $this->assertSame(1, CreditNote::count());

        $this->retourWeb($this->oeufs->id, 4, 23600)->assertHasNoErrors();
        $this->assertSame(2, CreditNote::count());
        $this->assertEquals(100 + 6 + 4, $this->oeufs->fresh()->stock_qty);

        // Tout est retourné : message dédié.
        $r = $this->retourWeb($this->oeufs->id, 1, 100)->assertHasErrors(['qty']);
        $this->assertStringContainsString('déjà été retourné en totalité', collect($r->errors()->get('qty'))->implode(' '));
    }

    public function test_web_le_montant_ne_depasse_pas_la_ligne_moins_le_deja_credite(): void
    {
        $this->retourWeb($this->oeufs->id, 2, 59001)->assertHasErrors(['amount']);
        $this->assertSame(0, CreditNote::count());

        $this->retourWeb($this->oeufs->id, 2, 50000)->assertHasNoErrors();
        // Reste à créditer : 59 000 − 50 000 = 9 000.
        $this->retourWeb($this->oeufs->id, 1, 9001)->assertHasErrors(['amount']);
        $this->retourWeb($this->oeufs->id, 1, 9000)->assertHasNoErrors();
        $this->assertSame(2, CreditNote::count());
    }

    public function test_web_un_produit_hors_vente_ou_une_vente_annulee_est_refuse(): void
    {
        $autre = Product::create([
            'sku' => 'X-1', 'name' => 'Autre', 'category_id' => $this->oeufs->category_id, 'unit' => 'kg',
            'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => 5, 'is_active' => true,
        ]);
        $this->retourWeb($autre->id, 1, 100)->assertHasErrors(['productId']);

        $this->vente->update(['status' => 'annulee']);
        $this->retourWeb($this->oeufs->id, 1, 100)->assertHasErrors(['saleId']);
        $this->assertSame(0, CreditNote::count());
    }

    public function test_web_un_exercice_clos_refuse_le_retour_sans_rien_ecrire(): void
    {
        FiscalYear::where('year', 2026)->update(['status' => 'cloture']);

        $this->retourWeb($this->oeufs->id, 2, 11800)->assertDispatched('toast');

        $this->assertSame(0, CreditNote::count(), 'plus de « retour enregistré SANS écriture »');
        $this->assertEquals(100, $this->oeufs->fresh()->stock_qty);
        $this->assertSame(0, StockMovement::where('reference_type', 'credit_note')->count());
    }

    public function test_web_un_plan_comptable_incomplet_refuse_le_retour_sans_rien_ecrire(): void
    {
        ChartOfAccount::where('code', '411')->delete();

        $this->retourWeb($this->oeufs->id, 2, 11800)->assertDispatched('toast');

        $this->assertSame(0, CreditNote::count());
        $this->assertEquals(100, $this->oeufs->fresh()->stock_qty);
    }

    // ------------------------------------------------------------------ Absorbeur : accepté

    public function test_une_demande_acceptee_produit_l_avoir_le_stock_et_l_ecriture_inverse(): void
    {
        $d = $this->demande();
        $rep = $this->pousser($this->caissier, ['credit_notes' => [$d]]);

        $this->assertSame([$d['id']], $rep->json('credit_notes.accepted'));
        $this->assertSame([], $rep->json('credit_notes.rejected'));

        $avoir = CreditNote::findOrFail($d['id']);
        $this->assertSame('AV-2026-001', $avoir->credit_note_number, 'la numérotation est attribuée par le serveur');
        $this->assertSame('en_attente', $avoir->status);
        $this->assertSame('reintegre', $avoir->decision);
        $this->assertEquals(2, $avoir->qty);
        $this->assertEquals(11800, $avoir->amount);
        $this->assertSame('2026-10-21 09:30:00', $avoir->created_at->format('Y-m-d H:i:s'), 'le jour du FAIT, pas celui de la réception');

        // Stock : +2 par UN mouvement `credit_note`, daté du jour du retour.
        $this->assertEquals(102, $this->oeufs->fresh()->stock_qty);
        $mouvement = StockMovement::where('reference_type', 'credit_note')->sole();
        $this->assertSame($avoir->id, $mouvement->reference_id);
        $this->assertSame('entree', $mouvement->type);

        // Écriture inverse, recalculée : 11 800 TTC = HT 10 000 + TVA 1 800 ; 701 et 443 débités, 411 crédité ; jamais 531.
        $this->assertEquals(10000, $this->net('701'));
        $this->assertEquals(1800, $this->net('443'));
        $this->assertEquals(-11800, $this->net('411'));
        $this->assertEquals(0, $this->net('531'));
        $ecriture = AccountingEntry::findOrFail($avoir->accounting_entry_id);
        $this->assertSame('2026-10-21', $ecriture->entry_date->format('Y-m-d'));
    }

    public function test_une_demande_reformee_n_a_aucun_impact_stock_mais_est_comptabilisee(): void
    {
        $d = $this->demande(['decision' => 'reforme', 'qty' => 1, 'amount' => 5900]);
        $this->pousser($this->caissier, ['credit_notes' => [$d]])->assertJsonPath('credit_notes.accepted.0', $d['id']);

        $this->assertEquals(100, $this->oeufs->fresh()->stock_qty);
        $this->assertSame(0, StockMovement::where('reference_type', 'credit_note')->count());
        $this->assertNotNull(CreditNote::findOrFail($d['id'])->accounting_entry_id);
    }

    public function test_les_numeros_se_suivent_et_un_produit_sans_tva_n_a_pas_de_ligne_443(): void
    {
        $a = $this->demande();
        $b = $this->demande(['product_id' => $this->vitamines->id, 'qty' => 1, 'amount' => 5000]);
        $this->pousser($this->caissier, ['credit_notes' => [$a, $b]]);

        $this->assertSame('AV-2026-001', CreditNote::findOrFail($a['id'])->credit_note_number);
        $this->assertSame('AV-2026-002', CreditNote::findOrFail($b['id'])->credit_note_number);
        $this->assertEquals(1800, $this->net('443'), 'seul l\'avoir des œufs porte de la TVA');
        $this->assertEquals(15000, $this->net('701'), '10 000 + 5 000');
    }

    public function test_un_retour_part_dans_le_meme_envoi_que_sa_vente(): void
    {
        $venteId = (string) Str::uuid();
        $vente = [
            'id' => $venteId, 'payment_mode' => 'especes', 'subtotal' => 5900, 'discount' => 0, 'total' => 5900,
            'cash_received' => 5900, 'change_due' => 0, 'status' => 'validee', 'sold_at' => '2026-10-21 08:00:00',
            'lines' => [['product_id' => $this->oeufs->id, 'qty' => 1, 'unit_price' => 5900, 'manual_total_amount' => 5900]],
        ];
        $d = $this->demande(['sale_id' => $venteId, 'qty' => 1, 'amount' => 5900]);

        $rep = $this->pousser($this->caissier, ['sales' => [$vente], 'credit_notes' => [$d]]);

        $this->assertSame([$venteId], $rep->json('sales.accepted'));
        $this->assertSame([$d['id']], $rep->json('credit_notes.accepted'), json_encode($rep->json('credit_notes')));
        // −1 (vente) +1 (retour réintégré) : le stock revient à 100.
        $this->assertEquals(100, $this->oeufs->fresh()->stock_qty);
    }

    // ------------------------------------------------------------------ Absorbeur : idempotent

    public function test_un_renvoi_du_meme_identifiant_ne_rejoue_rien(): void
    {
        $d = $this->demande();
        $this->pousser($this->caissier, ['credit_notes' => [$d]]);
        $rep = $this->pousser($this->caissier, ['credit_notes' => [$d]]);

        $this->assertSame([$d['id']], $rep->json('credit_notes.accepted'));
        $this->assertSame([], $rep->json('credit_notes.rejected'));
        $this->assertSame(1, CreditNote::count());
        $this->assertSame(1, StockMovement::where('reference_type', 'credit_note')->count());
        $this->assertEquals(102, $this->oeufs->fresh()->stock_qty);
        $this->assertSame(1, AccountingEntry::where('source_type', 'credit_note')->count());
        $this->assertEquals(10000, $this->net('701'));
    }

    public function test_marquer_traite_est_une_demande_idempotente(): void
    {
        $d = $this->demande();
        $this->pousser($this->caissier, ['credit_notes' => [$d]]);
        $this->assertSame('en_attente', CreditNote::findOrFail($d['id'])->status);

        $traite = ['id' => $d['id'], 'status' => 'traite'] + $d;
        $rep = $this->pousser($this->caissier, ['credit_notes' => [$traite]]);
        $this->assertSame([$d['id']], $rep->json('credit_notes.accepted'));
        $this->assertSame('traite', CreditNote::findOrFail($d['id'])->status);
        $this->assertSame(1, \App\Models\AuditLog::where('action', 'credit_note.treated')->count());

        $this->pousser($this->caissier, ['credit_notes' => [$traite]]);
        $this->assertSame(1, \App\Models\AuditLog::where('action', 'credit_note.treated')->count(), 'une seule fois');
        $this->assertSame(1, CreditNote::count());
    }

    // ------------------------------------------------------------------ Absorbeur : rejeté, avec motif, rien d'écrit

    private function assertRejete(array $d, string $extraitDuMotif): void
    {
        $avant = [CreditNote::count(), StockMovement::count(), AccountingEntry::count(), (float) $this->oeufs->fresh()->stock_qty];

        $rep = $this->pousser($this->caissier, ['credit_notes' => [$d]]);

        $this->assertSame([], $rep->json('credit_notes.accepted'));
        $this->assertSame($d['id'], $rep->json('credit_notes.rejected.0.id'));
        $this->assertStringContainsString($extraitDuMotif, $rep->json('credit_notes.rejected.0.reason'));
        $this->assertSame($avant, [CreditNote::count(), StockMovement::count(), AccountingEntry::count(), (float) $this->oeufs->fresh()->stock_qty],
            'un refus n\'écrit ni avoir, ni stock, ni écriture');
    }

    public function test_refus_quantite_au_dela_du_vendu(): void
    {
        $this->assertRejete($this->demande(['qty' => 11, 'amount' => 100]), 'dépasse ce qui reste retournable');
    }

    public function test_refus_deja_retourne(): void
    {
        $this->pousser($this->caissier, ['credit_notes' => [$this->demande(['qty' => 8, 'amount' => 47200])]]);

        $this->assertRejete($this->demande(['qty' => 3, 'amount' => 100]), '2 restant(s)');
    }

    public function test_refus_montant_au_dela_de_la_ligne(): void
    {
        $this->assertRejete($this->demande(['amount' => 59001]), 'dépasse ce qui reste à créditer');
    }

    public function test_refus_vente_inconnue_ou_produit_hors_vente_ou_vente_annulee(): void
    {
        $this->assertRejete($this->demande(['sale_id' => (string) Str::uuid()]), 'vente est inconnue');

        $autre = Product::create([
            'sku' => 'X-1', 'name' => 'Autre', 'category_id' => $this->oeufs->category_id, 'unit' => 'kg',
            'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => 5, 'is_active' => true,
        ]);
        $this->assertRejete($this->demande(['product_id' => $autre->id]), 'ne figure pas sur cette vente');

        $this->vente->update(['status' => 'annulee']);
        $this->assertRejete($this->demande(), 'vente est annulée');
    }

    public function test_refus_champs_invalides_en_francais(): void
    {
        $this->assertRejete($this->demande(['qty' => 0]), 'quantité retournée');
        $this->assertRejete($this->demande(['decision' => 'rembourse']), 'décision');
        $this->assertRejete($this->demande(['reason' => '']), 'motif');
        $this->assertRejete($this->demande(['id' => 'pas-un-uuid']), 'identifiant');
    }

    public function test_refus_date_future_ou_anterieure_a_la_vente(): void
    {
        $this->assertRejete($this->demande(['credit_date' => '2026-10-22 09:00:00']), 'dans le futur');
        $this->assertRejete($this->demande(['credit_date' => '2026-10-19 09:00:00']), 'précéder celle de la vente');
    }

    public function test_refus_exercice_clos_a_la_date_du_retour(): void
    {
        // Vente et retour de décembre 2025, exercice 2025 clôturé : le retour est daté DANS l'exercice clos.
        FiscalYear::create(['year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'cloture']);
        $vieille = $this->vendre('2025-12-20 10:00:00');

        $d = $this->demande(['sale_id' => $vieille->id, 'credit_date' => '2025-12-28 10:00:00']);
        $this->assertRejete($d, "L'exercice 2025 est clôturé");
    }

    public function test_refus_plan_comptable_incomplet(): void
    {
        ChartOfAccount::where('code', '443')->delete();

        $this->assertRejete($this->demande(), 'plan comptable incomplet');
    }

    public function test_un_compte_sans_le_droit_manage_ventes_est_refuse(): void
    {
        $animalier = $this->compte('animalier');
        $d = $this->demande();

        $rep = $this->pousser($animalier, ['credit_notes' => [$d]]);

        $this->assertSame([], $rep->json('credit_notes.accepted'));
        $this->assertStringContainsString('votre rôle ne permet pas', $rep->json('credit_notes.rejected.0.reason'));
        $this->assertSame(0, CreditNote::count());
    }

    public function test_un_refus_ne_bloque_pas_les_autres_demandes_du_meme_envoi(): void
    {
        $mauvaise = $this->demande(['qty' => 99]);
        $bonne = $this->demande();

        $rep = $this->pousser($this->caissier, ['credit_notes' => [$mauvaise, $bonne]]);

        $this->assertSame([$bonne['id']], $rep->json('credit_notes.accepted'));
        $this->assertSame($mauvaise['id'], $rep->json('credit_notes.rejected.0.id'));
        $this->assertSame(1, CreditNote::count());
    }

    // ------------------------------------------------------------------ Tirage

    /** @return array<string, mixed> */
    private function tirer(User $u): array
    {
        Carbon::setTestNow(now()->addMinute());
        $pages = [];
        $jeton = null;
        do {
            $corps = $this->actingAs($u, 'sanctum')->getJson('/api/sync/pull?'.http_build_query(array_filter([
                'page' => count($pages) + 1, 'curseur_page' => $jeton,
            ])))->assertOk()->json();
            $pages[] = $corps;
            $jeton = $corps['page_suivante'];
        } while ($jeton !== null && count($pages) < 50);

        return $pages;
    }

    public function test_les_avoirs_descendent_aux_comptes_qui_lisent_les_ventes_avec_leurs_colonnes(): void
    {
        $d = $this->demande();
        $this->pousser($this->caissier, ['credit_notes' => [$d]]);

        $pages = $this->tirer($this->caissier);
        $this->assertContains('credit_notes', $pages[0]['tables_servies']);
        $servis = collect($pages)->flatMap(fn ($p) => $p['credit_notes'] ?? []);

        $this->assertSame(['id', 'credit_note_number', 'sale_id', 'product_id', 'qty', 'amount', 'reason', 'decision',
            'inspection_notes', 'status', 'created_at'], array_keys($servis->sole()));
        $this->assertEquals([
            'id' => $d['id'], 'credit_note_number' => 'AV-2026-001', 'sale_id' => $this->vente->id,
            'product_id' => $this->oeufs->id, 'qty' => 2.0, 'amount' => 11800.0, 'reason' => 'Plaquette détériorée',
            'decision' => 'reintegre', 'inspection_notes' => null, 'status' => 'en_attente',
            'created_at' => '2026-10-21 09:30:00',
        ], $servis->sole());

        $animalier = $this->tirer($this->compte('animalier'));
        $this->assertNotContains('credit_notes', $animalier[0]['tables_servies']);
        $this->assertArrayNotHasKey('credit_notes', $animalier[0]);
    }

    public function test_le_curseur_du_tirage_suit_l_ecriture_du_serveur_pas_la_date_du_fait(): void
    {
        // Retour daté d'avant-hier, reçu aujourd'hui : il doit descendre à un tirage incrémental depuis ce matin.
        $d = $this->demande(['credit_date' => '2026-10-20 16:00:00']);
        $this->pousser($this->caissier, ['credit_notes' => [$d]]);

        Carbon::setTestNow(now()->addMinutes(2));
        $depuis = '2026-10-21T08:00:00Z';
        $corps = $this->actingAs($this->caissier, 'sanctum')
            ->getJson('/api/sync/pull?page=1&since='.urlencode($depuis))->assertOk()->json();

        $this->assertSame([$d['id']], collect($corps['credit_notes'])->pluck('id')->all());
    }

    // ------------------------------------------------------------------ Annulation d'une vente (Historique des Ventes)

    /** @return array<string, mixed> */
    private function venteDuPoste(string $statut): array
    {
        return [
            'id' => $this->vente->id, 'payment_mode' => 'especes', 'subtotal' => 79000, 'discount' => 0, 'total' => 79000,
            'cash_received' => 79000, 'change_due' => 0, 'status' => $statut, 'sold_at' => '2026-10-20 15:00:00',
            'lines' => [
                ['product_id' => $this->oeufs->id, 'qty' => 10, 'unit_price' => 5900, 'manual_total_amount' => 59000],
                ['product_id' => $this->vitamines->id, 'qty' => 4, 'unit_price' => 5000, 'manual_total_amount' => 20000],
            ],
        ];
    }

    public function test_une_vente_connue_renvoyee_annulee_reintegre_le_stock_une_seule_fois(): void
    {
        $rep = $this->pousser($this->caissier, ['sales' => [$this->venteDuPoste('annulee')]]);

        $this->assertSame([$this->vente->id], $rep->json('sales.accepted'));
        $this->assertSame('annulee', $this->vente->fresh()->status);
        $this->assertEquals(110, $this->oeufs->fresh()->stock_qty);
        $this->assertEquals(54, $this->vitamines->fresh()->stock_qty);
        $this->assertSame(1, \App\Models\AuditLog::where('action', 'sale.cancelled')->count());

        // Renvoi : rien ne se rejoue.
        $this->pousser($this->caissier, ['sales' => [$this->venteDuPoste('annulee')]]);
        $this->assertEquals(110, $this->oeufs->fresh()->stock_qty);
        $this->assertSame(1, \App\Models\AuditLog::where('action', 'sale.cancelled')->count());
    }

    public function test_une_vente_validee_renvoyee_ne_change_rien(): void
    {
        $this->pousser($this->caissier, ['sales' => [$this->venteDuPoste('validee')]]);

        $this->assertSame('validee', $this->vente->fresh()->status);
        $this->assertEquals(100, $this->oeufs->fresh()->stock_qty);
    }

    public function test_une_vente_inconnue_annulee_avant_son_premier_envoi_est_vendue_puis_annulee(): void
    {
        $id = (string) Str::uuid();
        $vente = array_merge($this->venteDuPoste('annulee'), ['id' => $id]);

        $rep = $this->pousser($this->caissier, ['sales' => [$vente]]);

        $this->assertSame([$id], $rep->json('sales.accepted'));
        $this->assertSame('annulee', Sale::findOrFail($id)->status);
        $this->assertEquals(100, $this->oeufs->fresh()->stock_qty, '−10 à la vente, +10 à l\'annulation');
        $this->assertSame(4, StockMovement::where('reference_id', $id)->count(), 'deux lignes : une sortie et une entrée chacune');
    }

    public function test_sans_manage_ventes_l_annulation_est_refusee(): void
    {
        $rep = $this->pousser($this->compte('animalier'), ['sales' => [$this->venteDuPoste('annulee')]]);

        $this->assertSame([], $rep->json('sales.accepted'));
        $this->assertSame('validee', $this->vente->fresh()->status);
    }

    // ------------------------------------------------------------------ Ticket PDF d'une vente

    public function test_le_ticket_pdf_d_une_vente_est_servi_aux_comptes_qui_exportent_les_ventes(): void
    {
        $this->actingAs($this->caissier, 'sanctum')->get('/api/ventes/'.$this->vente->id.'/pdf')
            ->assertOk()->assertHeader('content-type', 'application/pdf')
            ->assertHeader('content-disposition', 'attachment; filename="vente-'.strtoupper(substr($this->vente->id, 0, 8)).'.pdf"');

        $this->actingAs($this->compte('animalier'), 'sanctum')->get('/api/ventes/'.$this->vente->id.'/pdf')->assertForbidden();
        $this->actingAs($this->caissier, 'sanctum')->get('/api/ventes/'.Str::uuid().'/pdf')->assertNotFound();
    }

    // ------------------------------------------------------------------ Contrat de schéma (lu par le poste)

    public function test_les_colonnes_de_credit_notes_sont_celles_que_le_poste_reflete(): void
    {
        // Le miroir Drift (`CreditNotes`, `AppDatabase`) lit cette liste : `test/avoirs_schema_test.dart`.
        $colonnes = Schema::getColumnListing('credit_notes');
        sort($colonnes);

        $this->assertSame([
            'accounting_entry_id', 'amount', 'created_at', 'credit_note_number', 'decision', 'id', 'inspection_notes',
            'product_id', 'qty', 'reason', 'sale_id', 'status', 'updated_at',
        ], $colonnes);
    }
}
