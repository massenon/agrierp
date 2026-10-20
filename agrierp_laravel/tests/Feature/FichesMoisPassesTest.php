<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheEscargots;
use App\Livewire\Elevage\FicheLapins;
use App\Livewire\Elevage\FichePondeuses;
use App\Livewire\Elevage\FichePorcs;
use App\Livewire\Elevage\FicheReproducteurs;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\User;
use App\Models\VeterinaryRecord;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * Ticket EX8 (EF12, PRD `docs/prd/exercices-comptables.md` § 4) — FICHES D'ÉLEVAGE DES MOIS PASSÉS.
 *
 * 🔴 Les cinq fiches (Pondeuses, Reproducteurs, Lapins, Porcs, Escargots) ne montraient que le mois civil EN COURS
 * (`FichePondeuses.php:177`, `FichePorcs.php:193` : `now()->startOfMonth()`) : tableau mensuel, cartes du mois,
 * colonne « Traitements & Prophylaxie » et PDF. Une fois en 2027, les fiches de 2026 n'étaient plus consultables.
 *
 * Désormais : le mois affiché est celui du jour choisi ; « ‹ » / « › » passent au mois précédent / suivant (jamais
 * au-delà du mois en cours) ; un mois d'un exercice CLOS s'affiche en lecture seule (bandeau, formulaire grisé) — le
 * refus d'enregistrer existait déjà (EX5). `loadDay()` ne remet jamais une fiche existante à zéro (U11, U12a).
 */
