<?php

namespace App\Services\Import;

use App\Models\AuditLog;
use App\Models\ImportBatch;
use App\Models\User;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\Spreadsheet;

/**
 * Ticket IMPORT-1 — ORCHESTRATEUR DE L'IMPORTATION EN MASSE PAR TABLEUR xlsx (décision du client, 08/11/2026).
 *
 * Étapes : [analyser] (lecture du fichier, validation LIGNE PAR LIGNE, AUCUNE écriture : valides / ignorées (déjà présentes)
 * / refusées, doublons du fichier compris) → [importer] (confirmation : écriture ligne par ligne, une transaction par ligne,
 * par le point de passage unique du module) → [rapportXlsx].
 *
 * ⚠️⚠️ CE SERVICE N'ÉCRIT RIEN LUI-MÊME dans le métier : chaque ligne passe par `ModuleImport::ecrire`, donc par la fabrique
 * que l'écran et la synchronisation utilisent (`ProductCatalogService::creer` → `AdjustStockAction`, `CustomerCatalogService`,
 * `SupplierCatalogService`). Les droits (`manage-stocks` / `manage-ventes` / `manage-achats`) sont vérifiés ICI, au serveur,
 * à chaque appel ; l'écran masque en plus les modules refusés. Une ligne `import.masse` est tracée par fichier (module,
 * compteurs dans le journal `import_batches`, jamais le contenu).
 *
 * Écriture : « validation INTÉGRALE avant toute écriture, puis ligne par ligne, une transaction par ligne, les refusées exclues et
 * listées, jamais de demi-ligne » (guide logialvia, bloc 21 §6). Chaque ligne est REVALIDÉE au moment d'être écrite
 * (une fiche créée entre l'aperçu et la confirmation la fait passer en « ignorée »).
 *
 * Registre extensible : ajouter un module = une classe `ModuleImport` + une ligne de [REGISTRE]. Phases suivantes, non
 * construites : employés, plan comptable, barème de rationnement.
 */
class ImportMasseService
{
    /** @var array<string, class-string<ModuleImport>> */
    public const REGISTRE = [
        'stocks' => ImportStocksService::class,
        'clients' => ImportClientsService::class,
        'fournisseurs' => ImportFournisseursService::class,
    ];

    public const STATUT_VALIDE = 'valide';

    public const STATUT_IGNOREE = 'ignoree';

    public const STATUT_REFUSEE = 'refusee';

    public const STATUT_CREEE = 'creee';

    public static function module(string $cle): ?ModuleImport
    {
        $classe = self::REGISTRE[$cle] ?? null;

        return $classe ? new $classe() : null;
    }

    /** @return array<string, ModuleImport> */
    public static function modules(): array
    {
        return array_map(fn (string $classe) => new $classe(), self::REGISTRE);
    }

    /**
     * Les modules que [$user] a le droit d'importer (les autres sont absents de l'écran ET refusés ici).
     *
     * @return array<string, ModuleImport>
     */
    public function modulesAutorises(?User $user): array
    {
        return array_filter(self::modules(), fn (ModuleImport $m) => $user !== null && $user->can($m->permission()));
    }

    /** @throws ImportRefuse|AuthorizationException */
    public function moduleAutorise(string $cle, ?User $user): ModuleImport
    {
        $module = self::module($cle);
        if ($module === null) {
            throw new ImportRefuse("Module d'importation inconnu : « {$cle} ».");
        }
        if ($user === null || ! $user->can($module->permission())) {
            throw new AuthorizationException("Vous n'avez pas le droit d'importer le module « {$module->libelle()} ».");
        }

        return $module;
    }

