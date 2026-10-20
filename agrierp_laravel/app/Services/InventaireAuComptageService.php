<?php

namespace App\Services;

use App\Actions\AdjustStockAction;
use App\Actions\RecordStockAdjustmentEntryAction;
use App\Livewire\Stocks\GestionStocks;
use App\Models\AuditLog;
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
 * 🔴→✅ TICKET S-T12 — LE MOUVEMENT ANTÉRIEUR AU COMPTAGE QUI ARRIVE APRÈS LUI (`compenserMouvementAnterieur`). Une
 * vente faite AVANT T sur une caisse restée hors ligne plus longtemps que le poste qui compte (ou un achat, ou une
 * vente antidatée saisie au web après un inventaire — 15.30) était décomptée EN PLUS du comptage, qui la reflétait
 * déjà : les rayons comptés à T ne contenaient plus la marchandise vendue avant T. Le stock finissait trop bas (ou
 * trop haut pour un achat), sans erreur. Règle : le mouvement est enregistré à SA date métier (grand livre, rotation,
 * fiche), puis une RÉGULARISATION d'inventaire de sens opposé est écrite à l'instant du premier comptage qui le suit —
 * c'est l'écart de ce comptage, recalculé avec ce que l'on sait maintenant. Effet net après T : nul. Voir la méthode.
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
     * Ticket S-T12 — LE MOUVEMENT [$mouvement], DATÉ AVANT UN COMPTAGE DÉJÀ ENREGISTRÉ, NE CHANGE PLUS LE STOCK D'APRÈS
     * CE COMPTAGE. Appelé par `AdjustStockAction` (point de passage unique) pour tout mouvement daté qu'il écrit.
     *
     * Le comptage d'un instant T est la vérité physique à T : les rayons comptés reflétaient déjà tout ce qui s'était
     * passé avant. Un mouvement daté avant T (une vente d'une caisse restée hors ligne, `sold_at` ; un achat du poste,
     * `purchased_at` ; une vente antidatée au web, 15.30 ; un ajout de stock d'un jour passé) qui n'arrive qu'APRÈS
     * l'enregistrement du comptage a donc déjà été « vu » par lui. Il est gardé à sa date — le grand livre, la rotation
     * et la fiche le voient au bon jour —, et l'écart du comptage est RECALCULÉ : une régularisation d'inventaire de
     * sens opposé (`inventaire`, `reference_id` = ce mouvement), datée de T, ramène le stock à T sur la quantité
     * comptée. Les mouvements postérieurs à T restent comptés une fois par-dessus, comme `evaluer()` le veut.
     *
     * - Le comptage retenu est le PREMIER qui suit le mouvement : c'est lui qui l'a vu ; les suivants partent de lui.
     * - Un mouvement daté du seul JOUR (minuit) le jour même d'un comptage le SUIT (son heure n'est pas connue, et il
     *   est enregistré après lui) — la règle de `apresLeComptage`. Un mouvement à la seconde exacte du comptage le
     *   suit aussi (enregistré après lui).
     * - La PERTE passée au journal par ce comptage (14.41, D 657 / C 601 au PMP) suit son écart recalculé : une vente
     *   qui explique un « manquant » le reclasse en achats consommés (`annulerPerte`), un achat antérieur qui creuse
     *   le manquant ajoute la perte correspondante. Valorisée au PMP courant.
     *
     * ⚠️ Limite dite : un comptage SANS écart ne laisse aucun mouvement (le web répond « Aucun écart détecté », S-T10
     * l'acquitte sans mouvement) — il n'est donc pas retrouvé ici, et un mouvement antérieur qui arrive après lui
     * reste compté en plus.
     */
    public function compenserMouvementAnterieur(Product $produit, StockMovement $mouvement): ?StockMovement
    {
        if (in_array($mouvement->reference_type, GestionStocks::TYPES_ECART_INVENTAIRE, true)) {
            return null;   // un comptage ne se compense pas lui-même (et la régularisation n'en appelle pas une autre)
        }

        $delta = match ($mouvement->type) {
            'entree' => (float) $mouvement->quantity,
            'sortie' => -(float) $mouvement->quantity,
            default => 0.0,
        };
        $date = $mouvement->movement_date?->copy()->setTimezone(config('app.timezone'));
        if ($delta == 0.0 || $date === null) {
            return null;
        }
        $jourSeul = $date->format('H:i:s') === '00:00:00';

        $comptage = StockMovement::query()
            ->where('product_id', $produit->id)
            ->whereIn('reference_type', GestionStocks::TYPES_ECART_INVENTAIRE)
            ->where('movement_date', '>', $date->format('Y-m-d H:i:s'))
            ->orderBy('movement_date')
            ->get(['movement_date'])
            ->first(fn (StockMovement $c) => ! ($jourSeul && $c->movement_date->isSameDay($date)));
        if ($comptage === null) {
            return null;
        }
        $instant = $comptage->movement_date;

        // Écart de ce comptage tel qu'il est au grand livre (le mouvement d'origine et ses régularisations, tous datés
        // de T), avant celle-ci.
        $ecartAvant = (float) StockMovement::query()
            ->where('product_id', $produit->id)
            ->whereIn('reference_type', GestionStocks::TYPES_ECART_INVENTAIRE)
            ->where('movement_date', $instant->format('Y-m-d H:i:s'))
            ->get(['type', 'quantity'])
            ->sum(fn (StockMovement $m) => $m->type === 'entree' ? (float) $m->quantity : -(float) $m->quantity);

        $motif = mb_substr(sprintf(
            'Régularisation d\'inventaire : %s du %s, antérieur(e) au comptage du %s, enregistré(e) après lui',
            self::LIBELLES[$mouvement->reference_type] ?? $mouvement->reference_type,
            $date->format('d/m/Y H:i'),
            $instant->format('d/m/Y H:i'),
        ), 0, 255);

        $regularisation = app(AdjustStockAction::class)->execute($produit, -$delta, 'inventaire', $mouvement->id, $instant, $motif);

        $perteAvant = max(0.0, -$ecartAvant);
        $perteApres = max(0.0, -($ecartAvant - $delta));
        $variation = round($perteApres - $perteAvant, 2);
        $ecritures = app(RecordStockAdjustmentEntryAction::class);
        if ($variation > 0) {
            $ecritures->execute($produit->fresh(), -$variation, 'régularisation d\'inventaire');
        } elseif ($variation < 0) {
            $ecritures->annulerPerte($produit->fresh(), -$variation, 'régularisation d\'inventaire');
        }

        AuditLog::record('stock.inventaire_regularise', 'stocks');

        return $regularisation;
    }

    /** Ce que le motif de la régularisation dit du mouvement compensé. */
    private const LIBELLES = [
        'sale' => 'vente',
        'purchase' => 'achat',
        'purchase_return' => 'retour fournisseur',
        'credit_note' => 'retour client',
        'manual_addition' => 'ajout de stock',
        'transformation' => 'transformation',
        'elevage' => 'production d\'élevage',
        'daily_entry' => 'production',
    ];

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
