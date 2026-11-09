<?php

namespace App\Services\Mecef;

use App\Support\AibTaux;

/**
 * CONF-2 — la COUCHE DE TRADUCTION de la facture normalisée vers le boîtier Eltrade CC300 (`bill.spec.json` du pilote).
 *
 * `MecefFactureBuilder` reste LE constructeur unique (prix entiers, remise répartie, écart d'arrondi, groupes de taxe,
 * libellés ≤ 60) : cette classe ne recalcule RIEN, elle ne fait que renommer. Écart documenté (docs/logialvia/41_MECEF_EMECEF.md
 * §3.2) : l'API en ligne parle `items` / `taxGroup` / `payment` / `type` / `aib` = `A|B`, le pilote attend `products` / `tax` /
 * `payments` / `vt` / `aib` = `"1%"|"5%"|"N/A"` / `seller_id` / `seller_name`.
 *
 * ⚠️ Jamais confrontée à un vrai boîtier (MECEF-2 n'est pas construit) : le schéma est celui de `bill.spec.json`, lu, pas essayé.
 */
final class ChargeBoitierEltrade
{
    /** Modes de paiement du boîtier : « V » virement, « C » carte, « M » mobile money, « D » chèque, « E » espèces, « A » autre. */
    public const MODES = [
        'ESPECES' => 'E',
        'MOBILEMONEY' => 'M',
        'VIREMENT' => 'V',
        'CARTE' => 'C',
        'CHEQUE' => 'D',
        'AUTRE' => 'A',
    ];

    /** Longueur maximale de `seller_name` dans le schéma du pilote. */
    public const VENDEUR_MAX = 30;

    /**
     * @param  array<string, mixed>  $enLigne  sortie de `MecefFactureBuilder::pourVente` (facture de vente `FV`) ou `pourAvoir`
     * @return array<string, mixed>
     */
    public function depuisChargeEnLigne(array $enLigne, string $vendeurId, string $vendeurNom): array
    {
        $charge = [
            'vt' => $enLigne['type'],
            'seller_id' => $vendeurId,
            'seller_name' => mb_substr($vendeurNom, 0, self::VENDEUR_MAX),
        ];

        if (($enLigne['type'] ?? '') === 'FA') {
            unset($charge['vt']);
            $charge = ['rt' => 'FA', 'rn' => (string) ($enLigne['reference'] ?? '')] + $charge;
        }

        $client = $enLigne['client'] ?? [];
        if (! empty($client['ifu'])) {
            $charge['buyer_ifu'] = (string) $client['ifu'];
        }
        if (! empty($client['name'])) {
            $charge['buyer_name'] = (string) $client['name'];
        }

        $charge['aib'] = match ($enLigne['aib'] ?? null) {
            'B' => AibTaux::CINQ,
            'A' => AibTaux::UN,
            default => AibTaux::AUCUN,
        };

        $charge['payments'] = array_map(fn (array $p) => [
            'mode' => self::MODES[$p['name']] ?? 'A',
            'amount' => $p['amount'],
        ], $enLigne['payment']);

        $charge['products'] = array_map(function (array $i) {
            $produit = ['label' => $i['name'], 'tax' => $i['taxGroup'], 'price' => $i['price'], 'items' => $i['quantity']];
            if (isset($i['originalPrice'])) {
                $produit['original_price'] = $i['originalPrice'];
                $produit['price_change_explanation'] = (string) ($i['priceModification'] ?? 'Remise');
            }

            return $produit;
        }, $enLigne['items']);

        return $charge;
    }
}
