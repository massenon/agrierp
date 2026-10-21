<?php

namespace Tests\Feature;

use App\Actions\SaisieReproducteurAction;
use App\Livewire\Elevage\AnimalDetails;
use App\Livewire\Elevage\RegistreReproducteurs;
use App\Models\Animal;
use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Services\AnimalFicheService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Décisions du client du 21/10/2026 sur le registre des reproducteurs — BS-Q11, BS-Q12, BS-Q13 (OUI aux trois).
 *
 *  - BS-Q11 : le statut d'un sujet sorti s'écrit « Réformé », « Vendu », « Mort » (jamais « Reforme » : `ucfirst` sur la
 *    valeur technique), au registre, à la fiche du sujet, à son PDF et à son historique ; la valeur technique reste
 *    `reforme` / `vendu` / `mort` en base et à l'envoi.
 *  - BS-Q12 : UNE règle pour les espèces du registre, au web comme au poste — les modules actifs (`modules_config`), le
 *    point de vérité du projet (`LivestockSpecies::enabled()`), celui que le tirage sert au poste. Le web filtrait sur
 *    `livestock_species.is_enabled`, un indicateur que l'écran « Modules actifs » ne pilote pas.
 *  - BS-Q13 : l'identifiant d'un sujet enregistré ne change plus (les saillies s'y rattachent par ce nom) : champ grisé
 *    en modification, refus serveur, y compris à l'envoi du poste.
 *
 * Valeurs attendues écrites à la main. Décor : `PreparationExercices` (bande de pondeuses, espèce « aviculture »).
 */
class RegistreReproducteursDecisionsTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const ANIMAL = 'bbbb3333-0000-4000-8000-000000000001';

    private const MESSAGE_IDENTIFIANT_FIGE = "L'identifiant d'un sujet enregistré ne peut pas être modifié : les saillies et l'historique du sujet s'y rattachent par ce nom.";

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

    private function sujet(array $remplacements = []): Animal
    {
        // `id` n'est pas remplissable (UUID créé par le modèle) : posé de force quand le test veut celui du poste.
        $animal = (new Animal())->forceFill(array_merge([
            'identifier' => 'POU-2026-0007', 'species_id' => $this->pondeuses->species_id, 'lot_id' => $this->pondeuses->id,
            'category' => 'reproducteur', 'sex' => 'F', 'breed' => 'Sussex', 'entry_date' => '2026-04-10', 'cage' => 'C5',
        ], $remplacements));
        $animal->save();

        return $animal;
    }

    private function sortie(string $statut, string $motif = ''): Animal
    {
        return $this->sujet([
            'identifier' => 'SORTI-'.strtoupper($statut), 'status' => $statut, 'exit_date' => '2026-10-01', 'exit_reason' => $motif ?: null,
        ]);
    }

    /** Le sujet tel que le poste l'envoie. */
    private function ligneDuPoste(array $remplacements = []): array
    {
        return array_merge([
            'id' => self::ANIMAL, 'identifier' => 'POU-2026-0007', 'species_id' => $this->pondeuses->species_id,
            'lot_id' => $this->pondeuses->id, 'category' => 'reproducteur', 'sex' => 'F', 'breed' => 'Sussex',
            'birth_date' => '2026-03-01', 'entry_date' => '2026-04-10', 'origin' => null, 'cage' => 'C5',
            'status' => 'actif', 'exit_date' => null, 'exit_reason' => null, 'is_active' => true, 'device_id' => 'poste-bureau',
        ], $remplacements);
    }

    /** Texte des cellules « Statut » du tableau du registre. */
    private function statutsAffiches($composant): array
    {
        $doc = new \DOMDocument();
        @$doc->loadHTML('<?xml encoding="utf-8"?>'.$composant->html());
        $xp = new \DOMXPath($doc);
        $sortie = [];
        foreach ($xp->query("//tr[contains(@class, 'rrow')]") as $tr) {
            $identifiant = trim($xp->query(".//td[@data-label='Identifiant']", $tr)->item(0)->textContent);
            $sortie[$identifiant] = trim(preg_replace('/\s+/u', ' ', $xp->query(".//td[@data-label='Statut']", $tr)->item(0)->textContent));
        }

        return $sortie;
    }

    // ── BS-Q11 : « Réformé », « Vendu », « Mort » ──────────────────────────────────────────────────────────────────

    public function test_le_registre_ecrit_les_statuts_de_sortie_avec_accent_et_majuscule(): void
    {
        $this->sujet(['identifier' => 'A-PRESENT']);
        $this->sortie('reforme', 'Réforme pour âge');
        $this->sortie('vendu');
        $this->sortie('mort');

        $affiches = $this->statutsAffiches(Livewire::test(RegistreReproducteurs::class));

        $this->assertSame([
            'A-PRESENT' => 'Actif',
            'SORTI-MORT' => 'Mort',
            'SORTI-REFORME' => 'Réformé',
            'SORTI-VENDU' => 'Vendu',
        ], $affiches);
    }

    public function test_la_valeur_technique_reste_sans_accent_en_base_et_dans_les_filtres(): void
    {
        $this->sortie('reforme');

        $this->assertSame('reforme', Animal::where('identifier', 'SORTI-REFORME')->value('status'));
        $html = Livewire::test(RegistreReproducteurs::class)->html();
        $this->assertStringContainsString('<option value="reforme">Réformé</option>', $html);
        $this->assertStringContainsString('<option value="vendu">Vendu</option>', $html);
        $this->assertStringContainsString('<option value="mort">Mort</option>', $html);
        $this->assertStringContainsString('<option value="actif">Actif</option>', $html);
    }

    public function test_les_libelles_de_statut_viennent_d_une_seule_correspondance(): void
    {
        $this->assertSame(
            ['actif' => 'Actif', 'reforme' => 'Réformé', 'vendu' => 'Vendu', 'mort' => 'Mort'],
            Animal::LIBELLES_STATUT,
        );
        $this->assertSame('Réformé', Animal::libelleStatut('reforme'));
        $this->assertSame('Réformé', SaisieReproducteurAction::libelleStatut('reforme'));
        $this->assertSame('Disparu', Animal::libelleStatut('disparu'), 'une valeur inconnue garde `ucfirst`');
        $this->assertSame('Réformé', $this->sortie('reforme')->status_label);
    }

    public function test_la_fiche_du_sujet_son_historique_et_son_pdf_suivent(): void
    {
        $a = $this->sortie('reforme', 'Réforme pour âge');

        $html = Livewire::test(AnimalDetails::class, ['animal' => $a])->html();
        $this->assertStringContainsString('Réformé', $html);
        $this->assertStringNotContainsString('Reforme', $html);

        $service = app(AnimalFicheService::class);
        $this->assertSame('Sortie — Réformé', $service->mouvements($a)[1]['libelle']);

        $pdf = view('exports.animal-details', $service->donneesPdf($a))->render();
        $this->assertStringContainsString('· Réformé</p>', $pdf);
        $this->assertStringNotContainsString('Reforme', $pdf);
    }

    public function test_le_message_de_seconde_sortie_garde_le_libelle_accentue(): void
    {
        $this->assertSame(
            'Ce reproducteur est déjà sorti (Réformé) : sa sortie ne peut pas être modifiée.',
            SaisieReproducteurAction::messageDejaSorti('reforme'),
        );
    }

    // ── BS-Q12 : les espèces du registre = les modules actifs, comme le tirage du poste ────────────────────────────

    private function especes(): array
    {
        // aviculture (décor) : module actif ; cuniculture : indicateur `is_enabled` vrai MAIS module éteint ;
        // helico : indicateur `is_enabled` FAUX mais module activé depuis « Modules actifs ».
        $lapins = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        $escargots = LivestockSpecies::create(['code' => 'helico', 'label' => 'Escargots', 'is_enabled' => false]);
        ModuleConfig::create(['species_code' => 'aviculture', 'is_enabled' => true]);
        ModuleConfig::create(['species_code' => 'cuniculture', 'is_enabled' => false]);
        ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);

        return ['lapins' => $lapins, 'escargots' => $escargots];
    }

    public function test_les_especes_proposees_sont_celles_des_modules_actifs(): void
    {
        $this->especes();

        $c = Livewire::test(RegistreReproducteurs::class);

        $this->assertSame(['Escargots', 'Volailles'], $c->instance()->speciesOptions->pluck('label')->all());
        $html = $c->html();
        $this->assertStringNotContainsString('>Lapins<', $html, 'module éteint : espèce non proposée');
        $this->assertStringContainsString('>Escargots<', $html, 'module activé : proposée même si `is_enabled` est faux');
    }

    public function test_le_tirage_sert_au_poste_les_memes_especes_que_le_registre(): void
    {
        $this->especes();
        $this->connecterLePoste();

        $tirage = collect($this->withHeader('Authorization', 'Bearer '.$this->jeton)->getJson('/api/sync/pull')->assertOk()->json('livestock_species'))
            ->pluck('label')->all();

        $this->assertSame(['Escargots', 'Volailles'], $tirage);
        $this->assertSame(
            $tirage,
            Livewire::test(RegistreReproducteurs::class)->instance()->speciesOptions->pluck('label')->all(),
        );
    }

    public function test_modifier_un_sujet_dont_le_module_vient_d_etre_eteint_garde_son_espece_dans_la_modale(): void
    {
        $lapins = $this->especes()['lapins'];
        $a = $this->sujet(['identifier' => 'LAP-OLD', 'species_id' => $lapins->id, 'lot_id' => null]);

        $c = Livewire::test(RegistreReproducteurs::class)->call('editAnimal', $a->id);

        $this->assertSame(['Escargots', 'Lapins', 'Volailles'], $c->instance()->speciesFormOptions->pluck('label')->all());
        $c->set('cage', 'C9')->call('saveAnimal')->assertHasNoErrors();
        $this->assertSame([$lapins->id, 'C9'], [$a->fresh()->species_id, $a->fresh()->cage]);

        $this->assertSame(
            ['Escargots', 'Volailles'],
            Livewire::test(RegistreReproducteurs::class)->call('newAnimal')->instance()->speciesFormOptions->pluck('label')->all(),
            'à la création : les modules actifs seulement',
        );
    }

    // ── BS-Q13 : l'identifiant d'un sujet enregistré ne change plus ────────────────────────────────────────────────

    public function test_en_modification_le_champ_identifiant_est_grise_avec_son_info_bulle(): void
    {
        $a = $this->sujet();

        $html = Livewire::test(RegistreReproducteurs::class)->call('editAnimal', $a->id)->html();

        $this->assertMatchesRegularExpression('/<input[^>]*wire:model="identifier"[^>]*\bdisabled\b[^>]*>/', $html);
        $this->assertStringContainsString('title="'.htmlspecialchars(self::MESSAGE_IDENTIFIANT_FIGE, ENT_QUOTES).'"', $html);
        $this->assertStringContainsString('<p class="text-[10px] text-outline mt-xs">'.e(self::MESSAGE_IDENTIFIANT_FIGE).'</p>', $html, 'l\'aide sous le champ dit pourquoi');
    }

    public function test_a_la_creation_le_champ_identifiant_reste_libre(): void
    {
        $html = Livewire::test(RegistreReproducteurs::class)->call('newAnimal')->html();

        $this->assertDoesNotMatchRegularExpression('/<input[^>]*wire:model="identifier"[^>]*\bdisabled\b[^>]*>/', $html);
        $this->assertStringNotContainsString(e(self::MESSAGE_IDENTIFIANT_FIGE), $html);
    }

    public function test_le_web_refuse_un_identifiant_modifie_meme_forge_et_ne_change_rien(): void
    {
        $a = $this->sujet();

        $c = Livewire::test(RegistreReproducteurs::class)->call('editAnimal', $a->id)
            ->set('identifier', 'POU-2026-9999')->set('cage', 'C9')->call('saveAnimal');

        $this->assertErreurSousLeChamp($c, 'identifier', self::MESSAGE_IDENTIFIANT_FIGE);
        $c->assertNotDispatched('toast');
        $fresh = $a->fresh();
        $this->assertSame(['POU-2026-0007', 'C5'], [$fresh->identifier, $fresh->cage], 'rien n\'est écrit, pas même la cage');
        $this->assertSame(0, AuditLog::where('action', 'animal.updated')->count());
    }

    public function test_modifier_sans_toucher_l_identifiant_reste_possible(): void
    {
        $a = $this->sujet();

        Livewire::test(RegistreReproducteurs::class)->call('editAnimal', $a->id)->set('cage', 'C9')->call('saveAnimal')->assertHasNoErrors();

        $this->assertSame(['POU-2026-0007', 'C9'], [$a->fresh()->identifier, $a->fresh()->cage]);
    }

    public function test_le_point_de_passage_refuse_le_changement_d_identifiant_sous_le_champ(): void
    {
        $a = $this->sujet();
        $donnees = [
            'identifier' => 'AUTRE-ID', 'species_id' => $a->species_id, 'lot_id' => null, 'sex' => 'F', 'entry_date' => '2026-04-10',
        ];

        try {
            app(SaisieReproducteurAction::class)->modifier($a->id, $donnees);
            $this->fail('Le changement d\'identifiant doit être refusé.');
        } catch (ValidationException $e) {
            $this->assertSame(['identifier' => [self::MESSAGE_IDENTIFIANT_FIGE]], $e->errors());
        }

        $this->assertSame('POU-2026-0007', $a->fresh()->identifier);
        $this->assertSame(self::MESSAGE_IDENTIFIANT_FIGE, SaisieReproducteurAction::MESSAGE_IDENTIFIANT_FIGE);
    }

    public function test_un_sujet_sorti_garde_lui_aussi_son_identifiant(): void
    {
        $a = $this->sortie('vendu');

        $this->expectException(ValidationException::class);
        app(SaisieReproducteurAction::class)->modifier($a->id, [
            'identifier' => 'AUTRE-ID', 'species_id' => $a->species_id, 'sex' => 'F', 'entry_date' => '2026-04-10',
        ]);
    }

    public function test_un_identifiant_modifie_a_l_envoi_du_poste_est_rejete_avec_son_motif_et_ne_change_rien(): void
    {
        $this->sujet(['id' => self::ANIMAL]);

        $reponse = $this->envoyer(['animals' => [$this->ligneDuPoste(['identifier' => 'POU-2026-0008', 'cage' => 'C9'])]])->assertOk();

        $reponse->assertJsonPath('animals.accepted', []);
        $reponse->assertJsonPath('animals.rejected.0.id', self::ANIMAL);
        $reponse->assertJsonPath('animals.rejected.0.reason', self::MESSAGE_IDENTIFIANT_FIGE);
        $a = Animal::findOrFail(self::ANIMAL);
        $this->assertSame(['POU-2026-0007', 'C5'], [$a->identifier, $a->cage]);
    }

    public function test_un_sujet_cree_au_poste_puis_corrige_avant_tout_envoi_arrive_sous_son_identifiant_final(): void
    {
        // Le serveur ne le connaît pas encore : c'est une CRÉATION, la saisie y est libre.
        $this->envoyer(['animals' => [$this->ligneDuPoste(['identifier' => 'POU-FINAL'])]])
            ->assertOk()->assertJsonPath('animals.accepted', [self::ANIMAL])->assertJsonPath('animals.rejected', []);

        $this->assertSame('POU-FINAL', Animal::findOrFail(self::ANIMAL)->identifier);
    }

    public function test_le_renvoi_identique_et_la_correction_d_une_autre_fiche_passent_toujours(): void
    {
        $this->sujet(['id' => self::ANIMAL]);

        $this->envoyer(['animals' => [$this->ligneDuPoste()]])->assertJsonPath('animals.accepted', [self::ANIMAL]);
        $this->envoyer(['animals' => [$this->ligneDuPoste(['cage' => 'C9', 'breed' => 'Rhode Island'])]])->assertJsonPath('animals.accepted', [self::ANIMAL]);

        $this->assertSame(['POU-2026-0007', 'C9', 'Rhode Island'], [Animal::findOrFail(self::ANIMAL)->identifier, Animal::findOrFail(self::ANIMAL)->cage, Animal::findOrFail(self::ANIMAL)->breed]);
    }

    public function test_les_saillies_pointent_par_l_identifiant_et_le_gel_les_garde_rattachees(): void
    {
        $a = $this->sujet(['id' => self::ANIMAL]);
        LivestockReproductionEvent::create([
            'lot_id' => $this->pondeuses->id, 'mother_ref' => 'POU-2026-0007', 'sire_ref' => 'POU-MALE-1',
            'saillie_date' => '2026-09-01', 'status' => 'en_cours',
        ]);
        $this->assertSame(1, $a->reproductionEvents()->count(), 'la saillie se retrouve par l\'identifiant');

        $this->envoyer(['animals' => [$this->ligneDuPoste(['identifier' => 'POU-2026-0008'])]])->assertJsonPath('animals.accepted', []);
        Livewire::test(RegistreReproducteurs::class)->call('editAnimal', $a->id)->set('identifier', 'POU-2026-0008')->call('saveAnimal');

        $this->assertSame(1, $a->fresh()->reproductionEvents()->count(), 'aucune saillie orpheline : l\'identifiant n\'a pas bougé');
    }

    public function test_aucune_autre_voie_ne_reecrit_l_identifiant_d_un_sujet(): void
    {
        // Garde-fou lu dans le code : en dehors du point de passage, personne n'écrit `identifier` sur un sujet existant.
        $ecrivains = [];
        foreach (new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator(app_path())) as $fichier) {
            if ($fichier->getExtension() !== 'php') {
                continue;
            }
            $source = file_get_contents($fichier->getPathname());
            if (preg_match('/Animal::(?:query\(\)|where\([^)]*\)|whereKey\([^)]*\)|find[A-Za-z]*\([^)]*\))->(?:update|fill)\(|\$(?:animal|sujet|a)->identifier\s*=[^=]/', $source)) {
                $ecrivains[] = str_replace(app_path().DIRECTORY_SEPARATOR, '', $fichier->getPathname());
            }
        }
        $this->assertSame([], $ecrivains);

        $modifier = (string) file_get_contents(app_path('Actions/SaisieReproducteurAction.php'));
        $this->assertStringContainsString('MESSAGE_IDENTIFIANT_FIGE', substr($modifier, (int) strpos($modifier, 'public function modifier')));
    }
}
