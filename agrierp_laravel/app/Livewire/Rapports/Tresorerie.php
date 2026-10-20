<?php

namespace App\Livewire\Rapports;

use App\Models\AccountingEntryLine;
use App\Services\FinancialReportService;
use App\Services\PdfExportService;
use Illuminate\Support\Facades\Response;
use Livewire\Attributes\On;
use Livewire\Component;

/**
 * Ticket 12.3 (Sprint 12) — rapport-tresorerie.html →
 * Livewire\Rapports\Tresorerie
 * "Position de trésorerie consolidée."
 *
 * ⚠️ DÉCISION ARCHITECTURALE, DISTINCTE DU TICKET 12.2 PRÉCÉDENT :
 * contrairement à `RecettesDepenses` (business tables), ce rapport suit
 * EXACTEMENT le texte du prototype lui-même — l'info-bulle de la colonne
 * Actions dit explicitement "Ce rapport est généré à partir des
 * écritures comptables réelles" — calculé depuis le grand livre
 * (`accounting_entry_lines`, comptes de classe 5), même discipline que le
 * Bilan (ticket 10.5). Chaque rapport de ce sprint suit la source que SON
 * PROPRE texte prototype indique, jamais une règle uniforme imposée à
 * tous les rapports sans les avoir lus individuellement.
 *
 * "Solde Caisse" = comptes classe 5 dont le code commence par 531 ;
 * "Solde Banque" = tous les autres comptes classe 5 (521, 5212...) —
 * regroupement fidèle aux 2 colonnes du prototype (pas de 3ᵉ colonne
 * Mobile Money séparée ici, contrairement à Modes de Paiement, Sprint 11,
 * qui a 3 colonnes ; ce rapport en a 2, fidélité au tableau source).
 *
 * Une ligne par DATE où une écriture a touché la trésorerie dans la
 * période — solde CUMULÉ (pas le mouvement du jour) à cette date, cohérent
 * avec "Solde Caisse : 420 000" affiché comme un solde, pas un delta.
 *
 * ⚠️ Même conséquence honnête que le Bilan/Comptabilité Analytique :
 * tant que le rétro-câblage des modules métier vers le grand livre reste
 * différé (ticket 10.2), ce rapport ne montre que les écritures
 * manuelles du Journal Comptable qui auraient touché un compte de
 * trésorerie.
 */
class Tresorerie extends Component
{
    public string $startDate;

    public string $endDate;

    public function mount(string $startDate, string $endDate): void
    {
        $this->startDate = $startDate;
        $this->endDate = $endDate;
    }

    public function getRowsProperty(): array
    {
        // Solde cumulé de chaque compte classe 5 à CHAQUE date d'activité
        // dans la période — jamais seulement le mouvement du jour.
        // 🔴→✅ Ticket EX1 (défaut C1) : un à-nouveau n'est pas une activité (sa date n'ouvre pas de ligne), et le
        // solde suit la règle R1 — il cumulait tout l'historique ET l'à-nouveau, deux fois l'exercice clos.
        $dates = FinancialReportService::filtrerANouveau(AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id'), false)
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->where('accounting_entries.is_active', true)
            ->where('chart_of_accounts.class', 5)
            ->whereDate('accounting_entries.entry_date', '>=', $this->startDate)
            ->whereDate('accounting_entries.entry_date', '<=', $this->endDate)
            ->selectRaw('DISTINCT accounting_entries.entry_date')
            ->orderByDesc('accounting_entries.entry_date')
            ->pluck('entry_date');

        $rapports = app(FinancialReportService::class);

        return $dates->map(function ($date) use ($rapports) {
            $balances = array_filter(
                $rapports->soldes(substr((string) $date, 0, 10))['comptes'],
                fn ($c) => $c['class'] === 5,
            );

            $caisse = array_sum(array_map(fn ($b) => str_starts_with($b['code'], '531') ? $b['net'] : 0, $balances));
            $banque = array_sum(array_map(fn ($b) => ! str_starts_with($b['code'], '531') ? $b['net'] : 0, $balances));

            return [
                'date' => $date,
                'caisse' => round((float) $caisse, 2),
                'banque' => round((float) $banque, 2),
                'total' => round((float) $caisse + $banque, 2),
            ];
        })->all();
    }

    #[On('export-report')]
    public function exportReport(string $format, string $startDate, string $endDate)
    {
        $this->authorize('export-rapports');

        $this->startDate = $startDate;
        $this->endDate = $endDate;

        $rows = $this->rows;
        $period = \Carbon\Carbon::parse($startDate)->format('d/m/Y').' au '.\Carbon\Carbon::parse($endDate)->format('d/m/Y');

        if ($format === 'pdf') {
            $pdf = app(PdfExportService::class)->render(
                'exports.tresorerie',
                ['rows' => $rows],
                'État de Trésorerie',
                $period
            );

            return response()->streamDownload(fn () => print($pdf->output()), 'tresorerie-'.now()->format('Y-m-d').'.pdf');
        }

        $csv = "Date,Solde Caisse,Solde Banque,Solde Total\n";
        foreach ($rows as $r) {
            $csv .= \Carbon\Carbon::parse($r['date'])->format('d/m/Y').','.$r['caisse'].','.$r['banque'].','.$r['total']."\n";
        }

        return Response::streamDownload(fn () => print($csv), 'tresorerie-'.now()->format('Y-m-d').'.csv', ['Content-Type' => 'text/csv']);
    }

    public function render()
    {
        return view('livewire.rapports.tresorerie');
    }
}
