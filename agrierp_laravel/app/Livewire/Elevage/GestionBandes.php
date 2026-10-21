<?php

namespace App\Livewire\Elevage;

use App\Actions\SaisieBandeAction;
use App\Actions\TransferBetweenLotsAction;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Rules\UniqueNormalise;
use App\Services\EffectifParCategorieService;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 3.3 (Sprint 3) — gestion-bandes.html → Livewire\Elevage\GestionBandes
 * "Numérotation continue inter-bandes" (Document 05).
 *
 * ⚠️ RÉCONCILIATION DOCUMENTÉE : le champ "Code Unique de la Bande" du
 * prototype est un texte libre pré-rempli par l'utilisateur lui-même, sans
 * continuité réelle possible dans une maquette statique sans backend.
 * `LivestockLot::suggestNextCode()` (nouveau, ticket 3.3) pré-remplit le
 * champ avec le prochain code réellement disponible pour l'espèce choisie
 * (dérivé des préfixes configurés au ticket 2.8), tout en laissant le
 * champ modifiable — fidèle au comportement du champ texte du prototype,
 * tout en honorant réellement l'exigence de continuité du ticket.
 *
 * ⚠️ ÉCART DE SCHÉMA : la modale d'édition du prototype propose 3 statuts
 * ("Actif", "Vendu", "Clôturé") alors que `livestock_lots.status` (schéma
 * documenté, `FULL_MIGRATIONS_DATABASE.md` §6) n'admet que 2 valeurs
 * (`actif`, `cloture`). "Vendu" n'est pas un statut de bande mais une
 * CAUSE de clôture — conservé comme tel : le formulaire propose Actif/
 * Clôturé uniquement, conforme au schéma documenté, sans inventer une 3e
 * valeur d'enum non spécifiée ailleurs.
 *
 * ⚠️ PÉRIMÈTRE DU TIROIR DE DÉTAIL : "Autonomie Alimentaire" reste en
 * attente (aucune table ne suit de stock d'aliment réel avant le Sprint 6,
 * même constat qu'au ticket 3.2). Le résumé de reproduction et les
 * alertes sanitaires restent en attente des tickets 3.10/3.12 — un
 * tiroir affichant les informations réelles de la bande, sans tenter de
 * reconstruire en avance des écrans qui ont leur propre ticket dédié.
 *
 * 🔴→✅ EXTENSION DU PATTERN RBAC CRUD AU NIVEAU ACTION (référence
 * initiale : `PlanComptable`) — `$this->authorize('manage-elevage')` sur
 * les 5 actions mutantes (`newLot`, `saveLot`, `editLot`, `updateLot`,
 * `archiveLot`). Écran pertinent aussi pour la bascule papier→numérique
 * (`STRATEGIE_BASCULE_PAPIER_NUMERIQUE.md`) : c'est ici que l'effectif de
 * départ de chaque bande est saisi au jour J, une action qui doit rester
 * réservée aux rôles habilités.
 */
#[Layout('layouts.app')]
class GestionBandes extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $filiere = '';

    /** BS-Q7 : `''` = bandes en cours (par défaut), `archivees` = bandes archivées (restaurables). */
    #[Url]
    public string $affichage = '';

    /** BS-Q4 : la bande éditée a des fiches journalières — son effectif se corrige depuis la fiche. */
    public bool $effectifVerrouille = false;

    /** Ticket UNI : le code de la bande éditée est partagé avec une autre bande — seul cas où il se corrige. */
    public bool $codeEnDoublon = false;

    public ?string $editingLotId = null;

    public ?string $viewingLotId = null;

    // --- Formulaire création/édition ---
    public string $code = '';

    public string $species_id = '';

    /** Valeur STOCKÉE du stade (`reproduction`, `croissance`, `ponte`, `engraissement`) ; libellé selon l'espèce. */
    public string $stage = 'reproduction';

    public string $created_date = '';

    public int $quantity = 0;

    public ?int $acquisition_cost = null;

    /**
     * Produit vendable issu de cette bande (ticket 14.37).
     *
     * ⚠️ FACULTATIF. Une bande sans produit rattaché ne génère aucun mouvement
     * de stock — l'exploitation reste libre de ne pas s'en servir, et les
     * bandes déjà créées ne deviennent pas invalides.
     */
    public string $product_id = '';

    public string $status = 'actif';

    /**
     * Ticket 15.46 — bande d'origine FACULTATIVE : la nouvelle bande est constituée de sujets déjà comptés dans
     * une autre (portée, sevrés). Sa création inscrit leur sortie de la bande d'origine (constitution), sinon ils
     * seraient comptés deux fois dans « Effectif Total Vivant ». Vide pour un achat ou des animaux extérieurs.
     */
    public string $lot_origine_id = '';

    /**
     * Produits candidats pour la bande sélectionnée.
     *
     * ⚠️ Restreints à l'ESPÈCE choisie, et les intrants écartés : on ne produit
     * pas de la provende avec un élevage. Sans espèce sélectionnée, la liste
     * reste vide plutôt que de proposer tout le catalogue.
     */
    public function getProduitsCandidatsProperty()
    {
        if (! $this->species_id) {
            return collect();
        }

        return \App\Models\Product::where('is_active', true)
            ->where('species_id', $this->species_id)
            ->where('sku', 'not like', 'ALI-%')
            ->where('sku', 'not like', 'MED-%')
            ->orderBy('name')
            ->get();
    }

    /**
     * Ticket UNI — nombre de codes de bande partagés par plusieurs bandes (déjà présents avant la règle d'unicité).
     * Alerte NON bloquante : le bandeau invite à les renommer (« Modifier » ouvre le champ code de ces bandes).
     */
    public function getDoublonsDeCodesProperty(): int
    {
        return app(\App\Services\DetectionDoublons::class)->nombreDeCodesDeBandeEnDouble();
    }

    public function getKpisProperty(): array
    {
        $actives = LivestockLot::vivantes();   // Bandes VIVANTES : une bande archivée ne compte plus (LivestockLot::vivantes).

        return [
            'bandes_actives' => (clone $actives)->count(),
            'en_reproduction' => (clone $actives)->where('stage', 'reproduction')->count(),
            'effectif_total' => (int) (clone $actives)->sum('current_quantity'),
            // 🔴→✅ TROUVÉ ENCORE "EN ATTENTE (Sprint 3.12)" ALORS QUE LE
            // MODULE EST RÉEL DEPUIS LONGTEMPS — même gap systémique que
            // le Tableau de Bord (`Schema::hasTable` correct mais valeur
            // jamais branchée). `VeterinaryWithdrawalPeriod` (ticket 3.12)
            // et le calendrier de soins existent réellement — compte les
            // bandes actives sous rémanence en cours aujourd'hui.
            'alertes_sanitaires' => \App\Models\VeterinaryWithdrawalPeriod::where('end_date', '>=', now()->toDateString())
                ->whereHas('lot', fn ($q) => $q->vivantes())
                ->distinct('lot_id')
                ->count('lot_id'),
        ];
    }

    /** Ticket 15.46 — bandes vivantes de l'espèce choisie, candidates comme bande d'origine. */
    public function getBandesOriginePossiblesProperty()
    {
        return $this->species_id === ''
            ? collect()
            : LivestockLot::where('species_id', $this->species_id)->where('is_active', true)->orderBy('code')->get();
    }

    public function getSpeciesOptionsProperty()
    {
        return LivestockSpecies::enabled()->orderBy('label')->get();
    }

    public function getLotsProperty()
    {
        return LivestockLot::with('species')
            ->where('is_active', $this->affichage !== 'archivees')
            ->when($this->search, fn ($q) => $q->where('code', 'like', '%'.$this->search.'%'))
            ->when($this->filiere, fn ($q) => $q->whereHas('species', fn ($q2) => $q2->where('code', $this->filiere)))
            ->orderByDesc('created_date')
            ->orderBy('code')   // ordre stable à date égale (le poste départage de la même façon)
            ->get();
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR BALAYAGE STRUCTUREL SYSTÉMATIQUE : bouton
     * "Exporter PDF" absent — même schéma déjà trouvé sur de nombreux
     * écrans de ce projet.
     */
    public function exportBandesPdf()
    {
        $this->authorize('view-elevage');

        $lots = $this->lots;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.gestion-bandes',
            ['lots' => $lots],
            'Gestion des Bandes',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'bandes-'.now()->format('Y-m-d').'.pdf');
    }

    public function getViewingLotProperty(): ?LivestockLot
    {
        return $this->viewingLotId ? LivestockLot::with('species')->find($this->viewingLotId) : null;
    }

    /**
     * 🔴→✅ TIROIR « AUTONOMIE ALIMENTAIRE » — était un « sera alimenté… Sprint 6 » alors que le stock de provende
     * et la provende servie existent. Autonomie de la FILIÈRE de la bande (le stock de provende est commun à la
     * filière), même calcul que les fiches (AutonomieAlimentaireService), plus la provende servie à CETTE bande
     * sur sa dernière fiche.
     */
    public function getAutonomieBandeProperty(): ?array
    {
        $lot = $this->viewingLot;
        if (! $lot || ! $lot->species) {
            return null;
        }

        $derniere = \App\Models\LivestockDailyEntry::where('lot_id', $lot->id)->orderByDesc('entry_date')->first();

        return [
            'filiere' => app(\App\Services\AutonomieAlimentaireService::class)->pourEspece($lot->species->code),
            'provende_bande_kg' => $derniere?->feed_qty_kg === null ? null : round((float) $derniere->feed_qty_kg, 2),
            'date_fiche' => $derniere?->entry_date,
        ];
    }

    /**
     * 🔴→✅ TIROIR « SUIVI SANITAIRE » — était un « sera alimenté… ticket 3.12 » alors que rémanences, infirmerie et
     * registre vétérinaire existent. Données réelles de la bande : délai d'attente en cours (vente interdite),
     * sujets en infirmerie, mortalité des 7 derniers jours, derniers soins ACTIFS du registre.
     */
    public function getSuiviSanitaireBandeProperty(): ?array
    {
        $lot = $this->viewingLot;
        if (! $lot) {
            return null;
        }

        $fiches7j = \App\Models\LivestockDailyEntry::where('lot_id', $lot->id)
            ->whereDate('entry_date', '>=', now()->subDays(6)->toDateString())->get();
        $depart7j = $fiches7j->sortBy('entry_date')->first()?->previousEffectif();

        return [
            'remanence' => \App\Models\VeterinaryWithdrawalPeriod::where('lot_id', $lot->id)
                ->whereDate('end_date', '>=', now()->toDateString())->orderByDesc('end_date')->first(),
            'infirmerie' => \App\Models\InfirmaryRecord::where('lot_id', $lot->id)->where('status', 'en_cours')->count(),
            'morts_7j' => (int) $fiches7j->sum('mort'),
            'mortalite_7j' => $depart7j ? round($fiches7j->sum('mort') / $depart7j * 100, 1) : null,
            'derniers_soins' => \App\Models\VeterinaryRecord::where('lot_id', $lot->id)->where('is_active', true)
                ->orderByDesc('record_date')->orderByDesc('created_at')->limit(3)->get(),
        ];
    }

    public function view(string $id): void
    {
        $this->viewingLotId = $id;
    }

    public function closeDrawer(): void
    {
        $this->viewingLotId = null;
    }

    /**
     * Stades proposés pour l'espèce choisie : Reproducteur / Jeune / Sous-mères pour les lapins
     * (décision client du 17/10/2026), les quatre stades génériques sinon.
     *
     * @return array<string, string>
     */
    public function getStadesProperty(): array
    {
        return LivestockLot::stadesPourEspece(LivestockSpecies::find($this->species_id)?->code);
    }

    public function updatedSpeciesId(): void
    {
        $species = LivestockSpecies::find($this->species_id);

        if ($species) {
            $this->code = LivestockLot::suggestNextCode($species->code);
        }

        // Un stade qui n'existe pas pour la nouvelle espèce (la ponte pour les lapins) n'est jamais gardé.
        if (! array_key_exists($this->stage, $this->stades)) {
            $this->stage = array_key_first($this->stades);
        }
    }

    public function newLot(): void
    {
        $this->authorize('manage-elevage');

        $this->reset(['editingLotId', 'code', 'species_id', 'acquisition_cost', 'lot_origine_id']);
        $this->stage = 'reproduction';
        $this->created_date = now()->format('Y-m-d');
        $this->quantity = 0;
        $this->dispatch('open-modal', name: 'modal-create-bande');
    }

    public function saveLot(): void
    {
        $this->authorize('manage-elevage');

        // Ticket UNI : le code est rangé sans espaces autour, et unique parmi TOUTES les bandes (en cours ou
        // archivées), casse et espaces ignorés — le message dit quel code est déjà pris.
        $this->code = trim($this->code);

        $this->validate([
            'code' => ['required', 'string', 'max:50', UniqueNormalise::bande()],
            'species_id' => ['required', 'exists:livestock_species,id'],
            'stage' => ['required', 'in:'.implode(',', array_keys($this->stades))],
            'created_date' => ['required', 'date'],
            'quantity' => ['required', 'integer', 'min:1'],
            'product_id' => ['nullable', 'exists:products,id'],
            'lot_origine_id' => ['nullable', 'exists:livestock_lots,id'],
        ]);

        try {
            DB::transaction(fn () => $this->creerLaBande());
        } catch (ValidationException $e) {
            // La date dans un exercice clos (BS1) se lit sous « Date de Création » ; la constitution refusée (bande
            // d'origine insuffisante…) sous « Bande d'Origine » : dans les deux cas la bande n'est pas créée.
            $erreurs = $e->errors();
            if (isset($erreurs['created_date'])) {
                $this->addError('created_date', $erreurs['created_date'][0]);
            } else {
                $this->addError('lot_origine_id', collect($erreurs)->flatten()->first());
            }

            return;
        }

        $this->dispatch('close-modal', name: 'modal-create-bande');
        $this->dispatch('toast', message: 'Bande créée avec succès.', type: 'success');
        $this->reset(['code', 'species_id', 'quantity', 'acquisition_cost', 'product_id', 'lot_origine_id']);
    }

    private function creerLaBande(): void
    {
        // Ticket BS1 — le point de passage unique de la bande (le poste envoie la sienne par le même).
        $lot = app(SaisieBandeAction::class)->creer([
            'code' => $this->code,
            'species_id' => $this->species_id,
            'product_id' => $this->product_id,
            'stage' => $this->stage,
            'quantity' => $this->quantity,
            'created_date' => $this->created_date,
            'acquisition_cost' => $this->acquisition_cost,
        ]);

        if ($this->lot_origine_id !== '') {
            app(TransferBetweenLotsAction::class)->execute([
                'source_lot_id' => $this->lot_origine_id,
                'target_lot_id' => $lot->id,
                'transfer_date' => $lot->created_date->format('Y-m-d'),
                'quantity' => $lot->initial_quantity,
                'categorie' => EffectifParCategorieService::especeDuLot($lot->load('species')) !== null
                    ? EffectifParCategorieService::categorieDuStade($lot->stage)
                    : null,
                'constitution' => true,
                'motif' => 'Constitution de la bande '.$lot->code,
            ], Auth::user());
        }
    }

    public function editLot(string $id): void
    {
        $this->authorize('manage-elevage');

        $lot = LivestockLot::findOrFail($id);
        $this->editingLotId = $lot->id;
        $this->code = $lot->code;
        $this->species_id = $lot->species_id;
        $this->stage = $lot->stage;
        $this->quantity = $lot->current_quantity;
        $this->status = $lot->status;
        $this->effectifVerrouille = SaisieBandeAction::aDesFiches($lot->id);
        $this->codeEnDoublon = $lot->codeEstEnDoublon();
        $this->dispatch('open-modal', name: 'modal-edit-bande');
    }

    public function updateLot(): void
    {
        $this->authorize('manage-elevage');

        $this->code = trim($this->code);

        $this->validate([
            'stage' => ['required', 'in:'.implode(',', array_keys($this->stades))],
            'quantity' => ['required', 'integer', 'min:0'],
            'status' => ['required', 'in:actif,cloture'],
        ] + ($this->codeEnDoublon ? ['code' => ['required', 'string', 'max:50', UniqueNormalise::bande($this->editingLotId)]] : []));

        try {
            app(SaisieBandeAction::class)->modifier($this->editingLotId, [
                'stage' => $this->stage,
                'current_quantity' => $this->quantity,
                'status' => $this->status,
            ] + ($this->codeEnDoublon ? ['code' => $this->code] : []));
        } catch (ValidationException $e) {
            // Bande archivée depuis l'ouverture de la modale (autre onglet, autre poste).
            $this->dispatch('close-modal', name: 'modal-edit-bande');
            $this->dispatch('toast', message: collect($e->errors())->flatten()->first(), type: 'error');

            return;
        }

        $this->dispatch('close-modal', name: 'modal-edit-bande');
        $this->dispatch('toast', message: 'Bande modifiée avec succès.', type: 'success');
    }

    public function archiveLot(string $id): void
    {
        $this->authorize('manage-elevage');

        try {
            app(SaisieBandeAction::class)->archiver($id);
        } catch (ValidationException $e) {
            // BS-Q3 : une bande qui a des sujets vivants ne s'archive pas.
            $this->dispatch('toast', message: collect($e->errors())->flatten()->first(), type: 'error');

            return;
        }

        $this->dispatch('toast', message: 'Bande archivée avec succès.', type: 'warning');
    }

    /** BS-Q7 — restaure une bande archivée (même droit que l'archivage). */
    public function restoreLot(string $id): void
    {
        $this->authorize('manage-elevage');

        try {
            $resultat = app(SaisieBandeAction::class)->restaurer($id);
        } catch (ValidationException $e) {
            $this->dispatch('toast', message: collect($e->errors())->flatten()->first(), type: 'error');

            return;
        }

        if ($resultat === SaisieBandeAction::RESTAUREE_MAINTENANT) {
            $this->dispatch('toast', message: 'Bande restaurée avec succès.', type: 'success');
        }
    }

    public function render()
    {
        return view('livewire.elevage.gestion-bandes', ['title' => 'Élevage > Bandes & Sujets']);
    }
}
