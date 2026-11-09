<?php

namespace Tests\Feature;

use App\Livewire\Stocks\ImportationMasse;
use App\Models\AuditLog;
use App\Models\FiscalYear;
use App\Models\ImportBatch;
use App\Models\Product;
use App\Models\StockMovement;
use App\Services\Import\ImportRefuse;
use Illuminate\Auth\Access\AuthorizationException;
use Livewire\Livewire;
use Livewire\Features\SupportFileUploads\TemporaryUploadedFile;

/**
 * Ticket IMPORT-1 — l'importation en masse des STOCKS (produits avec stock initial).
 *
 * Valeurs littérales, calculées à la main : 3 produits valides → 3 produits, 3 mouvements « Stock initial » de 12, 8,5 et 0
 * (le zéro n'en produit aucun), jamais un `stock_qty` écrit sans son mouvement.
 */
class ImportMasseStocksTest extends ImportMasseBase
{
    private function ligne(array $remplace = []): array
    {
        return array_merge([
            'nom' => 'Poulet fermier', 'categorie' => 'Aviculture', 'unite' => 'u', 'filiere' => 'Aviculture',
            'mode_prix' => 'Fourchette', 'prix_min' => 3000, 'prix_max' => 4000, 'tva' => 0, 'seuil' => 5,
            'stock_initial' => 12,
        ], $remplace);
    }

    public function test_un_fichier_valide_cree_les_produits_et_leurs_mouvements_de_stock_initial(): void
    {
        $user = $this->utilisateur(['manage-stocks']);

        $lot = $this->analyser('stocks', [
            $this->ligne(),
            $this->ligne(['nom' => 'Aliment ponte', 'unite' => 'sac', 'filiere' => '', 'mode_prix' => 'Sur devis', 'prix_min' => '', 'prix_max' => '', 'tva' => 18, 'seuil' => 10, 'stock_initial' => '8,5']),
            $this->ligne(['nom' => 'Plateau vide', 'categorie' => 'Équipements', 'unite' => 'plateau', 'filiere' => '', 'stock_initial' => 0]),
        ], $user);

        $this->assertSame(3, $lot->lues);
        $this->assertSame(3, $lot->valides);
        $this->assertSame(0, $lot->refusees);
        $this->assertSame(0, Product::count(), "L'aperçu n'écrit RIEN.");

        $lot = $this->service()->importer($lot, $user);

        $this->assertSame('termine', $lot->statut);
        $this->assertSame(3, $lot->creees);
        $this->assertSame(3, Product::count());

        $poulet = Product::where('name', 'Poulet fermier')->firstOrFail();
        $this->assertEquals(12, $poulet->stock_qty);
        $this->assertEquals(3000, $poulet->price_min);
        $this->assertEquals(4000, $poulet->price_max);
        $this->assertEquals(5, $poulet->alert_threshold);
        $this->assertSame($this->espece->id, $poulet->species_id);
        $this->assertTrue($poulet->is_active);
        $this->assertMatchesRegularExpression('/^AVI-\d+$/', $poulet->sku, 'Le SKU est engendré par le serveur.');

        $aliment = Product::where('name', 'Aliment ponte')->firstOrFail();
        $this->assertEquals(8.5, $aliment->stock_qty);
        $this->assertSame('quote', $aliment->pricing_mode);
        $this->assertNull($aliment->price_min);
        $this->assertEquals(18, $aliment->tva_rate);

        // Le stock initial entre par un MOUVEMENT « Stock initial » (jamais un stock_qty sans son mouvement).
        $mouvements = StockMovement::orderBy('quantity')->get();
        $this->assertCount(2, $mouvements, 'Un stock initial de 0 ne produit aucun mouvement.');
        $this->assertSame([8.5, 12.0], $mouvements->map(fn ($m) => (float) $m->quantity)->all());
        $this->assertSame(['entree', 'entree'], $mouvements->pluck('type')->all());
        $this->assertSame(['Stock initial', 'Stock initial'], $mouvements->pluck('reason')->all());
        foreach (Product::all() as $produit) {
            $this->assertEqualsWithDelta((float) $produit->stock_qty, (float) StockMovement::where('product_id', $produit->id)->sum('quantity'), 0.0001, 'stock_qty = grand livre des mouvements');
        }
    }

    public function test_l_audit_est_une_ligne_par_fichier_et_chaque_produit_garde_le_sien(): void
    {
        $user = $this->utilisateur(['manage-stocks']);
        $lot = $this->analyser('stocks', [$this->ligne(), $this->ligne(['nom' => 'Autre produit'])], $user);
        $this->service()->importer($lot, $user);

        $this->assertSame(1, AuditLog::where('action', 'import.masse')->count());
        $audit = AuditLog::where('action', 'import.masse')->first();
        $this->assertSame('stocks', $audit->module);
        $this->assertSame($lot->id, $audit->entity_id);
        $this->assertSame(2, AuditLog::where('action', 'product.created')->count());
    }

