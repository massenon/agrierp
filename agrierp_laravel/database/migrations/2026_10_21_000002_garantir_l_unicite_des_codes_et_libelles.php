<?php

use App\Support\CleUnicite;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket UNI — INDEX UNIQUE sur `livestock_lots.code` et `product_categories.label`, SEULEMENT si les données le
 * permettent.
 *
 * Deux bandes de même code (`AVI-2026-01`) et deux catégories de même libellé (« Aliments ») ont fait planter des
 * écrans du poste. L'application refuse désormais d'en créer (règle `UniqueNormalise`) ; cette migration pose en plus
 * la garantie au niveau de la base, quand elle est possible :
 *
 *  - elle cherche d'abord les doublons, avec la MÊME clé que l'application (casse, accents et espaces ignorés —
 *    plus stricte que l'index lui-même : si elle ne trouve rien, l'index passe) ;
 *  - AUCUN doublon : l'index unique est ajouté s'il n'existe pas déjà (`livestock_lots.code` l'a depuis sa création,
 *    la migration le rétablit seulement s'il manque sur une base restaurée à la main) ;
 *  - DES doublons : l'index n'est PAS ajouté, un `Log::warning` le dit (table, valeurs, nombre) et l'unicité reste
 *    contrôlée par l'application. Rien n'est supprimé, rien n'est renommé : le client renomme lui-même, guidé par
 *    `php artisan agrierp:doublons` et l'alerte du poste. Relancer la migration (`migrate:refresh` n'est pas
 *    nécessaire : elle est idempotente) après correction posera l'index.
 *
 * Aucune donnée n'est jamais modifiée ici.
 */
return new class extends Migration
{
    /** @var array<string, string> table => colonne */
    private const CIBLES = [
        'product_categories' => 'label',
        'livestock_lots' => 'code',
    ];

    public function up(): void
    {
        foreach (self::CIBLES as $table => $colonne) {
            if (! Schema::hasTable($table) || ! Schema::hasColumn($table, $colonne)) {
                continue;
            }

            $doublons = $this->doublons($table, $colonne);
            if ($doublons !== []) {
                Log::warning(
                    "UNI : {$table}.{$colonne} contient ".count($doublons).' valeur(s) en doublon ('
                    .implode(', ', array_map(fn ($v) => "« {$v} »", array_slice($doublons, 0, 10)))
                    .(count($doublons) > 10 ? ', …' : '')
                    .") : l'index unique n'est PAS ajouté, l'unicité reste contrôlée par l'application. "
                    .'Renommez les lignes concernées (php artisan agrierp:doublons les liste) puis relancez php artisan migrate.'
                );

                continue;
            }

            if (! Schema::hasIndex($table, [$colonne], 'unique')) {
                Schema::table($table, fn (Blueprint $t) => $t->unique($colonne, "{$table}_{$colonne}_unique"));
            }
        }
    }

    public function down(): void
    {
        // `livestock_lots.code` était unique avant ce ticket : seul l'index ajouté ici sur les catégories est retiré.
        if (Schema::hasTable('product_categories') && Schema::hasIndex('product_categories', ['label'], 'unique')) {
            Schema::table('product_categories', fn (Blueprint $t) => $t->dropUnique('product_categories_label_unique'));
        }
    }

    /** @return list<string> les valeurs (telles qu'écrites, première rencontrée) portées par plus d'une ligne */
    private function doublons(string $table, string $colonne): array
    {
        $vues = [];
        $doublons = [];

        foreach (DB::table($table)->orderBy('id')->pluck($colonne) as $valeur) {
            $cle = CleUnicite::cle((string) $valeur);
            if ($cle === '') {
                continue;
            }
            if (isset($vues[$cle])) {
                $doublons[$cle] = $vues[$cle];

                continue;
            }
            $vues[$cle] = trim((string) $valeur);
        }

        return array_values($doublons);
    }
};
