<?php

namespace App\Livewire\Comptabilite;

use App\Models\FiscalYear;
use App\Models\PeriodicClosure;
use App\Services\ClotureExerciceService;
use Illuminate\Support\Facades\Auth;
use App\Services\BankReconciliationService;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 10.6 (Sprint 10) — cloture-exercice.html → Livewire\Comptabilite\ClotureExercice
 * "Assistant de clôture d'exercice comptable (N → N+1)" — Document 01
 * §6.6, assistant à 3 étapes réelles, aucune approximée.
 *
 * ⚠️ Étape 1 (Travaux d'Inventaire) : le prototype la traite comme un
 * simple toast sans état persistant — corrigé (`fiscal_years.step1_confirmed_at`
 * réellement enregistré, ticket 10.6 addendum). Les travaux eux-mêmes
 * (rapprochements, amortissements, provisions, FNP/FAE) restent des
 * écritures manuelles réelles à passer par le Journal Comptable (ticket
 * 10.4) AVANT de confirmer cette étape — cet écran ne les invente pas,
 * il ne fait que tracer la confirmation que l'utilisateur les a faites.
 *
 * Étape 2 (Solde des Comptes de Gestion) : RÉEL — calcule le solde de
 * chaque compte de classe 6 (charges) et 7 (produits) sur l'exercice,
 * génère UNE écriture équilibrée qui solde chacun de ces comptes à zéro
 * avec pour contrepartie le compte 131 (Bénéfice) si résultat positif ou
 * 139 (Perte) si négatif — jamais une simulation, une vraie écriture
 * dans le grand livre.
 *
 * Étape 3 (Clôture définitive) : RÉEL — verrouille (`is_locked = true`)
 * TOUTES les écritures actives de l'exercice clôturé (🔁 ticket 15.53 : plus
 * irréversible — `rouvrirExercice`, administrateur, journalisé), crée le nouvel exercice
 * (statut ouvert), génère les écritures de report à nouveau (RAN) pour
 * les comptes de bilan (classes 1 à 5) au 1er janvier du nouvel exercice.
 *
 * ⚠️ CORRECTION CRITIQUE APPORTÉE À `AccountingEntryService` DANS CE
 * MÊME TICKET : `record()` recherchait auparavant "le dernier exercice
 * ouvert" sans vérifier que la DATE de l'écriture tombe réellement dans
 * cet exercice — une fois qu'un exercice peut être réellement clôturé
 * (ce ticket), une écriture antidatée aurait pu être rattachée à tort au
 * nouvel exercice. Corrigé pour résoudre l'exercice qui couvre
 * effectivement la date, et refuser toute écriture dont la date tombe
 * dans un exercice clos (Document 01 §6.6 point 4, `ClosedFiscalYearException`).
 *
 * "Lettrage Bancaire" (KPI) : 🔴→✅ LIVRÉ AU TICKET 14.43. Le mécanisme
 * manquait au projet entier, pas à cet écran ; il existe depuis le ticket
 * 14.8 (`BankReconciliationService`, import de relevé CSV, lettrage ligne
 * à ligne) sans que cette carte y soit jamais revenue. Le taux est
 * désormais calculé sur l'exercice sélectionné, les deux côtés confondus
 * (livre ET relevé). ⚠️ Aucun relevé importé ⇒ « — » et le motif, JAMAIS
 * 100 % : zéro ligne lettrée sur zéro n'est pas un rapprochement parfait,
 * et l'afficher ainsi autoriserait une clôture sur une trésorerie non
 * vérifiée.
 */
#[Layout('layouts.app')]
class ClotureExercice extends Component
{
    public string $selectedYear = '';

    /** Ticket 14.14 — onglet actif : 'periodique' (defaut, comme le prototype) ou 'annuelle'. */
    public string $tab = 'periodique';

    /** Mois vise par la cloture periodique, format YYYY-MM. */
    public string $periodeACloturer = '';

    /** Cloture visee par la decloture exceptionnelle. */
    public string $closureAReouvrir = '';

