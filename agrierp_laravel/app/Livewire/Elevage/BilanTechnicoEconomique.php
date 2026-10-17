<?php

namespace App\Livewire\Elevage;

use App\Models\FeedType;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\VeterinaryRecord;
use App\Services\LotRevenueService;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 3.14 (Sprint 3) — bilan-technico-economique.html →
 * Livewire\Elevage\BilanTechnicoEconomique. DERNIER TICKET DU SPRINT 3.
 *
 * "Ce bilan agrège automatiquement : le coût d'acquisition initial de la
 * bande, les provendes servies (valorisées au prix d'achat), les frais
 * vétérinaires imputés au lot, et les ventes / transformations
 * enregistrées via le module POS ou Transformation." (copie du prototype)
 *
 * ⚠️ PÉRIMÈTRE ANNONCÉ AVANT CODAGE — 3 lignes de coût sur 4 réelles :
 *   - Acquisition initiale : réelle (voir bug corrigé ci-dessous).
 *   - Provende servie (cumul) : réelle, mais valorisée au prix INDICATIF
 *     du catalogue Types de Provende (`feed_types.price_per_kg`, ticket
 *     2.8) — "au prix d'achat" réel nécessiterait les achats (Sprint 5),
 *     pas encore disponibles. Écart documenté, pas une approximation
 *     cachée.
 *   - Frais vétérinaires : réels (`veterinary_records.cost`, ticket 3.11).
 *   - Main d'œuvre imputée : voir ci-dessous, ticket 14.44.
 * Revenus (ventes sujets vivants, transformés, sous-produits) : EN
 * ATTENTE dans leur totalité — nécessitent le POS (Sprint 4). Marge Nette
 * non calculable sans revenus réels ; Coût de Revient/Sujet reste
 * calculable sur les seuls coûts déjà réels.
 *
 * ⚠️ ÉCART DE LIBELLÉ ASSUMÉ (relevé au ticket 14.49) : la première carte
 * s'intitule « Coût Total CONNU du Lot » là où le prototype écrit « Coût
 * Total du Lot ». Le qualificatif n'est pas cosmétique — la main d'œuvre
 * reste hors du calcul (voir ci-dessous) et un « Coût Total » sans réserve
 * serait un chiffre faux présenté comme complet. À retirer le jour où la clé
 * d'imputation sera arbitrée, pas avant.
 *
 * ⚠️ Les quatre cartes sont codées à la main plutôt qu'avec `<x-kpi-card>`,
 * contrairement au reste du projet — divergence de forme sans effet visuel,
 * à uniformiser lors d'un passage ultérieur sur cet écran.
 *
 * ═══════════════════════════════════════════════════════════════════════
 * TICKET 14.44 (Sprint 14) — REVENUS RÉELS, ET UN MOTIF D'ATTENTE CORRIGÉ
 * ═══════════════════════════════════════════════════════════════════════
 *
 * 🔴→✅ REVENUS PAR BANDE : LIVRÉS. Le POS existe depuis le Sprint 4, mais
 * la ligne de vente ne conservait PAS la bande vendue — l'information était
 * pourtant connue du panier (`confirmWeightAdd()` l'exige pour le contrôle
 * de rémanence vétérinaire) et servait déjà à décrémenter l'effectif du
 * jour. Elle est désormais persistée (`sale_lines.lot_id`, migration
 * dédiée), ce qui rend le revenu par bande EXACT — jamais reconstruit par
 * une heuristique FIFO ou une répartition au prorata.
 *
 * ⚠️ REVENU NET DES AVOIRS TRAITÉS et des ventes annulées exclues : un
 * retour marchandise sur une bande n'est pas un revenu de cette bande.
 *
 * ✅ LES VENTES TRANSFORMÉES SONT COUVERTES, ET C'ÉTAIT À VÉRIFIER. Une
 * première rédaction de ce ticket les déclarait « non rattachables, stock
 * fongible ». C'était faux POUR CETTE APPLICATION : le POS exige la bande
 * source pour TOUT produit lié à une espèce, transformés compris — le
 * caissier la désigne à la caisse. Le lien n'est donc pas reconstruit après
 * coup, il est saisi. Vérifié sur la simulation : « Poulet fumé » et
 * « Poulet braisé » remontent bien au bilan de leur bande.
 *
 * ⚠️ LA CONTREPARTIE DE CETTE RÈGLE, À ARBITRER. Le POS réclame une bande
 * pour tout produit portant `species_id` — ce qui inclut les PROVENDES du
 * catalogue (`ALI-001` porte l'espèce Aviculture). Vendre un sac d'aliment
 * à un voisin obligerait donc le caissier à l'imputer à une bande, et ce
 * revenu viendrait gonfler le bilan de cette bande alors qu'il ne provient
 * pas d'elle. Le cas ne se produit pas dans la simulation (aucune provende
 * n'est revendue), mais la règle le permet. Distinguer « produit ISSU d'une
 * bande » de « intrant VENDU » exigerait un champ qui n'existe pas :
 * modifier ici le déclenchement du contrôle de rémanence toucherait une
 * règle de sécurité sanitaire validée. SIGNALÉ, NON RÉSOLU.
 *
 * 🔴 MAIN D'ŒUVRE IMPUTÉE : TOUJOURS EN ATTENTE, MAIS PLUS POUR LA MÊME
 * RAISON. Le motif inscrit ici était « paie/RH, Sprint 8 » : la paie existe
 * depuis, avec bulletins, charges patronales et écritures comptables. Le
 * blocage réel est ailleurs et n'est pas technique : AUCUNE CLÉ
 * D'IMPUTATION n'existe. `employees` ne porte ni bande ni centre de coût,
 * et ni le CDC ni le prototype ne définissent comment répartir le salaire
 * d'un animalier entre les bandes dont il s'occupe (au temps passé ? à
 * l'effectif ? au poids vif ?). Chacune de ces clés donne un coût de
 * revient différent. ARBITRAGE CLIENT REQUIS — inventer la règle serait
 * livrer un chiffre faux avec l'apparence de la précision.
 *
 * ⚠️ BUG RÉEL CORRIGÉ EN PRÉALABLE : `livestock_lots.acquisition_cost`
 * existait dans le formulaire de création de bande (ticket 3.3) mais
 * n'était ni en base ni sauvegardé — corrigé par une migration dédiée et
 * la correction de `GestionBandes::saveLot()`, sans quoi CE ticket
 * n'aurait eu aucune vraie donnée d'acquisition à afficher.
 */
#[Layout('layouts.app')]
class BilanTechnicoEconomique extends Component
{
    #[Url]
    public string $lotId = '';

    public function mount(): void
    {
        $this->lotId = $this->lotId ?: ($this->lots->first()?->id ?? '');
    }

    public function getLotsProperty()
    {
        return LivestockLot::with('species')->where('is_active', true)->orderByDesc('created_date')->get();
    }

    public function getSelectedLotProperty(): ?LivestockLot
    {
        return $this->lotId ? LivestockLot::with('species')->find($this->lotId) : null;
    }

    public function getCoutsProperty(): array
    {
        $lot = $this->selectedLot;

        if (! $lot) {
            return [];
        }

        $provendeServieKg = (float) LivestockDailyEntry::where('lot_id', $lot->id)->sum('feed_qty_kg');
        $prixMoyenKg = (float) (FeedType::where('species_id', $lot->species_id)->avg('price_per_kg') ?? 0);
        $coutProvende = round($provendeServieKg * $prixMoyenKg);

        $coutVeterinaire = (float) VeterinaryRecord::where('lot_id', $lot->id)->where('is_active', true)->sum('cost');   // soin archivé = supprimé

        return [
            ['label' => 'Acquisition initiale', 'montant' => $lot->acquisition_cost, 'reel' => $lot->acquisition_cost !== null],
            ['label' => 'Provende servie (cumul, prix indicatif)', 'montant' => $coutProvende, 'reel' => true],
            ['label' => 'Frais vétérinaires', 'montant' => $coutVeterinaire, 'reel' => true],
            [
                'label' => "Main d'œuvre imputée",
                'montant' => null,
                'reel' => false,
                // Le motif a changé de nature au ticket 14.44 : ce n'est plus
                // la paie qui manque, c'est la clé de répartition.
                'motif' => "Aucune clé d'imputation définie — un employé n'est rattaché ni à une bande ni à un centre de coût. Arbitrage client requis.",
            ],
        ];
    }

    /**
     * Revenus RÉELS de la bande, une ligne par produit effectivement vendu.
     *
     * ⚠️ Ventes annulées exclues et avoirs traités déduits : un retour
     * marchandise n'est pas un revenu.
     */
    public function getRevenusProperty(): array
    {
        $lot = $this->selectedLot;

        if (! $lot) {
            return [];
        }

        // ⚠️ TICKET 15.12 — LE CALCUL VIT DANS `LotRevenueService`, partagé avec
        // le tirage du poste : une seule règle, un seul chiffre.
        return array_map(
            fn (array $r) => ['label' => $r['label'], 'montant' => $r['montant'], 'reel' => $r['reel']],
            app(LotRevenueService::class)->forLot($lot->id),
        );
    }

    public function getRevenuTotalConnuProperty(): float
    {
        return round(collect($this->revenus)->sum(fn ($r) => $r['montant'] ?? 0), 2);
    }

    /**
     * Marge Nette sur revenus ET coûts CONNUS. Le qualificatif n'est pas une
     * précaution de style : la main d'œuvre manque toujours au dénominateur
     * des coûts, et le transformé peut manquer aux revenus.
     */
    public function getMargeNetteProperty(): float
    {
        return round($this->revenuTotalConnu - $this->coutTotalConnu, 2);
    }

    public function getCoutTotalConnuProperty(): float
    {
        return collect($this->couts)->sum(fn ($c) => $c['montant'] ?? 0);
    }

    public function getCoutParSujetProperty(): ?float
    {
        $lot = $this->selectedLot;

        if (! $lot || $lot->initial_quantity <= 0) {
            return null;
        }

        return round($this->coutTotalConnu / $lot->initial_quantity);
    }

    public function render()
    {
        return view('livewire.elevage.bilan-technico-economique', ['title' => 'Élevage > Rentabilité']);
    }
}
