<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.26 (Sprint 14) — CAPITALISATION des immobilisations.
 *
 * 🔴 DEFAUT QU'AURAIT INTRODUIT LE REGISTRE SANS CETTE ETAPE. `bilan()` somme
 * TOUTE la classe 2 pour son « Actif Immobilise », amortissements 281 compris
 * — ce qui est la bonne formule (VNC = brut moins amortissement), a condition
 * que le BRUT soit reellement au grand livre. Or aucun flux ne debitait jamais
 * 221/241/244 : les achats vont en charges (601). Passer une dotation aurait
 * donc credite 281 face a un brut nul et affiche un Actif Immobilise NEGATIF
 * au Bilan.
 *
 * L'ACQUISITION DOIT DONC S'ECRIRE ELLE AUSSI :
 *     Debit  2xx (221/241/244) ..... valeur d'acquisition
 *     Credit contrepartie .......... tresorerie payante, ou 401 si a credit
 *
 * `is_capitalized` distingue les biens reellement entres en comptabilite de
 * ceux saisis en REPRISE D'ANTERIORITE (deja en service avant la mise en
 * route de l'ERP). Ces derniers alimentent la Note 2 mais ne sont ni
 * capitalises ni amortis au grand livre : leur valeur et leur amortissement
 * anterieur relevent d'un bilan d'ouverture que ce projet n'importe nulle part
 * — limite reelle, signalee a l'ecran, jamais comblee par une ecriture
 * inventee au credit du Capital.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('fixed_assets', function (Blueprint $table) {
            $table->boolean('is_capitalized')->default(false)->after('method');
            $table->uuid('acquisition_entry_id')->nullable()->after('is_capitalized');
        });
    }

    public function down(): void
    {
        Schema::table('fixed_assets', function (Blueprint $table) {
            $table->dropColumn(['is_capitalized', 'acquisition_entry_id']);
        });
    }
};