    /**
     * Lit et VALIDE le fichier, sans rien écrire dans le métier ; garde l'aperçu au journal (`apercu`).
     *
     * @throws ImportRefuse  le fichier entier est refusé (message de l'écran)
     * @throws AuthorizationException
     */
    public function analyser(string $cle, string $chemin, string $nomFichier, User $user): ImportBatch
    {
        $module = $this->moduleAutorise($cle, $user);

        if (strtolower(pathinfo($nomFichier, PATHINFO_EXTENSION)) !== 'xlsx') {
            throw new ImportRefuse('Seuls les fichiers Excel .xlsx sont acceptés : utilisez le modèle « '.$module->libelle().' » téléchargé à l\'étape 2.');
        }

        $lecture = app(LecteurXlsx::class)->lire($chemin, $module);
        $empreinte = hash_file('sha256', $chemin);

        $lignes = [];
        $premiere = []; // clé de ligne → numéro de la première ligne valide
        foreach ($lecture['lignes'] as $numero => $brut) {
            $entree = [
                'ligne' => $numero,
                'designation' => $module->designation($brut),
                'brut' => $brut,
                'statut' => self::STATUT_VALIDE,
                'motif' => null,
                'doublon' => false,
            ];

            $resultat = $module->valider($brut);
            if ($resultat['erreurs'] !== []) {
                $entree['statut'] = self::STATUT_REFUSEE;
                $entree['motif'] = $this->motifsDeColonnes($module, $numero, $resultat['erreurs']);
            } else {
                $cleLigne = $module->cleLigne($resultat['valeurs']);
                if (isset($premiere[$cleLigne])) {
                    $entree['statut'] = self::STATUT_REFUSEE;
                    $entree['doublon'] = true;
                    $entree['motif'] = "Ligne {$numero} : doublon de la ligne {$premiere[$cleLigne]}.";
                } else {
                    $premiere[$cleLigne] = $numero;
                    if (($deja = $module->dejaPresente($resultat['valeurs'])) !== null) {
                        $entree['statut'] = self::STATUT_IGNOREE;
                        $entree['motif'] = $deja;
                    }
                }
            }

            $lignes[] = $entree;
        }

        $compte = array_count_values(array_column($lignes, 'statut'));

        $precedent = ImportBatch::where('module', $module->cle())
            ->where('empreinte', $empreinte)
            ->where('statut', ImportBatch::TERMINE)
            ->with('user')
            ->latest('termine_le')
            ->first();

        return ImportBatch::create([
            'user_id' => $user->id,
            'module' => $module->cle(),
            'version_modele' => $module->version(),
            'nom_fichier' => mb_substr($nomFichier, 0, 255),
            'empreinte' => $empreinte,
            'statut' => ImportBatch::APERCU,
            'lues' => count($lignes),
            'valides' => $compte[self::STATUT_VALIDE] ?? 0,
            'ignorees' => $compte[self::STATUT_IGNOREE] ?? 0,
            'refusees' => $compte[self::STATUT_REFUSEE] ?? 0,
            'avertissement' => $precedent
                ? 'Ce fichier a déjà été importé le '.$precedent->termine_le->format('d/m/Y à H:i').' par '.($precedent->user?->name ?? 'un utilisateur inconnu').'. Les fiches déjà présentes seront ignorées.'
                : null,
            'lignes' => $lignes,
            // Motif qui interdit TOUT l'import (exercice clos…) : refusé ICI, avant la confirmation.
            'rapport' => ['bloquant' => $module->controlePrealable()],
        ]);
    }

    /**
     * Écrit les lignes valides de l'aperçu, ligne par ligne, par le point de passage unique du module.
     *
     * @throws ImportRefuse  rien n'est écrit (aperçu déjà confirmé, motif bloquant, autre utilisateur)
     * @throws AuthorizationException
     */
    public function importer(ImportBatch $lot, User $user): ImportBatch
    {
        $module = $this->moduleAutorise($lot->module, $user);

        if ($lot->statut !== ImportBatch::APERCU) {
            throw new ImportRefuse('Cet import a déjà été confirmé ou annulé : recommencez à l\'étape 3 avec le fichier.');
        }
        if ($lot->user_id !== $user->id) {
            throw new ImportRefuse('Cet aperçu a été préparé par un autre utilisateur.');
        }
        if (($bloquant = $module->controlePrealable()) !== null) {
            throw new ImportRefuse($bloquant);
        }

        $lignes = $lot->lignes;
        foreach ($lignes as $i => $l) {
            if ($l['statut'] !== self::STATUT_VALIDE) {
                continue;
            }

            $resultat = $module->valider($l['brut']);
            if ($resultat['erreurs'] !== []) {
                $lignes[$i]['statut'] = self::STATUT_REFUSEE;
                $lignes[$i]['motif'] = $this->motifsDeColonnes($module, $l['ligne'], $resultat['erreurs']);

                continue;
            }

            if (($deja = $module->dejaPresente($resultat['valeurs'])) !== null) {
                $lignes[$i]['statut'] = self::STATUT_IGNOREE;
                $lignes[$i]['motif'] = $deja;

                continue;
            }

            try {
                DB::transaction(fn () => $module->ecrire($resultat['valeurs'], $module->idLigne($resultat['valeurs'])));
                $lignes[$i]['statut'] = self::STATUT_CREEE;
            } catch (\Throwable $e) {
                $lignes[$i]['statut'] = self::STATUT_REFUSEE;
                $lignes[$i]['motif'] = 'Ligne '.$l['ligne'].' : '.$this->motifDe($e);
            }
        }

        // Les valeurs lues ne restent que pour les lignes REFUSÉES (le rapport à corriger) : jamais celles des fiches créées.
        foreach ($lignes as $i => $l) {
            if ($l['statut'] !== self::STATUT_REFUSEE) {
                $lignes[$i]['brut'] = null;
            }
        }

        $compte = array_count_values(array_column($lignes, 'statut'));
        $lot->update([
            'statut' => ImportBatch::TERMINE,
            'creees' => $compte[self::STATUT_CREEE] ?? 0,
            'ignorees' => $compte[self::STATUT_IGNOREE] ?? 0,
            'refusees' => $compte[self::STATUT_REFUSEE] ?? 0,
            'valides' => 0,
            'lignes' => $lignes,
            'termine_le' => now(),
        ]);

        // UNE ligne d'audit par fichier : le module, le lot (compteurs au journal), jamais le contenu.
        AuditLog::record('import.masse', $module->moduleAudit(), $user->id, $lot);

        return $lot->fresh();
    }

