<?php

namespace App\Services;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockReproductionEvent;
use App\Models\Notification;
use App\Models\Product;
use App\Models\VeterinaryCalendarEvent;
use Illuminate\Support\Collection;

/**
 * Ticket 15.49 — ALERTES DE LA CLOCHE QUI N'ÉTAIENT JAMAIS ÉMISES.
 *
 * 🔴 La cloche ne recevait que l'autonomie de provende (fiches Lapins et Porcs), la prophylaxie du jour et la
 * vente sous délai d'attente. Le stock sous seuil, la mortalité anormale, les soins planifiés à venir ou en retard
 * et les échecs de reproduction (« Alertes Réforme / Pertes » du Suivi Reproduction) n'étaient qu'AFFICHÉS sur
 * leurs écrans : personne n'en était averti.
 *
 * ⚠️ AUCUN SEUIL INVENTÉ : chaque règle est celle que l'application affiche déjà.
 *  - stock : `stock_qty <= alert_threshold` (Seuils d'Alerte, badge « Urgence », tableau de bord) ;
 *  - mortalité : pire jour des 7 derniers jours ≥ 5 % (tableau de bord, règle de `gestion-elevage.html`, F0.32 ;
 *    la divergence de formule avec le cumul hebdomadaire reste un ARBITRAGE CLIENT ouvert) ;
 *  - soins : calendrier vétérinaire, événement « planifié » daté d'ici `JOURS_RAPPEL_SOINS` jours, ou dépassé ;
 *  - reproduction : cycle passé en « échec » (palpation négative), compté par l'indicateur « Alertes Réforme /
 *    Pertes ».
 * ⚠️ Une alerte n'est émise qu'UNE fois par objet et par jour (même `type` + même `link_url`), comme
 * `RaiseFeedAutonomyAlertAction` : relancer la tâche ne réempile rien.
 */
class AlertesElevageService
{
    public const SEUIL_MORTALITE_JOUR = 5.0;

    /**
     * Fenêtre du rappel des soins planifiés. ⚠️ Aucune durée n'est fixée par la maquette ni par la documentation :
     * 3 jours, comme le seuil d'autonomie de provende (`RaiseFeedAutonomyAlertAction::SEUIL_JOURS`), à confirmer
     * par l'exploitant (consigné au ticket 15.49).
     */
    public const JOURS_RAPPEL_SOINS = 3;

    /** @return Collection<int, Product> produits actifs au seuil d'alerte ou en dessous */
    public function produitsSousSeuil(): Collection
    {
        return Product::where('is_active', true)
            ->whereNotNull('alert_threshold')
            ->whereColumn('stock_qty', '<=', 'alert_threshold')
            ->orderBy('name')
            ->get();
    }

    /**
     * Pire jour des 7 derniers jours de chaque bande vivante, quand il atteint le seuil.
     *
     * @return Collection<int, LivestockDailyEntry>
     */
    public function mortalitesAnormales(): Collection
    {
        return LivestockDailyEntry::with('lot')
            ->whereDate('entry_date', '>=', now()->subDays(7)->toDateString())
            ->whereHas('lot', fn ($q) => $q->vivantes())
            ->get()
            ->groupBy('lot_id')
            ->map(fn ($fiches) => $fiches->sortByDesc(fn ($f) => $f->mortality_rate)->first())
            ->filter(fn ($pire) => $pire && $pire->mortality_rate >= self::SEUIL_MORTALITE_JOUR)
            ->values();
    }

    /** @return Collection<int, VeterinaryCalendarEvent> soins planifiés en retard ou d'ici la fenêtre de rappel */
    public function soinsAVenir(): Collection
    {
        return VeterinaryCalendarEvent::with('lot')
            ->where('status', 'planned')
            ->whereDate('scheduled_date', '<=', now()->addDays(self::JOURS_RAPPEL_SOINS)->toDateString())
            ->whereHas('lot', fn ($q) => $q->vivantes())
            ->orderBy('scheduled_date')
            ->get();
    }