class FichesMoisPassesTest extends TestCase
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
        ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** @return array<string, array{class-string, string, string}> composant, espèce, stade de la bande */
    public static function fiches(): array
    {
        return [
            'Pondeuses' => [FichePondeuses::class, 'aviculture', 'ponte'],
            'Reproducteurs' => [FicheReproducteurs::class, 'aviculture', 'reproduction'],
            'Lapins' => [FicheLapins::class, 'cuniculture', 'croissance'],
            'Porcs' => [FichePorcs::class, 'porciculture', 'engraissement'],
            'Escargots' => [FicheEscargots::class, 'helico', 'engraissement'],
        ];
    }

    private function bande(string $codeEspece, string $stade): LivestockLot
    {
        $espece = LivestockSpecies::firstOrCreate(['code' => $codeEspece], ['label' => $codeEspece, 'is_enabled' => true]);

        return LivestockLot::create([
            'code' => 'BANDE-A', 'species_id' => $espece->id, 'stage' => $stade, 'initial_quantity' => 200,
            'current_quantity' => 198, 'created_date' => '2025-11-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function fiche(LivestockLot $bande, string $jour, array $valeurs = []): LivestockDailyEntry
    {
        return LivestockDailyEntry::create($valeurs + [
            'lot_id' => $bande->id, 'entry_date' => $jour, 'achat' => 3, 'ne' => 1, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 204, 'ponte_total' => 150,
        ]);
    }

    #[DataProvider('fiches')]
    public function test_le_tableau_suit_le_mois_choisi_et_se_navigue(string $composant, string $espece, string $stade): void
    {
        $bande = $this->bande($espece, $stade);
        $this->fiche($bande, '2026-09-28');
        $this->fiche($bande, '2026-10-05', ['achat' => 0, 'ne' => 4]);

        $fiche = Livewire::test($composant);

        // Par défaut : le mois en cours, comme avant.
        $fiche->assertSet('selectedDate', '2026-10-14')->assertSee('Octobre 2026');
        $this->assertCount(31, $fiche->instance()->daysInMonth);
        $this->assertSame(['2026-10-05'], $fiche->instance()->monthlyEntries->keys()->all());
        $this->assertTrue($fiche->instance()->estMoisCourant, 'le mois en cours n\'a pas de mois suivant');

        // « ‹ » : septembre 2026, du 1er au 30.
        $fiche->call('moisPrecedent')
            ->assertSet('selectedDate', '2026-09-01')
            ->assertSee('Septembre 2026')
            ->assertSee('28/09');
        $this->assertCount(30, $fiche->instance()->daysInMonth);
        $this->assertSame(['2026-09-28'], $fiche->instance()->monthlyEntries->keys()->all());
        $this->assertFalse($fiche->instance()->estMoisCourant);

        // « › » : retour au mois en cours, sur le jour même ; jamais au-delà.
        $fiche->call('moisSuivant')->assertSet('selectedDate', '2026-10-14')->assertSee('Octobre 2026');
        // « › » grisé dès le rendu qui suit (une propriété calculée lue avant le changement de mois restait « faux »).
        $this->assertTrue($fiche->instance()->estMoisCourant);
        $this->assertMatchesRegularExpression('/wire:click="moisSuivant"[^>]*disabled/', $fiche->html());
        $fiche->call('moisSuivant')->assertSet('selectedDate', '2026-10-14');

        // Choisir une date d'un autre mois y amène le tableau.
        $fiche->set('selectedDate', '2026-08-12')->assertSee('Août 2026');
        $this->assertCount(31, $fiche->instance()->daysInMonth);
    }

    #[DataProvider('fiches')]
    public function test_naviguer_puis_enregistrer_un_jour_passe_ne_l_ecrase_pas(string $composant, string $espece, string $stade): void
    {
        $bande = $this->bande($espece, $stade);
        $this->fiche($bande, '2026-09-28');

        $fiche = Livewire::test($composant)->call('moisPrecedent')->call('loadDay', '2026-09-28');
        $fiche->assertSet('achat', 3)->assertSet('selectedDate', '2026-09-28');
        $fiche->call('saveDay')->assertHasNoErrors();

        $e = LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', '2026-09-28')->sole();
        $this->assertSame([3, 1, 150], [(int) $e->achat, (int) $e->ne, (int) $e->ponte_total], 'rechargée, jamais remise à zéro');
    }

    #[DataProvider('fiches')]
    public function test_le_pdf_porte_le_mois_affiche(string $composant, string $espece, string $stade): void
    {
        $bande = $this->bande($espece, $stade);
        $this->fiche($bande, '2026-09-28');

        Livewire::test($composant)->call('exportFichePdf')->assertFileDownloaded('fiche-2026-10.pdf');
        Livewire::test($composant)->call('moisPrecedent')->call('exportFichePdf')->assertFileDownloaded('fiche-2026-09.pdf');
    }

    #[DataProvider('fiches')]
    public function test_un_mois_d_un_exercice_clos_se_consulte_en_lecture_seule(string $composant, string $espece, string $stade): void
    {
        FiscalYear::create(['year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'cloture']);
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        $bande = $this->bande($espece, $stade);
        $this->fiche($bande, '2025-12-20', ['achat' => 7]);

        $fiche = Livewire::test($composant)->set('selectedDate', '2026-01-15');
        $this->assertNull($fiche->instance()->motifLectureSeule);
        $this->assertDoesNotMatchRegularExpression('/<fieldset[^>]*disabled/', $fiche->html());

        // Décembre 2025 : exercice clos — consultable, en lecture seule.
        $fiche->call('moisPrecedent')->assertSet('selectedDate', '2025-12-01')
            ->assertSee('Décembre 2025')
            ->assertSee('20/12')
            // Fusion EX7 + EX8 : le bandeau de lecture seule d'EX7, même composant, même texte, pour l'exercice du JOUR.
            ->assertSee("Exercice 2025 clôturé — lecture seule. Les saisies se font dans l'exercice 2026.")
            ->assertSee('Passer à 2026')
            ->assertSee('wire:click="passerALExerciceDeSaisie"', false);
        $this->assertSame('Exercice 2025 clôturé — lecture seule', $fiche->instance()->motifLectureSeule);
        $this->assertMatchesRegularExpression('/<fieldset[^>]*disabled/', $fiche->html(), 'formulaire grisé');

        // La fiche du 20/12/2025 se relit ; l'enregistrer reste refusé au serveur (EX5), rien n'est écrit.
        $fiche->call('loadDay', '2025-12-20')->assertSet('achat', 7);
        $fiche->set('achat', 9)->call('saveDay');
        $this->assertSame(7, (int) LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', '2025-12-20')->value('achat'));

        // « Passer à 2026 » ramène la fiche au jour de saisie (aujourd'hui), formulaire rouvert.
        $fiche->call('passerALExerciceDeSaisie')->assertSet('selectedDate', '2026-10-14')->assertSee('Octobre 2026');
        $this->assertNull($fiche->instance()->motifLectureSeule);
        $this->assertDoesNotMatchRegularExpression('/<fieldset[^>]*disabled/', $fiche->html());
    }

    /**
     * Fusion EX7 + EX8 — le bandeau de la fiche est CELUI d'EX7 (`x-bandeau-lecture-seule`) : quand l'exercice du jour
     * est l'exercice affiché (clos), le bandeau du haut de page le dit déjà — la fiche ne le répète pas, mais son
     * formulaire reste grisé. Ouvert affiché + jour clos : la fiche porte le sien.
     */
    public function test_le_bandeau_de_la_fiche_est_celui_d_ex7_et_ne_double_pas_celui_du_haut(): void
    {
        FiscalYear::create(['year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'cloture']);
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        $this->bande('cuniculture', 'croissance');
        $texte = "Exercice 2025 clôturé — lecture seule. Les saisies se font dans l'exercice 2026.";

        // 2025 (clos) affiché au sélecteur, fiche ouverte sur un jour de 2025.
        \App\Support\ExerciceChoisi::choisir(2025);
        Livewire::test(\App\Livewire\Shared\BandeauExercice::class)->assertSee($texte);
        $fiche = Livewire::test(FicheLapins::class)->set('selectedDate', '2025-12-10');
        $this->assertNull($fiche->instance()->bandeauLectureSeule, 'le bandeau du haut le dit déjà');
        $this->assertSame('Exercice 2025 clôturé — lecture seule', $fiche->instance()->motifLectureSeule);
        $this->assertSame(0, substr_count($fiche->html(), 'data-bandeau-exercice'));
        $this->assertMatchesRegularExpression('/<fieldset[^>]*disabled/', $fiche->html(), 'formulaire grisé quand même');

        // Un jour de 2026 (ouvert) : rien de grisé, même avec 2025 affiché (la fiche ne lit pas l'exercice affiché, EX-Q8).
        $fiche->set('selectedDate', '2026-10-14');
        $this->assertNull($fiche->instance()->motifLectureSeule);

        // 2026 affiché, jour de 2025 : la fiche porte LE bandeau d'EX7, une fois.
        \App\Support\ExerciceChoisi::choisir(2026);
        $html = Livewire::test(FicheLapins::class)->set('selectedDate', '2025-12-10')->html();
        $this->assertSame(1, substr_count($html, 'data-bandeau-exercice'));
        $this->assertStringContainsString(e($texte), $html);

        // Même composant des deux côtés, aucun bandeau propre aux fiches.
        $composant = file_get_contents(resource_path('views/components/bandeau-lecture-seule.blade.php'));
        $this->assertStringContainsString('Passer à {{', $composant);
        $this->assertStringContainsString('<x-bandeau-lecture-seule', file_get_contents(resource_path('views/livewire/shared/bandeau-exercice.blade.php')));
        $this->assertFileDoesNotExist(resource_path('views/components/fiche-lecture-seule.blade.php'));
    }

    public function test_les_cartes_et_les_soins_du_mois_suivent_le_mois_affiche(): void
    {
        $bande = $this->bande('cuniculture', 'croissance');
        $this->fiche($bande, '2026-09-28', ['ne' => 1]);
        $this->fiche($bande, '2026-10-05', ['ne' => 4]);
        VeterinaryRecord::create(['lot_id' => $bande->id, 'action_type' => 'Vaccination', 'product_used' => 'Pasteurellose', 'record_date' => '2026-09-28', 'is_active' => true]);

        $fiche = Livewire::test(FicheLapins::class);
        $this->assertSame(4, $fiche->instance()->kpis['naissances_mois']);
        $fiche->assertDontSee('Vaccination (Pasteurellose)');

        $fiche->call('moisPrecedent');
        $this->assertSame(1, $fiche->instance()->kpis['naissances_mois'], 'naissances de septembre');
        $fiche->assertSee('Vaccination (Pasteurellose)');
    }
}
