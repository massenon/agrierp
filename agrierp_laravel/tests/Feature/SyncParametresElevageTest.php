<?php

namespace Tests\Feature;

use App\Models\ElevageNumberingSetting;
use App\Models\FeedRationStandard;
use App\Models\FeedType;
use App\Models\LivestockSpecies;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.77 (Sprint 14) — LES DEUX DERNIERS RÉFÉRENTIELS D'ÉLEVAGE
 * DESCENDENT AU POSTE.
 *
 * 🔴 CE QUE CE TICKET DÉBLOQUE. L'écran Paramètres Élevage a quatre onglets ;
 * deux vivaient déjà au poste (rations depuis 14.52, calendrier prophylactique
 * depuis 14.54), deux n'y étaient pas du tout :
 *   • `feed_types` — le catalogue des aliments, **et le seul endroit du schéma
 *     où vit le poids d'un sac** ;
 *   • `elevage_numbering_settings` — les préfixes qui NOMMENT les animaux sur
 *     le terrain (R1, T1, LOT-VOL-1, FOSSE F1).
 *
 * ⚠️⚠️ LES PRÉFIXES NE SONT PAS UN CONFORT D'AFFICHAGE. Le registre papier, la
 * fiche d'élevage et l'écran Suivi Reproduction désignent le même animal par ce
 * nom. Un poste qui les ignore proposerait sa propre convention, et deux
 * registres de la même ferme cesseraient de se lire ensemble.
 *
 * ⚠️ LES DEUX SONT SERVIES EN LECTURE SEULE : le serveur ignore tout envoi les
 * concernant et le COMPTE — un rejet muet passerait pour un succès.
 */
class SyncParametresElevageTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private LivestockSpecies $aviculture;

    protected function setUp(): void
    {
        parent::setUp();

        $this->utilisateur = User::create([
            'name' => "Chef d'Élevage", 'username' => 'elevage',
            'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        $this->aviculture = LivestockSpecies::create([
            'label' => 'Aviculture (Volailles)', 'code' => 'aviculture', 'is_active' => true,
        ]);
    }

    private function tirer(array $parametres = []): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->getJson('/api/sync/pull'.($parametres ? '?'.http_build_query($parametres) : ''));
    }

    /**
     * ⚠️⚠️ LE POIDS DU SAC EST LA DONNÉE QUI MANQUE AILLEURS : sans lui,
     * l'autonomie alimentaire du Dashboard Élevage ne peut pas se calculer —
     * le stock compte des SACS, la ration se compte en GRAMMES.
     */
    public function test_the_feed_type_reaches_the_device_with_its_bag_weight(): void
    {
        FeedType::create([
            'name' => 'Aliment Ponte (Pondeuse)',
            'species_id' => $this->aviculture->id,
            'standard_bag_weight_kg' => 25,
            'price_per_kg' => 260,
            'is_active' => true,
        ]);

        $this->tirer()
            ->assertOk()
            ->assertJsonCount(1, 'feed_types')
            ->assertJsonPath('feed_types.0.name', 'Aliment Ponte (Pondeuse)')
            ->assertJsonPath('feed_types.0.standard_bag_weight_kg', '25.00')
            ->assertJsonPath('feed_types.0.price_per_kg', '260.00');
    }

    /**
     * ⚠️ LE LIBELLÉ DE L'ESPÈCE VOYAGE AVEC LE TYPE. Le poste n'a pas de table
     * des espèces : sans ce champ, la colonne « Espèce Cible » n'aurait qu'un
     * UUID à afficher. Même règle que le code espèce des bandes (F0.14).
     */
    public function test_the_species_label_travels_with_the_feed_type(): void
    {
        FeedType::create([
            'name' => 'Aliment Démarrage (Poussin)',
            'species_id' => $this->aviculture->id,
            'standard_bag_weight_kg' => 25, 'price_per_kg' => 300, 'is_active' => true,
        ]);

        $this->tirer()
            ->assertOk()
            ->assertJsonPath('feed_types.0.species_label', 'Aviculture (Volailles)')
            ->assertJsonPath('feed_types.0.species_code', 'aviculture');
    }

    /** Un type archivé ne descend plus : la ferme ne le sert plus. */
    public function test_an_archived_feed_type_is_not_served(): void
    {
        FeedType::create([
            'name' => 'Aliment retiré du catalogue',
            'species_id' => $this->aviculture->id,
            'standard_bag_weight_kg' => 25, 'price_per_kg' => 200, 'is_active' => false,
        ]);

        $this->tirer()->assertOk()->assertJsonCount(0, 'feed_types');
    }

    /** Les neuf préfixes descendent, y compris quand la ligne n'existait pas. */
    public function test_the_numbering_prefixes_reach_the_device(): void
    {
        $reponse = $this->tirer()->assertOk();

        foreach ([
            'bande_format' => 'BANDE B',
            'lapine_prefix' => 'R',
            'male_prefix' => 'M',
            'truie_prefix' => 'T',
            'verrat_prefix' => 'V',
            'portee_prefix' => 'P',
            'volaille_prefix' => 'LOT-VOL',
            'parc_prefix' => 'PARC',
            'escargot_prefix' => 'FOSSE',
        ] as $champ => $attendu) {
            $reponse->assertJsonPath("elevage_numbering.$champ", $attendu);
        }
    }

    /** Un préfixe corrigé sur le web arrive au poste au tirage suivant. */
    public function test_a_corrected_prefix_reaches_the_device(): void
    {
        ElevageNumberingSetting::current()->update(['lapine_prefix' => 'LAP']);

        $this->tirer()->assertOk()->assertJsonPath('elevage_numbering.lapine_prefix', 'LAP');
    }

    /**
     * ⚠️ SERVIS SANS FILTRE `since`, comme les rations : ces référentiels
     * pilotent un affichage, et un poste resté hors ligne depuis une correction
     * garderait sinon une convention périmée sans le savoir.
     */
    public function test_both_referentials_survive_an_incremental_pull(): void
    {
        $type = FeedType::create([
            'name' => 'Aliment Lapins', 'species_id' => $this->aviculture->id,
            'standard_bag_weight_kg' => 25, 'price_per_kg' => 290, 'is_active' => true,
        ]);
        $type->timestamps = false;
        $type->update(['updated_at' => now()->subMonths(2)]);

        $this->tirer(['since' => now()->subDay()->toIso8601String()])
            ->assertOk()
            ->assertJsonCount(1, 'feed_types')
            ->assertJsonPath('elevage_numbering.lapine_prefix', 'R');
    }

    /**
     * ⚠️⚠️ UN ENVOI SUR CES TABLES DOIT ÊTRE IGNORÉ **ET COMPTÉ**. Tant qu'une
     * table servie en lecture seule ne figure pas dans la liste des
     * référentiels, un envoi la concernant tombe dans le vide sans trace — le
     * rejet muet que ce mécanisme existe pour empêcher.
     */
    /**
     * Ticket H9b (décision D-H9 du 19/10/2026) — ces barèmes NE SONT PLUS en lecture seule : le poste les modifie
     * comme le web (`SyncParametresElevageModifiablesTest`). Un envoi INCOMPLET reste sans effet, mais il est désormais
     * REFUSÉ avec son motif au lieu d'être compté parmi les référentiels ignorés.
     */
    public function test_an_incomplete_write_back_is_refused_with_its_reason(): void
    {
        FeedRationStandard::create([
            'species_code' => 'aviculture', 'stage_label' => 'Ponte',
            'ration_g_per_day' => 120, 'is_active' => true,
        ]);

        $reponse = $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'feed_types' => [['id' => '33333333-3333-4333-8333-333333333333', 'name' => 'INVENTÉ']],
            'elevage_numbering' => [['lapine_prefix' => 'ZZZ']],
        ]);

        $reponse->assertOk()
            ->assertJsonCount(1, 'feed_types.rejected')
            ->assertJsonCount(1, 'elevage_numbering.rejected');
        $this->assertSame(0, FeedType::count());
        $this->assertSame('R', ElevageNumberingSetting::current()->lapine_prefix);
    }
}
