<?php

namespace App\Livewire\Comptabilite;

use App\Models\ChartOfAccount;
use App\Services\FinancialReportService;
use App\Support\ExerciceChoisi;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.1 (Sprint 14) — grand-livre.html → Livewire\Comptabilite\GrandLivre
 * "Écritures chronologiques d'un compte, avec solde progressif."
 *
 * Premier des 5 écrans comptables ajoutés au prototype après le Sprint 12
 * (Grand Livre, Balance Générale, États Financiers, Déclaration TVA,
 * Rapprochement Bancaire) — le hub Laravel n'en référençait aucun alors que
 * `comptabilite-hub.html` les liait déjà : écart réel comblé ici pour le
 * premier d'entre eux.
 *
 * Calcul délégué à `FinancialReportService::grandLivre()` et non fait dans ce
 * composant : la Balance Générale et les États Financiers (tickets suivants)
 * reposent sur les mêmes soldes par compte. Un seul point de vérité, même
 * discipline que `Bilan` (ticket 10.5) — calculé exclusivement depuis le
 * grand livre (`accounting_entries` / `accounting_entry_lines`), jamais
 * recalculé depuis des tables métier disjointes.
 *
 * ⚠️ TROUVÉ / DOCUMENTÉ — écarts réels entre le prototype et le plan
 * comptable réellement semé (`ChartOfAccountsSeeder`), NON corrigés
 * silencieusement :
 *   - le prototype propose `661 — Personnel (Salaires)` dans son menu
 *     déroulant ; ce compte n'existe pas dans le seeder actuel (qui est
 *     explicitement un extrait, pas le plan SYSCOHADA complet) ;
 *   - le prototype écrit `521` et `5212`, le seeder `521101` (Banque) et
 *     `521201` (Mobile Money).
 * Ce composant n'invente aucun compte : le menu déroulant est alimenté par
 * `chart_of_accounts` réel (transformation légitime prototype → Laravel,
 * cf. L1 §4 « données statiques codées en dur → requêtes Eloquent réelles »).
 * Les comptes manquants apparaîtront d'eux-mêmes dès que le plan comptable
 * SYSCOHADA complet sera semé, sans modification de cet écran.
 *
 * Les 4 cartes KPI réutilisent `x-kpi-card` plutôt que de recopier les
 * `<div>` du prototype : couleurs et libellés identiques (emerald /
 * info-blue / error-red / accent-yellow), composant partagé déjà utilisé par
 * tous les autres écrans convertis — cohérence de pattern (A2 §5) préférée à
 * une variante locale de plus.
 */
#[Layout('layouts.app')]
class GrandLivre extends Component
{
    #[Url]
    public string $accountId = '';

    #[Url]
    public string $startDate = '';

    #[Url]
    public string $endDate = '';

    #[Url]
    public string $search = '';

    public function mount(): void
    {
        // Ticket EX7 (EF9) — période par défaut DANS l'exercice affiché : du 1er du mois à aujourd'hui quand il
        // contient le jour, l'exercice entier sinon (2026 consulté en 2027) ; une date d'URL hors exercice est bornée.
        [$debut, $fin] = ExerciceChoisi::periodeParDefaut(now()->startOfMonth()->format('Y-m-d'), now()->format('Y-m-d'));
        [$this->startDate, $this->endDate] = ExerciceChoisi::bornerPeriode($this->startDate !== '' ? $this->startDate : $debut, $this->endDate !== '' ? $this->endDate : $fin);

        if ($this->accountId === '') {
            $this->accountId = (string) $this->defaultAccountId();
        }
    }

    /** Ticket EX7 (EF9) — une date saisie hors de l'exercice affiché est ramenée à sa borne. */
    public function updatedStartDate(): void
    {
        [$this->startDate, $this->endDate] = ExerciceChoisi::bornerPeriode($this->startDate, $this->endDate);
    }

    public function updatedEndDate(): void
    {
        $this->updatedStartDate();
    }

    /**
     * Le prototype ouvrait sur `531 — Caisse` (1re option de son menu figé).
     * On conserve cette intention quand le compte existe réellement, sans
     * jamais coder en dur un identifiant : repli sur le plus petit code actif
     * si le plan comptable semé ne contient pas 531.
     */
    private function defaultAccountId(): ?string
    {
        return ChartOfAccount::where('is_active', true)->where('code', '531')->value('id')
            ?? ChartOfAccount::where('is_active', true)->orderBy('code')->value('id');
    }

    public function getAccountsProperty()
    {
        return ChartOfAccount::where('is_active', true)->orderBy('code')->get();
    }

    public function getLedgerProperty(): array
    {
        return app(FinancialReportService::class)->grandLivre(
            $this->accountId,
            $this->startDate,
            $this->endDate,
            $this->search,
        );
    }

    public function exportGrandLivrePdf()
    {
        $this->authorize('view-comptabilite');

        $ledger = $this->ledger;
        $account = $ledger['account'];

        $title = $account
            ? 'Grand Livre — Compte '.$account->code.' — '.$account->label
            : 'Grand Livre';

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.grand-livre',
            ['ledger' => $ledger],
            $title,
            'Période du '.\Carbon\Carbon::parse($this->startDate)->format('d/m/Y').' au '.\Carbon\Carbon::parse($this->endDate)->format('d/m/Y')
                .($ledger['ouverture']['provisoire'] ? ' — À-nouveaux provisoires' : '')
        );

        return response()->streamDownload(
            fn () => print ($pdf->output()),
            'grand-livre-'.($account?->code ?? 'compte').'-'.now()->format('Y-m-d').'.pdf'
        );
    }

    public function render()
    {
        return view('livewire.comptabilite.grand-livre', ['title' => 'Comptabilité > Grand Livre']);
    }
}
