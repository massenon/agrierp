<?php

namespace App\Services;

use App\Models\AccountingEntryLine;
use App\Models\BankStatementLine;
use Carbon\Carbon;

/**
 * Ticket 14.8 (Sprint 14) — Rapprochement Bancaire : confrontation du Grand
 * Livre d'un compte de trésorerie au relevé bancaire réellement importé.
 *
 * ⚠️ L'ÉQUATION DE RAPPROCHEMENT, REPRISE TELLE QUELLE DU PROTOTYPE :
 *     Solde Livre − opérations en instance + lignes du relevé non encore
 *     saisies = Solde Relevé
 * Les « opérations en instance » sont les écritures passées au livre que la
 * banque n'a pas encore débitées/créditées (chèque émis non présenté). Les
 * « nouvelles » sont l'inverse : présentes au relevé, pas encore saisies
 * (frais de tenue de compte). L'écart doit être nul ; s'il ne l'est pas,
 * c'est un vrai problème à corriger avant clôture.
 *
 * ⚠️ LETTRAGE AUTOMATIQUE — RÈGLE EXPLICITE ET CONSERVATRICE : une ligne du
 * livre et une ligne du relevé sont appariées si elles portent le MÊME
 * MONTANT SIGNÉ à moins de {TOLERANCE_JOURS} jours d'écart. Un même montant
 * peut apparaître plusieurs fois : l'appariement est glouton par date la plus
 * proche, et chaque ligne n'est appariée QU'UNE FOIS — jamais un même
 * encaissement lettré contre deux lignes de relevé, ce qui masquerait un
 * doublon réel.
 *
 * Le délai bancaire (une opération met quelques jours à apparaître au relevé)
 * rend une correspondance de date exacte irréaliste ; une tolérance trop large
 * apparierait en revanche des opérations sans rapport. 5 jours est la valeur
 * retenue, exposée en constante pour être ajustable sans toucher à la logique.
 */
class BankReconciliationService
{
    public const TOLERANCE_JOURS = 5;

    /**
     * @return array{
     *     ledger: array<int, array<string, mixed>>,
     *     statement: array<int, array<string, mixed>>,
     *     opening_balance: float,
     *     solde_livre: float,
     *     solde_releve: float,
     *     en_instance: float,
     *     nouveau_non_saisi: float,
     *     ecart: float,
     *     is_balanced: bool
     * }
     */
    public function reconcile(string $accountId, string $startDate, string $endDate): array
    {
        $opening = $this->openingBalance($accountId, $startDate);

        $ledger = $this->ledgerLines($accountId, $startDate, $endDate);
        $statement = $this->statementLines($accountId, $startDate, $endDate);

        $this->match($ledger, $statement);

        $soldeLivre = round($opening + array_sum(array_column($ledger, 'amount')), 2);
        $soldeReleve = round($opening + array_sum(array_column($statement, 'amount')), 2);

        $enInstance = round(array_sum(array_map(
            fn ($l) => $l['is_matched'] ? 0 : $l['amount'],
            $ledger
        )), 2);

        $nouveauNonSaisi = round(array_sum(array_map(
            fn ($l) => $l['is_matched'] ? 0 : $l['amount'],
            $statement
        )), 2);

        $soldeLivreProjete = round($soldeLivre - $enInstance + $nouveauNonSaisi, 2);
        $ecart = round($soldeLivreProjete - $soldeReleve, 2);

        return [
            'ledger' => $ledger,
            'statement' => $statement,
            'opening_balance' => $opening,
            'solde_livre' => $soldeLivre,
            'solde_releve' => $soldeReleve,
            'en_instance' => $enInstance,
            'nouveau_non_saisi' => $nouveauNonSaisi,
            'ecart' => $ecart,
            'is_balanced' => abs($ecart) < 0.01,
        ];
    }

