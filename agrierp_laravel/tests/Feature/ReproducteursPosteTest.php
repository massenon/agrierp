<?php

namespace Tests\Feature;

use App\Actions\SaisieReproducteurAction;
use App\Livewire\Elevage\GestionBandes;
use App\Livewire\Elevage\RegistreReproducteurs;
use App\Models\Animal;
use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket BS3 (décision BS-Q1 du 21/10/2026) — « Sujets » inclut le REGISTRE NOMINATIF DES REPRODUCTEURS : créer, modifier,
 * sortir un sujet nominatif, au web (`RegistreReproducteurs`) ET au poste (envoi `animals`), par UN point de passage
 * (`SaisieReproducteurAction`). Valeurs attendues écrites à la main.
 *
 * Règle d'or héritée du ticket 14.17 : identifier un sujet n'est PAS le faire entrer — l'effectif de la bande ne bouge
 * jamais (aucune cascade, ni à l'enregistrement, ni à la sortie).
 *
 * Décor : `PreparationExercices` (bande de pondeuses PON-2026-01 de 200 têtes, espèce « aviculture »), date figée au
 * 21/10/2026.
 */
class ReproducteursPosteTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const ANIMAL = 'aaaa2222-0000-4000-8000-000000000001';

    private const ANIMAL_2 = 'aaaa2222-0000-4000-8000-000000000002';

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2026-10-21 09:00:00');
        $this->exercice(2026);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** Un reproducteur tel que le poste l'envoie. */
    private function sujet(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::ANIMAL, 'identifier' => 'POU-2026-0007', 'species_id' => $this->pondeuses->species_id,
            'lot_id' => $this->pondeuses->id, 'category' => 'reproducteur', 'sex' => 'F', 'breed' => 'Sussex',
            'birth_date' => '2026-03-01', 'entry_date' => '2026-04-10', 'origin' => 'Achat couvoir', 'cage' => 'C5',
            'status' => 'actif', 'exit_date' => null, 'exit_reason' => null, 'is_active' => true, 'device_id' => 'poste-bureau',
        ], $remplacements);
    }

    private function pousser(array ...$sujets)
    {
        return $this->envoyer(['animals' => $sujets]);
    }

    private function jeton(string $role): void
    {
        $utilisateur = User::create([
            'name' => $role, 'username' => $role.'-bs3', 'email' => $role.'-bs3@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $utilisateur->assignRole($role);
        $this->app['auth']->forgetGuards();
        $this->jeton = $this->postJson('/api/auth/login', [
            'identifiant' => $role.'-bs3', 'password' => 'AgriERP@2026', 'device_name' => 'poste-'.$role,
        ])->assertOk()->json('token');
    }

    // ── Envoi du poste : créer ──────────────────────────────────────────────────────────────────────────────────────

    public function test_un_reproducteur_cree_au_poste_est_accepte_avec_son_uuid_actif_et_sans_toucher_l_effectif_de_la_bande(): void
    {
        $reponse = $this->pousser($this->sujet())->assertOk();

        $reponse->assertJsonPath('animals.accepted', [self::ANIMAL])->assertJsonPath('animals.rejected', []);
        $a = Animal::findOrFail(self::ANIMAL);
        $this->assertSame(
            ['POU-2026-0007', 'reproducteur', 'F', 'Sussex', 'Achat couvoir', 'C5', 'actif', true, $this->pondeuses->id],
            [$a->identifier, $a->category, $a->sex, $a->breed, $a->origin, $a->cage, $a->status, (bool) $a->is_active, $a->lot_id],
        );
        $this->assertSame(['2026-03-01', '2026-04-10'], [$a->birth_date->format('Y-m-d'), $a->entry_date->format('Y-m-d')]);
        $this->assertSame(200, (int) $this->pondeuses->fresh()->current_quantity, "l'effectif de la bande ne bouge jamais");
        $this->assertSame(1, AuditLog::where('action', 'animal.registered')->count());
    }

    public function test_le_renvoi_d_un_sujet_connu_est_acquitte_sans_rien_reecrire(): void
    {
        $this->pousser($this->sujet())->assertOk();
        $avant = Animal::findOrFail(self::ANIMAL)->updated_at;
        Carbon::setTestNow('2026-10-21 11:00:00');

        $this->pousser($this->sujet())->assertJsonPath('animals.accepted', [self::ANIMAL]);

        $this->assertSame(1, Animal::count());
        $this->assertSame(1, AuditLog::where('action', 'animal.registered')->count());
        $this->assertSame(0, AuditLog::where('action', 'animal.updated')->count());
        $this->assertTrue($avant->equalTo(Animal::findOrFail(self::ANIMAL)->updated_at), 'aucune écriture au renvoi');
    }

    public function test_un_reproducteur_sans_bande_ni_race_est_accepte(): void
    {
        $this->pousser($this->sujet(['lot_id' => null, 'breed' => null, 'birth_date' => null, 'origin' => null, 'cage' => null]))
            ->assertJsonPath('animals.accepted', [self::ANIMAL]);

        $a = Animal::findOrFail(self::ANIMAL);
        $this->assertSame([null, null, null], [$a->lot_id, $a->breed, $a->birth_date]);
    }

    public function test_la_bande_et_son_reproducteur_du_meme_envoi_sont_acceptes_dans_l_ordre(): void
    {
        $lot = 'bbbb2222-0000-4000-8000-000000000001';
        $reponse = $this->envoyer([
            'livestock_lots' => [[
                'id' => $lot, 'code' => 'LOT-VOL-9', 'species_id' => $this->pondeuses->species_id, 'stage' => 'reproduction',
                'created_date' => '2026-10-20', 'initial_quantity' => 6, 'status' => 'actif', 'is_active' => true,
            ]],
            'animals' => [$this->sujet(['lot_id' => $lot])],
        ])->assertOk();

        $reponse->assertJsonPath('livestock_lots.accepted', [$lot])->assertJsonPath('animals.accepted', [self::ANIMAL]);
        $this->assertSame($lot, Animal::findOrFail(self::ANIMAL)->lot_id);
        $this->assertSame(6, (int) LivestockLot::findOrFail($lot)->current_quantity);
    }

    // ── Envoi du poste : modifier ───────────────────────────────────────────────────────────────────────────────────

    public function test_modifier_un_reproducteur_change_race_cage_bande_et_identifiant_avec_audit(): void
    {
        $this->pousser($this->sujet())->assertOk();

        $this->pousser($this->sujet(['breed' => 'Rhode Island', 'cage' => 'C9', 'identifier' => 'POU-2026-0008', 'lot_id' => null]))
            ->assertJsonPath('animals.accepted', [self::ANIMAL]);

        $a = Animal::findOrFail(self::ANIMAL);
        $this->assertSame(['Rhode Island', 'C9', 'POU-2026-0008', null, 'actif'], [$a->breed, $a->cage, $a->identifier, $a->lot_id, $a->status]);
        $this->assertSame(1, AuditLog::where('action', 'animal.updated')->count());
        $this->assertSame(200, (int) $this->pondeuses->fresh()->current_quantity);
    }

    public function test_la_sortie_au_poste_pose_le_statut_la_date_et_le_motif_sans_toucher_l_effectif(): void
    {
        $this->pousser($this->sujet())->assertOk();

        $this->pousser($this->sujet(['status' => 'reforme', 'exit_date' => '2026-10-15', 'exit_reason' => 'Réforme pour âge']))
            ->assertJsonPath('animals.accepted', [self::ANIMAL]);

        $a = Animal::findOrFail(self::ANIMAL);
        $this->assertSame(['reforme', '2026-10-15', 'Réforme pour âge', false], [$a->status, $a->exit_date->format('Y-m-d'), $a->exit_reason, $a->isPresent()]);
        $this->assertTrue((bool) $a->is_active, 'la ligne est gardée : archivage logique, jamais de suppression');
        $this->assertSame(1, AuditLog::where('action', 'animal.exited')->count());
        $this->assertSame(200, (int) $this->pondeuses->fresh()->current_quantity, "l'effectif reste celui des fiches");

        // Renvoi de la même sortie : acquitté, sans seconde trace.
        $this->pousser($this->sujet(['status' => 'reforme', 'exit_date' => '2026-10-15', 'exit_reason' => 'Réforme pour âge']))
            ->assertJsonPath('animals.accepted', [self::ANIMAL]);
        $this->assertSame(1, AuditLog::where('action', 'animal.exited')->count());
    }

    public function test_un_sujet_cree_puis_sorti_avant_tout_envoi_arrive_sorti(): void
    {
        $this->pousser($this->sujet(['status' => 'mort', 'exit_date' => '2026-10-18', 'exit_reason' => 'Coccidiose']))
            ->assertJsonPath('animals.accepted', [self::ANIMAL]);

        $a = Animal::findOrFail(self::ANIMAL);
        $this->assertSame(['mort', 'Coccidiose'], [$a->status, $a->exit_reason]);
        $this->assertSame(1, AuditLog::where('action', 'animal.registered')->count());
        $this->assertSame(1, AuditLog::where('action', 'animal.exited')->count());
    }

    public function test_une_seconde_sortie_differente_est_refusee_avec_un_motif_clair(): void
    {
        $this->pousser($this->sujet(['status' => 'vendu', 'exit_date' => '2026-10-15', 'exit_reason' => 'Vente']))->assertOk();

        $reponse = $this->pousser($this->sujet(['status' => 'mort', 'exit_date' => '2026-10-16', 'exit_reason' => 'Mort']));

        $reponse->assertJsonPath('animals.accepted', []);
        $reponse->assertJsonPath('animals.rejected.0.reason', 'Ce reproducteur est déjà sorti (Vendu) : sa sortie ne peut pas être modifiée.');
        $this->assertSame('vendu', Animal::findOrFail(self::ANIMAL)->status);
    }

    // ── Rejets motivés ──────────────────────────────────────────────────────────────────────────────────────────────

    public function test_les_rejets_sont_motives_en_francais_et_n_ecrivent_rien(): void
    {
        Animal::create(['identifier' => 'POU-2026-0007', 'species_id' => $this->pondeuses->species_id, 'category' => 'reproducteur', 'sex' => 'F', 'entry_date' => '2026-04-10']);
        $id = fn (int $n) => 'aaaa2222-0000-4000-8000-0000000000'.str_pad((string) $n, 2, '0', STR_PAD_LEFT);

        $reponse = $this->pousser(
            $this->sujet(['id' => $id(11)]),                                                        // identifiant déjà pris
            $this->sujet(['id' => $id(12), 'identifier' => 'X-12', 'birth_date' => '2026-05-01']),  // naissance après l'entrée du 10/04
            $this->sujet(['id' => $id(13), 'identifier' => 'X-13', 'sex' => 'Z']),
            $this->sujet(['id' => $id(14), 'identifier' => 'X-14', 'species_id' => 'aaaa2222-0000-4000-8000-0000000000ff']),
            $this->sujet(['id' => $id(15), 'identifier' => 'X-15', 'entry_date' => '2026-12-31']),  // entrée dans le futur
            $this->sujet(['id' => $id(16), 'identifier' => 'X-16', 'exit_date' => '2026-01-01', 'exit_reason' => 'x', 'status' => 'vendu']), // sortie avant l'entrée
            $this->sujet(['id' => $id(17), 'identifier' => 'X-17', 'status' => 'disparu', 'exit_date' => '2026-10-01']),
        )->assertOk();

        $reponse->assertJsonPath('animals.accepted', []);
        $motifs = collect($reponse->json('animals.rejected'))->pluck('reason', 'id');
        $this->assertSame("La valeur du champ identifiant existe déjà.", $motifs[$id(11)]);
        $this->assertSame("La date de naissance ne peut pas être postérieure à la date d'entrée.", $motifs[$id(12)]);
        $this->assertSame("La valeur du champ sexe n'est pas autorisée.", $motifs[$id(13)]);
        $this->assertSame('La valeur du champ espèce ne correspond à aucun enregistrement connu du serveur.', $motifs[$id(14)]);
        $this->assertSame("La date du champ date d'entrée ne peut pas être postérieure à aujourd'hui.", $motifs[$id(15)]);
        $this->assertSame("La date de sortie ne peut pas précéder la date d'entrée du sujet.", $motifs[$id(16)]);
        $this->assertSame("La valeur du champ statut n'est pas autorisée.", $motifs[$id(17)]);
        $this->assertSame(1, Animal::count(), 'seul le sujet du décor existe');
    }

    public function test_un_compte_sans_manage_elevage_est_refuse_sujet_par_sujet(): void
    {
        $this->jeton('caissier');

        $reponse = $this->pousser($this->sujet())->assertOk();

        $reponse->assertJsonPath('animals.accepted', []);
        $reponse->assertJsonPath('animals.rejected.0.id', self::ANIMAL);
        $reponse->assertJsonPath('animals.rejected.0.reason', 'Refusé : votre rôle ne permet pas de créer, modifier ou sortir un reproducteur. Connectez-vous au poste avec un compte autorisé.');
        $this->assertSame(0, Animal::count());
    }

    public function test_l_animalier_envoie_ses_reproducteurs(): void
    {
        $this->jeton('animalier');

        $this->pousser($this->sujet())->assertJsonPath('animals.accepted', [self::ANIMAL]);
    }

    // ── Tirage : l'espèce descend avec le sujet ─────────────────────────────────────────────────────────────────────

    public function test_le_tirage_sert_l_identifiant_de_l_espece_pour_que_le_poste_puisse_ecrire(): void
    {
        $this->pousser($this->sujet())->assertOk();

        $ligne = collect($this->withHeader('Authorization', 'Bearer '.$this->jeton)->getJson('/api/sync/pull')->assertOk()->json('animals'))
            ->firstWhere('id', self::ANIMAL);

        $this->assertSame($this->pondeuses->species_id, $ligne['species_id']);
        $this->assertSame('Volailles', $ligne['species_label']);
    }

    // ── Web : même point de passage, même comportement ──────────────────────────────────────────────────────────────

    public function test_le_web_enregistre_modifie_et_sort_par_le_point_de_passage_unique_avec_l_audit_et_sans_toucher_l_effectif(): void
    {
        $c = Livewire::test(RegistreReproducteurs::class)
            ->call('newAnimal')
            ->set('identifier', 'POU-WEB-1')->set('species_id', $this->pondeuses->species_id)->set('lot_id', $this->pondeuses->id)
            ->set('sex', 'M')->set('breed', 'Sussex')->set('entry_date', '2026-10-01')
            ->call('saveAnimal')->assertHasNoErrors()
            ->assertDispatched('toast', message: "Reproducteur enregistré — l'effectif de la bande est inchangé, ce sujet y était déjà compté.", type: 'success');
        $a = Animal::where('identifier', 'POU-WEB-1')->firstOrFail();
        $this->assertSame(1, AuditLog::where('action', 'animal.registered')->count());

        $c->call('editAnimal', $a->id)->set('cage', 'C1')->call('saveAnimal')->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Reproducteur mis à jour.', type: 'success');
        $this->assertSame('C1', $a->fresh()->cage);
        $this->assertSame(1, AuditLog::where('action', 'animal.updated')->count());

        $c->call('openExit', $a->id)->set('exitStatus', 'vendu')->set('exit_date', '2026-10-10')->set('exit_reason', 'Vente')->call('confirmExit')->assertHasNoErrors();
        $this->assertSame(['vendu', 'Vente'], [$a->fresh()->status, $a->fresh()->exit_reason]);
        $this->assertSame(1, AuditLog::where('action', 'animal.exited')->count());
        $this->assertSame(200, (int) $this->pondeuses->fresh()->current_quantity);
    }

    public function test_le_web_refuse_une_seconde_sortie_d_un_sujet_deja_sorti(): void
    {
        $a = Animal::create(['identifier' => 'POU-WEB-2', 'species_id' => $this->pondeuses->species_id, 'category' => 'reproducteur', 'sex' => 'F', 'entry_date' => '2026-04-10', 'status' => 'vendu', 'exit_date' => '2026-10-01']);

        Livewire::test(RegistreReproducteurs::class)
            ->call('openExit', $a->id)->set('exitStatus', 'mort')->set('exit_date', '2026-10-10')
            ->call('confirmExit')
            ->assertHasErrors('exitStatus');

        $this->assertSame('vendu', $a->fresh()->status);
    }

    public function test_le_point_de_passage_porte_les_trois_gestes_et_refuse_sous_le_champ_du_formulaire(): void
    {
        $action = app(SaisieReproducteurAction::class);
        $a = $action->enregistrer([
            'identifier' => 'POU-ACT-1', 'species_id' => $this->pondeuses->species_id, 'lot_id' => null, 'sex' => 'F', 'breed' => null,
            'birth_date' => null, 'entry_date' => '2026-04-10', 'origin' => null, 'cage' => null,
        ]);
        $this->assertSame(['actif', 'reproducteur', true], [$a->status, $a->category, (bool) $a->is_active]);

        try {
            $action->sortir($a->id, ['status' => 'mort', 'exit_date' => '2026-01-01', 'exit_reason' => null]);
            $this->fail('La sortie avant l\'entrée doit être refusée.');
        } catch (ValidationException $e) {
            $this->assertSame(['exit_date' => ["La date de sortie ne peut pas précéder la date d'entrée du sujet."]], $e->errors());
        }

        $this->assertSame(SaisieReproducteurAction::SORTI_MAINTENANT, $action->sortir($a->id, ['status' => 'mort', 'exit_date' => '2026-10-10', 'exit_reason' => null]));
        $this->assertSame(SaisieReproducteurAction::DEJA_SORTI, $action->sortir($a->id, ['status' => 'mort', 'exit_date' => '2026-10-10', 'exit_reason' => null]));
    }

    public function test_le_registre_est_atteignable_depuis_bandes_et_sujets(): void
    {
        $html = Livewire::test(GestionBandes::class)->html();

        $this->assertStringContainsString(route('elevage.reproducteurs'), $html);
        $this->assertStringContainsString('Registre des Reproducteurs', $html);
    }
}
