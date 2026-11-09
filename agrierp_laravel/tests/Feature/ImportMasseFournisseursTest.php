<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Supplier;
use Illuminate\Auth\Access\AuthorizationException;

/**
 * Ticket IMPORT-1 — l'importation en masse des FOURNISSEURS (`SupplierCatalogService::creer`, point de passage unique).
 */
class ImportMasseFournisseursTest extends ImportMasseBase
{
    private function ligne(array $remplace = []): array
    {
        return array_merge(['nom' => 'Provenderie du Plateau', 'categorie' => 'Aliments', 'telephone' => '0197654321', 'adresse' => 'Route de Kétou'], $remplace);
    }

    public function test_un_fichier_valide_cree_les_fournisseurs(): void
    {
        $user = $this->utilisateur(['manage-achats']);

        $lot = $this->analyser('fournisseurs', [
            $this->ligne(),
            $this->ligne(['nom' => 'Pharmacie vétérinaire Dossou', 'categorie' => 'produits VÉTÉRINAIRES', 'telephone' => '0196112233', 'adresse' => '']),
        ], $user);
        $this->assertSame(2, $lot->valides);

        $lot = $this->service()->importer($lot, $user);

        $this->assertSame(2, $lot->creees);
        $provenderie = Supplier::where('name', 'Provenderie du Plateau')->firstOrFail();
        $this->assertSame('Aliments', $provenderie->category);
        $this->assertSame('0197654321', $provenderie->phone);
        $this->assertSame('Route de Kétou', $provenderie->address);
        $this->assertTrue($provenderie->is_active);
        $this->assertSame('Produits vétérinaires', Supplier::where('name', 'Pharmacie vétérinaire Dossou')->value('category'), 'La catégorie est celle de la liste, pas la saisie.');
        $this->assertNull(Supplier::where('name', 'Pharmacie vétérinaire Dossou')->value('address'));
        $this->assertSame(2, AuditLog::where('action', 'supplier.created')->count());
        $this->assertSame(1, AuditLog::where('action', 'import.masse')->where('module', 'achats')->count());
    }

    public function test_les_lignes_erronees_sont_refusees_avec_les_motifs_du_service(): void
    {
        $user = $this->utilisateur(['manage-achats']);

        $lot = $this->analyser('fournisseurs', [
            $this->ligne(['nom' => 'Sans téléphone', 'telephone' => '']),
            $this->ligne(['nom' => 'Catégorie ?', 'categorie' => 'Jardinage', 'telephone' => '0197000002']),
            $this->ligne(['nom' => 'Sans catégorie', 'categorie' => '', 'telephone' => '0197000003']),
            $this->ligne(['nom' => 'Téléphone trop long', 'telephone' => str_repeat('9', 31)]),
            $this->ligne(['nom' => 'Bon fournisseur', 'telephone' => '0197000005']),
        ], $user);

        $this->assertSame([1, 0, 4], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $motifs = collect($lot->lignes)->keyBy('ligne')->map(fn ($l) => $l['motif']);
        $this->assertSame('Feuille « Données », ligne 2, colonne « Téléphone * » : Le champ téléphone est obligatoire.', $motifs[2]);
        $this->assertSame('Feuille « Données », ligne 3, colonne « Catégorie * » : Catégorie inconnue : « Jardinage ». Choisissez une valeur de la liste déroulante.', $motifs[3]);
        $this->assertSame('Feuille « Données », ligne 4, colonne « Catégorie * » : Le champ catégorie est obligatoire.', $motifs[4]);
        $this->assertSame('Feuille « Données », ligne 5, colonne « Téléphone * » : Le champ téléphone ne doit pas dépasser 30 caractères.', $motifs[5]);

        $this->assertSame(1, $this->service()->importer($lot, $user)->creees);
    }

    public function test_doublon_dans_le_fichier_et_doublon_en_base(): void
    {
        $user = $this->utilisateur(['manage-achats']);
        $existant = Supplier::create(['name' => 'Quincaillerie Centrale', 'category' => 'Matériel', 'phone' => '+22997112233', 'is_active' => true]);

        $lot = $this->analyser('fournisseurs', [
            $this->ligne(),
            $this->ligne(['nom' => 'PROVENDERIE du plateau', 'telephone' => '01 97 65 43 21']),
            $this->ligne(['nom' => 'quincaillerie centrale', 'categorie' => 'Autre', 'telephone' => '97112233']),
        ], $user);

        $this->assertSame([1, 1, 1], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $this->assertSame('Ligne 3 : doublon de la ligne 2.', $lot->lignes[1]['motif']);
        $this->assertSame('Ce fournisseur existe déjà (même nom, même téléphone) : ignoré, la fiche existante est gardée.', $lot->lignes[2]['motif']);

        $this->service()->importer($lot, $user);
        $this->assertSame('Matériel', $existant->fresh()->category, 'Jamais d\'écrasement.');
        $this->assertSame(2, Supplier::count());
    }

    public function test_un_reimport_ne_cree_aucun_doublon(): void
    {
        $user = $this->utilisateur(['manage-achats']);
        $lignes = [$this->ligne(), $this->ligne(['nom' => 'Second', 'telephone' => '0196000002'])];

        $this->service()->importer($this->analyser('fournisseurs', $lignes, $user), $user);
        $second = $this->analyser('fournisseurs', $lignes, $user);

        $this->assertSame([0, 2, 0], [$second->valides, $second->ignorees, $second->refusees]);
        $this->service()->importer($second, $user);
        $this->assertSame(2, Supplier::count());
    }

    public function test_les_droits_exigent_manage_achats(): void
    {
        $this->expectException(AuthorizationException::class);
        $this->analyser('fournisseurs', [$this->ligne()], $this->utilisateur(['manage-ventes', 'manage-stocks']));
    }
}