    /**
     * Ticket 14.43 — TAUX DE LETTRAGE de la période, tous comptes de
     * trésorerie confondus. Répond à la seule question qui compte avant une
     * clôture : « mon livre est-il corroboré par la banque ? »
     *
     * ⚠️ LES DEUX CÔTÉS COMPTENT. Le dénominateur additionne les lignes du
     * LIVRE et celles du RELEVÉ. Une écriture passée que la banque n'a pas
     * débitée (chèque non présenté) et une ligne du relevé jamais saisie
     * (frais de tenue de compte) sont deux anomalies distinctes, et toutes
     * deux doivent être résorbées avant clôture. Ne compter qu'un seul côté
     * en masquerait la moitié.
     *
     * ⚠️ SEULS LES COMPTES DISPOSANT D'UN RELEVÉ IMPORTÉ ENTRENT AU CALCUL.
     * Un compte sans relevé n'est pas « mal lettré » : il est non
     * rapprochable, ce qui appelle une autre action (importer le relevé).
     * Les confondre donnerait un pourcentage qui ne dit pas quoi faire. Ces
     * comptes sont donc COMPTÉS À PART et affichés, jamais passés sous
     * silence.
     *
     * ⚠️ AUCUN RELEVÉ IMPORTÉ ⇒ `taux = null`, JAMAIS 100 %. Zéro ligne
     * lettrée sur zéro ligne n'est pas un rapprochement parfait ; l'afficher
     * comme tel donnerait le feu vert à une clôture sur une trésorerie non
     * vérifiée.
     *
     * @return array{taux: float|null, lignes: int, lettrees: int, comptes_sans_releve: int}
     */
    public function tauxDeLettrage(string $startDate, string $endDate): array
    {
        $comptesAvecReleve = BankStatementLine::query()
            ->whereDate('statement_date', '>=', $startDate)
            ->whereDate('statement_date', '<=', $endDate)
            ->distinct()
            ->pluck('account_id')
            ->all();

        $lignes = 0;
        $lettrees = 0;

        foreach ($comptesAvecReleve as $accountId) {
            $resultat = $this->reconcile((string) $accountId, $startDate, $endDate);

            foreach (['ledger', 'statement'] as $cote) {
                foreach ($resultat[$cote] as $ligne) {
                    $lignes++;
                    if ($ligne['is_matched']) {
                        $lettrees++;
                    }
                }
            }
        }

        // Comptes de trésorerie réellement mouvementés sur la période mais
        // dont aucun relevé n'a été importé : non rapprochables.
        $comptesSansReleve = AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->where('accounting_entries.is_active', true)
            ->where('chart_of_accounts.class', 5)
            ->whereDate('accounting_entries.entry_date', '>=', $startDate)
            ->whereDate('accounting_entries.entry_date', '<=', $endDate)
            ->when($comptesAvecReleve !== [], fn ($q) => $q->whereNotIn('accounting_entry_lines.account_id', $comptesAvecReleve))
            ->distinct()
            ->count('accounting_entry_lines.account_id');

        return [
            'taux' => $lignes > 0 ? round(100 * $lettrees / $lignes, 0) : null,
            'lignes' => $lignes,
            'lettrees' => $lettrees,
            'comptes_sans_releve' => $comptesSansReleve,
        ];
    }

    /** Solde du compte au grand livre, strictement avant la période. */
    private function openingBalance(string $accountId, string $startDate): float
    {
        $row = AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->where('accounting_entry_lines.account_id', $accountId)
            ->whereDate('accounting_entries.entry_date', '<', $startDate)
            ->selectRaw('SUM(accounting_entry_lines.debit) as d, SUM(accounting_entry_lines.credit) as c')
            ->first();

        return round((float) ($row->d ?? 0) - (float) ($row->c ?? 0), 2);
    }

    /** @return array<int, array<string, mixed>> */
    private function ledgerLines(string $accountId, string $startDate, string $endDate): array
    {
        return AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->where('accounting_entry_lines.account_id', $accountId)
            ->whereDate('accounting_entries.entry_date', '>=', $startDate)
            ->whereDate('accounting_entries.entry_date', '<=', $endDate)
            ->orderBy('accounting_entries.entry_date')
            ->select([
                'accounting_entry_lines.id',
                'accounting_entries.entry_date',
                'accounting_entries.reference',
                'accounting_entry_lines.debit',
                'accounting_entry_lines.credit',
            ])
            ->get()
            ->map(function ($row) {
                $parts = explode('—', (string) $row->reference, 2);

                return [
                    'id' => $row->id,
                    'date' => Carbon::parse($row->entry_date)->format('Y-m-d'),
                    'label' => trim($parts[1] ?? $parts[0] ?? ''),
                    'amount' => round((float) $row->debit - (float) $row->credit, 2),
                    'is_matched' => false,
                ];
            })
            ->all();
    }

