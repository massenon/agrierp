<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('veterinary_records', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('lot_id')->constrained('livestock_lots')->restrictOnDelete();
            $table->string('action_type', 100);
            $table->string('product_used', 150)->nullable();
            $table->string('dose', 100)->nullable();
            $table->string('vet_name', 150)->nullable();
            $table->text('symptomes')->nullable();
            $table->enum('gravite', ['legere', 'moderee', 'severe'])->nullable();
            $table->decimal('cost', 14, 2)->nullable();
            $table->date('record_date');
            $table->foreignUuid('daily_entry_id')->nullable()->constrained('livestock_daily_entries')->nullOnDelete();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('veterinary_calendar_events', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('lot_id')->constrained('livestock_lots')->restrictOnDelete();
            $table->string('task_type', 100);
            $table->date('scheduled_date');
            $table->enum('status', ['planned', 'done', 'late', 'inprogress'])->default('planned');
            $table->timestamps();
            $table->index('scheduled_date');
        });

        Schema::create('infirmary_records', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('lot_id')->constrained('livestock_lots')->restrictOnDelete();
            $table->string('sujet_ref', 50)->nullable();
            $table->text('motif');
            $table->string('isolation_level', 50)->nullable();
            $table->date('entry_date');
            $table->enum('status', ['en_cours', 'reintegre', 'deces'])->default('en_cours');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('infirmary_records');
        Schema::dropIfExists('veterinary_calendar_events');
        Schema::dropIfExists('veterinary_records');
    }
};
