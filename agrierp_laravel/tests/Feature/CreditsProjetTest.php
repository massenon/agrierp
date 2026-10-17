<?php

namespace Tests\Feature;

use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 15.8 (Sprint 15) — LES TROIS STRUCTURES DU PROJET, CRÉDITÉES PARTOUT.
 *
 * Trois structures interviennent sur AgriERP, avec des rôles DISTINCTS :
 *
 *   • PAEB — Projet d'Appui à l'Entrepreneuriat au Bénin ... maîtrise d'ouvrage
 *   • Cabinet FAGUEZ SARL .................................. accompagnement des PME
 *   • Dr MASSENON Rhodes ................................... éditeur du logiciel
 *
 * ⚠️ POURQUOI CE TEST EXISTE. Le ticket 15.2 a remplacé « FAGUEZ SARL » par
 * « Dr MASSENON Rhodes » partout où l'ÉDITEUR était nommé — correct — mais a
 * du même coup effacé le cabinet d'accompagnement des pieds de page, où il a
 * sa place à part entière. Personne ne s'en est aperçu pendant deux tickets :
 * un crédit manquant ne casse rien, n'émet aucune erreur, et ne se voit que
 * si quelqu'un lit attentivement un pied de page.
 *
 * Ce test échouerait si un futur nettoyage refaisait la même chose.
 */
class CreditsProjetTest extends TestCase
{
    use RefreshDatabase;

    private const PAEB = 'PAEB';
    private const CABINET = 'Cabinet FAGUEZ SARL';
    private const EDITEUR = 'MASSENON Rhodes';

    /**
     * Ramène le HTML à une forme comparable.
     *
     * ⚠️ NÉCESSAIRE, PAS COSMÉTIQUE : les vues soudent volontairement les noms
     * propres avec des espaces insécables (`Dr&nbsp;MASSENON&nbsp;Rhodes`) pour
     * qu'ils ne se coupent jamais en fin de ligne — défaut constaté sur le pied
     * de page de l'écran de connexion. Une recherche littérale sur
     * « MASSENON Rhodes » échouerait alors, alors que le nom est bien affiché.
     * On compare donc le SENS, pas les octets.
     */
    private function normaliser(string $html): string
    {
        return preg_replace('/\s+/u', ' ', str_replace(['&nbsp;', "\xC2\xA0"], ' ', $html));
    }

    private function utilisateur(): User
    {
        Permission::findOrCreate('view-elevage', 'web');
        $role = Role::findOrCreate('admin', 'web');
        $role->givePermissionTo('view-elevage');

        $u = User::create([
            'name' => 'Test Crédits',
            'username' => 'credits',
            'email' => 'credits@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'),
            'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    // =================================================================
    //  Pages accessibles sans connexion
    // =================================================================

    public static function pagesPubliques(): array
    {
        return [
            'connexion' => ['/login'],
            'accueil' => ['/welcome'],
            'présentation' => ['/presentation'],
        ];
    }

    /**
     * @dataProvider pagesPubliques
     */
    public function test_les_pages_publiques_creditent_les_trois_structures(string $url): void
    {
        $html = $this->normaliser($this->get($url)->assertOk()->getContent());

        foreach ([self::PAEB, self::CABINET, self::EDITEUR] as $structure) {
            $this->assertStringContainsString($structure, $html,
                "« {$structure} » n'apparaît pas sur {$url}. Les trois structures du projet ".
                'doivent être créditées : PAEB (maîtrise d\'ouvrage), Cabinet FAGUEZ SARL '.
                "(accompagnement des PME), Dr MASSENON Rhodes (éditeur).");
        }
    }

    // =================================================================
    //  Pages internes
    // =================================================================

    public function test_l_ecran_aide_credite_les_trois_structures(): void
    {
        $html = $this->normaliser($this->actingAs($this->utilisateur())->get('/aide-a-propos')->assertOk()->getContent());

        foreach ([self::PAEB, self::CABINET, self::EDITEUR] as $structure) {
            $this->assertStringContainsString($structure, $html,
                "« {$structure} » manque sur l'écran Aide & À Propos.");
        }
    }

    public function test_l_ecran_de_contact_oriente_vers_le_bon_interlocuteur(): void
    {
        $html = $this->normaliser($this->actingAs($this->utilisateur())->get('/contact-editeur')->assertOk()->getContent());

        // Les coordonnées de l'éditeur restent la raison d'être de l'écran.
        $this->assertStringContainsString(self::EDITEUR, $html);
        $this->assertStringContainsString('rarhodes06@gmail.com', $html);
        $this->assertStringContainsString('contact@massenonrhodes.com', $html);

        // ⚠️ Le point du ticket : un barème fiscal ou un taux de charges ne se
        // corrige pas dans le code. Sans ce renvoi, ces demandes arrivent à
        // l'éditeur, qui ne peut que les réorienter — et la ferme perd des jours.
        $this->assertStringContainsString(self::CABINET, $html,
            "L'écran de contact doit renvoyer vers le cabinet d'accompagnement ".
            'pour les questions réglementaires (barème ITS, taux CNSS, plan comptable).');
        $this->assertStringContainsString('Qui contacter', $html);
    }

    // =================================================================
    //  Cohérence avec le manuel
    // =================================================================

    public function test_le_cabinet_reste_nomme_sur_l_ecran_du_bareme_fiscal(): void
    {
        $vue = file_get_contents(resource_path('views/livewire/parametres/bareme-its.blade.php'));

        // ⚠️ ARBITRAGE CLOS AU TICKET 15.7 : cette mention avait été signalée
        // comme un oubli du renommage du ticket 15.2. Elle est en réalité
        // CORRECTE — c'est bien le cabinet d'accompagnement qui valide un
        // barème fiscal, jamais l'auteur du code. Ce test empêche qu'un futur
        // « nettoyage » la remplace par le nom de l'éditeur.
        $this->assertStringContainsString('Cabinet FAGUEZ', $vue,
            "L'écran du barème IR-PTS / ITS doit continuer de renvoyer au cabinet ".
            "d'accompagnement pour validation. Ce n'est pas un reliquat de renommage.");
    }
}
