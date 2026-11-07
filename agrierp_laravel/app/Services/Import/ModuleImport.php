<?php

namespace App\Services\Import;

use App\Services\FusionReferentielsService;
use Illuminate\Support\Facades\Validator;
use Ramsey\Uuid\Uuid;

/**
 * Ticket IMPORT-1 — CONTRAT D'UN MODULE IMPORTABLE (registre extensible : `ImportMasseService::REGISTRE`).
 *
 * ⚠️⚠️ UN MODULE N'AJOUTE AUCUNE RÈGLE MÉTIER. Il lit une ligne, la traduit dans le vocabulaire du point de passage unique
 * de l'écran (ProductCatalogService, CustomerCatalogService, SupplierCatalogService…), fait valider ces données par LES
 * RÈGLES DE CE SERVICE (`regles()`, `messages()`) et les écrit par SA fabrique (`creer`) — jamais un `INSERT` direct, jamais
 * un `stock_qty` écrit à la main. Les refus de l'import sont ceux du service, mot pour mot.
 *
 * Phases suivantes (non construites, voir `docs/PLAN_FINALISATION.md`, IMPORT-1) : employés (`SaisieEmployeAction`), plan
 * comptable (`PlanComptableService`), barème de rationnement (Paramètres Élevage). Ajouter un module = une classe qui étend
 * celle-ci + une ligne dans le registre + l'entrée de l'écran.
 */
abstract class ModuleImport
{
    /** Espace de noms des UUID v5 de l'importation (fixe : le poste a la même constante). */
    public const ESPACE_UUID = 'b3b0e2c4-6f5e-5b7a-9a4d-2f1c7a1d0e51';

    abstract public function cle(): string;

    abstract public function libelle(): string;

    abstract public function description(): string;

    /** Icône Material Symbols de la carte. */
    abstract public function icone(): string;

    /** Droit `manage-…` exigé pour importer ce module (vérifié au serveur ET masqué à l'écran). */
    abstract public function permission(): string;

    /** Module de l'audit (`AuditLog::record('import.masse', <module>)`). */
    abstract public function moduleAudit(): string;

    /** Version du modèle : augmente à tout changement de colonne. */
    abstract public function version(): int;

    /** Empreinte SHA-256 attendue des en-têtes de la version courante (garde `ImportMasseModelesTest`). */
    abstract public function empreinteAttendue(): string;

    /** @return array<int, ColonneImport> */
    abstract public function colonnes(): array;

    /**
     * Listes déroulantes du modèle (nom de liste → valeurs), lues en base au moment de la génération.
     *
     * @return array<string, array<int, string>>
     */
    public function listes(): array
    {
        return [];
    }

    /**
     * Lignes d'exemple de la feuille « Instructions » (jamais dans « Données » : aucune ne s'importerait par erreur).
     *
     * @return array<int, array<string, string>> clé de colonne → texte
     */
    abstract public function exemples(): array;

    /** Notes ajoutées à la feuille « Instructions » (règles propres au module : idempotence, stock…). @return array<int, string> */
    public function notes(): array
    {
        return [];
    }

    /**
     * Traduit les valeurs lues d'UNE ligne et les fait valider par les règles du service.
     *
     * @param  array<string, string>  $brut  clé de colonne → texte de la cellule
     * @return array{valeurs: array<string, mixed>, erreurs: array<string, string>}  `erreurs` : clé de colonne → motif
     */
    abstract public function valider(array $brut): array;

    /** Texte qui désigne la ligne dans l'aperçu et le rapport (le nom). @param array<string, string> $brut */
    public function designation(array $brut): string
    {
        return (string) ($brut['nom'] ?? '');
    }

    /** Clé naturelle NORMALISÉE d'une ligne valide (doublon dans le fichier, UUID v5). @param array<string, mixed> $valeurs */
    abstract public function cleLigne(array $valeurs): string;

    /**
     * Le motif « déjà présente » si la fiche existe déjà (même identifiant déterministe, ou même clé naturelle que
     * `FusionReferentielsService`), `null` sinon. Une ligne déjà présente est IGNORÉE, jamais mise à jour.
     *
     * @param  array<string, mixed>  $valeurs
     */
    abstract public function dejaPresente(array $valeurs): ?string;

    /**
     * Écrit UNE ligne valide par le point de passage unique. Lève l'exception du service (exercice clos, contrainte…) :
     * l'orchestrateur la transforme en refus avec son motif.
     *
     * @param  array<string, mixed>  $valeurs
     */
    abstract public function ecrire(array $valeurs, string $id): void;

    /** Motif qui interdit TOUT l'import (exercice clos…), vérifié à l'aperçu ET avant d'écrire ; `null` sinon. */
    public function controlePrealable(): ?string
    {
        return null;
    }