    /** @return array<int, array<string, mixed>> */
    private function statementLines(string $accountId, string $startDate, string $endDate): array
    {
        return BankStatementLine::where('account_id', $accountId)
            ->whereDate('statement_date', '>=', $startDate)
            ->whereDate('statement_date', '<=', $endDate)
            ->orderBy('statement_date')
            ->get()
            ->map(fn ($line) => [
                'id' => $line->id,
                'date' => $line->statement_date->format('Y-m-d'),
                'label' => $line->label,
                'amount' => round((float) $line->amount, 2),
                'is_matched' => false,
            ])
            ->all();
    }

    /**
     * Appariement glouton : pour chaque ligne du livre, la ligne de relevé de
     * même montant encore libre dont la date est la plus proche, dans la limite
     * de la tolérance. Modifie les deux tableaux par référence.
     */
    private function match(array &$ledger, array &$statement): void
    {
        foreach ($ledger as $i => $ligne) {
            $meilleur = null;
            $meilleurEcart = null;

            foreach ($statement as $j => $releve) {
                if ($releve['is_matched'] || abs($releve['amount'] - $ligne['amount']) >= 0.01) {
                    continue;
                }

                $ecartJours = abs(Carbon::parse($ligne['date'])->diffInDays(Carbon::parse($releve['date'])));

                if ($ecartJours > self::TOLERANCE_JOURS) {
                    continue;
                }

                if ($meilleurEcart === null || $ecartJours < $meilleurEcart) {
                    $meilleur = $j;
                    $meilleurEcart = $ecartJours;
                }
            }

            if ($meilleur !== null) {
                $ledger[$i]['is_matched'] = true;
                $statement[$meilleur]['is_matched'] = true;
            }
        }
    }

    /**
     * Import d'un relevé au format CSV `date;libellé;montant`.
     *
     * Le montant est signé ; le séparateur décimal virgule est accepté (usage
     * francophone courant des exports bancaires), les espaces de milliers
     * retirés. Une ligne illisible est COMPTÉE ET SIGNALÉE, jamais avalée en
     * silence — un relevé partiellement importé sans avertissement produirait
     * un écart inexplicable.
     *
     * @return array{imported: int, skipped: int}
     */
    public function importCsv(string $accountId, string $contents): array
    {
        $imported = 0;
        $skipped = 0;

        foreach (preg_split('/\r\n|\r|\n/', $contents) as $index => $ligne) {
            $ligne = trim($ligne);

            if ($ligne === '') {
                continue;
            }

            $colonnes = str_getcsv($ligne, ';');

            if (count($colonnes) < 3) {
                $colonnes = str_getcsv($ligne, ',');
            }

            if (count($colonnes) < 3) {
                $skipped++;

                continue;
            }

            [$date, $label, $montant] = array_map('trim', array_slice($colonnes, 0, 3));

            // En-tête éventuel.
            if ($index === 0 && ! preg_match('/^\d/', $date)) {
                continue;
            }

            $montant = str_replace([' ', ' ', ','], ['', '', '.'], $montant);

            if (! is_numeric($montant)) {
                $skipped++;

                continue;
            }

            try {
                $date = Carbon::parse($date)->format('Y-m-d');
            } catch (\Throwable) {
                $skipped++;

                continue;
            }

            BankStatementLine::create([
                'account_id' => $accountId,
                'statement_date' => $date,
                'label' => $label !== '' ? mb_substr($label, 0, 255) : 'Opération bancaire',
                'amount' => (float) $montant,
            ]);

            $imported++;
        }

        return ['imported' => $imported, 'skipped' => $skipped];
    }
}
