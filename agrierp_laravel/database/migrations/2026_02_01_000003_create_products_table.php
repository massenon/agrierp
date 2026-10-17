<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Contrainte applicative (validée en Form Request/règles Livewire, pas en
 * SQL — Document 03 §3.6) : `pricing_mode='quote'` ⇒ `price_min`/
 * `price_max` doivent être null. `pricing_mode='fourchette'` ⇒ les deux
 * doivent être renseignés, `price_max >= price_min`. Jamais de "prix fixe"
 * ni de "prix au kg" (Document 00 §5.3 — exactement 2 valeurs).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('products', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('sku', 50)->unique();
            $table->string('name', 150);
            $table->foreignUuid('category_id')->constrained('product_categories')->restrictOnDelete();
            $table->string('unit', 20); // toujours une unité de pièce/comptage
            $table->enum('pricing_mode', ['fourchette', 'quote']);
            $table->decimal('price_min', 14, 2)->nullable();
            $table->decimal('price_max', 14, 2)->nullable();
            $table->decimal('tva_rate', 5, 2)->default(0);
            $table->decimal('stock_qty', 12, 2)->default(0);
            $table->decimal('alert_threshold', 12, 2)->default(0);
            $table->foreignUuid('species_id')->nullable()->constrained('livestock_species')->nullOnDelete();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->index(['species_id', 'category_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('products');
    }
};
