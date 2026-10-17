<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Ticket 15.20 — RETOUR FOURNISSEUR : de quoi le rendre idempotent et descendant.
 *
 * `purchase_returns` (une ligne par ligne d'achat retournée) :
 *  - `return_batch_id`  : UUID du retour, FOURNI PAR LE POSTE (le web en génère un). Toutes les lignes d'un
 *                         même retour le portent : c'est la clé d'idempotence d'un renvoi.
 *  - `purchase_line_id` : la ligne d'achat retournée. UNIQUE : une ligne d'achat ne peut être retournée qu'UNE
 *                         fois, quoi qu'il arrive (deux retours simultanés, deux postes). Le retour étant l'annulation
 *                         COMPLÈTE de l'achat (D6), toutes ses lignes sont retournées ensemble ou aucune : l'achat
 *                         n'est donc annulé qu'une fois. NULLABLE : les retours d'avant le ticket n'en ont pas.
 *  - `return_date`, `device_id`.
 *
 * `purchases` :
 *  - `returned_at`      : marqueur DESCENDANT (le tirage incrémental `updated_at > since` le sert au poste).
 *  - `supplier_credit`  : part DÉJÀ PAYÉE au moment du retour = créance sur le fournisseur (compte 409). Sert à
 *                         plafonner les remboursements (`supplier_refunds`).
 *
 * Retours d'AVANT le ticket : ils ont décrémenté le stock sans toucher ni dette, ni trésorerie, ni journal. On les
 * marque « retournés » (sinon un second retour décrémenterait une seconde fois) mais on NE LEUR INVENTE ni écriture ni
 * créance : leur régularisation comptable est une décision du cabinet.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('purchase_returns', function (Blueprint $table) {
            $table->uuid('return_batch_id')->nullable()->index();
            $table->uuid('purchase_line_id')->nullable()->unique();
            $table->date('return_date')->nullable();
            $table->string('device_id', 64)->nullable();
        });

        Schema::table('purchases', function (Blueprint $table) {
            $table->timestamp('returned_at')->nullable();
            $table->decimal('supplier_credit', 14, 2)->default(0);
        });

        // Rattrapage des retours d'avant : un lot par achat, marqueur posé à la date du premier retour.
        $achats = DB::table('purchase_returns')->select('purchase_id')->distinct()->pluck('purchase_id');

        foreach ($achats as $achatId) {
            $premier = DB::table('purchase_returns')->where('purchase_id', $achatId)->min('created_at');

            DB::table('purchase_returns')->where('purchase_id', $achatId)->whereNull('return_batch_id')
                ->update(['return_batch_id' => (string) Str::uuid()]);

            DB::table('purchases')->where('id', $achatId)->update([
                'returned_at' => $premier ?? now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        Schema::table('purchases', function (Blueprint $table) {
            $table->dropColumn(['returned_at', 'supplier_credit']);
        });

        Schema::table('purchase_returns', function (Blueprint $table) {
            $table->dropUnique(['purchase_line_id']);
            $table->dropIndex(['return_batch_id']);
            $table->dropColumn(['return_batch_id', 'purchase_line_id', 'return_date', 'device_id']);
        });
    }
};
