<?php

namespace Tests\Feature;

use App\Actions\RaiseFeedAutonomyAlertAction;
use App\Livewire\Elevage\DashboardElevage;
use App\Livewire\Elevage\ParametresElevage;
use App\Models\AuditLog;
use App\Models\FieldSurveyEntry;
use App\Models\Notification;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\User;
use App\Services\Elevage\ReleveTerrainService;
use Database\Seeders\ReleveTerrainSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket RELEVES-1 — onglet « Relevés de terrain » : CRUD, droits, calculs, semis idempotent, validation par modale,
 * enregistrer = « Validé », synchronisation (envoi / tirage), absorbeur strict, refus, lien avec le Dashboard et le
 * seuil critique d'autonomie. Valeurs attendues = littéraux calculés à la main.
 */
class ReleveTerrainTest extends TestCase
{
    use RefreshDatabase;

    private User $animalier;

    private User $lecteur;

    protected function setUp(): void
    {
        parent::setUp();
        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('animalier', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);
        Role::findOrCreate('lecteur', 'web')->givePermissionTo('view-elevage');
        $this->animalier = $this->compte('animalier');
        $this->lecteur = $this->compte('lecteur');
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function ligne(string $cle): FieldSurveyEntry
    {
        return FieldSurveyEntry::findOrFail(ReleveTerrainService::idDuSemis($cle));
    }

    private function service(): ReleveTerrainService
    {
        return app(ReleveTerrainService::class);
    }

    private function envoyer(User $u, array $corps)
    {
        return $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test'] + $corps);
    }

    private function donneesLot(array $remplace = []): array
    {
        return array_merge([
            'mise_date' => '2026-10-01', 'mode' => 'couveuse_artificielle', 'oeufs_mis' => 100, 'oeufs_fertiles' => 80,
            'oeufs_eclos' => 60, 'premier_eclos_date' => '2026-10-29', 'dernier_eclos_date' => '2026-10-31',
        ], $remplace);
    }

    // ---------------------------------------------------------------- semis

    public function test_les_propositions_naissent_a_valider_avec_les_valeurs_du_client(): void
    {
        $this->assertSame(11, FieldSurveyEntry::count());
        $this->assertSame(11, FieldSurveyEntry::where('status', 'a_valider')->count());

        $pintade = $this->ligne('incubation_pintade');
        $this->assertSame('pintade', $pintade->species_code);
        $this->assertSame(28, $pintade->data['duree_jours']);
        $this->assertSame([26, 28], [$pintade->data['eclosion_min'], $pintade->data['eclosion_max']]);
        $this->assertSame([7, 14], $pintade->data['mirages']);
        $this->assertSame(25, $pintade->data['transfert_jour']);
        $this->assertSame(10, $pintade->data['conservation_max_jours']);
        $this->assertSame('couveuse_artificielle', $pintade->data['mode']);
        $this->assertSame(21, $this->ligne('incubation_goliath')->data['duree_jours']);

        $this->assertSame([3, 7, 4], [
            $this->ligne('delai_provende')->data['critique_jours'], $this->ligne('delai_provende')->data['alerte_jours'], $this->ligne('delai_provende')->data['marge_jours'],
        ]);

        // Barème de DV-01 : alevin < 5 g 10–20 %, fingerling 5–20 g 6–8 %, juvénile 20–100 g 3–5 %, grossissement 100–500 g 2–3 %, > 500 g 1–2 %.
        $attendu = [[0, 5, 10, 20], [5, 20, 6, 8], [20, 100, 3, 5], [100, 500, 2, 3], [500, null, 1, 2]];
        $lus = FieldSurveyEntry::where('type', 'poisson_bareme')->get()->sortBy(fn ($l) => $l->data['poids_min_g'])->values()
            ->map(fn ($l) => [$l->data['poids_min_g'], $l->data['poids_max_g'], $l->data['biomasse_min_pct'], $l->data['biomasse_max_pct']])->all();
        $this->assertSame($attendu, $lus);
        $t = $this->ligne('poisson_temperature')->data;
        $this->assertSame([26, 30, 22], [$t['optimale_min'], $t['optimale_max'], $t['reduire_sous']]);
        // Aucune valeur inventée : marque, densité, granulé, protéine restent « — ».
        $this->assertNull($this->ligne('poisson_densite')->data['densite']);
        $this->assertNull($this->ligne('poisson_marque')->data['marque']);
        $this->assertNull($this->ligne('poisson_bareme_1')->data['granule']);
        $this->assertStringContainsString('— (à renseigner)', ReleveTerrainService::resume('poisson_densite', $this->ligne('poisson_densite')->data));
    }

    public function test_le_semis_est_idempotent_et_n_ecrase_jamais(): void
    {
        $this->assertSame(0, ReleveTerrainService::semerParDefaut());
        (new ReleveTerrainSeeder)->run();
        $this->assertSame(11, FieldSurveyEntry::count());

        // Une ligne modifiée et validée, une ligne archivée : jamais réécrites ni recréées.
        $this->service()->modifier($this->ligne('incubation_pintade'), ['label' => 'Pintade', 'species_code' => 'pintade', 'data' => ['duree_jours' => 27] + $this->ligne('incubation_pintade')->data], $this->animalier->id);
        $this->service()->archiver($this->ligne('incubation_goliath'), $this->animalier->id);
        ReleveTerrainService::semerParDefaut();
        (new ReleveTerrainSeeder)->run();

        $this->assertSame(27, $this->ligne('incubation_pintade')->data['duree_jours']);
        $this->assertSame('valide', $this->ligne('incubation_pintade')->status);
        $this->assertFalse($this->ligne('incubation_goliath')->is_active);
        $this->assertSame(11, FieldSurveyEntry::count());
    }

    // ---------------------------------------------------------------- calculs

    public function test_les_calculs_d_un_lot_ne_donnent_jamais_zero_quand_une_donnee_manque(): void
    {
        $c = ReleveTerrainService::calculsLot($this->donneesLot());
        $this->assertSame([28, 80.0, 75.0], [$c['duree_jours'], $c['taux_fertilite'], $c['taux_eclosion']]);

        $c = ReleveTerrainService::calculsLot($this->donneesLot(['oeufs_mis' => 90, 'oeufs_fertiles' => 70, 'oeufs_eclos' => 50]));
        $this->assertSame([77.8, 71.4], [$c['taux_fertilite'], $c['taux_eclosion']]);

        $vide = ReleveTerrainService::calculsLot(['mise_date' => '2026-10-01']);
        $this->assertSame([null, null, null], [$vide['duree_jours'], $vide['taux_fertilite'], $vide['taux_eclosion']]);
        $zero = ReleveTerrainService::calculsLot($this->donneesLot(['oeufs_fertiles' => 0, 'oeufs_eclos' => 0]));
        $this->assertNull($zero['taux_eclosion']);   // 0 fertile : pas de taux (jamais « 0 % » ni division par zéro)
        $this->assertSame(0.0, $zero['taux_fertilite']);
        $this->assertStringContainsString('fertilité — · éclosion —', ReleveTerrainService::resume('incubation_lot', ['mise_date' => '2026-10-01', 'mode' => 'couveuse_artificielle']));
    }

    private function bonRecu(Supplier $f, string $jourBon, string $jourReception, string $categorie = 'Aliments'): void
    {
        static $n = 0;
        $n++;
        $cat = ProductCategory::firstOrCreate(['label' => $categorie], ['is_active' => true]);
        $produit = Product::create([
            'sku' => 'T-'.$n, 'name' => 'Provende '.$n, 'category_id' => $cat->id, 'unit' => 'sac', 'pricing_mode' => 'fourchette',
            'price_min' => 100, 'price_max' => 200, 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true,
        ]);
        $bon = PurchaseOrder::create(['supplier_id' => $f->id, 'status' => 'recu']);
        DB::table('purchase_orders')->where('id', $bon->id)->update(['created_at' => $jourBon.' 10:00:00']);
        PurchaseOrderLine::create(['purchase_order_id' => $bon->id, 'product_id' => $produit->id, 'qty' => 5, 'estimated_unit_price' => 100]);
        Purchase::create(['supplier_id' => $f->id, 'purchase_order_id' => $bon->id, 'payment_mode' => 'credit', 'total' => 500, 'purchase_date' => $jourReception]);
    }

    public function test_le_delai_fournisseur_est_calcule_sur_les_cinq_derniers_bons_de_provende(): void
    {
        $f = Supplier::create(['name' => 'Provenderie Ikpinlè', 'is_active' => true]);
        $this->bonRecu($f, '2026-01-01', '2026-01-31');   // le plus ancien (30 j) : hors des 5 derniers
        foreach ([['2026-02-01', '2026-02-04'], ['2026-03-01', '2026-03-05'], ['2026-04-01', '2026-04-04'], ['2026-05-01', '2026-05-07'], ['2026-06-01', '2026-06-05']] as [$a, $b]) {
            $this->bonRecu($f, $a, $b);
        }
        $this->bonRecu($f, '2026-07-01', '2026-07-20', 'Médicaments');   // hors catégorie « Aliments » : ignoré

        $delais = ReleveTerrainService::delaisFournisseurs();
        $this->assertCount(1, $delais);
        $this->assertSame([5, 3, 4, 3, 6, 4], [$delais[0]['nb'], ...array_reverse(array_column($delais[0]['bons'], 'delai_jours'))]);
        $this->assertSame(6, $delais[0]['critique_propose']);   // le PLUS LONG des 5 (exemple de DV-18 : 3, 4, 3, 6, 4 → 6 j)

        // Règle encore « À valider » : le comportement d'avant (3 j / 7 j) ne bouge pas.
        $this->assertSame(['critique' => 3, 'alerte' => 7, 'source' => 'depart'], array_intersect_key(ReleveTerrainService::regleEnVigueur(), array_flip(['critique', 'alerte', 'source'])));

        // Validée : critique = 6 j, alerte = 6 + 4 = 10 j.
        $regle = $this->ligne('delai_provende');
        $this->service()->valider($regle, null, $this->animalier->id);
        $r = ReleveTerrainService::regleEnVigueur();
        $this->assertSame([6, 10, 'constate'], [$r['critique'], $r['alerte'], $r['source']]);

        // Mode « valeurs saisies » : les valeurs de la ligne.
        $this->service()->modifier($regle->fresh(), ['label' => $regle->label, 'data' => ['mode' => 'manuel', 'marge_jours' => 4, 'critique_jours' => 2, 'alerte_jours' => 5]], $this->animalier->id);
        $r = ReleveTerrainService::regleEnVigueur();
        $this->assertSame([2, 5, 'manuel'], [$r['critique'], $r['alerte'], $r['source']]);
    }

    public function test_moins_de_cinq_bons_gardent_les_valeurs_de_depart_meme_validees(): void
    {
        $f = Supplier::create(['name' => 'Fournisseur B', 'is_active' => true]);
        $this->bonRecu($f, '2026-02-01', '2026-02-09');
        $this->service()->valider($this->ligne('delai_provende'), null, $this->animalier->id);

        $this->assertSame([3, 7, 'depart'], [ReleveTerrainService::regleEnVigueur()['critique'], ReleveTerrainService::regleEnVigueur()['alerte'], ReleveTerrainService::regleEnVigueur()['source']]);
        $this->assertNull(ReleveTerrainService::delaisFournisseurs()[0]['critique_propose']);
    }

    public function test_l_alerte_d_autonomie_lit_le_seuil_critique_de_la_regle(): void
    {
        $produit = Product::create([
            'sku' => 'ALI-X', 'name' => 'Provende lapins', 'category_id' => ProductCategory::create(['label' => 'Aliments', 'is_active' => true])->id,
            'unit' => 'kg', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true,
        ]);
        $action = app(RaiseFeedAutonomyAlertAction::class);

        // 50 kg ÷ 10 kg/j = 5 jours : au-dessus du seuil de départ (3 j) → aucune alerte (comportement actuel).
        $this->assertNull($action->execute($produit, 10.0));
        $this->assertSame(3.0, ReleveTerrainService::seuilCritiqueJours());

        // Règle validée en saisie manuelle à 6 j : 5 jours ≤ 6 → alerte levée.
        $regle = $this->ligne('delai_provende');
        $this->service()->modifier($regle, ['label' => $regle->label, 'data' => ['mode' => 'manuel', 'marge_jours' => 4, 'critique_jours' => 6, 'alerte_jours' => 10]], $this->animalier->id);
        $this->assertSame(6.0, ReleveTerrainService::seuilCritiqueJours());
        $this->assertNotNull($action->execute($produit, 10.0));
        $this->assertSame(1, Notification::where('type', 'stock_low')->count());
    }

    // ---------------------------------------------------------------- CRUD web, droits

    public function test_crud_web_creation_modification_archivage_avec_audit(): void
    {
        Livewire::actingAs($this->animalier)->test(ParametresElevage::class, ['tab' => 'releves'])
            ->call('newReleve', 'incubation_lot')
            ->set('releveForm.label', 'LOT-P1')->set('releveForm.species_code', 'pintade')
            ->set('releveForm.data.mise_date', '2026-10-01')->set('releveForm.data.oeufs_mis', '100')
            ->set('releveForm.data.oeufs_fertiles', '80')->set('releveForm.data.oeufs_eclos', '60')
            ->set('releveForm.data.premier_eclos_date', '2026-10-29')
            ->call('saveReleve')->assertHasNoErrors();

        $lot = FieldSurveyEntry::where('type', 'incubation_lot')->firstOrFail();
        $this->assertSame(['LOT-P1', 'pintade', 'valide', $this->animalier->id], [$lot->label, $lot->species_code, $lot->status, $lot->validated_by]);
        $this->assertNotNull($lot->validated_at);
        $this->assertSame(100, $lot->data['oeufs_mis']);
        $this->assertSame(1, AuditLog::where('action', 'releve.saved')->where('entity_id', $lot->id)->count());

        Livewire::actingAs($this->animalier)->test(ParametresElevage::class, ['tab' => 'releves'])
            ->call('editReleve', $lot->id)->set('releveForm.data.oeufs_eclos', '65')->call('saveReleve')->assertHasNoErrors();
        $this->assertSame(65, $lot->fresh()->data['oeufs_eclos']);

        Livewire::actingAs($this->animalier)->test(ParametresElevage::class, ['tab' => 'releves'])->call('archiveReleve', $lot->id);
        $this->assertFalse($lot->fresh()->is_active);
        $this->assertSame(1, AuditLog::where('action', 'releve.archived')->count());
    }

    public function test_l_ecran_affiche_le_tableau_les_statuts_et_les_valeurs(): void
    {
        Livewire::actingAs($this->animalier)->test(ParametresElevage::class, ['tab' => 'releves'])
            ->assertSee('Relevés de terrain')->assertSee('À valider')->assertSee('Valider')
            ->assertSee('28 j · éclosion J26 à J28 · Couveuse artificielle · mirages J7, J14 · éclosoir J25 · œufs conservés ≤ 10 j')
            ->call('setReleveFamille', 'technicien')->assertSee('10 à 20 % de la biomasse par jour')->assertSee('— (à renseigner)')
            ->call('setReleveFamille', 'provende')->assertSee('critique 3 j · alerte 7 j · marge 4 j');
    }

    public function test_refus_en_francais_et_droits(): void
    {
        $this->actingAs($this->lecteur)->get('/parametres-elevage?tab=releves')->assertForbidden();
        // Une écriture forgée par un lecteur est refusée par `authorize('manage-elevage')`.
        Livewire::actingAs($this->lecteur)->test(ParametresElevage::class)->call('saveReleve')->assertForbidden();

        Livewire::actingAs($this->animalier)->test(ParametresElevage::class, ['tab' => 'releves'])
            ->call('newReleve', 'incubation_lot')
            ->set('releveForm.label', 'LOT-X')->set('releveForm.species_code', 'dinde')
            ->set('releveForm.data.oeufs_mis', '10')->set('releveForm.data.oeufs_fertiles', '12')
            ->call('saveReleve')
            ->assertHasErrors(['releveForm.species_code', 'releveForm.data.mise_date', 'releveForm.data.oeufs_fertiles']);
        $this->assertSame(0, FieldSurveyEntry::where('type', 'incubation_lot')->count());

        try {
            $this->service()->creer('incubation_regle', ['label' => 'Pintade bis', 'species_code' => 'pintade', 'data' => ['duree_jours' => 70]], $this->animalier->id);
            $this->fail('Une règle hors bornes devait être refusée.');
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->assertSame('Une règle d\'incubation existe déjà pour cette espèce.', $e->errors()['species_code'][0]);
            $this->assertSame('Le champ durée d\'incubation doit être un nombre entier compris entre 1 et 60.', $e->errors()['data.duree_jours'][0]);
            $this->assertSame('Les jours de mirage doivent être 1 à 3 entiers croissants, tous inférieurs à la durée d\'incubation.', $e->errors()['data.mirages'][0]);
        }
    }

    // ---------------------------------------------------------------- règle « À valider » → « Validé »

    public function test_la_modale_valider_fait_passer_a_valide_avec_validateur_et_audit(): void
    {
        $id = ReleveTerrainService::idDuSemis('incubation_pintade');
        Livewire::actingAs($this->animalier)->test(ParametresElevage::class, ['tab' => 'releves'])
            ->call('ouvrirValidation', $id)
            ->assertDispatched('open-modal', name: 'modal-valider-releve')
            ->assertSet('releveForm.data.duree_jours', 28)
            ->set('releveForm.data.duree_jours', '27')       // la modale permet de corriger les valeurs
            ->call('validerReleve')->assertHasNoErrors()
            ->assertDispatched('close-modal', name: 'modal-valider-releve');

        $l = $this->ligne('incubation_pintade');
        $this->assertSame(['valide', $this->animalier->id, 27], [$l->status, $l->validated_by, $l->data['duree_jours']]);
        $this->assertNotNull($l->validated_at);
        $this->assertSame(1, AuditLog::where('action', 'releve.valide')->where('entity_id', $id)->where('user_id', $this->animalier->id)->count());
        $this->assertSame(10, $this->service()->nombreAValider());
    }

    public function test_modifier_puis_enregistrer_passe_a_valide(): void
    {
        $id = ReleveTerrainService::idDuSemis('poisson_densite');
        Livewire::actingAs($this->animalier)->test(ParametresElevage::class, ['tab' => 'releves'])
            ->call('editReleve', $id)->set('releveForm.data.densite', '50')->set('releveForm.data.unite', 'poissons/m³')
            ->call('saveReleve')->assertHasNoErrors();
        $this->assertSame(['valide', $this->animalier->id], [$this->ligne('poisson_densite')->status, $this->ligne('poisson_densite')->validated_by]);
    }

    public function test_aucun_chemin_d_enregistrement_ne_laisse_a_valider_sur_une_ligne_modifiee_par_un_humain(): void
    {
        $s = $this->service();
        $cles = ['incubation_pintade', 'incubation_goliath', 'delai_provende', 'poisson_marque', 'poisson_bareme_1', 'poisson_bareme_2', 'poisson_temperature', 'poisson_densite'];
        foreach ($cles as $i => $cle) {
            $l = $this->ligne($cle);
            $this->assertSame('a_valider', $l->status);
            $saisie = ['label' => $l->label, 'species_code' => $l->species_code, 'data' => $l->data];
            match ($i % 3) {   // les trois chemins humains du service
                0 => $s->modifier($l, $saisie, $this->animalier->id),
                1 => $s->valider($l, null, $this->animalier->id),
                2 => $s->valider($l, $saisie, $this->animalier->id),
            };
            $this->assertSame('valide', $l->fresh()->status, $cle);
        }

        // Création humaine et chemin du poste.
        $this->assertSame('valide', $s->creer('incubation_regle', ['label' => 'Oie', 'species_code' => 'oie', 'data' => ['duree_jours' => 30, 'eclosion_min' => 28, 'eclosion_max' => 32, 'mode' => 'couveuse_artificielle', 'mirages' => '7, 14', 'conservation_max_jours' => 10]], $this->animalier->id)->status);
        $a = $this->ligne('poisson_bareme_3');
        $this->envoyer($this->animalier, ['field_survey_entries' => [['id' => $a->id, 'type' => $a->type, 'label' => $a->label, 'species_code' => $a->species_code, 'data' => $a->data, 'status' => 'a_valider']]])->assertOk();
        $this->assertSame('valide', $a->fresh()->status);   // le statut envoyé est IGNORÉ

        // Seule `semerParDefaut` écrit le statut « à valider » dans le code applicatif.
        $fichiers = [];
        foreach (new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator(app_path())) as $f) {
            if ($f->isFile() && str_ends_with($f->getFilename(), '.php')) {
                $src = file_get_contents($f->getPathname());
                if (preg_match("/'a_valider'|A_VALIDER/", $src)) {
                    $fichiers[] = str_replace(app_path().DIRECTORY_SEPARATOR, '', $f->getPathname());
                }
            }
        }
        sort($fichiers);
        $this->assertSame(['Models'.DIRECTORY_SEPARATOR.'FieldSurveyEntry.php', 'Services'.DIRECTORY_SEPARATOR.'Elevage'.DIRECTORY_SEPARATOR.'ReleveTerrainService.php'], $fichiers);
        $service = file_get_contents(app_path('Services/Elevage/ReleveTerrainService.php'));
        $this->assertSame(1, preg_match_all('/=> self::A_VALIDER|\'status\' => self::A_VALIDER/', $service));   // le semis
        $this->assertStringContainsString("['status' => self::VALIDE, 'validated_by'", $service);              // l'empreinte humaine unique
    }

