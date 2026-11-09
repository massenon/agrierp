<?php

namespace App\Services\Import;

use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Services\AccountingEntryService;
use App\Services\ProductCatalogService;
use App\Support\CategorieVolaille;
use App\Support\StadePondeuse;

/**
 * Ticket IMPORT-1 — MODULE « STOCKS » : des produits du catalogue AVEC leur stock initial.
 *
 * Point de passage UNIQUE : `ProductCatalogService::creer`, qui pose le stock initial par `AdjustStockAction` (mouvement
 * « Stock initial », daté de l'import, sans écriture comptable) — jamais un `stock_qty` écrit à la main (défaut S-T12).
 * Règles de validation : `ProductCatalogService::regles()` / `messages()`, mot pour mot ; le format du fichier ajoute
 * seulement : montants en FCFA ENTIERS, listes de valeurs.
 *
 * ⚠️⚠️ IDEMPOTENCE — un produit DÉJÀ AU CATALOGUE (même nom, catégorie, unité et filière : la clé de
 * `FusionReferentielsService`, ou le même identifiant déterministe d'un import précédent) est IGNORÉ et son STOCK INITIAL
 * N'EST PAS AJOUTÉ : deux déclarations du même article sont le même stock physique ; l'écart se corrige par un inventaire.
 * Le rapport le dit ligne par ligne.
 *
 * ⚠️ Le SKU n'est pas une colonne : il est ENGENDRÉ par le serveur (`Product::generateSku`), jamais lu d'un fichier.
 */
class ImportStocksService extends ModuleImport
{
    public const EMPREINTE_V1 = '89edb3fdc8347a341d96fb8642844c956cc95e596f7815fd329dc96251896157';

    public const MODE_FOURCHETTE = 'Fourchette';

    public const MODE_DEVIS = 'Sur devis';

    /** Unités proposées par la liste (comptage : jamais une unité de poids) ; les unités déjà au catalogue s'y ajoutent. */
    public const UNITES_PROPOSEES = ['u', 'sac', 'plateau', 'carton', 'botte', 'flacon', 'boîte'];

    /** champ du service → colonne du modèle */
    private const CHAMPS = [
        'name' => 'nom', 'category_id' => 'categorie', 'unit' => 'unite', 'species_id' => 'filiere',
        'pricing_mode' => 'mode_prix', 'price_min' => 'prix_min', 'price_max' => 'prix_max', 'tva_rate' => 'tva',
        'alert_threshold' => 'seuil', 'stock_qty' => 'stock_initial', 'categorie_effectif' => 'categorie_effectif',
        'description' => 'description',
    ];

    /** @var array<string, array<string, string>>|null */
    private ?array $memo = null;

    public function cle(): string
    {
        return 'stocks';
    }

    public function libelle(): string
    {
        return 'Stocks';
    }

    public function description(): string
    {
        return 'Produits du catalogue avec leur stock initial (un mouvement « Stock initial » par produit).';
    }

    public function icone(): string
    {
        return 'inventory_2';
    }

    public function permission(): string
    {
        return 'manage-stocks';
    }

    public function moduleAudit(): string
    {
        return 'stocks';
    }

    public function version(): int
    {
        return 1;
    }

    public function empreinteAttendue(): string
    {
        return self::EMPREINTE_V1;
    }

