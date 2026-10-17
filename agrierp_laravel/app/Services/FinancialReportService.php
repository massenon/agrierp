<?php

namespace App\Services;

use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;

/**
 * Ticket 10.8 (Sprint 10) — extraction du calcul de bilan hors de
 * `Livewire\Comptabilite\Bilan` (ticket 10.5) vers ce service partagé.
 * Le hub Comptabilité affiche des KPI ("Total Actif", "Trésorerie
 * Disponible") qui recoupent EXACTEMENT ce que `Bilan` calcule déjà —
 * dupliquer cette logique dans le composant du hub aurait recréé deux
 * implémentations du même calcul pouvant un jour diverger. Un seul point
 * de vérité, appelé par les deux écrans.
 *
 * Même discipline architecturale que documentée dans `Bilan` : calculé
 * exclusivement depuis le grand livre, jamais depuis des tables métier
 * disjointes.
 */
class FinancialReportService
{
    public function bilan(string $asOfDate): array
    {
        $balances = $this->accountBalances($asOfDate);

        $immo = array_values(array_filter($balances, fn ($b) => $b['class'] === 2));
        $stocks = array_values(array_filter($balances, fn ($b) => $b['class'] === 3));
        $tresorerie = array_values(array_filter($balances, fn ($b) => $b['class'] === 5));
        $tiers = array_values(array_filter($balances, fn ($b) => $b['class'] === 4));
        $capitaux = array_values(array_filter($balances, fn ($b) => $b['class'] === 1));
        $charges = array_values(array_filter($balances, fn ($b) => $b['class'] === 6));
        $produits = array_values(array_filter($balances, fn ($b) => $b['class'] === 7));

        $creances = array_values(array_filter($tiers, fn ($b) => $b['balance'] > 0));
        $dettes = array_map(fn ($b) => ['code' => $b['code'], 'label' => $b['label'], 'balance' => -$b['balance']], array_values(array_filter($tiers, fn ($b) => $b['balance'] < 0)));

        $totalImmo = array_sum(array_column($immo, 'balance'));
        $totalStocks = array_sum(array_column($stocks, 'balance'));
        $totalCreances = array_sum(array_column($creances, 'balance'));
        $totalTresorerie = array_sum(array_column($tresorerie, 'balance'));
        $totalActifCirculant = $totalStocks + $totalCreances;

        $totalCapitaux = -array_sum(array_column($capitaux, 'balance'));
        $totalCharges = array_sum(array_column($charges, 'balance'));
        $totalProduits = -array_sum(array_column($produits, 'balance'));
        $resultat = round($totalProduits - $totalCharges, 2);
        $totalDettes = array_sum(array_column($dettes, 'balance'));

        $totalActif = round($totalImmo + $totalActifCirculant + $totalTresorerie, 2);
        $totalPassif = round($totalCapitaux + $resultat + $totalDettes, 2);

        return [
            'immo' => $immo,
            'stocks' => $stocks,
            'creances' => $creances,
            'tresorerie' => $tresorerie,
            'capitaux' => $capitaux,
            'dettes' => $dettes,
            'total_immo' => $totalImmo,
            'total_circulant' => $totalActifCirculant,
            'total_tresorerie' => $totalTresorerie,
            'total_actif' => $totalActif,
            'total_capitaux' => $totalCapitaux,
            'resultat' => $resultat,
            'total_dettes' => $totalDettes,
            'total_passif' => $totalPassif,
            'is_balanced' => abs($totalActif - $totalPassif) < 0.01,
        ];
    }

    /** Recettes (classe 7, crédit-débit) sur une période — un seul point de calcul. */
    public function produitsPeriode(string $startDate, string $endDate): float
    {
        $lines = AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->whereDate('accounting_entries.entry_date', '>=', $startDate)
            ->whereDate('accounting_entries.entry_date', '<=', $endDate)
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->where('chart_of_accounts.class', 7)
            ->selectRaw('SUM(accounting_entry_lines.credit) as total_credit, SUM(accounting_entry_lines.debit) as total_debit')
            ->first();

        return round((float) ($lines->total_credit ?? 0) - (float) ($lines->total_debit ?? 0), 2);
    }