    // ---------------------------------------------------------------- synchronisation

    public function test_le_tirage_sert_les_releves_a_qui_voit_l_elevage_et_nomme_le_validateur(): void
    {
        $this->service()->valider($this->ligne('poisson_temperature'), null, $this->animalier->id);

        $r = $this->actingAs($this->lecteur, 'sanctum')->getJson('/api/sync/pull?page=1')->assertOk();
        $this->assertContains('field_survey_entries', $r->json('tables_servies'));
        $lignes = collect($r->json('field_survey_entries'));
        $this->assertCount(11, $lignes);
        $t = $lignes->firstWhere('id', ReleveTerrainService::idDuSemis('poisson_temperature'));
        $this->assertSame(['valide', 'Animalier', 26], [$t['status'], $t['validated_by_name'], $t['data']['optimale_min']]);
        $this->assertSame('a_valider', $lignes->firstWhere('id', ReleveTerrainService::idDuSemis('incubation_pintade'))['status']);

        Role::findOrCreate('sans_droit', 'web');
        $caissier = $this->compte('sans_droit');
        $caissier->assignRole('sans_droit');
        $this->assertNotContains('field_survey_entries', $this->actingAs($caissier, 'sanctum')->getJson('/api/sync/pull?page=1')->json('tables_servies'));
    }

