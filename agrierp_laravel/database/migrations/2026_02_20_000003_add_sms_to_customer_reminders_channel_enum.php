<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ⚠️ CORRECTION : `customer_reminders.channel` (§12, documenté) n'admet
 * que `['whatsapp', 'email', 'appel']` — pas de valeur `sms` distincte.
 * Un SMS n'est pas un appel téléphonique ; les confondre aurait rendu la
 * traçabilité des relances trompeuse. Enum étendu avec `sms`.
 *
 * 🔴→✅ TROUVÉ AU TICKET 14.1 : `ALTER TABLE ... MODIFY COLUMN ... ENUM`
 * est de la syntaxe MySQL pure, alors que `phpunit.xml` fait tourner toute
 * la suite de tests sur SQLite en mémoire. Cette migration faisait donc
 * échouer `php artisan test` avec « near "MODIFY": syntax error » AVANT
 * même que le moindre test ne s'exécute — les 8 tests Feature échouaient
 * tous pour cette seule raison, aucun rapport avec ce qu'ils vérifient.
 * Le comportement MySQL de production est inchangé ; seul un repli portable
 * est ajouté pour les autres pilotes.
 */
return new class extends Migration
{
    public function up(): void
    {
        if ($this->isMysql()) {
            DB::statement("ALTER TABLE customer_reminders MODIFY COLUMN channel ENUM('whatsapp', 'email', 'appel', 'sms') NOT NULL");

            return;
        }

        // SQLite (tests) : pas de type ENUM natif — la colonne devient une
        // chaîne, la contrainte de valeurs restant portée par la validation
        // applicative, comme partout ailleurs dans le projet.
        Schema::table('customer_reminders', function (Blueprint $table) {
            $table->string('channel')->nullable(false)->change();
        });
    }

    public function down(): void
    {
        if ($this->isMysql()) {
            DB::statement("ALTER TABLE customer_reminders MODIFY COLUMN channel ENUM('whatsapp', 'email', 'appel') NOT NULL");
        }
    }

    private function isMysql(): bool
    {
        return in_array(DB::connection()->getDriverName(), ['mysql', 'mariadb'], true);
    }
};
