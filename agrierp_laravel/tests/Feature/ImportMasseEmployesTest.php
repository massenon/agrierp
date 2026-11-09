<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Employee;
use App\Services\Import\ImportMasseService;
use Illuminate\Auth\Access\AuthorizationException;

/**
 * Ticket IMPORT-2 — l'importation en masse des EMPLOYÉS (`SaisieEmployeAction::creer`, point de passage unique, droit `manage-rh`).
 */
class ImportMasseEmployesTest extends ImportMasseBase
{
    private function ligne(array $remplace = []): array
    {
        return array_merge([
            'nom' => 'AGBOTON', 'prenom' => 'Pascal', 'poste' => 'Gardien', 'date_embauche' => '2024-03-01', 'salaire' => '45000', 'statut' => 'Actif',
        ], $remplace);
    }

    public function test_un_fichier_valide_cree_les_employes(): void
    {
        $user = $this->utilisateur(['manage-rh']);

        $lot = $this->analyser('employes', [
            $this->ligne(),
            $this->ligne(['nom' => 'DOSSOU', 'prenom' => 'Clarisse', 'poste' => 'Aide', 'date_embauche' => '2025-09-15', 'salaire' => '', 'statut' => 'congé']),
            $this->ligne(['nom' => 'KPADE', 'prenom' => 'Jean', 'date_embauche' => '2025-01-02', 'statut' => '']),
        ], $user);
        $this->assertSame(3, $lot->valides);

        $lot = $this->service()->importer($lot, $user);

        $this->assertSame(3, $lot->creees);
        $pascal = Employee::where('last_name', 'AGBOTON')->firstOrFail();
        $this->assertSame('Pascal', $pascal->first_name);
        $this->assertSame('2024-03-01', $pascal->hire_date->format('Y-m-d'));
        $this->assertSame('45000.00', $pascal->base_salary);
        $this->assertSame('actif', $pascal->status);
        $this->assertTrue($pascal->is_active);
        $this->assertSame('conge', Employee::where('last_name', 'DOSSOU')->value('status'));
        $this->assertNull(Employee::where('last_name', 'DOSSOU')->value('base_salary'));
        $this->assertSame('actif', Employee::where('last_name', 'KPADE')->value('status'), 'Statut vide : Actif.');
        $this->assertSame(3, AuditLog::where('action', 'employee.created')->count());
        $this->assertSame(1, AuditLog::where('action', 'import.masse')->where('module', 'rh')->count());
    }

