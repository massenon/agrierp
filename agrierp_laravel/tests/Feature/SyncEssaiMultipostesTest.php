<?php

namespace Tests\Feature;

use App\Actions\RecordSaleAccountingEntryAction;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Support\MotifsRefusPush;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use App\Models\Permission;
use App\Models\Role;
use Tests\TestCase;

/**
 * Ticket S-T9 — DÉFAUTS TROUVÉS PAR L'ESSAI À PLUSIEURS POSTES CONTRE LE VRAI SERVEUR (MariaDB, coupures au hasard,
 * `agrierp_flutter/outils/essai_multipostes.sh`), verrouillés ici sur l'envoi.
 *
 *  1. Deux comptoirs vendent dans la même bande le même jour, sur la fiche qu'ils ont tirée : chacun la renvoyait
 *     avec SA vente, le serveur l'écrivait (dernier écrivain) et exemptait la vente (15.30) — un sujet vendu jamais
 *     sorti de la bande. La vente d'une fiche connue appartient désormais au serveur : chaque vente l'incrémente.
 *  2. La caisse crée la fiche du jour sous SON identifiant dès qu'elle vend ; la fiche de l'animalier (même bande,
 *     même jour) était ensuite refusée (« Une fiche existe déjà… ») : morts et aliment jamais connus du serveur.
 *     Fusion prudente par (bande, jour), réponse `merged`.
 *  3. Un envoi interbloqué (MariaDB, deux comptoirs en même temps) partait en 500 À MOITIÉ ÉCRIT : la fiche créée,
 *     pas ses ventes ; au renvoi, chaque vente comptait ses sujets une seconde fois. L'envoi est atomique.
 */
class SyncEssaiMultipostesTest extends TestCase
{
    use RefreshDatabase;

    private const JOUR = '2026-10-14';

    private Product $poulet;

    private LivestockLot $bande;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow(self::JOUR.' 12:00:00');

