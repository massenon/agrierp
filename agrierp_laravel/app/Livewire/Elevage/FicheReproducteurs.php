<?php

namespace App\Livewire\Elevage;

use App\Livewire\Elevage\Concerns\AvecTransfertsDuJour;
use App\Actions\RecordSaleOnFicheElevageAction;
use App\Actions\SyncLotProductionStockAction;
use App\Livewire\Elevage\Concerns\AvecProphylaxieDuJour;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\FeedRationStandard;
use App\Support\RationVolaille;
use App\Models\LivestockLot;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 3.7 (Sprint 3) — fiche-volailles-reproducteurs.html →
 * Livewire\Elevage\FicheReproducteurs — workflow Couvoir & Éclosion,
 * Taux d'Éclosion (FORMULE_FICHE_ELEVAGE.md §3).
 *
 * ⚠️ ÉCART CONSTATÉ ENTRE LE DOCUMENT DE RÉFÉRENCE ET LE PROTOTYPE RÉEL :
 * `RESPECT_TABLEAU_MENSUEL_DES_31_JOURS...md` classe cette fiche en
 * "Variante A" (structure Entrées/Sorties/Effectif à 5 colonnes, identique
 * à Lapins/Porcs/Escargots). La lecture directe de
 * `fiche-volailles-reproducteurs.html` (lignes 465-483) montre une
 * structure RÉELLEMENT DIFFÉRENTE et propre à cette fiche : Date / Lot-
 * Souche / Couvoir (Couvés, Nés) / Morts par catégorie (Repro, Poulet,
 * Poussin) / Effectif Final (colonne UNIQUE, pas de M/F/Sevrés/S-Mères) /
 * Taux Mort % / Poids Général (g) / Traitements. Le prototype (hiérarchie
 * des sources n°1) l'emporte sur le document de référence, qui semble
 * avoir généralisé à tort cette fiche sous le même gabarit que les autres.
 * Colonnes implémentées ici EXACTEMENT comme observées dans le fichier
 * source, pas comme le document de référence les décrivait.
 *
 * Mapping de colonnes (réutilise le schéma existant, aucune nouvelle
 * colonne nécessaire) :
 *   - `ponte_total` = Œufs Couvés (mis en incubation)
 *   - `ne` = Poussins Nés (éclosion du jour — alimente aussi l'effectif
 *     final via la formule universelle, un poussin né est un animal vivant
 *     de plus)
 *   - `ponte_casses` non utilisé sur cette fiche (workflow différent de la
 *     ponte commerciale des Pondeuses)
 *
 * Multi-lots : contrairement aux fiches Lapins/Pondeuses (un seul lot actif
 * par écran), le prototype propose un sélecteur "Bande / Lot Concerné"
 * (Reproducteurs / Goliath-Chair / Poussins Démarrage peuvent coexister).
 * Repris ici avec les bandes actives réelles (aviculture, hors stade
 * ponte — géré par la fiche Pondeuses).
 */
#[Layout('layouts.app')]
class FicheReproducteurs extends Component
{
    use AvecTransfertsDuJour;
    use AvecProphylaxieDuJour;

    public string $selectedDate;

    public string $selectedLotId = '';

    public int $achat = 0;

    public int $oeufsCouves = 0;

    public int $poussinsNes = 0;

    public int $mortRepro = 0;

    public int $mortPoulet = 0;

    public int $mortPoussin = 0;

    public int $donRepro = 0;

    public int $donPoulet = 0;

    public int $donPoussin = 0;

    /**
     * Ticket 15.56 — dons déjà enregistrés pour le jour rechargé (même règle que `mortEnregistre`) : la répartition
     * n'est pas stockée, seul le total l'est ; il est gardé tant qu'aucune répartition n'est ressaisie.
     */
    public ?int $donEnregistre = null;