    public function test_une_ligne_erronee_est_refusee_avec_feuille_ligne_colonne_et_les_autres_entrent(): void
    {
        $user = $this->utilisateur(['manage-stocks']);

        $lot = $this->analyser('stocks', [
            $this->ligne(),                                                   // ligne 2 : valide
            $this->ligne(['nom' => 'Prix décimal', 'prix_min' => '3000,50']), // ligne 3
            $this->ligne(['nom' => 'TVA folle', 'tva' => 120]),               // ligne 4
            $this->ligne(['nom' => 'Max < min', 'prix_min' => 5000, 'prix_max' => 4000]), // ligne 5
            $this->ligne(['nom' => 'Catégorie ?', 'categorie' => 'Inconnue']), // ligne 6
            $this->ligne(['nom' => '', 'stock_initial' => '']),                // ligne 7
            $this->ligne(['nom' => 'Stock négatif', 'stock_initial' => -3]),   // ligne 8
            $this->ligne(['nom' => 'Mode ?', 'mode_prix' => 'Gratuit']),       // ligne 9
            $this->ligne(['nom' => 'Sans prix', 'prix_min' => '', 'prix_max' => '']), // ligne 10 : fourchette sans prix
        ], $user);

        $this->assertSame(9, $lot->lues);
        $this->assertSame(1, $lot->valides);
        $this->assertSame(8, $lot->refusees);

        $motifs = collect($lot->lignes)->keyBy('ligne')->map(fn ($l) => $l['motif']);
        $this->assertSame('Feuille « Données », ligne 3, colonne « Prix min (FCFA) » : Montant invalide : un nombre entier de FCFA est attendu.', $motifs[3]);
        $this->assertSame('Feuille « Données », ligne 4, colonne « TVA % * » : Le champ TVA ne doit pas dépasser 100.', $motifs[4]);
        $this->assertSame('Feuille « Données », ligne 5, colonne « Prix max (FCFA) » : Le prix maximum doit être supérieur ou égal au prix minimum.', $motifs[5]);
        $this->assertSame("Feuille « Données », ligne 6, colonne « Catégorie * » : Catégorie inconnue : « Inconnue ». Choisissez une valeur de la liste déroulante.", $motifs[6]);
        $this->assertStringContainsString('colonne « Nom * » : Le champ nom est obligatoire.', $motifs[7]);
        $this->assertStringContainsString('colonne « Stock initial * » : Le champ stock initial est obligatoire.', $motifs[7]);
        $this->assertStringContainsString('colonne « Stock initial * » : Le champ stock initial doit être au moins égal à 0.', $motifs[8]);
        $this->assertStringContainsString('colonne « Mode de prix * » : Mode de prix inconnu : « Gratuit ».', $motifs[9]);
        $this->assertStringContainsString('colonne « Prix min (FCFA) » : Le champ prix min est obligatoire.', $motifs[10]);

        $lot = $this->service()->importer($lot, $user);
        $this->assertSame(1, $lot->creees);
        $this->assertSame(8, $lot->refusees);
        $this->assertSame(1, Product::count());
    }

    public function test_un_doublon_dans_le_fichier_est_refuse_a_l_apercu(): void
    {
        $user = $this->utilisateur(['manage-stocks']);

        $lot = $this->analyser('stocks', [
            $this->ligne(),
            $this->ligne(['nom' => 'Autre']),
            $this->ligne(['nom' => '  poulet FERMIER ', 'prix_min' => 1, 'prix_max' => 2]), // même clé : nom normalisé
        ], $user);

        $this->assertSame(2, $lot->valides);
        $this->assertSame(1, $lot->refusees);
        $troisieme = $lot->lignes[2];
        $this->assertSame(4, $troisieme['ligne']);
        $this->assertTrue($troisieme['doublon']);
        $this->assertSame('Ligne 4 : doublon de la ligne 2.', $troisieme['motif']);
    }

