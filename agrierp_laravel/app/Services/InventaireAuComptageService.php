<?php

namespace App\Services;

use App\Livewire\Stocks\GestionStocks;
use App\Models\Product;
use App\Models\StockMovement;
use Carbon\Carbon;
use Carbon\CarbonInterface;

/**
 * Ticket S-T10 — L'ÉCART D'UN INVENTAIRE SAISI AU POSTE EST CALCULÉ PAR LE SERVEUR, À L'INSTANT DU COMPTAGE.
 *
 * ⚠️⚠️ LE DÉFAUT CORRIGÉ. Le poste envoyait son inventaire sous forme d'ÉCART contre SON stock local, et le serveur
 * l'appliquait tel quel. Une vente faite ailleurs (au web, ou sur une autre caisse) et pas encore descendue au poste
 * laissait ce stock local trop haut : le poste constatait un « manquant » qui n'était que cette vente, et le serveur,
 * qui l'avait déjà décomptée, la retirait une seconde fois — sans erreur. Le stock finissait faux, et une perte
 * fictive passait au journal (657).
 *
 * RÈGLE MAÎTRE — LE WEB (`GestionStocks::validateAdjustment`, doctrine article 5) : écart = quantité comptée − stock
 * courant DU SERVEUR. Ici, le comptage a eu lieu à l'instant T, peut-être hors ligne, et arrive plus tard ; le stock
 * du serveur À CET INSTANT se lit dans son grand livre : stock courant − mouvements datés APRÈS T. D'où :
 *
 *     écart = quantité comptée − (stock courant − Σ mouvements de ce produit datés après T)
 *
 * Rejoué à T par `AdjustStockAction`, il ramène le stock à T sur le comptage, et chaque mouvement postérieur reste
 * compté UNE fois par-dessus : stock final = quantité comptée + Σ mouvements après T. Quand le comptage arrive à
 * l'instant même où il est fait (T = maintenant, aucun mouvement après T), c'est exactement la formule du web.
 *
 * ⚠️ UN COMPTAGE DÉPASSÉ N'A PLUS D'EFFET. Si un autre inventaire du même produit (web ou poste) est daté après T, ce
 * comptage-là a été remplacé par un plus récent, qui reflétait déjà tout : l'appliquer par-dessus fausserait le stock
 * du second. Le serveur l'acquitte sans mouvement (et le journalise).
 *
 * ⚠️ Un mouvement daté du seul JOUR du comptage (minuit pile) est placé par son heure d'enregistrement (voir
 * `apresLeComptage`).
 *
 * Limite connue, dite : un mouvement fait AVANT T mais arrivé au serveur APRÈS ce comptage (vente d'une caisse restée
 * hors ligne plus longtemps que le poste qui compte) est encore compté en plus du comptage, qui le reflétait déjà.
 */
class InventaireAuComptageService
{
    /**
     * L'instant du comptage tel que le poste l'envoie (ISO 8601 avec son fuseau), ramené à l'heure MURALE du serveur
     * (`app.timezone`, Africa/Porto-Novo) — celle de `stock_movements.movement_date` — et jamais dans le futur (une
     * horloge de poste en avance daterait le comptage après des ventes qui l'ont suivi).
     *
     * ⚠️ Eloquent écrit et compare une date dans SON fuseau : un instant laissé en UTC serait stocké et comparé une
     * heure trop tôt.
     */
    public function instantDuComptage(string $brut): Carbon
    {
        $instant = Carbon::parse($brut)->setTimezone(config('app.timezone'));

        return $instant->greaterThan(now()) ? now() : $instant;
    }

    /**
     * @return array{stock_au_comptage: float, ecart: float, depasse: bool, posterieurs: int}
     */
    public function evaluer(Product $produit, float $quantiteComptee, CarbonInterface $instant): array
    {
        $instant = Carbon::instance($instant)->setTimezone(config('app.timezone'));

        // Candidats : tout ce qui est daté du JOUR du comptage ou après (un mouvement d'un jour antérieur le précède).
        $posterieurs = StockMovement::query()
            ->where('product_id', $produit->id)
            ->where('movement_date', '>=', $instant->copy()->startOfDay()->format('Y-m-d H:i:s'))
            ->get(['type', 'quantity', 'reference_type', 'movement_date', 'created_at'])
            ->filter(fn (StockMovement $m) => $this->apresLeComptage($m, $instant))
            ->values();

        // Seuls `entree` et `sortie` déplacent `stock_qty` (`AdjustStockAction`) ; un autre type n'y a jamais touché.
        $net = $posterieurs->sum(fn (StockMovement $m) => match ($m->type) {
            'entree' => (float) $m->quantity,
            'sortie' => -(float) $m->quantity,
            default => 0.0,
        });

        $stockAuComptage = round((float) $produit->stock_qty - $net, 2);

        return [
            'stock_au_comptage' => $stockAuComptage,
            'ecart' => round($quantiteComptee - $stockAuComptage, 2),
            'depasse' => $posterieurs->contains(
                fn (StockMovement $m) => in_array($m->reference_type, GestionStocks::TYPES_ECART_INVENTAIRE, true)
            ),
            'posterieurs' => $posterieurs->count(),
        ];
    }

    /**
     * Le mouvement [$m] a-t-il eu lieu APRÈS le comptage ?
     *
     * Par sa date de mouvement, à la seconde : une vente (`sold_at`), un inventaire, une réception. ⚠️ Sauf un
     * mouvement daté du seul JOUR (minuit pile : « Ajouter Stock » au jour choisi, ponte d'une fiche) le jour même du
     * comptage : sa date ne dit pas l'heure. Un ajout de 30 sacs saisi à 14 h, daté du jour, ne précède pas un
     * comptage de 10 h — le compter avant ferait perdre ces 30 sacs. Il est alors placé par son heure
     * d'ENREGISTREMENT (`created_at`).
     */
    private function apresLeComptage(StockMovement $m, Carbon $instant): bool
    {
        $date = $m->movement_date;
        if ($date === null) {
            return false;
        }
        if ($date->greaterThan($instant)) {
            return true;
        }
        $jourSeul = $date->format('H:i:s') === '00:00:00' && $date->isSameDay($instant);

        return $jourSeul && $m->created_at !== null && $m->created_at->greaterThan($instant);
    }
}