    public function test_l_envoi_du_poste_cree_modifie_archive_et_est_idempotent(): void
    {
        $regle = $this->ligne('incubation_pintade');
        $lot = ['id' => (string) Str::uuid(), 'type' => 'incubation_lot', 'label' => 'LOT-P2', 'species_code' => 'pintade', 'data' => $this->donneesLot(), 'is_active' => true];

        $this->envoyer($this->animalier, ['field_survey_entries' => [$lot]])->assertOk()->assertJsonPath('field_survey_entries.accepted.0', $lot['id']);
        $this->assertSame(['valide', $this->animalier->id, 'poste-test'], [FieldSurveyEntry::find($lot['id'])->status, FieldSurveyEntry::find($lot['id'])->validated_by, FieldSurveyEntry::find($lot['id'])->device_id]);

        // Rejeu identique : acquitté, sans écriture ni nouvelle trace.
        $audits = AuditLog::where('action', 'like', 'releve.%')->count();
        $this->envoyer($this->animalier, ['field_survey_entries' => [$lot]])->assertOk()->assertJsonPath('field_survey_entries.accepted.0', $lot['id']);
        $this->assertSame($audits, AuditLog::where('action', 'like', 'releve.%')->count());

        // Modification, puis validation d'une proposition (ligne « À valider » → audit releve.valide), puis archivage.
        $lot['data']['oeufs_eclos'] = 70;
        $this->envoyer($this->animalier, ['field_survey_entries' => [$lot]])->assertOk();
        $this->assertSame(70, FieldSurveyEntry::find($lot['id'])->data['oeufs_eclos']);
        $this->envoyer($this->animalier, ['field_survey_entries' => [['id' => $regle->id, 'type' => $regle->type, 'label' => $regle->label, 'species_code' => 'pintade', 'data' => ['duree_jours' => 28] + $regle->data]]])->assertOk();
        $this->assertSame('valide', $regle->fresh()->status);
        $this->assertSame(1, AuditLog::where('action', 'releve.valide')->where('entity_id', $regle->id)->count());
        $this->envoyer($this->animalier, ['field_survey_entries' => [['is_active' => false] + $lot]])->assertOk();
        $this->assertFalse(FieldSurveyEntry::find($lot['id'])->is_active);
        // Une ligne archivée n'est jamais rouverte.
        $this->envoyer($this->animalier, ['field_survey_entries' => [['is_active' => true, 'label' => 'AUTRE'] + $lot]])->assertOk();
        $this->assertFalse(FieldSurveyEntry::find($lot['id'])->is_active);
        $this->assertSame('LOT-P2', FieldSurveyEntry::find($lot['id'])->label);
    }

