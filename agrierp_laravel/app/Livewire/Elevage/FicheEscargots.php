<?php

namespace App\Livewire\Elevage;

use App\Livewire\Elevage\Concerns\AvecTransfertsDuJour;
use App\Actions\RecordSaleOnFicheElevageAction;
use App\Actions\SyncLotProductionStockAction;
use App\Livewire\Elevage\Concerns\AvecSoinsDuMois;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\ModuleConfig;
use App\Support\OrdreDesVerrous;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 3.9 (Sprint 3) — fiche-escargots.html → Livewire\Elevage\FicheEscargots
 * Implémentation réelle complète, visibilité conditionnée à
 * `modules_config.helico` — DERNIÈRE FICHE ESPÈCE DU SPRINT 3.
 *
 * Vérification SERVEUR (Document 00 §2.4 : le masquage de menu n'est
 * qu'un confort d'affichage, la vraie autorisation est vérifiée à chaque
 * action) dans `mount()` — un accès direct à l'URL alors que le module est
 * désactivé est bloqué ici, pas seulement caché dans le hub (ticket 3.2).
 *
 * Workflow Ponte en Terre & Éclosion des Naissains — même mécanique que
 * `FicheReproducteurs` (ticket 3.7) : `ponte_total` = œufs pondus en terre,
 * `ne` = naissains nés. Taux d'Éclosion applicable ici (Aviculture
 * Reproducteurs ET Héliciculture uniquement, FORMULE_FICHE_ELEVAGE.md §3).
 *
 * Ventilation effectif (4 sous-colonnes du tableau mensuel réel :
 * Naissains/Engraiss./Bordés/Total, PAS M/F/Sevrés/S-Mères comme Lapins —
 * confirmé par lecture directe, lignes 460-463) réutilise
 * `effectif_m`→Naissains, `effectif_f`→Engraissement, `effectif_sevres`→
 * Bordés (reproducteurs), `effectif_smeres` non utilisé pour cette espèce
 * (pas de 4e catégorie dans le prototype réel).
 *
 * ⚠️ RATIONNEMENT NON IMPLÉMENTÉ, SIGNALÉ EXPLICITEMENT : le prototype
 * demande un "Rationnement Farine Calcique & Fourrage" propre aux
 * escargots, mais aucun barème n'a été fourni pour cette filière
 * (`feed_ration_standards`, ticket 2.7, ne couvre que cuniculture/
 * aviculture/porciculture — Héliciculture explicitement désactivée par
 * défaut, Document 00 §5.1). Plutôt que d'inventer un grammage non
 * documenté, cette section reste en bandeau d'attente.
 */
#[Layout('layouts.app')]
class FicheEscargots extends Component
{
    use \App\Livewire\Elevage\Concerns\AvecMoisDeFiche;   // Ticket EX8 (EF12) : mois passés, lecture seule
    use AvecTransfertsDuJour;
    use AvecSoinsDuMois;

    public string $selectedDate;

    public int $achat = 0;

    public int $naissainsNes = 0;

    public int $oeufsTerre = 0;

    public int $mortBorde = 0;

    public int $mortEngraissement = 0;

    public int $mortNaissain = 0;

    public int $donBorde = 0;

    public int $donEngraissement = 0;

    public int $donNaissain = 0;

    /**
     * Ticket 15.56 — dons déjà enregistrés pour le jour rechargé (même règle que `mortEnregistre`) : la répartition
     * n'est pas stockée, seul le total l'est ; il est gardé tant qu'aucune répartition n'est ressaisie.
     */
    public ?int $donEnregistre = null;

    public int $effectifNaissains = 0;

    public int $effectifEngraissement = 0;

    public int $effectifBordes = 0;

    public ?int $peseeTotal = null;

    public string $observations = '';

    public bool $moduleEnabled = false;

    /**
     * Ticket 15.47 (A11) — LA bande de la fiche, comme Lapins et Porcs (15.41). Avant : `saveDay()` écrivait
     * toujours sur la PREMIÈRE bande et le tableau mensuel mêlait toutes les bandes.
     */
    public ?string $bandeId = null;