    /**
     * Ticket 15.55 — morts déjà enregistrés pour le jour rechargé (miroir de 15.47, Pondeuses et Escargots). La
     * répartition Repro / Poulet / Poussin n'est pas stockée : `loadDay` ne rechargeait AUCUN mort (ceux d'un
     * autre jour affiché restaient même dans les compteurs), et ré-enregistrer le jour remettait ses morts à zéro
     * ou y inscrivait ceux d'un autre jour. Le total est gardé tant qu'aucune répartition n'est ressaisie.
     */
    public ?int $mortEnregistre = null;

    public ?int $peseeTotal = null;

    public string $observations = '';

    public function mount(): void
    {
        $this->selectedDate = now()->format('Y-m-d');
        $this->selectedLotId = $this->lots->first()?->id ?? '';
        // 🔴→✅ Ticket U12a — le jour du jour s'ouvre avec SES valeurs (vente du POS, saisie précédente), comme les
        // autres fiches : sans ce chargement, le formulaire s'ouvrait à zéro et « Enregistrer ce Jour » écrasait la
        // fiche du jour (achats, œufs couvés, poussins nés) avec ces zéros.
        $this->loadDay($this->selectedDate);
    }

    /**
     * 🔴→✅ Ticket U12a — changer la date CHARGE le jour choisi. Le champ « Date : » (`wire:model.live`) changeait la
     * date sans recharger le formulaire : les valeurs du jour précédemment affiché s'enregistraient sur le nouveau.
     */
    public function updatedSelectedDate(): void
    {
        $this->loadDay($this->selectedDate);
    }

    public function getLotsProperty()
    {
        return LivestockLot::whereHas('species', fn ($q) => $q->where('code', 'aviculture'))
            ->where('stage', '!=', 'ponte')
            ->where('status', 'actif')
            ->where('is_active', true)
            ->get();
    }

    /** Prophylaxie du jour : la bande sélectionnée dans la fiche (AvecProphylaxieDuJour). */
    protected function bandeDeLaFiche()
    {
        return $this->selectedLot;
    }

    public function getSelectedLotProperty(): ?LivestockLot
    {
        return $this->lots->firstWhere('id', $this->selectedLotId);
    }

    public function getKpisProperty(): array
    {
        $lotIds = $this->lots->pluck('id');
        $monthEntries = LivestockDailyEntry::whereIn('lot_id', $lotIds)
            ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
            ->get();

        $totalCouves = $monthEntries->sum('ponte_total');
        $totalNes = $monthEntries->sum('ne');
        $totalMorts = $monthEntries->sum('mort');
        $totalEffectifDepart = $monthEntries->sum(fn ($e) => $e->previousEffectif());

        return [
            'effectif_total' => (int) $this->lots->sum('current_quantity'),
            // 🔴→✅ Ticket U12a — sans un seul œuf couvé, le taux d'éclosion du mois est INCONNU (« — »). Le web
            // affichait 85,0 % : la valeur de DÉMONSTRATION de la maquette, présentée comme un taux calculé (le même
            // défaut que le ticket 14.61 avait corrigé pour le taux du jour).
            'taux_eclosion' => $totalCouves > 0 ? round(($totalNes / $totalCouves) * 100, 1) : null,
            'poussins_nes' => (int) $totalNes,
            'taux_mortalite_mois' => $totalEffectifDepart > 0 ? round(($totalMorts / $totalEffectifDepart) * 100, 1) : 0.0,
        ];
    }

