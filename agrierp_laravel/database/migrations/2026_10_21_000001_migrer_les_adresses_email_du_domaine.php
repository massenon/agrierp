<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * MAIL1 (décision du client, 21/10/2026) — les adresses `@olouwachegoun.bj` DÉJÀ enregistrées en base deviennent
 * `@fermeolouwachegoun.com` (le code, les seeders et les écrans ont été convertis par le commit précédent ; ceci
 * convertit les DONNÉES). Migration de données, IDEMPOTENTE : relancée, elle ne trouve plus rien à changer.
 *
 * ⚠️ Parcours GÉNÉRIQUE du schéma (`Schema::getTables()` / `getColumns()`), sans modèle : pour chaque table, les
 * colonnes texte dont le nom évoque une adresse e-mail (`email`, `*_email`, `smtp_user`, `smtp_from_address`,
 * `reply_to`…), plus les colonnes de configuration/notification listées dans `COLONNES_SUPPLEMENTAIRES`. Seul
 * l'enchaînement `@olouwachegoun.bj` (insensible à la casse) est réécrit : un nom de serveur (`smtp.olouwachegoun.bj`,
 * sans « @ ») n'est pas une adresse et n'est pas touché ; une adresse d'un autre domaine non plus.
 *
 * ⚠️ JAMAIS TOUCHÉS : les secrets (`smtp_password_encrypted`, `*_encrypted`, `*_token*`, `*password*`, `*secret*`)
 * sont écartés par leur NOM, avant toute lecture — on ne lit même pas leur valeur.
 *
 * ⚠️ UNICITÉ : `users.email` est unique. Si la nouvelle adresse existe déjà chez un AUTRE enregistrement (index
 * unique, y compris la clé primaire de `password_reset_tokens`), la ligne n'est pas changée, un `Log::warning`
 * la signale, et la migration continue.
 *
 * ⚠️ COMPTE `admin` : l'adresse de contact du DG est `contact@fermeolouwachegoun.com` (DemoUsersSeeder). Un ancien
 * `dg@olouwachegoun.bj` porté par le compte `admin` devient donc `contact@…` et non `dg@…` ; toute autre adresse
 * du compte `admin`, et `dg@` d'un autre compte, suivent la règle générale (même partie locale).
 *
 * `updated_at` (quand la table en a un) est mis à « maintenant » sur les SEULES lignes modifiées : le tirage des
 * postes les resert et les postes convergent. Aucun schéma n'est touché ; `down()` est vide (le domaine précédent
 * n'est plus conservé nulle part, la décision du client est à sens unique).
 */
