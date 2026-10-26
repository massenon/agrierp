<?php

namespace Tests\Feature;

use App\Livewire\Achats\ListeAchats;
use App\Livewire\Achats\SaisieDepenses;
use App\Livewire\Comptabilite\BalanceGenerale;
use App\Livewire\Comptabilite\Bilan;
use App\Livewire\Comptabilite\DeclarationTva;
use App\Livewire\Comptabilite\EtatsFinanciers;
use App\Livewire\Comptabilite\GrandLivre;
use App\Livewire\Comptabilite\JournalComptable;
use App\Livewire\Comptabilite\PlanComptable;
use App\Livewire\Comptabilite\RapprochementBancaire;
use App\Livewire\Dashboard\Index as TableauDeBord;
use App\Livewire\Elevage\SoinsVaccinsHub;
use App\Livewire\Elevage\TransfertsBandes;
use App\Livewire\Facturation\Facturation;
use App\Livewire\Rapports\RapportMensuel;
use App\Livewire\Rapports\RapportsExportsHub;
use App\Livewire\Shared\BandeauExercice;
use App\Livewire\Shared\SelecteurExercice;
use App\Livewire\Stocks\GestionStocks;
use App\Livewire\Ventes\HistoriqueVentes;
use App\Models\Expense;
use App\Models\FiscalYear;
use App\Models\InfirmaryRecord;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\LivestockTransfer;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\Sale;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Models\VeterinaryRecord;
use App\Services\FinancialReportService;
use App\Support\ExerciceChoisi;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket EX7 (EF8, EF9, EF10 du PRD `docs/prd/exercices-comptables.md`) — le sélecteur d'exercice global.
 *
 * Écrit AVANT le code (rouge d'abord). Les montants attendus sont ceux de l'exemple du § 5 du PRD, calculés à la main
 * (`JeuBasculeExercice`) :
 *
 *   2026 : apport 1 000 000 (521101 / 101), vente 300 000 (531 / 701), énergie 100 000 (605 / 531)
 *   2027 : vente 50 000 (531 / 701) le 15/01
 *
 * Balance « Exercice 2026 » lue en 2027 (R1) : 521101 D 1 000 000, 531 D 200 000, 605 D 100 000, 101 C 1 000 000,
 * 701 C 300 000 → 1 300 000 de chaque côté ; jamais la vente de 2027, jamais l'à-nouveau du 01/01/2027.
 * Après la clôture de 2026 (étape 2 au 31/12/2026) : 605 et 701 soldés, 131 C 200 000 → 1 200 000 de chaque côté.
 */
class SelecteurExerciceTest extends TestCase
{
    use JeuBasculeExercice;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2027-02-10 10:00:00', 'Africa/Porto-Novo'));
        $this->preparerComptable();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function administrateur(): User
    {
        $admin = User::create([
            'name' => 'Direction', 'username' => 'admin-selecteur', 'email' => 'admin-selecteur@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $admin->assignRole('admin');
        $this->actingAs($admin);

        return $admin;
    }

    private function ligne(array $rows, string $code): array
    {
        foreach ($rows as $row) {
            if ($row['code'] === $code && ! ($row['provisoire'] ?? false)) {
                return $row;
            }
        }
        $this->fail("compte {$code} absent");
    }

    // ── EF8 : le choix, son défaut, sa mémoire ───────────────────────────────────────────────────────────────

    public function test_par_defaut_l_exercice_qui_contient_le_jour_a_l_heure_du_benin(): void
    {
        $this->ouvrirExercices();

        // 31/12/2026 à 23 h 30 au Bénin (22 h 30 UTC) : encore 2026, alors que `FiscalYear::current()` dit 2027.
        Carbon::setTestNow(Carbon::parse('2026-12-31 22:30:00', 'UTC'));
        $this->assertSame(2026, ExerciceChoisi::annee());
        $this->assertSame(2027, FiscalYear::current()->year);

        // 01/01/2027 à 00 h 30 au Bénin (31/12/2026 23 h 30 UTC) : déjà 2027.
        Carbon::setTestNow(Carbon::parse('2026-12-31 23:30:00', 'UTC'));
        $this->assertSame(2027, ExerciceChoisi::annee());

        // Aucun exercice ne contient le jour (2028 pas encore ouvert) : le plus récent.
        Carbon::setTestNow(Carbon::parse('2028-01-01 09:00:00', 'Africa/Porto-Novo'));
        $this->assertSame(2027, ExerciceChoisi::annee());
    }

    public function test_le_choix_est_memorise_en_session_et_un_exercice_inconnu_est_refuse(): void
    {
        $this->ouvrirExercices();
        $this->assertSame(2027, ExerciceChoisi::annee());

        Livewire::test(SelecteurExercice::class)->call('choisir', 2026)->assertRedirect();
        $this->assertSame(2026, session(ExerciceChoisi::CLE_SESSION));
        $this->assertSame(2026, ExerciceChoisi::annee());
        $this->assertSame('2026-01-01', ExerciceChoisi::bornes()[0]);
        $this->assertSame('2026-12-31', ExerciceChoisi::bornes()[1]);

        // Un exercice qui n'existe pas ne remplace pas le choix.
        Livewire::test(SelecteurExercice::class)->call('choisir', 2031);
        $this->assertSame(2026, ExerciceChoisi::annee());

        // Un exercice choisi puis supprimé (réinitialisation) : retour au défaut, jamais une erreur.
        session([ExerciceChoisi::CLE_SESSION => 2019]);
        $this->assertSame(2027, ExerciceChoisi::annee());
    }

    public function test_la_liste_porte_les_badges_ouvert_provisoire_cloture(): void
    {
        FiscalYear::create(['year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'cloture', 'closed_at' => now()]);
        $this->ouvrirExercices();

        $statuts = collect(ExerciceChoisi::liste())->mapWithKeys(fn ($e) => [$e['annee'] => $e['statut']])->all();
        // 2027 : ouvert, précédent (2026) ouvert → à-nouveaux provisoires ; 2026 : précédent clos → ouvert ; 2025 : clos.
        $this->assertSame([2027 => 'provisoire', 2026 => 'ouvert', 2025 => 'cloture'], $statuts);

        // Même prédicat que les états (R3) : jamais deux définitions du « provisoire ».
        $service = app(FinancialReportService::class);
        $this->assertTrue($service->ouvertureExercice('2027-01-01')['provisoire']);
        $this->assertFalse($service->ouvertureExercice('2026-01-01')['provisoire']);

        Livewire::test(SelecteurExercice::class)
            ->assertSeeInOrder(['Exercice 2027', 'Exercice 2027', 'Provisoire', 'Exercice 2026', 'Ouvert', 'Exercice 2025', 'lock', 'Clôturé']);
    }

    public function test_un_premier_exercice_ouvert_sans_precedent_est_ouvert_et_non_provisoire(): void
    {
        FiscalYear::create(['year' => 2027, 'start_date' => '2027-01-01', 'end_date' => '2027-12-31', 'status' => 'ouvert']);

        $this->assertSame([['annee' => 2027, 'statut' => 'ouvert', 'libelle' => 'Ouvert', 'choisi' => true]], ExerciceChoisi::liste());
    }

    public function test_le_selecteur_est_dans_la_barre_superieure_a_gauche_de_synchroniser(): void
    {
        $this->ouvrirExercices();
        $this->administrateur();

        $html = $this->get('/dashboard')->assertOk()->getContent();

        $selecteur = strpos($html, 'dusk="selecteur-exercice"');
        $this->assertNotFalse($selecteur, 'le sélecteur est dans la barre supérieure');
        $this->assertLessThan(strpos($html, 'dusk="bouton-synchroniser"'), $selecteur, 'à gauche du bouton Synchroniser');
        $this->assertLessThan($selecteur, strpos($html, '<header'));
        $this->assertStringContainsString('Exercice 2027', $html);
    }

    // ── EF9 : ce que le sélecteur pilote ─────────────────────────────────────────────────────────────────────

    public function test_balance_exercice_2026_choisie_en_2027_selon_r1_avant_et_apres_la_cloture(): void
    {
        $this->jeuDuParagraphe5();

        // Sans choix : 2027 (le jour), comme avant — la caisse vaut 250 000.
        $balance2027 = Livewire::test(BalanceGenerale::class)->set('periode', 'exercice')->instance();
        $this->assertSame('Exercice 2027', $balance2027->periodLabel);
        $this->assertEquals(250_000.0, $this->ligne($balance2027->balance['rows'], '531')['final_debit']);

        ExerciceChoisi::choisir(2026);

        $balance = Livewire::test(BalanceGenerale::class)
            ->set('periode', 'exercice')
            ->assertSee('Exercice 2026')
            ->instance();
        $this->assertSame('Exercice 2026', $balance->periodLabel);
        $this->assertSame(['2026-01-01', '2026-12-31'], $balance->periodBounds());
        $rows = $balance->balance['rows'];
        $this->assertSame(['101', '521101', '531', '605', '701'], array_column($rows, 'code'));
        $this->assertEquals(200_000.0, $this->ligne($rows, '531')['final_debit'], 'ni la vente de 2027, ni l\'à-nouveau');
        $this->assertEquals(1_000_000.0, $this->ligne($rows, '521101')['final_debit']);
        $this->assertEquals(300_000.0, $this->ligne($rows, '701')['final_credit']);
        $this->assertEquals(1_300_000.0, $balance->balance['total_final_debit']);
        $this->assertEquals(1_300_000.0, $balance->balance['total_final_credit']);

        // Option « mois » : le dernier mois de l'exercice choisi (le mois courant n'est pas dans 2026).
        $mois = Livewire::test(BalanceGenerale::class)->instance();
        $this->assertSame(['2026-12-01', '2026-12-31'], $mois->periodBounds());
        $this->assertSame('Décembre 2026', $mois->periodLabel);

        // États financiers, Plan comptable, tableau de bord : 2026.
        $etats = Livewire::test(EtatsFinanciers::class)->instance();
        $this->assertSame('Situation au 31/12/2026 — Exercice 2026', $etats->situationLabel);
        $this->assertEquals(1_200_000.0, $etats->bilan['total_actif']);
        $this->assertEquals(200_000.0, $etats->resultat['resultat_net']);
        $this->assertSame(2026, Livewire::test(PlanComptable::class)->instance()->kpis['exercice']);
        $this->assertSame(2026, Livewire::test(TableauDeBord::class)->instance()->details['exercice']);

        // Après la clôture de 2026 (vrai assistant) : mêmes chiffres de bilan, résultat porté au 131.
        $this->cloturer2026();
        ExerciceChoisi::choisir(2026);
        $apres = Livewire::test(BalanceGenerale::class)->set('periode', 'exercice')->instance()->balance;
        $this->assertEquals(200_000.0, $this->ligne($apres['rows'], '531')['final_debit']);
        $this->assertEquals(200_000.0, $this->ligne($apres['rows'], '131')['final_credit']);
        $this->assertEquals(0.0, $this->ligne($apres['rows'], '701')['final_credit']);
        $this->assertEquals(1_200_000.0, $apres['total_final_debit']);
        $this->assertEquals(1_200_000.0, $apres['total_final_credit']);
    }

    public function test_les_periodes_des_etats_et_des_modules_sont_bornees_a_l_exercice_choisi(): void
    {
        $this->ouvrirExercices();
        $this->planDeLExemple();

        // Exercice du jour (2027) : défauts inchangés — du 1er du mois à aujourd'hui.
        $grandLivre = Livewire::test(GrandLivre::class);
        $this->assertSame(['2027-02-01', '2027-02-10'], [$grandLivre->get('startDate'), $grandLivre->get('endDate')]);

        ExerciceChoisi::choisir(2026);

        $grandLivre = Livewire::test(GrandLivre::class);
        $this->assertSame(['2026-01-01', '2026-12-31'], [$grandLivre->get('startDate'), $grandLivre->get('endDate')]);
        // Une date hors de l'exercice est ramenée à sa borne.
        $grandLivre->set('startDate', '2025-05-01')->set('endDate', '2027-03-01');
        $this->assertSame(['2026-01-01', '2026-12-31'], [$grandLivre->get('startDate'), $grandLivre->get('endDate')]);
        $grandLivre->assertSeeHtml('min="2026-01-01"')->assertSeeHtml('max="2026-12-31"');

        $rapprochement = Livewire::test(RapprochementBancaire::class);
        $this->assertSame(['2026-01-01', '2026-12-31'], [$rapprochement->get('startDate'), $rapprochement->get('endDate')]);

        $this->assertSame('2026-12-31', Livewire::test(Bilan::class)->get('asOfDate'));

        $tva = Livewire::test(DeclarationTva::class);
        $this->assertSame('2026-12', $tva->get('periode'));
        $this->assertSame(
            ['2026-12', '2026-11', '2026-10', '2026-09', '2026-08', '2026-07', '2026-06', '2026-05', '2026-04', '2026-03', '2026-02', '2026-01'],
            array_keys($tva->instance()->periodes),
        );

        $mensuel = Livewire::test(RapportMensuel::class);
        $this->assertSame('2026-12', $mensuel->get('periode'));

        $rapports = Livewire::test(RapportsExportsHub::class);
        $this->assertSame(['2026-01-01', '2026-12-31'], [$rapports->get('startDate'), $rapports->get('endDate')]);

        $ventes = Livewire::test(HistoriqueVentes::class);
        $this->assertSame(['2026-01-01', '2026-12-31'], [$ventes->get('dateFrom'), $ventes->get('dateTo')]);
    }

    public function test_les_listes_sont_paginees_dans_l_exercice_choisi(): void
    {
        $this->ouvrirExercices();
        $this->planDeLExemple();
        $this->administrateur();

        // 27 lignes en 2026 (deux pages de 25), une en 2027, une en 2025 (hors des deux exercices choisis).
        $jours = array_merge(
            array_map(fn ($i) => Carbon::parse('2026-01-05')->addDays($i * 13)->format('Y-m-d'), range(0, 26)),
            ['2027-01-20', '2025-12-30'],
        );

        $espece = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true, 'is_active' => true]);
        $bande = LivestockLot::create(['code' => 'PON-A', 'species_id' => $espece->id, 'stage' => 'ponte', 'initial_quantity' => 500, 'current_quantity' => 500, 'created_date' => '2025-01-01', 'status' => 'actif', 'is_active' => true]);
        $cible = LivestockLot::create(['code' => 'PON-B', 'species_id' => $espece->id, 'stage' => 'ponte', 'initial_quantity' => 10, 'current_quantity' => 10, 'created_date' => '2025-01-01', 'status' => 'actif', 'is_active' => true]);
        $categorie = ProductCategory::create(['label' => 'Provende', 'is_active' => true]);
        $produit = Product::create(['sku' => 'MAIS', 'name' => 'Maïs', 'category_id' => $categorie->id, 'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true]);
        $fournisseur = Supplier::create(['name' => 'Provenderie', 'phone' => '97000000', 'is_active' => true]);
        $caisse = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        foreach ($jours as $n => $jour) {
            Sale::create(['payment_mode' => 'especes', 'subtotal' => 1000, 'total' => 1000, 'status' => 'validee', 'sold_at' => $jour.' 09:00:00']);
            Purchase::create(['supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => 1000, 'purchase_date' => $jour]);
            Expense::create(['expense_date' => $jour, 'label' => "Dépense {$n}", 'category' => '605 - Énergie', 'amount' => 1000, 'treasury_account_id' => $caisse->id, 'status' => 'payee', 'is_active' => true]);
            StockMovement::create(['product_id' => $produit->id, 'type' => 'entree', 'quantity' => 1, 'reference_type' => 'manual_addition', 'movement_date' => $jour.' 08:00:00']);
            VeterinaryRecord::create(['lot_id' => $bande->id, 'action_type' => 'vaccination', 'record_date' => $jour, 'is_active' => true]);
            InfirmaryRecord::create(['lot_id' => $bande->id, 'motif' => 'Boiterie', 'entry_date' => $jour, 'status' => 'reintegre']);
            LivestockTransfer::create(['source_lot_id' => $bande->id, 'target_lot_id' => $cible->id, 'transfer_date' => $jour, 'quantity' => 1, 'is_active' => true]);
            // Hors des exercices enregistrés (2025) : écrit directement, `record()` le refuserait.
            if (substr($jour, 0, 4) !== '2025') {
                $this->ecrire($jour, '531', '701', 1000, "Vente {$n}");
            }
        }

        $listes = [
            [JournalComptable::class, 'entries', 'pageJournal'],
            [HistoriqueVentes::class, 'sales', 'pageVentes'],
            [Facturation::class, 'sales', 'pageFactures'],
            [ListeAchats::class, 'purchases', 'pageAchats'],
            [SaisieDepenses::class, 'expenses', 'pageDepenses'],
            [GestionStocks::class, 'movements', 'pageMouvements'],
            [SoinsVaccinsHub::class, 'veterinaryRecords', 'pageRegistre'],
            [SoinsVaccinsHub::class, 'infirmaryRecords', 'pageInfirmerie'],
            [TransfertsBandes::class, 'transferts', 'pageTransferts'],
        ];

        ExerciceChoisi::choisir(2026);
        foreach ($listes as [$composant, $propriete, $page]) {
            $test = Livewire::test($composant);
            $liste = $test->instance()->{$propriete};
            $this->assertSame(27, $liste->total(), "{$composant}::{$propriete} : les 27 lignes de 2026, ni 2025 ni 2027");
            $this->assertSame(25, $liste->count(), "{$composant}::{$propriete} : 25 par page");
            $this->assertSame($page, $liste->getPageName());

            $test->call('gotoPage', 2, $page);
            $deuxieme = $test->instance()->{$propriete};
            $this->assertSame(2, $deuxieme->currentPage());
            $this->assertSame(2, $deuxieme->count(), "{$composant}::{$propriete} : la page 2 porte les deux plus anciennes");
        }

        ExerciceChoisi::choisir(2027);
        foreach ($listes as [$composant, $propriete]) {
            $this->assertSame(1, Livewire::test($composant)->instance()->{$propriete}->total(), "{$composant}::{$propriete} : 2027 seulement");
        }

        // ⚠️ Infirmerie : un cas ENCORE EN COURS entré en 2026 reste listé dans 2027 (il se réintègre depuis l'exercice
        // du jour) ; il ne l'est pas dans 2025, qui ne contient pas le jour.
        InfirmaryRecord::create(['lot_id' => $bande->id, 'motif' => 'Diarrhée', 'entry_date' => '2026-12-28', 'status' => 'en_cours']);
        $this->assertSame(2, Livewire::test(SoinsVaccinsHub::class)->instance()->infirmaryRecords->total());

        // Le pied de pagination (composant partagé) : nombre de lignes dans l'exercice, Précédent / Suivant.
        ExerciceChoisi::choisir(2026);
        Livewire::test(JournalComptable::class)
            ->assertSee("27 lignes dans l'exercice 2026 — page 1 sur 2", false)
            ->assertSee('Précédent')
            ->assertSee('Suivant');
    }

    public function test_l_export_du_journal_reprend_tout_l_exercice_et_non_la_page(): void
    {
        $this->ouvrirExercices();
        $this->planDeLExemple();
        foreach (range(1, 30) as $n) {
            $this->ecrire('2026-03-'.str_pad((string) (($n % 28) + 1), 2, '0', STR_PAD_LEFT), '531', '701', 1000, "Vente {$n}");
        }
        ExerciceChoisi::choisir(2026);

        $journal = Livewire::test(JournalComptable::class)->instance();
        $this->assertCount(25, $journal->entries->items());
        $this->assertCount(30, $journal->ecrituresDeLExercice());
    }

    // ── EF10 : exercice clos = lecture seule à l'écran ───────────────────────────────────────────────────────

    private function exerciceCloturé(): void
    {
        $this->exercice2026 = FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'cloture', 'closed_at' => now()]);
        $this->exercice2027 = FiscalYear::create(['year' => 2027, 'start_date' => '2027-01-01', 'end_date' => '2027-12-31', 'status' => 'ouvert']);
    }

    public function test_un_exercice_clos_affiche_le_bandeau_et_grise_les_boutons_de_saisie(): void
    {
        $this->exerciceCloturé();
        $this->planDeLExemple();
        $this->administrateur();
        $motif = 'Exercice 2026 clôturé — lecture seule';
        $this->assertNull(ExerciceChoisi::motifLectureSeule(), 'par défaut : 2027, ouvert');

        // Exercice ouvert : ni bandeau, ni bouton grisé.
        $html = $this->get('/journal-comptable')->assertOk()->getContent();
        $this->assertStringNotContainsString('clôturé — lecture seule', $html);
        $this->assertStringNotContainsString('data-lecture-seule', $html);

        ExerciceChoisi::choisir(2026);
        $this->assertSame($motif, ExerciceChoisi::motifLectureSeule());
        // Une requête HTTP de test repart d'une session neuve : le choix lui est passé explicitement.
        $this->withSession([ExerciceChoisi::CLE_SESSION => 2026]);

        $html = $this->get('/journal-comptable')->assertOk()->getContent();
        $this->assertStringContainsString(e("Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027."), $html);
        $this->assertStringContainsString('Passer à 2027', $html);
        $this->assertMatchesRegularExpression('/<button[^>]*disabled[^>]*data-lecture-seule[^>]*title="'.preg_quote($motif, '/').'"[^>]*wire:click="newEntry"/u', $html, '« Nouvelle écriture » grisé, motif en info-bulle');
        // Consultation, export et impression restent ouverts.
        $this->assertMatchesRegularExpression('/<button type="button" wire:click="exportJournalPdf"/u', $html);

        // Une saisie par écran : bouton grisé, motif en info-bulle.
        foreach ([
            '/saisie-depenses' => 'type="submit"',
            '/gestion-stocks' => 'wire:click="openAddStockModal"',
            '/transferts-bandes' => 'wire:click="nouveauTransfert"',
        ] as $url => $repere) {
            $page = $this->get($url)->assertOk()->getContent();
            $this->assertStringContainsString(e("Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027."), $page, $url);
            $this->assertMatchesRegularExpression('/<button[^>]*disabled[^>]*data-lecture-seule[^>]*title="'.preg_quote($motif, '/').'"[^>]*'.preg_quote($repere, '/').'/u', $page, "{$url} : {$repere} grisé");
        }

        // « Passer à 2027 » : le choix revient à l'exercice de saisie.
        Livewire::test(BandeauExercice::class)->call('passer')->assertRedirect();
        $this->assertSame(2027, ExerciceChoisi::annee());
        $this->assertNull(ExerciceChoisi::motifLectureSeule());
    }

    public function test_le_refus_du_serveur_reste_intact_quel_que_soit_l_exercice_choisi(): void
    {
        $this->exerciceCloturé();
        $this->planDeLExemple();

        // L'exercice choisi est OUVERT (2027), mais l'écriture est datée de 2026, clos : refusée par le serveur (EX5).
        ExerciceChoisi::choisir(2027);
        Livewire::test(JournalComptable::class)
            ->set('entryDate', '2026-06-01')
            ->set('label', 'Tentative')
            ->set('debitAccountId', $this->comptes['531']->id)
            ->set('creditAccountId', $this->comptes['701']->id)
            ->set('amount', 5000)
            ->call('saveEntry')
            ->assertDispatched('toast', message: "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 01/06/2026.", type: 'error');
        $this->assertSame(0, \App\Models\AccountingEntry::count());

        // Le grisé est un confort : le serveur juge la DATE, pas l'exercice affiché.
        ExerciceChoisi::choisir(2026);
        Livewire::test(JournalComptable::class)
            ->set('entryDate', '2027-02-10')
            ->set('label', 'Vente du jour')
            ->set('debitAccountId', $this->comptes['531']->id)
            ->set('creditAccountId', $this->comptes['701']->id)
            ->set('amount', 5000)
            ->call('saveEntry');
        $this->assertSame(1, \App\Models\AccountingEntry::count());
    }

    // ── EX-Q5 (remplacée par DEP1) : une dépense comptabilisée est immuable, sa date comprise ─────────────────

    public function test_une_depense_comptabilisee_ne_s_ouvre_plus_en_modification_sa_date_comprise(): void
    {
        $this->ouvrirExercices();
        $this->planDeLExemple();
        $this->administrateur();
        $caisse = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 100_000, 'is_active' => true]);

        $saisie = Livewire::test(SaisieDepenses::class)
            ->call('nouvelleDepense')
            ->set('expenseDate', '2027-02-05')
            ->set('treasuryAccountId', $caisse->id)
            ->set('costCenterId', \App\Models\CostCenter::general()->id)
            ->set('lines.0.label', 'Carburant')
            ->set('lines.0.chargeAccountId', \App\Models\ChartOfAccount::where('code', '605')->value('id'))
            ->set('lines.0.amount', '5000')
            ->call('submitExpense');
        $depense = Expense::firstOrFail();

        $this->assertNotNull($depense->accounting_entry_id, 'le décor comptabilise la dépense (605 / 531 au plan)');

        $saisie->call('editExpense', $depense->id)
            ->assertNotDispatched('open-modal')
            ->assertDispatched('toast', message: \App\Actions\SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE, type: 'error');
    }
}
