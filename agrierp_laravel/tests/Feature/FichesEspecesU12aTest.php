<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheEscargots;
use App\Livewire\Elevage\FicheLapins;
use App\Livewire\Elevage\FichePorcs;
use App\Livewire\Elevage\FicheReproducteurs;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U12a — DÉFAUTS DU WEB TROUVÉS EN ALIGNANT LES FICHES LAPINS, PORCS, REPRODUCTEURS ET ESCARGOTS DU POSTE.
 *
 * 🔴 1. Le défaut de la fiche Pondeuses (U11) existait sur les fiches Escargots et Reproducteurs : `loadDay()` lisait
 *       la fiche dans `monthlyEntries` (mois COURANT seulement). Un jour du mois précédent s'ouvrait vide et
 *       « Enregistrer ce Jour » l'écrasait avec des zéros. Lapins et Porcs relisaient déjà n'importe quel jour.
 * 🔴 2. Fiche Reproducteurs : ni `mount()` ni un changement de date ne chargeaient le jour — le jour même s'ouvrait à
 *       zéro (une vente du POS, une saisie précédente) et s'écrasait au premier enregistrement ; changer la date
 *       gardait les valeurs du jour précédemment affiché et les enregistrait sur le nouveau.
 * 🔴 3. Taux d'éclosion du mois sans un seul œuf : 85,0 % (Reproducteurs, valeur de démonstration de la maquette) et
 *       0,0 % (Escargots) — désormais « — ».
 * 🔴 4. Fiche Porcs : « Poids Moyen Constaté » affichait « 0 Kg » sans pesée — désormais « — », comme Lapins.
 * 🔴 5. Fiches Escargots et Reproducteurs : la formule affichée sous l'effectif final omettait les ventes, que le
 *       calcul retire pourtant (`computeEffectifFinal`).
 */
