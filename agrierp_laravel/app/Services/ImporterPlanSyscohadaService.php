<?php

namespace App\Services;

use App\Models\ChartOfAccount;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

/**
 * Ticket 15.27 — PHASE A DE L'ITEM 9 : IMPORT DU PLAN COMPTABLE SYSCOHADA RÉVISÉ OFFICIEL (CSV du client).
 *
 * ⚠️⚠️ INSERTION SEULE. Ce service AJOUTE les codes du CSV qui n'existent pas encore dans `chart_of_accounts`. Il ne
 * modifie, ne renomme, ne désactive ni ne supprime JAMAIS un compte existant — même quand son libellé ou son sens
 * diffère de celui du CSV : 12 comptes de la ferme (221, 241, 244, 281, 531, 602, 614, 621, 624, 628, 701, 4473)
 * portent un code que le CSV utilise pour AUTRE CHOSE (531 = « chèques postaux » au CSV, « caisse » à la ferme).
 * Les remapper est la PHASE B, bloquée par la validation du cabinet FAGUEZ. Aucun code de comptabilisation
 * (`app/Actions`), aucune écriture, aucun `treasury_accounts` n'est touché.
 *
 * Source : `database/data/plan-comptable-syscohada-revise.csv`, copie octet pour octet du fichier fourni par le client
 * (`EMPREINTE_SHA256`). « Code;Libellé », UTF-8 (BOM toléré), CRLF ou LF.
 *
 * Règles (aucune n'est inventée) :
 *  - classe = premier chiffre du code (1 à 9) ;
 *  - libellé = celui du CSV, nettoyé (espaces de bord, guillemets d'enveloppe CSV). JAMAIS tronqué : la colonne a été
 *    élargie à 255 pour deux libellés du CSV qui dépassent 150 (voir `libelles_longs` du rapport) ;
 *  - parent = compte le plus proche par préfixe (le code privé de son dernier chiffre, récursivement), qu'il préexiste
 *    ou qu'il soit créé par cet import ; `null` s'il n'y en a aucun. Ne fait que POSER le parent d'un compte créé ;
 *  - actif, UUID générés ici ;
 *  - tout ou rien : le fichier est entièrement validé AVANT la première écriture, puis écrit en une transaction.
 *
 * ⚠️ À VALIDER PAR LE CABINET FAGUEZ : trois libellés du CSV sont des phrases de note de bas de page, pas des
 * intitulés (`LIBELLES_A_CORRIGER_PAR_LE_CABINET`). Importés TELS QUELS, ils sont signalés dans le rapport.
 */
class ImporterPlanSyscohadaService
{
    public const CHEMIN_PAR_DEFAUT = 'database/data/plan-comptable-syscohada-revise.csv';

    public const EMPREINTE_SHA256 = '4103f4efc474fd6ffd5755575732d0eba7289a71f8364f51462e25924e9df143';

    /** Largeur de la colonne `label` (migration `widen_chart_of_accounts_label`) : au-delà, le fichier est REFUSÉ, jamais tronqué. */
    public const LONGUEUR_MAX = 255;

    /** Seuil historique de la colonne `label` ; au-delà, le libellé est signalé (et conservé entier). */
    public const LONGUEUR_HISTORIQUE = 150;

    /** À CORRIGER PAR LE CABINET FAGUEZ : le CSV y met une phrase de note au lieu d'un intitulé. */
    public const LIBELLES_A_CORRIGER_PAR_LE_CABINET = ['54', '603', '66'];

