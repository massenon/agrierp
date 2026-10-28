<?php

namespace App\Livewire\Comptabilite;

use App\Actions\RecordDepreciationEntryAction;
use App\Models\ChartOfAccount;
use App\Models\FixedAsset;
use App\Models\TreasuryAccount;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.26 (Sprint 14) — REGISTRE DES IMMOBILISATIONS.
 *
 * Écran demandé explicitement, sans écran source dans le prototype : aucune
 * page `immobilisations.html` n'existe. La maquette de référence est donc
 * indirecte mais réelle — la **Note 2 des États Financiers**
 * (`etats-financiers.html`) ventile les immobilisations par nature (Bâtiments
 * et Constructions, Cages Modernes Galvanisées, Broyeurs et Équipements) avec
 * valeur brute, amortissement et valeur nette. Ce sont exactement les colonnes
 * et les natures reprises ici : rien d'inventé, l'écran donne enfin une source
 * de données à un tableau que le prototype affichait en dur.
 *
 * 🔴→✅ CE QUE CET ÉCRAN CORRIGE. La Note 2 portait, depuis le ticket 14.6,
 * une limite documentée : « le plan comptable ne trace les immobilisations
 * qu'au niveau agrégé de la classe 2, sans ventilation par nature d'actif ».
 * Le prototype lui-même s'en expliquait — « Hypothèse retenue : l'amortissement
 * cumulé de la période (380 000 FCFA) est intégralement imputé aux Broyeurs et
 * Équipements ». Avec ce registre, la ventilation cesse d'être une hypothèse.
 *
 * ⚠️ AUCUNE SUPPRESSION D'IMMOBILISATION. Un bien sort par CESSION ou
 * RÉFORME — changement de statut et date de sortie — jamais par effacement :
 * son historique comptable (dotations déjà passées) doit rester justifiable.
 * `is_active` reste réservé à l'archivage d'une saisie erronée.
 *
 * ⚠️ LA DOTATION EST DÉLÉGUÉE À `RecordDepreciationEntryAction`, qui poste
 * l'ÉCART et non le cumul — voir le raisonnement d'idempotence dans cette
 * Action. Cet écran ne calcule aucun montant comptable lui-même.
 */
#[Layout('layouts.app')]
class Immobilisations extends Component
{
    /** Filtre par nature = compte de classe 2 ; 'tous' par défaut. */
    #[Url]
    public string $filtreNature = 'tous';

    /** 'en_service' | 'cede' | 'reforme' | 'tous'. */
    #[Url]
    public string $filtreStatut = 'en_service';

    /** Date d'arrêté des calculs d'amortissement. */
    public string $dateArrete = '';

    public bool $showForm = false;

    public ?string $editingId = null;

    public string $code = '';

    public string $label = '';

    public string $accountCode = '';

    public string $acquisitionDate = '';

    public $acquisitionValue = '';

    public $residualValue = 0;

    public $durationYears = '';

    /**
     * Contrepartie de l'acquisition :
     *   ''         → reprise d'antériorité, aucune écriture (bien déjà en
     *                service avant la mise en route de l'ERP)
     *   'credit'   → acquisition à crédit, crédit 401 Fournisseurs
     *   <uuid>     → compte de trésorerie qui paie
     */
    public string $contrepartie = '';

    public bool $showCession = false;

    public ?string $cessionId = null;

    public string $cessionDate = '';

    public string $cessionStatus = 'cede';

    public string $cessionReason = '';

    public function mount(): void
    {
        $this->dateArrete = now()->format('Y-m-d');
        $this->acquisitionDate = now()->format('Y-m-d');
    }

    /** Natures de la ferme proposées d'origine (tickets 14.26 et 15.27). */
    public const NATURES_FERME = \App\Services\ImmobilisationService::NATURES_FERME;

