<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket 14.38 (Sprint 14) — TVA ACTIVABLE et parametres de PAIE (Benin).
 *
 * TVA : toutes les exploitations ne sont pas assujetties. Une ferme sous le
 * regime du micro-entrepreneur ou exoneree ne collecte pas de TVA, et
 * afficher des montants TTC lui presenterait des chiffres faux. Le drapeau
 * pilote l'affichage (TTC contre HT) ET la generation des ecritures : quand la
 * TVA est desactivee, aucune ligne 443/445 n'est produite.
 *
 * PAIE : charges patronales beninoises, absentes jusqu'ici alors que la paie
 * ne retenait que la CNSS salariale (3,6 %).
 *   - VPS (Versement Patronal sur Salaires) : 4 % pour les entreprises
 *     ordinaires, 2 % pour les structures privees d'enseignement. Cette
 *     exploitation etant une FERME ECOLE, le taux applicable doit etre
 *     tranche par le client — d'ou un parametre, jamais une valeur en dur.
 *   - CNSS patronale : 6,4 % (pensions) + 9 % (prestations familiales)
 *     + 1 a 4 % (risques professionnels, selon le niveau de risque de
 *     l'entreprise — d'ou un parametre).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->boolean('tva_enabled')->default(true)->after('rccm');
            $table->decimal('tva_default_rate', 5, 2)->default(18)->after('tva_enabled');

            $table->decimal('vps_rate', 5, 2)->default(4)->after('tva_default_rate');
            $table->decimal('cnss_employee_rate', 5, 2)->default(3.6)->after('vps_rate');
            $table->decimal('cnss_employer_pension_rate', 5, 2)->default(6.4)->after('cnss_employee_rate');
            $table->decimal('cnss_employer_family_rate', 5, 2)->default(9)->after('cnss_employer_pension_rate');
            $table->decimal('cnss_employer_risk_rate', 5, 2)->default(2)->after('cnss_employer_family_rate');
        });
    }

    public function down(): void
    {
        Schema::table('company_settings', function (Blueprint $table) {
            $table->dropColumn([
                'tva_enabled', 'tva_default_rate', 'vps_rate', 'cnss_employee_rate',
                'cnss_employer_pension_rate', 'cnss_employer_family_rate', 'cnss_employer_risk_rate',
            ]);
        });
    }
};