    /**
     * @return array{total_csv: int, deja_presents: int, crees: int, dry_run: bool, par_classe: array<int, int>, libelles_longs: array<int, array{code: string, longueur: int}>, libelles_a_corriger_par_le_cabinet: array<int, array{code: string, label: string, cree: bool}>, empreinte: string}
     */
    public function importer(?string $chemin = null, bool $dryRun = false): array
    {
        $chemin ??= base_path(self::CHEMIN_PAR_DEFAUT);
        $plan = $this->lire($chemin);

        $existants = DB::table('chart_of_accounts')->pluck('id', 'code')->all();
        $existants = array_combine(array_map('strval', array_keys($existants)), array_values($existants));

        $aCreer = array_diff_key($plan, $existants);
        // Les parents d'abord : codes courts avant codes longs.
        uksort($aCreer, fn ($a, $b) => [strlen((string) $a), (string) $a] <=> [strlen((string) $b), (string) $b]);

        $lignes = [];
        $ids = $existants;
        $parClasse = [];
        $maintenant = now();

        foreach ($aCreer as $code => $label) {
            $code = (string) $code;
            $id = (string) Str::uuid();
            $parent = null;
            for ($p = strlen($code) - 1; $p >= 1; $p--) {
                if (isset($ids[substr($code, 0, $p)])) {
                    $parent = $ids[substr($code, 0, $p)];
                    break;
                }
            }
            $ids[$code] = $id;
            $classe = (int) $code[0];
            $parClasse[$classe] = ($parClasse[$classe] ?? 0) + 1;
            $lignes[] = [
                'id' => $id, 'code' => $code, 'label' => $label, 'class' => $classe, 'parent_id' => $parent,
                'is_active' => true, 'created_at' => $maintenant, 'updated_at' => $maintenant,
            ];
        }

        if (! $dryRun && $lignes !== []) {
            DB::transaction(function () use ($lignes) {
                foreach (array_chunk($lignes, 200) as $lot) {
                    DB::table('chart_of_accounts')->insert($lot);
                }
            });
        }

        ksort($parClasse);
        $longs = [];
        foreach ($plan as $code => $label) {
            if (mb_strlen($label) > self::LONGUEUR_HISTORIQUE) {
                $longs[] = ['code' => (string) $code, 'longueur' => mb_strlen($label)];
            }
        }

        $acorriger = [];
        foreach (self::LIBELLES_A_CORRIGER_PAR_LE_CABINET as $code) {
            if (isset($plan[$code])) {
                $acorriger[] = ['code' => $code, 'label' => $plan[$code], 'cree' => isset($aCreer[$code])];
            }
        }

        return [
            'total_csv' => count($plan),
            'deja_presents' => count($plan) - count($aCreer),
            'crees' => count($lignes),
            'dry_run' => $dryRun,
            'par_classe' => $parClasse,
            'libelles_longs' => $longs,
            'libelles_a_corriger_par_le_cabinet' => $acorriger,
            'empreinte' => hash_file('sha256', $chemin),
        ];
    }

    /**
     * Lit et VALIDE tout le fichier. Aucune écriture ici.
     *
     * @return array<string, string> code => libellé, dans l'ordre du fichier
     *
     * @throws InvalidArgumentException fichier illisible ou malformé (avec le numéro de ligne)
     */
    public function lire(string $chemin): array
    {
        if (! is_file($chemin) || ($texte = file_get_contents($chemin)) === false) {
            throw new InvalidArgumentException("Fichier du plan comptable introuvable : {$chemin}");
        }

        $texte = preg_replace('/^\xEF\xBB\xBF/', '', $texte);
        if (! mb_check_encoding($texte, 'UTF-8')) {
            throw new InvalidArgumentException("Le fichier du plan comptable n'est pas en UTF-8.");
        }

        $lignes = preg_split('/\r\n|\n|\r/', $texte);
        if (trim((string) ($lignes[0] ?? '')) !== 'Code;Libellé') {
            throw new InvalidArgumentException('Entête attendu « Code;Libellé » absent de la ligne 1.');
        }

        $plan = [];
        foreach ($lignes as $i => $ligne) {
            if ($i === 0 || trim($ligne) === '') {
                continue;
            }
            $n = $i + 1;

            if (! str_contains($ligne, ';')) {
                throw new InvalidArgumentException("Ligne {$n} : séparateur « ; » absent.");
            }
            [$code, $label] = explode(';', $ligne, 2);
            $code = trim($code);
            $label = $this->nettoyer($label);

            if (! preg_match('/^[1-9][0-9]{0,19}$/', $code)) {
                throw new InvalidArgumentException("Ligne {$n} : code « {$code} » invalide (chiffres, premier chiffre de 1 à 9).");
            }
            if ($label === '') {
                throw new InvalidArgumentException("Ligne {$n} : libellé vide pour le code {$code}.");
            }
            if (mb_strlen($label) > self::LONGUEUR_MAX) {
                throw new InvalidArgumentException('Ligne '.$n.' : libellé du code '.$code.' de '.mb_strlen($label).' caractères, maximum '.self::LONGUEUR_MAX.' (jamais tronqué : fichier refusé).');
            }
            if (isset($plan[$code])) {
                throw new InvalidArgumentException("Ligne {$n} : code {$code} en double.");
            }
            $plan[$code] = $label;
        }

        if ($plan === []) {
            throw new InvalidArgumentException('Le fichier du plan comptable ne contient aucun compte.');
        }

        return $plan;
    }

    private function nettoyer(string $label): string
    {
        $label = trim($label);
        // Champ CSV entièrement entouré de guillemets (code 5024) : on retire l'enveloppe, pas le contenu.
        if (strlen($label) >= 2 && $label[0] === '"' && substr($label, -1) === '"') {
            $label = str_replace('""', '"', substr($label, 1, -1));
        }

        return trim($label);
    }
}
