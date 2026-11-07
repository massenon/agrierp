<?php

namespace App\Services\Mecef;

use App\Exceptions\MecefFactureInvalideException;
use App\Models\CreditNote;
use App\Models\Sale;
use App\Services\TvaSettingService;

/**
 * MECEF-1 — LE CONSTRUCTEUR UNIQUE de la facture normalisée (vente `FV`, avoir `FA`) : vente → JSON e-MECeF.
 *
 * Partagé par `EmecefGateway` (serveur, MECEF-1) et, le jour venu, par le mode boîtier du poste (MECEF-2) : jamais une
 * seconde façon de construire la facture. Noms de champs de l'API e-MECeF (DGI) : `ifu`, `type`, `client`, `operator`,
 * `items` (`name`, `price` TTC, `quantity`, `taxGroup`, `originalPrice`, `priceModification`), `payment`, `reference`.
 *
 * Règles :
 *  - groupe de taxe d'après le taux de TVA du produit (`TvaSettingService::tauxPour`, donc 0 si l'exploitation n'est
 *    pas assujettie) : 0 % = A (exonéré), 18 % = B ; tout autre taux est REFUSÉ avec son motif (jamais deviné) ;
 *  - la remise globale de la vente est répartie au prorata des lignes (entiers, le reliquat sur la dernière) ;
 *    `originalPrice` / `priceModification` disent le prix avant remise ;
 *  - un seul règlement égal au total ; mode de paiement interne → mode DGI ;
 *  - les frais de livraison ne font pas partie de `sales.total` (facture web) : ils ne sont pas dans la facture DGI.
 *  - le client : son nom (« Client Anonyme » au comptant). Le client n'a ni IFU ni AIB dans la base : omis.
 */
class MecefFactureBuilder
{
    public const MODES_PAIEMENT = [
        'especes' => 'ESPECES',
        'mobile_money' => 'MOBILEMONEY',
        'virement' => 'VIREMENT',
        'credit' => 'CREDIT',
        'avance' => 'AUTRE',
    ];

    public const GROUPES_TAXE = ['0' => 'A', '18' => 'B'];

    /**
     * @param  array{ifu: string, operateur_id: string, operateur_nom: string}  $emetteur
     * @return array<string, mixed>
     *
     * @throws MecefFactureInvalideException
     */
    public function pourVente(Sale $sale, array $emetteur): array
    {
        $sale->loadMissing('lines.product', 'customer');

        if ($sale->lines->isEmpty()) {
            throw new MecefFactureInvalideException('Facture sans ligne : rien à normaliser.');
        }

        $lignes = $sale->lines->map(fn ($l) => [
            'nom' => $l->product?->name ?? 'Article',
            'qte' => (float) $l->qty,
            'total' => (float) ($l->manual_total_amount ?? $l->qty * $l->unit_price),
            'taux' => (float) ($l->product?->tva_rate ?? 0),
        ])->all();

        $sousTotal = array_sum(array_column($lignes, 'total'));
        $remise = min((float) $sale->discount, $sousTotal);
        $reste = (int) round($remise);
        $items = [];

        foreach ($lignes as $i => $l) {
            $derniere = $i === array_key_last($lignes);
            $part = $remise > 0 && $sousTotal > 0
                ? ($derniere ? $reste : (int) round($remise * $l['total'] / $sousTotal))
                : 0;
            $part = min($part, (int) round($l['total']));
            $reste -= $part;
            $net = $l['total'] - $part;

            $items[] = $this->ligne($l['nom'], $l['qte'], $net, $l['taux'], $part > 0 ? $l['total'] : null);
        }

        $total = array_sum(array_map(fn ($it) => round($it['price'] * $it['quantity']), $items));

        if ($total <= 0) {
            throw new MecefFactureInvalideException('Facture de montant nul : rien à normaliser.');
        }

        return $this->enveloppe('FV', $emetteur, $sale, $items, (float) $total, null);
    }

    /**
     * Facture d'avoir `FA` : une ligne (le produit retourné, la quantité et le montant crédité), `reference` = uid DGI de
     * la facture d'origine.
     *
     * @param  array{ifu: string, operateur_id: string, operateur_nom: string}  $emetteur
     * @return array<string, mixed>
     *
     * @throws MecefFactureInvalideException
     */
    public function pourAvoir(CreditNote $avoir, array $emetteur): array
    {
        $avoir->loadMissing('product', 'sale.customer');
        $sale = $avoir->sale;

        if ($sale === null || ! $sale->mecef_uid) {
            throw new MecefFactureInvalideException('Avoir sans facture d\'origine normalisée : référence DGI absente.');
        }

        if ((float) $avoir->amount <= 0 || (float) $avoir->qty <= 0) {
            throw new MecefFactureInvalideException('Avoir de montant nul : rien à normaliser.');
        }

        $items = [$this->ligne($avoir->product?->name ?? 'Article', (float) $avoir->qty, (float) $avoir->amount, (float) ($avoir->product?->tva_rate ?? 0), null)];
        $total = round($items[0]['price'] * $items[0]['quantity']);

        return $this->enveloppe('FA', $emetteur, $sale, $items, (float) $total, $sale->mecef_uid);
    }

    /** @return array<string, mixed> */
    private function ligne(string $nom, float $qte, float $netLigne, float $tauxProduit, ?float $totalAvantRemise): array
    {
        $taux = app(TvaSettingService::class)->tauxPour($tauxProduit);
        $cle = rtrim(rtrim(number_format($taux, 2, '.', ''), '0'), '.');
        $groupe = self::GROUPES_TAXE[$cle === '' ? '0' : $cle] ?? null;

        if ($groupe === null) {
            throw new MecefFactureInvalideException('Taux de TVA de '.str_replace('.', ',', $cle).' % non pris en charge par e-MECeF (article « '.$nom.' ») : seuls 0 % (exonéré) et 18 % le sont.');
        }

        $ligne = [
            'name' => $nom,
            'price' => round($netLigne / max($qte, 0.0001), 2),
            'quantity' => $qte,
            'taxGroup' => $groupe,
        ];

        if ($totalAvantRemise !== null) {
            $ligne['originalPrice'] = round($totalAvantRemise / max($qte, 0.0001), 2);
            $ligne['priceModification'] = 'Remise';
        }

        return $ligne;
    }

    /** @return array<string, mixed> */
    private function enveloppe(string $type, array $emetteur, Sale $sale, array $items, float $total, ?string $reference): array
    {
        $charge = [
            'ifu' => $emetteur['ifu'],
            'type' => $type,
            'client' => ['name' => $sale->customer?->name ?? 'Client Anonyme'],
            'operator' => ['id' => $emetteur['operateur_id'], 'name' => $emetteur['operateur_nom']],
            'items' => $items,
            'payment' => [['name' => self::MODES_PAIEMENT[$sale->payment_mode] ?? 'AUTRE', 'amount' => $total]],
        ];

        if ($reference !== null) {
            $charge['reference'] = $reference;
        }

        return $charge;
    }
}
