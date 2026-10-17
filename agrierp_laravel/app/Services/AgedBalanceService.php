<?php

namespace App\Services;

use App\Models\Payable;
use App\Models\Receivable;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Ticket 14.66 (Sprint 14) — BALANCE ÂGÉE (clients et fournisseurs).
 *
 * ⚠️ **ÉCRAN HORS MAQUETTE, ET C'EST DIT.** `prototype_html` ne porte aucune
 * balance âgée : le mot « âgée » n'y apparaît que sur des écrans de STOCK
 * (ancienneté des lots), jamais sur les créances. Cet écran répond à un besoin
 * exprimé par le client comptable, il ne convertit pas une maquette existante.
 * Aucun écran du prototype n'est modifié — la Balance générale reste intacte.
 *
 * ⚠️⚠️ **LES TRANCHES SONT CELLES DE L'USAGE, PAS DES VALEURS INVENTÉES** :
 * non échu, 1-30, 31-60, 61-90, plus de 90 jours. C'est le découpage courant du
 * suivi de créances, celui qu'un comptable attend. Il est exposé en constante
 * pour rester modifiable sans toucher au calcul.
 *
 * ⚠️ **L'ÂGE SE COMPTE DEPUIS L'ÉCHÉANCE, PAS DEPUIS L'ÉMISSION.** Une facture
 * à 60 jours émise il y a 45 jours n'est pas en retard : la classer « 31-60 »
 * ferait relancer un client parfaitement à jour, et abîmerait la relation
 * commerciale pour rien.
 *
 * ⚠️ **LE RESTE DÛ, JAMAIS LE MONTANT INITIAL** : une facture de 100 000 réglée
 * à 90 000 pèse 10 000 dans la balance âgée. Retenir le montant d'origine
 * gonflerait l'encours de tout ce qui a déjà été encaissé.
 */
class AgedBalanceService
{
    /**
     * Bornes hautes des tranches, en jours de retard.
     *
     * @var array<string, int|null>
     */
    public const TRANCHES = [
        'Non échu' => 0,
        '1 à 30 jours' => 30,
        '31 à 60 jours' => 60,
        '61 à 90 jours' => 90,
        'Plus de 90 jours' => null,
    ];

    /** Balance âgée des créances clients. */
    public function creances(?Carbon $arrete = null): array
    {
        return $this->agencer(
            Receivable::with('customer')
                ->whereColumn('amount_paid', '<', 'amount')
                ->get(),
            fn ($ligne) => $ligne->customer?->name ?? 'Client supprimé',
            $arrete,
        );
    }

    /** Balance âgée des dettes fournisseurs. */
    public function dettes(?Carbon $arrete = null): array
    {
        return $this->agencer(
            Payable::with('supplier')
                ->whereColumn('amount_paid', '<', 'amount')
                ->get(),
            fn ($ligne) => $ligne->supplier?->name ?? 'Fournisseur supprimé',
            $arrete,
        );
    }

    /**
     * Tranche d'une échéance à une date d'arrêté.
     *
     * ⚠️ SANS ÉCHÉANCE, LA LIGNE EST « NON ÉCHUE » — jamais rangée dans la
     * tranche la plus ancienne. Une date manquante est une lacune de saisie,
     * pas un retard de paiement : l'inverse ferait relancer à tort.
     */
    public function tranche(?Carbon $echeance, Carbon $arrete): string
    {
        if ($echeance === null || $echeance->greaterThanOrEqualTo($arrete)) {
            return 'Non échu';
        }

        $retard = $echeance->diffInDays($arrete);

        foreach (self::TRANCHES as $libelle => $borne) {
            if ($borne === 0) {
                continue;
            }

            if ($borne === null || $retard <= $borne) {
                return $libelle;
            }
        }

        return 'Plus de 90 jours';
    }

    /**
     * @param  Collection<int, object>  $lignes
     * @param  callable(object): string  $nomDuTiers
     * @return array{tiers: array<int, array<string, mixed>>, totaux: array<string, float>, total: float}
     */
    private function agencer(Collection $lignes, callable $nomDuTiers, ?Carbon $arrete): array
    {
        $arrete = ($arrete ?? Carbon::now())->startOfDay();

        $vide = array_fill_keys(array_keys(self::TRANCHES), 0.0);
        $parTiers = [];
        $totaux = $vide;

        foreach ($lignes as $ligne) {
            // ⚠️ LE RESTE DÛ, pas le montant initial.
            $reste = (float) $ligne->amount - (float) $ligne->amount_paid;

            if ($reste <= 0) {
                continue;
            }

            $nom = $nomDuTiers($ligne);
            $echeance = $ligne->due_date ? Carbon::parse($ligne->due_date)->startOfDay() : null;
            $tranche = $this->tranche($echeance, $arrete);

            $parTiers[$nom] ??= ['nom' => $nom, 'tranches' => $vide, 'total' => 0.0];
            $parTiers[$nom]['tranches'][$tranche] += $reste;
            $parTiers[$nom]['total'] += $reste;

            $totaux[$tranche] += $reste;
        }

        // Le plus gros encours d'abord : c'est celui qu'on relance en premier.
        uasort($parTiers, fn ($a, $b) => $b['total'] <=> $a['total']);

        return [
            'tiers' => array_values($parTiers),
            'totaux' => $totaux,
            'total' => array_sum($totaux),
        ];
    }
}
