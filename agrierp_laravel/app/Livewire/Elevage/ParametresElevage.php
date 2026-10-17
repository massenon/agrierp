<?php

namespace App\Livewire\Elevage;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\ElevageNumberingSetting;
use App\Models\FeedRationStandard;
use App\Models\FeedType;
use App\Models\LivestockSpecies;
use App\Models\ProphylaxisScheduleStandard;
use App\Services\AlertesElevageService;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 2.8 (Sprint 2) — parametres-elevage.html → Livewire\Elevage\ParametresElevage
 * DERNIER TICKET DU SPRINT 2.
 *
 * ⚠️ TROIS TABLES DE PARAMÈTRES/BARÈME AJOUTÉES, ABSENTES DES 26
 * MIGRATIONS DOCUMENTÉES (constat signalé avant codage, Document 00 §2.2) :
 * `feed_types`, `prophylaxis_schedule_standards`, `elevage_numbering_settings`
 * — voir le docblock de chaque migration pour la justification complète.
 * Toutes trois suivent le même principe que `feed_ration_standards`
 * (ticket 2.7) : un barème/une configuration, pas une donnée
 * transactionnelle liée à un lot réel (Sprint 3).
 *
 * ⚠️ EXCEPTION DOCUMENTÉE À LA RÈGLE "TOUJOURS ARCHIVAGE" : ces 3 tables +
 * `feed_ration_standards` acceptent une suppression PHYSIQUE réelle
 * (`<x-modal-confirm-permanent-delete>`), conforme à la modale du
 * prototype ("irréversible... Oui, Supprimer définitivement") — ce sont
 * des valeurs de configuration sans historique métier à préserver, à la
 * différence des entités métier (produits, clients...) qui restent
 * toujours archivées (Document 01 FR-01).
 *
 * ⚠️ BUG CORRIGÉ AU TICKET 2.7 PUIS RE-CORRIGÉ ICI : la lecture de
 * `parametres-elevage.html` (`RATIONS_STORE`) confirme que les valeurs
 * ORIGINALES de `SEEDER_TEST.md` (Lapin Sevré 30g, Pondeuse 110g, 4 stades
 * aviculture) sont correctes — ma "correction" du ticket 2.7, basée sur
 * `Fiche_de_rationneent_des_aniamaux.md`, était erronée. Voir docblock de
 * `FeedRationStandardsSeeder` pour le détail complet de cette correction
 * d'une correction.
 */
#[Layout('layouts.app')]
class ParametresElevage extends Component
{
    #[Url]
    public string $tab = 'rationnement';

    // --- Onglet Prophylaxie : sous-filtre espèce ---
    public string $prophySpecies = 'cuniculture';

    // --- Formulaire Ration ---
    public ?string $editingRationId = null;

    public string $ration_species_code = 'aviculture';

    public string $ration_stage_label = '';

    public ?int $ration_grammes = null;

    // --- Formulaire Prophylaxie ---
    public ?string $editingProphyId = null;

    public string $prophy_period_label = '';

    public string $prophy_treatment = '';

    public string $prophy_product = '';

    public string $prophy_dosage = '';

    public int $prophy_withdrawal_days = 0;

    // --- Formulaire Provende ---
    public ?string $editingProvendeId = null;

    public string $provende_name = '';

    public string $provende_species_id = '';

    public float $provende_bag_kg = 25;

    public float $provende_price_kg = 250;

    // --- Numérotation ---
    public array $numbering = [];

    /** Règle R-SOINS-01 — délai du rappel des soins planifiés (jours). */
    public int $rappelSoinsJours = AlertesElevageService::JOURS_RAPPEL_SOINS;

    public function mount(): void
    {
        $this->numbering = ElevageNumberingSetting::current()->only([
            'bande_format', 'lapine_prefix', 'male_prefix', 'truie_prefix',
            'verrat_prefix', 'portee_prefix', 'volaille_prefix', 'parc_prefix', 'escargot_prefix',
        ]);
        $this->rappelSoinsJours = app(AlertesElevageService::class)->joursRappelSoins();
    }

    /** Règle R-SOINS-01 — l'exploitant règle le délai du rappel des soins planifiés. */
    public function saveRappelSoins(): void
    {
        $this->authorize('manage-elevage');

        $this->validate(['rappelSoinsJours' => ['required', 'integer', 'min:0', 'max:30']], [], [
            'rappelSoinsJours' => 'délai de rappel',
        ]);

        CompanySetting::current()->update(['rappel_soins_jours' => $this->rappelSoinsJours]);

        AuditLog::record('rappel_soins.updated', 'elevage');
        $this->dispatch('toast', message: 'Délai de rappel des soins enregistré.', type: 'success');
    }

