<?php

namespace App\Services;

use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use Carbon\Carbon;

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
    /**
     * Tickets EX1 / EX2 — écritures d'À-NOUVEAU : elles portent l'OUVERTURE d'un exercice, jamais un mouvement de sa
     * période. `ran` = report écrit à la clôture de l'exercice précédent (ou à-nouveau initial des reprises, Q7) ;
     * `ran_reversal` = sa contre-passation à la réouverture (ticket 15.53).
     */
    public const SOURCES_A_NOUVEAU = ['ran', 'ran_reversal'];

    /**
     * Ticket EX8 — écriture de SOLDE DES COMPTES DE GESTION (étape 2 de la clôture, `ClotureExercice::soldeComptesGestion`,
     * datée du 31/12 de l'exercice) : elle ramène les classes 6 et 7 à zéro et porte le résultat au 131 / 139. Le Bilan et
     * le Compte de résultat l'ÉCARTENT, ses deux côtés ensemble (point relevé par EX1) : lue telle quelle, le Compte de
     * résultat d'un exercice clos vaudrait 0 et le comparatif N-1 serait faux. La Balance et le Grand Livre, eux, la
     * montrent : ce sont les livres, elle y est écrite.
     */
    public const SOURCES_SOLDE_GESTION = ['closing'];

    /** Libellé de la ligne de résultat d'un exercice encore ouvert, reporté dans l'ouverture du suivant (R3). */
    public static function libelleResultatProvisoire(int $annee): string
    {
        return "Résultat de l'exercice {$annee} (provisoire)";
    }

    /** @var array<string, array<string, mixed>> ouvertures déjà calculées par ce service (récursion R3) */
    private array $ouvertures = [];

    /**
     * Ticket EX1 — RÈGLE R1 (PRD `docs/prd/exercices-comptables.md` § 5) : l'exercice F qui contient `$date`.
     *
     * L'exercice enregistré qui couvre la date ; à défaut (exercice pas encore créé, date antérieure au premier
     * exercice), l'année civile de la date, « non enregistrée » (`reel` faux, `statut` null) — elle se traite comme un
     * exercice ouvert.
     *
     * @return array{annee: int, debut: string, fin: string, statut: ?string, reel: bool}
     */
    public function exerciceDe(string $date): array
    {
        $date = substr($date, 0, 10);
        $exercice = FiscalYear::whereDate('start_date', '<=', $date)
            ->whereDate('end_date', '>=', $date)
            ->orderBy('start_date')
            ->first();

        if ($exercice) {
            return [
                'annee' => (int) $exercice->year,
                'debut' => $exercice->start_date->format('Y-m-d'),
                'fin' => $exercice->end_date->format('Y-m-d'),
                'statut' => $exercice->status,
                'reel' => true,
            ];
        }

        $annee = (int) substr($date, 0, 4);

        return ['annee' => $annee, 'debut' => "{$annee}-01-01", 'fin' => "{$annee}-12-31", 'statut' => null, 'reel' => false];
    }

    /**
     * Tickets EX1 / EX2 — OUVERTURE de l'exercice qui contient `$date` (R1), pour les comptes des classes 1 à 5.
     *
     * Un seul cas par exercice, JAMAIS deux additionnés (défaut C1 : l'historique de N ET l'à-nouveau de N+1) :
     *  - `anouveau` : l'exercice précédent est clos → les écritures `ran` de F, nettes de leurs `ran_reversal` ;
     *    premier exercice → son à-nouveau initial (reprises d'avant le logiciel, Q7) ;
     *  - `provisoire` (R3) : l'exercice précédent est encore ouvert (ou pas enregistré) → ses soldes de clôture
     *    CALCULÉS (son ouverture + ses mouvements, classes 1 à 5) et une ligne « Résultat de l'exercice N
     *    (provisoire) » au 131 (bénéfice) ou au 139 (perte), ce que fera l'étape 2. Rien n'est écrit au journal ;
     *    à la clôture, l'à-nouveau écrit donne les mêmes chiffres ;
     *  - `historique` : premier exercice SANS à-nouveau initial → les écritures datées avant lui (vide en pratique :
     *    `record()` refuse toute date hors exercice, et la migration Q7 les reprend en à-nouveau initial). Jamais
     *    additionné à un à-nouveau : il n'est lu que s'il n'y en a aucun.
     *
     * `comptes` : solde NET (débit − crédit) par compte, comptes soldés exclus ; `resultat_provisoire` : la ligne R3,
     * à part (`net` < 0 = bénéfice, au crédit du 131), `null` hors mode provisoire.
     *
     * @return array{annee: int, debut: string, fin: string, mode: string, provisoire: bool, precedent: ?int, comptes: array<string, array{code: string, label: string, class: int, net: float}>, resultat_provisoire: ?array{annee: int, account_id: ?string, code: string, label: string, net: float}}
     */
    public function ouvertureExercice(string $date): array
    {
        return $this->ouverture($this->exerciceDe($date));
    }

    /** @param array{annee: int, debut: string, fin: string, statut: ?string, reel: bool} $exercice */
    private function ouverture(array $exercice): array
    {
        $cle = $exercice['debut'];
        if (isset($this->ouvertures[$cle])) {
            return $this->ouvertures[$cle];
        }

        $veille = Carbon::parse($exercice['debut'])->subDay()->format('Y-m-d');
        $precedent = FiscalYear::whereDate('start_date', '<', $exercice['debut'])->exists()
            ? $this->exerciceDe($veille)
            : null;

        $resultatProvisoire = null;

        if ($precedent === null) {
            $anouveau = $exercice['reel'] ? $this->cumuls($exercice['debut'], $exercice['fin'], true) : [];
            if ($anouveau !== []) {
                $mode = 'anouveau';
                $comptes = $this->nets($anouveau);
            } else {
                $mode = 'historique';
                $calcul = $this->clotureDepuis([], $this->cumuls(null, $veille, false));
                $comptes = $this->fusionner($calcul['comptes'], $this->ligneResultat(
                    $calcul['resultat'],
                    $exercice['annee'] - 1,
                    'Résultat antérieur au '.Carbon::parse($exercice['debut'])->format('d/m/Y'),
                ));
            }
        } elseif ($precedent['statut'] === 'cloture') {
            $mode = 'anouveau';
            $comptes = $this->nets($this->cumuls($exercice['debut'], $exercice['fin'], true));
        } else {
            $mode = 'provisoire';
            $calcul = $this->clotureCalculee($precedent);
            $comptes = $calcul['comptes'];
            $resultatProvisoire = $this->ligneResultat(
                $calcul['resultat'],
                $precedent['annee'],
                self::libelleResultatProvisoire($precedent['annee']),
            );
        }

        $comptes = array_filter($comptes, fn ($c) => abs($c['net']) >= 0.005);
        uasort($comptes, fn ($a, $b) => strcmp($a['code'], $b['code']));

        return $this->ouvertures[$cle] = [
            'annee' => $exercice['annee'],
            'debut' => $exercice['debut'],
            'fin' => $exercice['fin'],
            'mode' => $mode,
            'provisoire' => $mode === 'provisoire',
            'precedent' => $precedent['annee'] ?? null,
            'comptes' => $comptes,
            'resultat_provisoire' => $resultatProvisoire,
        ];
    }

    /**
     * Soldes de CLÔTURE calculés d'un exercice (R3) : son ouverture (ligne provisoire comprise, reportée sur son
     * compte) + ses mouvements hors à-nouveau ; les classes 6 et au-delà forment le résultat (produits − charges).
     *
     * @return array{comptes: array<string, array{code: string, label: string, class: int, net: float}>, resultat: float}
     */
    private function clotureCalculee(array $exercice): array
    {
        $ouverture = $this->ouverture($exercice);
        $comptes = $this->fusionner($ouverture['comptes'], $ouverture['resultat_provisoire']);

        return $this->clotureDepuis($comptes, $this->cumuls($exercice['debut'], $exercice['fin'], false));
    }

    /** @return array{comptes: array<string, array{code: string, label: string, class: int, net: float}>, resultat: float} */
    private function clotureDepuis(array $comptes, array $mouvements): array
    {
        $resultat = 0.0;
        foreach ($mouvements as $id => $m) {
            $net = (float) $m['debit'] - (float) $m['credit'];
            if ($m['class'] >= 1 && $m['class'] <= 5) {
                $comptes[$id] ??= ['code' => $m['code'], 'label' => $m['label'], 'class' => $m['class'], 'net' => 0.0];
                $comptes[$id]['net'] = round($comptes[$id]['net'] + $net, 2);
            } else {
                $resultat -= $net;   // produits (crédit) − charges (débit)
            }
        }

        return ['comptes' => $comptes, 'resultat' => round($resultat, 2)];
    }

    /**
     * La ligne de résultat d'un exercice reporté : au 131 s'il est positif, au 139 sinon (la règle de l'étape 2 de la
     * clôture) ; `null` s'il est nul.
     */
    private function ligneResultat(float $resultat, int $annee, string $libelle): ?array
    {
        if (abs($resultat) < 0.005) {
            return null;
        }

        $code = $resultat > 0 ? '131' : '139';

        return [
            'annee' => $annee,
            'account_id' => ChartOfAccount::where('code', $code)->value('id'),
            'code' => $code,
            'label' => $libelle,
            'net' => round(-$resultat, 2),
        ];
    }

    /** Reporte la ligne de résultat sur son compte (clé de repli quand le 131/139 manque au plan). */
    private function fusionner(array $comptes, ?array $ligne): array
    {
        if ($ligne === null) {
            return $comptes;
        }

        $id = $ligne['account_id'] ?? 'resultat-'.$ligne['code'];
        $comptes[$id] ??= ['code' => $ligne['code'], 'label' => $ligne['label'], 'class' => 1, 'net' => 0.0];
        $comptes[$id]['net'] = round($comptes[$id]['net'] + $ligne['net'], 2);

        return $comptes;
    }

    /** @return array<string, array{code: string, label: string, class: int, net: float}> */
    private function nets(array $cumuls): array
    {
        return array_map(fn ($c) => [
            'code' => $c['code'], 'label' => $c['label'], 'class' => $c['class'],
            'net' => round((float) $c['debit'] - (float) $c['credit'], 2),
        ], $cumuls);
    }

    /**
     * Ticket EX1 — SOLDES À UNE DATE selon R1 : classes 1 à 5 = ouverture de l'exercice + mouvements de l'exercice
     * jusqu'à la date ; classes 6 et au-delà = mouvements de l'exercice seulement. `$inclus` faux : à l'ouverture de
     * la journée (« strictement avant » : l'ouverture d'une période). `$horsSoldeGestion` vrai (ticket EX8 : Bilan et
     * Compte de résultat) : l'écriture de solde des comptes de gestion de l'exercice est écartée
     * (`SOURCES_SOLDE_GESTION`).
     *
     * @return array{ouverture: array, comptes: array<string, array{code: string, label: string, class: int, net: float}>, resultat_provisoire: ?array}
     */
    public function soldes(string $date, bool $inclus = true, bool $horsSoldeGestion = false): array
    {
        $date = substr($date, 0, 10);
        $exercice = $this->exerciceDe($date);
        $ouverture = $this->ouverture($exercice);
        $fin = $inclus ? $date : Carbon::parse($date)->subDay()->format('Y-m-d');

        $comptes = $ouverture['comptes'];
        if ($fin >= $exercice['debut']) {
            foreach ($this->cumuls($exercice['debut'], $fin, false, $horsSoldeGestion) as $id => $m) {
                $comptes[$id] ??= ['code' => $m['code'], 'label' => $m['label'], 'class' => $m['class'], 'net' => 0.0];
                $comptes[$id]['net'] = round($comptes[$id]['net'] + (float) $m['debit'] - (float) $m['credit'], 2);
            }
        }

        return ['ouverture' => $ouverture, 'comptes' => $comptes, 'resultat_provisoire' => $ouverture['resultat_provisoire']];
    }

    /** Solde net (débit − crédit) d'UN compte selon R1, ligne de résultat provisoire comprise si elle est la sienne. */
    public function soldeCompte(string $accountId, string $date, bool $inclus = true): float
    {
        return $this->netDans($this->soldes($date, $inclus), $accountId);
    }

    private function netDans(array $soldes, string $accountId): float
    {
        $net = (float) ($soldes['comptes'][$accountId]['net'] ?? 0);
        if (($soldes['resultat_provisoire']['account_id'] ?? null) === $accountId) {
            $net += $soldes['resultat_provisoire']['net'];
        }

        return round($net, 2);
    }

    /** Ce que les écrans disent de l'ouverture : « À-nouveaux provisoires » tant que l'exercice précédent est ouvert. */
    public function resumeOuverture(array $ouverture): array
    {
        return [
            'provisoire' => $ouverture['provisoire'],
            'annee' => $ouverture['annee'],
            'precedent' => $ouverture['precedent'],
            'mode' => $ouverture['mode'],
        ];
    }

    /**
     * Ticket EX1 — CONTRÔLE PERMANENT (PRD § 5, ajouté au contrôle de cohérence S-T6) : pour chaque exercice qui a un
     * précédent, et pour chaque compte des classes 1 à 5, OUVERTURE de N+1 = CLÔTURE de N (son ouverture + ses
     * mouvements, résultat porté au 131/139). Vrai par construction en provisoire ; après la clôture, il compare
     * l'à-nouveau ÉCRIT au calcul — une écriture de N déplacée hors de son exercice, un à-nouveau altéré, s'y voient.
     * Montants en solde net (débit − crédit).
     *
     * @return array<int, array{exercice: int, precedent: int, statut_precedent: ?string, ecarts: array<int, array{code: string, libelle: string, cloture: float, ouverture: float}>}>
     */
    public function controleAnouveaux(): array
    {
        $resultat = [];

        foreach (FiscalYear::orderBy('start_date')->get() as $enregistre) {
            $debut = $enregistre->start_date->format('Y-m-d');
            if (! FiscalYear::whereDate('start_date', '<', $debut)->exists()) {
                continue;
            }
            $exercice = $this->exerciceDe($debut);
            $precedent = $this->exerciceDe(Carbon::parse($debut)->subDay()->format('Y-m-d'));

            $calcul = $this->clotureCalculee($precedent);
            $attendu = $this->fusionner($calcul['comptes'], $this->ligneResultat(
                $calcul['resultat'],
                $precedent['annee'],
                self::libelleResultatProvisoire($precedent['annee']),
            ));
            $ouverture = $this->ouverture($exercice);
            $obtenu = $this->fusionner($ouverture['comptes'], $ouverture['resultat_provisoire']);

            $ecarts = [];
            foreach (array_keys($attendu + $obtenu) as $id) {
                $meta = $attendu[$id] ?? $obtenu[$id];
                if ($meta['class'] < 1 || $meta['class'] > 5) {
                    continue;
                }
                $cloture = round((float) ($attendu[$id]['net'] ?? 0), 2);
                $ouvert = round((float) ($obtenu[$id]['net'] ?? 0), 2);
                if (abs($cloture - $ouvert) >= 0.01) {
                    $ecarts[] = ['code' => $meta['code'], 'libelle' => $meta['label'], 'cloture' => $cloture, 'ouverture' => $ouvert];
                }
            }
            usort($ecarts, fn ($a, $b) => strcmp($a['code'], $b['code']));

            $resultat[] = [
                'exercice' => $exercice['annee'],
                'precedent' => $precedent['annee'],
                'statut_precedent' => $precedent['statut'],
                'ecarts' => $ecarts,
            ];
        }

        return $resultat;
    }

    /**
     * Cumuls débit / crédit par compte des écritures ACTIVES datées de `$du` (inclus ; `null` = depuis l'origine) à
     * `$au` (inclus). `$aNouveau` vrai : les seules écritures d'à-nouveau ; faux : toutes les AUTRES.
     * `$horsSoldeGestion` vrai : sans l'écriture de solde des comptes de gestion (ticket EX8).
     *
     * @return array<string, array{code: string, label: string, class: int, debit: float, credit: float}>
     */
    private function cumuls(?string $du, string $au, bool $aNouveau, bool $horsSoldeGestion = false): array
    {
        $query = AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->where('accounting_entries.is_active', true)
            ->whereDate('accounting_entries.entry_date', '<=', $au)
            ->when($du !== null, fn ($q) => $q->whereDate('accounting_entries.entry_date', '>=', $du));

        self::filtrerANouveau($query, $aNouveau);
        if ($horsSoldeGestion) {
            // ⚠️ Comme `filtrerANouveau` : une écriture SANS `source_type` est gardée (NULL n'est jamais « pas dans »).
            $query->where(fn ($q) => $q->whereNull('accounting_entries.source_type')
                ->orWhereNotIn('accounting_entries.source_type', self::SOURCES_SOLDE_GESTION));
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
     * Garde (vrai) ou écarte (faux) les écritures d'à-nouveau d'une requête jointe à `accounting_entries`.
     * ⚠️ Une écriture SANS `source_type` est un mouvement : `NOT IN` seul l'écarterait (NULL n'est jamais « pas dans »).
     */
    public static function filtrerANouveau($query, bool $aNouveau)
    {
        return $aNouveau
            ? $query->whereIn('accounting_entries.source_type', self::SOURCES_A_NOUVEAU)
            : $query->where(fn ($q) => $q->whereNull('accounting_entries.source_type')
                ->orWhereNotIn('accounting_entries.source_type', self::SOURCES_A_NOUVEAU));
    }

    /** Lignes « compte » d'un jeu de soldes R1, ligne de résultat provisoire comprise (classe 1, marquée). */
    private function lignesDeSoldes(array $soldes): array
    {
        $lignes = [];
        foreach ($soldes['comptes'] as $c) {
            $lignes[] = ['code' => $c['code'], 'label' => $c['label'], 'class' => $c['class'], 'balance' => round($c['net'], 2)];
        }
        if ($soldes['resultat_provisoire'] !== null) {
            $p = $soldes['resultat_provisoire'];
            $lignes[] = ['code' => $p['code'], 'label' => $p['label'], 'class' => 1, 'balance' => $p['net'], 'provisoire' => true];
        }
        // Tri par code, stable : la ligne provisoire suit le compte réel du même numéro.
        usort($lignes, fn ($a, $b) => strcmp((string) $a['code'], (string) $b['code']));

        return $lignes;
    }

    /**
     * Ticket EX1 — le Bilan lit les soldes de R1 (`soldes()`) : classes 1 à 5 depuis l'ouverture de l'exercice,
     * résultat = classes 6 et 7 de l'exercice seulement.
     *
     * 🔴→✅ Ticket EX8 — sans l'écriture de solde des comptes de gestion (`SOURCES_SOLDE_GESTION`) : le résultat d'un
     * exercice dont l'étape 2 est passée reste « Résultat de l'exercice », jamais déplacé au 131 / 139 (même total).
     */
    public function bilan(string $asOfDate): array
    {
        return $this->bilanDepuis($this->soldes($asOfDate, true, true));
    }

    private function bilanDepuis(array $soldes): array
    {
        $balances = $this->lignesDeSoldes($soldes);

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
            'ouverture' => $this->resumeOuverture($soldes['ouverture']),
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
     * Le solde d'ouverture est CALCULÉ, jamais saisi ou figé : changer la
     * période recalcule réellement l'ouverture. Ticket EX1 : il suit la règle
     * R1 (`soldes()`) — ouverture de l'exercice de `$startDate` (à-nouveau, ou
     * calcul R3 tant que l'exercice précédent est ouvert) + mouvements de cet
     * exercice avant `$startDate` ; jamais tout l'historique EN PLUS de
     * l'à-nouveau. Les écritures d'à-nouveau ne sont jamais des lignes.
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
            'ouverture' => ['provisoire' => false, 'annee' => null, 'precedent' => null, 'mode' => null],
        ];

        if (! $account) {
            return $empty;
        }

        $isDebitNature = $this->isDebitNature($account);

        // 🔴→✅ TICKET EX1 (défaut C1) — l'ouverture était TOUT l'historique antérieur au début de la période, ET
        // l'à-nouveau du 01/01 arrivait ensuite comme une ligne de la période : la caisse comptait deux fois le solde
        // de l'exercice clos. Désormais : règle R1 (ouverture de l'exercice + mouvements de l'exercice avant le
        // début), et les écritures d'à-nouveau ne sont jamais des lignes de la période.
        $soldes = $this->soldes($startDate, false);
        $openingNet = $this->netDans($soldes, $accountId);
        $openingBalance = round($isDebitNature ? $openingNet : -$openingNet, 2);

        $rows = self::filtrerANouveau($this->accountLinesQuery($accountId), false)
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
            'ouverture' => $this->resumeOuverture($soldes['ouverture']),
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
     *   1. même fenêtre que `bilan()` : les mêmes soldes R1 (`soldes()`), soit
     *      les classes 6-7 de l'exercice jusqu'à `$asOfDate` (ticket EX1 :
     *      plus l'historique depuis l'origine) ;
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
        // Ticket EX8 — l'écriture de solde de l'étape 2 écartée : le Compte de résultat d'un exercice clos n'est plus 0.
        return $this->compteResultatDepuis($this->soldes($asOfDate, true, true));
    }

    /** Ticket EX1 — classes 6 et 7 de l'EXERCICE seulement (R1), depuis son premier jour. */
    private function compteResultatDepuis(array $soldes): array
    {
        $balances = $this->lignesDeSoldes($soldes);

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
     * Ticket EX8 (EF11) — DATE D'ARRÊTÉ des états d'un exercice choisi : aujourd'hui s'il est en cours, sa clôture s'il
     * est passé, son premier jour s'il est à venir. L'exercice enregistré de cette année, à défaut l'année civile.
     * C'est la date que prennent le Bilan et les États financiers quand l'exercice affiché leur est donné (`exercice`,
     * branché par le sélecteur d'exercice d'EX7).
     */
    public function arreteDeLExercice(int $annee): string
    {
        $exercice = FiscalYear::where('year', $annee)->first();
        $debut = $exercice?->start_date->format('Y-m-d') ?? "{$annee}-01-01";
        $fin = $exercice?->end_date->format('Y-m-d') ?? "{$annee}-12-31";
        $aujourdhui = now()->format('Y-m-d');

        return max($debut, min($aujourdhui, $fin));
    }

    /**
     * Ticket EX8 (EF11) — l'exercice N-1 de l'exercice qui contient `$asOfDate` : l'exercice ENREGISTRÉ qui couvre la
     * veille du premier jour de N, présenté à sa clôture (`arrete` = son dernier jour), ou `null` s'il n'existe pas —
     * la colonne N-1 dit alors « — », jamais 0.
     *
     * @return array{exercice_n: array{annee: int, arrete: string}, exercice_n1: ?array{annee: int, arrete: string, statut: ?string}}
     */
    public function exercicesComparatif(string $asOfDate): array
    {
        $asOfDate = substr($asOfDate, 0, 10);
        $n = $this->exerciceDe($asOfDate);
        $precedent = $this->exerciceDe(Carbon::parse($n['debut'])->subDay()->format('Y-m-d'));

        return [
            'exercice_n' => ['annee' => $n['annee'], 'arrete' => $asOfDate],
            'exercice_n1' => $precedent['reel']
                ? ['annee' => $precedent['annee'], 'arrete' => $precedent['fin'], 'statut' => $precedent['statut']]
                : null,
        ];
    }

    /**
     * Ticket EX8 (EF11) — BILAN N / N-1 : le Bilan de N à `$asOfDate` et celui de N-1 à sa clôture, juxtaposés.
     *
     * `n` / `n1` : `bilan()` de chaque exercice (totaux, résultat, équilibre) — `n1` vaut `null` sans exercice N-1.
     * `lignes` : par rubrique (`immo`, `stocks`, `creances`, `tresorerie`, `capitaux`, `dettes`), l'union des comptes
     * des deux colonnes, triée par code ; chaque ligne porte son solde (même signe que `bilan()`) en `n` et en `n1`. Un
     * compte absent d'un exercice EXISTANT y vaut 0 (mesuré) ; sans exercice N-1, `n1` vaut `null` (inconnu : « — »).
     *
     * @return array{exercice_n: array, exercice_n1: ?array, n: array, n1: ?array, lignes: array<string, array<int, array{code: string, label: string, provisoire: bool, n: float, n1: ?float}>>}
     */
    public function bilanComparatif(string $asOfDate): array
    {
        $exercices = $this->exercicesComparatif($asOfDate);
        $n = $this->bilan($exercices['exercice_n']['arrete']);
        $n1 = $exercices['exercice_n1'] !== null ? $this->bilan($exercices['exercice_n1']['arrete']) : null;

        $lignes = [];
        foreach (['immo', 'stocks', 'creances', 'tresorerie', 'capitaux', 'dettes'] as $rubrique) {
            $fusion = [];
            $colonnes = ['n' => $n[$rubrique]];
            if ($n1 !== null) {
                $colonnes['n1'] = $n1[$rubrique];
            }
            foreach ($colonnes as $colonne => $source) {
                foreach ($source as $l) {
                    $provisoire = (bool) ($l['provisoire'] ?? false);
                    $cle = $l['code'].'|'.$l['label'].'|'.($provisoire ? 'p' : '');
                    $fusion[$cle] ??= [
                        'code' => (string) $l['code'], 'label' => (string) $l['label'], 'provisoire' => $provisoire,
                        'n' => 0.0, 'n1' => $n1 === null ? null : 0.0,
                    ];
                    $fusion[$cle][$colonne] = round($fusion[$cle][$colonne] + (float) $l['balance'], 2);
                }
            }
            $fusion = array_values($fusion);
            // Tri STABLE par code : à code égal, l'ordre d'arrivée (colonne N d'abord).
            usort($fusion, fn ($a, $b) => strcmp($a['code'], $b['code']));
            $lignes[$rubrique] = $fusion;
        }

        return $exercices + ['n' => $n, 'n1' => $n1, 'lignes' => $lignes];
    }

    /**
     * Ticket EX8 (EF11) — COMPTE DE RÉSULTAT N / N-1 : la cascade de N à `$asOfDate` et celle de l'exercice N-1 entier
     * (à sa clôture), écriture de solde des comptes de gestion écartée ; `n1` vaut `null` sans exercice N-1.
     *
     * @return array{exercice_n: array, exercice_n1: ?array, n: array<string, float>, n1: ?array<string, float>}
     */
    public function compteResultatComparatif(string $asOfDate): array
    {
        $exercices = $this->exercicesComparatif($asOfDate);

        return $exercices + [
            'n' => $this->compteResultat($exercices['exercice_n']['arrete']),
            'n1' => $exercices['exercice_n1'] !== null ? $this->compteResultat($exercices['exercice_n1']['arrete']) : null,
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
        // 🔴→✅ TICKET EX1 — l'ouverture est la situation à l'OUVERTURE de la journée `$startDate` dans son exercice
        // (R1), et non le Bilan de la veille : au 01/01, la veille appartient à l'exercice précédent, dont le résultat
        // est encore en classes 6-7 (ou provisoire), alors que l'ouverture du nouvel exercice le porte au 131/139.
        // Comparer les deux faisait passer le résultat reporté pour un flux de financement.
        $soldesOuverture = $this->soldes($startDate, false, true);   // EX8 : même lecture que `bilan()`
        $ouverture = $this->bilanDepuis($soldesOuverture);
        $cloture = $this->bilan($endDate);

        // Résultat et dotations DE LA PÉRIODE : ceux de l'exercice au `$endDate`, moins ceux déjà acquis avant
        // `$startDate` (zéro quand la période part du premier jour de l'exercice).
        $resultat = $this->compteResultat($endDate);
        $resultatAvant = $this->compteResultatDepuis($soldesOuverture);
        $resultatNet = round($resultat['resultat_net'] - $resultatAvant['resultat_net'], 2);
        $dotations = round($resultat['dotations'] - $resultatAvant['dotations'], 2);

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
        // 🔴→✅ TICKET EX1 (défaut C1) — l'ouverture cumulait TOUT l'historique avant le début de la période, et
        // l'à-nouveau du 01/01 entrait en plus dans les mouvements : « Exercice 2027 » montrait chaque solde de bilan
        // deux fois. Désormais : ouverture = soldes R1 à l'ouverture de la journée `$startDate` (à-nouveau ou calcul
        // R3 + mouvements de l'exercice avant le début ; classes 6-7 depuis le premier jour de l'exercice), et les
        // mouvements de la période n'incluent jamais un à-nouveau.
        $soldes = $this->soldes($startDate, false);
        $period = $this->cumuls($startDate, $endDate, false);

        $opening = [];
        foreach ($soldes['comptes'] as $id => $c) {
            $opening[$id] = ['code' => $c['code'], 'label' => $c['label'], 'class' => $c['class'], 'net' => $c['net']];
        }
        // Ligne « Résultat de l'exercice N (provisoire) » : une ligne à part, après le compte du même numéro.
        if ($soldes['resultat_provisoire'] !== null) {
            $p = $soldes['resultat_provisoire'];
            $opening['resultat-provisoire'] = ['code' => $p['code'], 'label' => $p['label'], 'class' => 1, 'net' => $p['net'], 'provisoire' => true];
        }

        $accounts = [];
        foreach ($opening + $period as $id => $meta) {   // union par clé (id de compte)
            $accounts[$id] = $meta;
        }
        uasort($accounts, fn ($a, $b) => strcmp((string) $a['code'], (string) $b['code']));

        $rows = [];
        $totals = [
            'opening_debit' => 0.0, 'opening_credit' => 0.0,
            'period_debit' => 0.0, 'period_credit' => 0.0,
            'final_debit' => 0.0, 'final_credit' => 0.0,
        ];

        foreach ($accounts as $id => $meta) {
            $openingNet = round((float) ($opening[$id]['net'] ?? 0), 2);

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
                'provisoire' => (bool) ($meta['provisoire'] ?? false),
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
            'ouverture' => $this->resumeOuverture($soldes['ouverture']),
        ];
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
}
