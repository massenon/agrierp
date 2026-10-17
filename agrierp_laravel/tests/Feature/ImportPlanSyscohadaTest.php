<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\GrandLivre;
use App\Livewire\Comptabilite\Immobilisations;
use App\Livewire\Comptabilite\PlanComptable;
use App\Livewire\Comptabilite\RapprochementBancaire;
use App\Livewire\Parametres\ModesPaiement;
use App\Livewire\Rapports\Tresorerie;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\FixedAsset;
use App\Models\Permission;
use App\Models\Role;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\AccountingEntryService;
use App\Services\FinancialReportService;
use App\Services\ImporterPlanSyscohadaService;
use Database\Seeders\ChartOfAccountsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schema;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.27 — PHASE A DE L'ITEM 9 : IMPORT (INSERTION SEULE) DU PLAN COMPTABLE SYSCOHADA RÉVISÉ OFFICIEL.
 *
 * ⚠️ CE QUE CES TESTS PROTÈGENT. L'import n'ajoute que des comptes ABSENTS. Il ne modifie, ne renomme, ne
 * désactive jamais un compte existant (les 36 comptes de la ferme restent intacts, y compris les 12 dont le sens
 * diffère de celui du CSV : le remappage est la phase B, bloquée par la validation du cabinet FAGUEZ). Et 1 300
 * comptes de plus ne doivent altérer AUCUN état ni AUCUNE liste métier : un compte sans écriture n'apparaît pas
 * comme un solde 0.
 *
 * ⚠️ Le nombre attendu est RECALCULÉ INDÉPENDAMMENT depuis le CSV (lecture brute dans ce test, jamais le service).
 */
class ImportPlanSyscohadaTest extends TestCase
{
    use RefreshDatabase;

    private const CSV = __DIR__.'/../../database/data/plan-comptable-syscohada-revise.csv';

    private const EMPREINTE = '4103f4efc474fd6ffd5755575732d0eba7289a71f8364f51462e25924e9df143';

    /** Les 36 comptes de la ferme (code => [libellé, classe]), recopiés du seeder d'origine. */
    private const FERME = [
        '101' => ['Capital social', 1], '131' => ['Résultat net (bénéfice)', 1], '139' => ['Résultat net (perte)', 1],
        '221' => ['Bâtiments et constructions', 2], '241' => ["Cages et matériel d'élevage", 2],
        '244' => ['Broyeurs et équipements', 2], '281' => ['Amortissements des immobilisations', 2],
        '313' => ['Produits transformés', 3], '401' => ['Fournisseurs', 4], '409' => ['Fournisseurs débiteurs', 4],
        '411' => ['Clients', 4], '419' => ['Avances et acomptes reçus', 4], '443' => ['TVA facturée', 4],
        '445' => ['TVA récupérable', 4], '431' => ['Sécurité sociale (CNSS)', 4],
        '521101' => ['Banque - Compte principal', 5], '521201' => ['Mobile Money', 5], '531' => ['Caisse', 5],
        '601' => ['Achats de marchandises', 6], '602' => ['Produits vétérinaires', 6],
        '604' => ['Fournitures et matériel', 6], '605' => ['Énergie', 6], '606' => ['Entretien', 6],
        '614' => ['Transports', 6], '621' => ['Salaires', 6], '624' => ['Transports (variante prototype)', 6],
        '628' => ['Autres charges', 6], '65' => ['Autres charges de gestion', 6], '657' => ['Charges exceptionnelles', 6],
        '661' => ['Charges de personnel', 6], '664' => ['Charges sociales patronales', 6],
        '4472' => ['Impôt sur les traitements et salaires (ITS)', 4], '4473' => ['Versement patronal sur salaires (VPS)', 4],
        '681' => ['Dotations aux amortissements', 6], '701' => ['Ventes de produits', 7], '73' => ['Variation de stocks', 7],
    ];

    /** Lecture BRUTE et indépendante du CSV : code => libellé. */
    private function csvBrut(?string $chemin = null): array
    {
        $texte = file_get_contents($chemin ?? self::CSV);
        $texte = preg_replace('/^\xEF\xBB\xBF/', '', $texte);
        $res = [];
        foreach (preg_split('/\r\n|\n|\r/', $texte) as $i => $ligne) {
            if ($i === 0 || trim($ligne) === '') {
                continue;
            }
            [$c, $l] = explode(';', $ligne, 2);
            $l = trim($l);
            if (strlen($l) > 1 && $l[0] === '"' && substr($l, -1) === '"') {
                $l = str_replace('""', '"', substr($l, 1, -1));
            }
            $res[trim($c)] = $l;
        }

        return $res;
    }

