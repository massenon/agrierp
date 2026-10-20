<?php

namespace App\Services;

use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use Illuminate\Support\Facades\Log;

/**
 * Ticket EX1 — À-NOUVEAU INITIAL DES REPRISES D'AVANT LE LOGICIEL (question Q7, décision du client du 20/10/2026).
 *
 * RÈGLE : une écriture datée AVANT le premier exercice (reprise d'une situation antérieure au logiciel) ne sert jamais
 * directement d'ouverture. Elle est présentée comme un « à-nouveau initial » : une écriture `ran` au PREMIER JOUR du
 * premier exercice, sans exercice d'origine (`source_id` nul), qui reporte le solde net de chaque compte des classes
 * 1 à 5 et porte le résultat de ces écritures (classes 6 et au-delà) au 131 (bénéfice) ou au 139 (perte). Ainsi R1 n'a
 * qu'un seul cas : l'ouverture d'un exercice vient toujours d'un à-nouveau (ou du calcul R3), jamais de l'historique.
 *
 * ⚠️ AU MOMENT DE LA REPRISE : `AccountingEntryService::record()` refuse toute date que ne couvre aucun exercice ;
 * une reprise se saisit donc DANS le premier exercice (apport `asset_opening` à sa date, écritures d'ouverture au
 * Journal) ou n'entre pas en comptabilité (reprise d'antériorité d'une immobilisation, sans écriture). Seule une
 * écriture déplacée au Journal avant le premier exercice (défaut que ferme EX5) ou une base importée peut en porter :
 * la migration `2026_10_20_000001` appelle `regulariser()` une fois au déploiement.
 *
 * IDEMPOTENT : l'à-nouveau initial déjà écrit est comparé aux reprises ; seule la DIFFÉRENCE est écrite (rien quand
 * elles concordent). L'écriture passe par `record()`, le point de passage unique : il faut donc que le premier
 * exercice soit OUVERT ; clos, rien n'est écrit et la raison est journalisée (le contrôle S-T6 montrera l'écart).
 */
class AnouveauInitialService
{
    public const LIBELLE = 'À-nouveau initial — reprises antérieures au ';

    /** @return int nombre d'écritures écrites (0 ou 1) */
    public function regulariser(): int
    {
        $premier = FiscalYear::orderBy('start_date')->first();
        if (! $premier) {
            return 0;
        }

        $debut = $premier->start_date->format('Y-m-d');
        $reprises = $this->netsParCompte(fn ($q) => $q->whereDate('accounting_entries.entry_date', '<', $debut));
        if ($reprises === []) {
            return 0;
        }

        // Reprises → lignes d'à-nouveau : classes 1 à 5 telles quelles, le reste en résultat au 131 / 139.
        $attendu = [];
        $resultat = 0.0;
        foreach ($reprises as $id => $r) {
            if ($r['class'] >= 1 && $r['class'] <= 5) {
                $attendu[$id] = ($attendu[$id] ?? 0) + $r['net'];
            } else {
                $resultat -= $r['net'];
            }
        }
        if (abs($resultat) >= 0.005) {
            $compte = ChartOfAccount::where('code', $resultat > 0 ? '131' : '139')->value('id');
            if ($compte === null) {
                Log::warning('À-nouveau initial non écrit : compte 131/139 absent du plan comptable.');

                return 0;
            }
            $attendu[$compte] = ($attendu[$compte] ?? 0) - $resultat;
        }

        $deja = $this->netsParCompte(fn ($q) => $q->where('accounting_entries.source_type', 'ran')
            ->whereNull('accounting_entries.source_id')
            ->whereDate('accounting_entries.entry_date', $debut));

        $lignes = [];
        foreach (array_keys($attendu + $deja) as $id) {
            $ecart = round(($attendu[$id] ?? 0) - ($deja[$id]['net'] ?? 0), 2);
            if (abs($ecart) >= 0.01) {
                $lignes[] = ['account_id' => $id, 'debit' => max($ecart, 0), 'credit' => max(-$ecart, 0)];
            }
        }
        if ($lignes === []) {
            return 0;
        }

        if ($premier->status !== 'ouvert') {
            Log::warning("À-nouveau initial non écrit : le premier exercice ({$premier->year}) est clôturé.");

            return 0;
        }

        app(AccountingEntryService::class)->record(
            lines: $lignes,
            entryDate: $debut,
            reference: self::LIBELLE.$premier->start_date->format('d/m/Y'),
            sourceType: 'ran',
            sourceId: null,
        );

        return 1;
    }

    /** @return array<string, array{class: int, net: float}> */
    private function netsParCompte(callable $filtre): array
    {
        $query = AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->where('accounting_entries.is_active', true);
        $filtre($query);

        return $query
            ->groupBy('chart_of_accounts.id', 'chart_of_accounts.class')
            ->selectRaw('chart_of_accounts.id as account_id, chart_of_accounts.class, SUM(accounting_entry_lines.debit) as d, SUM(accounting_entry_lines.credit) as c')
            ->get()
            ->mapWithKeys(fn ($l) => [$l->account_id => ['class' => (int) $l->class, 'net' => round((float) $l->d - (float) $l->c, 2)]])
            ->all();
    }
}