    public function colonnes(): array
    {
        return [
            new ColonneImport('nom', 'Nom', true, 'texte', '150 caractères au plus.'),
            new ColonneImport('categorie', 'Catégorie', true, 'liste', 'Une catégorie du catalogue (liste déroulante).', 'categories'),
            new ColonneImport('unite', 'Unité', true, 'liste', "20 caractères au plus ; une unité de comptage (u, sac, plateau…), jamais une unité de poids.", 'unites'),
            new ColonneImport('filiere', 'Filière', false, 'liste', "L'espèce d'élevage du produit (liste déroulante) ; vide si aucune.", 'filieres'),
            new ColonneImport('mode_prix', 'Mode de prix', true, 'liste', '« Fourchette » (prix min et max exigés) ou « Sur devis » (aucun prix).', 'modes_prix'),
            new ColonneImport('prix_min', 'Prix min (FCFA)', false, 'entier', 'Exigé en mode Fourchette.'),
            new ColonneImport('prix_max', 'Prix max (FCFA)', false, 'entier', 'Exigé en mode Fourchette ; supérieur ou égal au prix min.'),
            new ColonneImport('tva', 'TVA %', true, 'decimal', 'Entre 0 et 100.'),
            new ColonneImport('seuil', "Seuil d'alerte", true, 'decimal', '0 ou plus.'),
            new ColonneImport('stock_initial', 'Stock initial', true, 'decimal', '0 ou plus. Entre en stock par un mouvement « Stock initial » ; ignoré si le produit existe déjà.'),
            new ColonneImport('categorie_effectif', "Catégorie d'effectif", false, 'liste', "Produits de l'aviculture seulement (liste déroulante) ; vide ailleurs.", 'categories_effectif'),
            new ColonneImport('description', 'Description', false, 'texte', '2 000 caractères au plus.'),
        ];
    }

    protected function attributs(): array
    {
        return ['tva' => 'TVA', 'prix_min' => 'prix min', 'prix_max' => 'prix max'];
    }

    public function listes(): array
    {
        // Unités proposées + celles déjà au catalogue (un doublon de casse n'est pas ajouté).
        $unites = self::UNITES_PROPOSEES;
        foreach (Product::query()->distinct()->orderBy('unit')->pluck('unit') as $unite) {
            if ($unite !== null && $unite !== '' && ! in_array(mb_strtolower($unite), array_map('mb_strtolower', $unites), true)) {
                $unites[] = $unite;
            }
        }

        return [
            'categories' => ProductCategory::where('is_active', true)->orderBy('label')->pluck('label')->all(),
            'unites' => $unites,
            'filieres' => LivestockSpecies::enabled()->orderBy('label')->pluck('label')->all(),
            'modes_prix' => [self::MODE_FOURCHETTE, self::MODE_DEVIS],
            'categories_effectif' => array_values(array_merge(CategorieVolaille::LIBELLES, StadePondeuse::LIBELLES)),
        ];
    }

    public function exemples(): array
    {
        return [
            ['nom' => 'Poulet fermier (sujet vif)', 'categorie' => 'Aviculture', 'unite' => 'u', 'filiere' => 'Aviculture', 'mode_prix' => self::MODE_FOURCHETTE, 'prix_min' => '4000', 'prix_max' => '6500', 'tva' => '0', 'seuil' => '15', 'stock_initial' => '64', 'categorie_effectif' => '', 'description' => ''],
            ['nom' => 'Aliment ponte (sac 25 kg)', 'categorie' => 'Aviculture', 'unite' => 'sac', 'filiere' => '', 'mode_prix' => self::MODE_DEVIS, 'prix_min' => '', 'prix_max' => '', 'tva' => '18', 'seuil' => '10', 'stock_initial' => '8,5', 'categorie_effectif' => '', 'description' => 'Sac de 25 kg'],
        ];
    }

    public function notes(): array
    {
        return [
            "Un produit déjà au catalogue (même nom, catégorie, unité et filière) est IGNORÉ : son stock initial n'est PAS ajouté (deux déclarations du même article sont le même stock physique). Un écart se corrige par un inventaire.",
            'Le stock initial entre par un mouvement « Stock initial » daté du jour de l\'importation, sans écriture comptable. Un exercice clos refuse tout l\'import.',
            'Le SKU est attribué par le serveur : ne le saisissez pas. Le mode « Sur devis » ignore les prix saisis.',
            "Les valeurs de « Catégorie », « Filière » et « Catégorie d'effectif » se choisissent dans les listes déroulantes (feuille « Listes »).",
        ];
    }