    private function semerLesTrenteSix(): void
    {
        foreach (self::FERME as $code => [$label, $classe]) {
            ChartOfAccount::updateOrCreate(['code' => (string) $code], ['label' => $label, 'class' => $classe, 'is_active' => true]);
        }
    }

    private function instantane(): array
    {
        return DB::table('chart_of_accounts')->orderBy('code')->get()->map(fn ($l) => (array) $l)->keyBy('code')->all();
    }

    private function csvTemporaire(string $contenu): string
    {
        $f = tempnam(sys_get_temp_dir(), 'plan');
        file_put_contents($f, $contenu);

        return $f;
    }

    // ------------------------------------------------------------ source

    public function test_le_csv_du_depot_est_octet_pour_octet_celui_du_client(): void
    {
        $this->assertSame(self::EMPREINTE, hash_file('sha256', self::CSV));
        $this->assertSame(ImporterPlanSyscohadaService::EMPREINTE_SHA256, self::EMPREINTE);
        $this->assertCount(1332, $this->csvBrut());
    }

    // ------------------------------------------------------------ import

    public function test_le_nombre_de_comptes_apres_import_est_celui_recalcule_depuis_le_csv(): void
    {
        $this->semerLesTrenteSix();
        $csv = $this->csvBrut();

        $attendu = count(array_unique(array_merge(array_keys($csv), array_map('strval', array_keys(self::FERME)))));
        $resultat = app(ImporterPlanSyscohadaService::class)->importer();

        $this->assertSame($attendu, ChartOfAccount::count());
        $this->assertSame(1337, $attendu, '1 332 du CSV + 5 comptes de la ferme absents du CSV (313, 521101, 521201, 606, 657).');
        $this->assertSame(1332 - 31, $resultat['crees']);
        $this->assertSame(31, $resultat['deja_presents']);
        $this->assertSame(1332, $resultat['total_csv']);
    }

    public function test_deux_imports_donnent_la_meme_base(): void
    {
        $this->semerLesTrenteSix();
        $service = app(ImporterPlanSyscohadaService::class);

        $service->importer();
        $apres1 = $this->instantane();
        $second = $service->importer();
        $apres2 = $this->instantane();

        $this->assertSame(0, $second['crees']);
        $this->assertSame($apres1, $apres2, 'Aucune ligne créée, aucune modifiée (updated_at compris).');
    }

    public function test_aucun_compte_existant_n_est_modifie(): void
    {
        $this->semerLesTrenteSix();
        // Un compte archivé et un compte dont le libellé diffère du CSV : ils doivent rester tels quels.
        ChartOfAccount::where('code', '701')->update(['is_active' => false]);
        ChartOfAccount::where('code', '4473')->update(['label' => 'VPS (saisi à la main)']);

        $avant = $this->instantane();
        app(ImporterPlanSyscohadaService::class)->importer();
        $apres = $this->instantane();

        $this->assertCount(36, $avant);
        foreach ($avant as $code => $ligne) {
            $this->assertSame($ligne, $apres[$code], "Le compte {$code} a changé.");
        }
        $this->assertSame(0, (int) $apres['701']['is_active']);
        $this->assertSame('Caisse', $apres['531']['label'], '531 reste la caisse de la ferme, pas « chèques postaux ».');
        $this->assertSame('Bâtiments et constructions', $apres['221']['label']);
    }

    public function test_les_comptes_crees_ont_classe_parent_et_statut_attendus(): void
    {
        $this->semerLesTrenteSix();
        app(ImporterPlanSyscohadaService::class)->importer();

        $csv = $this->csvBrut();
        $tous = ChartOfAccount::pluck('id', 'code')->all();
        $classes = [];

        foreach ($csv as $code => $label) {
            $code = (string) $code;
            if (array_key_exists($code, self::FERME)) {
                continue;
            }
            $c = ChartOfAccount::where('code', (string) $code)->first();
            $this->assertNotNull($c, "Compte {$code} absent.");
            $this->assertSame((int) $code[0], $c->class, "Classe de {$code}.");
            $this->assertTrue($c->is_active);
            $this->assertSame($label, $c->label, "Libellé de {$code}.");

            // Recalcul indépendant du parent : plus long préfixe strict présent dans le plan final.
            $parentAttendu = null;
            for ($p = strlen($code) - 1; $p >= 1; $p--) {
                if (isset($tous[substr($code, 0, $p)])) {
                    $parentAttendu = $tous[substr($code, 0, $p)];
                    break;
                }
            }
            $this->assertSame($parentAttendu, $c->parent_id, "Parent de {$code}.");
            $classes[$c->class] = true;
        }

        ksort($classes);
        $this->assertSame([1, 2, 3, 4, 5, 6, 7, 8, 9], array_keys($classes));
        // Quelques cas lus à la main : 2312 -> 231 -> 23 ; 5711 -> 571 ; 1 n'a pas de parent.
        $this->assertSame('231', ChartOfAccount::find(ChartOfAccount::where('code', '2312')->value('parent_id'))->code);
        $this->assertNull(ChartOfAccount::where('code', '1')->value('parent_id'));
    }