    /**
     * Comptes de classe 2 hors amortissements (28x) : les biens eux-mêmes.
     *
     * TICKET 15.27 : le plan SYSCOHADA importé ajoute plus de 250 comptes de classe 2 (regroupements, financiers 26/27,
     * dépréciations 29…) qui ne sont pas des natures de bien choisies par la ferme. Le sélecteur garde donc ses natures
     * d'avant l'import : les trois de la ferme, plus toute nature déjà portée par un bien enregistré. Aucune règle
     * d'« imputabilité » n'est inventée ; la liste définitive relève du cabinet FAGUEZ (phase B).
     */
    public function getNaturesProperty()
    {
        return app(\App\Services\ImmobilisationService::class)->natures();
    }

    public function getComptesTresorerieProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    public function getBiensProperty()
    {
        $query = FixedAsset::active()->orderBy('acquisition_date')->orderBy('code');

        if ($this->filtreNature !== 'tous') {
            $query->where('account_code', $this->filtreNature);
        }

        if ($this->filtreStatut !== 'tous') {
            $query->where('status', $this->filtreStatut);
        }

        return $query->get();
    }

    /**
     * Ventilation par nature — la structure même de la Note 2 des États
     * Financiers. Calculée sur TOUT le registre en service, jamais sur la
     * liste filtrée : un total qui bougerait avec un filtre d'affichage ne
     * serait plus un total de bilan.
     *
     * @return array<int, array{code: string, label: string, brut: float, amortissement: float, net: float, nombre: int}>
     */
    public function getVentilationProperty(): array
    {
        $biens = FixedAsset::active()->inService()->get()->groupBy('account_code');
        $libelles = $this->natures->keyBy('code');

        $lignes = [];

        foreach ($biens as $compte => $groupe) {
            $brut = round($groupe->sum(fn ($b) => (float) $b->acquisition_value), 2);
            $amortissement = round($groupe->sum(fn ($b) => $b->cumulAmortissement($this->dateArrete)), 2);

            $lignes[] = [
                'code' => $compte,
                'label' => $libelles[$compte]->label ?? $compte,
                'brut' => $brut,
                'amortissement' => $amortissement,
                'net' => round($brut - $amortissement, 2),
                'nombre' => $groupe->count(),
                // Part non entrée en comptabilité — ce qui explique tout écart
                // entre ce registre et l'Actif Immobilisé du Bilan.
                'hors_compta' => round($groupe->where('is_capitalized', false)->sum(fn ($b) => (float) $b->acquisition_value), 2),
            ];
        }

        usort($lignes, fn ($a, $b) => strcmp($a['code'], $b['code']));

        return $lignes;
    }

    /** @return array{brut: float, amortissement: float, net: float, a_doter: float} */
    public function getKpisProperty(): array
    {
        $brut = round(array_sum(array_column($this->ventilation, 'brut')), 2);
        $amortissement = round(array_sum(array_column($this->ventilation, 'amortissement')), 2);

        return [
            'brut' => $brut,
            'amortissement' => $amortissement,
            'net' => round($brut - $amortissement, 2),
            'a_doter' => app(RecordDepreciationEntryAction::class)->montantADoter($this->dateArrete),
            'hors_compta' => round(array_sum(array_column($this->ventilation, 'hors_compta')), 2),
        ];
    }

    public function updatedDateArrete(): void
    {
        // Les 3 propriétés dérivent de la date d'arrêté : les invalider ici
        // évite d'afficher des amortissements calculés à l'ancienne date
        // (défaut de mémoïsation constaté aux tickets 14.9 et 14.11).
        unset($this->ventilation, $this->kpis, $this->biens);
    }

    public function nouveau(): void
    {
        $this->authorize('manage-comptabilite');

        $this->reset(['editingId', 'code', 'label', 'accountCode', 'acquisitionValue', 'residualValue', 'durationYears', 'contrepartie']);
        $this->resetValidation();
        $this->acquisitionDate = now()->format('Y-m-d');
        $this->residualValue = 0;
        $this->showForm = true;
    }

