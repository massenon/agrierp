<?php

namespace App\Livewire\Comptabilite;

use App\Models\ChartOfAccount;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 10.3 (Sprint 10) — plan-comptable.html → Livewire\Comptabilite\PlanComptable
 * "Nomenclature des comptes du référentiel SYSCOHADA révisé."
 *
 * CRUD réel sur `chart_of_accounts` (table déjà créée au Sprint 2,
 * `ChartOfAccountsSeeder` déjà livré en extrait représentatif — le plan
 * SYSCOHADA complet reste à compléter par vos soins avant la démo
 * finale, documenté dans `SEEDER_TEST.md`, pas re-saisi ici).
 *
 * ⚠️ ARCHIVAGE BLOQUÉ SI LE COMPTE EST DÉJÀ UTILISÉ : un compte déjà
 * référencé par au moins une `AccountingEntryLine` ne peut pas être
 * archivé — l'archiver casserait la lisibilité de toutes les écritures
 * passées qui le citent. Ce contrôle n'existe dans aucun document
 * explicite mais découle directement de la contrainte
 * `restrictOnDelete()` déjà posée sur `accounting_entry_lines.account_id`
 * (ticket 10.1) — bloquer AVANT plutôt que de laisser l'utilisateur
 * découvrir une erreur SQL confuse.
 *
 * "Exercice" (KPI) : l'exercice affiché (`ExerciceChoisi`, ticket EX7 ; `FiscalYear::current()` avant), un seul point de
 * vérité — jamais une valeur codée en dur.
 *
 * 🔴→✅ ÉCRAN DE RÉFÉRENCE POUR LE PATTERN RBAC CRUD AU NIVEAU ACTION,
 * trouvé manquant par l'audit RBAC (ticket 13.1 avait déjà signalé que
 * 1 seul composant sur 76 avait ce contrôle). "Rôles dynamiques" étant
 * confirmé réel et fonctionnel (un admin peut créer un rôle personnalisé
 * avec `view-comptabilite` SANS `manage-comptabilite`, ex. un profil
 * "Consultant Comptable" en lecture seule) — sans ce contrôle, un tel
 * rôle personnalisé aurait pu voir ET utiliser avec succès les boutons
 * Nouveau/Modifier/Archiver malgré l'absence de la permission `manage-`,
 * puisque seule la ROUTE (`can:view-comptabilite`) était gardée, jamais
 * chaque action individuelle. `$this->authorize('manage-comptabilite')`
 * ajouté aux 4 méthodes mutantes (`newAccount`, `editAccount`,
 * `saveAccount`, `archiveAccount`) — la vue masque également les boutons
 * correspondants via `@can('manage-comptabilite')` pour que l'absence de
 * droit soit visible avant même le clic, pas seulement bloquée après.
 * PATTERN À GÉNÉRALISER aux 75 autres composants mutants du projet —
 * chantier systématique hors périmètre d'un seul écran, documenté ici
 * comme référence concrète plutôt que laissé abstrait.
 */
#[Layout('layouts.app')]
class PlanComptable extends Component
{
    #[Url]
    public string $search = '';

    public ?string $editingId = null;

    public string $code = '';

    public string $label = '';

    public string $class = '';

    /**
     * TICKET 15.27 — le plan compte désormais 1 300+ comptes : l'écran n'affiche que les premiers (tri par code) et
     * « Afficher plus » en ajoute autant. La recherche porte sur TOUT le plan. Le KPI et l'export PDF gardent la totalité.
     */
    public const LIMITE_AFFICHAGE = 200;

    public int $limite = self::LIMITE_AFFICHAGE;

    public function getKpisProperty(): array
    {
        return [
            'comptes_actifs' => ChartOfAccount::where('is_active', true)->count(),
            // Ticket EX7 — l'exercice AFFICHÉ (sélecteur de la barre supérieure), plus le plus récent ouvert.
            'exercice' => \App\Support\ExerciceChoisi::exercice()?->year ?? '—',
        ];
    }

