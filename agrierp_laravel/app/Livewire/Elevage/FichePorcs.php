<?php

namespace App\Livewire\Elevage;

use App\Actions\RaiseFeedAutonomyAlertAction;
use App\Actions\RecordSaleOnFicheElevageAction;
use App\Actions\SyncLotProductionStockAction;
use App\Livewire\Elevage\Concerns\AvecDepartAutomatique;
use App\Livewire\Elevage\Concerns\AvecProphylaxieDuJour;
use App\Livewire\Elevage\Concerns\AvecSoinsDuMois;
use App\Models\AuditLog;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Services\AutonomieAlimentaireService;
use App\Services\EffectifParCategorieService;
use App\Support\CategorieRationPorc;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 3.8 (Sprint 3) — fiche-porcs.html → Livewire\Elevage\FichePorcs
 * Poids Général en Kg — seule fiche à cette échelle (Lapins/Volailles sont
 * en grammes), confirmé par lecture directe (lignes 346-436).
 *
 * `weight_sample_avg_g` reste la colonne de stockage (grammes, cohérence
 * de schéma inter-fiches) — la saisie et l'affichage se font en Kg pour
 * cette fiche uniquement, convertis en grammes juste avant la sauvegarde
 * (Kg × 1000), jamais une colonne séparée pour un simple changement d'unité
 * d'affichage.
 *
 * 🔁 TICKET 15.35 — La section « Suivi Clinique & Prophylaxie » est câblée sur
 * le moteur de prophylaxie (barème `prophylaxis_schedule_standards`, règle du
 * jour de cycle partagée avec `DailyProphylaxyReminderJob` dans
 * `ProtocoleDuJourService`, validation = soin + rémanence) : voir le trait
 * `AvecProphylaxieDuJour`. Elle affichait auparavant un marqueur « ticket 3.11 »
 * périmé. Le calendrier Gantt `veterinary_calendar_events` n'est PAS utilisé.
 *
 * Réutilisation des colonnes de ventilation d'effectif (`effectif_m/f/
 * sevres/smeres`, ajoutées au ticket 3.5 pour Lapins) avec un sens
 * différent ici, confirmé par lecture directe du tableau mensuel réel
 * (lignes 442-449) : M→Verrats, F→Truies Gestantes, Sevrés→Porcelets,
 * S/Mères→Engraissement. Même structure de colonnes, libellés adaptés par
 * espèce — pas une nouvelle migration pour un simple renommage contextuel.
 * Ces quatre champs RESTENT SAISIS (décision client QC5, 14/10/2026).
 *
 * 🔁 TICKET 15.42 — EFFECTIF AUTOMATIQUE PAR CATÉGORIE (miroir de 15.41 pour les lapins ; plan et décisions client
 * des 14-15/10/2026) : les trois effectifs Reproducteur / Porcelet / Porc Marchand sont CALCULÉS (champs `disabled`,
 * en direct) par `EffectifParCategorieService::calculerJour` depuis un effectif de DÉPART saisi une seule fois (D4, puis
 * verrouillé) et les mouvements PAR CATÉGORIE persistés (`mort_*`, `don_*`, `passage_sevre_jeune`). Règles porcs :
 * Reproducteur = veille + ACHATS − morts − dons (D11 : l'achat gonfle le Reproducteur, comme la maquette ; le web
 * l'ignorait) ; Porcelet = veille + nés − morts − dons − passage ; Porc Marchand = veille − ventes − morts − dons +
 * passage ; passage de stade = transfert Porcelet → Porc Marchand (D3), total inchangé, refusé s'il dépasse le
 * Porcelet APRÈS ses autres mouvements du jour. Bande sans chaîne : « — » (jamais 0, plus de répartition de
 * démonstration du premier jour). Corrige les défauts lus le 14/10 : (a) `loadDay()` d'un jour existant ne
 * rechargeait pas morts / dons ; (b) changer la date ne chargeait pas le jour ; (c) la veille et les requêtes
 * portaient sur TOUTES les bandes de l'espèce alors que l'enregistrement écrivait sur `lots->first()` — la fiche
 * travaille désormais sur LA bande choisie (`bandeId`). D6 : une bande déjà saisie à la main n'est jamais migrée
 * automatiquement (signalée, départ à saisir). D8 / D9 / D12 : avertissement daté somme ≠ total, morts > veille =
 * plancher + avertissement, jours antérieurs au départ « — ».
 *
 * ⚠️ D15 (décision client à confirmer) : la maquette dit « Porc Marchand », le barème dit « Jeune porc ». L'écran
 * affiche le libellé de la maquette ; la donnée du barème N'EST PAS renommée. Le rapprochement des rations passe par
 * la CLÉ STABLE de `App\Support\CategorieRationPorc` (et non plus par fragment de libellé sensible à la casse, qui
 * retombait en silence sur 2 000 / 300 / 600).
 *
 * Emplacements génériques (14.12) : `repro` = Reproducteur ; `sevre` = Porcelet ; `jeune` = Porc Marchand.
 * Colonnes de synchronisation INCHANGÉES : `cat_eff_sevre` = Porcelet, `cat_eff_jeune` = Porc Marchand.
 *
 * 🔴→✅ MISE À JOUR TICKET 14.12 (SUPERSÉDÉE EN PARTIE PAR 15.42 : les `catEff*` ne sont plus des saisies) — le
 * Reproducteur était automatique, Porcelet et Jeune restaient saisis à la main. Les colonnes `cat_eff_repro` /
 * `cat_eff_sevre` / `cat_eff_jeune` existent (migration 2026_08_16_000003) et sont désormais DÉRIVÉES par la chaîne.
 */
#[Layout('layouts.app')]
class FichePorcs extends Component
{
    use AvecDepartAutomatique;
    use AvecProphylaxieDuJour;
    use AvecSoinsDuMois;

    public string $selectedDate;

    public int $achat = 0;

    public int $ne = 0;

    public int $mortRepro = 0;

    public int $mortMarchand = 0;

    public int $mortPorcelet = 0;

    public int $donRepro = 0;

    public int $donMarchand = 0;

    public int $donPorcelet = 0;

    public int $effectifVerrats = 0;

    public int $effectifTruies = 0;

    public int $effectifPorcelets = 0;

    public int $effectifEngraissement = 0;

    /**
     * Ticket 15.42 — PASSAGE DE STADE du jour (Porcelet → Porc Marchand), décision client QC3/D3 du 14-15/10/2026 :
     * un FAIT saisi (nombre de sujets qui changent de stade ce jour), jamais un effectif. HORS MAQUETTE, assumé.
     */
    public int $passage = 0;

    /**
     * Ticket 15.42 — EFFECTIF DE DÉPART par catégorie (D4 : effectif au DÉBUT du jour). Saisi UNE seule fois,
     * sur une bande SANS chaîne, puis verrouillé (aucun déverrouillage : D5 non tranché). Emplacements
     * génériques : `departSevre` = Porcelet, `departJeune` = Porc Marchand.
     */
    public ?int $departRepro = null;

    public ?int $departSevre = null;

    public ?int $departJeune = null;

    /**
     * Ticket 15.42 — LA bande de la fiche (identifiant). `null` = la première bande active. Toutes les requêtes
     * (veille, jour chargé, ventes, tableau mensuel, enregistrement) portent sur cette bande et pas sur
     * « toutes les bandes de l'espèce » (défaut (c) du plan du 14/10/2026).
     */
    public ?string $bandeId = null;

    /**
     * Ticket 15.42 — totaux de morts / dons d'une fiche ANCIENNE non ventilée (colonnes `mort_*` / `don_*` à
     * null) rechargée dans le formulaire : on ne peut pas deviner la catégorie, mais on ne doit pas non plus
     * remettre ces morts à zéro en silence au prochain enregistrement.
     */
    public ?int $mortAncienTotal = null;

    public ?int $donAncienTotal = null;

    public ?float $peseeTotalKg = null;

    public string $observations = '';

    public function mount(): void
    {
        $this->selectedDate = now()->format('Y-m-d');
        // Un jour déjà saisi (vente du POS, enregistrement précédent) s'ouvre avec ses valeurs, jamais à zéro.
        $this->loadDay($this->selectedDate);
    }

    /** Défaut (b) du plan : changer la date charge le jour choisi (le tableau mensuel le faisait déjà). */
    public function updatedSelectedDate(): void
    {
        $this->loadDay($this->selectedDate);
    }

    /** Changer de bande recharge le jour affiché pour la nouvelle bande. */
    public function updatedBandeId(): void
    {
        $this->loadDay($this->selectedDate);
    }

    private function speciesCode(): string
    {
        return 'porciculture';
    }

    public function getLotsProperty()
    {
        return LivestockLot::whereHas('species', fn ($q) => $q->where('code', $this->speciesCode()))
            ->where('status', 'actif')
            ->where('is_active', true)
            ->get();
    }

    public function getKpisProperty(): array
    {
        $lots = $this->lots;
        $lotIds = $lots->pluck('id');

        $latestPerLot = LivestockDailyEntry::whereIn('lot_id', $lotIds)
            ->orderBy('entry_date')
            ->get()
            ->groupBy('lot_id')
            ->map(fn ($group) => $group->last());

        $monthEntries = LivestockDailyEntry::whereIn('lot_id', $lotIds)
            ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
            ->get();

        $totalMorts = $monthEntries->sum('mort');
        $totalEffectifDepart = $monthEntries->sum(fn ($e) => $e->previousEffectif());

        return [
            'effectif_total' => (int) $lots->sum('current_quantity'),
            'truies' => (int) $latestPerLot->sum('effectif_f'),
            'verrats' => (int) $latestPerLot->sum('effectif_m'),
            'porcelets_sous_mere' => (int) $latestPerLot->sum('effectif_sevres'),
            'taux_mortalite_mois' => $totalEffectifDepart > 0 ? round(($totalMorts / $totalEffectifDepart) * 100, 1) : 0.0,
        ];
    }

    /**
     * Ticket 15.42 — LA bande de la fiche : celle choisie (`bandeId`) si elle est encore active, sinon la première.
     * `lots->first()` ne décide plus seul : il n'est que le choix par défaut.
     */
    public function getBandeProperty(): ?LivestockLot
    {
        $lots = $this->lots;

        return ($this->bandeId !== null ? $lots->firstWhere('id', $this->bandeId) : null) ?? $lots->first();
    }

    protected function bandeDeLaFiche()
    {
        return $this->bande;
    }

    /** Fiches du mois courant de LA bande de la fiche, par date (le tableau mensuel est celui d'une bande). */
    /** Bandes du tableau mensuel (AvecSoinsDuMois). */
    protected function lotsDuTableauMensuel(): array
    {
        return [$this->bande?->id];
    }

    public function getMonthlyEntriesProperty()
    {
        $bande = $this->bande;

        if (! $bande) {
            return collect();
        }

        // Ticket audit fidélité : eager-load treatmentProduct — colonne
        // "Traitements & Prophylaxie" du prototype, trouvée manquante du
        // tableau mensuel (même écart que fiche-lapins.html), corrigée
        // dans la foulée pour les 3 fiches partageant ce même patron.
        return LivestockDailyEntry::where('lot_id', $bande->id)
            ->whereBetween('entry_date', [now()->startOfMonth(), now()->endOfMonth()])
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
            'Fiche Porcs — Suivi Mensuel',
            now()->translatedFormat('F Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'fiche-'.now()->format('Y-m').'.pdf');
    }

    public function getDaysInMonthProperty(): array
    {
        return range(1, now()->daysInMonth);
    }

    public function getRationStandardsProperty()
    {
        return FeedRationStandard::where('species_code', $this->speciesCode())->get();
    }

    /**
     * 🔁 TICKET 15.42 — EFFECTIFS PAR CATÉGORIE : CALCULÉS, PLUS SAISIS (plan du 14/10/2026, décisions D1-D12).
     *
     * Les trois effectifs (Reproducteur / Porcelet / Porc Marchand) ne sont plus des champs de saisie : ils sont
     * DÉRIVÉS, en direct, des achats, nés, morts et dons PAR CATÉGORIE, du passage de stade et des ventes, par
     * `EffectifParCategorieService::calculerJour` — aucune formule n'est recopiée ici ni dans la vue. Le serveur
     * (`recalculerChaine`) en réécrit ensuite la valeur stockée à chaque enregistrement.
     *
     * ⚠️ `null` = INCONNU, jamais 0 (affiché « — ») : bande sans chaîne, jour antérieur au départ (D12), départ
     * stocké incohérent, mouvement ancien non ventilé. Aucun pourcentage de démonstration n'est plus appliqué
     * au premier jour (la maquette répartit un effectif de démonstration entre les trois catégories).
     *
     * Emplacements génériques : `repro` = Reproducteur ; `sevre` = Porcelet ; `jeune` = Porc Marchand.
     *
     * @return array{mode: string, repro: ?int, sevre: ?int, jeune: ?int, resultat: ?\App\Support\EffectifCategoriesJour, motif: ?string, refus_passage: ?string, avertissements: list<string>, depart_requis: bool, depart_date: ?string, depart: ?array, ancien: ?array}
     */
    public function getCategoriesJourProperty(): array
    {
        // Livewire met déjà en cache les propriétés calculées pour la durée d'UNE requête : pas de mémo ici.
        // `saveDay` purge ce cache après écriture (voir `purgerCalculs`).
        return $this->calculerCategoriesJour();
    }

    /**
     * Livewire garde chaque propriété calculée en cache pour toute la requête : après une écriture, l'écran rendu
     * dans la MÊME requête afficherait l'état d'avant (départ encore saisissable, tableau mensuel sans le jour).
     */
    private function purgerCalculs(): void
    {
        unset($this->lots, $this->bande, $this->categoriesJour, $this->previousEffectif, $this->venteDuJour,
            $this->effectifFinalCalc, $this->provendeCalculation, $this->feedAutonomy, $this->monthlyEntries, $this->kpis);
    }

    private function calculerCategoriesJour(): array
    {
        $sortie = [
            'mode' => 'sans_chaine', 'repro' => null, 'sevre' => null, 'jeune' => null, 'resultat' => null,
            'motif' => null, 'refus_passage' => null, 'avertissements' => [], 'depart_requis' => false,
            'depart_date' => null, 'depart' => null, 'ancien' => null,
        ];

        $bande = $this->bande;
        if (! $bande || ! $this->dateValide($this->selectedDate)) {
            return $sortie;
        }

        $service = app(EffectifParCategorieService::class);
        $etat = $service->etatPourJour($bande->loadMissing('species'), $this->selectedDate);
        $sortie['mode'] = $etat['mode'];
        $sortie['depart_date'] = $etat['depart_date'];
        $sortie['depart'] = $etat['depart'];
        $sortie['motif'] = $etat['refus'];

        $veille = $etat['veille'];

        if ($etat['mode'] === 'sans_chaine') {
            $sortie['depart_requis'] = true;
            $sortie['ancien'] = $service->teteImplicite($bande->id);   // D6 : signalé, jamais écrit
            $saisi = ['repro' => $this->departRepro, 'sevre' => $this->departSevre, 'jeune' => $this->departJeune];

            if (in_array(null, $saisi, true)) {
                // Départ à saisir : catégories inconnues. Saisie PARTIELLE : le motif « incomplet » est dit.
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
        }

        if ($veille === null) {
            return $sortie;       // avant le départ (D12) ou départ stocké refusé
        }

        $resultat = EffectifParCategorieService::calculerJour(EffectifParCategorieService::PORCS, $veille, [
            'achat' => $this->achat, 'ne' => $this->ne, 'vente' => $this->venteDuJour,
            // Emplacements : Porcelet = `sevre` ; Porc Marchand = `jeune`.
            'mort_repro' => $this->mortRepro, 'mort_sevre' => $this->mortPorcelet, 'mort_jeune' => $this->mortMarchand,
            'don_repro' => $this->donRepro, 'don_sevre' => $this->donPorcelet, 'don_jeune' => $this->donMarchand,
            'passage' => $this->passage,
        ], $this->effectifFinalCalc);

        $sortie['resultat'] = $resultat;
        $sortie['repro'] = $resultat->repro;
        $sortie['sevre'] = $resultat->sevre;
        $sortie['jeune'] = $resultat->jeune;
        $sortie['refus_passage'] = $resultat->refus;

        // D8 : avertissement DATÉ (hors maquette, assumé), jamais un blocage.
        if ($resultat->sommeDifferente === true) {
            $sortie['avertissements'][] = 'Avertissement (hors maquette) — fiche du '.Carbon::parse($this->selectedDate)->format('d/m/Y')
                .' : la somme des catégories ('.$resultat->somme().') diffère de l\'effectif total ('.$this->effectifFinalCalc
                .'). Un effectif de catégorie ne descend jamais sous 0 : vérifiez les ventes, morts et dons saisis.';
        }

        return $sortie;
    }

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
     * D9 : des morts supérieurs à l'effectif de la veille ne bloquent plus (la maquette bloquait) — le plancher à 0
     * s'applique et l'écran le dit.
     */
    public function getAvertissementMortsProperty(): ?string
    {
        $morts = $this->mortRepro + $this->mortMarchand + $this->mortPorcelet;

        return $morts > $this->previousEffectif
            ? "Morts du jour ({$morts}) supérieurs à l'effectif de la veille ({$this->previousEffectif}) : l'effectif est ramené à 0, vérifiez la saisie."
            : null;
    }

    /**
     * Provende théorique du jour (g), 3 catégories.
     *
     * Ticket 15.42 : l'effectif de chaque ligne VIENT des effectifs de catégorie ci-dessus (Reproducteur / Porcelet /
     * Porc Marchand). Une catégorie inconnue donne une ligne « — » et un total inconnu : jamais une provende
     * partielle présentée comme complète. La ration reste celle du barème, rapprochée par CLÉ STABLE
     * (`CategorieRationPorc`) — plus par fragment de libellé avec valeurs de secours silencieuses.
     */
    public function getProvendeCalculationProperty(): array
    {
        $rations = $this->rationStandards;
        $rPorcelet = CategorieRationPorc::ration($rations, CategorieRationPorc::PORCELET);
        $rJeune = CategorieRationPorc::ration($rations, CategorieRationPorc::MARCHAND);
        $rRepro = CategorieRationPorc::ration($rations, CategorieRationPorc::REPRODUCTEUR);

        $cat = $this->categoriesJour;
        // Colonnes de synchro INCHANGÉES : cat_eff_sevre = Porcelet, cat_eff_jeune = Porc Marchand.
        $ligne = fn (?int $effectif, int $ration): array => [
            'ration' => $ration, 'effectif' => $effectif, 'total_g' => $effectif === null ? null : $effectif * $ration,
        ];
        $porcelet = $ligne($cat['sevre'], $rPorcelet);
        $jeune = $ligne($cat['jeune'], $rJeune);
        $repro = $ligne($cat['repro'], $rRepro);

        $inconnu = $porcelet['total_g'] === null || $jeune['total_g'] === null || $repro['total_g'] === null;
        $total = $inconnu ? null : $porcelet['total_g'] + $jeune['total_g'] + $repro['total_g'];

        return [
            'porcelet' => $porcelet,
            'jeune' => $jeune,
            'repro' => $repro,
            'total_g' => $total,
            'total_kg' => $total === null ? null : round($total / 1000, 2),
        ];
    }

    /** Autonomie alimentaire de la filière sur la provende du jour affiché — calcul commun (AutonomieAlimentaireService). */
    public function getFeedAutonomyProperty(): ?array
    {
        $service = app(AutonomieAlimentaireService::class);

        return $service->evaluer($service->produitProvende($this->speciesCode()), $this->provendeCalculation['total_kg']);
    }

    /**
     * Effectif de la veille de LA bande de la fiche (ticket 15.42, défaut (c)) : dernière fiche ANTÉRIEURE de cette
     * bande, sinon son effectif initial. Avant : la dernière fiche de TOUTES les bandes de l'espèce, ou la somme des
     * effectifs initiaux de toutes les bandes — alors que l'enregistrement écrivait sur la première bande seule.
     * Même règle que `LivestockDailyEntry::previousEffectif()` (un seul point de vérité).
     */
    public function getPreviousEffectifProperty(): int
    {
        $bande = $this->bande;

        if (! $bande || ! $this->dateValide($this->selectedDate)) {
            return 0;
        }

        return (new LivestockDailyEntry(['lot_id' => $bande->id, 'entry_date' => $this->selectedDate]))->previousEffectif();
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

        if (! $lot || ! $this->dateValide($this->selectedDate)) {
            return 0;
        }

        return (int) (LivestockDailyEntry::where('lot_id', $lot->id)
            ->whereDate('entry_date', $this->selectedDate)
            ->value('vente') ?? 0);
    }

    public function getEffectifFinalCalcProperty(): int
    {
        $mort = $this->mortRepro + $this->mortMarchand + $this->mortPorcelet;
        $don = $this->donRepro + $this->donMarchand + $this->donPorcelet;

        return LivestockDailyEntry::computeEffectifFinal($this->previousEffectif, $this->achat, $this->ne, $mort, $this->venteDuJour, $don);
    }

    public function getMortalityRateCalcProperty(): float
    {
        $mort = $this->mortRepro + $this->mortMarchand + $this->mortPorcelet;

        return $this->previousEffectif > 0 ? round(($mort / $this->previousEffectif) * 100, 1) : 0.0;
    }

    public function loadDay(string $date): void
    {
        // Ticket 15.42 : une date vide ou invalide (champ date vidé) ne casse pas la fiche — retour au jour courant.
        $this->selectedDate = $this->dateValide($date) ? $date : now()->format('Y-m-d');
        $date = $this->selectedDate;
        // Ticket 15.35 : un cochage de prophylaxie ne survit pas au changement de jour.
        $this->traitementsCoches = [];
        // Le départ saisi (aperçu) est propre à un jour : il ne survit pas à un changement de jour.
        $this->reset(['departRepro', 'departSevre', 'departJeune', 'mortAncienTotal', 'donAncienTotal']);
        $this->preremplirDepartDepuisStade();

        // Ticket 15.42 : la fiche de LA bande à CETTE date, quel que soit le mois (le tableau mensuel ne couvre que
        // le mois courant) — jamais la fiche d'une autre bande.
        $bande = $this->bande;
        $entry = $bande
            ? LivestockDailyEntry::where('lot_id', $bande->id)->whereDate('entry_date', $date)->first()
            : null;

        if ($entry) {
            $this->achat = $entry->achat;
            $this->ne = $entry->ne;
            // 🔴→✅ TICKET 15.42 — DÉFAUT (a) : les compteurs de morts, de dons et le passage de stade étaient
            // laissés à leur valeur précédente à l'ouverture d'un jour existant, puis réécrits tels quels
            // (`mort` / `don` périmés) au réenregistrement. Ils sont rechargés depuis les colonnes PAR CATÉGORIE.
            // Emplacements : `mort_sevre` = Porcelet, `mort_jeune` = Porc Marchand.
            if ($entry->mort_repro !== null && $entry->mort_sevre !== null && $entry->mort_jeune !== null) {
                $this->mortRepro = (int) $entry->mort_repro;
                $this->mortPorcelet = (int) $entry->mort_sevre;
                $this->mortMarchand = (int) $entry->mort_jeune;
            } else {
                // Fiche ANCIENNE non ventilée : on ne devine pas la catégorie, on le dit (voir `saveDay`).
                $this->reset(['mortRepro', 'mortPorcelet', 'mortMarchand']);
                $this->mortAncienTotal = (int) $entry->mort > 0 ? (int) $entry->mort : null;
            }
            if ($entry->don_repro !== null && $entry->don_sevre !== null && $entry->don_jeune !== null) {
                $this->donRepro = (int) $entry->don_repro;
                $this->donPorcelet = (int) $entry->don_sevre;
                $this->donMarchand = (int) $entry->don_jeune;
            } else {
                $this->reset(['donRepro', 'donPorcelet', 'donMarchand']);
                $this->donAncienTotal = (int) ($entry->don ?? 0) > 0 ? (int) $entry->don : null;
            }
            $this->passage = (int) ($entry->passage_sevre_jeune ?? 0);
            $this->effectifVerrats = $entry->effectif_m ?? 0;
            $this->effectifTruies = $entry->effectif_f ?? 0;
            $this->effectifPorcelets = $entry->effectif_sevres ?? 0;
            $this->effectifEngraissement = $entry->effectif_smeres ?? 0;
            // 🔴→✅ TICKET 14.60 — ALLER-RETOUR DE LA PESEE CORRIGE.
            // `weight_sample_avg_g` stocke le poids MOYEN par sujet, en
            // grammes (voir `saveDay`). Le rechargement le remettait tel quel
            // — divise par 1000 — dans « Poids Général Pesé (Kg) », qui est un
            // TOTAL : 500 Kg peses sur 100 porcs revenaient a 5 Kg. Le total
            // se reconstitue en remultipliant par l'effectif de la fiche.
            $effectifFiche = (int) ($entry->effectif_final ?? 0);
            $this->peseeTotalKg = $entry->weight_sample_avg_g && $effectifFiche > 0
                ? round(($entry->weight_sample_avg_g * $effectifFiche) / 1000, 2)
                : null;
            // Ticket 15.42 : les effectifs par catégorie ne se rechargent plus — ils se CALCULENT
            // (`categoriesJour`). Plus de `catEff*` persistés puis rechargés comme saisie.
        } else {
            // Ticket 15.42 : un jour non encore saisi repart à zéro pour les MOUVEMENTS (ce sont des faits du jour) ;
            // les effectifs de catégorie, eux, se calculent depuis la veille de la chaîne — plus de reprise
            // manuelle du dernier jour connu, plus de répartition de démonstration.
            $this->reset(['achat', 'ne', 'mortRepro', 'mortMarchand', 'mortPorcelet', 'donRepro', 'donMarchand', 'donPorcelet', 'passage', 'effectifVerrats', 'effectifTruies', 'effectifPorcelets', 'effectifEngraissement', 'peseeTotalKg']);
        }
    }

    public function saveDay(): void
    {
        $this->authorize('manage-elevage');
        $lot = $this->bande;

        if (! $lot) {
            $this->dispatch('toast', message: "Aucune bande active en porciculture. Créez d'abord une bande.", type: 'error');

            return;
        }

        if (! $this->dateValide($this->selectedDate)) {
            $this->dispatch('toast', message: 'Date invalide : choisissez un jour.', type: 'error');

            return;
        }

        // --- Ticket 15.42 : contrôles AVANT toute écriture -------------------------------------------------
        $cat = $this->categoriesJour;

        // D3 : un passage de stade supérieur à la catégorie source ne s'enregistre pas.
        if ($cat['refus_passage'] !== null) {
            $this->dispatch('toast', message: $cat['refus_passage'], type: 'error');

            return;
        }

        // D4 : le départ saisi (bande sans chaîne) doit être complet et sa somme égale au total au début du jour.
        $departSaisi = ['repro' => $this->departRepro, 'sevre' => $this->departSevre, 'jeune' => $this->departJeune];
        $departAEcrire = false;
        if ($cat['mode'] === 'sans_chaine' && count(array_filter($departSaisi, fn ($v) => $v !== null)) > 0) {
            $refusDepart = EffectifParCategorieService::verifierDepart($departSaisi, $this->previousEffectif);
            if ($refusDepart !== null) {
                $this->dispatch('toast', message: $refusDepart, type: 'error');

                return;
            }
            $departAEcrire = true;
        }

        $mort = $this->mortRepro + $this->mortMarchand + $this->mortPorcelet;
        $don = $this->donRepro + $this->donMarchand + $this->donPorcelet;

        // Fiche ancienne non ventilée rechargée : ne pas remettre ses morts / dons à zéro en silence.
        if (($this->mortAncienTotal !== null && $mort === 0) || ($this->donAncienTotal !== null && $don === 0)) {
            $this->dispatch('toast', message: 'Cette fiche porte des morts ou des dons non ventilés par catégorie : ventilez-les (Reproducteur / Porc Marchand / Porcelet) avant d\'enregistrer.', type: 'error');

            return;
        }

        $effectifFinal = $this->effectifFinalCalc;

        // 🔴→✅ TICKET 14.37 — état AVANT enregistrement, pour n'appliquer
        // au stock que l'ÉCART. Une fiche se corrige : appliquer les
        // valeurs telles quelles compterait la production autant de fois
        // que la journée est sauvegardée.
        $ficheAvant = LivestockDailyEntry::where('lot_id', $lot->id)
            ->whereDate('entry_date', $this->selectedDate)
            ->first();

        $etatAvant = $ficheAvant
            ? ['ne' => (int) $ficheAvant->ne, 'mort' => (int) $ficheAvant->mort, 'don' => (int) ($ficheAvant->don ?? 0)]
            : [];

        // Provende du jour : inconnue (null) tant qu'une catégorie est inconnue — jamais 0.
        $donnees = [
            'achat' => $this->achat,
            'ne' => $this->ne,
            'mort' => $mort,
            'vente' => $this->venteDuJour,
            'don' => $don,
            'effectif_final' => $effectifFinal,
            'effectif_m' => $this->effectifVerrats,
            'effectif_f' => $this->effectifTruies,
            'effectif_sevres' => $this->effectifPorcelets,
            'effectif_smeres' => $this->effectifEngraissement,
            'feed_qty_kg' => $this->provendeCalculation['total_kg'],
            // Ticket 15.42 — MOUVEMENTS PAR CATÉGORIE persistés (ils rechargent le jour et alimentent la chaîne).
            // Emplacements : `*_sevre` = Porcelet, `*_jeune` = Porc Marchand.
            'mort_repro' => $this->mortRepro, 'mort_sevre' => $this->mortPorcelet, 'mort_jeune' => $this->mortMarchand,
            'don_repro' => $this->donRepro, 'don_sevre' => $this->donPorcelet, 'don_jeune' => $this->donMarchand,
            'passage_sevre_jeune' => $this->passage,
            'weight_sample_avg_g' => $this->peseeTotalKg && $effectifFinal > 0
                ? (int) round(($this->peseeTotalKg * 1000) / $effectifFinal)
                : null,
        ];

        // Ticket 15.42 — le DÉPART n'est écrit qu'UNE fois, sur une bande sans chaîne (D4), puis verrouillé (D5 non
        // tranché : aucun déverrouillage). Les `cat_eff_*` ne sont JAMAIS écrits ici : la chaîne (service) les
        // dérive après l'enregistrement ; sur une bande sans chaîne, les valeurs anciennes saisies à la main
        // (D6) restent intactes.
        if ($departAEcrire) {
            $donnees += [
                'cat_depart_repro' => $this->departRepro,
                'cat_depart_sevre' => $this->departSevre,
                'cat_depart_jeune' => $this->departJeune,
            ];
        }

        DB::transaction(function () use ($lot, $donnees, $etatAvant) {
            $entree = LivestockDailyEntry::updateOrCreate(
                ['lot_id' => $lot->id, 'entry_date' => $this->selectedDate],
                $donnees
            );

            // La production du cheptel entre réellement en stock — naissances
            // portées au crédit, mortalité et dons au débit. Sans bande
            // rattachée à un produit, l'Action ne fait rien.
            app(SyncLotProductionStockAction::class)->execute($entree, $etatAvant);

            // 🔴→✅ TICKET 15.42 — CASCADE (décision client 15.31, fiches déjà saisies après la date) : les effectifs
            // finaux des jours SUIVANTS, les catégories de la chaîne et l'effectif de la bande (`current_quantity` =
            // dernière fiche, et non l'effectif du jour édité) sont recalculés dans la même transaction. Le même
            // point d'entrée que la vente antidatée et le push des fiches.
            app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot->id, $this->selectedDate);
        });

        $this->purgerCalculs();

        // 🔴→✅ TICKET 14.40 — L'ALERTE VIENT CHERCHER L'ÉLEVEUR.
        //
        // Le calcul d'autonomie existait, mais uniquement affiché DANS la fiche
        // consultée : l'alerte n'était visible que si l'on ouvrait précisément
        // la bonne fiche, c'est-à-dire jamais au moment où elle est utile. Elle
        // remonte désormais à la cloche de notification, comme le montre le
        // prototype (« Stock aliment lapins bas »).
        $provende = $this->feedAutonomy;

        // Ticket 15.42 : provende inconnue (catégorie inconnue) → aucune alerte déclenchée sur un 0 inventé.
        if (($provende['available'] ?? false) && ! empty($provende['product']) && empty($provende['inconnu'])) {
            app(RaiseFeedAutonomyAlertAction::class)->execute(
                $provende['product'],
                (float) $this->provendeCalculation['total_kg'],
            );
        }

        AuditLog::record('livestock_daily_entry.saved', 'elevage');
        $this->dispatch('toast', message: 'Jour enregistré avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.elevage.fiche-porcs', ['title' => 'Élevage > Fiches Porcs']);
    }
}