    public function test_les_libelles_plus_longs_que_150_sont_conserves_entiers_et_signales(): void
    {
        app(ImporterPlanSyscohadaService::class)->importer();
        $csv = $this->csvBrut();

        foreach (['54', '603'] as $code) {
            $this->assertGreaterThan(150, mb_strlen($csv[$code]));
            $this->assertSame($csv[$code], ChartOfAccount::where('code', $code)->value('label'), "Libellé de {$code} tronqué.");
        }

        $rapport = app(ImporterPlanSyscohadaService::class)->importer(dryRun: true);
        $this->assertSame(['54', '603'], array_column($rapport['libelles_longs'], 'code'));
        $this->assertSame(['54', '603', '66'], array_column($rapport['libelles_a_corriger_par_le_cabinet'], 'code'));
    }

    public function test_le_libelle_entre_guillemets_du_csv_est_nettoye(): void
    {
        app(ImporterPlanSyscohadaService::class)->importer();

        $this->assertSame(
            "Actions démembrées (certificats d'investissement ; droits de vote)",
            ChartOfAccount::where('code', '5024')->value('label')
        );
    }

    public function test_un_csv_avec_bom_et_fins_de_ligne_unix_est_accepte(): void
    {
        $f = $this->csvTemporaire("\xEF\xBB\xBFCode;Libellé\n1;RESSOURCES\n11;CAPITAL\n111;Capital social\n");

        $r = app(ImporterPlanSyscohadaService::class)->importer($f);

        $this->assertSame(3, $r['crees']);
        $this->assertSame(ChartOfAccount::where('code', '11')->value('id'), ChartOfAccount::where('code', '111')->value('parent_id'));
    }

    public function test_un_csv_mal_forme_est_refuse_sans_rien_ecrire(): void
    {
        $cas = [
            'entête absent' => "1;RESSOURCES\n11;CAPITAL\n",
            'ligne sans séparateur' => "Code;Libellé\n1;RESSOURCES\n11 CAPITAL\n",
            'code en double' => "Code;Libellé\n1;A\n1;B\n",
            'libellé vide' => "Code;Libellé\n1;A\n12;   \n",
            'code non numérique' => "Code;Libellé\n1;A\nAB;B\n",
            'classe zéro' => "Code;Libellé\n1;A\n0;B\n",
            'fichier vide' => '',
        ];

        foreach ($cas as $nom => $contenu) {
            $f = $this->csvTemporaire($contenu);
            try {
                app(ImporterPlanSyscohadaService::class)->importer($f);
                $this->fail("« {$nom} » aurait dû être refusé.");
            } catch (\InvalidArgumentException $e) {
                $this->assertNotSame('', $e->getMessage(), $nom);
            }
            $this->assertSame(2, ChartOfAccount::count(), "« {$nom} » a écrit malgré le refus.");
        }

        $this->expectException(\InvalidArgumentException::class);
        app(ImporterPlanSyscohadaService::class)->importer('/chemin/inexistant.csv');
    }

    public function test_le_dry_run_compte_sans_ecrire(): void
    {
        $this->semerLesTrenteSix();
        $avant = $this->instantane();

        $r = app(ImporterPlanSyscohadaService::class)->importer(dryRun: true);

        $this->assertTrue($r['dry_run']);
        $this->assertSame(1301, $r['crees'], 'Nombre qui SERAIT créé.');
        $this->assertSame($avant, $this->instantane());
    }

    public function test_la_commande_artisan_importe_et_son_dry_run_n_ecrit_rien(): void
    {
        $this->semerLesTrenteSix();

        $this->artisan('comptabilite:importer-plan-syscohada', ['--dry-run' => true])
            ->expectsOutputToContain('1301')
            ->assertSuccessful();
        $this->assertSame(36, ChartOfAccount::count());

        $this->artisan('comptabilite:importer-plan-syscohada')->assertSuccessful();
        $this->assertSame(1337, ChartOfAccount::count());

        $this->artisan('comptabilite:importer-plan-syscohada', ['--fichier' => '/nulle/part.csv'])->assertFailed();
    }