        foreach (['view-ventes', 'manage-ventes', 'view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('caissier', 'web')->givePermissionTo(['view-ventes', 'manage-ventes']);
        Role::findOrCreate('animalier', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-ventes', 'manage-ventes', 'view-elevage', 'manage-elevage']);

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes de marchandises', 7], ['443', 'TVA collectée', 4]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $espece = LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'aviculture', 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Volailles', 'is_active' => true]);
        $this->poulet = Product::create([
            'sku' => 'AVI-001', 'name' => 'Poulet goliath', 'category_id' => $categorie->id,
            'species_id' => $espece->id, 'unit' => 'u', 'pricing_mode' => 'fourchette',
            'price_min' => 3_000, 'price_max' => 4_000, 'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true,
        ]);
        $this->bande = LivestockLot::create([
            'code' => 'ESSAI-A', 'species_id' => $espece->id, 'stage' => 'engraissement',
            'initial_quantity' => 300, 'current_quantity' => 300,
            'created_date' => '2026-10-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function vente(string $id, int $qte, array $remplacements = []): array
    {
        return array_merge([
            'id' => $id, 'payment_mode' => 'especes', 'status' => 'validee',
            'subtotal' => 3_500 * $qte, 'discount' => 0, 'total' => 3_500 * $qte,
            'sold_at' => self::JOUR.' 10:00:00',
            'lines' => [['product_id' => $this->poulet->id, 'lot_id' => $this->bande->id, 'qty' => $qte, 'unit_price' => 3_500, 'manual_total_amount' => 3_500 * $qte]],
        ], $remplacements);
    }

    private function fiche(string $id, array $valeurs = []): array
    {
        return array_merge([
            'id' => $id, 'lot_id' => $this->bande->id, 'entry_date' => self::JOUR,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
        ], $valeurs);
    }

    private function pousser(User $compte, array $fiches, array $ventes = [])
    {
        return $this->actingAs($compte, 'sanctum')->postJson('/api/sync/push', array_filter([
            'livestock_daily_entries' => $fiches,
            'sales' => $ventes,
        ]))->assertOk();
    }

    private function ficheDuJour(): LivestockDailyEntry
    {
        return LivestockDailyEntry::where('lot_id', $this->bande->id)->whereDate('entry_date', self::JOUR)->firstOrFail();
    }

    // ═══ 1. La vente d'une fiche connue appartient au serveur ═══

    /** 🔴 Deux comptoirs, une fiche tirée par les deux : 1 + 1 sujets vendus, la fiche en porte 2 (elle en portait 1). */
    public function test_deux_comptoirs_vendent_sur_la_meme_fiche_tiree_chaque_vente_compte(): void
    {
        $caissier = $this->compte('caissier');
        $f = LivestockDailyEntry::create(['lot_id' => $this->bande->id, 'entry_date' => self::JOUR, 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'effectif_final' => 300]);

        $this->pousser($caissier, [$this->fiche($f->id, ['vente' => 1])], [$this->vente('a1111111-1111-4111-8111-111111111111', 1)]);
        $this->pousser($caissier, [$this->fiche($f->id, ['vente' => 1])], [$this->vente('a2222222-2222-4222-8222-222222222222', 1)]);

        $this->assertSame(2, (int) $f->fresh()->vente, 'une vente comptée zéro fois : la fiche du second comptoir écrasait la première');
        $this->assertSame(298, (int) $f->fresh()->effectif_final);
        $this->assertSame(298, (int) $this->bande->fresh()->current_quantity);
    }

    /** 🔴 L'animalier renvoie la fiche avec la vente qu'il avait tirée (0) : les ventes des comptoirs restent. */
    public function test_la_fiche_de_l_animalier_n_efface_pas_les_ventes_d_un_autre_poste(): void
    {
        $f = LivestockDailyEntry::create(['lot_id' => $this->bande->id, 'entry_date' => self::JOUR, 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'effectif_final' => 300]);
        $this->pousser($this->compte('caissier'), [], [$this->vente('a1111111-1111-4111-8111-111111111111', 3)]);
        $this->assertSame(3, (int) $f->fresh()->vente);

        $this->pousser($this->compte('animalier'), [$this->fiche($f->id, ['mort' => 2, 'vente' => 0])]);

        $this->assertSame(3, (int) $f->fresh()->vente);
        $this->assertSame(2, (int) $f->fresh()->mort, 'le dernier écrivain gagne toujours sur la saisie d\'élevage');
        $this->assertSame(295, (int) $f->fresh()->effectif_final);
    }

    /** Une fiche CRÉÉE par l'envoi porte les ventes du même envoi (15.30, inchangé) ; renvoyée, rien ne double. */
    public function test_une_fiche_creee_par_l_envoi_porte_ses_ventes_et_son_renvoi_ne_double_rien(): void
    {
        $caissier = $this->compte('caissier');
        $envoi = fn () => $this->pousser($caissier, [$this->fiche('f1111111-1111-4111-8111-111111111111', ['vente' => 4])], [$this->vente('a1111111-1111-4111-8111-111111111111', 4)]);

        $envoi();
        $envoi();

        $this->assertSame(4, (int) $this->ficheDuJour()->vente);
        $this->assertSame(1, Sale::count());
    }

    /** 🔴 Vente refusée dans l'envoi qui crée sa fiche : ses sujets ne restent pas « vendus » sur la fiche. */
    public function test_une_vente_refusee_est_retiree_de_la_fiche_creee_par_le_meme_envoi(): void
    {
        $reponse = $this->pousser(
            $this->compte('caissier'),
            [$this->fiche('f1111111-1111-4111-8111-111111111111', ['vente' => 2])],
            [$this->vente('a1111111-1111-4111-8111-111111111111', 2, ['total' => 1])],
        );

        $this->assertCount(1, $reponse->json('sales.rejected'));
        $this->assertSame(0, (int) $this->ficheDuJour()->vente);
        $this->assertSame(300, (int) $this->ficheDuJour()->effectif_final);

        // Relancée et corrigée plus tard : comptée une fois.
        $this->pousser($this->compte('animalier'), [], []);
        $this->pousser(User::where('username', 'caissier')->first(), [['id' => 'f1111111-1111-4111-8111-111111111111', 'lot_id' => $this->bande->id, 'entry_date' => self::JOUR]], [$this->vente('a1111111-1111-4111-8111-111111111111', 2)]);
        $this->assertSame(2, (int) $this->ficheDuJour()->vente);
    }

    // ═══ 2. Fusion par (bande, jour) ═══

    /** 🔴 La fiche de l'animalier arrive après celle née d'une vente au comptoir : réunie, pas refusée. */
    public function test_la_fiche_de_l_animalier_est_reunie_a_celle_nee_d_une_vente(): void
    {
        $this->pousser($this->compte('caissier'), [$this->fiche('f1111111-1111-4111-8111-111111111111', ['vente' => 2])], [$this->vente('a1111111-1111-4111-8111-111111111111', 2)]);

        $reponse = $this->pousser($this->compte('animalier'), [$this->fiche('f2222222-2222-4222-8222-222222222222', ['mort' => 3, 'feed_qty_kg' => 12.5])]);

        $reponse->assertJsonPath('livestock_daily_entries.accepted', ['f2222222-2222-4222-8222-222222222222']);
        $reponse->assertJsonPath('livestock_daily_entries.merged.0.id_serveur', 'f1111111-1111-4111-8111-111111111111');
        $f = $this->ficheDuJour();
        $this->assertSame([3, 2, 12.5, 295], [(int) $f->mort, (int) $f->vente, (float) $f->feed_qty_kg, (int) $f->effectif_final]);
        $this->assertSame(1, LivestockDailyEntry::count());
    }

    /** La fiche née d'une vente arrive APRÈS celle de l'animalier : réunie, la vente comptée par la vente. */
    public function test_la_fiche_du_comptoir_est_reunie_a_celle_de_l_animalier_sans_rien_ecraser(): void
    {
        $this->pousser($this->compte('animalier'), [$this->fiche('f2222222-2222-4222-8222-222222222222', ['mort' => 3])]);

        $reponse = $this->pousser($this->compte('caissier'), [$this->fiche('f1111111-1111-4111-8111-111111111111', ['vente' => 2])], [$this->vente('a1111111-1111-4111-8111-111111111111', 2)]);

        $reponse->assertJsonPath('livestock_daily_entries.merged.0.id_serveur', 'f2222222-2222-4222-8222-222222222222');
        $f = $this->ficheDuJour();
        $this->assertSame([3, 2, 295], [(int) $f->mort, (int) $f->vente, (int) $f->effectif_final]);
    }

    /** Deux saisies d'élevage DIFFÉRENTES : refus motivé (l'éleveur compare) ; la même saisie renvoyée : réunie. */
    public function test_deux_saisies_d_elevage_differentes_restent_refusees_les_memes_sont_reunies(): void
    {
        $animalier = $this->compte('animalier');
        $this->pousser($animalier, [$this->fiche('f2222222-2222-4222-8222-222222222222', ['mort' => 3])]);

        $refus = $this->pousser($animalier, [$this->fiche('f3333333-3333-4333-8333-333333333333', ['mort' => 1])]);
        $this->assertSame(MotifsRefusPush::ficheEnDouble(), $refus->json('livestock_daily_entries.rejected.0.reason'));

        $meme = $this->pousser($animalier, [$this->fiche('f4444444-4444-4444-8444-444444444444', ['mort' => 3])]);
        $meme->assertJsonPath('livestock_daily_entries.merged.0.id_serveur', 'f2222222-2222-4222-8222-222222222222');
        $this->assertSame(3, (int) $this->ficheDuJour()->mort);
    }

    /** 🔴 Le comptoir renvoie sa fiche née d'une vente (accusé perdu) après la fusion de l'animalier : acceptée, rien écrit. */
    public function test_le_renvoi_de_la_fiche_du_comptoir_apres_fusion_n_est_ni_refuse_ni_ecrit(): void
    {
        $caissier = $this->compte('caissier');
        $this->pousser($caissier, [$this->fiche('f1111111-1111-4111-8111-111111111111', ['vente' => 2])], [$this->vente('a1111111-1111-4111-8111-111111111111', 2)]);
        $this->pousser($this->compte('animalier'), [$this->fiche('f2222222-2222-4222-8222-222222222222', ['mort' => 3])]);

        $reponse = $this->pousser($caissier, [$this->fiche('f1111111-1111-4111-8111-111111111111', ['vente' => 2])], [$this->vente('a1111111-1111-4111-8111-111111111111', 2)]);

        $reponse->assertJsonPath('livestock_daily_entries.rejected', []);
        $f = $this->ficheDuJour();
        $this->assertSame([3, 2], [(int) $f->mort, (int) $f->vente]);
    }

    /** Une vraie saisie d'élevage sous un compte caissier reste refusée (S1, inchangé). */
    public function test_le_caissier_ne_fait_toujours_pas_de_saisie_d_elevage(): void
    {
        $f = LivestockDailyEntry::create(['lot_id' => $this->bande->id, 'entry_date' => self::JOUR, 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'effectif_final' => 300]);

        $reponse = $this->pousser($this->compte('caissier'), [$this->fiche($f->id, ['mort' => 4])]);

        $this->assertSame(MotifsRefusPush::ficheEleveurRequise(), $reponse->json('livestock_daily_entries.rejected.0.reason'));
        $this->assertSame(0, (int) $f->fresh()->mort);
    }

    // ═══ 3. L'envoi est atomique ═══

    /** 🔴 Un échec au milieu de l'envoi (après la fiche, pendant la vente) n'écrit rien ; le renvoi compte UNE fois. */
    /**
     * 🔴→✅ Ticket S-T12 (essai à plusieurs postes, graine 7, MariaDB) — DEUX ENVOIS SIMULTANÉS SUR LA MÊME FICHE CONNUE.
     * Deux caisses vendent chacune un lapin de la même bande le même jour ; leurs envois arrivent ensemble. Chaque
     * transaction lisait `vente` = 5 sans verrou et écrivait 6 : une vente comptée zéro fois (5 → 6 au lieu de 7). SQLite
     * (cette suite) sérialise les transactions et ne peut pas le montrer : ce garde-fou lit le code — la fiche doit être
     * relue SOUS VERROU (`lockForUpdate`) avant l'incrément ; l'essai sur MariaDB en est la preuve exécutée.
     */
    public function test_l_increment_de_la_vente_d_une_fiche_relit_la_fiche_sous_verrou(): void
    {
        $source = (string) file_get_contents(app_path('Actions/RecordSaleOnFicheElevageAction.php'));
        $increment = strpos($source, '$entry->vente = (int) $entry->vente + $qty;');
        $this->assertNotFalse($increment, 'incrément de la vente introuvable');
        $avant = substr($source, 0, $increment);
        $verrou = strrpos($avant, '->lockForUpdate()');
        $this->assertNotFalse($verrou, 'la fiche n\'est pas relue sous verrou avant l\'incrément de sa vente');
        $recherche = strrpos($avant, '$this->ficheDuJour(');
        $this->assertNotFalse($recherche, 'la fiche du jour n\'est plus cherchée par `ficheDuJour`');
        $this->assertGreaterThan($recherche, $verrou,
            'le verrou doit porter sur la relecture APRÈS la recherche de la fiche (lecture à jour), pas avant');
    }

    /**
     * 🔴→✅ Ticket S-T12 (essai à plusieurs postes, graine 5, MariaDB) — DEUX COMPTOIRS CRÉENT LA MÊME FICHE AU MÊME
     * INSTANT. Le second envoi bute sur l'unicité (bande, jour) et relit la fiche du premier pour la fusion prudente
     * (S-T9) ; une lecture ordinaire lisait l'instantané de SA transaction, où la fiche validée entre-temps n'existe pas
     * encore : « aucune », et la fiche de la caisse (sa vente seulement) était refusée « en double ». SQLite n'a pas cet
     * isolement : ce garde-fou lit le code — la relecture qui suit la violation d'unicité est VERROUILLANTE.
     */
    public function test_la_relecture_apres_une_creation_simultanee_de_fiche_est_verrouillante(): void
    {
        $source = (string) file_get_contents(app_path('Http/Controllers/Api/SyncController.php'));
        $debut = strpos($source, 'catch (\\Illuminate\\Database\\UniqueConstraintViolationException $e) {');
        $this->assertNotFalse($debut, 'le rattrapage de la violation d\'unicité des fiches a disparu');
        $bloc = substr($source, $debut, (int) strpos($source, '$this->ficheFusionnable($validated, $occupante)', $debut) - $debut);
        $this->assertStringContainsString('->lockForUpdate()->first()', $bloc,
            'la fiche concurrente doit être relue sous verrou : une lecture ordinaire ne la voit pas (instantané de la transaction)');
    }

    /**
     * 🔴→✅ Ticket S-T12 (essai à plusieurs postes, graine 314, MariaDB) — LA FICHE DU JOUR CRÉÉE PAR UN AUTRE ENVOI
     * ENTRE LA LECTURE ET L'INSERTION. La vente (web ou poste) cherche la fiche (bande, jour), n'en trouve pas, et
     * l'insère ; un poste vient de créer la même au même instant : l'unicité (bande, jour) refusait la seconde insertion
     * (`SQLSTATE 1062`) — la caisse du web affichait l'erreur, la vente était perdue. Simulé ici : la fiche concurrente
     * (1 sujet vendu) est écrite JUSTE AVANT l'insertion de celle de la vente. Attendu : la vente de 2 sujets s'ajoute à
     * elle (3 vendus, effectif 297), aucune erreur, une seule fiche.
     */
    public function test_une_fiche_creee_au_meme_instant_par_un_autre_envoi_recoit_la_vente(): void
    {
        $caissier = $this->compte('caissier');
        $concurrente = null;
        LivestockDailyEntry::creating(function (LivestockDailyEntry $f) use (&$concurrente) {
            if ($concurrente === null && $f->lot_id === $this->bande->id) {
                $concurrente = (string) \Illuminate\Support\Str::uuid();
                \Illuminate\Support\Facades\DB::table('livestock_daily_entries')->insert([
                    'id' => $concurrente, 'lot_id' => $this->bande->id, 'entry_date' => self::JOUR,
                    'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 1, 'don' => 0, 'effectif_final' => 299,
                    'created_at' => now(), 'updated_at' => now(),
                ]);
            }
        });

        $this->pousser($caissier, [], [$this->vente('a3333333-3333-4333-8333-333333333333', 2)])
            ->assertJsonPath('sales.accepted.0', 'a3333333-3333-4333-8333-333333333333');

        $this->assertNotNull($concurrente, 'la création concurrente n\'a pas été simulée');
        $this->assertSame(1, LivestockDailyEntry::where('lot_id', $this->bande->id)->count());
        $this->assertSame(3, (int) $this->ficheDuJour()->vente, '1 vendu par l\'autre envoi + 2 par celui-ci');
        $this->assertSame(297, (int) $this->ficheDuJour()->effectif_final);
    }

    public function test_un_envoi_en_echec_n_ecrit_rien_et_son_renvoi_ne_double_pas_la_vente(): void
    {
        $caissier = $this->compte('caissier');
        $envoi = [
            'livestock_daily_entries' => [$this->fiche('f1111111-1111-4111-8111-111111111111', ['vente' => 2])],
            'sales' => [$this->vente('a1111111-1111-4111-8111-111111111111', 2)],
        ];

        $this->app->instance(RecordSaleAccountingEntryAction::class, new class extends RecordSaleAccountingEntryAction
        {
            public function __construct() {}

            public function execute(Sale $sale): ?\App\Models\AccountingEntry
            {
                throw new \RuntimeException('panne simulée (interblocage)');
            }
        });
        $this->withoutExceptionHandling();
        try {
            $this->actingAs($caissier, 'sanctum')->postJson('/api/sync/push', $envoi);
            $this->fail('l\'envoi aurait dû échouer');
        } catch (\RuntimeException) {
        }
        $this->assertSame(0, LivestockDailyEntry::count(), 'la fiche ne doit pas survivre à l\'échec de sa vente');

        $this->app->forgetInstance(RecordSaleAccountingEntryAction::class);
        $this->actingAs($caissier, 'sanctum')->postJson('/api/sync/push', $envoi)->assertOk();

        $this->assertSame(2, (int) $this->ficheDuJour()->vente, '2N : la fiche connue au renvoi ne porte plus la vente');
    }
}
