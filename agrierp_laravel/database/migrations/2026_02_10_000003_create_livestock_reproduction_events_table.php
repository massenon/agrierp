<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('livestock_reproduction_events', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('lot_id')->constrained('livestock_lots')->restrictOnDelete();
            $table->string('mother_ref', 50);
            $table->string('sire_ref', 50)->nullable();
            $table->date('saillie_date');
            $table->date('palpation_date')->nullable();
            $table->date('mise_bas_date_expected')->nullable();
            $table->date('mise_bas_date_actual')->nullable();
            $table->date('sevrage_date_expected')->nullable();
            $table->unsignedInteger('nes_vivants')->nullable();
            $table->unsignedInteger('nes_morts')->nullable();
            $table->enum('status', ['en_cours', 'termine', 'echec'])->default('en_cours');
            $table->timestamps();
            $table->index(['lot_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('livestock_reproduction_events');
    }
};