    /**
     * Ticket 15.47 — morts déjà enregistrés pour le jour rechargé : la répartition Bordés / Engraissement /
     * Naissains n'est pas stockée ; sans ce total, ré-enregistrer le jour remettait ses morts à zéro.
     */
    public ?int $mortEnregistre = null;

    public function mount(): void
    {
        $this->moduleEnabled = ModuleConfig::isEnabled('helico');
        $this->selectedDate = now()->format('Y-m-d');
        $this->loadDay($this->selectedDate);
    }

    public function updatedSelectedDate(): void
    {
        $this->loadDay($this->selectedDate);
    }

    public function updatedBandeId(): void
    {
        $this->loadDay($this->selectedDate);
    }

    public function getBandeProperty(): ?LivestockLot
    {
        $lots = $this->lots;

        return ($this->bandeId !== null ? $lots->firstWhere('id', $this->bandeId) : null) ?? $lots->first();
    }

    protected function bandeDeLaFiche()
    {
        return $this->bande;
    }

    /** Morts du jour : la répartition saisie, sinon le total déjà enregistré. */
    private function mortDuJour(): int
    {
        $saisis = $this->mortBorde + $this->mortEngraissement + $this->mortNaissain;

        return $saisis > 0 ? $saisis : (int) ($this->mortEnregistre ?? 0);
    }

    /**
     * Ticket 15.56 — dons du jour : la répartition saisie, sinon le total déjà enregistré. Un don fait QUITTER le
     * sujet de l'exploitation : il réduit l'effectif et sort du stock du produit de la bande
     * (`SyncLotProductionStockAction`, ticket 14.37).
     */
    private function donDuJour(): int
    {
        $saisis = $this->donBorde + $this->donEngraissement + $this->donNaissain;

        return $saisis > 0 ? $saisis : (int) ($this->donEnregistre ?? 0);
    }

    public function getLotsProperty()
    {
        if (! $this->moduleEnabled) {
            return collect();
        }

        return LivestockLot::whereHas('species', fn ($q) => $q->where('code', 'helico'))
            ->where('status', 'actif')
            ->where('is_active', true)
            ->orderBy('code')
            ->get();
    }

    public function getKpisProperty(): array
    {
        $lotIds = $this->lots->pluck('id');
        $monthEntries = LivestockDailyEntry::whereIn('lot_id', $lotIds)
            ->whereBetween('entry_date', [$this->debutMoisFiche(), $this->finMoisFiche()])   // EX8 : le mois affiché
            ->get();

        $totalOeufs = $monthEntries->sum('ponte_total');
        $totalNaissains = $monthEntries->sum('ne');
        $totalMorts = $monthEntries->sum('mort');
        $totalEffectifDepart = $monthEntries->sum(fn ($e) => $e->previousEffectif());

        return [
            'effectif_total' => (int) $this->lots->sum('current_quantity'),
            'naissains_mois' => (int) $totalNaissains,
            // 🔴→✅ Ticket U12a — sans un seul œuf pondu, le taux d'éclosion du mois est INCONNU (« — »), jamais 0,0 % :
            // un zéro se lit « aucune éclosion », alors que rien n'a été mis en terre.
            'taux_eclosion' => $totalOeufs > 0 ? round(($totalNaissains / $totalOeufs) * 100, 1) : null,
            'taux_mortalite_mois' => $totalEffectifDepart > 0 ? round(($totalMorts / $totalEffectifDepart) * 100, 1) : 0.0,
        ];
    }

    /** Bandes du tableau mensuel (AvecSoinsDuMois). */
    protected function lotsDuTableauMensuel(): array
    {
        return [$this->bande?->id];
    }