    /** Empreinte des en-têtes réels : change dès qu'une colonne bouge. */
    public function empreinte(): string
    {
        return hash('sha256', implode('|', array_map(fn (ColonneImport $c) => $c->entete(), $this->colonnes())));
    }

    /** UUID v5 DÉTERMINISTE d'une ligne : relire le même fichier produit les mêmes identifiants. @param array<string, mixed> $valeurs */
    public function idLigne(array $valeurs): string
    {
        return Uuid::uuid5(self::ESPACE_UUID, $this->cle().'|'.$this->cleLigne($valeurs))->toString();
    }

    /** @var array<string, array<string, string>> table → (clé naturelle → désignation de la fiche déjà là) */
    private array $indexNaturel = [];

    /**
     * La fiche ACTIVE déjà là de même clé naturelle (`FusionReferentielsService::cleNaturelle`, SEUL juge de « le même »),
     * ou `null`. L'index de la table est lu UNE fois pour tout l'import (5 000 lignes ne relisent pas 5 000 fois le catalogue) ;
     * [memoriserNaturelle] y ajoute chaque fiche écrite.
     *
     * @param  array<string, mixed>  $donnees
     * @return string|null SKU (produit) ou identifiant de la fiche trouvée
     */
    protected function ficheNaturelle(string $table, array $donnees): ?string
    {
        $cle = app(FusionReferentielsService::class)->cleNaturelle($table, $donnees);
        if ($cle === null) {
            return null;
        }

        $this->indexNaturel[$table] ??= $this->construireIndex($table);

        return $this->indexNaturel[$table][$cle] ?? null;
    }

    /** @param array<string, mixed> $donnees */
    protected function memoriserNaturelle(string $table, array $donnees, string $designation): void
    {
        $cle = app(FusionReferentielsService::class)->cleNaturelle($table, $donnees);
        if ($cle !== null) {
            $this->indexNaturel[$table] ??= $this->construireIndex($table);
            $this->indexNaturel[$table][$cle] ??= $designation;
        }
    }

    /** @return array<string, string> */
    private function construireIndex(string $table): array
    {
        $fusion = app(FusionReferentielsService::class);
        $modele = FusionReferentielsService::MODELES[$table];
        $requete = $modele::query()->where('is_active', true);
        if ($table !== 'products') {
            $requete->whereNotNull('phone');
        }

        $index = [];
        foreach ($requete->orderBy('created_at')->orderBy('id')->get() as $fiche) {
            $cle = $fusion->cleNaturelle($table, $fiche->getAttributes());
            if ($cle !== null) {
                $index[$cle] ??= (string) ($fiche->sku ?? $fiche->getKey());
            }
        }

        return $index;
    }

    /**
     * Nom de la colonne DANS LES MESSAGES des règles (« Le champ TVA ne doit pas dépasser 100. ») quand le libellé en minuscules
     * ne se lit pas bien. Le poste reprend ces noms (`importation_repository.dart`).
     *
     * @return array<string, string> clé de colonne → nom
     */
    protected function attributs(): array
    {
        return [];
    }

    /** Colonne par clé. */
    public function colonne(string $cle): ColonneImport
    {
        foreach ($this->colonnes() as $c) {
            if ($c->cle === $cle) {
                return $c;
            }
        }

        throw new \InvalidArgumentException("Colonne inconnue : {$cle}.");
    }

    /**
     * Fait passer [$donnees] par les règles du service ; chaque refus est rattaché à sa colonne (`$champVersColonne`),
     * le premier motif par colonne, sans écraser un motif déjà posé (format de cellule).
     *
     * @param  array<string, mixed>  $donnees
     * @param  array<string, array<int, mixed>>  $regles
     * @param  array<string, string>  $messages
     * @param  array<string, string>  $champVersColonne  champ du service → clé de colonne
     * @param  array<string, string>  $erreurs  motifs déjà posés (modifié)
     */
    protected function appliquerRegles(array $donnees, array $regles, array $messages, array $champVersColonne, array &$erreurs): void
    {
        $attributs = [];
        foreach ($champVersColonne as $champ => $colonne) {
            $attributs[$champ] = $this->attributs()[$colonne] ?? mb_strtolower($this->colonne($colonne)->libelle);
        }

        $validateur = Validator::make($donnees, $regles, $messages, $attributs);
        if (! $validateur->fails()) {
            return;
        }

        foreach ($validateur->errors()->messages() as $champ => $motifs) {
            $colonne = $champVersColonne[$champ] ?? $champ;
            $erreurs[$colonne] ??= $motifs[0];
        }
    }
}
