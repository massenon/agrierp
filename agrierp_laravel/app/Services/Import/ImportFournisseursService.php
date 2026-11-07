<?php

namespace App\Services\Import;

use App\Models\Supplier;
use App\Services\FusionReferentielsService;
use App\Services\SupplierCatalogService;

/**
 * Ticket IMPORT-1 — MODULE « FOURNISSEURS ».
 *
 * Point de passage UNIQUE : `SupplierCatalogService::creer` ; règles : `SupplierCatalogService::regles()` (nom, catégorie et
 * téléphone obligatoires), mot pour mot. La catégorie se choisit dans la liste du formulaire
 * (`SupplierCatalogService::CATEGORIES`). Pas de colonne e-mail : le formulaire web « Nouveau Fournisseur » n'a pas ce champ et
 * le poste ne l'envoie pas (`_fournisseurEnJson`).
 *
 * IDEMPOTENCE — nom normalisé + téléphone normalisé (`FusionReferentielsService`) ; un fournisseur déjà là est IGNORÉ.
 */
class ImportFournisseursService extends ModuleImport
{
    public const EMPREINTE_V1 = '0000000000000000000000000000000000000000000000000000000000000000';

    private const CHAMPS = ['name' => 'nom', 'category' => 'categorie', 'phone' => 'telephone', 'address' => 'adresse'];

    public function cle(): string
    {
        return 'fournisseurs';
    }

    public function libelle(): string
    {
        return 'Fournisseurs';
    }

    public function description(): string
    {
        return 'Fiches fournisseurs : nom, catégorie, téléphone et adresse.';
    }

    public function icone(): string
    {
        return 'local_shipping';
    }

    public function permission(): string
    {
        return 'manage-achats';
    }

    public function moduleAudit(): string
    {
        return 'achats';
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
            new ColonneImport('categorie', 'Catégorie', true, 'liste', 'Une catégorie de la liste déroulante.', 'categories'),
            new ColonneImport('telephone', 'Téléphone', true, 'telephone', '30 caractères au plus. Format texte : le zéro initial est conservé.'),
            new ColonneImport('adresse', 'Adresse', false, 'texte', '255 caractères au plus.'),
        ];
    }

    public function listes(): array
    {
        return ['categories' => SupplierCatalogService::CATEGORIES];
    }

    public function exemples(): array
    {
        return [
            ['nom' => 'Provenderie du Plateau', 'categorie' => 'Aliments', 'telephone' => '0197654321', 'adresse' => 'Route de Kétou, Pobè'],
            ['nom' => 'Pharmacie vétérinaire Dossou', 'categorie' => 'Produits vétérinaires', 'telephone' => '0196112233', 'adresse' => ''],
        ];
    }

    public function notes(): array
    {
        return [
            'Un fournisseur dont le nom ET le téléphone (8 chiffres au moins) existent déjà est IGNORÉ ; la fiche existante n\'est jamais modifiée.',
            'Le téléphone est obligatoire. Écrivez-le comme du texte : les cellules du modèle sont déjà au format texte.',
        ];
    }

    public function valider(array $brut): array
    {
        $erreurs = [];

        $texteCategorie = LectureValeurs::texte($brut['categorie'] ?? null);
        $categorie = '';
        foreach (SupplierCatalogService::CATEGORIES as $propose) {
            if ($texteCategorie !== '' && LectureValeurs::cle($propose) === LectureValeurs::cle($texteCategorie)) {
                $categorie = $propose;
            }
        }
        if ($texteCategorie !== '' && $categorie === '') {
            $erreurs['categorie'] = "Catégorie inconnue : « {$texteCategorie} ». Choisissez une valeur de la liste déroulante.";
        }

        $adresse = LectureValeurs::texte($brut['adresse'] ?? null);
        $donnees = [
            'name' => LectureValeurs::texte($brut['nom'] ?? null),
            'category' => $categorie,
            'phone' => LectureValeurs::texte($brut['telephone'] ?? null),
            'address' => $adresse === '' ? null : $adresse,
        ];

        $service = app(SupplierCatalogService::class);
        $this->appliquerRegles($donnees, array_intersect_key($service->regles(), self::CHAMPS), [], self::CHAMPS, $erreurs);

        return ['valeurs' => $donnees, 'erreurs' => $erreurs];
    }

    public function cleLigne(array $valeurs): string
    {
        $fusion = app(FusionReferentielsService::class);
        $telephone = $fusion->normaliserTelephone($valeurs['phone'] ?? null) ?? (preg_replace('/\D+/', '', (string) ($valeurs['phone'] ?? '')) ?: '-');

        return LectureValeurs::cle((string) $valeurs['name']).'|'.$telephone;
    }

    public function dejaPresente(array $valeurs): ?string
    {
        $id = $this->idLigne($valeurs);
        if (Supplier::whereKey($id)->exists()) {
            return 'Ce fournisseur a déjà été importé : ignoré.';
        }

        if ($this->ficheNaturelle('suppliers', $valeurs) !== null) {
            return 'Ce fournisseur existe déjà (même nom, même téléphone) : ignoré, la fiche existante est gardée.';
        }

        return null;
    }

    public function ecrire(array $valeurs, string $id): void
    {
        app(SupplierCatalogService::class)->creer($valeurs, $id);
        $this->memoriserNaturelle('suppliers', $valeurs, $id);
    }
}
