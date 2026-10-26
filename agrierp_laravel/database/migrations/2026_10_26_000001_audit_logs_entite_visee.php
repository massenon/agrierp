<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket ARC-Q2 (PRD `docs/prd/archives.md`) — « QUI a archivé ? ».
 *
 * Jusqu'ici une ligne d'`audit_logs` disait QUI avait fait QUOI, jamais SUR QUEL enregistrement : la Corbeille ne
 * pouvait donc pas afficher l'auteur d'un archivage. On ajoute l'enregistrement visé (`entity_type` = classe du
 * modèle, `entity_id` = sa clé), NULLABLES : les lignes antérieures n'ont pas d'entité, et la Corbeille y affiche
 * « — » (jamais un nom inventé). L'index sert la lecture « dernier archivage de cette entité ».
 *
 * Rejouable : chaque ajout est gardé (colonne / index déjà présents = rien à faire), `down()` aussi.
 */
return new class extends Migration
{
    private const INDEX = 'audit_logs_entite_visee_index';

    public function up(): void
    {
        if (! Schema::hasColumn('audit_logs', 'entity_type')) {
            Schema::table('audit_logs', function (Blueprint $table) {
                $table->string('entity_type', 150)->nullable()->after('module');
            });
        }
        if (! Schema::hasColumn('audit_logs', 'entity_id')) {
            Schema::table('audit_logs', function (Blueprint $table) {
                $table->string('entity_id', 64)->nullable()->after('entity_type');
            });
        }
        if (! Schema::hasIndex('audit_logs', self::INDEX)) {
            Schema::table('audit_logs', function (Blueprint $table) {
                $table->index(['entity_type', 'entity_id', 'created_at'], self::INDEX);
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasIndex('audit_logs', self::INDEX)) {
            Schema::table('audit_logs', function (Blueprint $table) {
                $table->dropIndex(self::INDEX);
            });
        }
        foreach (['entity_id', 'entity_type'] as $colonne) {
            if (Schema::hasColumn('audit_logs', $colonne)) {
                Schema::table('audit_logs', function (Blueprint $table) use ($colonne) {
                    $table->dropColumn($colonne);
                });
            }
        }
    }
};