    public function mount(): void
    {
        // Ticket EX3 — deux exercices peuvent être ouverts (N et N+1, de janvier à la clôture de N) : l'écran s'ouvre
        // sur celui qu'il faut clôturer, le plus ANCIEN encore ouvert (et non `FiscalYear::current()`, le plus récent).
        $this->selectedYear = (string) (FiscalYear::where('status', 'ouvert')->min('year') ?? now()->year);
        $this->periodeACloturer = now()->format('Y-m');
    }

    public function getFiscalYearProperty(): ?FiscalYear
    {
        return FiscalYear::where('year', $this->selectedYear)->first();
    }

    public function changeYear(int $delta): void
    {
        $this->selectedYear = (string) ((int) $this->selectedYear + $delta);
        $this->refreshComputed();
    }

    /**
     * 🔴→✅ TICKET 14.2 — BUG RÉEL CORRIGÉ : `fiscalYear` et `kpis` sont des
     * propriétés calculées, et Livewire les **mémoïse pour la durée de la
     * requête** (`SupportLegacyComputedPropertySyntax` : la valeur est
     * poussée dans `store($this)->find('computedProperties', ...)` au premier
     * accès). Une action qui LIT l'une d'elles puis MODIFIE les données
     * derrière laisse donc le rendu qui suit afficher la valeur d'AVANT
     * l'action.
     *
     * Symptôme réel observé (test `ClotureExerciceTest` — qui n'avait jamais
     * pu s'exécuter avant le ticket 14.1, faute de `tests/TestCase.php`) :
     * après un clic sur « Solder les comptes de gestion », l'écran continuait
     * d'annoncer « 2 comptes à solder » alors que l'écriture de solde était
     * bel et bien enregistrée et les comptes réellement soldés — l'opérateur
     * pouvait croire l'étape 2 en échec et la relancer.
     *
     * Toute action de cet écran qui change `selectedYear` ou écrit en base
     * appelle donc cette méthode : le rendu repart de l'état réel.
     */
    private function refreshComputed(): void
    {
        unset($this->fiscalYear, $this->kpis);
    }

    /** Solde de chaque compte de classe 6/7 sur l'exercice sélectionné — un seul point de calcul (`ClotureExerciceService`). */
    private function gestionBalances(): array
    {
        return app(ClotureExerciceService::class)->soldesDeGestion($this->fiscalYear);
    }

    public function getKpisProperty(): array
    {
        $indicateurs = app(ClotureExerciceService::class)->indicateurs($this->fiscalYear);

        $lettrage = $this->fiscalYear
            ? app(BankReconciliationService::class)->tauxDeLettrage(
                $this->fiscalYear->start_date->format('Y-m-d'),
                $this->fiscalYear->end_date->format('Y-m-d'),
            )
            : ['taux' => null, 'lignes' => 0, 'lettrees' => 0, 'comptes_sans_releve' => 0];

        return [
            'resultat' => $indicateurs['resultat'],
            'comptes_a_solder' => $indicateurs['comptes_a_solder'],
            'lettrage' => $lettrage,
        ];
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR VÉRIFICATION NIVEAU 2 : bouton "Exporter
     * PDF" totalement absent — réutilise `gestionBalances()` déjà réel
     * (un seul point de vérité pour "quels comptes sont à solder"),
     * enrichi avec les libellés de compte pour un export lisible.
     */
    public function exportClotureExercicePdf()
    {
        $this->authorize('view-comptabilite');

        $balances = $this->gestionBalances();
        $accountIds = array_column($balances, 'account_id');
        $accounts = \App\Models\ChartOfAccount::whereIn('id', $accountIds)->get()->keyBy('id');

        $rows = collect($balances)->map(fn ($b) => [
            'code' => $accounts[$b['account_id']]->code ?? '—',
            'label' => $accounts[$b['account_id']]->label ?? '—',
            'class' => $b['class'],
            'balance' => $b['balance'],
        ]);

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.cloture-exercice',
            ['rows' => $rows, 'fiscalYear' => $this->fiscalYear, 'kpis' => $this->kpis],
            "Bascule & Clôture d'Exercice Comptable",
            $this->fiscalYear ? 'Exercice '.$this->fiscalYear->year : ''
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'cloture-exercice-'.now()->format('Y-m-d').'.pdf');
    }

