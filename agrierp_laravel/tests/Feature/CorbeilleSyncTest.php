<?php

namespace Tests\Feature;

use App\Actions\SaisieDepenseAction;
use App\Http\Controllers\Api\SyncController;
use App\Models\AuditLog;
use App\Models\CorbeilleOperation;
use App\Models\Customer;
use App\Models\Expense;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\User;
use App\Services\CorbeilleService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Ramsey\Uuid\Uuid;
use Tests\TestCase;

/**
 * Ticket ARC2 (PRD `docs/prd/archives.md` § 6) — LA CORBEILLE AU POSTE : l'instantané qui descend (`corbeille`) et les
 * demandes qui montent (`corbeille_demandes`).
 *
 * ⚠️⚠️ Ce que ces tests protègent : le poste n'envoie que la DEMANDE ; le serveur fait les effets par
 * `CorbeilleService`, le point de passage de la page web (mêmes règles, mêmes messages) ; une demande rejouée n'est jamais
 * rejouée ; la liste, qui agrège les archives de TOUS les modules, ne descend qu'à l'administrateur.
 */
class CorbeilleSyncTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();
        $this->caissier = User::create(['name' => 'Caissière', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $this->caissier->assignRole('caissier');
    }

    private function archive(string $nom = 'Kossi Adjovi'): Customer
    {
        return Customer::create(['name' => $nom, 'phone' => '+22997000001', 'is_active' => false]);
    }

    private function demande(string $action, string $type, string $id, array $plus = []): array
    {
        return ['id' => (string) Str::uuid(), 'type' => $type, 'element_id' => $id, 'action' => $action, 'device_id' => 'poste-test'] + $plus;
    }

    private function pousser(User $u, array $demandes, array $plus = []): array
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test', 'corbeille_demandes' => $demandes] + $plus)->assertOk()->json();
    }

    /** @return array<string, mixed> la page 1 du tirage paginé */
    private function tirer(User $u): array
    {
        return $this->actingAs($u, 'sanctum')->getJson('/api/sync/pull?page=1')->assertOk()->json();
    }

    // ───────────────────────────────────── tirage ─────────────────────────────────────

    public function test_l_instantane_descend_a_l_administrateur_avec_ce_que_le_serveur_permet(): void
    {
        $client = $this->archive('Kossi Adjovi');
        $depense = app(SaisieDepenseAction::class)->creer($this->document());
        app(SaisieDepenseAction::class)->archiver($depense->id);

        $corps = $this->tirer($this->admin);

        $this->assertContains('corbeille', $corps['tables_servies']);
        $lignes = collect($corps['corbeille'])->keyBy('type');
        $this->assertCount(2, $corps['corbeille']);

        $c = $lignes['clients'];
        $this->assertSame(Uuid::uuid5(CorbeilleService::ESPACE_CORBEILLE, 'clients:'.$client->id)->toString(), $c['id']);
        $this->assertSame($client->id, $c['element_id']);
        $this->assertSame('Kossi Adjovi', $c['titre']);
        $this->assertSame('+22997000001', $c['detail']);
        $this->assertSame('ventes', $c['module']);
        $this->assertSame('2026-06-20 09:00:00', $c['archive_le'], 'heure murale du serveur, jamais convertie');
        $this->assertTrue($c['restaurable']);
        $this->assertNull($c['motif_restauration']);
        $this->assertTrue($c['supprimable']);
        $this->assertNull($c['motif_suppression']);

        $d = $lignes['depenses'];
        $this->assertFalse($d['restaurable']);
        $this->assertSame(CorbeilleService::REFUS_DEPENSE, $d['motif_restauration']);
        $this->assertFalse($d['supprimable']);
        $this->assertNotEmpty($d['motif_suppression']);
    }

    /** La liste agrège les archives de TOUS les modules : un compte sans `manage-parametres` n'en reçoit rien. */
    public function test_l_instantane_ne_descend_pas_a_un_compte_sans_le_droit(): void
    {
        $this->archive();

        $corps = $this->tirer($this->caissier);

        $this->assertNotContains('corbeille', $corps['tables_servies']);
        $this->assertArrayNotHasKey('corbeille', $corps);
        // et la réponse COMPLÈTE des postes anciens (sans `page`), qui ne filtre pas les tables, ne fuit pas non plus
        $ancien = $this->actingAs($this->caissier, 'sanctum')->getJson('/api/sync/pull')->assertOk()->json();
        $this->assertSame([], $ancien['corbeille'] ?? []);
        $this->assertNotEmpty(app(CorbeilleService::class)->elements(), "l'élément existe bien");
    }

    public function test_l_instantane_est_remplace_en_entier_a_chaque_tirage(): void
    {
        $client = $this->archive();
        $this->assertCount(1, $this->tirer($this->admin)['corbeille']);

        $client->update(['is_active' => true]);

        $this->assertSame([], $this->tirer($this->admin)['corbeille'], 'liste vide servie (clé présente), jamais clé absente');
        $this->assertArrayHasKey('corbeille', SyncController::PERMISSIONS_DE_TIRAGE);
        $this->assertSame(['manage-parametres'], SyncController::PERMISSIONS_DE_TIRAGE['corbeille']);
    }

    // ───────────────────────────────────── envoi : restauration ─────────────────────────────────────

    public function test_une_demande_de_restauration_est_rejouee_par_le_serveur(): void
    {
        $client = $this->archive();
        $d = $this->demande('restaurer', 'clients', $client->id);

        $reponse = $this->pousser($this->admin, [$d]);

        $this->assertSame([$d['id']], $reponse['corbeille_demandes']['accepted']);
        $this->assertSame([], $reponse['corbeille_demandes']['rejected']);
        $this->assertTrue((bool) $client->fresh()->is_active);
        $this->assertSame(1, AuditLog::where('action', 'corbeille.restored')->count());
        $operation = CorbeilleOperation::find($d['id']);
        $this->assertSame('accepte', $operation->issue);
        $this->assertSame('poste-test', $operation->device_id, 'le poste qui a demandé');
        $this->assertSame($this->admin->id, $operation->user_id);
        $this->assertSame('Kossi Adjovi', $operation->titre);
    }

    /** IDEMPOTENCE : une demande déjà acceptée, renvoyée (acquittement perdu), est acquittée sans rien rejouer. */
    public function test_une_demande_acceptee_renvoyee_n_est_jamais_rejouee(): void
    {
        $client = $this->archive();
        $d = $this->demande('restaurer', 'clients', $client->id);
        $this->pousser($this->admin, [$d]);
        Customer::whereKey($client->id)->update(['is_active' => false]);      // rearchivé entre-temps, par quelqu'un d'autre

        $reponse = $this->pousser($this->admin, [$d]);

        $this->assertSame([$d['id']], $reponse['corbeille_demandes']['accepted']);
        $this->assertFalse((bool) $client->fresh()->is_active, 'rien n\'est rejoué : la demande a déjà eu son effet');
        $this->assertSame(1, AuditLog::where('action', 'corbeille.restored')->count());
        $this->assertSame(1, CorbeilleOperation::where('action', 'restaurer')->count());
    }

    /** Une dépense ne se restaure pas : le serveur refuse avec le MÊME message que la page web, et n'écrit rien. */
    public function test_une_demande_de_restauration_d_une_depense_est_refusee_avec_le_message_du_web(): void
    {
        $depense = app(SaisieDepenseAction::class)->creer($this->document());
        app(SaisieDepenseAction::class)->archiver($depense->id);
        $d = $this->demande('restaurer', 'depenses', $depense->id);

        $reponse = $this->pousser($this->admin, [$d]);

        $this->assertSame([], $reponse['corbeille_demandes']['accepted']);
        $this->assertSame([['id' => $d['id'], 'reason' => CorbeilleService::REFUS_DEPENSE]], $reponse['corbeille_demandes']['rejected']);
        $this->assertFalse((bool) Expense::find($depense->id)->is_active);
        $this->assertSame(0, AuditLog::where('action', 'corbeille.restored')->count());
        $refus = CorbeilleOperation::where('issue', 'refuse')->first();
        $this->assertSame('restaurer', $refus->action);
        $this->assertSame(CorbeilleService::REFUS_DEPENSE, $refus->motif);
        $this->assertNotSame($d['id'], $refus->id, "l'identifiant de la demande reste libre pour la relance");
        // « Relancer » : la même demande est rejugée (et refusée encore), jamais acquittée sur la foi du premier refus
        $this->assertCount(1, $this->pousser($this->admin, [$d])['corbeille_demandes']['rejected']);
    }

    /** Une demande refusée puis devenue possible (la cause a disparu) est acceptée à la relance. */
    public function test_une_demande_refusee_est_rejugee_a_la_relance(): void
    {
        $client = $this->archive();
        $client->update(['is_active' => true]);              // déjà restauré ailleurs → refus
        $d = $this->demande('restaurer', 'clients', $client->id);
        $this->assertCount(1, $this->pousser($this->admin, [$d])['corbeille_demandes']['rejected']);

        $client->update(['is_active' => false]);

        $this->assertSame([$d['id']], $this->pousser($this->admin, [$d])['corbeille_demandes']['accepted']);
        $this->assertTrue((bool) $client->fresh()->is_active);
    }

    // ───────────────────────────────────── envoi : suppression définitive ─────────────────────────────────────

    public function test_une_demande_de_suppression_exige_le_mot_et_efface(): void
    {
        $client = $this->archive();

        $sansMot = $this->demande('supprimer', 'clients', $client->id);
        $mauvais = $this->demande('supprimer', 'clients', $client->id, ['confirmation' => 'supprimer']);
        $reponse = $this->pousser($this->admin, [$sansMot, $mauvais]);
        $this->assertCount(2, $reponse['corbeille_demandes']['rejected']);
        $this->assertSame(CorbeilleService::MESSAGE_CONFIRMATION, $reponse['corbeille_demandes']['rejected'][0]['reason']);
        $this->assertDatabaseHas('customers', ['id' => $client->id]);

        $bonne = $this->demande('supprimer', 'clients', $client->id, ['confirmation' => 'SUPPRIMER']);
        $reponse = $this->pousser($this->admin, [$bonne]);

        $this->assertSame([$bonne['id']], $reponse['corbeille_demandes']['accepted']);
        $this->assertDatabaseMissing('customers', ['id' => $client->id]);
        $this->assertSame(1, AuditLog::where('action', 'corbeille.deleted')->count());
        $this->assertSame('Kossi Adjovi', CorbeilleOperation::find($bonne['id'])->titre);
        // renvoi de la demande acquittée : acquittée encore (l'élément n'existe plus, ce n'est pas un échec)
        $this->assertSame([$bonne['id']], $this->pousser($this->admin, [$bonne])['corbeille_demandes']['accepted']);
        $this->assertSame(1, AuditLog::where('action', 'corbeille.deleted')->count());
    }

    public function test_une_demande_de_suppression_d_un_element_reference_est_refusee(): void
    {
        $client = $this->archive('SOGEA');
        $produit = Product::create(['sku' => 'ALI-001', 'name' => 'Maïs', 'category_id' => ProductCategory::create(['label' => 'Aliments', 'is_active' => true])->id, 'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true]);
        $vente = Sale::create(['customer_id' => $client->id, 'payment_mode' => 'especes', 'subtotal' => 5000, 'discount' => 0, 'total' => 5000, 'status' => 'validee', 'sold_at' => '2026-06-10 10:00:00']);
        SaleLine::create(['sale_id' => $vente->id, 'product_id' => $produit->id, 'qty' => 1, 'unit_price' => 5000, 'manual_total_amount' => 5000]);
        $d = $this->demande('supprimer', 'clients', $client->id, ['confirmation' => 'SUPPRIMER']);

        $reponse = $this->pousser($this->admin, [$d]);

        $this->assertSame([], $reponse['corbeille_demandes']['accepted']);
        $this->assertStringContainsString('SOGEA est référencé par 1 vente(s)', $reponse['corbeille_demandes']['rejected'][0]['reason']);
        $this->assertDatabaseHas('customers', ['id' => $client->id]);
        $this->assertSame(0, AuditLog::where('action', 'corbeille.deleted')->count());
    }

    // ───────────────────────────────────── droits et formes ─────────────────────────────────────

    public function test_un_compte_sans_le_droit_est_refuse_demande_par_demande(): void
    {
        $client = $this->archive();
        $d = $this->demande('restaurer', 'clients', $client->id);

        $reponse = $this->pousser($this->caissier, [$d]);

        $this->assertSame([], $reponse['corbeille_demandes']['accepted']);
        $this->assertSame($d['id'], $reponse['corbeille_demandes']['rejected'][0]['id']);
        $this->assertStringContainsString('restaurer ou supprimer définitivement un élément de la corbeille', $reponse['corbeille_demandes']['rejected'][0]['reason']);
        $this->assertFalse((bool) $client->fresh()->is_active);
        $this->assertSame(0, CorbeilleOperation::count());
    }

    public function test_type_inconnu_action_inconnue_et_identifiant_invalide(): void
    {
        $client = $this->archive();

        $reponse = $this->pousser($this->admin, [
            $this->demande('restaurer', 'App\\Models\\User', $this->admin->id),
            $this->demande('restaurer', 'utilisateurs', $this->admin->id),
            $this->demande('detruire', 'clients', $client->id),
            ['id' => 'pas-un-uuid', 'type' => 'clients', 'element_id' => $client->id, 'action' => 'restaurer'],
            $this->demande('restaurer', 'clients', 'pas-un-uuid'),
        ]);

        $this->assertSame([], $reponse['corbeille_demandes']['accepted']);
        $this->assertCount(5, $reponse['corbeille_demandes']['rejected']);
        $this->assertSame(CorbeilleService::MESSAGE_RESTAURATION_INTROUVABLE, $reponse['corbeille_demandes']['rejected'][0]['reason']);
        $this->assertTrue((bool) User::find($this->admin->id)->is_active);
        $this->assertFalse((bool) $client->fresh()->is_active);
    }

    public function test_une_cle_qui_n_est_pas_une_liste_est_ecartee_et_signalee(): void
    {
        $reponse = $this->actingAs($this->admin, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test', 'corbeille_demandes' => 'x'])->assertOk()->json();

        $this->assertArrayHasKey('corbeille_demandes', $reponse['cles_invalides']);
        $this->assertSame(['accepted' => [], 'rejected' => []], $reponse['corbeille_demandes']);
    }

    /** Traitée EN DERNIER : l'archivage du même envoi est connu du serveur avant la demande qui le vise. */
    public function test_la_demande_est_traitee_apres_l_archivage_du_meme_envoi(): void
    {
        $client = Customer::create(['name' => 'Kossi Adjovi', 'phone' => '+22997000001', 'is_active' => true]);
        $d = $this->demande('supprimer', 'clients', $client->id, ['confirmation' => 'SUPPRIMER']);

        $reponse = $this->pousser($this->admin, [$d], ['customers' => [[
            'id' => $client->id, 'name' => 'Kossi Adjovi', 'phone' => '+22997000001', 'is_active' => false, 'device_id' => 'poste-test',
        ]]]);

        $this->assertContains($client->id, $reponse['customers']['accepted'], json_encode($reponse['customers']));
        $this->assertSame([$d['id']], $reponse['corbeille_demandes']['accepted'], json_encode($reponse['corbeille_demandes']));
        $this->assertDatabaseMissing('customers', ['id' => $client->id]);
    }
}