class FichesEspecesU12aTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $compte = User::create([
            'name' => 'Animalier', 'username' => 'animalier', 'email' => 'animalier@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $compte->assignRole('animalier');
        $this->actingAs($compte);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(string $codeEspece, string $code, string $stade): LivestockLot
    {
        $espece = LivestockSpecies::firstOrCreate(['code' => $codeEspece], ['label' => $codeEspece, 'is_enabled' => true]);

        return LivestockLot::create([
            'code' => $code, 'species_id' => $espece->id, 'stage' => $stade, 'initial_quantity' => 200,
            'current_quantity' => 198, 'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function fiche(LivestockLot $bande, string $jour, array $valeurs = []): LivestockDailyEntry
    {
        return LivestockDailyEntry::create($valeurs + [
            'lot_id' => $bande->id, 'entry_date' => $jour, 'achat' => 3, 'ne' => 1, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 204, 'ponte_total' => 150,
        ]);
    }

    public function test_escargots_une_fiche_du_mois_precedent_se_recharge_et_n_est_pas_ecrasee(): void
    {
        ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);
        $bande = $this->bande('helico', 'ESC-A', 'engraissement');
        $this->fiche($bande, '2026-09-28', ['effectif_m' => 40, 'effectif_f' => 150, 'effectif_sevres' => 14]);

        $fiche = Livewire::test(FicheEscargots::class)->set('selectedDate', '2026-09-28');
        $fiche->assertSet('achat', 3)->assertSet('naissainsNes', 1)->assertSet('oeufsTerre', 150)
            ->assertSet('effectifNaissains', 40)->assertSet('effectifEngraissement', 150)->assertSet('effectifBordes', 14);

        $fiche->call('saveDay')->assertHasNoErrors();
        $e = LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', '2026-09-28')->first();
        $this->assertSame([3, 1, 150, 40, 150, 14], [
            (int) $e->achat, (int) $e->ne, (int) $e->ponte_total, (int) $e->effectif_m, (int) $e->effectif_f, (int) $e->effectif_sevres,
        ]);
    }

    public function test_reproducteurs_une_fiche_du_mois_precedent_se_recharge_et_n_est_pas_ecrasee(): void
    {
        $bande = $this->bande('aviculture', 'REP-A', 'reproduction');
        $this->fiche($bande, '2026-09-28');

        $fiche = Livewire::test(FicheReproducteurs::class)->set('selectedDate', '2026-09-28');
        $fiche->assertSet('achat', 3)->assertSet('poussinsNes', 1)->assertSet('oeufsCouves', 150);

        $fiche->call('saveDay')->assertHasNoErrors();
        $e = LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', '2026-09-28')->first();
        $this->assertSame([3, 1, 150], [(int) $e->achat, (int) $e->ne, (int) $e->ponte_total]);
    }

    public function test_reproducteurs_le_jour_meme_s_ouvre_avec_sa_fiche_et_changer_la_date_charge_le_jour(): void
    {
        $bande = $this->bande('aviculture', 'REP-A', 'reproduction');
        $this->fiche($bande, '2026-10-14', ['achat' => 5, 'ne' => 2, 'ponte_total' => 60, 'vente' => 4]);
        $this->fiche($bande, '2026-10-10', ['achat' => 0, 'ne' => 7, 'ponte_total' => 90]);

        $fiche = Livewire::test(FicheReproducteurs::class);
        $fiche->assertSet('achat', 5)->assertSet('poussinsNes', 2)->assertSet('oeufsCouves', 60);

        // Enregistrer le jour sans rien toucher ne l'écrase plus.
        $fiche->call('saveDay')->assertHasNoErrors();
        $e = LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', '2026-10-14')->first();
        $this->assertSame([5, 2, 60, 4], [(int) $e->achat, (int) $e->ne, (int) $e->ponte_total, (int) $e->vente]);

        // Changer la date charge le jour choisi ; un jour sans fiche repart à zéro.
        $fiche->set('selectedDate', '2026-10-10')->assertSet('achat', 0)->assertSet('poussinsNes', 7)->assertSet('oeufsCouves', 90);
        $fiche->set('selectedDate', '2026-10-12')->assertSet('poussinsNes', 0)->assertSet('oeufsCouves', 0);
    }

    public function test_lapins_et_porcs_relisaient_deja_un_jour_du_mois_precedent(): void
    {
        foreach ([[FicheLapins::class, 'cuniculture'], [FichePorcs::class, 'porciculture']] as [$classe, $espece]) {
            $bande = $this->bande($espece, 'B-'.$espece, 'engraissement');
            $this->fiche($bande, '2026-09-28', ['achat' => 6, 'ne' => 2]);
            Livewire::test($classe)->set('selectedDate', '2026-09-28')->assertSet('achat', 6)->assertSet('ne', 2);
        }
    }

    public function test_taux_d_eclosion_du_mois_sans_oeuf_est_inconnu_jamais_85_ni_0(): void
    {
        ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);
        $repro = $this->bande('aviculture', 'REP-A', 'reproduction');
        $escargots = $this->bande('helico', 'ESC-A', 'engraissement');
        $this->fiche($repro, '2026-10-05', ['ponte_total' => null]);
        $this->fiche($escargots, '2026-10-05', ['ponte_total' => 0]);

        foreach ([FicheReproducteurs::class, FicheEscargots::class] as $classe) {
            $composant = Livewire::test($classe);
            $this->assertNull($composant->instance()->kpis['taux_eclosion'], $classe);
            // Carte « Taux d'Éclosion Couvoir » (2e) / « Taux d'Éclosion Naissains » (3e).
            $this->assertSame('—', $this->cartes($composant->html())[$classe === FicheReproducteurs::class ? 1 : 2], $classe);
        }

        // Avec des œufs, le taux reste calculé sur le mois : (1 + 1) nés ÷ 4 œufs = 50 %.
        $this->fiche($repro, '2026-10-06', ['ne' => 1, 'ponte_total' => 4]);
        $this->assertSame(50.0, Livewire::test(FicheReproducteurs::class)->instance()->kpis['taux_eclosion']);
    }

    public function test_porcs_poids_moyen_sans_pesee_est_un_tiret_jamais_0_kg(): void
    {
        $this->bande('porciculture', 'POR-A', 'engraissement');
        $fiche = Livewire::test(FichePorcs::class);
        $this->assertSame('—', $this->poidsMoyen($fiche->html()));

        // 85 Kg pesés sur 200 porcs (effectif initial, aucune fiche) : 0,425 → « 0.4 Kg ».
        $this->assertSame('0.4 Kg', $this->poidsMoyen($fiche->set('peseeTotalKg', 85)->html()));
    }

    /** Valeurs des quatre `x-kpi-card`, dans l'ordre. */
    private function cartes(string $html): array
    {
        $doc = new \DOMDocument();
        @$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
        $valeurs = [];
        foreach ((new \DOMXPath($doc))->query("//span[contains(@class, 'md:text-2xl')]") as $span) {
            $valeurs[] = trim(preg_replace('/\s+/u', ' ', $span->textContent));
        }

        return $valeurs;
    }

    /** Texte de l'encadré « Poids Moyen Constaté » de la fiche rendue. */
    private function poidsMoyen(string $html): string
    {
        $apres = substr($html, strpos($html, 'Poids Moyen Constaté'));
        preg_match('/<div[^>]*>(.*?)<\/div>/s', $apres, $m);

        return trim(preg_replace('/\s+/u', ' ', strip_tags(preg_replace('/\{\{--.*?--\}\}/s', '', $m[1]))));
    }

    public function test_la_formule_affichee_des_escargots_et_reproducteurs_retire_les_ventes(): void
    {
        ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);
        $this->bande('helico', 'ESC-A', 'engraissement');
        $this->bande('aviculture', 'REP-A', 'reproduction');

        Livewire::test(FicheEscargots::class)->assertSee('= Effectif (J-1) + Achats/Naissains − (Morts + Ventes + Dons)');
        Livewire::test(FicheReproducteurs::class)->assertSee('= Effectif (J-1) + Achats/Poussins Nés − (Morts + Ventes + Dons)');
    }
}