    public function valider(array $brut): array
    {
        $erreurs = [];
        $v = [];

        // Listes lues UNE fois pour tout l'import (5 000 lignes ne les relisent pas 5 000 fois).
        $this->memo ??= [
            'categories' => $this->index(ProductCategory::where('is_active', true)->pluck('label', 'id')->all()),
            'filieres' => $this->index(LivestockSpecies::enabled()->pluck('label', 'id')->all()),
            'effectifs' => $this->indexEffectifs(),
        ];
        ['categories' => $categories, 'filieres' => $filieres, 'effectifs' => $effectifs] = $this->memo;

        $nom = LectureValeurs::texte($brut['nom'] ?? null);
        $unite = LectureValeurs::texte($brut['unite'] ?? null);
        $descr = LectureValeurs::texte($brut['description'] ?? null);

        // Catégorie : le libellé de la liste devient l'identifiant attendu par le service.
        $texteCategorie = LectureValeurs::texte($brut['categorie'] ?? null);
        $categorieId = $texteCategorie === '' ? '' : ($categories[LectureValeurs::cle($texteCategorie)] ?? null);
        if ($categorieId === null) {
            $erreurs['categorie'] = "Catégorie inconnue : « {$texteCategorie} ». Choisissez une valeur de la liste déroulante.";
            $categorieId = '';
        }

        $texteFiliere = LectureValeurs::texte($brut['filiere'] ?? null);
        $especeId = $texteFiliere === '' ? null : ($filieres[LectureValeurs::cle($texteFiliere)] ?? null);
        if ($texteFiliere !== '' && $especeId === null) {
            $erreurs['filiere'] = "Filière inconnue : « {$texteFiliere} ». Choisissez une valeur de la liste déroulante.";
        }

        $texteMode = LectureValeurs::texte($brut['mode_prix'] ?? null);
        $mode = match (LectureValeurs::cle($texteMode)) {
            'fourchette' => 'fourchette',
            'sur devis', 'quote' => 'quote',
            default => null,
        };
        if ($mode === null && $texteMode !== '') {
            $erreurs['mode_prix'] = "Mode de prix inconnu : « {$texteMode} ». Attendu : « Fourchette » ou « Sur devis ».";
        }

        // Montants : des FCFA ENTIERS (durcissement du FORMAT du fichier ; le web accepte `numeric`).
        $prix = [];
        foreach (['prix_min', 'prix_max'] as $colonne) {
            $texte = LectureValeurs::texte($brut[$colonne] ?? null);
            $prix[$colonne] = null;
            if ($texte === '') {
                continue;
            }
            $entier = LectureValeurs::entier($texte);
            if ($entier === null) {
                $erreurs[$colonne] = 'Montant invalide : un nombre entier de FCFA est attendu.';
            } else {
                $prix[$colonne] = $entier;
            }
        }

        $nombres = [];
        foreach (['tva', 'seuil', 'stock_initial'] as $colonne) {
            $texte = LectureValeurs::texte($brut[$colonne] ?? null);
            $nombres[$colonne] = null;
            if ($texte === '') {
                continue;
            }
            $nombre = LectureValeurs::decimal($texte);
            if ($nombre === null) {
                $erreurs[$colonne] = 'Nombre invalide : un nombre est attendu (virgule ou point).';
            } else {
                $nombres[$colonne] = $nombre;
            }
        }

        $texteEffectif = LectureValeurs::texte($brut['categorie_effectif'] ?? null);
        $effectif = $texteEffectif === '' ? '' : ($effectifs[LectureValeurs::cle($texteEffectif)] ?? $texteEffectif);

        $donnees = [
            'name' => $nom,
            'description' => $descr === '' ? null : $descr,
            'category_id' => $categorieId,
            'species_id' => $especeId,
            'unit' => $unite,
            'pricing_mode' => $mode ?? '',
            'price_min' => $prix['prix_min'],
            'price_max' => $prix['prix_max'],
            'tva_rate' => $nombres['tva'],
            'alert_threshold' => $nombres['seuil'],
            'stock_qty' => $nombres['stock_initial'],
            'categorie_effectif' => $effectif === '' ? null : $effectif,
        ];

        // Les règles du service, telles quelles : fourchette ⇒ les deux prix et max ≥ min, TVA 0–100, stock ≥ 0…
        $service = app(ProductCatalogService::class);
        $formatMin = isset($erreurs['prix_min']);
        $this->appliquerRegles($donnees, $service->regles($mode ?? '', true), $service->messages(), self::CHAMPS, $erreurs);
        // Un prix min illisible fausse la comparaison « max ≥ min » : le motif du format suffit, pas un second motif parasite.
        if ($formatMin && ($erreurs['prix_max'] ?? null) === $service->messages()['price_max.gte']) {
            unset($erreurs['prix_max']);
        }

        $v = $donnees;
        $v['categorie_libelle'] = $texteCategorie;
        $v['filiere_libelle'] = $texteFiliere;

        return ['valeurs' => $v, 'erreurs' => $erreurs];
    }