    public function editer(string $id): void
    {
        $this->authorize('manage-comptabilite');

        $bien = FixedAsset::findOrFail($id);

        $this->editingId = $bien->id;
        $this->code = $bien->code;
        $this->label = $bien->label;
        $this->accountCode = $bien->account_code;
        $this->acquisitionDate = $bien->acquisition_date->format('Y-m-d');
        $this->acquisitionValue = (float) $bien->acquisition_value;
        $this->residualValue = (float) $bien->residual_value;
        $this->durationYears = $bien->duration_years;
        $this->resetValidation();
        $this->showForm = true;
    }

    public function enregistrer(): void
    {
        // ⚠️ Autorisation revérifiée sur l'ACTION qui écrit, pas seulement à
        // l'ouverture du formulaire : `showForm` est une propriété publique,
        // donc modifiable côté client (leçon du ticket 12.4).
        $this->authorize('manage-comptabilite');

        $service = app(\App\Services\ImmobilisationService::class);

        $valide = $this->validate($service->regles($this->editingId), [], \App\Services\ImmobilisationService::ATTRIBUTS);

        if ($this->editingId) {
            try {
                $service->modifier(FixedAsset::findOrFail($this->editingId), $valide);
            } catch (\Illuminate\Validation\ValidationException $e) {
                $this->addError('acquisitionValue', $e->validator->errors()->first());

                return;
            }
            $message = 'Immobilisation modifiée.';
        } else {
            $message = $service->enregistrer($valide)['message'];
        }

        $this->showForm = false;
        $this->editingId = null;
        unset($this->biens, $this->ventilation, $this->kpis);

        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function ouvrirCession(string $id): void
    {
        $this->authorize('manage-comptabilite');

        $this->cessionId = $id;
        $this->cessionDate = now()->format('Y-m-d');
        $this->cessionStatus = 'cede';
        $this->cessionReason = '';
        $this->resetValidation();
        $this->showCession = true;
    }

    public function confirmerCession(): void
    {
        $this->authorize('manage-comptabilite');

        $bien = FixedAsset::findOrFail($this->cessionId);

        $service = app(\App\Services\ImmobilisationService::class);

        $valide = $this->validate($service->reglesSortie($bien), \App\Services\ImmobilisationService::MESSAGES_SORTIE, \App\Services\ImmobilisationService::ATTRIBUTS_SORTIE);

        $service->sortir($bien, $valide['cessionDate'], $valide['cessionStatus'], $valide['cessionReason']);

        $this->showCession = false;
        $this->cessionId = null;
        unset($this->biens, $this->ventilation, $this->kpis);

        $this->dispatch('toast', message: 'Sortie enregistrée — le bien cesse de s\'amortir à cette date.', type: 'success');
    }

    /**
     * Passe la dotation aux amortissements de la période.
     *
     * ⚠️ Le montant n'est PAS repris d'une propriété publique affichée
     * (client-modifiable) : l'Action le recalcule elle-même à partir du
     * registre et du grand livre.
     */
    public function passerDotation(): void
    {
        $this->authorize('manage-comptabilite');

        try {
            $ecriture = app(\App\Services\ImmobilisationService::class)->passerDotation($this->dateArrete);
        } catch (\App\Exceptions\ClosedFiscalYearException|\App\Exceptions\NoOpenFiscalYearException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        unset($this->kpis);

        if (! $ecriture) {
            $this->dispatch('toast', message: 'Aucune dotation à passer à cette date — les amortissements sont déjà comptabilisés.', type: 'info');

            return;
        }

        $this->dispatch('toast',
            message: 'Dotation comptabilisée : '.number_format((float) $ecriture->total_debit, 0, ',', ' ').' FCFA (débit 681 / crédit 281).',
            type: 'success');
    }

    public function render()
    {
        return view('livewire.comptabilite.immobilisations', ['title' => 'Comptabilité > Immobilisations']);
    }
}