    /**
     * Ticket 14.10 (Sprint 14) — Charges (classe 6, débit−crédit) sur une
     * période. Pendant symétrique de `produitsPeriode()`, ajouté pour le
     * Rapport Mensuel : sans lui, le résultat mensuel aurait dû être
     * recalculé localement dans le composant — soit un 2e point de calcul du
     * même concept.
     */
    public function chargesPeriode(string $startDate, string $endDate): float
    {
        $lines = AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->whereDate('accounting_entries.entry_date', '>=', $startDate)
            ->whereDate('accounting_entries.entry_date', '<=', $endDate)
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->where('chart_of_accounts.class', 6)
            ->selectRaw('SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
            ->first();

        return round((float) ($lines->total_debit ?? 0) - (float) ($lines->total_credit ?? 0), 2);
    }

    /**
     * Ticket 14.1 (Sprint 14) — Grand Livre : écritures chronologiques d'UN
     * compte sur une période, avec solde progressif.
     *
     * Placé ici et non dans le composant Livewire pour la même raison que
     * `bilan()` (ticket 10.8) : la Balance Générale et les États Financiers
     * (écrans suivants du prototype, `balance-generale.html` /
     * `etats-financiers.html`) recalculent exactement ces mêmes soldes par
     * compte — un seul point de vérité dès maintenant, plutôt que trois
     * implémentations qui divergeront.
     *
     * Le solde d'ouverture est calculé depuis TOUTES les écritures
     * antérieures à `$startDate`, jamais depuis une valeur saisie ou figée :
     * changer la période recalcule réellement l'ouverture.
     *
     * @return array{account: ?ChartOfAccount, is_debit_nature: bool, opening_balance: float, lines: array<int, array{date: string, reference: string, label: string, debit: float, credit: float, running_balance: float}>, total_debit: float, total_credit: float, closing_balance: float}
     */
    public function grandLivre(string $accountId, string $startDate, string $endDate, ?string $search = null): array
    {
        $account = $accountId !== '' ? ChartOfAccount::find($accountId) : null;

        $empty = [
            'account' => null,
            'is_debit_nature' => true,
            'opening_balance' => 0.0,
            'lines' => [],
            'total_debit' => 0.0,
            'total_credit' => 0.0,
            'closing_balance' => 0.0,
        ];

        if (! $account) {
            return $empty;
        }

        $isDebitNature = $this->isDebitNature($account);

        $before = $this->accountLinesQuery($accountId)
            ->whereDate('accounting_entries.entry_date', '<', $startDate)
            ->selectRaw('SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
            ->first();

        $openingDebit = (float) ($before->total_debit ?? 0);
        $openingCredit = (float) ($before->total_credit ?? 0);
        $openingBalance = round($isDebitNature ? $openingDebit - $openingCredit : $openingCredit - $openingDebit, 2);

        $rows = $this->accountLinesQuery($accountId)
            ->whereDate('accounting_entries.entry_date', '>=', $startDate)
            ->whereDate('accounting_entries.entry_date', '<=', $endDate)
            ->when(
                $search !== null && $search !== '',
                fn ($q) => $q->where('accounting_entries.reference', 'like', '%'.$search.'%')
            )
            ->orderBy('accounting_entries.entry_date')
            ->orderBy('accounting_entries.created_at')
            ->select([
                'accounting_entries.entry_date',
                'accounting_entries.reference',
                'accounting_entry_lines.debit',
                'accounting_entry_lines.credit',
            ])
            ->get();

        $balance = $openingBalance;
        $totalDebit = 0.0;
        $totalCredit = 0.0;
        $lines = [];

        foreach ($rows as $row) {
            $debit = (float) $row->debit;
            $credit = (float) $row->credit;
            $totalDebit += $debit;
            $totalCredit += $credit;

            // Même convention de `reference` que `JournalComptable` (ticket 10.4) :
            // "OD-2026-0001 — Libellé" dans un seul champ texte, pas de colonne
            // libellé séparée dans le schéma.
            $refParts = explode('—', (string) $row->reference, 2);

            $balance = round($balance + ($isDebitNature ? $debit - $credit : $credit - $debit), 2);

            $lines[] = [
                'date' => (string) $row->entry_date,
                'reference' => trim($refParts[0] ?? ''),
                'label' => trim($refParts[1] ?? ''),
                'debit' => $debit,
                'credit' => $credit,
                'running_balance' => $balance,
            ];
        }

        return [
            'account' => $account,
            'is_debit_nature' => $isDebitNature,
            'opening_balance' => $openingBalance,
            'lines' => $lines,
            'total_debit' => round($totalDebit, 2),
            'total_credit' => round($totalCredit, 2),
            'closing_balance' => $balance,
        ];
    }

    /**
     * Ticket 14.6 (Sprint 14) — Compte de Résultat, cascade SYSCOHADA :
     * Ventes → Marge Commerciale → EBE → Résultat d'Exploitation → RAO →
     * Résultat Net.
     *
     * ⚠️ IDENTITÉ AVEC LE BILAN GARANTIE PAR CONSTRUCTION, PAS PAR
     * COÏNCIDENCE — exigence explicite du prototype : *"Le Résultat Net est
     * calculé depuis la même source que celui affiché au Bilan — toujours
     * strictement identiques."* Deux moyens l'assurent :
     *   1. même fenêtre que `bilan()` : tout ce qui précède `$asOfDate`
     *      (et non une période glissante qui divergerait) ;
     *   2. la ligne « autres charges » ABSORBE tout compte de classe 6 non
     *      classé ailleurs dans la cascade. La somme des lignes est donc
     *      identiquement `produits(7) − charges(6)`, quel que soit le plan
     *      comptable réellement utilisé — aucun compte ne peut « tomber »
     *      hors du calcul en passant inaperçu.
     *
     * @return array<string, float>
     */
    public function compteResultat(string $asOfDate): array
    {
        $balances = $this->accountBalances($asOfDate);

        // Solde débiteur (charges) / créditeur (produits) par préfixe de compte.
        $charges = fn (string ...$prefixes) => round(array_sum(array_map(
            fn ($b) => $b['class'] === 6 && $this->hasPrefix($b['code'], $prefixes) ? $b['balance'] : 0,
            $balances
        )), 2);

        $produits = fn (string ...$prefixes) => round(-array_sum(array_map(
            fn ($b) => $b['class'] === 7 && $this->hasPrefix($b['code'], $prefixes) ? $b['balance'] : 0,
            $balances
        )), 2);

        $totalCharges = round(array_sum(array_map(fn ($b) => $b['class'] === 6 ? $b['balance'] : 0, $balances)), 2);
        $totalProduits = round(-array_sum(array_map(fn ($b) => $b['class'] === 7 ? $b['balance'] : 0, $balances)), 2);

        $achats = $charges('60');
        $personnel = $charges('66');
        $dotations = $charges('68');
        $chargesFinancieres = $charges('67');
        $produitsFinanciers = $produits('77');

        // Produits d'exploitation = classe 7 hors produits financiers.
        $ventes = round($totalProduits - $produitsFinanciers, 2);

        // Tout le reste de la classe 6 — jamais perdu en route.
        $autresCharges = round($totalCharges - $achats - $personnel - $dotations - $chargesFinancieres, 2);

        $margeCommerciale = round($ventes - $achats, 2);
        $ebe = round($margeCommerciale - $personnel, 2);
        $resultatExploitation = round($ebe - $dotations, 2);
        $resultatFinancier = round($produitsFinanciers - $chargesFinancieres, 2);
        $rao = round($resultatExploitation + $resultatFinancier, 2);
        $resultatNet = round($rao - $autresCharges, 2);

        return [
            'ventes' => $ventes,
            'achats' => $achats,
            'marge_commerciale' => $margeCommerciale,
            'charges_personnel' => $personnel,
            'ebe' => $ebe,
            'dotations' => $dotations,
            'resultat_exploitation' => $resultatExploitation,
            'resultat_financier' => $resultatFinancier,
            'rao' => $rao,
            'autres_charges' => $autresCharges,
            'resultat_net' => $resultatNet,
        ];
    }

    /**
     * Ticket 14.6 — TAFIRE simplifié (tableau des flux de trésorerie).
     *
     * ⚠️ LE CONTRÔLE DE COHÉRENCE EST RÉELLEMENT FALSIFIABLE — c'est tout son
     * intérêt. Le prototype écrivait :
     *     tresorerieOuverture = tresorerieCloture - variation
     *     tresorerieCloture   = tresorerieOuverture + variation
     * ce qui rend l'égalité vraie par pure algèbre, quelle que soit la
     * réalité comptable : une « vérification » qui ne peut jamais échouer ne
     * vérifie rien. Ici la trésorerie d'ouverture est le **solde réel du
     * grand livre** à la veille de la période, la clôture est **dérivée par
     * les flux**, et les deux sont comparées ensuite à la trésorerie du
     * Bilan. Si une écriture est déséquilibrée ou un compte mal classé, le
     * contrôle échoue — comme il se doit.
     *
     * Note sur les amortissements : `bilan()` renvoie des immobilisations
     * NETTES (classe 2 = brut moins amortissements). Le flux d'investissement
     * retranche donc `dotations` de la variation d'immobilisations pour
     * n'isoler que les acquisitions réelles — sans quoi les dotations
     * seraient comptées deux fois (une fois réintégrées au flux
     * d'exploitation, une fois via la baisse de l'actif net).
     *
     * @return array<string, float|bool>
     */
    public function tafire(string $startDate, string $endDate): array
    {
        $veille = \Carbon\Carbon::parse($startDate)->subDay()->format('Y-m-d');

        $ouverture = $this->bilan($veille);
        $cloture = $this->bilan($endDate);

        $resultat = $this->compteResultat($endDate);
        $resultatNet = $resultat['resultat_net'];
        $dotations = $resultat['dotations'];

        $bfrOuverture = round($ouverture['total_circulant'] - $ouverture['total_dettes'], 2);
        $bfrCloture = round($cloture['total_circulant'] - $cloture['total_dettes'], 2);
        $variationBfr = round($bfrCloture - $bfrOuverture, 2);

        $fluxExploitation = round($resultatNet + $dotations - $variationBfr, 2);

        // Acquisitions réelles = variation des immobilisations NETTES + dotations.
        $acquisitions = round(($cloture['total_immo'] - $ouverture['total_immo']) + $dotations, 2);
        $fluxInvestissement = round(-$acquisitions, 2);

        $fluxFinancement = round($cloture['total_capitaux'] - $ouverture['total_capitaux'], 2);

        $variationTresorerie = round($fluxExploitation + $fluxInvestissement + $fluxFinancement, 2);

        $tresorerieOuverture = round($ouverture['total_tresorerie'], 2);          // solde RÉEL du grand livre
        $tresorerieClotureCalculee = round($tresorerieOuverture + $variationTresorerie, 2);
        $tresorerieClotureBilan = round($cloture['total_tresorerie'], 2);         // comparée, jamais imposée

        $ecart = round($tresorerieClotureCalculee - $tresorerieClotureBilan, 2);

        return [
            'resultat_net' => $resultatNet,
            'dotations' => $dotations,
            'variation_bfr' => $variationBfr,
            'flux_exploitation' => $fluxExploitation,
            'flux_investissement' => $fluxInvestissement,
            'flux_financement' => $fluxFinancement,
            'variation_tresorerie' => $variationTresorerie,
            'tresorerie_ouverture' => $tresorerieOuverture,
            'tresorerie_cloture' => $tresorerieClotureCalculee,
            'tresorerie_cloture_bilan' => $tresorerieClotureBilan,
            'ecart' => $ecart,
            'is_coherent' => abs($ecart) < 0.01,
        ];
    }

    /** Le code de compte commence-t-il par l'un des préfixes donnés ? */
    private function hasPrefix(string $code, array $prefixes): bool
    {
        foreach ($prefixes as $prefix) {
            if (str_starts_with($code, $prefix)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Ticket 14.5 (Sprint 14) — Balance Générale : pour chaque compte réellement
     * mouvementé, Solde d'Ouverture / Mouvements de la Période / Solde Final,
     * plus les totaux et le contrôle d'équilibre.
     *
     * ⚠️ RÈGLE DE PLACEMENT EN COLONNE — décision de conception à ne pas
     * inverser : le solde final est placé en Débit ou en Crédit selon le
     * **signe réel du solde**, JAMAIS selon la nature du compte. Placer selon
     * la nature ferait disparaître silencieusement des deux colonnes tout
     * compte en anomalie (un compte débiteur par nature se retrouvant en
     * position créditrice) — or une Balance sert précisément à révéler ce
     * genre d'anomalie, jamais à la masquer. `isDebitNature()` n'est donc
     * volontairement PAS utilisée ici.
     *
     * Calculé exclusivement depuis `accounting_entry_lines`, comme `bilan()`
     * et `grandLivre()` — jamais depuis des tables métier disjointes.
     *
     * @return array{rows: array<int, array<string, mixed>>, total_opening_debit: float, total_opening_credit: float, total_period_debit: float, total_period_credit: float, total_final_debit: float, total_final_credit: float, ecart: float, is_balanced: bool}
     */
    public function balanceGenerale(string $startDate, string $endDate): array
    {
        $opening = $this->sumsByAccount(null, $startDate);       // strictement avant le début de période
        $period = $this->sumsByAccount($startDate, $endDate);

        $accounts = $opening + $period;   // union par clé (id de compte)
        uasort($accounts, fn ($a, $b) => strcmp((string) $a['code'], (string) $b['code']));

        $rows = [];
        $totals = [
            'opening_debit' => 0.0, 'opening_credit' => 0.0,
            'period_debit' => 0.0, 'period_credit' => 0.0,
            'final_debit' => 0.0, 'final_credit' => 0.0,
        ];

        foreach ($accounts as $id => $meta) {
            $openingNet = round(
                (float) ($opening[$id]['debit'] ?? 0) - (float) ($opening[$id]['credit'] ?? 0),
                2
            );

            // Le solde d'ouverture est un NET, présenté dans une seule des deux
            // colonnes — même convention que le prototype.
            $openingDebit = $openingNet > 0 ? $openingNet : 0.0;
            $openingCredit = $openingNet < 0 ? -$openingNet : 0.0;

            // Les mouvements de la période, eux, restent des cumuls BRUTS : un
            // même compte peut avoir été mouvementé dans les deux sens sur la
            // période (ex. la Caisse), et les deux colonnes doivent le montrer.
            $periodDebit = round((float) ($period[$id]['debit'] ?? 0), 2);
            $periodCredit = round((float) ($period[$id]['credit'] ?? 0), 2);

            $finalNet = round(($openingDebit + $periodDebit) - ($openingCredit + $periodCredit), 2);
            $finalDebit = $finalNet > 0 ? $finalNet : 0.0;
            $finalCredit = $finalNet < 0 ? -$finalNet : 0.0;

            if ($openingNet == 0.0 && $periodDebit == 0.0 && $periodCredit == 0.0) {
                continue;   // compte sans aucun mouvement réel — hors balance
            }

            $rows[] = [
                'code' => $meta['code'],
                'label' => $meta['label'],
                'class' => $meta['class'],
                'opening_debit' => $openingDebit,
                'opening_credit' => $openingCredit,
                'period_debit' => $periodDebit,
                'period_credit' => $periodCredit,
                'final_debit' => $finalDebit,
                'final_credit' => $finalCredit,
            ];

            $totals['opening_debit'] += $openingDebit;
            $totals['opening_credit'] += $openingCredit;
            $totals['period_debit'] += $periodDebit;
            $totals['period_credit'] += $periodCredit;
            $totals['final_debit'] += $finalDebit;
            $totals['final_credit'] += $finalCredit;
        }

        $ecart = round($totals['final_debit'] - $totals['final_credit'], 2);

        return [
            'rows' => $rows,
            'total_opening_debit' => round($totals['opening_debit'], 2),
            'total_opening_credit' => round($totals['opening_credit'], 2),
            'total_period_debit' => round($totals['period_debit'], 2),
            'total_period_credit' => round($totals['period_credit'], 2),
            'total_final_debit' => round($totals['final_debit'], 2),
            'total_final_credit' => round($totals['final_credit'], 2),
            'ecart' => $ecart,
            'is_balanced' => abs($ecart) < 0.01,
        ];
    }

    /**
     * Cumuls débit/crédit par compte sur un intervalle de dates.
     * `$from` à `null` = tout ce qui précède strictement `$to` (solde
     * d'ouverture). Deux requêtes distinctes plutôt qu'un `SUM(CASE WHEN …)` :
     * `whereDate()` compare des dates de façon portable, là où une comparaison
     * brute de chaîne dépend de la sérialisation du pilote — le piège
     * exact rencontré au ticket 14.4 sur `livestock_daily_entries`.
     *
     * @return array<string, array{code: string, label: string, class: int, debit: float, credit: float}>
     */
    private function sumsByAccount(?string $from, string $to): array
    {
        $query = AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->where('accounting_entries.is_active', true);

        if ($from === null) {
            $query->whereDate('accounting_entries.entry_date', '<', $to);
        } else {
            $query->whereDate('accounting_entries.entry_date', '>=', $from)
                ->whereDate('accounting_entries.entry_date', '<=', $to);
        }

        return $query
            ->groupBy('chart_of_accounts.id', 'chart_of_accounts.code', 'chart_of_accounts.label', 'chart_of_accounts.class')
            ->selectRaw('chart_of_accounts.id as account_id, chart_of_accounts.code, chart_of_accounts.label, chart_of_accounts.class, SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
            ->get()
            ->mapWithKeys(fn ($l) => [$l->account_id => [
                'code' => (string) $l->code,
                'label' => (string) $l->label,
                'class' => (int) $l->class,
                'debit' => (float) $l->total_debit,
                'credit' => (float) $l->total_credit,
            ]])
            ->all();
    }

    /**
     * Sens naturel du compte, pour le signe du solde progressif.
     *
     * Le prototype (`grand-livre.html`) portait deux listes de codes écrites
     * en dur — `COMPTES_DEBITEURS_PAR_NATURE = 531,521,5212,601,661,411` et
     * `COMPTES_CREDITEURS_PAR_NATURE = 701,401`. Une liste figée de 8 codes
     * ne peut pas fonctionner sur un plan comptable réel qui en contiendra
     * plusieurs centaines : la règle est donc dérivée de la classe SYSCOHADA,
     * ce qui reproduit exactement le classement du prototype pour ses 8
     * comptes (531, 521x, 601, 661, 411 débiteurs ; 701, 401 créditeurs) tout en
     * restant valable pour tout compte ajouté ensuite.
     *
     * Classe 4 (tiers) : seul cas ambigu. TICKET 15.21 — l'ancienne règle
     * (`41x` débiteur, tout le reste créditeur) lisait mal quatre comptes du plan :
     * `409` Fournisseurs débiteurs (créance) et `445` TVA récupérable étaient
     * pris pour des dettes (solde progressif de -2000 pour 2000 de débit), et
     * `419` Avances reçues (dette envers le client), qui commence par `41`,
     * pour une créance. Règle actuelle — PROPOSITION À FAIRE VALIDER PAR LE
     * CABINET FAGUEZ, compte par compte dans `NatureComptesTiersTest` :
     *   débitrices : `409x`, `41x` hors `419x`, `445x` (TVA récupérable) ;
     *   créditrices : tout le reste de la classe 4 (`40x` hors `409x`, `419x`,
     *   `43x`, `443x` TVA facturée, `447x`…).
     * Sous-comptes de TVA absents du plan semé : `4456` suit `445` (débiteur) ;
     * `4457` est EXCEPTÉ de `445` et traité en créditeur (TVA collectée dans le
     * plan comptable français, seul où ce sous-compte existe) — AMBIGU : la
     * règle « 445 = récupérable » du plan en base le rangerait en débiteur ;
     * à valider par le cabinet. Autres sens de la même famille :
     * `139` (perte) débiteur ; `28x`/`29x`/`39x`/`59x` (amortissements et
     * dépréciations) créditeurs. Classes 8 et 9 : règle d'origine conservée
     * (débiteur), non revue ici.
     */
    private function isDebitNature(ChartOfAccount $account): bool
    {
        return self::natureDebitrice((string) $account->code, (int) $account->class);
    }

    /** Sens naturel d'un compte (true = débiteur). Un seul point de décision, voir `isDebitNature()`. */
    public static function natureDebitrice(string $code, int $classe): bool
    {
        $commencePar = fn (string ...$prefixes) => array_reduce(
            $prefixes,
            fn (bool $acc, string $p) => $acc || str_starts_with($code, $p),
            false
        );

        return match ($classe) {
            1 => $commencePar('139'),
            2 => ! $commencePar('28', '29'),
            3 => ! $commencePar('39'),
            4 => $commencePar('409')
                || ($commencePar('445') && ! $commencePar('4457'))
                || ($commencePar('41') && ! $commencePar('419')),
            5 => ! $commencePar('59'),
            7 => false,
            default => true,
        };
    }

    /** Lignes actives d'un compte donné — base commune ouverture/période. */
    private function accountLinesQuery(string $accountId)
    {
        return AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->where('accounting_entry_lines.account_id', $accountId);
    }

    /** Solde de chaque compte (débit-crédit) à la date choisie. */
    private function accountBalances(string $asOfDate): array
    {
        $lines = AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->whereDate('accounting_entries.entry_date', '<=', $asOfDate)
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->selectRaw('chart_of_accounts.id as account_id, chart_of_accounts.code, chart_of_accounts.label, chart_of_accounts.class, SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
            ->groupBy('chart_of_accounts.id', 'chart_of_accounts.code', 'chart_of_accounts.label', 'chart_of_accounts.class')
            ->get();

        return $lines->map(fn ($l) => [
            'code' => $l->code,
            'label' => $l->label,
            'class' => (int) $l->class,
            'balance' => round((float) $l->total_debit - (float) $l->total_credit, 2),
        ])->all();
    }
}
