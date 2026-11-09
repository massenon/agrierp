<?php

namespace App\Livewire\Elevage;

use App\Livewire\Elevage\Concerns\AvecTransfertsDuJour;
use App\Actions\RecordSaleOnFicheElevageAction;
use App\Actions\SyncLotProductionStockAction;
use App\Livewire\Elevage\Concerns\AvecProphylaxieDuJour;
use App\Actions\RaiseFeedAutonomyAlertAction;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\FeedRationStandard;
use App\Support\CategorieVolaille;
use App\Models\LivestockLot;
use App\Services\AutonomieAlimentaireService;
use App\Services\EffectifParCategorieService;
use App\Support\OrdreDesVerrous;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
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
 *
 * 🔁 TICKET VOL-1 (décision client du 04/11/2026) — EFFECTIF PAR CATÉGORIE CALCULÉ, comme les lapins et les porcs
 * (tickets 15.39 à 15.42). Trois catégories : Reproducteur, Jeune, Poussin. ⚠️ Libellé affiché « Jeune » — jamais « Jeune
 * à maturité », jamais « Poulet » (les propriétés `mortPoulet` / `donPoulet` gardent leur nom interne). Emplacements
 * génériques de synchronisation : `repro` = Reproducteur ; `sevre` = Poussin ; `jeune` = Jeune.
 *   R = max(0, Rv − vente_R − mort_R − don_R)
 *   J = max(0, Jv + achat − vente_J − mort_J − don_J + p)      (les achats vont aux Jeunes)
 *   P = max(0, Pv + éclosions − vente_P − mort_P − don_P − p)  (p = passage Poussin → Jeune, refusé au-delà du stock source)
 * Calcul : `EffectifParCategorieService::calculerJour(VOLAILLES_REPRO, …)` — aucune formule recopiée ici. ⚠️ AUCUNE catégorie
 * « inconnue » sur cette fiche (contrairement aux lapins) : le DÉPART de la bande (effectif de chaque catégorie au début
 * du jour de départ, somme = effectif total) est exigé avant toute saisie ; sans lui la fiche affiche la demande de
 * départ au lieu de l'effectif et refuse d'enregistrer ; les jours antérieurs au départ ne sont pas saisissables. Les
 * ventes (`vente_repro/sevre/jeune`) viennent de la caisse, rangées dans la catégorie du PRODUIT vendu.
 */
#[Layout('layouts.app')]
class FicheReproducteurs extends Component
{
    use \App\Livewire\Elevage\Concerns\AvecMoisDeFiche;   // Ticket EX8 (EF12) : mois passés, lecture seule
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

    /** Ticket VOL-1 — passage de stade du jour, Poussin → Jeune (un FAIT saisi, jamais un effectif). */
    public int $passage = 0;

    /**
     * Ticket VOL-1 — EFFECTIF DE DÉPART par catégorie (début du jour de départ), saisi UNE fois par bande puis verrouillé.
     * Emplacements génériques : `departSevre` = Poussin, `departJeune` = Jeune.
     */
    public ?int $departRepro = null;

    public ?int $departSevre = null;

