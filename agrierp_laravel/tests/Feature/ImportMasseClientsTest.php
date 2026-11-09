<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Services\Import\ImportMasseService;
use Illuminate\Auth\Access\AuthorizationException;

/**
 * Ticket IMPORT-1 — l'importation en masse des CLIENTS (`CustomerCatalogService::creer`, point de passage unique).
 */
class ImportMasseClientsTest extends ImportMasseBase
{
    private function ligne(array $remplace = []): array
    {
        return array_merge(['nom' => 'Boulangerie Le Bon Pain', 'telephone' => '0197123456', 'email' => 'contact@bonpain.example', 'ville' => 'Pobè', 'ifu' => '3201234567890'], $remplace);
    }

    public function test_un_fichier_valide_cree_les_clients_par_la_fabrique_du_web(): void
    {
        $user = $this->utilisateur(['manage-ventes']);

        $lot = $this->analyser('clients', [
            $this->ligne(),
            $this->ligne(['nom' => 'Mme Adjovi', 'telephone' => '', 'email' => '', 'ifu' => '', 'ville' => 'Ikpinlè']),
            $this->ligne(['nom' => 'Chez Tantie', 'telephone' => '0196000001', 'email' => '', 'ifu' => '', 'ville' => '']),
        ], $user);
        $this->assertSame([3, 0, 0], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $this->assertSame(0, Customer::count());

        $lot = $this->service()->importer($lot, $user);

        $this->assertSame(3, $lot->creees);
        $boulangerie = Customer::where('name', 'Boulangerie Le Bon Pain')->firstOrFail();
        $this->assertSame('0197123456', $boulangerie->phone, 'Le zéro initial du téléphone est conservé.');
        $this->assertSame('3201234567890', $boulangerie->ifu);
        $this->assertSame('Pobè', $boulangerie->city);
        $this->assertTrue($boulangerie->is_active);
        $this->assertEquals(0, $boulangerie->credit_limit, 'Le plafond de crédit n\'est jamais écrit par un import.');
        $this->assertSame(3, AuditLog::where('action', 'customer.created')->count());
        $this->assertSame(1, AuditLog::where('action', 'import.masse')->where('module', 'ventes')->count());

        // L'identifiant est DÉTERMINISTE (UUID v5 du module et de la clé de ligne) : le poste calcule le même.
        $this->assertSame(
            \Ramsey\Uuid\Uuid::uuid5('b3b0e2c4-6f5e-5b7a-9a4d-2f1c7a1d0e51', 'clients|boulangerie le bon pain|0197123456')->toString(),
            $boulangerie->id,
        );
    }

    public function test_les_lignes_erronees_sont_refusees_avec_les_motifs_du_service(): void
    {
        $user = $this->utilisateur(['manage-ventes']);

        $lot = $this->analyser('clients', [
            $this->ligne(['nom' => 'IFU court', 'telephone' => '0197000001', 'ifu' => '320123456789']),
            $this->ligne(['nom' => 'Mail faux', 'telephone' => '0197000002', 'email' => 'pas-un-mail']),
            $this->ligne(['nom' => str_repeat('N', 151), 'telephone' => '0197000003']),
            $this->ligne(['nom' => '', 'telephone' => '0197000004']),
            $this->ligne(['nom' => 'Bon client', 'telephone' => '0197000005']),
        ], $user);

        $this->assertSame([1, 0, 4], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $motifs = collect($lot->lignes)->keyBy('ligne')->map(fn ($l) => $l['motif']);
        $this->assertSame('Feuille « Données », ligne 2, colonne « IFU » : L\'IFU du client doit comporter 13 chiffres (laissez-le vide pour un client sans IFU).', $motifs[2]);
        $this->assertSame('Feuille « Données », ligne 3, colonne « E-mail » : Le champ e-mail doit être une adresse e-mail valide.', $motifs[3]);
        $this->assertSame('Feuille « Données », ligne 4, colonne « Nom * » : Le champ nom ne doit pas dépasser 150 caractères.', $motifs[4]);
        $this->assertSame('Feuille « Données », ligne 5, colonne « Nom * » : Le champ nom est obligatoire.', $motifs[5]);

        $this->assertSame(1, $this->service()->importer($lot, $user)->creees);
        $this->assertSame(['Bon client'], Customer::pluck('name')->all());
    }

    public function test_doublon_dans_le_fichier_meme_nom_et_meme_telephone_ecrits_differemment(): void
    {
        $user = $this->utilisateur(['manage-ventes']);

        $lot = $this->analyser('clients', [
            $this->ligne(),
            $this->ligne(['nom' => 'BOULANGERIE le bon pain', 'telephone' => '+229 01 97 12 34 56']),
            $this->ligne(['nom' => 'Même nom, autre numéro', 'telephone' => '0197999999']),
        ], $user);

        $this->assertSame(2, $lot->valides);
        $this->assertTrue($lot->lignes[1]['doublon']);
        $this->assertSame('Ligne 3 : doublon de la ligne 2.', $lot->lignes[1]['motif']);
    }

    public function test_un_client_deja_en_base_est_ignore_et_sa_fiche_n_est_pas_modifiee(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $existant = Customer::create(['name' => 'Boulangerie Le Bon Pain', 'phone' => '+229 0197123456', 'city' => 'Cotonou', 'is_active' => true]);

        $lot = $this->analyser('clients', [$this->ligne(['ville' => 'Pobè']), $this->ligne(['nom' => 'Nouveau', 'telephone' => '0197555555'])], $user);

        $this->assertSame([1, 1, 0], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $this->assertSame('Ce client existe déjà (même nom, même téléphone) : ignoré, la fiche existante est gardée.', $lot->lignes[0]['motif']);

        $this->service()->importer($lot, $user);
        $this->assertSame('Cotonou', $existant->fresh()->city, 'Création SEULE : jamais d\'écrasement.');
        $this->assertSame(2, Customer::count());
    }

    public function test_un_reimport_ne_cree_aucun_doublon_meme_sans_telephone(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $lignes = [$this->ligne(), $this->ligne(['nom' => 'Mme Adjovi', 'telephone' => '', 'email' => '', 'ifu' => ''])];

        $this->assertSame(2, $this->service()->importer($this->analyser('clients', $lignes, $user), $user)->creees);

        $second = $this->analyser('clients', $lignes, $user);
        $this->assertSame([0, 2, 0], [$second->valides, $second->ignorees, $second->refusees]);
        $this->assertSame('Ce client a déjà été importé : ignoré.', $second->lignes[1]['motif'], 'Sans téléphone : l\'UUID déterministe fait l\'idempotence.');

        $this->service()->importer($second, $user);
        $this->assertSame(2, Customer::count());
    }

    public function test_le_poste_peut_deja_avoir_envoye_le_meme_client_par_la_synchronisation(): void
    {
        // Même identifiant déterministe : un client déjà poussé sous cet UUID est reconnu, archivé compris.
        $user = $this->utilisateur(['manage-ventes']);
        $module = ImportMasseService::module('clients');
        $valeurs = $module->valider(['nom' => 'Mme Adjovi', 'telephone' => '', 'email' => '', 'ville' => '', 'ifu' => ''])['valeurs'];
        $client = new Customer();
        $client->id = $module->idLigne($valeurs);
        $client->fill(['name' => 'Mme Adjovi', 'is_active' => false])->save();

        $lot = $this->analyser('clients', [['nom' => 'Mme Adjovi']], $user);

        $this->assertSame(1, $lot->ignorees);
        $this->assertSame('Ce client a déjà été importé : ignoré.', $lot->lignes[0]['motif']);
    }

    public function test_les_droits_exigent_manage_ventes(): void
    {
        $this->expectException(AuthorizationException::class);
        $this->analyser('clients', [$this->ligne()], $this->utilisateur(['manage-stocks', 'manage-achats']));
    }

    public function test_un_exercice_clos_n_empeche_pas_d_importer_des_clients(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        FiscalYear::query()->update(['status' => 'cloture']);

        $lot = $this->analyser('clients', [$this->ligne()], $user);
        $this->assertNull($lot->rapport['bloquant']);
        $this->assertSame(1, $this->service()->importer($lot, $user)->creees);
    }

    public function test_un_telephone_saisi_comme_nombre_perd_son_zero_mais_reste_lisible(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $lot = $this->analyser('clients', [$this->ligne(['telephone' => 97123456])], $user);

        $this->assertSame(1, $lot->valides);
        $this->service()->importer($lot, $user);
        $this->assertSame('97123456', Customer::first()->phone);
    }
}