    public function test_absorbeur_strict_refus_motives_et_droit_d_ecriture(): void
    {
        $id = (string) Str::uuid();
        $mauvais = ['id' => $id, 'type' => 'incubation_lot', 'label' => 'LOT-Z', 'species_code' => 'pintade', 'data' => $this->donneesLot(['oeufs_fertiles' => 150])];
        $r = $this->envoyer($this->animalier, ['field_survey_entries' => [$mauvais, ['id' => (string) Str::uuid(), 'type' => 'inconnu', 'label' => 'x', 'data' => []], ['id' => 'pas-un-uuid', 'type' => 'incubation_lot']]])->assertOk();
        $this->assertSame([], $r->json('field_survey_entries.accepted'));
        $this->assertSame('Les œufs fertiles ne peuvent pas dépasser les œufs mis.', $r->json('field_survey_entries.rejected.0.reason'));
        $this->assertSame('Type de relevé inconnu.', $r->json('field_survey_entries.rejected.1.reason'));
        $this->assertSame('Identifiant de relevé invalide.', $r->json('field_survey_entries.rejected.2.reason'));
        $this->assertNull(FieldSurveyEntry::find($id));

        $bon = ['id' => (string) Str::uuid(), 'type' => 'incubation_lot', 'label' => 'LOT-OK', 'species_code' => 'pintade', 'data' => $this->donneesLot()];
        $r = $this->envoyer($this->lecteur, ['field_survey_entries' => [$bon]]);
        $this->assertNull(FieldSurveyEntry::find($bon['id']));
        $this->assertStringContainsString('votre rôle ne permet pas', json_encode($r->json(), JSON_UNESCAPED_UNICODE));   // refus du plancher d'écriture (manage-elevage)
    }

