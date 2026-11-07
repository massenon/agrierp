<?php

namespace App\Services\Mecef;

use App\Exceptions\MecefFactureInvalideException;
use App\Models\CreditNote;
use App\Models\Sale;
use App\Services\TvaSettingService;
use App\Services\VatDeclarationService;
use App\Support\AibTaux;

/**
 * MECEF-1 — LE CONSTRUCTEUR UNIQUE de la facture normalisée (vente `FV`, avoir `FA`) : vente → JSON e-MECeF.
 *
 * Partagé par `EmecefGateway` (serveur, MECEF-1) et, le jour venu, par le mode boîtier du poste (MECEF-2) : jamais une
 * seconde façon de construire la facture. Noms de champs de l'API e-MECeF (DGI) : `ifu`, `type`, `client`, `operator`,
 * `items` (`name`, `price` TTC, `quantity`, `taxGroup`, `originalPrice`, `priceModification`), `payment`, `reference`, `aib`.
 *
 * ━━ PAS DE PRIX DÉCIMAL (demande du client, 07/11/2026) ━━
 * Tout montant envoyé à la DGI — prix unitaire TTC, `originalPrice`, total d'un règlement — est un ENTIER en FCFA. Il n'y a
 * qu'UNE fonction d'arrondi, `arrondi()` (au plus proche, la moitié vers le haut) : le builder ne rend jamais un montant autrement.
 * Seule la QUANTITÉ peut être décimale (2,5 kg, jamais plus de 3 décimales).
 *
 *  1. Montant de chaque ligne = `sale_lines.manual_total_amount` (SOURCE DE VÉRITÉ, jamais `unit_price`), arrondi ;
 *  2. remise globale (arrondie) répartie au prorata des lignes par la méthode du plus fort reste (somme EXACTE, jamais plus
 *     que la ligne, départage par l'ordre des lignes) ;
 *  3. frais de livraison inclus dans la vente (`delivery_in_total`) : une ligne « Frais de livraison », quantité 1 ;
 *  4. ÉCART D'ARRONDI : le total de la vente (arrondi) doit être égal à la somme des lignes. S'il y a un écart, il est dû aux
 *     seuls arrondis (au plus 1 FCFA par ligne) et est ABSORBÉ par la ligne de produit de plus grand montant (la première
 *     en cas d'égalité) ; un écart plus grand que le nombre de lignes n'est pas un arrondi : facture REFUSÉE (motif français),
 *     jamais envoyée telle quelle ;
 *  5. prix unitaire = montant de la ligne ÷ quantité quand la division tombe juste (prix × quantité = montant, à l'unité près
 *     des milliers de quantité) ; sinon la ligne part en QUANTITÉ 1, au montant de la ligne, et le libellé porte la quantité
 *     réelle « (2,5 kg) » ;
 *  6. le total du règlement unique = somme des lignes = total de la vente (arrondi) : égaux par construction.
 *
 * Autres règles :
 *  - groupe de taxe d'après le taux de TVA du produit (`TvaSettingService::tauxPour`, donc 0 si l'exploitation n'est pas
 *    assujettie) : 0 % = A (exonéré), 18 % = B ; tout autre taux est REFUSÉ avec son motif (jamais deviné) ;
 *  - frais de livraison : même groupe que la ligne principale de la vente (`VatDeclarationService::tauxDeLaLivraison` : la ligne de
 *    produit de plus grand montant ; à égalité, le taux le plus haut) — B si taxable à 18 %, A si exonérée ;
 *  - aucune taxe spécifique n'est envoyée (la ferme n'en a pas) ;
 *  - le client : nom et IFU saisis à la vente (`client_nom_facture`, `client_ifu`), sinon le nom du client de la vente, sinon
 *    « Client Anonyme » ; un IFU vide = client sans IFU, le champ `ifu` du client est omis ;
 *  - AIB : champ `aib` de la facture (`B` = 5 %, `A` = 1 %, omis pour N/A — voir `AibTaux`). Le MONTANT n'est jamais calculé :
 *    la DGI le calcule et le renvoie (gardé dans `sales.mecef_aib_montant`). Le règlement ne l'ajoute pas au total : le paquet de
 *    référence compare les paiements à la SEULE somme des lignes (`InvoiceRequestDto::fromArray`). Non confirmé par la DGI.
 *  - libellé d'un article : 60 caractères au plus (limite du boîtier, reprise ici pour que MECEF-2 envoie le même texte).
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

    public const NOM_MAX = 60;

    public const LIBELLE_LIVRAISON = 'Frais de livraison';

    /**
     * L'UNIQUE ARRONDI de montant du constructeur : au FCFA le plus proche, la moitié vers le haut.
     */
    public static function arrondi(float|int|string|null $montant): int
    {
        return (int) round((float) $montant, 0, PHP_ROUND_HALF_UP);
    }

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
            'unite' => (string) ($l->product?->unit ?? ''),
            'qte' => (float) $l->qty,
            'montant' => self::arrondi($l->manual_total_amount ?? $l->qty * $l->unit_price),
            'taux' => (float) ($l->product?->tva_rate ?? 0),
        ])->all();

        // 2. Remise : répartie au prorata, somme exacte.
        $montants = array_column($lignes, 'montant');
        $remise = min(max(0, self::arrondi($sale->discount)), array_sum($montants));
        $parts = $this->repartir($remise, $montants);

        $nets = [];
        foreach ($lignes as $i => $l) {
            $nets[$i] = $l['montant'] - $parts[$i];
        }

        // 3. Frais de livraison inclus dans la vente : une ligne, quantité 1.
        $livraison = $sale->delivery_in_total ? max(0, self::arrondi($sale->delivery_fee)) : 0;

        // 4. Écart d'arrondi entre le total de la vente et la somme des lignes.
        $cible = self::arrondi($sale->total);
        $ecart = $cible - (array_sum($nets) + $livraison);

        if ($ecart !== 0) {
            if (abs($ecart) > count($lignes) + ($livraison > 0 ? 1 : 0)) {
                throw new MecefFactureInvalideException('Total de la vente ('.$cible.' FCFA) différent de la somme de ses lignes ('.(array_sum($nets) + $livraison).' FCFA) : facture non transmise.');
            }

            $absorbante = $this->indexDuPlusGrand($nets);
            if ($nets[$absorbante] + $ecart < 0) {
                throw new MecefFactureInvalideException('Écart d\'arrondi impossible à absorber : facture non transmise.');
            }
            $nets[$absorbante] += $ecart;
        }

        $items = [];
        foreach ($lignes as $i => $l) {
            if ($nets[$i] <= 0) {
                continue; // ligne entièrement remisée : rien à déclarer (la DGI exige un prix > 0).
            }

            $items[] = $this->ligne($l['nom'], $l['unite'], $l['qte'], $nets[$i], $l['taux'], $parts[$i] > 0 ? $l['montant'] : null);
        }

        if ($livraison > 0) {
            // Même taux que l'écriture comptable et la Déclaration de TVA : un seul calcul (`tauxDeLaLivraison`).
            $tauxLivraison = round(app(VatDeclarationService::class)->tauxDeLaLivraison($sale) * 100, 2);
            $items[] = $this->ligne(self::LIBELLE_LIVRAISON, '', 1.0, $livraison, $tauxLivraison, null);
        }

        $total = array_sum($nets) + $livraison;

        if ($total <= 0 || $items === []) {
            throw new MecefFactureInvalideException('Facture de montant nul : rien à normaliser.');
        }

        return $this->enveloppe('FV', $emetteur, $sale, $items, $total, null);
    }

    /**
     * Facture d'avoir `FA` : une ligne (le produit retourné, la quantité et le montant crédité), `reference` = uid DGI de
     * la facture d'origine. Le client et l'AIB sont ceux de la facture d'origine.
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

        $montant = self::arrondi($avoir->amount);

        if ($montant <= 0 || (float) $avoir->qty <= 0) {
            throw new MecefFactureInvalideException('Avoir de montant nul : rien à normaliser.');
        }

        $items = [$this->ligne($avoir->product?->name ?? 'Article', (string) ($avoir->product?->unit ?? ''), (float) $avoir->qty, $montant, (float) ($avoir->product?->tva_rate ?? 0), null)];

        return $this->enveloppe('FA', $emetteur, $sale, $items, $montant, $sale->mecef_uid);
    }

    /**
     * Répartit un montant ENTIER au prorata de poids entiers, méthode du plus fort reste : la somme des parts est EXACTEMENT
     * le montant, aucune part ne dépasse son poids, l'égalité des restes est tranchée par l'ordre des lignes (déterministe).
     *
     * @param  array<int, int>  $poids
     * @return array<int, int>
     */
    private function repartir(int $montant, array $poids): array
    {
        $somme = array_sum($poids);
        $parts = array_fill_keys(array_keys($poids), 0);

        if ($montant <= 0 || $somme <= 0) {
            return $parts;
        }

        $restes = [];
        foreach ($poids as $i => $p) {
            $parts[$i] = intdiv($montant * $p, $somme);
            $restes[$i] = ($montant * $p) % $somme;
        }

        $reliquat = $montant - array_sum($parts);
        $ordre = array_keys($restes);
        usort($ordre, fn ($a, $b) => $restes[$b] <=> $restes[$a] ?: $a <=> $b);

        foreach (array_slice($ordre, 0, $reliquat) as $i) {
            $parts[$i]++;
        }

        return $parts;
    }

    /**
     * L'index de la ligne de plus grand montant (la première à égalité).
     *
     * @param  array<int, int>  $nets
     */
    private function indexDuPlusGrand(array $nets): int
    {
        $meilleur = null;

        foreach ($nets as $i => $net) {
            if ($meilleur === null || $net > $nets[$meilleur]) {
                $meilleur = $i;
            }
        }

        return (int) $meilleur;
    }

    /**
     * Une ligne de facture, en entiers. `$net` = montant de la ligne après remise (entier > 0) ; `$montantAvantRemise` = son
     * montant avant remise (entier) ou null.
     *
     * @return array<string, mixed>
     */
    private function ligne(string $nom, string $unite, float $qte, int $net, float $tauxProduit, ?int $montantAvantRemise): array
    {
        $taux = app(TvaSettingService::class)->tauxPour($tauxProduit);
        $cle = rtrim(rtrim(number_format($taux, 2, '.', ''), '0'), '.');
        $groupe = self::GROUPES_TAXE[$cle === '' ? '0' : $cle] ?? null;

        if ($groupe === null) {
            throw new MecefFactureInvalideException('Taux de TVA de '.str_replace('.', ',', $cle).' % non pris en charge par e-MECeF (article « '.$nom.' ») : seuls 0 % (exonéré) et 18 % le sont.');
        }

        // Quantité en millièmes (3 décimales au plus) : toute l'arithmétique qui suit est ENTIÈRE.
        $milliemes = (int) round($qte * 1000);

        if ($milliemes <= 0) {
            throw new MecefFactureInvalideException('Quantité nulle pour l\'article « '.$nom.' » : rien à normaliser.');
        }

        if (($net * 1000) % $milliemes === 0) {
            // Prix unitaire ENTIER et prix × quantité = montant de la ligne.
            $prix = intdiv($net * 1000, $milliemes);
            $quantite = $milliemes % 1000 === 0 ? intdiv($milliemes, 1000) : $milliemes / 1000;
            $original = $montantAvantRemise === null ? null : self::arrondi($montantAvantRemise * 1000 / $milliemes);
            $suffixe = '';
        } else {
            // La division ne tombe pas juste : quantité 1 au montant de la ligne, la quantité réelle est dans le libellé.
            $prix = $net;
            $quantite = 1;
            $original = $montantAvantRemise;
            $reelle = rtrim(rtrim(number_format($milliemes / 1000, 3, ',', ''), '0'), ',');
            $suffixe = ' ('.$reelle.($unite !== '' ? ' '.$unite : '').')';
        }

        $ligne = [
            'name' => $this->tronquer($nom, $suffixe),
            'price' => $prix,
            'quantity' => $quantite,
            'taxGroup' => $groupe,
        ];

        if ($original !== null) {
            $ligne['originalPrice'] = $original;
            $ligne['priceModification'] = 'Remise';
        }

        return $ligne;
    }

    /** Libellé = nom + suffixe (la quantité réelle d'une ligne à quantité 1), borné à `NOM_MAX` caractères : c'est le NOM qu'on rogne, jamais le suffixe. */
    private function tronquer(string $nom, string $suffixe): string
    {
        if (mb_strlen($suffixe) >= self::NOM_MAX) {
            return mb_substr($nom.$suffixe, 0, self::NOM_MAX);
        }

        return mb_substr($nom, 0, self::NOM_MAX - mb_strlen($suffixe)).$suffixe;
    }

    /** @return array<string, mixed> */
    private function enveloppe(string $type, array $emetteur, Sale $sale, array $items, int $total, ?string $reference): array
    {
        $client = ['name' => $sale->client_nom_facture ?: ($sale->customer?->name ?? 'Client Anonyme')];

        // IFU vide = client sans IFU (particulier) : le champ est omis, la DGI l'accepte.
        if (is_string($sale->client_ifu) && $sale->client_ifu !== '') {
            $client['ifu'] = $sale->client_ifu;
        }

        $charge = [
            'ifu' => $emetteur['ifu'],
            'type' => $type,
            'client' => $client,
            'operator' => ['id' => $emetteur['operateur_id'], 'name' => $emetteur['operateur_nom']],
            'items' => $items,
            'payment' => [['name' => self::MODES_PAIEMENT[$sale->payment_mode] ?? 'AUTRE', 'amount' => $total]],
        ];

        $aib = AibTaux::codeApi($sale->aib_taux);
        if ($aib !== null) {
            $charge['aib'] = $aib;
        }

        if ($reference !== null) {
            $charge['reference'] = $reference;
        }

        return $charge;
    }
}
