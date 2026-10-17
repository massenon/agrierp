<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('livestock_daily_entries', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('lot_id')->constrained('livestock_lots')->restrictOnDelete();
            $table->date('entry_date');
            $table->unsignedInteger('achat')->default(0);
            $table->unsignedInteger('ne')->default(0);
            $table->unsignedInteger('mort')->default(0);
            $table->unsignedInteger('vente')->default(0);
            $table->unsignedInteger('don')->nullable();
            $table->unsignedInteger('effectif_final');
            $table->decimal('feed_qty_kg', 8, 2)->nullable();
            $table->foreignUuid('feed_product_id')->nullable()->constrained('products')->nullOnDelete();
            $table->unsignedInteger('weight_sample_avg_g')->nullable();
            $table->unsignedInteger('ponte_total')->nullable();
            $table->unsignedInteger('ponte_casses')->nullable();
            $table->foreignUuid('treatment_product_id')->nullable()->constrained('products')->nullOnDelete();
            $table->string('treatment_dose', 100)->nullable();
            $table->text('symptomes')->nullable();
            $table->enum('vente_sexe', ['M', 'F', 'Mixte'])->nullable();
            $table->decimal('vente_montant', 14, 2)->nullable();
            $table->timestamps();
            $table->unique(['lot_id', 'entry_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('livestock_daily_entries');
    }
};