    // ---------------------------------------------------------------- Dashboard

    public function test_le_dashboard_resume_les_releves_et_affiche_des_tirets_sans_lot(): void
    {
        $s = $this->service()->synthese();
        $this->assertSame([11, 0, null, null, null], [$s['a_valider'], $s['nb_lots'], $s['fertilite_moyenne'], $s['eclosion_moyenne'], $s['duree_observee_moyenne']]);
        Livewire::actingAs($this->animalier)->test(DashboardElevage::class)->assertSee('Référentiels à valider')->assertSee('Aucun lot relevé')->assertSee('3 j / 7 j');

        $this->service()->creer('incubation_lot', ['label' => 'L1', 'species_code' => 'pintade', 'data' => $this->donneesLot()], $this->animalier->id);   // 28 j, 80 %, 75 %
        $this->service()->creer('incubation_lot', ['label' => 'L2', 'species_code' => 'pintade', 'data' => $this->donneesLot(['oeufs_mis' => 90, 'oeufs_fertiles' => 70, 'oeufs_eclos' => 50, 'premier_eclos_date' => '2026-10-27'])], $this->animalier->id);   // 26 j, 77,8 %, 71,4 %
        $s = $this->service()->synthese();
        $this->assertSame([2, 78.9, 73.2, 27.0, 28.0], [$s['nb_lots'], $s['fertilite_moyenne'], $s['eclosion_moyenne'], $s['duree_observee_moyenne'], $s['duree_regle_moyenne']]);
        Livewire::actingAs($this->animalier)->test(DashboardElevage::class)->assertSee('78,9 %')->assertSee('73,2 %')->assertSee('27 j')->assertSee('Règle : 28 j');
    }
}
