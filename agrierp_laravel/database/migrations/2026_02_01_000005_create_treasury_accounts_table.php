<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('treasury_accounts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->enum('type', ['caisse', 'banque', 'mobile_money']);
            $table->string('label', 100);
            $table->string('account_code', 20);
            $table->string('bank_name', 100)->nullable();
            $table->string('operator_name', 100)->nullable();
            $table->string('rib', 100)->nullable();
            $table->string('phone_number', 30)->nullable();
            $table->decimal('balance', 14, 2)->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('treasury_accounts');
    }
};