    public function test_un_produit_deja_au_catalogue_est_ignore_et_son_stock_n_est_pas_ajoute(): void
    {
        $user = $this->utilisateur(['manage-stocks']);
        $existant = Product::create([
            'sku' => 'AVI-001', 'name' => 'Poulet fermier', 'category_id' => $this->categorie->id, 'species_id' => $this->espece->id,
            'unit' => 'U', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => 7, 'is_active' => true,
        ]);

        $lot = $this->analyser('stocks', [$this->ligne(['stock_initial' => 100]), $this->ligne(['nom' => 'Nouveau', 'stock_initial' => 4])], $user);

        $this->assertSame(1, $lot->ignorees);
        $this->assertSame(1, $lot->valides);
        $this->assertStringContainsString('existe déjà au catalogue (AVI-001) : ignoré, le stock initial n\'est pas ajouté', $lot->lignes[0]['motif']);

        $this->service()->importer($lot, $user);

        $this->assertEquals(7, $existant->fresh()->stock_qty, 'Le stock du produit existant ne bouge pas.');
        $this->assertSame(0, StockMovement::where('product_id', $existant->id)->count());
        $this->assertSame(2, Product::count());
    }

    public function test_un_reimport_du_meme_fichier_ne_cree_rien_et_avertit(): void
    {
        $user = $this->utilisateur(['manage-stocks']);
        $lignes = [$this->ligne(), $this->ligne(['nom' => 'Second', 'stock_initial' => 3])];

        $premier = $this->service()->importer($this->analyser('stocks', $lignes, $user), $user);
        $this->assertSame(2, $premier->creees);

        $chemin = $this->fichier(\App\Services\Import\ImportMasseService::module('stocks'), $lignes);
        $second = $this->service()->analyser('stocks', $chemin, 'import.xlsx', $user);
        $this->assertSame(2, $second->ignorees);
        $this->assertSame(0, $second->valides);

        // Le MÊME fichier (mêmes octets) : l'avertissement « déjà importé » apparaît, sans bloquer.
        $troisieme = $this->service()->analyser('stocks', $chemin, 'import.xlsx', $user);
        $this->assertSame(0, $troisieme->valides);

        $this->service()->importer($second, $user);
        $this->assertSame(2, Product::count(), 'Aucun doublon.');
        $this->assertSame(2, StockMovement::count(), 'Aucun stock initial ajouté une seconde fois.');
    }

    public function test_l_avertissement_deja_importe_nomme_la_date_et_l_auteur(): void
    {
        $user = $this->utilisateur(['manage-stocks'], 'Awa');
        $chemin = $this->fichier(\App\Services\Import\ImportMasseService::module('stocks'), [$this->ligne()]);

        $this->service()->importer($this->service()->analyser('stocks', $chemin, 'import.xlsx', $user), $user);
        $lot = $this->service()->analyser('stocks', $chemin, 'import.xlsx', $user);

        $this->assertStringContainsString('Ce fichier a déjà été importé le '.now()->format('d/m/Y'), $lot->avertissement);
        $this->assertStringContainsString('par Awa', $lot->avertissement);
    }

    public function test_un_exercice_clos_refuse_tout_l_import_avant_la_confirmation(): void
    {
        $user = $this->utilisateur(['manage-stocks']);
        FiscalYear::query()->update(['status' => 'cloture']);

        $lot = $this->analyser('stocks', [$this->ligne()], $user);
        $this->assertNotNull($lot->rapport['bloquant']);
        $this->assertStringContainsString('clôturé', $lot->rapport['bloquant']);

        try {
            $this->service()->importer($lot, $user);
            $this->fail('Un exercice clos doit refuser l\'import.');
        } catch (ImportRefuse $e) {
            $this->assertSame($lot->rapport['bloquant'], $e->getMessage());
        }

        $this->assertSame(0, Product::count());
        $this->assertSame(0, StockMovement::count());
    }

    public function test_les_droits_sont_verifies_au_serveur(): void
    {
        $sans = $this->utilisateur(['manage-ventes'], 'Caissier');
        $this->expectException(AuthorizationException::class);

        try {
            $this->analyser('stocks', [$this->ligne()], $sans);
        } finally {
            $this->assertSame(0, ImportBatch::count());
        }
    }

    public function test_confirmer_deux_fois_n_ecrit_qu_une_fois(): void
    {
        $user = $this->utilisateur(['manage-stocks']);
        $lot = $this->analyser('stocks', [$this->ligne()], $user);
        $this->service()->importer($lot, $user);

        $this->expectException(ImportRefuse::class);
        try {
            $this->service()->importer($lot->fresh(), $user);
        } finally {
            $this->assertSame(1, Product::count());
        }
    }

    public function test_l_aperçu_d_un_autre_utilisateur_ne_se_confirme_pas(): void
    {
        $a = $this->utilisateur(['manage-stocks'], 'Alpha');
        $b = $this->utilisateur(['manage-stocks'], 'Beta');
        $lot = $this->analyser('stocks', [$this->ligne()], $a);

        $this->expectException(ImportRefuse::class);
        $this->service()->importer($lot, $b);
    }

