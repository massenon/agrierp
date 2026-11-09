<?php

namespace App\Services\Import;

use App\Models\ChartOfAccount;
use App\Services\PlanComptableService;

/**
 * Ticket IMPORT-3 — MODULE « PLAN COMPTABLE » (comptes COMPLÉMENTAIRES : le SYSCOHADA de base est semé).
 *
 * Point de passage UNIQUE : `PlanComptableService::creer` ; règles : `PlanComptableService::regles()`, mot pour mot, à UNE
 * exception documentée : la règle `unique` du numéro n'est pas appliquée à l'aperçu — création SEULE oblige, un numéro déjà
 * au plan est IGNORÉ (« déjà présent »), pas refusé. Droit : `manage-comptabilite`.
 *
 * Aucune écriture comptable n'est passée : l'exercice clos ne bloque donc pas cet import (créer un compte n'écrit pas dans un
 * exercice). Clé de ligne : numéro de compte sans espace, en minuscules.
 */
class ImportPlanComptableService extends ModuleImport
{
    public const EMPREINTE_V1 = 'ed50d17855d3f547d6ca54c20f1c4064740e81e8dae4ce11b93241124f3cca4d';

    private const CHAMPS = ['code' => 'numero', 'label' => 'libelle', 'class' => 'classe'];

    /** @var array<string, true>|null */
    private ?array $index = null;

    public function cle(): string
    {
        return 'plan_comptable';
    }

    public function libelle(): string
    {
        return 'Plan comptable';
    }

    public function description(): string
    {
        return 'Comptes complémentaires du plan comptable : numéro, intitulé et classe.';
    }

    public function icone(): string
    {
        return 'menu_book';
    }

    public function permission(): string
    {
        return 'manage-comptabilite';
    }

    public function moduleAudit(): string
    {
        return 'comptabilite';
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
            new ColonneImport('numero', 'Numéro de compte', true, 'code', '20 caractères au plus (exemple : 6051).'),
            new ColonneImport('libelle', 'Intitulé', true, 'texte', '255 caractères au plus.'),
            new ColonneImport('classe', 'Classe', true, 'liste', 'Une classe de la liste déroulante, ou son chiffre (1 à 9).', 'classes'),
        ];
    }

    public function listes(): array
    {
        return ['classes' => array_values(PlanComptableService::LIBELLES_CLASSE)];
    }

    public function exemples(): array
    {
        return [
            ['numero' => '60511', 'libelle' => 'Achats de provende', 'classe' => '6 - Charges'],
            ['numero' => '70131', 'libelle' => 'Ventes de lapins', 'classe' => '7'],
        ];
    }

    public function notes(): array
    {
        return [
            'Un numéro de compte déjà présent au plan comptable (actif ou archivé) est IGNORÉ ; le compte existant n\'est jamais modifié.',
            'Importez des comptes COMPLÉMENTAIRES : le plan SYSCOHADA de base est déjà installé. Aucune écriture comptable n\'est passée.',
        ];
    }

    protected function attributs(): array
    {
        return ['numero' => 'code', 'libelle' => 'libellé', 'classe' => 'classe'];
    }

    public function designation(array $brut): string
    {
        return trim(LectureValeurs::texte($brut['numero'] ?? null).' — '.LectureValeurs::texte($brut['libelle'] ?? null), ' —');
    }

    public function valider(array $brut): array
    {
        $erreurs = [];

        $texteClasse = LectureValeurs::texte($brut['classe'] ?? null);
        $classe = $texteClasse;
        foreach (PlanComptableService::LIBELLES_CLASSE as $chiffre => $libelle) {
            if ($texteClasse !== '' && LectureValeurs::cle($libelle) === LectureValeurs::cle($texteClasse)) {
                $classe = (string) $chiffre;
            }
        }

        $donnees = [
            'code' => LectureValeurs::texte($brut['numero'] ?? null),
            'label' => LectureValeurs::texte($brut['libelle'] ?? null),
            'class' => $classe,
        ];

        // Création seule : la règle `unique` du numéro devient « déjà présent » (voir `dejaPresente`).
        $regles = array_map(
            fn (array $regle) => array_values(array_filter($regle, fn (string $r) => ! str_starts_with($r, 'unique:'))),
            app(PlanComptableService::class)->regles(),
        );
        $this->appliquerRegles($donnees, $regles, [], self::CHAMPS, $erreurs);

        return ['valeurs' => $donnees, 'erreurs' => $erreurs];
    }

    public function cleLigne(array $valeurs): string
    {
        return self::cleDeCode((string) $valeurs['code']);
    }

    private static function cleDeCode(string $code): string
    {
        return mb_strtolower(LectureValeurs::sansEspaces($code));
    }

    public function dejaPresente(array $valeurs): ?string
    {
        if (ChartOfAccount::whereKey($this->idLigne($valeurs))->exists()) {
            return 'Ce compte a déjà été importé : ignoré.';
        }

        $this->index ??= $this->construireIndex();
        if (isset($this->index[$this->cleLigne($valeurs)])) {
            return 'Ce numéro de compte existe déjà au plan comptable : ignoré, le compte existant est gardé.';
        }

        return null;
    }

    public function ecrire(array $valeurs, string $id): void
    {
        app(PlanComptableService::class)->creer($valeurs, $id);
        $this->index ??= $this->construireIndex();
        $this->index[$this->cleLigne($valeurs)] = true;
    }

    /** @return array<string, true> tous les numéros du plan, archivés compris (la colonne est unique) */
    private function construireIndex(): array
    {
        $index = [];
        foreach (ChartOfAccount::query()->pluck('code') as $code) {
            $index[self::cleDeCode((string) $code)] = true;
        }

        return $index;
    }
}
