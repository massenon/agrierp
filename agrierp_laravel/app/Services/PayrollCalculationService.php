<?php

namespace App\Services;

use App\Models\CompanySetting;
use App\Models\IncomeTaxBracket;

/**
 * Ticket 14.38 (Sprint 14) — CALCUL DE PAIE, droit béninois.
 *
 * Point de vérité unique du bulletin : `GestionPaie`, les états de paie et les
 * écritures comptables lisent tous le même calcul. Recopier une formule dans
 * un écran, comme le faisait le taux CNSS jusqu'ici, garantit qu'une révision
 * de taux en oubliera un.
 *
 * ⚠️ LA DISTINCTION QUI STRUCTURE TOUT : retenues salariales contre charges
 * patronales.
 *
 *   RETENUES (prélevées SUR le salarié, diminuent son net) :
 *     - CNSS salariale ...... 3,6 % du brut
 *     - ITS / IR-PTS ........ barème progressif sur le net imposable
 *
 *   CHARGES PATRONALES (payées EN PLUS par l'employeur, ne touchent pas le
 *   net mais augmentent le coût du travail) :
 *     - VPS ................. 4 % du brut (2 % si structure d'enseignement privé)
 *     - CNSS pensions ....... 6,4 %
 *     - CNSS prestations familiales ... 9 %
 *     - CNSS risques professionnels ... 1 à 4 % selon le niveau de risque
 *
 * Les confondre produit un bulletin qui équilibre en apparence : mettre une
 * charge patronale en retenue sous-paie le salarié ; l'inverse sous-déclare
 * l'entreprise. Aucune des deux erreurs ne lève d'alerte.
 *
 * ⚠️ ASSIETTE DE L'ITS : le NET IMPOSABLE, c'est-à-dire le brut MOINS la CNSS
 * salariale — jamais le brut. Calculer l'ITS sur le brut le surestimerait
 * systématiquement, d'autant plus que le salaire est élevé.
 *
 * ⚠️ BARÈME EN BASE, PAS EN DUR (`income_tax_brackets`). Un barème fiscal
 * change par loi de finances ; le figer dans le code imposerait un
 * redéploiement à chaque révision et rendrait invisible la version réellement
 * appliquée à un bulletin donné. **Le barème semé doit être validé par le
 * client avant toute paie réelle** : ni le prototype ni le CDC ne le
 * documentent.
 */
class PayrollCalculationService
{
    /**
     * Décompose une paie à partir du brut et des jours d'absence.
     *
     * @return array{
     *     brut: float, retenue_absence: float, salaire_du: float,
     *     cnss_salariale: float, net_imposable: float, its: float, net: float,
     *     vps: float, cnss_patronale_pension: float, cnss_patronale_famille: float,
     *     cnss_patronale_risque: float, total_charges_patronales: float,
     *     cout_employeur: float, bareme_its_renseigne: bool
     * }
     */
    public function calculer(float $brut, int $joursAbsence = 0, int $joursOuvres = 26): array
    {
        $parametres = CompanySetting::first();

        $brut = round($brut, 2);

        // L'absence réduit le salaire réellement dû. Ce n'est pas une retenue
        // reversée à un tiers : elle n'a pas de contrepartie, elle diminue la
        // base de tout le reste.
        $retenueAbsence = $joursOuvres > 0
            ? round($brut / $joursOuvres * max(0, $joursAbsence), 2)
            : 0.0;

        $salaireDu = round(max(0, $brut - $retenueAbsence), 2);

        $tauxCnssSalarie = (float) ($parametres->cnss_employee_rate ?? 3.6);
        $cnssSalariale = round($salaireDu * $tauxCnssSalarie / 100, 2);

        // ⚠️ Assiette de l'ITS : le salaire dû MOINS la cotisation sociale
        // salariale — le net imposable, jamais le brut.
        $netImposable = round(max(0, $salaireDu - $cnssSalariale), 2);

        $bareme = IncomeTaxBracket::where('is_active', true)->orderBy('from_amount')->get();
        $its = $this->impotProgressif($netImposable, $bareme);

        $net = round($netImposable - $its, 2);

        // --- Charges patronales : elles n'entrent PAS dans le net -----------
        $vps = round($salaireDu * (float) ($parametres->vps_rate ?? 4) / 100, 2);
        $pension = round($salaireDu * (float) ($parametres->cnss_employer_pension_rate ?? 6.4) / 100, 2);
        $famille = round($salaireDu * (float) ($parametres->cnss_employer_family_rate ?? 9) / 100, 2);
        $risque = round($salaireDu * (float) ($parametres->cnss_employer_risk_rate ?? 2) / 100, 2);

        $chargesPatronales = round($vps + $pension + $famille + $risque, 2);

        return [
            'brut' => $brut,
            'retenue_absence' => $retenueAbsence,
            'salaire_du' => $salaireDu,
            'cnss_salariale' => $cnssSalariale,
            'net_imposable' => $netImposable,
            'its' => $its,
            'net' => $net,
            'vps' => $vps,
            'cnss_patronale_pension' => $pension,
            'cnss_patronale_famille' => $famille,
            'cnss_patronale_risque' => $risque,
            'total_charges_patronales' => $chargesPatronales,
            // Ce que le poste coûte réellement : le salaire dû + tout ce que
            // l'employeur verse par-dessus.
            'cout_employeur' => round($salaireDu + $chargesPatronales, 2),
            // ⚠️ Rendu VISIBLE plutôt que masqué par un zéro : un ITS nul
            // parce qu'aucun barème n'est renseigné n'est pas un ITS nul parce
            // que le salaire est sous le seuil d'imposition.
            'bareme_its_renseigne' => $bareme->isNotEmpty(),
        ];
    }

    /**
     * Impôt progressif PAR TRANCHES.
     *
     * ⚠️ CHAQUE TRANCHE N'EST TAXÉE QUE SUR SA PROPRE PORTION, jamais le
     * revenu entier au taux de la tranche atteinte. C'est l'erreur classique du
     * calcul progressif : elle produit un saut d'impôt brutal au passage d'un
     * seuil, et peut rendre une augmentation de salaire défavorable au
     * salarié — un résultat absurde que le barème progressif existe justement
     * pour éviter.
     *
     * @param  \Illuminate\Support\Collection<int, IncomeTaxBracket>  $bareme
     */
    private function impotProgressif(float $netImposable, $bareme): float
    {
        if ($netImposable <= 0 || $bareme->isEmpty()) {
            return 0.0;
        }

        $impot = 0.0;

        foreach ($bareme as $tranche) {
            $plancher = (float) $tranche->from_amount;
            $plafond = $tranche->to_amount !== null ? (float) $tranche->to_amount : INF;

            if ($netImposable <= $plancher) {
                break;
            }

            $portion = min($netImposable, $plafond) - $plancher;

            if ($portion > 0) {
                $impot += $portion * (float) $tranche->rate / 100;
            }
        }

        return round($impot, 2);
    }
}