    public function test_les_lignes_erronees_sont_refusees_avec_les_motifs_du_service(): void
    {
        $user = $this->utilisateur(['manage-rh']);

        $lot = $this->analyser('employes', [
            $this->ligne(['nom' => '']),
            $this->ligne(['prenom' => '', 'nom' => 'B']),
            $this->ligne(['nom' => 'C', 'poste' => '']),
            $this->ligne(['nom' => 'D', 'date_embauche' => '01/03/2024']),
            $this->ligne(['nom' => 'E', 'date_embauche' => '2024-02-31']),
            $this->ligne(['nom' => 'F', 'date_embauche' => '']),
            $this->ligne(['nom' => 'G', 'statut' => 'Retraité']),
            $this->ligne(['nom' => 'H', 'salaire' => '45000,5']),
            $this->ligne(['nom' => str_repeat('N', 101)]),
            $this->ligne(['nom' => 'Bon', 'prenom' => 'Employé']),
        ], $user);

        $this->assertSame([1, 0, 9], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $m = collect($lot->lignes)->keyBy('ligne')->map(fn ($l) => $l['motif']);
        $this->assertSame('Feuille « Données », ligne 2, colonne « Nom * » : Le champ nom est obligatoire.', $m[2]);
        $this->assertSame('Feuille « Données », ligne 3, colonne « Prénom * » : Le champ prénom est obligatoire.', $m[3]);
        $this->assertSame('Feuille « Données », ligne 4, colonne « Poste * » : Le champ poste est obligatoire.', $m[4]);
        $this->assertSame("Feuille « Données », ligne 5, colonne « Date d'embauche * » : Date invalide : « 01/03/2024 ». Écrivez la date au format AAAA-MM-JJ (exemple : 2026-11-08).", $m[5]);
        $this->assertStringContainsString('Date invalide : « 2024-02-31 »', $m[6]);
        $this->assertSame("Feuille « Données », ligne 7, colonne « Date d'embauche * » : Le champ date d'embauche est obligatoire.", $m[7]);
        $this->assertSame('Feuille « Données », ligne 8, colonne « Statut » : Statut inconnu : « Retraité ». Choisissez une valeur de la liste déroulante.', $m[8]);
        $this->assertSame('Feuille « Données », ligne 9, colonne « Salaire de base (FCFA) » : Montant invalide : un nombre entier de FCFA est attendu.', $m[9]);
        $this->assertSame('Feuille « Données », ligne 10, colonne « Nom * » : Le champ nom ne doit pas dépasser 100 caractères.', $m[10]);

        $this->assertSame(1, $this->service()->importer($lot, $user)->creees);
    }

    public function test_doublon_du_fichier_doublon_en_base_et_archive(): void
    {
        $user = $this->utilisateur(['manage-rh']);
        $actif = Employee::create(['first_name' => 'Marie', 'last_name' => 'Adjovi', 'position' => 'Comptable', 'hire_date' => '2023-05-10', 'status' => 'actif', 'is_active' => true]);
        Employee::create(['first_name' => 'Luc', 'last_name' => 'Zinsou', 'position' => 'Ancien', 'hire_date' => '2020-01-01', 'status' => 'actif', 'is_active' => false]);

        $lot = $this->analyser('employes', [
            $this->ligne(),
            $this->ligne(['nom' => 'agbotôn', 'prenom' => 'PÀSCAL']),
            $this->ligne(['nom' => 'ADJOVI', 'prenom' => 'marie', 'poste' => 'Autre poste', 'date_embauche' => '2023-05-10']),
            $this->ligne(['nom' => 'Zinsou', 'prenom' => 'Luc', 'date_embauche' => '2020-01-01']),
            $this->ligne(['nom' => 'ADJOVI', 'prenom' => 'Marie', 'date_embauche' => '2024-06-01']),
        ], $user);

        $this->assertSame([3, 1, 1], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $this->assertSame('Ligne 3 : doublon de la ligne 2.', $lot->lignes[1]['motif']);
        $this->assertSame("Cet employé existe déjà (même nom, même prénom, même date d'embauche) : ignoré, la fiche existante est gardée.", $lot->lignes[2]['motif']);

        $this->service()->importer($lot, $user);
        $this->assertSame('Comptable', $actif->fresh()->position, 'Jamais d\'écrasement.');
        $this->assertSame(2, Employee::where('last_name', 'Zinsou')->count(), 'Un archivé ne compte pas comme déjà présent : un employé actif est créé.');
    }

    public function test_un_reimport_ne_cree_aucun_doublon(): void
    {
        $user = $this->utilisateur(['manage-rh']);
        $lignes = [$this->ligne(), $this->ligne(['nom' => 'Second', 'date_embauche' => '2025-02-02'])];

        $this->service()->importer($this->analyser('employes', $lignes, $user), $user);
        $second = $this->analyser('employes', $lignes, $user);

        $this->assertSame([0, 2, 0], [$second->valides, $second->ignorees, $second->refusees]);
        $this->service()->importer($second, $user);
        $this->assertSame(2, Employee::count());
    }

    public function test_le_salaire_ne_figure_jamais_au_rapport_ni_au_journal(): void
    {
        $user = $this->utilisateur(['manage-rh']);
        $lot = $this->analyser('employes', [
            $this->ligne(['nom' => 'REFUSE', 'salaire' => '123456', 'poste' => '']),
            $this->ligne(['nom' => 'BON', 'salaire' => '654321']),
        ], $user);
        $lot = $this->service()->importer($lot, $user);

        $this->assertArrayNotHasKey('salaire', $lot->lignes[0]['brut'], 'Même une ligne refusée ne garde pas le salaire.');
        $this->assertNull($lot->lignes[1]['brut']);
        $this->assertStringNotContainsString('123456', json_encode($lot->lignes));
        $this->assertStringNotContainsString('654321', json_encode($lot->lignes));

        // Le rapport d'un APERÇU (valeurs encore lues) masque aussi la colonne.
        $apercu = $this->analyser('employes', [$this->ligne(['nom' => 'REFUSE2', 'salaire' => '777777', 'poste' => ''])], $user);
        $chemin = $this->service()->rapportXlsx($apercu);
        $feuille = \PhpOffice\PhpSpreadsheet\IOFactory::load($chemin)->getSheetByName('Lignes refusées');
        $this->assertSame('REFUSE2', (string) $feuille->getCell('C2')->getValue());
        $this->assertSame('', (string) $feuille->getCell('G2')->getValue(), 'La colonne « Salaire de base (FCFA) » reste vide.');
        $this->assertStringNotContainsString('777777', json_encode($feuille->toArray()));
        @unlink($chemin);
    }

    public function test_les_droits_exigent_manage_rh(): void
    {
        $sans = $this->utilisateur(['manage-ventes', 'manage-stocks', 'manage-comptabilite']);
        $this->assertArrayNotHasKey('employes', $this->service()->modulesAutorises($sans));
        $this->assertArrayHasKey('employes', $this->service()->modulesAutorises($this->utilisateur(['manage-rh'], 'RH')));

        $this->expectException(AuthorizationException::class);
        $this->analyser('employes', [$this->ligne()], $sans);
    }

    public function test_le_module_est_au_registre(): void
    {
        $this->assertSame('manage-rh', ImportMasseService::module('employes')->permission());
    }
}
