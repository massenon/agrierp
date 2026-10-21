<?php

namespace Tests\Feature;

use App\Livewire\Elevage\GestionBandes;
use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\ProductCategory;
use App\Rules\UniqueNormalise;
use App\Support\CleUnicite;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket UNI — UNICITÉ À LA SOURCE des codes de bande et des libellés de catégorie (web, absorbeur du poste, base).
 *
 * Contexte : deux bandes de même code (`AVI-2026-01`) et deux catégories de même libellé (« Aliments ») ont fait
 * planter des écrans du poste (clés dupliquées). Aucune donnée existante n'est jamais modifiée ni supprimée : on
 * empêche seulement d'en créer de nouveaux. Valeurs attendues écrites à la main.
 *
 * Décor : `PreparationExercices` (bande PON-2026-01 de 200 têtes, espèce « aviculture »).
 */
class UniciteCodesTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const LOT_POSTE = 'bbbb2222-0000-4000-8000-000000000001';

    private const LOT_AUTRE_POSTE = 'bbbb2222-0000-4000-8000-000000000002';

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2026-10-21 09:00:00');
        $this->exercice(2025, 'cloture');
        $this->exercice(2026);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function especeId(): string
    {
        return $this->pondeuses->species_id;
    }

    private function bandeDuPoste(string $id, string $code): array
    {
        return [
            'id' => $id, 'code' => $code, 'species_id' => $this->especeId(), 'stage' => 'croissance',
            'created_date' => '2026-10-20', 'initial_quantity' => 40, 'acquisition_cost' => null,
            'product_id' => null, 'status' => 'actif', 'is_active' => true, 'device_id' => 'poste-bureau',
        ];
    }

    private function creerAuWeb(string $code)
    {
        return Livewire::test(GestionBandes::class)
            ->set('species_id', $this->especeId())
            ->set('code', $code)
            ->set('stage', 'croissance')
            ->set('created_date', '2026-10-20')
            ->set('quantity', 40)
            ->call('saveLot');
    }

    // ── La clé de comparaison ──────────────────────────────────────────────────────────────────────────────────────

    public function test_la_cle_ignore_la_casse_les_espaces_autour_et_doubles_et_les_accents(): void
    {
        $this->assertSame('avi-2026-01', CleUnicite::cle('  AVI-2026-01 '));
        $this->assertSame('lot lap 7', CleUnicite::cle("LOT\t LAP   7"));
        $this->assertSame('oeufs', CleUnicite::cle('Œufs'));
        $this->assertSame('aliments', CleUnicite::cle(' ALIMENTS'));
    }

    // ── Web : création ─────────────────────────────────────────────────────────────────────────────────────────────

    public function test_le_web_refuse_un_code_deja_pris_avec_le_code_dans_le_message(): void
    {
        $composant = $this->creerAuWeb('PON-2026-01');

        $this->assertErreurSousLeChamp($composant, 'code',
            'Le code « PON-2026-01 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.');
        $this->assertSame(1, LivestockLot::count(), 'aucune bande créée');
    }

    public function test_le_web_refuse_un_code_qui_ne_differe_que_par_la_casse_et_les_espaces(): void
    {
        $this->assertErreurSousLeChamp($this->creerAuWeb('pon-2026-01'), 'code',
            'Le code « pon-2026-01 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.');
        $this->assertErreurSousLeChamp($this->creerAuWeb('  PON-2026-01  '), 'code',
            'Le code « PON-2026-01 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.');
        $this->assertSame(1, LivestockLot::count());
    }

    public function test_le_web_refuse_le_code_d_une_bande_archivee(): void
    {
        LivestockLot::create([
            'code' => 'ARCH-1', 'species_id' => $this->especeId(), 'stage' => 'ponte', 'initial_quantity' => 0,
            'current_quantity' => 0, 'created_date' => '2026-01-10', 'status' => 'cloture', 'is_active' => false,
        ]);

        $this->assertErreurSousLeChamp($this->creerAuWeb('arch-1'), 'code',
            'Le code « arch-1 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.');
        $this->assertSame(2, LivestockLot::count());
    }

    public function test_le_web_accepte_un_code_libre_et_le_range_sans_espaces_autour(): void
    {
        $this->creerAuWeb('  LOT-VOL-9 ')->assertHasNoErrors();

        $this->assertSame(1, LivestockLot::where('code', 'LOT-VOL-9')->count());
    }

    // ── La règle : modification gardant son propre code ────────────────────────────────────────────────────────────

    public function test_la_regle_laisse_une_bande_garder_son_propre_code_et_refuse_celui_d_une_autre(): void
    {
        $propre = LivestockLot::where('code', 'PON-2026-01')->firstOrFail();
        $autre = LivestockLot::create([
            'code' => 'PON-2026-02', 'species_id' => $this->especeId(), 'stage' => 'ponte', 'initial_quantity' => 5,
            'current_quantity' => 5, 'created_date' => '2026-02-01',
        ]);
        $regle = fn (string $code, ?string $ignorer) => Validator::make(['code' => $code], [
            'code' => [UniqueNormalise::bande($ignorer)],
        ])->passes();

        $this->assertTrue($regle(' pon-2026-01', $propre->id), 'sa propre ligne est ignorée, casse et espaces compris');
        $this->assertFalse($regle('PON-2026-01', $autre->id), 'le code d\'une AUTRE bande reste refusé');
        $this->assertFalse($regle('PON-2026-01', null));
        $this->assertTrue($regle('PON-2026-03', null));
    }

    public function test_le_point_de_passage_refuse_aussi_un_code_pris_meme_hors_formulaire(): void
    {
        try {
            app(\App\Actions\SaisieBandeAction::class)->creer([
                'code' => 'Pon-2026-01 ', 'species_id' => $this->especeId(), 'stage' => 'ponte',
                'created_date' => '2026-10-20', 'quantity' => 3,
            ]);
            $this->fail('un code déjà pris doit être refusé');
        } catch (ValidationException $e) {
            $this->assertSame(
                'Le code « Pon-2026-01 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.',
                $e->errors()['code'][0]
            );
        }
        $this->assertSame(1, LivestockLot::count());
    }

    // ── Absorbeur du serveur ───────────────────────────────────────────────────────────────────────────────────────

    public function test_l_absorbeur_rejette_un_code_deja_pris_sans_ecraser_et_dit_quoi_faire(): void
    {
        $avant = LivestockLot::where('code', 'PON-2026-01')->firstOrFail()->only(['id', 'stage', 'current_quantity']);

        $reponse = $this->envoyer(['livestock_lots' => [$this->bandeDuPoste(self::LOT_POSTE, 'PON-2026-01')]])->assertOk();

        $reponse->assertJsonPath('livestock_lots.accepted', []);
        $reponse->assertJsonPath('livestock_lots.rejected.0.id', self::LOT_POSTE);
        $reponse->assertJsonPath('livestock_lots.rejected.0.reason',
            'Le code « PON-2026-01 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code. '
            .'Votre bande est conservée sur ce poste : renommez-la (Élevage > Bandes & Sujets, bouton « Modifier ») puis synchronisez de nouveau.');
        $this->assertSame(1, LivestockLot::count());
        $this->assertNull(LivestockLot::find(self::LOT_POSTE));
        $this->assertSame($avant, LivestockLot::where('code', 'PON-2026-01')->firstOrFail()->only(['id', 'stage', 'current_quantity']));
    }

    public function test_l_absorbeur_rejette_le_code_qui_ne_differe_que_par_la_casse_ou_les_espaces(): void
    {
        $this->envoyer(['livestock_lots' => [$this->bandeDuPoste(self::LOT_POSTE, ' pon-2026-01 ')]])
            ->assertJsonPath('livestock_lots.accepted', [])
            ->assertJsonPath('livestock_lots.rejected.0.id', self::LOT_POSTE);

        $this->assertSame(1, LivestockLot::count());
    }

    public function test_deux_postes_qui_creent_le_meme_code_hors_ligne_le_second_est_rejete_proprement(): void
    {
        $this->envoyer(['livestock_lots' => [$this->bandeDuPoste(self::LOT_POSTE, 'LOT-VOL-9')]])
            ->assertJsonPath('livestock_lots.accepted', [self::LOT_POSTE]);

        $this->envoyer(['livestock_lots' => [$this->bandeDuPoste(self::LOT_AUTRE_POSTE, 'LOT-VOL-9')]])
            ->assertJsonPath('livestock_lots.accepted', [])
            ->assertJsonPath('livestock_lots.rejected.0.id', self::LOT_AUTRE_POSTE);

        $this->assertSame(1, LivestockLot::where('code', 'LOT-VOL-9')->count());
        $this->assertSame(self::LOT_POSTE, LivestockLot::where('code', 'LOT-VOL-9')->value('id'));
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.created')->count());
    }

    public function test_le_rejeu_du_meme_uuid_reste_accepte_sans_doublon(): void
    {
        $this->envoyer(['livestock_lots' => [$this->bandeDuPoste(self::LOT_POSTE, 'LOT-VOL-9')]])->assertOk();

        $this->envoyer(['livestock_lots' => [$this->bandeDuPoste(self::LOT_POSTE, 'LOT-VOL-9')]])
            ->assertJsonPath('livestock_lots.accepted', [self::LOT_POSTE])
            ->assertJsonPath('livestock_lots.rejected', []);

        $this->assertSame(1, LivestockLot::where('code', 'LOT-VOL-9')->count());
    }

    // ── Renommer une bande dont le code est partagé (le client corrige lui-même ses doublons) ─────────────────────

    /** Un doublon déjà en base (posé hors application, index retiré) : la bande PON-2026-01 et sa jumelle. */
    private function jumelle(string $code = 'pon-2026-01 '): string
    {
        $this->retirerLesIndex();
        DB::table('livestock_lots')->insert([
            'id' => 'bbbb3333-0000-4000-8000-000000000001', 'code' => $code, 'species_id' => $this->especeId(), 'stage' => 'ponte',
            'initial_quantity' => 9, 'current_quantity' => 9, 'created_date' => '2026-01-01', 'status' => 'actif', 'is_active' => true,
        ]);

        return 'bbbb3333-0000-4000-8000-000000000001';
    }

    public function test_le_web_laisse_renommer_une_bande_dont_le_code_est_partage_et_trace_l_audit(): void
    {
        $id = $this->jumelle();

        Livewire::test(GestionBandes::class)
            ->call('editLot', $id)
            ->assertSet('codeEnDoublon', true)
            ->set('code', 'PON-2026-03')
            ->call('updateLot')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Bande modifiée avec succès.', type: 'success');

        $this->assertSame('PON-2026-03', LivestockLot::findOrFail($id)->code);
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.renamed')->count());
    }

    public function test_le_bandeau_du_web_signale_les_doublons_sans_bloquer_et_disparait_sans_doublon(): void
    {
        Livewire::test(GestionBandes::class)->assertDontSeeHtml('data-doublons-codes');

        $this->jumelle();

        Livewire::test(GestionBandes::class)
            ->assertSeeHtml('data-doublons-codes')
            ->assertSee('1 doublon de code détecté — à renommer.');
    }

    public function test_le_web_refuse_de_renommer_vers_un_code_deja_pris(): void
    {
        $id = $this->jumelle();

        $composant = Livewire::test(GestionBandes::class)
            ->call('editLot', $id)
            ->set('code', 'PON-2026-01 ')
            ->call('updateLot');

        $this->assertErreurSousLeChamp($composant, 'code',
            'Le code « PON-2026-01 » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code.');
        $this->assertSame('pon-2026-01 ', LivestockLot::findOrFail($id)->code, 'rien n\'est écrit');
    }

    public function test_une_bande_au_code_unique_n_est_pas_renommable_meme_en_forcant_le_champ(): void
    {
        $lot = LivestockLot::where('code', 'PON-2026-01')->firstOrFail();

        Livewire::test(GestionBandes::class)
            ->call('editLot', $lot->id)
            ->assertSet('codeEnDoublon', false)
            ->set('code', 'AUTRE-1')
            ->call('updateLot');

        $this->assertSame('PON-2026-01', $lot->fresh()->code, 'le code reste immuable');
        $this->assertSame(0, AuditLog::where('action', 'livestock_lot.renamed')->count());
    }

    public function test_le_point_de_passage_ne_renomme_qu_un_code_partage(): void
    {
        $lot = LivestockLot::where('code', 'PON-2026-01')->firstOrFail();

        try {
            app(\App\Actions\SaisieBandeAction::class)->modifier($lot->id, ['stage' => 'ponte', 'status' => 'actif', 'code' => 'AUTRE-1']);
            $this->fail('un code unique ne se renomme pas');
        } catch (ValidationException $e) {
            $this->assertSame(
                "Le code d'une bande ne se modifie jamais après sa création : seul un code partagé avec une autre bande peut être corrigé.",
                $e->errors()['code'][0]
            );
        }
        $this->assertSame('PON-2026-01', $lot->fresh()->code);
    }

    public function test_l_absorbeur_accepte_le_renommage_d_une_bande_au_code_partage_et_refuse_sinon(): void
    {
        $id = $this->jumelle();
        $envoi = fn (string $idBande, string $code) => $this->envoyer(['livestock_lots' => [
            $this->bandeDuPoste($idBande, $code),
        ]]);

        // Code libre : renommage accepté, rejoué à l'identique : acquitté sans changement.
        $envoi($id, 'PON-2026-03')->assertJsonPath('livestock_lots.accepted', [$id]);
        $envoi($id, 'PON-2026-03')->assertJsonPath('livestock_lots.accepted', [$id]);
        $this->assertSame('PON-2026-03', LivestockLot::findOrFail($id)->code);
        $this->assertSame(1, AuditLog::where('action', 'livestock_lot.renamed')->count());

        // Le code n'est plus partagé : il redevient immuable.
        $envoi($id, 'PON-2026-04')
            ->assertJsonPath('livestock_lots.accepted', [])
            ->assertJsonPath('livestock_lots.rejected.0.reason', "Le code d'une bande ne se modifie jamais après sa création.");
    }

    public function test_un_doublon_anterieur_ne_bloque_pas_la_mise_a_jour_de_la_bande_qui_garde_son_code(): void
    {
        $id = $this->jumelle();

        // Changement de stade, code inchangé : accepté (le client renommera quand il le voudra).
        $this->envoyer(['livestock_lots' => [$this->bandeDuPoste($id, 'pon-2026-01 ') + ['stage' => 'ponte']]])
            ->assertJsonPath('livestock_lots.accepted', [$id])
            ->assertJsonPath('livestock_lots.rejected', []);

        $this->assertSame('pon-2026-01 ', LivestockLot::findOrFail($id)->code);
    }

    public function test_l_absorbeur_refuse_de_renommer_vers_un_code_pris(): void
    {
        $id = $this->jumelle();

        $this->envoyer(['livestock_lots' => [$this->bandeDuPoste($id, 'PON-2026-01')]])
            ->assertJsonPath('livestock_lots.accepted', [])
            ->assertJsonPath('livestock_lots.rejected.0.id', $id);
        $this->assertSame('pon-2026-01 ', LivestockLot::findOrFail($id)->code);
    }

    // ── Catégories de produits ─────────────────────────────────────────────────────────────────────────────────────

    public function test_une_categorie_de_meme_libelle_est_refusee_casse_et_espaces_ignores(): void
    {
        ProductCategory::create(['label' => 'Aliments']);

        foreach (['aliments', '  ALIMENTS ', 'Aliments'] as $libelle) {
            try {
                ProductCategory::create(['label' => $libelle]);
                $this->fail("« {$libelle} » aurait dû être refusé");
            } catch (ValidationException $e) {
                $this->assertSame(
                    'Une catégorie de produits porte déjà le libellé « '.trim($libelle).' » : choisissez un autre libellé.',
                    $e->errors()['label'][0]
                );
            }
        }
        $this->assertSame(1, ProductCategory::where('label', 'like', '%liments%')->count());
    }

    public function test_une_categorie_peut_etre_modifiee_en_gardant_son_libelle(): void
    {
        $c = ProductCategory::create(['label' => 'Aliments']);

        $c->update(['is_active' => false]);
        $c->update(['label' => ' aliments']);

        $this->assertFalse($c->fresh()->is_active);
    }

    // ── Migration d'index ──────────────────────────────────────────────────────────────────────────────────────────

    private function migration(): object
    {
        return require database_path('migrations/2026_10_21_000002_garantir_l_unicite_des_codes_et_libelles.php');
    }

    private function retirerLesIndex(): void
    {
        if (Schema::hasIndex('product_categories', ['label'], 'unique')) {
            Schema::table('product_categories', fn ($t) => $t->dropUnique('product_categories_label_unique'));
        }
        Schema::table('livestock_lots', fn ($t) => $t->dropUnique('livestock_lots_code_unique'));
    }

    public function test_la_migration_ajoute_les_index_quand_il_n_y_a_aucun_doublon(): void
    {
        $this->retirerLesIndex();
        DB::table('product_categories')->insert([
            ['id' => 'c1', 'label' => 'Outillage', 'is_active' => true],
            ['id' => 'c2', 'label' => 'Semences', 'is_active' => true],
        ]);
        $this->assertFalse(Schema::hasIndex('product_categories', ['label'], 'unique'));
        $this->assertFalse(Schema::hasIndex('livestock_lots', ['code'], 'unique'));

        $this->migration()->up();

        $this->assertTrue(Schema::hasIndex('product_categories', ['label'], 'unique'));
        $this->assertTrue(Schema::hasIndex('livestock_lots', ['code'], 'unique'));
        $this->migration()->up();   // rejouée : rien à faire, aucune erreur
        $this->assertTrue(Schema::hasIndex('product_categories', ['label'], 'unique'));
    }

    public function test_la_migration_n_ajoute_pas_l_index_s_il_y_a_des_doublons_et_ne_touche_a_aucune_donnee(): void
    {
        $this->retirerLesIndex();
        DB::table('product_categories')->insert([
            ['id' => 'c1', 'label' => 'Outillage', 'is_active' => true],
            ['id' => 'c2', 'label' => 'outillage ', 'is_active' => true],
        ]);
        DB::table('livestock_lots')->insert([
            'id' => 'b1', 'code' => 'AVI-2026-01', 'species_id' => $this->especeId(), 'stage' => 'ponte',
            'initial_quantity' => 1, 'current_quantity' => 1, 'created_date' => '2026-01-01',
        ]);
        DB::table('livestock_lots')->insert([
            'id' => 'b2', 'code' => 'avi-2026-01', 'species_id' => $this->especeId(), 'stage' => 'ponte',
            'initial_quantity' => 1, 'current_quantity' => 1, 'created_date' => '2026-01-01',
        ]);
        $messages = [];
        Log::shouldReceive('warning')->andReturnUsing(function ($m) use (&$messages) {
            $messages[] = $m;
        });

        $this->migration()->up();

        $this->assertFalse(Schema::hasIndex('product_categories', ['label'], 'unique'));
        $this->assertFalse(Schema::hasIndex('livestock_lots', ['code'], 'unique'));
        $this->assertSame(2, DB::table('product_categories')->whereIn('id', ['c1', 'c2'])->count());
        $this->assertSame(['AVI-2026-01', 'avi-2026-01'], DB::table('livestock_lots')->whereIn('id', ['b1', 'b2'])->orderBy('id')->pluck('code')->all());
        $this->assertCount(2, $messages, 'un avertissement journalisé par table en doublon');
        $this->assertStringContainsString('product_categories', $messages[0]);
        $this->assertStringContainsString('livestock_lots', $messages[1]);
    }

    // ── Commande de détection ──────────────────────────────────────────────────────────────────────────────────────

    public function test_la_commande_liste_les_doublons_avec_leurs_lignes_liees_sans_rien_modifier(): void
    {
        $this->retirerLesIndex();
        DB::table('livestock_lots')->insert([
            'id' => 'b-ancienne', 'code' => 'pon-2026-01 ', 'species_id' => $this->especeId(), 'stage' => 'ponte',
            'initial_quantity' => 9, 'current_quantity' => 9, 'created_date' => '2026-01-01',
        ]);
        DB::table('livestock_daily_entries')->insert([
            'id' => 'f-1', 'lot_id' => 'b-ancienne', 'entry_date' => '2026-02-01', 'effectif_final' => 9,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $categorie = ProductCategory::create(['label' => 'Outillage']);
        DB::table('product_categories')->insert(['id' => 'cat-2', 'label' => ' OUTILLAGE', 'is_active' => true]);
        $avant = [DB::table('livestock_lots')->count(), DB::table('product_categories')->count()];

        $this->artisan('agrierp:doublons')
            ->expectsOutputToContain('2 bandes partagent le code « pon-2026-01 »')
            ->expectsOutputToContain('b-ancienne  « pon-2026-01  »  active  (1 fiche(s), 0 ligne(s) de vente, 0 transfert(s), 0 sujet(s) nominatif(s))')
            ->expectsOutputToContain('2 catégories de produits partagent le libellé « outillage »')
            ->expectsOutputToContain('cat-2')
            ->expectsOutputToContain($categorie->id)
            ->assertSuccessful();

        $this->assertSame($avant, [DB::table('livestock_lots')->count(), DB::table('product_categories')->count()]);
    }

    public function test_la_commande_dit_qu_il_n_y_a_aucun_doublon(): void
    {
        $this->artisan('agrierp:doublons')->expectsOutputToContain('Aucun doublon')->assertSuccessful();
    }
}
