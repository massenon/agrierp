<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheLapins;
use App\Livewire\Elevage\FichePorcs;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Défaut du 21/10/2026 : vider un champ numérique de la fiche Lapins levait « Property [$ne] not found » (500).
 * Un champ vidé vaut 0 ; l'écran se redessine ; une propriété nullable garde son « inconnu ».
 */
class ChampNumeriqueVideTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        $this->actingAs(User::where('username', 'admin')->firstOrFail());
    }

    public function test_vider_un_champ_numerique_de_la_fiche_lapins_le_remet_a_zero_sans_erreur(): void
    {
        $c = Livewire::test(FicheLapins::class);

        foreach (['achat', 'ne', 'mortRepro', 'mortChair', 'mortLapereau', 'donRepro', 'donChair'] as $champ) {
            $c->set($champ, 5)->set($champ, null)->assertHasNoErrors()->assertSet($champ, 0);
            // La propriété doit être INITIALISÉE (sinon le prochain `$this->$champ` lève « Property not found »,
            // même quand l'écran ne la lit qu'avec une chaîne de départ, absente de ce décor).
            $this->assertTrue(
                (new \ReflectionProperty(FicheLapins::class, $champ))->isInitialized($c->instance()),
                "« $champ » est restée non initialisée après avoir été vidée"
            );
        }

        // Le rendu qui suit (catégories du jour, provende, KPI) relit les champs : aucune exception.
        $c->assertOk()->set('ne', 3)->assertSet('ne', 3);
    }

    public function test_vider_un_champ_numerique_de_la_fiche_porcs_ne_leve_pas_d_erreur(): void
    {
        $c = Livewire::test(FichePorcs::class);
        $reflexion = new \ReflectionClass(FichePorcs::class);

        foreach ($reflexion->getProperties(\ReflectionProperty::IS_PUBLIC) as $p) {
            if ($p->getDeclaringClass()->getName() !== FichePorcs::class || ! $p->getType() instanceof \ReflectionNamedType) {
                continue;
            }
            if ($p->getType()->getName() === 'int' && ! $p->getType()->allowsNull()) {
                $c->set($p->getName(), null)->assertSet($p->getName(), 0);
                break;
            }
        }
        $c->assertOk();
    }

    public function test_une_propriete_nullable_garde_son_inconnu(): void
    {
        $composant = new class extends \Livewire\Component {
            public ?int $inconnu = 7;
            public int $compte = 4;
            public float $prix = 1.5;
            public function render() { return '<div></div>'; }
        };

        unset($composant->inconnu, $composant->compte, $composant->prix);
        \App\Support\ChampNumeriqueVide::normaliser($composant, 'inconnu');
        \App\Support\ChampNumeriqueVide::normaliser($composant, 'compte');
        \App\Support\ChampNumeriqueVide::normaliser($composant, 'prix');

        $this->assertFalse((new \ReflectionProperty($composant, 'inconnu'))->isInitialized($composant), 'le nullable reste inconnu');
        $this->assertSame(0, $composant->compte);
        $this->assertSame(0.0, $composant->prix);
    }
}
