<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\Employee;
use App\Services\Import\ImportRefuse;

/**
 * Ticket IMPORT-5 — LE CSV DE REPLI : même analyse, mêmes motifs, mêmes numéros de ligne que le classeur xlsx.
 */
class ImportMasseCsvTest extends ImportMasseBase
{
    /** Écrit un fichier CSV (octets tels quels) et rend son chemin. */
    private function csv(string $contenu): string
    {
        $dossier = sys_get_temp_dir().'/agrierp_csv_'.uniqid();
        mkdir($dossier);
        $chemin = $dossier.'/import.csv';
        file_put_contents($chemin, $contenu);

        return $chemin;
    }

    private function analyserCsv(string $module, string $contenu, $user)
    {
        return $this->service()->analyser($module, $this->csv($contenu), 'import.csv', $user);
    }

    public function test_utf8_avec_bom_et_point_virgule(): void
    {
        $user = $this->utilisateur(['manage-ventes']);

        $lot = $this->analyserCsv('clients', "\xEF\xBB\xBFNom *;Téléphone;E-mail;Ville;IFU\r\nBoulangerie Le Bon Pain;0197123456;;Pobè;3201234567890\r\n\r\nMme Adjovi;;;Ikpinlè;\r\n", $user);

        $this->assertSame([2, 0, 0], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $this->assertSame([2, 4], array_column($lot->lignes, 'ligne'), 'Le numéro est celui de l\'enregistrement (en-tête = 1) ; la ligne vide est sautée.');
        $this->assertSame(2, $this->service()->importer($lot, $user)->creees);
        $this->assertSame('0197123456', Customer::where('name', 'Boulangerie Le Bon Pain')->value('phone'), 'Le zéro initial est gardé : le CSV est lu comme du texte.');
    }

    public function test_windows_1252_virgule_guillemets_et_saut_de_ligne(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $contenu = "Nom *,Téléphone,E-mail,Ville,IFU\n\"Société « Évolution », Pobè\",0196111111,,\"Cotonou\nCentre\",\n\"Dit \"\"Le Grand\"\"\",0196111112,,Pobè,\n";
        $win = mb_convert_encoding($contenu, 'Windows-1252', 'UTF-8');
        $this->assertFalse(mb_check_encoding($win, 'UTF-8'));

        $lot = $this->analyserCsv('clients', $win, $user);
        $this->assertSame([2, 0, 0], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $this->service()->importer($lot, $user);

        $this->assertNotNull(Customer::where('name', 'Société « Évolution », Pobè')->first());
        $this->assertSame("Cotonou\nCentre", Customer::where('name', 'Société « Évolution », Pobè')->value('city'));
        $this->assertNotNull(Customer::where('name', 'Dit "Le Grand"')->first());
    }

    public function test_tabulation_et_memes_motifs_que_le_classeur(): void
    {
        $user = $this->utilisateur(['manage-rh']);
        $csv = "Nom *\tPrénom *\tPoste *\tDate d'embauche *\tSalaire de base (FCFA)\tStatut\nAGBOTON\tPascal\tGardien\t01/03/2024\t45000\tActif\nDOSSOU\tClarisse\tAide\t2025-09-15\t\t\n";

        $lotCsv = $this->analyserCsv('employes', $csv, $user);
        $lotXlsx = $this->analyser('employes', [
            ['nom' => 'AGBOTON', 'prenom' => 'Pascal', 'poste' => 'Gardien', 'date_embauche' => '01/03/2024', 'salaire' => '45000', 'statut' => 'Actif'],
            ['nom' => 'DOSSOU', 'prenom' => 'Clarisse', 'poste' => 'Aide', 'date_embauche' => '2025-09-15'],
        ], $user);

        $this->assertSame(array_column($lotXlsx->lignes, 'motif'), array_column($lotCsv->lignes, 'motif'));
        $this->assertSame(array_column($lotXlsx->lignes, 'statut'), array_column($lotCsv->lignes, 'statut'));
        $this->assertStringContainsString('Date invalide : « 01/03/2024 »', $lotCsv->lignes[0]['motif'], 'Une date réécrite par le tableur est refusée avec son motif.');

        $this->service()->importer($lotCsv, $user);
        $this->assertSame(1, Employee::count());
    }

    public function test_un_csv_reimporte_apres_le_xlsx_ne_cree_rien(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $this->service()->importer($this->analyser('clients', [['nom' => 'Client Un', 'telephone' => '0197000001']], $user), $user);

        $lot = $this->analyserCsv('clients', "Nom *;Téléphone;E-mail;Ville;IFU\nClient Un;0197000001;;;\n", $user);

        $this->assertSame([0, 1, 0], [$lot->valides, $lot->ignorees, $lot->refusees]);
    }

    public function test_les_refus_du_fichier_entier(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $refus = function (string $contenu) use ($user): string {
            try {
                $this->analyserCsv('clients', $contenu, $user);
            } catch (ImportRefuse $e) {
                return $e->getMessage();
            }
            $this->fail('refus attendu');
        };

        $this->assertStringContainsString("n'est pas un fichier CSV lisible", $refus(''));
        $this->assertStringContainsString("n'est pas un fichier CSV lisible", $refus("PK\x03\x04\0\0binaire"));
        $this->assertSame(
            'Colonne manquante ou renommée dans la première ligne du fichier CSV : « Nom * ». Ne renommez pas les en-têtes : téléchargez le modèle « Clients » à jour.',
            $refus("Raison sociale;Téléphone;E-mail;Ville;IFU\nA;;;;\n"),
        );
        $this->assertStringStartsWith('Le fichier ne contient aucune ligne à importer', $refus("Nom *;Téléphone;E-mail;Ville;IFU\n;;;;\n"));
    }

    public function test_les_droits_restent_ceux_du_module(): void
    {
        $this->expectException(\Illuminate\Auth\Access\AuthorizationException::class);
        $this->analyserCsv('employes', "Nom *;Prénom *;Poste *;Date d'embauche *\nA;B;C;2024-01-01\n", $this->utilisateur(['manage-ventes']));
    }
}