    public function cleLigne(array $valeurs): string
    {
        return LectureValeurs::cle((string) $valeurs['name'])
            .'|'.LectureValeurs::cle((string) ($valeurs['categorie_libelle'] ?? ''))
            .'|'.LectureValeurs::cle((string) $valeurs['unit'])
            .'|'.(LectureValeurs::cle((string) ($valeurs['filiere_libelle'] ?? '')) ?: '-');
    }

    public function dejaPresente(array $valeurs): ?string
    {
        $id = $this->idLigne($valeurs);
        if (Product::whereKey($id)->exists()) {
            return "Ce produit a déjà été importé : ignoré, le stock initial n'est pas ajouté.";
        }

        $sku = $this->ficheNaturelle('products', $this->donneesDeFusion($valeurs));
        if ($sku !== null) {
            return "Ce produit existe déjà au catalogue ({$sku}) : ignoré, le stock initial n'est pas ajouté.";
        }

        return null;
    }

    public function ecrire(array $valeurs, string $id): void
    {
        $donnees = $valeurs;
        unset($donnees['categorie_libelle'], $donnees['filiere_libelle']);

        $produit = app(ProductCatalogService::class)->creer($donnees, $id);
        $this->memoriserNaturelle('products', $this->donneesDeFusion($valeurs), (string) $produit->sku);
    }

    /** Un exercice CLOS qui couvre le jour de l'import refuse le stock initial (`AdjustStockAction`, R4) : tout l'import. */
    public function controlePrealable(): ?string
    {
        return app(AccountingEntryService::class)->refusExerciceClos(now()->format('Y-m-d'));
    }

    /** @param array<string, mixed> $valeurs @return array<string, mixed> */
    private function donneesDeFusion(array $valeurs): array
    {
        return [
            'name' => $valeurs['name'],
            'category_id' => $valeurs['category_id'],
            'unit' => $valeurs['unit'],
            'species_id' => $valeurs['species_id'],
        ];
    }

    /** @return array<string, string> clé de comparaison du libellé → clé de la catégorie d'effectif */
    private function indexEffectifs(): array
    {
        $effectifs = [];
        foreach (array_merge(CategorieVolaille::LIBELLES, StadePondeuse::LIBELLES) as $cle => $libelle) {
            $effectifs[LectureValeurs::cle($libelle)] = $cle;
        }

        return $effectifs;
    }

    /**
     * @param  array<string, string>  $libelleParId
     * @return array<string, string> clé de comparaison du libellé → identifiant (ou valeur)
     */
    private function index(array $libelleParId): array
    {
        $index = [];
        foreach ($libelleParId as $id => $libelle) {
            $index[LectureValeurs::cle((string) $libelle)] ??= (string) $id;
        }

        return $index;
    }
}
