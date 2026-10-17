<?php

namespace Database\Seeders\Demo;

use App\Models\ChartOfAccount;
use App\Models\CostCenter;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\TreasuryAccount;
use Carbon\CarbonImmutable;

/**
 * Ticket 14.31 (Sprint 14) — contexte partagé des seeders de démonstration.
 *
 * Regroupe la période simulée, le tirage pseudo-aléatoire et les recherches de
 * référentiel, pour que les 7 seeders de module racontent la MÊME histoire :
 * un achat de provende de mars doit être celui que consomment les fiches
 * d'élevage d'avril, et la vente qui décrémente le stock doit être celle qui
 * apparaît au Grand Livre.
 *
 * ⚠️ TIRAGE DÉTERMINISTE (`mt_srand`) : deux exécutions produisent exactement
 * les mêmes données. Sans cela, un chiffre constaté à l'écran ne serait pas
 * reproductible d'une base à l'autre, et aucune anomalie ne pourrait être
 * rejouée — un jeu de démonstration aléatoire ne se débogue pas.
 *
 * ⚠️ LA PÉRIODE TOMBE DANS L'EXERCICE OUVERT. `AccountingEntryService` refuse
 * toute écriture dont la date sort d'un exercice ouvert : une simulation
 * antidatée hors exercice ne produirait aucune écriture, et la comptabilité
 * de démonstration serait vide sans que rien ne le signale.
 */
class DemoContexte
{
    public CarbonImmutable $debut;

    public CarbonImmutable $fin;

    /** @var array<string, Product> */
    private array $produits = [];

    /** @var array<string, LivestockSpecies> */
    private array $especes = [];

    public function __construct()
    {
        // Graine fixe : la simulation est rejouable à l'identique.
        mt_srand(2026);

        $this->fin = CarbonImmutable::parse(now()->format('Y-m-d'));
        $this->debut = $this->fin->subMonths(5)->startOfMonth();
    }

    /** Entier pseudo-aléatoire déterministe. */
    public function entre(int $min, int $max): int
    {
        return $min + (mt_rand() % max(1, $max - $min + 1));
    }

    /** Vrai avec une probabilité donnée, en pourcentage. */
    public function chance(int $pourcent): bool
    {
        return $this->entre(1, 100) <= $pourcent;
    }

    /** @template T */
    public function parmi(array $valeurs)
    {
        return $valeurs[$this->entre(0, count($valeurs) - 1)];
    }

    public function produit(string $sku): Product
    {
        return $this->produits[$sku] ??= Product::where('sku', $sku)->firstOrFail();
    }

    public function espece(string $code): LivestockSpecies
    {
        return $this->especes[$code] ??= LivestockSpecies::where('code', $code)->firstOrFail();
    }

    public function centreDeCout(string $label): ?CostCenter
    {
        return CostCenter::where('label', $label)->first();
    }

    public function tresorerie(string $code): ?TreasuryAccount
    {
        return TreasuryAccount::where('account_code', $code)->first();
    }

    /**
     * Compte de trésorerie capable de couvrir ce montant, le mieux pourvu
     * d'abord.
     *
     * ⚠️ UN GÉRANT NE PAIE PAS DEPUIS UN COMPTE À DÉCOUVERT. Retenir
     * simplement « le compte le plus riche » suffisait tant que les montants
     * restaient petits, puis un règlement de 1,6 M mettait le Mobile Money en
     * négatif. On retient donc le premier compte SOLVABLE ; à défaut, le mieux
     * pourvu — et le découvert qui en résulterait serait alors un vrai
     * signal, non un artefact d'allocation.
     *
     * 🔴 Rappel du gap réel : sans VIREMENT INTERNE entre comptes, aucune
     * règle d'allocation ne peut garantir la solvabilité de chacun.
     */
    public function compteSolvable(float $montant): ?TreasuryAccount
    {
        $comptes = TreasuryAccount::where('is_active', true)->orderByDesc('balance')->orderBy('account_code')->get();

        return $comptes->first(fn ($c) => (float) $c->balance >= $montant) ?? $comptes->first();
    }

    public function compte(string $code): ?ChartOfAccount
    {
        return ChartOfAccount::where('code', $code)->first();
    }

    /** Chaque jour ouvré de la période — les fiches d'élevage, elles, sont quotidiennes. */
    public function jours(?CarbonImmutable $depuis = null): \Generator
    {
        for ($j = $depuis ?? $this->debut; $j->lte($this->fin); $j = $j->addDay()) {
            yield $j;
        }
    }
}