    private function requeteComptes()
    {
        return ChartOfAccount::where('is_active', true)
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('code', 'like', '%'.$this->search.'%')->orWhere('label', 'like', '%'.$this->search.'%')))
            ->orderBy('code');
    }

    /** Page affichée à l'écran (les `limite` premiers comptes correspondant à la recherche). */
    public function getAccountsProperty()
    {
        return $this->requeteComptes()->limit($this->limite)->get();
    }

    /** Nombre total de comptes correspondant à la recherche (au-delà de la page affichée). */
    public function getTotalCorrespondantProperty(): int
    {
        return $this->requeteComptes()->count();
    }

    /** La totalité des comptes correspondant à la recherche : l'export PDF ne se limite pas à la page. */
    public function comptesPourExport()
    {
        return $this->requeteComptes()->get();
    }

    public function afficherPlus(): void
    {
        $this->limite += self::LIMITE_AFFICHAGE;
    }

    public function updatedSearch(): void
    {
        $this->limite = self::LIMITE_AFFICHAGE;
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR VÉRIFICATION NIVEAU 2 : bouton "Exporter
     * PDF" totalement absent — même schéma déjà trouvé sur de nombreux
     * écrans de ce projet. Pas de permission `export-comptabilite`
     * dédiée dans le seeder — `view-comptabilite` réutilisée.
     */
    public function exportPlanComptablePdf()
    {
        $this->authorize('view-comptabilite');

        $accounts = $this->comptesPourExport();

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.plan-comptable',
            ['accounts' => $accounts, 'classLabels' => $this->classLabels()],
            'Plan Comptable SYSCOHADA',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'plan-comptable-'.now()->format('Y-m-d').'.pdf');
    }

    private function classLabels(): array
    {
        return [
            1 => '1 - Ressources', 2 => '2 - Immobilisations', 3 => '3 - Stocks',
            4 => '4 - Tiers', 5 => '5 - Trésorerie', 6 => '6 - Charges', 7 => '7 - Produits', 8 => '8 - Autres', 9 => '9 - Hors bilan et analytique',
        ];
    }

    public function classLabel(int $class): string
    {
        return $this->classLabels()[$class] ?? (string) $class;
    }

    public function newAccount(): void
    {
        $this->authorize('manage-comptabilite');

        $this->reset(['editingId', 'code', 'label', 'class']);
        $this->dispatch('open-modal', name: 'modal-create-plan-comptable');
    }

    public function editAccount(string $id): void
    {
        $this->authorize('manage-comptabilite');

        $account = ChartOfAccount::findOrFail($id);
        $this->editingId = $account->id;
        $this->code = $account->code;
        $this->label = $account->label;
        $this->class = (string) $account->class;
        $this->dispatch('open-modal', name: 'modal-create-plan-comptable');
    }

    public function saveAccount(): void
    {
        $this->authorize('manage-comptabilite');

        // Ticket CP-1 — `PlanComptableService`, partagé avec l'envoi du poste.
        $service = app(\App\Services\PlanComptableService::class);
        $this->validate($service->regles($this->editingId));

        $payload = ['code' => $this->code, 'label' => $this->label, 'class' => (int) $this->class];

        if ($this->editingId) {
            $service->modifier(ChartOfAccount::findOrFail($this->editingId), $payload);
            $message = 'Modification enregistrée avec succès.';
        } else {
            $service->creer($payload);
            $message = 'Compte créé avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-plan-comptable');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function archiveAccount(string $id): void
    {
        $this->authorize('manage-comptabilite');

        try {
            app(\App\Services\PlanComptableService::class)->archiver(ChartOfAccount::findOrFail($id));
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->dispatch('toast', message: $e->validator->errors()->first(), type: 'error');

            return;
        }

        $this->dispatch('toast', message: 'Compte archivé avec succès.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.comptabilite.plan-comptable', ['title' => 'Comptabilité > Plan Comptable']);
    }
}
