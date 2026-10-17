<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ÉCART DOCUMENTÉ : `company_settings` (§22) ne prévoit que la config
 * SMTP. Extension nécessaire pour piloter l'envoi SMS (Twilio et/ou
 * Vonage, au choix de l'utilisateur) depuis Paramètres, comme demandé
 * explicitement. Secrets stockés chiffrés (`_encrypted`, cast `encrypted`
 * du modèle), jamais en clair — même principe que `smtp_password_encrypted`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->enum('sms_provider', ['twilio', 'vonage'])->nullable()->after('smtp_password_encrypted');
            $table->string('twilio_account_sid', 100)->nullable();
            $table->text('twilio_auth_token_encrypted')->nullable();
            $table->string('twilio_from_number', 30)->nullable();
            $table->string('vonage_api_key', 100)->nullable();
            $table->text('vonage_api_secret_encrypted')->nullable();
            $table->string('vonage_from_name', 30)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->dropColumn([
                'sms_provider', 'twilio_account_sid', 'twilio_auth_token_encrypted', 'twilio_from_number',
                'vonage_api_key', 'vonage_api_secret_encrypted', 'vonage_from_name',
            ]);
        });
    }
};