return new class extends Migration
{
    private const ANCIEN_DOMAINE = 'olouwachegoun.bj';

    private const NOUVEAU_DOMAINE = 'fermeolouwachegoun.com';

    private const MOTIF = '/@olouwachegoun\.bj(?![A-Za-z0-9-])/i';

    /** Tables jamais parcourues, avec la raison. */
    private const TABLES_EXCLUES = [
        // Historique d'audit : un journal ne se réécrit pas (il atteste de ce qui a été fait, avec les mots de l'époque).
        'audit_logs' => 'journal d\'audit : historique intangible',
        'journal_synchronisation' => 'journal technique des synchronisations : historique intangible',
        // Tables techniques du framework : charges utiles sérialisées, jamais des adresses à jour.
        'migrations' => 'technique',
        'jobs' => 'technique', 'failed_jobs' => 'technique', 'job_batches' => 'technique',
        'sessions' => 'technique', 'cache' => 'technique', 'cache_locks' => 'technique',
    ];

    /** Colonnes de configuration / notification susceptibles de contenir une adresse, hors nom « e-mail ». */
    private const COLONNES_SUPPLEMENTAIRES = [
        'notifications' => ['message', 'title'],
    ];

    /** Un secret n'est jamais lu : écarté par son nom. */
    private const MOTIF_SECRET = '/password|passwd|secret|token|encrypted|api_key|auth_key/i';

    private const MOTIF_NOM_EMAIL = '/e?mail|smtp_user|reply_to|from_address|sender|expediteur/i';

    private const TYPES_TEXTE = ['varchar', 'char', 'text', 'tinytext', 'mediumtext', 'longtext', 'json', 'string'];

    public function up(): void
    {
        foreach (Schema::getTables() as $table) {
            $nom = $table['name'];
            if (isset(self::TABLES_EXCLUES[$nom])) {
                continue;
            }

            $colonnes = $this->colonnesAConvertir($nom);
            if ($colonnes === []) {
                continue;
            }

            $this->convertirTable($nom, $colonnes);
        }
    }

    public function down(): void
    {
        // Rien : décision du client à sens unique (le domaine précédent n'est plus conservé).
    }

    /** @return list<string> */
    private function colonnesAConvertir(string $table): array
    {
        $retenues = [];
        $supplementaires = self::COLONNES_SUPPLEMENTAIRES[$table] ?? [];

        foreach (Schema::getColumns($table) as $colonne) {
            $nom = $colonne['name'];
            if (! in_array(strtolower((string) $colonne['type_name']), self::TYPES_TEXTE, true)) {
                continue;
            }
            if (preg_match(self::MOTIF_SECRET, $nom)) {
                continue;
            }
            $evoqueUneAdresse = (bool) preg_match(self::MOTIF_NOM_EMAIL, $nom);
            $deConfiguration = in_array('*', $supplementaires, true) || in_array($nom, $supplementaires, true);
            if ($table === 'company_settings') {
                // Tous les champs texte non secrets de la configuration de l'entreprise.
                $deConfiguration = true;
            }
            if ($evoqueUneAdresse || $deConfiguration) {
                $retenues[] = $nom;
            }
        }

        return $retenues;
    }

    /** @param list<string> $colonnes */
    private function convertirTable(string $table, array $colonnes): void
    {
        $cle = $this->colonnesDeLaClePrimaire($table);
        if ($cle === []) {
            return; // Pas de moyen sûr d'adresser une ligne : on ne touche pas.
        }
        $uniques = $this->indexUniques($table);
        $aUpdatedAt = Schema::hasColumn($table, 'updated_at');

        foreach ($colonnes as $colonne) {
            $lignes = DB::table($table)
                ->whereNotNull($colonne)
                ->whereRaw('LOWER('.$this->citer($colonne).') LIKE ?', ['%@'.self::ANCIEN_DOMAINE.'%'])
                ->get(array_values(array_unique(array_merge($cle, [$colonne, ...($table === 'users' ? ['username'] : [])]))));

            foreach ($lignes as $ligne) {
                $ligne = (array) $ligne;
                $avant = (string) $ligne[$colonne];
                $apres = $this->remplacer($avant);
                if ($table === 'users' && $colonne === 'email' && ($ligne['username'] ?? null) === 'admin'
                    && strtolower($avant) === 'dg@'.self::ANCIEN_DOMAINE) {
                    $apres = 'contact@'.self::NOUVEAU_DOMAINE;
                }
                if ($apres === $avant) {
                    continue;
                }

                $adresse = array_intersect_key($ligne, array_flip($cle));
                if ($this->prisParUnAutre($table, $colonne, $apres, $adresse, $uniques)) {
                    Log::warning("Migration des adresses e-mail : {$table}.{$colonne} « {$avant} » n'est pas changée en « {$apres} », cette adresse existe déjà pour un autre enregistrement ({$this->decrire($adresse)}).");

                    continue;
                }

                $valeurs = [$colonne => $apres];
                if ($aUpdatedAt) {
                    $valeurs['updated_at'] = now();
                }
                DB::table($table)->where($adresse)->update($valeurs);
            }
        }
    }

    private function remplacer(string $valeur): string
    {
        return (string) preg_replace(self::MOTIF, '@'.self::NOUVEAU_DOMAINE, $valeur);
    }

    /** @return list<string> */
    private function colonnesDeLaClePrimaire(string $table): array
    {
        foreach (Schema::getIndexes($table) as $index) {
            if (! empty($index['primary'])) {
                return array_values($index['columns']);
            }
        }

        return [];
    }

    /** @return list<list<string>> colonnes de chaque index unique (clé primaire comprise) */
    private function indexUniques(string $table): array
    {
        $uniques = [];
        foreach (Schema::getIndexes($table) as $index) {
            if (! empty($index['unique']) || ! empty($index['primary'])) {
                $uniques[] = array_values($index['columns']);
            }
        }

        return $uniques;
    }

    /**
     * Vrai quand la nouvelle valeur violerait un index unique : un AUTRE enregistrement porte déjà les mêmes valeurs
     * (comparaison insensible à la casse, comme le collation MySQL utf8mb4_unicode_ci).
     *
     * @param  array<string,mixed>  $adresse  clé primaire de la ligne en cours
     * @param  list<list<string>>  $uniques
     */
    private function prisParUnAutre(string $table, string $colonne, string $nouvelle, array $adresse, array $uniques): bool
    {
        foreach ($uniques as $colonnesIndex) {
            if (! in_array($colonne, $colonnesIndex, true)) {
                continue;
            }

            $requete = DB::table($table);
            foreach ($colonnesIndex as $c) {
                if ($c === $colonne) {
                    $requete->whereRaw('LOWER('.$this->citer($c).') = ?', [strtolower($nouvelle)]);
                } else {
                    $valeur = DB::table($table)->where($adresse)->value($c);
                    $valeur === null ? $requete->whereNull($c) : $requete->where($c, $valeur);
                }
            }
            foreach ($adresse as $c => $v) {
                $requete->where($c, '!=', $v);
            }
            // Une clé primaire composée : « autre » = au moins une colonne de clé différente. Pour une clé simple
            // (cas de tout le schéma) c'est exactement `!=`.
            if ($requete->exists()) {
                return true;
            }
        }

        return false;
    }

    private function citer(string $colonne): string
    {
        return DB::connection()->getQueryGrammar()->wrap($colonne);
    }

    /** @param array<string,mixed> $adresse */
    private function decrire(array $adresse): string
    {
        return implode(', ', array_map(fn ($c, $v) => "{$c}={$v}", array_keys($adresse), $adresse));
    }
};