    public function getMonthlyEntriesProperty()
    {
        if (! $this->selectedLotId) {
            return collect();
        }

        return LivestockDailyEntry::where('lot_id', $this->selectedLotId)
            ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
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
            'Fiche Reproducteurs (Aviculture) — Suivi Mensuel',
            now()->translatedFormat('F Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'fiche-'.now()->format('Y-m').'.pdf');
    }

    public function getDaysInMonthProperty(): array
    {
        return range(1, now()->daysInMonth);
    }

    public function getPreviousEffectifProperty(): int
    {
        if (! $this->selectedLot) {
            return 0;
        }

        $entry = LivestockDailyEntry::where('lot_id', $this->selectedLotId)
            ->where('entry_date', '<', $this->selectedDate)
            ->orderByDesc('entry_date')
            ->first();

        return $entry?->effectif_final ?? $this->selectedLot->initial_quantity;
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
        if (! $this->selectedLotId) {
            return 0;
        }

        return (int) (LivestockDailyEntry::where('lot_id', $this->selectedLotId)
            ->where('entry_date', $this->selectedDate)
            ->value('vente') ?? 0);
    }

    /** Morts du jour : la répartition saisie, sinon le total déjà enregistré (15.55). */
    private function mortDuJour(): int
    {
        $saisis = $this->mortRepro + $this->mortPoulet + $this->mortPoussin;

        return $saisis > 0 ? $saisis : (int) ($this->mortEnregistre ?? 0);
    }

    /**
     * Ticket 15.56 — dons du jour : la répartition saisie, sinon le total déjà enregistré. Un don fait QUITTER le
     * sujet de l'exploitation : il réduit l'effectif et sort du stock du produit de la bande
     * (`SyncLotProductionStockAction`, ticket 14.37).
     */
    private function donDuJour(): int
    {
        $saisis = $this->donRepro + $this->donPoulet + $this->donPoussin;

        return $saisis > 0 ? $saisis : (int) ($this->donEnregistre ?? 0);
    }

    public function getEffectifFinalCalcProperty(): int
    {
        $mort = $this->mortDuJour();

        return LivestockDailyEntry::computeEffectifFinal($this->previousEffectif, $this->achat, $this->poussinsNes, $mort, $this->venteDuJour, $this->donDuJour(), $this->transfertsDuJour['transfert_entree'], $this->transfertsDuJour['transfert_sortie']);
    }

    public function getMortalityRateCalcProperty(): float
    {
        $mort = $this->mortDuJour();

        return $this->previousEffectif > 0 ? round(($mort / $this->previousEffectif) * 100, 1) : 0.0;
    }

    /**
     * 🔴→✅ TICKET 14.61 — 85 % ANNONCES SANS UN SEUL OEUF COUVE.
     *
     * ⚠️ La maquette distingue DEUX replis, et un seul avait ete recopie ici :
     * `computeTauxEclosionLive()` (l. 789 de `fiche-volailles-reproducteurs.html`)
     * retombe sur **'0.0'** pour le taux DU JOUR ; seul le KPI MENSUEL affiche
     * « 85.0 » — une valeur de demonstration. Le taux du jour affichait donc
     * **85 %** tant qu'aucun oeuf n'etait mis en incubation : un chiffre invente,
     * presente comme calcule, sur l'indicateur qui decide de la conduite du
     * couvoir.
     *
     * 🔴→✅ TICKET U14 — SANS ŒUF COUVÉ, LE TAUX DU JOUR EST INCONNU : `null`, affiché « — » (règle « inconnu = — »,
     * comme le taux du mois depuis U12a). « 0,0 % » se lisait « aucune éclosion » alors que rien n'était en incubation ;
     * une couvée entièrement perdue (œufs couvés, aucun né) affiche bien « 0,0 % ».
     */
    public function getEclosionRateCalcProperty(): ?float
    {
        return $this->oeufsCouves > 0 ? round(($this->poussinsNes / $this->oeufsCouves) * 100, 1) : null;
    }

    public function updatedSelectedLotId(): void
    {
        $this->loadDay($this->selectedDate);
    }

    public function loadDay(string $date): void
    {
        $this->traitementsCoches = [];   // une case cochée ne survit pas à un changement de jour
        $this->selectedDate = $date;
        // 🔴→✅ Ticket U12a — la fiche du jour CHOISI, même hors du mois en cours (défaut de la fiche Pondeuses, U11) :
        // `monthlyEntries` ne porte que le mois courant, un jour du mois précédent s'ouvrait vide et s'écrasait.
        $entry = $this->monthlyEntries->get($date)
            ?? ($this->selectedLotId !== ''
                ? LivestockDailyEntry::where('lot_id', $this->selectedLotId)->whereDate('entry_date', $date)->first()
                : null);

        $this->reset(['mortRepro', 'mortPoulet', 'mortPoussin', 'mortEnregistre', 'donRepro', 'donPoulet', 'donPoussin', 'donEnregistre']);

        if ($entry) {
            $this->achat = $entry->achat;
            $this->oeufsCouves = $entry->ponte_total ?? 0;
            $this->poussinsNes = $entry->ne;
            $this->mortEnregistre = (int) $entry->mort > 0 ? (int) $entry->mort : null;
            $this->donEnregistre = (int) ($entry->don ?? 0) > 0 ? (int) $entry->don : null;
            // Le TOTAL pese se reconstitue depuis la moyenne stockee.
            $effectifFiche = (int) ($entry->effectif_final ?? 0);
            $this->peseeTotal = $entry->weight_sample_avg_g && $effectifFiche > 0
                ? (int) round($entry->weight_sample_avg_g * $effectifFiche)
                : null;
        } else {
            $this->reset(['achat', 'oeufsCouves', 'poussinsNes', 'mortRepro', 'mortPoulet', 'mortPoussin', 'peseeTotal']);
        }
    }

    public function saveDay(): void
    {
        $this->authorize('manage-elevage');
        if (! $this->selectedLot) {
            $this->dispatch('toast', message: "Sélectionnez d'abord une bande.", type: 'error');

            return;
        }

        $mort = $this->mortDuJour();
        $effectifFinal = $this->effectifFinalCalc;        // 🔴→✅ TICKET 14.37 — état AVANT enregistrement, pour n'appliquer
        // au stock que l'ÉCART. Une fiche se corrige : appliquer les
        // valeurs telles quelles compterait la production autant de fois
        // que la journée est sauvegardée.
        // 🔴→✅ TICKET 14.63 — `$lot` N'ETAIT JAMAIS AFFECTE. La methode
        // levait « Undefined variable $lot » a chaque enregistrement : la
        // fiche Reproducteurs ne pouvait tout simplement PAS enregistrer sur
        // le web, et le correctif « delta » du ticket 14.37 qu'elle porte
        // n'avait jamais pu s'executer. Aucun test n'appelait `saveDay()`.
        $lot = $this->selectedLot;

        $ficheAvant = LivestockDailyEntry::where('lot_id', $lot->id)
            ->whereDate('entry_date', $this->selectedDate)
            ->first();

        $etatAvant = $ficheAvant
            ? ['ne' => (int) $ficheAvant->ne, 'mort' => (int) $ficheAvant->mort, 'don' => (int) ($ficheAvant->don ?? 0)]
            : [];



        $entree = LivestockDailyEntry::updateOrCreate(
            ['lot_id' => $this->selectedLotId, 'entry_date' => $this->selectedDate],
            [
                'achat' => $this->achat,
                'ne' => $this->poussinsNes,
                'mort' => $mort,
                'vente' => $this->venteDuJour,
                'don' => $this->donDuJour(),
                'effectif_final' => $effectifFinal,
                'ponte_total' => $this->oeufsCouves,
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

        AuditLog::record('livestock_daily_entry.saved', 'elevage');
        $this->dispatch('toast', message: 'Jour enregistré avec succès.', type: 'success');
    }

    /**
     * Ticket 15.57 — rationnement par stade, même règle que le poste (`RationVolaille`). Barème de l'aviculture.
     */
    public function getRationnementProperty(): array
    {
        return RationVolaille::tableau(
            FeedRationStandard::where('species_code', 'aviculture')->get(),
            RationVolaille::REPRODUCTEUR,
            $this->effectifFinalCalc,
        );
    }

    public function render()
    {
        return view('livewire.elevage.fiche-reproducteurs', ['title' => 'Élevage > Fiches Volailles Reproducteurs']);
    }
}
