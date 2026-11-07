<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\ComptabiliteHub;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Hub « Comptabilité » — la cible montrée par le client (07/11/2026) : DOUZE cartes, dans cet ordre, textes exacts
 * (accents compris), puis une rangée « Autres états » qui garde les trois pages sans autre accès.
 * Le poste lit la même liste (`comptabilite_hub_cartes_test.dart`).
 */
class ComptabiliteHubCartesTest extends TestCase
{
    use RefreshDatabase;

    /** @var array<int, array{0: string, 1: string, 2: string}> titre, description, icône */
    public const DOUZE = [
        ['Plan Comptable', 'Comptes SYSCOHADA (Classes 1 à 7)', 'menu_book'],
        ['Journal Comptable', 'Écritures Débit/Crédit, saisie manuelle', 'account_balance'],
        ['Grand Livre', 'Écritures par compte, solde progressif', 'import_contacts'],
        ['Balance Générale', 'Soldes de tous les comptes utilisés', 'balance'],
        ['États Financiers', 'Bilan, Résultat, Flux de Trésorerie, Notes Annexes', 'description'],
        ['Clôture Périodique & Annuelle', "Clôture mensuelle, bascule d'exercice, report à nouveau", 'event_repeat'],
        ['Comptabilité Analytique', 'Marges réelles par filière (Cuniculture, Aviculture, Porciculture)', 'insights'],
        ['Déclaration TVA', 'TVA Collectée / Déductible, taux 18% ou exonéré', 'receipt_long'],
        ['Rapprochement Bancaire', 'Pointage Grand Livre / Relevé Banque et Mobile Money', 'sync_alt'],
        ['Bilan de l\'Entreprise', 'Actif / Passif, équilibre comptable', 'account_balance'],
        ['Immobilisations', 'Registre des biens, amortissement linéaire et dotation', 'domain'],
        ['Balance Âgée', 'Encours clients et fournisseurs par ancienneté de retard', 'schedule'],
    ];

    private function html(): string
    {
        Permission::findOrCreate('view-comptabilite', 'web');
        $role = Role::findOrCreate('comptable-hub', 'web');
        $role->syncPermissions(['view-comptabilite']);
        $u = User::create(['name' => 'Comptable', 'email' => 'hub@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026')]);
        $u->assignRole($role);
        $this->actingAs($u);

        return Livewire::test(ComptabiliteHub::class)->html();
    }

    /** @return array<int, array{0: string, 1: string}> */
    private function cartes(string $html): array
    {
        preg_match_all('#<p class="text-sm font-bold text-brand-forest">(.*?)</p>\s*<p class="text-\[11px\] text-outline">(.*?)</p>#su', $html, $m, PREG_SET_ORDER);

        return array_map(fn ($c) => [html_entity_decode($c[1], ENT_QUOTES), html_entity_decode($c[2], ENT_QUOTES)], $m);
    }

    public function test_la_grille_porte_douze_cartes_dans_l_ordre_avec_leurs_textes_exacts(): void
    {
        $cartes = $this->cartes($this->html());

        $this->assertCount(12, $cartes);
        $this->assertSame(array_map(fn ($c) => [$c[0], $c[1]], self::DOUZE), $cartes);
    }

    public function test_les_icones_sont_celles_du_client(): void
    {
        $html = $this->html();
        preg_match_all('#<span class="material-symbols-outlined text-brand-emerald text-\[24px\]">(.*?)</span>#su', $html, $m);

        $this->assertSame(array_column(self::DOUZE, 2), $m[1]);
    }

    public function test_il_n_y_a_plus_de_rangee_autres_etats(): void
    {
        $html = $this->html();

        $this->assertStringNotContainsString('Autres états', $html);
        $this->assertSame(1, substr_count($html, 'grid-cols-1 sm:grid-cols-2 gap-md'));
    }
}