    public ?int $departJeune = null;

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
            ->whereBetween('entry_date', [$this->debutMoisFiche(), $this->finMoisFiche()])   // EX8 : le mois affiché
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
            ->whereBetween('entry_date', [$this->debutMoisFiche(), $this->finMoisFiche()])   // EX8 : le mois affiché
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
            $this->moisDuPdf()   // EX8 : le mois affiché
        );

        return response()->streamDownload(fn () => print($pdf->output()), $this->fichierDuPdf());
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

    public function getPoidsMoyenEstimeProperty(): ?int
    {
        if ($this->peseeTotal !== null) {
            return null;
        }
        $lot = $this->selectedLotId !== '' ? LivestockLot::find($this->selectedLotId) : null;
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

        $this->reset(['mortRepro', 'mortPoulet', 'mortPoussin', 'mortEnregistre', 'donRepro', 'donPoulet', 'donPoussin', 'donEnregistre', 'passage', 'departRepro', 'departSevre', 'departJeune']);

        if ($entry) {
            $this->achat = $entry->achat;
            $this->oeufsCouves = $entry->ponte_total ?? 0;
            $this->poussinsNes = $entry->ne;
            // Ticket VOL-1 : la ventilation STOCKÉE recharge le jour (emplacements : `*_sevre` = Poussin, `*_jeune` = Jeune).
            // Une fiche d'AVANT le ticket (colonnes à null) garde son total : il doit être ventilé avant d'enregistrer.
            if ($entry->mort_repro !== null && $entry->mort_sevre !== null && $entry->mort_jeune !== null) {
                $this->mortRepro = (int) $entry->mort_repro;
                $this->mortPoussin = (int) $entry->mort_sevre;
                $this->mortPoulet = (int) $entry->mort_jeune;
            } else {
                $this->mortEnregistre = (int) $entry->mort > 0 ? (int) $entry->mort : null;
            }
            if ($entry->don_repro !== null && $entry->don_sevre !== null && $entry->don_jeune !== null) {
                $this->donRepro = (int) $entry->don_repro;
                $this->donPoussin = (int) $entry->don_sevre;
                $this->donPoulet = (int) $entry->don_jeune;
            } else {
                $this->donEnregistre = (int) ($entry->don ?? 0) > 0 ? (int) $entry->don : null;
            }
            $this->passage = (int) ($entry->passage_sevre_jeune ?? 0);
            // Le TOTAL pese se reconstitue depuis la moyenne stockee.
            $effectifFiche = (int) ($entry->effectif_final ?? 0);
            $this->peseeTotal = $entry->weight_sample_avg_g && $effectifFiche > 0
                ? (int) round($entry->weight_sample_avg_g * $effectifFiche)
                : null;
        } else {
            $this->reset(['achat', 'oeufsCouves', 'poussinsNes', 'mortRepro', 'mortPoulet', 'mortPoussin', 'peseeTotal']);
        }
    }

    /** Ticket VOL-1 — date au format AAAA-MM-JJ et réelle (un champ date vidé ne casse pas la fiche). */
    private function dateValide(?string $date): bool
    {
        if ($date === null || ! preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
            return false;
        }

        try {
            return Carbon::createFromFormat('Y-m-d', $date)->format('Y-m-d') === $date;
        } catch (\Throwable) {
            return false;
        }
    }

    /**
     * Livewire garde chaque propriété calculée en cache pour toute la requête : après une écriture, l'écran rendu dans la
     * MÊME requête afficherait l'état d'avant (départ encore saisissable, tableau mensuel sans le jour).
     */
    private function purgerCalculs(): void
    {
        unset($this->lots, $this->selectedLot, $this->categoriesJour, $this->previousEffectif, $this->venteDuJour,
            $this->ventesDuJour, $this->effectifFinalCalc, $this->rationnement, $this->feedAutonomy, $this->monthlyEntries, $this->kpis);
    }

    /** Ticket VOL-1 — les ventes du jour, par catégorie (colonnes `vente_*` posées par la caisse), 0 sans fiche. */
    public function getVentesDuJourProperty(): array
    {
        $fiche = $this->selectedLotId !== '' && $this->dateValide($this->selectedDate)
            ? LivestockDailyEntry::where('lot_id', $this->selectedLotId)->whereDate('entry_date', $this->selectedDate)->first()
            : null;

        return [
            'repro' => (int) ($fiche?->vente_repro ?? 0),
            'sevre' => (int) ($fiche?->vente_sevre ?? 0),
            'jeune' => (int) ($fiche?->vente_jeune ?? 0),
            // Vente d'AVANT le ticket : le total existe, sa répartition par catégorie non (voir saveDay).
            'non_ventilee' => $fiche !== null && (int) $fiche->vente > 0 && $fiche->vente_repro === null,
        ];
    }

    /**
     * Ticket VOL-1 — EFFECTIFS PAR CATÉGORIE : CALCULÉS, jamais saisis (voir le docblock de la classe). Retourne
     * `mode` (`depart_requis` | `avant_depart` | `refus` | `chaine`), les trois effectifs (`null` UNIQUEMENT tant que le
     * départ n'est pas valide : la vue affiche alors la demande de départ, jamais « — »), le résultat du service, le
     * motif de refus du départ stocké ou saisi, le refus de passage et les avertissements.
     *
     * @return array{mode: string, repro: ?int, sevre: ?int, jeune: ?int, resultat: ?\App\Support\EffectifCategoriesJour, motif: ?string, refus_passage: ?string, avertissements: list<string>, depart_requis: bool, depart_date: ?string, depart: ?array, proposition: ?array}
     */
    public function getCategoriesJourProperty(): array
    {
        $sortie = [
            'mode' => 'depart_requis', 'repro' => null, 'sevre' => null, 'jeune' => null, 'resultat' => null,
            'motif' => null, 'refus_passage' => null, 'avertissements' => [], 'depart_requis' => true,
            'depart_date' => null, 'depart' => null, 'proposition' => null,
        ];

        $bande = $this->selectedLot;
        if (! $bande || ! $this->dateValide($this->selectedDate)) {
            return $sortie;
        }

        $service = app(EffectifParCategorieService::class);
        $etat = $service->etatPourJour($bande->loadMissing('species'), $this->selectedDate);
        $sortie['depart_date'] = $etat['depart_date'];
        $sortie['depart'] = $etat['depart'];
        $sortie['motif'] = $etat['refus'];
        $veille = $etat['veille'];

        if ($etat['mode'] === 'sans_chaine') {
            // Aucune chaîne : le départ est demandé. Proposition d'après le stade de la bande (jamais appliquée seule).
            $sortie['mode'] = 'depart_requis';
            $sortie['proposition'] = EffectifParCategorieService::departDepuisStade($bande, $this->previousEffectif);
            $saisi = ['repro' => $this->departRepro, 'sevre' => $this->departSevre, 'jeune' => $this->departJeune];

            if (in_array(null, $saisi, true)) {
                if (count(array_filter($saisi, fn ($v) => $v !== null)) > 0) {
                    $sortie['motif'] = EffectifParCategorieService::verifierDepart($saisi, $this->previousEffectif);
                }

                return $sortie;
            }

            $sortie['motif'] = EffectifParCategorieService::verifierDepart($saisi, $this->previousEffectif);
            if ($sortie['motif'] !== null) {
                return $sortie;
            }
            $veille = $saisi;     // aperçu : le départ saisi est l'effectif au DÉBUT du jour (D4)
        } else {
            $sortie['mode'] = $etat['mode'];
            $sortie['depart_requis'] = false;
        }

        if ($veille === null) {
            return $sortie;       // avant le départ ou départ stocké refusé
        }

        $ventes = $this->ventesDuJour;
        $resultat = EffectifParCategorieService::calculerJour(EffectifParCategorieService::VOLAILLES_REPRO, $veille, [
            'achat' => $this->achat, 'ne' => $this->poussinsNes,
            'vente_repro' => $ventes['repro'], 'vente_sevre' => $ventes['sevre'], 'vente_jeune' => $ventes['jeune'],
            // Emplacements : `sevre` = Poussin ; `jeune` = Jeune (propriétés internes `*Poulet`).
            'mort_repro' => $this->mortRepro, 'mort_sevre' => $this->mortPoussin, 'mort_jeune' => $this->mortPoulet,
            'don_repro' => $this->donRepro, 'don_sevre' => $this->donPoussin, 'don_jeune' => $this->donPoulet,
            'passage' => $this->passage,
        ] + $this->transfertsDuJour, $this->effectifFinalCalc);

        $sortie['resultat'] = $resultat;
        $sortie['repro'] = $resultat->repro;
        $sortie['sevre'] = $resultat->sevre;
        $sortie['jeune'] = $resultat->jeune;
        $sortie['refus_passage'] = $resultat->refus;

        // D8 : avertissement DATÉ, jamais un blocage (le plancher à 0 de chaque catégorie suffit à le produire).
        if ($resultat->sommeDifferente === true) {
            $sortie['avertissements'][] = 'Avertissement — fiche du '.Carbon::parse($this->selectedDate)->format('d/m/Y')
                .' : la somme des catégories ('.$resultat->somme().') diffère de l\'effectif total ('.$this->effectifFinalCalc
                .'). Un effectif de catégorie ne descend jamais sous 0 : vérifiez les ventes, morts et dons saisis.';
        }

        return $sortie;
    }

    /** D9 : des morts supérieurs à l'effectif de la veille ne bloquent pas (plancher à 0) — l'écran le dit. */
    public function getAvertissementMortsProperty(): ?string
    {
        $morts = $this->mortDuJour();

        return $morts > $this->previousEffectif
            ? "Morts du jour ({$morts}) supérieurs à l'effectif de la veille ({$this->previousEffectif}) : l'effectif est ramené à 0, vérifiez la saisie."
            : null;
    }

    /** Ticket VOL-1 — reprend la proposition de départ déduite du stade de la bande (action explicite de l'éleveur). */
    public function appliquerPropositionDepart(): void
    {
        $proposition = $this->categoriesJour['proposition'];

        if ($proposition === null) {
            $this->dispatch('toast', message: 'Aucune proposition pour le stade de cette bande : saisissez le départ de chaque catégorie.', type: 'warning');

            return;
        }

        $this->departRepro = $proposition['repro'];
        $this->departSevre = $proposition['sevre'];
        $this->departJeune = $proposition['jeune'];
    }

    public function saveDay(): void
    {
        $this->authorize('manage-elevage');
        if (! $this->selectedLot) {
            $this->dispatch('toast', message: "Sélectionnez d'abord une bande.", type: 'error');

            return;
        }

        // 🔴→✅ Ticket EX5 (EF5, décision Q3 du 20/10/2026) — une fiche datée dans un exercice CLOS est refusée : le stock
        // consommé de cet exercice est figé avec son inventaire. Même motif R4 qu'à l'envoi d'un poste.
        if ($refusExercice = app(\App\Services\AccountingEntryService::class)->refusExerciceClos($this->selectedDate)) {
            $this->dispatch('toast', message: $refusExercice, type: 'error');

            return;
        }

        if (! $this->dateValide($this->selectedDate)) {
            $this->dispatch('toast', message: 'Date invalide : choisissez un jour.', type: 'error');

            return;
        }

        // --- Ticket VOL-1 : contrôles AVANT toute écriture ------------------------------------------------------
        $cat = $this->categoriesJour;

        // Un jour antérieur au départ n'est pas saisissable (jamais d'effectif inconnu affiché).
        if ($cat['mode'] === 'avant_depart') {
            $this->dispatch('toast', message: 'Jour antérieur à l\'effectif de départ fixé le '.Carbon::parse($cat['depart_date'])->format('d/m/Y').' : il n\'est pas saisissable.', type: 'error');

            return;
        }

        // Départ stocké incohérent (D4) : la chaîne est refusée.
        if ($cat['mode'] === 'refus') {
            $this->dispatch('toast', message: $cat['motif'], type: 'error');

            return;
        }

        // Bande sans départ : il doit être saisi, complet et cohérent, AVANT d'enregistrer la journée.
        $departAEcrire = false;
        if ($cat['mode'] === 'depart_requis') {
            $departSaisi = ['repro' => $this->departRepro, 'sevre' => $this->departSevre, 'jeune' => $this->departJeune];
            $refusDepart = in_array(null, $departSaisi, true) && count(array_filter($departSaisi, fn ($v) => $v !== null)) === 0
                ? 'Saisissez d\'abord l\'effectif de départ de la bande par catégorie (Reproducteur, Jeune, Poussin) : la journée ne peut pas être enregistrée sans lui.'
                : EffectifParCategorieService::verifierDepart($departSaisi, $this->previousEffectif);
            if ($refusDepart !== null) {
                $this->dispatch('toast', message: $refusDepart, type: 'error');

                return;
            }
            $departAEcrire = true;
        }

        // D3 : un passage de stade supérieur à la catégorie source ne s'enregistre pas.
        if ($cat['refus_passage'] !== null) {
            $this->dispatch('toast', message: $cat['refus_passage'], type: 'error');

            return;
        }

        $mort = $this->mortRepro + $this->mortPoulet + $this->mortPoussin;
        $don = $this->donRepro + $this->donPoulet + $this->donPoussin;

        // Fiche d'AVANT le ticket (morts / dons / ventes non ventilés) : on ne devine pas la catégorie, on le dit.
        if (($this->mortEnregistre !== null && $mort === 0) || ($this->donEnregistre !== null && $don === 0)) {
            $this->dispatch('toast', message: 'Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les (Reproducteur / Jeune / Poussin) avant d\'enregistrer.', type: 'error');

            return;
        }
        if ($this->ventesDuJour['non_ventilee']) {
            $this->dispatch('toast', message: 'Cette journée porte des ventes d\'avant la mise en place des catégories, non ventilées : elle ne peut pas être ré-enregistrée. Saisissez le départ de la bande un autre jour.', type: 'error');

            return;
        }

        $ventes = $this->ventesDuJour;
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



        $entree = DB::transaction(function () use ($effectifFinal, $etatAvant, $lot, $mort, $don, $ventes, $departAEcrire) {
            // 🔴→✅ Ticket U14 — UNE TRANSACTION, ET LE STOCK AVANT LA FICHE (`OrdreDesVerrous`), comme les fiches Porcs et
            // Lapins, la caisse et l'envoi des postes. Ces écritures (fiche, production au stock, cascade) partaient une par
            // une : une erreur au milieu laissait la fiche sans son mouvement de stock.
            OrdreDesVerrous::stock(OrdreDesVerrous::produitsDesFiches([$lot->id]));

            $entree = LivestockDailyEntry::updateOrCreate(
                ['lot_id' => $this->selectedLotId, 'entry_date' => $this->selectedDate],
                [
                    'achat' => $this->achat,
                    'ne' => $this->poussinsNes,
                    'mort' => $mort,
                    'vente' => $this->venteDuJour,
                    'don' => $don,
                    'effectif_final' => $effectifFinal,
                    'ponte_total' => $this->oeufsCouves,
                    // Ticket VOL-1 — MOUVEMENTS PAR CATÉGORIE persistés (ils rechargent le jour et alimentent la chaîne).
                    // Emplacements : `*_sevre` = Poussin, `*_jeune` = Jeune. Les ventes viennent de la caisse (lues, jamais
                    // saisies ici) : `vente` = leur somme.
                    'mort_repro' => $this->mortRepro, 'mort_sevre' => $this->mortPoussin, 'mort_jeune' => $this->mortPoulet,
                    'don_repro' => $this->donRepro, 'don_sevre' => $this->donPoussin, 'don_jeune' => $this->donPoulet,
                    'vente_repro' => $ventes['repro'], 'vente_sevre' => $ventes['sevre'], 'vente_jeune' => $ventes['jeune'],
                    'passage_sevre_jeune' => $this->passage,
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

            // Le DÉPART n'est écrit qu'UNE fois (verrouillé ensuite) ; les `cat_eff_*` ne sont jamais écrits ici : la chaîne
            // (cascade ci-dessous) les dérive.
            if ($departAEcrire) {
                $entree->fill([
                    'cat_depart_repro' => $this->departRepro,
                    'cat_depart_sevre' => $this->departSevre,
                    'cat_depart_jeune' => $this->departJeune,
                ])->save();
            }

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

        $this->purgerCalculs();

        // L'alerte d'autonomie alimentaire remonte à la cloche (ticket 14.40), sur la provende des TROIS catégories.
        $provende = $this->feedAutonomy;
        if (($provende['available'] ?? false) && ! empty($provende['product']) && empty($provende['inconnu'])) {
            app(RaiseFeedAutonomyAlertAction::class)->execute($provende['product'], (float) $this->rationnement['total_kg']);
        }

        AuditLog::record('livestock_daily_entry.saved', 'elevage');
        $this->dispatch('toast', message: 'Jour enregistré avec succès.', type: 'success');
    }

    /**
     * Ticket VOL-1 — RATIONNEMENT PAR CATÉGORIE : effectif calculé de chaque catégorie × la ration de sa ligne du barème
     * de l'aviculture (clés stables `CategorieVolaille`), même tableau que le poste. Tant que le départ n'est pas valide,
     * les effectifs sont indisponibles (`null`) et le total aussi — la vue ne montre alors que la demande de départ.
     */
    public function getRationnementProperty(): array
    {
        $cat = $this->categoriesJour;

        return CategorieVolaille::tableauReproducteurs(
            FeedRationStandard::where('species_code', 'aviculture')->get(),
            ['repro' => $cat['repro'], 'sevre' => $cat['sevre'], 'jeune' => $cat['jeune']],
        );
    }

    /** Autonomie alimentaire de la filière sur la provende du jour (SOMME des trois catégories). */
    public function getFeedAutonomyProperty(): ?array
    {
        $service = app(AutonomieAlimentaireService::class);

        return $service->evaluer($service->produitProvende('aviculture'), $this->rationnement['total_kg']);
    }

    public function render()
    {
        return view('livewire.elevage.fiche-reproducteurs', ['title' => 'Élevage > Fiches Volailles Reproducteurs']);
    }
}
