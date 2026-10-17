<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.50 (Sprint 14) — IDENTIFIANT COURT DE CONNEXION.
 *
 * DEMANDE CLIENT EXPLICITE : se connecter avec « admin », « compta »… plutôt
 * qu'avec une adresse e-mail complète. Sur le terrain, l'ERP s'ouvre au
 * comptoir sur un téléphone : taper `caisse@olouwachegoun.bj` à chaque
 * ouverture de caisse est une friction réelle.
 *
 * ⚠️ LA MAQUETTE LE PRÉVOYAIT DÉJÀ. `login.html` intitule son champ « NOM
 * D'UTILISATEUR OU EMAIL » — le Blade reprenait ce libellé mot pour mot mais
 * l'implémentation n'acceptait que l'e-mail (`type="email"` + validation
 * `email`). L'écran promettait donc à l'utilisateur quelque chose qu'il
 * refusait ensuite. Cette migration rend le libellé vrai.
 *
 * ⚠️ L'E-MAIL EST CONSERVÉ, PAS REMPLACÉ. Il reste la clé de la
 * réinitialisation de mot de passe (`password_reset_tokens` est indexée
 * dessus) et le seul canal de notification hors application. Supprimer la
 * colonne casserait le lien « Mot de passe oublié » sans rien apporter.
 *
 * ⚠️ NULLABLE À DESSEIN : les comptes existants n'en ont pas encore, et un
 * `NOT NULL` sans valeur par défaut ferait échouer la migration sur une base
 * déjà peuplée. Ils sont renseignés juste après, à partir de la partie locale
 * de l'adresse — `compta@olouwachegoun.bj` devient `compta`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('username', 50)->nullable()->unique()->after('name');
        });

        // Renseignement des comptes déjà en base. Fait en PHP et non en SQL :
        // `SUBSTRING_INDEX` est propre à MySQL et rendrait la migration
        // intestable sur SQLite (leçon du ticket 14.x, `suggestNextCode`).
        $pris = [];

        foreach (DB::table('users')->orderBy('created_at')->orderBy('id')->get(['id', 'email']) as $u) {
            $base = strtolower(trim(explode('@', (string) $u->email)[0]));
            $base = preg_replace('/[^a-z0-9._-]/', '', $base) ?: 'utilisateur';

            // Deux adresses distinctes peuvent partager leur partie locale
            // (`compta@a.bj` et `compta@b.bj`) : la contrainte d'unicité ferait
            // alors échouer la migration. Suffixe numérique plutôt qu'une
            // erreur au déploiement.
            $identifiant = $base;
            $n = 1;

            while (in_array($identifiant, $pris, true)) {
                $identifiant = $base.(++$n);
            }

            $pris[] = $identifiant;
            DB::table('users')->where('id', $u->id)->update(['username' => $identifiant]);
        }
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique(['username']);
            $table->dropColumn('username');
        });
    }
};
