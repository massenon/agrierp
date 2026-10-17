<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Table singleton (une seule ligne), avancée pour ce ticket suite à une
 * demande explicite : l'envoi d'email doit être piloté par une config
 * SMTP réelle en Paramètres (pas seulement `.env`), et l'envoi de SMS par
 * des clés API Twilio/Vonage également modifiables en Paramètres.
 *
 * Base reprise à l'identique de `FULL_MIGRATIONS_DATABASE.md` §22.
 * L'écran complet "Données Entreprise" (nom, logo, IFU, RCCM...) reste un
 * ticket séparé (Sprint 11) — seuls les champs SMTP déjà documentés sont
 * exposés dans l'écran construit ici (Intégrations & Notifications).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('company_settings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('company_name', 150)->default('FERME ÉCOLE OLOUWACHEGOUN');
            $table->string('promoter_name', 150)->nullable();
            $table->string('address', 255)->nullable();
            $table->string('phone', 30)->nullable();
            $table->string('email', 150)->nullable();
            $table->string('ifu', 50)->nullable();
            $table->string('rccm', 50)->nullable();
            $table->string('smtp_host', 150)->nullable();
            $table->unsignedSmallInteger('smtp_port')->nullable();
            $table->string('smtp_security', 10)->nullable();
            $table->string('smtp_user', 150)->nullable();
            $table->text('smtp_password_encrypted')->nullable();
            $table->string('logo_path', 255)->nullable();
            $table->string('favicon_path', 255)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('company_settings');
    }
};
