<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.38 (Sprint 14) — charges beninoises sur le bulletin de paie.
 *
 * Le bulletin ne portait que la CNSS salariale (3,6 %). Deux familles
 * manquaient entierement :
 *
 * RETENUES SALARIALES (deduites du net verse)
 *   - `its_deduction` : Impot sur les Traitements et Salaires, retenu a la
 *     source, progressif, assis sur le net imposable APRES CNSS salariale.
 *
 * CHARGES PATRONALES (payees EN PLUS par l'employeur, jamais deduites du
 * salarie — elles ne reduisent pas le net mais augmentent le cout du travail)
 *   - `vps_employer` : Versement Patronal sur Salaires (2 % enseignement
 *     prive, 4 % autres), assis sur le brut, sans plafond ;
 *   - `cnss_employer_pension` : 6,4 % ;
 *   - `cnss_employer_family` : 9 % (prestations familiales) ;
 *   - `cnss_employer_risk` : 1 a 4 % (risques professionnels).
 *
 * ⚠️ LA DISTINCTION EST LA CLE DE VOUTE DU CALCUL. Confondre les deux
 * familles produit un bulletin qui equilibre en apparence : les retenues
 * DIMINUENT le net du salarie, les charges patronales l'AUGMENTENT le cout
 * pour l'employeur sans toucher au net. Les melanger sous-payerait le salarie
 * ou sous-declarerait l'entreprise.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('payslips', function (Blueprint $table) {
            $table->decimal('its_deduction', 14, 2)->default(0)->after('cnss_deduction');
            $table->decimal('vps_employer', 14, 2)->default(0)->after('its_deduction');
            $table->decimal('cnss_employer_pension', 14, 2)->default(0)->after('vps_employer');
            $table->decimal('cnss_employer_family', 14, 2)->default(0)->after('cnss_employer_pension');
            $table->decimal('cnss_employer_risk', 14, 2)->default(0)->after('cnss_employer_family');
        });
    }

    public function down(): void
    {
        Schema::table('payslips', function (Blueprint $table) {
            $table->dropColumn([
                'its_deduction', 'vps_employer', 'cnss_employer_pension',
                'cnss_employer_family', 'cnss_employer_risk',
            ]);
        });
    }
};