    public function annuler(ImportBatch $lot, User $user): void
    {
        if ($lot->statut === ImportBatch::APERCU && $lot->user_id === $user->id) {
            $lot->update(['statut' => ImportBatch::ANNULE, 'lignes' => null]);
        }
    }

    /**
     * Rapport téléchargeable : feuille « Rapport » (une ligne par ligne du fichier : résultat et motif) et feuille « Lignes
     * refusées » (leurs valeurs, à corriger puis à ré-importer). Les valeurs sont écrites comme du TEXTE (jamais une formule).
     *
     * @return string chemin d'un fichier temporaire (à supprimer par l'appelant)
     */
    public function rapportXlsx(ImportBatch $lot): string
    {
        $module = self::module($lot->module) ?? throw new ImportRefuse('Module inconnu.');
        $classeur = new Spreadsheet();

        $rapport = $classeur->getActiveSheet();
        $rapport->setTitle('Rapport');
        $this->ligneTexte($rapport, 1, ['Ligne', 'Désignation', 'Résultat', 'Motif']);
        $rapport->getStyle('A1:D1')->getFont()->setBold(true);
        $libelles = $this->libellesDeStatut($lot->statut === ImportBatch::TERMINE);
        foreach (array_values($lot->lignes ?? []) as $i => $l) {
            $this->ligneTexte($rapport, $i + 2, [(string) $l['ligne'], (string) $l['designation'], $libelles[$l['statut']] ?? $l['statut'], (string) ($l['motif'] ?? '')]);
        }
        foreach (['A' => 8, 'B' => 38, 'C' => 22, 'D' => 90] as $col => $largeur) {
            $rapport->getColumnDimension($col)->setWidth($largeur);
        }

        $refusees = $classeur->createSheet();
        $refusees->setTitle('Lignes refusées');
        $entetes = array_merge(['Ligne', 'Motif'], array_map(fn (ColonneImport $c) => $c->entete(), $module->colonnes()));
        $this->ligneTexte($refusees, 1, $entetes);
        $refusees->getStyle('A1:'.\PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex(count($entetes)).'1')->getFont()->setBold(true);
        $n = 2;
        foreach ($lot->lignes ?? [] as $l) {
            if ($l['statut'] !== self::STATUT_REFUSEE) {
                continue;
            }
            $valeurs = array_map(fn (ColonneImport $c) => (string) ($l['brut'][$c->cle] ?? ''), $module->colonnes());
            $this->ligneTexte($refusees, $n++, array_merge([(string) $l['ligne'], (string) $l['motif']], $valeurs));
        }
        $refusees->getColumnDimension('B')->setWidth(90);

        $chemin = tempnam(sys_get_temp_dir(), 'rapport_').'.xlsx';
        IOFactory::createWriter($classeur, 'Xlsx')->save($chemin);

        return $chemin;
    }

    public function nomDuRapport(ImportBatch $lot): string
    {
        return 'Rapport_importation_'.$lot->module.'_'.($lot->termine_le ?? $lot->created_at)->format('Ymd_His').'.xlsx';
    }

    /** @return array<string, string> */
    public function libellesDeStatut(bool $termine): array
    {
        return $termine
            ? [self::STATUT_CREEE => 'Créée', self::STATUT_IGNOREE => 'Ignorée (déjà présente)', self::STATUT_REFUSEE => 'Refusée', self::STATUT_VALIDE => 'Valide']
            : [self::STATUT_VALIDE => 'Valide', self::STATUT_IGNOREE => 'Ignorée (déjà présente)', self::STATUT_REFUSEE => 'Refusée'];
    }

    /** @param array<int, string> $valeurs */
    private function ligneTexte(\PhpOffice\PhpSpreadsheet\Worksheet\Worksheet $feuille, int $ligne, array $valeurs): void
    {
        foreach (array_values($valeurs) as $i => $valeur) {
            $feuille->setCellValueExplicit([$i + 1, $ligne], $valeur, DataType::TYPE_STRING);
        }
    }

    /**
     * « Feuille « Données », ligne 7, colonne « Nom * » : motif » — une ligne par colonne en erreur.
     *
     * @param  array<string, string>  $erreurs  clé de colonne → motif
     */
    private function motifsDeColonnes(ModuleImport $module, int $numero, array $erreurs): string
    {
        $messages = [];
        foreach ($erreurs as $cle => $motif) {
            $messages[] = 'Feuille « '.LecteurXlsx::FEUILLE_DONNEES.' », ligne '.$numero.', colonne « '.$module->colonne($cle)->entete().' » : '.$motif;
        }

        return implode("\n", $messages);
    }

    /** Le motif français d'un échec d'écriture : celui du service ; jamais un message SQL. */
    private function motifDe(\Throwable $e): string
    {
        if ($e instanceof ValidationException) {
            return (string) collect($e->errors())->flatten()->first();
        }
        if (str_starts_with($e::class, 'App\\Exceptions\\') || $e instanceof \DomainException || $e instanceof \InvalidArgumentException) {
            return $e->getMessage();
        }

        report($e);

        return "Enregistrement impossible (erreur technique, voir le journal du serveur). La ligne n'a pas été écrite.";
    }
}