    public function test_une_fiche_creee_entre_l_apercu_et_la_confirmation_est_ignoree(): void
    {
        $user = $this->utilisateur(['manage-stocks']);
        $lot = $this->analyser('stocks', [$this->ligne()], $user);

        Product::create([
            'sku' => 'AVI-009', 'name' => 'Poulet fermier', 'category_id' => $this->categorie->id, 'species_id' => $this->espece->id,
            'unit' => 'u', 'pricing_mode' => 'quote', 'stock_qty' => 0, 'is_active' => true,
        ]);

        $lot = $this->service()->importer($lot, $user);
        $this->assertSame(0, $lot->creees);
        $this->assertSame(1, $lot->ignorees);
        $this->assertSame(1, Product::count());
    }

    public function test_le_rapport_xlsx_liste_chaque_ligne_et_les_valeurs_des_refusees(): void
    {
        $user = $this->utilisateur(['manage-stocks']);
        $lot = $this->analyser('stocks', [$this->ligne(), $this->ligne(['nom' => 'Mauvais', 'tva' => 500])], $user);
        $lot = $this->service()->importer($lot, $user);

        $chemin = $this->service()->rapportXlsx($lot);
        $classeur = \PhpOffice\PhpSpreadsheet\IOFactory::load($chemin);
        @unlink($chemin);

        $rapport = $classeur->getSheetByName('Rapport')->toArray();
        $this->assertSame(['Ligne', 'Désignation', 'Résultat', 'Motif'], $rapport[0]);
        $this->assertSame(['2', 'Poulet fermier', 'Créée', null], $rapport[1]);
        $this->assertSame('3', $rapport[2][0]);
        $this->assertSame('Refusée', $rapport[2][2]);
        $this->assertStringContainsString('colonne « TVA % * »', $rapport[2][3]);

        $refusees = $classeur->getSheetByName('Lignes refusées')->toArray();
        $this->assertSame('3', $refusees[1][0]);
        $this->assertSame('Mauvais', $refusees[1][2]);
        $this->assertSame('500', $refusees[1][9], 'La valeur fautive est rendue pour être corrigée.');
        $this->assertCount(2, $refusees, "Seule la ligne refusée est listée.");

        // Les valeurs des fiches créées ne restent pas au journal.
        $this->assertNull($lot->lignes[0]['brut']);
        $this->assertNotNull($lot->lignes[1]['brut']);
    }

    public function test_l_ecran_conduit_les_six_etapes_et_ecrit_par_la_confirmation(): void
    {
        $user = $this->utilisateur(['manage-stocks']);
        $chemin = $this->fichier(\App\Services\Import\ImportMasseService::module('stocks'), [$this->ligne(), $this->ligne(['nom' => 'Cassé', 'tva' => 900])]);

        $ecran = Livewire::actingAs($user)->test(ImportationMasse::class)
            ->assertSee('Importation en masse')
            ->assertSee('Stocks')
            ->assertDontSee('Fournisseurs')
            ->assertSet('etape', 1)
            ->call('choisirModule', 'stocks')
            ->assertSet('etape', 2)
            ->assertSee('Télécharger le modèle')
            ->call('versEtape', 3)
            ->assertSet('etape', 3);

        $ecran->set('fichier', \Illuminate\Http\UploadedFile::fake()->createWithContent('stocks.xlsx', file_get_contents($chemin)))
            ->assertSet('etape', 4)
            ->assertSee('Aperçu')
            ->assertSee('Importer 1 ligne')
            ->assertSee('Feuille « Données », ligne 3, colonne « TVA % * »')
            ->assertSee('Refusées seulement');
        $this->assertSame(0, Product::count());

        $ecran->call('confirmer')
            ->assertSet('etape', 6)
            ->assertSee("Rapport d'importation", false)
            ->assertSee('Créées')
            ->assertSee('Télécharger le rapport')
            ->assertSee('Corriger le fichier puis ré-importer');
        $this->assertSame(1, Product::count());

        $ecran->call('telechargerRapport')->assertFileDownloaded();
    }

    public function test_un_module_non_autorise_est_refuse_par_l_ecran(): void
    {
        $caissier = $this->utilisateur(['manage-ventes']);

        Livewire::actingAs($caissier)->test(ImportationMasse::class)
            ->assertSee('Clients')
            ->assertDontSee('Produits du catalogue avec leur stock initial')
            ->call('choisirModule', 'stocks')
            ->assertForbidden();
    }

    public function test_l_ecran_est_ferme_sans_aucun_droit_d_importation(): void
    {
        $this->withoutVite();
        $rien = $this->utilisateur(['view-stocks']);

        $this->actingAs($rien)->get('/importation-masse')->assertForbidden();
        $this->actingAs($this->utilisateur(['manage-achats']))->get('/importation-masse')->assertOk()->assertSee('Fournisseurs');
    }
}