    // ===================== RATIONNEMENT =====================
    public function getRationsProperty()
    {
        // Ticket 14.55 — les archives ne s'affichent plus ici : elles vivent
        // dans Paramètres > Restauration.
        return FeedRationStandard::where('is_active', true)
            ->orderBy('species_code')->orderBy('ration_g_per_day')->get();
    }

    public function editRation(string $id): void
    {
        $r = FeedRationStandard::findOrFail($id);
        $this->editingRationId = $r->id;
        $this->ration_species_code = $r->species_code;
        $this->ration_stage_label = $r->stage_label;
        $this->ration_grammes = $r->ration_g_per_day;
        $this->dispatch('open-modal', name: 'modal-ration');
    }

    public function newRation(): void
    {
        $this->reset(['editingRationId', 'ration_stage_label', 'ration_grammes']);
        $this->ration_species_code = 'aviculture';
        $this->dispatch('open-modal', name: 'modal-ration');
    }

    public function saveRation(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'ration_species_code' => ['required', 'in:aviculture,cuniculture,porciculture'],
            'ration_stage_label' => ['required', 'string', 'max:100'],
            'ration_grammes' => ['required', 'integer', 'min:1'],
        ]);

        FeedRationStandard::updateOrCreate(
            ['id' => $this->editingRationId],
            [
                'species_code' => $this->ration_species_code,
                'stage_label' => $this->ration_stage_label,
                'ration_g_per_day' => $this->ration_grammes,
            ]
        );

        AuditLog::record('feed_ration_standard.saved', 'elevage');
        $this->dispatch('close-modal', name: 'modal-ration');
        $this->dispatch('toast', message: 'Ration enregistrée avec succès.', type: 'success');
        $this->reset(['editingRationId', 'ration_stage_label', 'ration_grammes']);
    }

    public function deleteRation(string $id): void
    {
        $this->authorize('manage-elevage');

        // 🔴→✅ TICKET 14.55 — ARCHIVAGE, PLUS SUPPRESSION. Une ration
        // effacée disparaissait aussi du poste Desktop au tirage suivant (le
        // référentiel y est REMPLACÉ), et la provende cessait d'être calculée
        // pour cette catégorie sans que rien ne l'explique. Restaurable depuis
        // Paramètres > Restauration.
        FeedRationStandard::findOrFail($id)->update(['is_active' => false]);
        AuditLog::record('feed_ration_standard.archived', 'elevage');
        $this->dispatch('toast', message: 'Paramètre archivé — restaurable depuis Paramètres > Restauration.', type: 'warning');
    }

    // ===================== PROPHYLAXIE =====================
    public function getProphylaxiesProperty()
    {
        return ProphylaxisScheduleStandard::where('is_active', true)
            ->where('species_code', $this->prophySpecies)
            ->orderBy('created_at')
            ->get();
    }

    public function editProphy(string $id): void
    {
        $p = ProphylaxisScheduleStandard::findOrFail($id);
        $this->editingProphyId = $p->id;
        $this->prophy_period_label = $p->period_label;
        $this->prophy_treatment = $p->treatment;
        $this->prophy_product = $p->product_recommended;
        $this->prophy_dosage = $p->dosage;
        $this->prophy_withdrawal_days = $p->withdrawal_days;
        $this->dispatch('open-modal', name: 'modal-prophylaxie');
    }

    public function newProphy(): void
    {
        $this->reset(['editingProphyId', 'prophy_period_label', 'prophy_treatment', 'prophy_product', 'prophy_dosage', 'prophy_withdrawal_days']);
        $this->dispatch('open-modal', name: 'modal-prophylaxie');
    }

    public function saveProphy(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'prophy_period_label' => ['required', 'string', 'max:100'],
            'prophy_treatment' => ['required', 'string', 'max:150'],
            'prophy_product' => ['required', 'string', 'max:150'],
            'prophy_dosage' => ['required', 'string', 'max:150'],
            'prophy_withdrawal_days' => ['required', 'integer', 'min:0'],
        ]);

        ProphylaxisScheduleStandard::updateOrCreate(
            ['id' => $this->editingProphyId],
            [
                'species_code' => $this->prophySpecies,
                'period_label' => $this->prophy_period_label,
                'treatment' => $this->prophy_treatment,
                'product_recommended' => $this->prophy_product,
                'dosage' => $this->prophy_dosage,
                'withdrawal_days' => $this->prophy_withdrawal_days,
            ]
        );

        AuditLog::record('prophylaxis_schedule.saved', 'elevage');
        $this->dispatch('close-modal', name: 'modal-prophylaxie');
        $this->dispatch('toast', message: 'Échéance enregistrée avec succès.', type: 'success');
        $this->reset(['editingProphyId', 'prophy_period_label', 'prophy_treatment', 'prophy_product', 'prophy_dosage', 'prophy_withdrawal_days']);
    }

    public function deleteProphy(string $id): void
    {
        $this->authorize('manage-elevage');

        // 🔴→✅ TICKET 14.55 — un protocole sanitaire effacé ne se
        // retrouve pas : archivé, il reste restaurable.
        ProphylaxisScheduleStandard::findOrFail($id)->update(['is_active' => false]);
        AuditLog::record('prophylaxis_schedule.archived', 'elevage');
        $this->dispatch('toast', message: 'Paramètre archivé — restaurable depuis Paramètres > Restauration.', type: 'warning');
    }

    // ===================== PROVENDE =====================
    public function getProvendesProperty()
    {
        return FeedType::with('species')->where('is_active', true)->orderBy('name')->get();
    }

    public function getSpeciesOptionsProperty()
    {
        return LivestockSpecies::enabled()->orderBy('label')->get();
    }

    public function editProvende(string $id): void
    {
        $p = FeedType::findOrFail($id);
        $this->editingProvendeId = $p->id;
        $this->provende_name = $p->name;
        $this->provende_species_id = (string) $p->species_id;
        $this->provende_bag_kg = (float) $p->standard_bag_weight_kg;
        $this->provende_price_kg = (float) $p->price_per_kg;
        $this->dispatch('open-modal', name: 'modal-provende');
    }

    public function newProvende(): void
    {
        $this->reset(['editingProvendeId', 'provende_name', 'provende_species_id']);
        $this->provende_bag_kg = 25;
        $this->provende_price_kg = 250;
        $this->dispatch('open-modal', name: 'modal-provende');
    }

    public function saveProvende(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'provende_name' => ['required', 'string', 'max:150'],
            'provende_species_id' => ['required', 'exists:livestock_species,id'],
            'provende_bag_kg' => ['required', 'numeric', 'min:0.01'],
            'provende_price_kg' => ['required', 'numeric', 'min:0'],
        ]);

        FeedType::updateOrCreate(
            ['id' => $this->editingProvendeId],
            [
                'name' => $this->provende_name,
                'species_id' => $this->provende_species_id,
                'standard_bag_weight_kg' => $this->provende_bag_kg,
                'price_per_kg' => $this->provende_price_kg,
                'is_active' => true,
            ]
        );

        AuditLog::record('feed_type.saved', 'elevage');
        $this->dispatch('close-modal', name: 'modal-provende');
        $this->dispatch('toast', message: 'Type de provende enregistré avec succès.', type: 'success');
        $this->reset(['editingProvendeId', 'provende_name', 'provende_species_id']);
    }

    public function deleteProvende(string $id): void
    {
        $this->authorize('manage-elevage');

        // 🔴→✅ TICKET 14.55 — archivage logique, comme partout ailleurs.
        FeedType::findOrFail($id)->update(['is_active' => false]);
        AuditLog::record('feed_type.archived', 'elevage');
        $this->dispatch('toast', message: 'Paramètre archivé — restaurable depuis Paramètres > Restauration.', type: 'warning');
    }

    // ===================== NUMÉROTATION =====================
    public function saveNumbering(): void
    {
        $this->authorize('manage-elevage');

        $this->validate([
            'numbering.bande_format' => ['required', 'string', 'max:50'],
            'numbering.lapine_prefix' => ['required', 'string', 'max:10'],
            'numbering.male_prefix' => ['required', 'string', 'max:10'],
            'numbering.truie_prefix' => ['required', 'string', 'max:10'],
            'numbering.verrat_prefix' => ['required', 'string', 'max:10'],
            'numbering.portee_prefix' => ['required', 'string', 'max:10'],
            'numbering.volaille_prefix' => ['required', 'string', 'max:20'],
            'numbering.parc_prefix' => ['required', 'string', 'max:20'],
            'numbering.escargot_prefix' => ['required', 'string', 'max:20'],
        ]);

        ElevageNumberingSetting::current()->update($this->numbering);

        AuditLog::record('elevage_numbering.updated', 'elevage');
        $this->dispatch('toast', message: 'Formats de numérotation enregistrés avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.elevage.parametres-elevage', ['title' => 'Paramètres Élevage']);
    }
}