    /* ==================== CLÔTURE PÉRIODIQUE (ticket 14.14) ==================== */

    /**
     * Ticket 14.14 — Clôture Périodique : verrouillage mensuel léger.
     *
     * Onglet marqué « (nouveau) » dans le prototype source, jamais
     * implémenté. Distinct de la clôture ANNUELLE : il n'affecte pas le
     * Report à Nouveau et reste réversible par un Administrateur.
     *
     * ⚠️ LE VERROU EST RÉELLEMENT APPLIQUÉ — c'est le point qui fait la
     * différence entre une fonctionnalité et une liste décorative :
     * `JournalComptable::saveEntry()` refuse toute écriture, nouvelle ou
     * modifiée, dont la date tombe dans un mois clôturé. Sans ce contrôle,
     * clôturer un mois n'aurait strictement aucun effet.
     */
    public function getPeriodesCloturablesProperty(): array
    {
        return collect(range(0, 11))
            ->mapWithKeys(function ($i) {
                $date = now()->startOfMonth()->subMonths($i);

                return [$date->format('Y-m') => ucfirst($date->translatedFormat('F Y'))];
            })
            ->all();
    }

    public function getClosuresProperty()
    {
        return PeriodicClosure::with(['closedBy', 'reopenedBy'])->orderByDesc('period')->get();
    }

    /**
     * Balance du mois sélectionné — la clôture est REFUSÉE si Σdébit ≠ Σcrédit.
     * Contrôle serveur, jamais un simple affichage contournable.
     */
    public function getPeriodeBalanceProperty(): array
    {
        return app(ClotureExerciceService::class)->balanceDePeriode($this->periodeACloturer);
    }

    public function getPeriodeDejaClotureeProperty(): bool
    {
        return app(ClotureExerciceService::class)->periodeDejaCloturee($this->periodeACloturer);
    }