    /** Fiches du mois de LA bande de la fiche (ticket 15.47 : une bande par tableau, plus d'écrasement). */
    public function getMonthlyEntriesProperty()
    {
        $bande = $this->bande;

        if (! $bande) {
            return collect();
        }

        $lotIds = [$bande->id];

        // Ticket audit fidélité : eager-load treatmentProduct — colonne
        // "Traitements & Prophylaxie" du prototype, trouvée manquante du
        // tableau mensuel (même écart que fiche-lapins.html), corrigée
        // dans la foulée pour les 3 fiches partageant ce même patron.
        return LivestockDailyEntry::whereIn('lot_id', $lotIds)
            ->whereBetween('entry_date', [$this->debutMoisFiche(), $this->finMoisFiche()])   // EX8 : le mois affiché
            ->with('treatmentProduct')
            ->orderBy('entry_date')
            ->get()
            ->keyBy(fn ($e) => $e->entry_date->format('Y-m-d'));
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR BALAYAGE STRUCTUREL SYSTÉMATIQUE : le
     * bouton "Exporter PDF" du prototype était absent — même schéma déjà
     * trouvé sur de nombreux écrans. Réutilise le gabarit PARTAGÉ
     * `exports.fiche-elevage` (colonnes universelles de
     * `livestock_daily_entries`) — un seul gabarit pour les 5 fiches,
     * jamais 5 gabarits quasi-identiques à maintenir séparément.
     */
    public function exportFichePdf()
    {
        $this->authorize('view-elevage');

        $entries = $this->monthlyEntries->values();

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.fiche-elevage',
            ['entries' => $entries],
            'Fiche Escargots — Suivi Mensuel',
            $this->moisDuPdf()   // EX8 : le mois affiché
        );

        return response()->streamDownload(fn () => print($pdf->output()), $this->fichierDuPdf());
    }


    public function getPreviousEffectifProperty(): int
    {
        // Ticket 15.47 — veille de LA bande (point unique `previousEffectif`), plus celle de toutes les bandes.
        $bande = $this->bande;

        if (! $bande) {
            return 0;
        }

        $sonde = new LivestockDailyEntry(['lot_id' => $bande->id, 'entry_date' => $this->selectedDate]);
        $sonde->setRelation('lot', $bande);

        return $sonde->previousEffectif();
    }

    /**
     * Ticket 14.4 — LIEN VENTE -> FICHE ELEVAGE, cote fiche.
     *
     * Le champ "Ventes" de la fiche journaliere etait etiquete comme
     * alimente par le POS mais valait `0` EN DUR — dans le calcul
     * d'effectif final affiche a l'ecran comme dans `saveDay()`, qui le
     * reecrivait donc a zero a chaque enregistrement de la journee par
     * l'animalier. Toute vente enregistree au POS etait silencieusement
     * annulee des la sauvegarde suivante.
     *
     * Lit desormais la valeur reellement persistee par
     * `PosInterface::recordFicheVente()` — un seul point de verite, jamais
     * une seconde source de comptage cote fiche.
     */
    public function getVenteDuJourProperty(): int
    {
        $lot = $this->bande;

        if (! $lot) {
            return 0;
        }

        return (int) (LivestockDailyEntry::where('lot_id', $lot->id)
            ->where('entry_date', $this->selectedDate)
            ->value('vente') ?? 0);
    }

    public function getEffectifFinalCalcProperty(): int
    {
        $mort = $this->mortDuJour();

        return LivestockDailyEntry::computeEffectifFinal($this->previousEffectif, $this->achat, $this->naissainsNes, $mort, $this->venteDuJour, $this->donDuJour(), $this->transfertsDuJour['transfert_entree'], $this->transfertsDuJour['transfert_sortie']);
    }

    public function getMortalityRateCalcProperty(): float
    {
        $mort = $this->mortDuJour();

        return $this->previousEffectif > 0 ? round(($mort / $this->previousEffectif) * 100, 1) : 0.0;
    }