    // ------------------------------------------------------------ semis et rattrapage

    public function test_le_seeder_pose_les_36_comptes_de_la_ferme_puis_importe_le_reste(): void
    {
        $this->seed(ChartOfAccountsSeeder::class);
        $this->assertSame(1337, ChartOfAccount::count());
        $this->assertSame('Caisse', ChartOfAccount::where('code', '531')->value('label'));
        $this->assertSame('Banque - Compte principal', ChartOfAccount::where('code', '521101')->value('label'));

        $avant = $this->instantane();
        $this->seed(ChartOfAccountsSeeder::class);
        $apres = $this->instantane();
        $this->assertSame(array_keys($avant), array_keys($apres));
        foreach ($avant as $code => $l) {
            $this->assertSame($l['id'], $apres[$code]['id'], "UUID de {$code} régénéré.");
            $this->assertSame($l['label'], $apres[$code]['label']);
        }
    }

    public function test_la_migration_de_rattrapage_importe_une_base_semee_et_ignore_une_base_vide(): void
    {
        $migration = require base_path('database/migrations/2026_10_10_000002_import_syscohada_chart_of_accounts.php');

        // Base non semée (installation neuve : seuls 409 et 419 posés par leurs migrations) : rien, c'est le seeder
        // qui importera APRÈS les 36 comptes.
        $migration->up();
        $this->assertSame(2, ChartOfAccount::count());

        // Base déjà semée : import, sans toucher aux 36.
        $this->semerLesTrenteSix();
        $migration->up();
        $this->assertSame(1337, ChartOfAccount::count());
        $this->assertSame('Caisse', ChartOfAccount::where('code', '531')->value('label'));

        // Rejouable.
        $migration->up();
        $this->assertSame(1337, ChartOfAccount::count());
    }

    // ------------------------------------------------------------ synchronisation