    /** @return Collection<int, LivestockReproductionEvent> cycles en échec (palpation négative) des 30 derniers jours */
    public function echecsReproduction(): Collection
    {
        return LivestockReproductionEvent::where('status', 'echec')
            ->where('updated_at', '>=', now()->subDays(30))
            ->get();
    }

    /** Émet les alertes manquantes ; rend le nombre de notifications créées. */
    public function emettre(): int
    {
        $creees = 0;

        foreach ($this->produitsSousSeuil() as $produit) {
            $creees += $this->notifier([
                'target_role' => 'admin',
                'type' => 'stock_low',
                'severity' => (float) $produit->stock_qty <= 0 ? 'critique' : 'moyen',
                'title' => 'Stock sous le seuil — '.$produit->name,
                'message' => sprintf(
                    '%s %s en stock pour un seuil d\'alerte de %s.',
                    $this->nombre($produit->stock_qty), $produit->unit, $this->nombre($produit->alert_threshold),
                ),
                'icon' => 'inventory_2',
                'link_url' => '/seuils-alerte?produit='.$produit->id,
            ]);
        }

        foreach ($this->mortalitesAnormales() as $pire) {
            $creees += $this->notifier([
                'target_role' => 'animalier',
                'type' => 'high_mortality',
                'severity' => 'critique',
                'title' => 'Mortalité anormale — Bande '.$pire->lot->code,
                'message' => sprintf(
                    '%s %% de mortalité le %s (%d mort(s)), seuil d\'alerte %s %%.',
                    $this->nombre($pire->mortality_rate, 1), $pire->entry_date->format('d/m/Y'),
                    (int) $pire->mort, $this->nombre(self::SEUIL_MORTALITE_JOUR, 0),
                ),
                'icon' => 'health_and_safety',
                'link_url' => '/gestion-bandes?search='.$pire->lot->code,
            ]);
        }

        foreach ($this->soinsAVenir() as $soin) {
            $enRetard = $soin->scheduled_date->lt(today());
            $creees += $this->notifier([
                'target_role' => 'animalier',
                'type' => 'prophylaxis_due',
                'severity' => $enRetard ? 'critique' : 'moyen',
                'title' => ($enRetard ? 'Soin en retard — ' : 'Soin à venir — ').$soin->task_type,
                'message' => sprintf(
                    'Bande %s — planifié le %s.%s',
                    $soin->lot?->code ?? '—', $soin->scheduled_date->format('d/m/Y'),
                    $enRetard ? ' La date est dépassée : réalisez-le ou replanifiez-le.' : '',
                ),
                'icon' => 'vaccines',
                'link_url' => '/soins-vaccins-hub?evenement='.$soin->id,
            ]);
        }

        foreach ($this->echecsReproduction() as $cycle) {
            $creees += $this->notifier([
                'target_role' => 'animalier',
                'type' => 'reproduction_echec',
                'severity' => 'moyen',
                'title' => 'Échec de reproduction — '.($cycle->mother_ref ?: 'reproductrice'),
                'message' => 'Palpation négative'
                    .($cycle->palpation_date ? ' le '.$cycle->palpation_date->format('d/m/Y') : '')
                    .' : réforme ou nouvelle saillie à décider.',
                'icon' => 'warning',
                'link_url' => '/suivi-reproduction?cycle='.$cycle->id,
            ], unefois: true);
        }

        return $creees;
    }

    /**
     * Crée la notification sauf si la même (type + lien) existe déjà aujourd'hui — ou, avec `$unefois`, déjà
     * tout court (un échec de reproduction ne se signale qu'une fois).
     */
    private function notifier(array $donnees, bool $unefois = false): int
    {
        $deja = Notification::where('type', $donnees['type'])
            ->where('link_url', $donnees['link_url'])
            ->when(! $unefois, fn ($q) => $q->whereDate('created_at', now()->toDateString()))
            ->exists();

        if ($deja) {
            return 0;
        }

        Notification::create($donnees + ['is_read' => false]);

        return 1;
    }

    private function nombre(float|string|null $valeur, int $decimales = 2): string
    {
        $texte = number_format((float) $valeur, $decimales, ',', ' ');

        return $decimales > 0 ? rtrim(rtrim($texte, '0'), ',') : $texte;
    }
}