    public function getPoidsMoyenEstimeProperty(): ?int
    {
        if ($this->peseeTotal !== null) {
            return null;
        }
        $lot = $this->bande;
        if (! $lot || ! $this->selectedDate) {
            return null;
        }
        $pesees = LivestockDailyEntry::where('lot_id', $lot->id)
            ->whereNotNull('weight_sample_avg_g')
            ->where('entry_date', '<', $this->selectedDate)
            ->orderBy('entry_date')
            ->get(['entry_date', 'weight_sample_avg_g']);
        if ($pesees->isEmpty()) {
            return null;
        }
        $derniere = $pesees->last();
        $jourTarget = \Carbon\Carbon::parse($this->selectedDate)->startOfDay();
        $joursEcoules = (int) $derniere->entry_date->startOfDay()->diffInDays($jourTarget);
        if ($joursEcoules <= 0) {
            return (int) round($derniere->weight_sample_avg_g);
        }
        if ($pesees->count() >= 2) {
            $premiere = $pesees->first();
            $joursGmq = (int) $premiere->entry_date->startOfDay()->diffInDays($derniere->entry_date->startOfDay());
            $gmq = $joursGmq > 0
                ? ($derniere->weight_sample_avg_g - $premiere->weight_sample_avg_g) / $joursGmq
                : 0.0;
        } else {
            $gmq = 0.0;
        }

        return (int) round($derniere->weight_sample_avg_g + $gmq * $joursEcoules);
    }

    /**
     * 🔴→✅ TICKET U14 — sans un œuf mis en terre, le taux d'éclosion du jour est INCONNU : `null`, affiché « — »
     * (règle « inconnu = — », comme le taux du mois depuis U12a), jamais « 0,0 % ».
     */
    public function getEclosionRateCalcProperty(): ?float
    {
        return $this->oeufsTerre > 0 ? round(($this->naissainsNes / $this->oeufsTerre) * 100, 1) : null;
    }