    public function test_le_tirage_de_synchronisation_sert_les_nouveaux_comptes(): void
    {
        $this->seed(ChartOfAccountsSeeder::class);
        Role::findOrCreate('caissier', 'web');
        $u = User::create(['name' => 'Caisse', 'username' => 'caisse', 'email' => 'caisse@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $u->assignRole('caissier');

        $jeton = $this->postJson('/api/auth/login', ['identifiant' => 'caisse', 'password' => 'AgriERP@2026', 'device_name' => 'poste-test'])->json('token');
        $r = $this->withHeader('Authorization', 'Bearer '.$jeton)->getJson('/api/sync/pull');
        $r->assertOk();

        $plan = collect($r->json('data.chart_of_accounts') ?? $r->json('chart_of_accounts'));
        $this->assertCount(1337, $plan);
        $codes = $plan->pluck('code')->all();
        $this->assertContains('5711', $codes);
        $this->assertContains('531', $codes);
        $this->assertSame($codes, collect($codes)->sort(SORT_STRING)->values()->all(), 'Tri par code conservé.');
        $this->assertSame(['class', 'code', 'id', 'label'], collect($plan->first())->keys()->sort()->values()->all());
    }

    // ------------------------------------------------------------ lecteurs : non-régression

    private function exerciceEtEcritures(): array
    {
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        $service = app(AccountingEntryService::class);
        $id = fn ($c) => ChartOfAccount::where('code', $c)->value('id');
        $service->recordManual($id('531'), $id('101'), 500_000, '2026-06-30', 'OD-2026-0001 — Ouverture');
        $service->recordManual($id('601'), $id('531'), 120_000, '2026-07-14', 'OD-2026-0002 — Achat');
        $service->recordManual($id('531'), $id('701'), 300_000, '2026-07-15', 'OD-2026-0003 — Vente');
        $service->recordManual($id('521101'), $id('701'), 80_000, '2026-07-16', 'OD-2026-0004 — Vente banque');

        return [$id('531'), $id('521101')];
    }

    public function test_les_etats_financiers_sont_identiques_avec_ou_sans_le_plan_complet(): void
    {
        $this->semerLesTrenteSix();
        $this->exerciceEtEcritures();
        $s = app(FinancialReportService::class);

        $avant = [
            'balance' => $s->balanceGenerale('2026-07-01', '2026-07-31'),
            'bilan' => $s->bilan('2026-07-31'),
            'resultat' => $s->compteResultat('2026-07-31'),
            'tafire' => $s->tafire('2026-07-01', '2026-07-31'),
            'produits' => $s->produitsPeriode('2026-07-01', '2026-07-31'),
            'charges' => $s->chargesPeriode('2026-07-01', '2026-07-31'),
            'gl' => $s->grandLivre(ChartOfAccount::where('code', '531')->value('id'), '2026-07-01', '2026-07-31'),
        ];

        app(ImporterPlanSyscohadaService::class)->importer();
        $s = app(FinancialReportService::class);

        $this->assertEquals($avant['balance'], $s->balanceGenerale('2026-07-01', '2026-07-31'));
        $this->assertEquals($avant['bilan'], $s->bilan('2026-07-31'));
        $this->assertEquals($avant['resultat'], $s->compteResultat('2026-07-31'));
        $this->assertEquals($avant['tafire'], $s->tafire('2026-07-01', '2026-07-31'));
        $this->assertEquals($avant['produits'], $s->produitsPeriode('2026-07-01', '2026-07-31'));
        $this->assertEquals($avant['charges'], $s->chargesPeriode('2026-07-01', '2026-07-31'));
        $this->assertEquals($avant['gl']['lines'], $s->grandLivre(ChartOfAccount::where('code', '531')->value('id'), '2026-07-01', '2026-07-31')['lines']);

        // Aucun compte sans écriture n'entre dans la balance : 4 comptes mouvementés + 0 solde fantôme.
        $codes = collect($s->balanceGenerale('2026-07-01', '2026-07-31')['rows'])->pluck('code')->map(fn ($c) => (string) $c)->sort(SORT_STRING)->values()->all();
        $this->assertSame(['101', '521101', '531', '601', '701'], $codes);
    }

    public function test_le_rapport_tresorerie_est_identique_avec_le_plan_complet(): void
    {
        $this->semerLesTrenteSix();
        $this->exerciceEtEcritures();
        $rows = fn () => Livewire::test(Tresorerie::class, ['startDate' => '2026-07-01', 'endDate' => '2026-07-31'])->instance()->rows;

        $avant = $rows();
        app(ImporterPlanSyscohadaService::class)->importer();

        $this->assertSame($avant, $rows());
        $this->assertNotEmpty($avant);
        // Recalcul indépendant : caisse au 15/07 = 500 000 - 120 000 + 300 000.
        $ligne15 = collect($avant)->first(fn ($r) => str_starts_with((string) $r['date'], '2026-07-15'));
        $this->assertEquals(680_000.0, $ligne15['caisse']);
    }

    private function comptable(): User
    {
        foreach (['view-comptabilite', 'manage-comptabilite'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('comptable', 'web');
        $role->givePermissionTo(['view-comptabilite', 'manage-comptabilite']);
        $u = User::create(['name' => 'Comptable', 'email' => 'plan@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026')]);
        $u->assignRole($role);
        $this->actingAs($u);

        return $u;
    }

    public function test_le_grand_livre_s_ouvre_toujours_sur_la_caisse_531(): void
    {
        $this->semerLesTrenteSix();
        $this->comptable();
        app(ImporterPlanSyscohadaService::class)->importer();

        Livewire::test(GrandLivre::class)
            ->assertSet('accountId', ChartOfAccount::where('code', '531')->value('id'));
    }

    public function test_le_rapprochement_bancaire_ne_propose_que_les_comptes_deja_utilises_ou_rattaches(): void
    {
        $this->semerLesTrenteSix();
        $this->comptable();
        foreach ([['531', 'caisse'], ['521101', 'banque'], ['521201', 'mobile_money']] as [$code, $type]) {
            TreasuryAccount::create(['type' => $type, 'label' => $code, 'account_code' => $code, 'balance' => 0, 'is_active' => true]);
        }
        $avant = Livewire::test(RapprochementBancaire::class);
        $attendu = $avant->instance()->treasuryAccounts->pluck('code')->all();
        $this->assertSame(['521101', '521201', '531'], $attendu);

        app(ImporterPlanSyscohadaService::class)->importer();

        $apres = Livewire::test(RapprochementBancaire::class);
        $this->assertSame($attendu, $apres->instance()->treasuryAccounts->pluck('code')->all());
        $this->assertSame(ChartOfAccount::where('code', '521101')->value('id'), $apres->get('accountId'), 'Compte par défaut inchangé (pas « 5 »).');
    }

    public function test_les_natures_d_immobilisation_restent_celles_de_la_ferme(): void
    {
        $this->semerLesTrenteSix();
        $this->comptable();
        $avant = Livewire::test(Immobilisations::class)->instance()->natures->pluck('code')->all();

        app(ImporterPlanSyscohadaService::class)->importer();

        $apres = Livewire::test(Immobilisations::class)->instance()->natures->pluck('code')->all();
        $this->assertSame(['221', '241', '244'], $avant);
        $this->assertSame($avant, $apres, 'Le sélecteur ne passe pas de 3 à plus de 250 natures.');

        // Un bien déjà enregistré sur une autre nature de classe 2 la garde proposée.
        $c = ChartOfAccount::where('code', '2312')->firstOrFail();
        FixedAsset::create([
            'code' => 'IMM-X', 'label' => 'Poulailler', 'account_code' => '2312',
            'acquisition_date' => '2026-01-01', 'acquisition_value' => 1000, 'residual_value' => 0,
            'duration_years' => 5, 'method' => 'lineaire', 'status' => 'en_service', 'is_active' => true, 'is_capitalized' => true,
        ]);
        $this->assertContains($c->code, Livewire::test(Immobilisations::class)->instance()->natures->pluck('code')->all());
    }

    public function test_l_ecran_plan_comptable_reste_utilisable_avec_1337_comptes(): void
    {
        $this->seed(ChartOfAccountsSeeder::class);
        $this->comptable();

        $page = Livewire::test(PlanComptable::class);
        $inst = $page->instance();

        $this->assertSame(1337, $inst->kpis['comptes_actifs'], 'Le KPI compte tous les comptes actifs.');
        $this->assertLessThanOrEqual(PlanComptable::LIMITE_AFFICHAGE, $inst->accounts->count());
        $this->assertSame(1337, $inst->totalCorrespondant);

        // La recherche porte sur TOUT le plan, pas sur la page affichée.
        $page->set('search', '5711');
        $this->assertSame(['5711'], $page->instance()->accounts->pluck('code')->all());

        // Afficher plus.
        $page->set('search', '')->call('afficherPlus');
        $this->assertSame(PlanComptable::LIMITE_AFFICHAGE * 2, $page->instance()->accounts->count());
    }

    public function test_un_compte_importe_de_classe_9_ou_au_libelle_long_est_modifiable(): void
    {
        $this->seed(ChartOfAccountsSeeder::class);
        $this->comptable();
        $long = ChartOfAccount::where('code', '603')->firstOrFail();
        $classe9 = ChartOfAccount::where('code', '9')->firstOrFail();

        Livewire::test(PlanComptable::class)
            ->call('editAccount', $long->id)
            ->call('saveAccount')
            ->assertHasNoErrors();
        Livewire::test(PlanComptable::class)
            ->call('editAccount', $classe9->id)
            ->call('saveAccount')
            ->assertHasNoErrors();
        $this->assertSame(9, $classe9->fresh()->class);
    }

    public function test_la_recherche_globale_par_numero_donne_le_compte_exact_avant_ses_sous_comptes(): void
    {
        // Un compte à code LONG posé AVANT l'import : sans tri, il sortirait en premier (ordre d'insertion).
        ChartOfAccount::create(['code' => '57999', 'label' => 'Compte long', 'class' => 5, 'is_active' => true]);
        $this->seed(ChartOfAccountsSeeder::class);
        $this->comptable();

        Livewire::test(\App\Livewire\Shared\GlobalSearch::class)
            ->set('query', '57')
            ->assertSee('57 — Caisse')
            ->assertDontSee('57999 — Compte long');
    }

    public function test_l_export_pdf_du_plan_contient_tous_les_comptes_et_pas_seulement_la_page(): void
    {
        $this->seed(ChartOfAccountsSeeder::class);
        $this->comptable();

        $comp = Livewire::test(PlanComptable::class)->instance();
        $this->assertSame(1337, $comp->comptesPourExport()->count());
    }

    // ------------------------------------------------------------ ticket 15.27-bis : audit indépendant de la phase A

    private function libelleDe(int $longueur, string $car = 'a'): string
    {
        return str_repeat($car, $longueur);
    }

    public function test_un_libelle_de_255_caracteres_est_accepte_entier_et_un_de_256_refuse_le_fichier_entier(): void
    {
        $ok = $this->csvTemporaire("Code;Libellé\n1;RESSOURCES\n11;".$this->libelleDe(255)."\n");
        $r = app(ImporterPlanSyscohadaService::class)->importer($ok);
        $this->assertSame(2, $r['crees']);
        $this->assertSame($this->libelleDe(255), ChartOfAccount::where('code', '11')->value('label'), 'Jamais tronqué.');
        $this->assertSame(255, ImporterPlanSyscohadaService::LONGUEUR_MAX);

        // Caractères multi-octets : la limite est en CARACTÈRES (colonne MySQL utf8mb4), pas en octets.
        ChartOfAccount::query()->delete();
        $accents = $this->csvTemporaire("Code;Libellé\n1;".$this->libelleDe(255, 'é')."\n");
        $this->assertSame(1, app(ImporterPlanSyscohadaService::class)->importer($accents)['crees']);

        ChartOfAccount::query()->delete();
        $trop = $this->csvTemporaire("Code;Libellé\n1;RESSOURCES\n11;CAPITAL\n12;".$this->libelleDe(256)."\n");
        try {
            app(ImporterPlanSyscohadaService::class)->importer($trop);
            $this->fail('Un libellé de 256 caractères aurait dû être refusé.');
        } catch (\InvalidArgumentException $e) {
            $this->assertStringContainsString('Ligne 4', $e->getMessage(), 'Le message cite la ligne.');
            $this->assertStringContainsString('code 12', $e->getMessage(), 'Le message cite le code.');
            $this->assertStringContainsString('256', $e->getMessage());
        }
        $this->assertSame(0, ChartOfAccount::count(), 'Fichier refusé en entier : aucune ligne valide écrite avant la fautive.');
    }

    public function test_le_dry_run_refuse_aussi_un_libelle_de_256_caracteres(): void
    {
        $trop = $this->csvTemporaire("Code;Libellé\n1;RESSOURCES\n12;".$this->libelleDe(256)."\n");
        $avant = ChartOfAccount::count();

        try {
            app(ImporterPlanSyscohadaService::class)->importer($trop, dryRun: true);
            $this->fail('Le dry-run aurait dû refuser le fichier.');
        } catch (\InvalidArgumentException $e) {
            $this->assertStringContainsString('Ligne 3', $e->getMessage());
        }
        $this->assertSame($avant, ChartOfAccount::count());
    }

    public function test_la_commande_refuse_un_libelle_trop_long_avec_un_code_de_sortie_en_echec(): void
    {
        $trop = $this->csvTemporaire("Code;Libellé\n1;".$this->libelleDe(256)."\n");
        $avant = ChartOfAccount::count();

        $this->artisan('comptabilite:importer-plan-syscohada', ['--fichier' => $trop, '--dry-run' => true])->assertFailed();
        $this->artisan('comptabilite:importer-plan-syscohada', ['--fichier' => $trop])->assertFailed();
        $this->assertSame($avant, ChartOfAccount::count());
    }

    public function test_les_lignes_vides_du_csv_finale_et_intermediaire_sont_ignorees_sans_erreur(): void
    {
        // Décision d'implémentation (non métier) : une ligne vide ou faite d'espaces n'est ni une erreur ni un compte.
        $avant = ChartOfAccount::count();
        $f = $this->csvTemporaire("Code;Libellé\n1;RESSOURCES\n\n11;CAPITAL\n   \n111;Capital social\n\n\n");

        $r = app(ImporterPlanSyscohadaService::class)->importer($f);

        $this->assertSame(3, $r['total_csv']);
        $this->assertSame(3, $r['crees']);
        $this->assertSame($avant + 3, ChartOfAccount::count());
    }

    public function test_les_parents_sont_poses_meme_quand_l_enfant_precede_son_parent_dans_le_fichier(): void
    {
        // Fichier NON TRIÉ : petit-enfant, puis enfant, puis racine. Le tri « parents d'abord » du service doit rétablir l'ordre.
        $f = $this->csvTemporaire("Code;Libellé\n1112;PETIT-ENFANT\n111;ENFANT\n1;RACINE\n11;INTERMEDIAIRE\n");

        app(ImporterPlanSyscohadaService::class)->importer($f);

        $id = fn (string $c) => ChartOfAccount::where('code', $c)->value('id');
        $parent = fn (string $c) => ChartOfAccount::where('code', $c)->value('parent_id');
        $this->assertNull($parent('1'));
        $this->assertSame($id('1'), $parent('11'));
        $this->assertSame($id('11'), $parent('111'));
        $this->assertSame($id('111'), $parent('1112'));
    }

    public function test_le_seeder_importe_apres_les_36_comptes_de_la_ferme_et_ne_leur_pose_aucun_parent(): void
    {
        // Insertion seule : un compte déjà présent n'est jamais modifié, `parent_id` compris. Si l'import passait AVANT les
        // 36 comptes, 531 serait créé par le CSV avec le parent « 53 », puis son libellé réécrit par le semis : le libellé
        // seul ne trahirait pas l'inversion, le parent si.
        $this->seed(ChartOfAccountsSeeder::class);

        $this->assertCount(36, ChartOfAccountsSeeder::comptesDeLaFerme());
        foreach (ChartOfAccountsSeeder::comptesDeLaFerme() as $c) {
            $this->assertNull(
                ChartOfAccount::where('code', $c['code'])->value('parent_id'),
                "Le compte de la ferme {$c['code']} a reçu un parent : l'import est passé avant le semis des 36 comptes."
            );
        }
        // Et ils ne sont pas isolés pour autant : le CSV a bien créé 53 à côté de 531.
        $this->assertNotNull(ChartOfAccount::where('code', '53')->first());
    }

    public function test_la_colonne_label_est_declaree_a_255_dans_le_schema_et_accordee_a_la_limite_du_service(): void
    {
        // ⚠️ Sqlite (base des tests) ne conserve pas la longueur d'un varchar : on ne peut pas la lire sur la base de test.
        // On rejoue donc la migration d'élargissement contre un Blueprint capturé et on lit la longueur DÉCLARÉE. Ce qui
        // n'est PAS verrouillé hors MySQL : le comportement réel du SGBD au-delà de la longueur (voir README, 15.27-bis).
        $migration = require base_path('database/migrations/2026_10_10_000001_widen_chart_of_accounts_label.php');
        $capture = null;
        Schema::shouldReceive('table')->once()->andReturnUsing(function ($table, $callback) use (&$capture) {
            $capture = new Blueprint(DB::connection(), $table);
            $callback($capture);
        });

        try {
            $migration->up();
        } finally {
            Schema::clearResolvedInstance('db.schema');
        }

        $colonnes = collect($capture->getColumns())->filter(fn ($c) => $c->name === 'label');
        $this->assertCount(1, $colonnes);
        $label = $colonnes->first();
        $this->assertSame('string', $label->type);
        $this->assertTrue((bool) $label->change, 'La migration modifie la colonne existante.');
        $this->assertSame(255, $label->length);
        $this->assertSame(ImporterPlanSyscohadaService::LONGUEUR_MAX, $label->length, 'Limite du service = largeur déclarée de la colonne.');
    }

    // ------------------------------------------------------------ A2 : caractérisation, NON résolue

    public function test_a2_a_decider_par_le_cabinet_les_codes_par_defaut_de_modes_paiement_pointent_un_regroupement_et_un_compte_fictif(): void
    {
        // ⚠️ À DÉCIDER PAR LE CABINET FAGUEZ (phase B). CE TEST NE TRANCHE RIEN : il DOCUMENTE un fait, il ne le valide pas.
        // `ModesPaiement::saveBank` crée une banque avec le code '521' et `saveMomo` un Mobile Money avec '5212' quand
        // l'utilisateur n'en saisit pas. Avant l'import ces codes n'existaient pas ; après, 521 est le regroupement
        // « BANQUES LOCALES » (il a des sous-comptes) et 5212 un libellé fictif du CSV (« Banque Y »). Les Actions de
        // comptabilisation poseraient donc silencieusement sur un compte de regroupement ou fictif. Si ce test devient
        // rouge parce que quelqu'un a décidé autre chose (codes par défaut changés, 521 retiré...), c'est BIEN : mettre
        // ce test à jour avec la décision du cabinet, ne pas le « réparer » en silence.
        $this->seed(ChartOfAccountsSeeder::class);

        // Ticket S2 : l'enregistrement d'un mode de paiement exige `manage-comptabilite`.
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $comptable = User::create([
            'name' => 'Comptable', 'username' => 'compta-a2', 'email' => 'compta-a2@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $comptable->assignRole('comptable');
        $this->actingAs($comptable);

        Livewire::test(ModesPaiement::class)
            ->set('bankName', 'Banque test')->set('rib', 'RIB-1')->set('iban', 'BJ00-1')
            ->call('saveBank')->assertHasNoErrors();
        Livewire::test(ModesPaiement::class)
            ->set('operatorName', 'MTN')->set('phoneNumber', '0100000000')
            ->call('saveMomo')->assertHasNoErrors();

        $this->assertSame('521', TreasuryAccount::where('type', 'banque')->value('account_code'));
        $this->assertSame('5212', TreasuryAccount::where('type', 'mobile_money')->value('account_code'));

        $c521 = ChartOfAccount::where('code', '521')->firstOrFail();
        $this->assertSame('BANQUES LOCALES', $c521->label);
        $this->assertTrue(ChartOfAccount::where('parent_id', $c521->id)->exists(), '521 est un compte de regroupement (il a des sous-comptes).');
        $this->assertSame('Banque Y', ChartOfAccount::where('code', '5212')->value('label'), '5212 = libellé fictif du CSV.');
    }
}