    public function cloturerPeriode(): void
    {
        $this->authorize('close-fiscal-year');

        try {
            app(ClotureExerciceService::class)->cloturerPeriode($this->periodeACloturer, Auth::id());
        } catch (\DomainException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-confirm-cloture-periodique');
        $this->dispatch('toast', message: 'Mois clôturé — les écritures de cette période sont désormais verrouillées.', type: 'success');
        unset($this->closures, $this->periodeDejaCloturee);
    }

    /**
     * Déclôture EXCEPTIONNELLE — réservée à l'Administrateur (`manage-modules`,
     * la permission réellement admin-seul du seeder), tracée avec identité et
     * horodatage. La ligne n'est jamais supprimée : l'historique d'une action
     * exceptionnelle doit rester consultable.
     */
    public function decloturerPeriode(string $id): void
    {
        $this->authorize('manage-modules');

        $closure = PeriodicClosure::findOrFail($id);

        try {
            app(ClotureExerciceService::class)->decloturerPeriode($closure, Auth::id());
        } catch (\DomainException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-confirm-decloture');
        $this->dispatch('toast', message: "Mois déclôturé — action exceptionnelle journalisée dans les Logs d'Audit.", type: 'warning');
        unset($this->closures, $this->periodeDejaCloturee);
    }

    /**
     * Ticket 15.53 — réouverture d'un exercice clôturé. Action EXCEPTIONNELLE réservée à l'administrateur
     * (même droit que la déclôture d'un mois), journalisée ; la logique vit dans `ReopenFiscalYearAction`.
     */
    public function rouvrirExercice(): void
    {
        $this->authorize('manage-modules');
        $year = $this->fiscalYear;

        if (! $year) {
            return;
        }

        try {
            app(ClotureExerciceService::class)->rouvrirExercice($year);
        } catch (\DomainException $e) {
            $this->dispatch('close-modal', name: 'modal-confirm-reouverture');
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-confirm-reouverture');
        $this->dispatch('toast', message: "Exercice {$year->year} rouvert — report à nouveau contre-passé, action journalisée dans les Logs d'Audit.", type: 'warning');
        $this->refreshComputed();
    }

    public function confirmStep1(): void
    {
        $this->authorize('close-fiscal-year');
        $year = $this->fiscalYear;
        if (! $year) {
            return;
        }

        app(ClotureExerciceService::class)->confirmerEtape1($year);
        $this->dispatch('toast', message: 'Étape 1 validée — rapprochements et régularisations confirmés.', type: 'success');
    }

    /* ==================== OUVERTURE DE N+1 (ticket EX3) ==================== */

    /**
     * Ticket EX3 (EF2) — le bouton « Ouvrir l'exercice N+1 » est offert, à partir du 1er décembre de N, quand N (l'exercice
     * affiché) est ouvert et que N+1 n'existe pas. Indicatif : `ouvrirExerciceSuivant` rejuge tout au serveur.
     */
    public function getPeutOuvrirSuivantProperty(): bool
    {
        $year = $this->fiscalYear;

        return $year !== null
            && $year->status === 'ouvert'
            && app(\App\Services\OuvertureExerciceService::class)
                ->refusOuverture($year->year + 1, \App\Services\OuvertureExerciceService::BOUTON) === null;
    }

    public function ouvrirExerciceSuivant(): void
    {
        $this->authorize('close-fiscal-year');

        $annee = (int) $this->selectedYear + 1;

        try {
            app(ClotureExerciceService::class)->ouvrirExerciceSuivant($annee);
        } catch (\DomainException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $this->dispatch('toast', message: "Exercice {$annee} ouvert (du 01/01/{$annee} au 31/12/{$annee}).", type: 'success');
        $this->refreshComputed();
    }

    /* ==================== GARDES DE LA CLÔTURE (ticket EX4) ==================== */

    /** Pourquoi l'étape 3 est refusée, ou `null` (`ClotureExerciceService`, EX4 : le même motif grise le bouton et refuse l'appel). */
    public function motifRefusCloture(?FiscalYear $year): ?string
    {
        return app(ClotureExerciceService::class)->motifRefusCloture($year);
    }

    public function getMotifRefusClotureProperty(): ?string
    {
        return $this->motifRefusCloture($this->fiscalYear);
    }

    public function soldeComptesGestion(): void
    {
        // 🔴→✅ Ticket EX4 — l'étape 2 écrit au journal (solde des classes 6 et 7) : même droit que les étapes 1 et 3.
        $this->authorize('close-fiscal-year');

        $year = $this->fiscalYear;
        $service = app(ClotureExerciceService::class);

        if (! $year || empty($service->soldesDeGestion($year))) {
            $this->dispatch('toast', message: ClotureExerciceService::MOTIF_RIEN_A_SOLDER, type: 'warning');

            return;
        }

        try {
            $resultat = $service->soldeComptesGestion($year);
        } catch (\DomainException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        // Les comptes 6/7 viennent d'être soldés : `kpis` porte encore l'état d'avant l'écriture.
        $this->refreshComputed();

        $this->dispatch('toast', message: 'Comptes de charges et produits soldés — résultat net calculé : '.number_format($resultat, 0, ',', ' ').' FCFA.', type: 'success');
    }

    public function confirmCloture(): void
    {
        $this->authorize('close-fiscal-year');
        $year = $this->fiscalYear;

        // Tickets EX4/EX5 — les gardes de l'étape 3 et la transaction vivent dans `ClotureExerciceService` ; un refus ne
        // laisse rien d'écrit et se dit en clair (jamais une erreur 500).
        try {
            app(ClotureExerciceService::class)->cloturerExercice($year, Auth::id());
        } catch (\DomainException $e) {
            $this->dispatch('close-modal', name: 'modal-confirm-cloture');
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-confirm-cloture');
        $this->dispatch('toast', message: "Exercice {$year->year} clôturé avec succès — exercice ".($year->year + 1).' ouvert.', type: 'success');
        $this->selectedYear = (string) ($year->year + 1);

        // 🔴→✅ TICKET 14.2 — `fiscalYear` a été lu pour l'exercice N et resterait mémoïsé : l'écran afficherait l'exercice
        // qui vient d'être CLÔTURÉ au lieu du nouvel exercice N+1 annoncé par son propre message de succès.
        $this->refreshComputed();
    }

    public function render()
    {
        return view('livewire.comptabilite.cloture-exercice', ['title' => 'Comptabilité > Clôture Exercice']);
    }
}