    public function loadDay(string $date): void
    {
        $this->selectedDate = $date;
        // 🔴→✅ Ticket U12a — la fiche du jour CHOISI, même hors du mois en cours (défaut trouvé en U11 sur la fiche
        // Pondeuses, présent ici aussi). `monthlyEntries` ne porte que le mois courant : choisir le 28 du mois
        // précédent vidait le formulaire alors que la fiche existait, et « Enregistrer ce Jour » l'écrasait avec des
        // zéros (achats, œufs pondus, naissains, effectifs saisis). Le poste charge la fiche de n'importe quel jour.
        $bande = $this->bande;
        $entry = $this->monthlyEntries->get($date)
            ?? ($bande ? LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', $date)->first() : null);
        $this->reset(['mortBorde', 'mortEngraissement', 'mortNaissain', 'mortEnregistre', 'donBorde', 'donEngraissement', 'donNaissain', 'donEnregistre']);

        if ($entry) {
            $this->mortEnregistre = (int) $entry->mort > 0 ? (int) $entry->mort : null;
            $this->donEnregistre = (int) ($entry->don ?? 0) > 0 ? (int) $entry->don : null;
            $this->achat = $entry->achat;
            $this->oeufsTerre = $entry->ponte_total ?? 0;
            $this->naissainsNes = $entry->ne;
            $this->effectifNaissains = $entry->effectif_m ?? 0;
            $this->effectifEngraissement = $entry->effectif_f ?? 0;
            $this->effectifBordes = $entry->effectif_sevres ?? 0;
            // Le TOTAL pese se reconstitue depuis la moyenne stockee.
            $effectifFiche = (int) ($entry->effectif_final ?? 0);
            $this->peseeTotal = $entry->weight_sample_avg_g && $effectifFiche > 0
                ? (int) round($entry->weight_sample_avg_g * $effectifFiche)
                : null;
        } else {
            $this->reset(['achat', 'oeufsTerre', 'naissainsNes', 'effectifNaissains', 'effectifEngraissement', 'effectifBordes', 'peseeTotal']);
        }
    }

    public function saveDay(): void
    {
        $this->authorize('manage-elevage');
        $lot = $this->bande;

        if (! $lot) {
            $this->dispatch('toast', message: "Aucune bande active en héliciculture. Créez d'abord une bande.", type: 'error');

            return;
        }

        // 🔴→✅ Ticket EX5 (EF5, décision Q3 du 20/10/2026) — une fiche datée dans un exercice CLOS est refusée : le stock
        // consommé de cet exercice est figé avec son inventaire. Même motif R4 qu'à l'envoi d'un poste.
        if ($refusExercice = app(\App\Services\AccountingEntryService::class)->refusExerciceClos($this->selectedDate)) {
            $this->dispatch('toast', message: $refusExercice, type: 'error');

            return;
        }

        $mort = $this->mortDuJour();
        $effectifFinal = $this->effectifFinalCalc;        // 🔴→✅ TICKET 14.37 — état AVANT enregistrement, pour n'appliquer
        // au stock que l'ÉCART. Une fiche se corrige : appliquer les
        // valeurs telles quelles compterait la production autant de fois
        // que la journée est sauvegardée.
        $ficheAvant = LivestockDailyEntry::where('lot_id', $lot->id)
            ->whereDate('entry_date', $this->selectedDate)
            ->first();

        $etatAvant = $ficheAvant
            ? ['ne' => (int) $ficheAvant->ne, 'mort' => (int) $ficheAvant->mort, 'don' => (int) ($ficheAvant->don ?? 0)]
            : [];



        $entree = DB::transaction(function () use ($effectifFinal, $etatAvant, $lot, $mort) {
            // 🔴→✅ Ticket U14 — UNE TRANSACTION, ET LE STOCK AVANT LA FICHE (`OrdreDesVerrous`), comme les fiches Porcs et
            // Lapins, la caisse et l'envoi des postes. Ces écritures (fiche, production au stock, cascade) partaient une par
            // une : une erreur au milieu laissait la fiche sans son mouvement de stock.
            OrdreDesVerrous::stock(OrdreDesVerrous::produitsDesFiches([$lot->id]));

            $entree = LivestockDailyEntry::updateOrCreate(
                ['lot_id' => $lot->id, 'entry_date' => $this->selectedDate],
                [
                    'achat' => $this->achat,
                    'ne' => $this->naissainsNes,
                    'mort' => $mort,
                    'vente' => $this->venteDuJour,
                    'don' => $this->donDuJour(),
                    'effectif_final' => $effectifFinal,
                    'ponte_total' => $this->oeufsTerre,
                    'effectif_m' => $this->effectifNaissains,
                    'effectif_f' => $this->effectifEngraissement,
                    'effectif_sevres' => $this->effectifBordes,
                    // 🔴→✅ TICKET 14.63 — LA COLONNE PORTE LE POIDS **MOYEN PAR
                    // SUJET**, en grammes. Cette fiche y deposait le TOTAL pese :
                    // `GrowthAnalysisService` en tire le GMQ en la traitant comme
                    // une moyenne, si bien qu'une bande qui perd des animaux voyait
                    // son « poids » BAISSER et son GMQ devenir negatif — un
                    // indicateur de croissance qui lit un amaigrissement.
                    //
                    // ⚠️ ARRONDI, PAS TRONCATURE : la maquette calcule
                    // `Math.round(poidsG / effectifFinal)`.
                    'weight_sample_avg_g' => $this->peseeTotal && $effectifFinal > 0
                        ? (int) round($this->peseeTotal / $effectifFinal)
                        : null,
                ]
            );

            // La production du cheptel entre réellement en stock — naissances
            // portées au crédit, mortalité et dons au débit. Sans bande
            // rattachée à un produit, l'Action ne fait rien.
            app(SyncLotProductionStockAction::class)->execute($entree, $etatAvant);

            // 🔴→✅ CORRECTIF « EFFECTIF TOTAL VIVANT » — la bande prenait l'effectif du jour ÉDITÉ.
            // Saisir ou corriger une fiche antérieure à la dernière remplaçait `current_quantity` par
            // l'effectif de CE jour (KPI « Effectif Total Vivant » faux sur Gestion des Bandes, Gestion
            // Élevage, Tableau de bord), sans recalculer les fiches suivantes. Même point d'entrée que
            // les fiches Porcs/Lapins (ticket 15.42), la vente antidatée et le push : jours suivants
            // recalculés, bande = DERNIÈRE fiche.
            app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot->id, $this->selectedDate);

            return $entree;
        });

        AuditLog::record('livestock_daily_entry.saved', 'elevage');
        $this->dispatch('toast', message: 'Jour enregistré avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.elevage.fiche-escargots', ['title' => 'Élevage > Fiches Escargots']);
    }
}
