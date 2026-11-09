<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use Illuminate\Auth\Access\AuthorizationException;

/**
 * Ticket IMPORT-3 — l'importation en masse des COMPTES du plan comptable (`PlanComptableService::creer`, droit `manage-comptabilite`).
 */
class ImportMassePlanComptableTest extends ImportMasseBase
{
    private function ligne(array $remplace = []): array
    {
        return array_merge(['numero' => '60511', 'libelle' => 'Achats de provende', 'classe' => '6 - Charges'], $remplace);
    }

    public function test_un_fichier_valide_cree_les_comptes(): void
    {
        $user = $this->utilisateur(['manage-comptabilite']);

        $lot = $this->analyser('plan_comptable', [
            $this->ligne(),
            $this->ligne(['numero' => '70131', 'libelle' => 'Ventes de lapins', 'classe' => '7']),
            $this->ligne(['numero' => 6052, 'libelle' => 'Achats de vaccins', 'classe' => '6 - CHARGES']),
        ], $user);
        $this->assertSame([3, 0, 0], [$lot->valides, $lot->ignorees, $lot->refusees]);

        $this->service()->importer($lot, $user);

        $compte = ChartOfAccount::where('code', '60511')->firstOrFail();
        $this->assertSame('Achats de provende', $compte->label);
        $this->assertSame(6, (int) $compte->class);
        $this->assertTrue($compte->is_active);
        $this->assertSame(7, (int) ChartOfAccount::where('code', '70131')->value('class'));
        $this->assertSame(1, AuditLog::where('action', 'import.masse')->where('module', 'comptabilite')->count());
        $this->assertSame(3, AuditLog::where('action', 'chart_of_account.created')->count());
    }

    public function test_les_lignes_erronees_sont_refusees_avec_les_motifs_du_service(): void
    {
        $user = $this->utilisateur(['manage-comptabilite']);

        $lot = $this->analyser('plan_comptable', [
            $this->ligne(['numero' => '']),
            $this->ligne(['numero' => str_repeat('1', 21)]),
            $this->ligne(['numero' => '6053', 'libelle' => '']),
            $this->ligne(['numero' => '6054', 'classe' => '']),
            $this->ligne(['numero' => '6055', 'classe' => '10']),
            $this->ligne(['numero' => '6056', 'classe' => 'abc']),
            $this->ligne(['numero' => '6057', 'classe' => '0']),
            $this->ligne(['numero' => '6058']),
        ], $user);

        $this->assertSame([1, 0, 7], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $m = collect($lot->lignes)->keyBy('ligne')->map(fn ($l) => $l['motif']);
        $this->assertSame('Feuille « Données », ligne 2, colonne « Numéro de compte * » : Le champ code est obligatoire.', $m[2]);
        $this->assertSame('Feuille « Données », ligne 3, colonne « Numéro de compte * » : Le champ code ne doit pas dépasser 20 caractères.', $m[3]);
        $this->assertSame('Feuille « Données », ligne 4, colonne « Intitulé * » : Le champ libellé est obligatoire.', $m[4]);
        $this->assertSame('Feuille « Données », ligne 5, colonne « Classe * » : Le champ classe est obligatoire.', $m[5]);
        $this->assertSame('Feuille « Données », ligne 6, colonne « Classe * » : Le champ classe doit être compris entre 1 et 9.', $m[6]);
        $this->assertSame('Feuille « Données », ligne 7, colonne « Classe * » : Le champ classe doit être un nombre entier.', $m[7]);
        $this->assertSame('Feuille « Données », ligne 8, colonne « Classe * » : Le champ classe doit être compris entre 1 et 9.', $m[8]);
    }

    public function test_numero_deja_au_plan_ou_en_double_dans_le_fichier(): void
    {
        $user = $this->utilisateur(['manage-comptabilite']);
        $existant = ChartOfAccount::create(['code' => '6061', 'label' => 'Fournitures', 'class' => 6, 'is_active' => true]);
        ChartOfAccount::create(['code' => '6062', 'label' => 'Archivé', 'class' => 6, 'is_active' => false]);

        $lot = $this->analyser('plan_comptable', [
            $this->ligne(),
            $this->ligne(['libelle' => 'Autre libellé']),
            $this->ligne(['numero' => '6061', 'libelle' => 'Écrasement ?', 'classe' => '7']),
            $this->ligne(['numero' => '60 62', 'libelle' => 'Un archivé existe']),
        ], $user);

        $this->assertSame([1, 2, 1], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $this->assertSame('Ligne 3 : doublon de la ligne 2.', $lot->lignes[1]['motif']);
        $this->assertSame('Ce numéro de compte existe déjà au plan comptable : ignoré, le compte existant est gardé.', $lot->lignes[2]['motif']);

        $this->service()->importer($lot, $user);
        $this->assertSame('Fournitures', $existant->fresh()->label, 'Jamais d\'écrasement.');
        $this->assertSame(6, (int) $existant->fresh()->class);
    }

    public function test_un_reimport_ne_cree_aucun_doublon(): void
    {
        $user = $this->utilisateur(['manage-comptabilite']);
        $lignes = [$this->ligne(), $this->ligne(['numero' => '60512', 'libelle' => 'Achats de sel'])];
        $avant = ChartOfAccount::count();

        $this->service()->importer($this->analyser('plan_comptable', $lignes, $user), $user);
        $second = $this->analyser('plan_comptable', $lignes, $user);

        $this->assertSame([0, 2, 0], [$second->valides, $second->ignorees, $second->refusees]);
        $this->assertSame($avant + 2, ChartOfAccount::count());
    }

    public function test_les_droits_exigent_manage_comptabilite(): void
    {
        $sans = $this->utilisateur(['manage-rh', 'manage-ventes']);
        $this->assertArrayNotHasKey('plan_comptable', $this->service()->modulesAutorises($sans));

        $this->expectException(AuthorizationException::class);
        $this->analyser('plan_comptable', [$this->ligne()], $sans);
    }
}
