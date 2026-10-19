<?php

namespace App\Livewire\Rapports;

use App\Models\Expense;
use App\Models\Payslip;
use App\Models\Purchase;
use App\Models\Sale;
use App\Services\PdfExportService;
use Illuminate\Support\Facades\Response;
use Livewire\Attributes\On;
use Livewire\Component;

/**
 * Ticket 12.2 (Sprint 12) — rapport-recettes-depenses.html →
 * Livewire\Rapports\RecettesDepenses
 * "Comparatif détaillé des entrées et sorties de trésorerie sur la
 * période."
 *
 * ⚠️ DÉCISION ARCHITECTURALE, DISTINCTE DU BILAN (ticket 10.5) : ce
 * rapport n'interroge PAS le grand livre comptable — contrairement au
 * Bilan et à la Comptabilité Analytique (hub Comptabilité, formels
 * SYSCOHADA, qui DOIVENT venir exclusivement des écritures), ce rapport
 * vit dans le hub Rapports & Exports et décrit de vrais MOUVEMENTS DE
 * TRÉSORERIE opérationnels (ventes encaissées, achats payés, dépenses,
 * paie réglée) — il interroge directement les tables métier déjà
 * pleinement réelles (`sales`, `purchases`, `expenses`, `payslips`),
 * jamais le grand livre encore clairsemé (rétro-câblage différé depuis
 * le ticket 10.2). Deux rapports différents, deux sources différentes,
 * chacune légitime pour ce qu'elle représente.
 *
 * ⚠️ LIMITE HONNÊTE, SIGNALÉE EXPLICITEMENT : seuls les mouvements
 * IMMÉDIATS (`payment_mode != 'credit'`) sont inclus, datés par leur
 * propre enregistrement (`created_at`/`purchase_date`/`expense_date`).
 * Les règlements différés sur `receivables`/`payables` (ventes/achats à
 * crédit payés plus tard) ne peuvent PAS être datés précisément — ces
 * deux tables ne conservent qu'un cumul (`amount_paid`), sans historique
 * de paiement horodaté (même limite déjà documentée pour les rapports de
 * Trésorerie : "reconstruit l'ouverture via solde courant moins flux de
 * la période, pas d'historique daté"). Ce rapport ne les invente pas.
 *
 * 🔴→✅ Ticket U12b — ORDRE DÉTERMINÉ : sans second critère, deux pièces de la même date (deux achats du même
 * jour, deux ventes de la même seconde) sortaient dans l'ordre du moteur de base, qui n'est garanti nulle part ;
 * le poste ne pouvait pas le reproduire. Chaque source est désormais lue par identifiant croissant (`orderBy('id')`)
 * et la fusion reste un tri STABLE par date (`sortByDesc`) : à date égale, achats, puis dépenses, puis paie.
 *
 * Export ciblé par le hub (`RapportsExportsHub`, ticket 12.1) via
 * événement Livewire `export-report` — ce composant reste seul
 * responsable de sa propre mise en page d'export (PDF/CSV), jamais une
 * logique générique côté hub.
 */
class RecettesDepenses extends Component
{
    public string $startDate;

    public string $endDate;

    public function mount(string $startDate, string $endDate): void
    {
        $this->startDate = $startDate;
        $this->endDate = $endDate;
    }

    private function recettesQuery()
    {
        return Sale::with('customer')
            ->where('payment_mode', '!=', 'credit')
            ->where('status', 'validee')
            ->soldBetween($this->startDate, $this->endDate);
    }

    private function depensesRows(): array
    {
        $purchases = Purchase::with('supplier')
            ->where('payment_mode', '!=', 'credit')
            ->whereDate('purchase_date', '>=', $this->startDate)
            ->whereDate('purchase_date', '<=', $this->endDate)
            ->orderBy('id')
            ->get()
            ->map(fn ($p) => ['date' => $p->purchase_date, 'label' => 'Achat — '.($p->supplier?->name ?? 'Fournisseur'), 'amount' => (float) $p->total]);

        // 🔴→✅ Ticket U12b — une dépense ARCHIVÉE n'est plus une dépense : `SaisieDepenses::archiveExpense()` réintègre
        // son montant en trésorerie et contre-passe sa charge (« archiver une dépense la retire des états »). Ce rapport
        // la comptait encore, sortie d'argent fantôme.
        $expenses = Expense::where('is_active', true)
            ->whereDate('expense_date', '>=', $this->startDate)
            ->whereDate('expense_date', '<=', $this->endDate)
            ->orderBy('id')
            ->get()
            ->map(fn ($e) => ['date' => $e->expense_date, 'label' => $e->label, 'amount' => (float) $e->amount]);

        $payslips = Payslip::with('employee')
            ->whereDate('created_at', '>=', $this->startDate)
            ->whereDate('created_at', '<=', $this->endDate)
            ->orderBy('id')
            ->get()
            ->map(fn ($p) => ['date' => $p->created_at->toDateString(), 'label' => 'Paie — '.($p->employee?->last_name.' '.$p->employee?->first_name ?? 'Employé'), 'amount' => (float) $p->net_salary]);

        return $purchases->concat($expenses)->concat($payslips)
            ->sortByDesc('date')->values()->all();
    }

    public function getRecettesProperty()
    {
        return $this->recettesQuery()->orderByEffectiveDate()->orderBy('id')->get()->map(fn ($s) => [
            'date' => $s->date_effective->toDateString(),
            'label' => 'Vente — '.($s->customer?->name ?? 'Client comptant'),
            'amount' => (float) $s->total,
        ]);
    }

    public function getDepensesProperty()
    {
        return collect($this->depensesRows());
    }

    public function getKpisProperty(): array
    {
        $totalRecettes = $this->recettesQuery()->sum('total');
        $totalDepenses = array_sum(array_column($this->depensesRows(), 'amount'));

        return [
            'recettes' => (float) $totalRecettes,
            'depenses' => $totalDepenses,
            'solde' => (float) $totalRecettes - $totalDepenses,
        ];
    }

    #[On('export-report')]
    public function exportReport(string $format, string $startDate, string $endDate)
    {
        $this->authorize('export-rapports');

        $this->startDate = $startDate;
        $this->endDate = $endDate;

        $recettes = $this->recettes;
        $depenses = $this->depenses;
        $kpis = $this->kpis;
        $period = \Carbon\Carbon::parse($startDate)->format('d/m/Y').' au '.\Carbon\Carbon::parse($endDate)->format('d/m/Y');

        if ($format === 'pdf') {
            $pdf = app(PdfExportService::class)->render(
                'exports.recettes-depenses',
                ['recettes' => $recettes, 'depenses' => $depenses, 'kpis' => $kpis],
                'État des Recettes et Dépenses',
                $period
            );

            return response()->streamDownload(fn () => print($pdf->output()), 'recettes-depenses-'.now()->format('Y-m-d').'.pdf');
        }

        $csv = "Type,Date,Libellé,Montant\n";
        foreach ($recettes as $r) {
            $csv .= 'Recette,'.\Carbon\Carbon::parse($r['date'])->format('d/m/Y').',"'.$r['label'].'",'.$r['amount']."\n";
        }
        foreach ($depenses as $d) {
            $csv .= 'Dépense,'.\Carbon\Carbon::parse($d['date'])->format('d/m/Y').',"'.$d['label'].'",-'.$d['amount']."\n";
        }

        return Response::streamDownload(fn () => print($csv), 'recettes-depenses-'.now()->format('Y-m-d').'.csv', ['Content-Type' => 'text/csv']);
    }

    public function render()
    {
        return view('livewire.rapports.recettes-depenses');
    }
}
