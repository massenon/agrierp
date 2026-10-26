<?php

namespace App\Services;

use App\Models\CreditNote;
use App\Models\Purchase;
use App\Models\Sale;


/**
 * Ticket 14.7 (Sprint 14) — Déclaration TVA (module M14, exigence impérative :
 * articles 162 bis et 1084-40 du CGI Bénin, en vigueur depuis le 01/07/2021).
 *
 * Service dédié plutôt qu'un calcul dans le composant : la TVA sera aussi
 * nécessaire au Rapprochement Bancaire et aux écritures 4431/4452 générées
 * automatiquement — un seul point de vérité posé dès maintenant.
 *
 * ⚠️ CONVENTION DE MONTANT, REPRISE DU PROTOTYPE : les montants stockés
 * (`sale_lines.manual_total_amount`, `purchase_lines.qty × unit_price`) sont
 * traités comme des montants **TTC**, dont le HT est dérivé —
 * `HT = arrondi(TTC / (1 + taux))`, `TVA = TTC − HT`. C'est exactement la
 * formule du prototype (`calculerHT`/`calculerTVA`). Le schéma ne porte
 * aucune colonne HT/TTC distincte : inventer une seconde convention ici la
 * ferait diverger de la Facturation.
 *
 * ⚠️ SEULES LES FACTURES RÉELLEMENT TRANSMISES SONT DÉCLARÉES — règle
 * explicite du prototype : une facture au statut « Erreur MeCeF » n'a pas été
 * transmise à la DGI, elle ne peut donc pas figurer dans la déclaration.
 * Filtre `mecef_status = 'transmise'`, jamais toutes les ventes validées.
 */
class VatDeclarationService
{
    /** HT dérivé d'un TTC, à l'unité près — même arrondi que le prototype. */
    /**
     * Ticket 14.38 — l'exploitation est-elle assujettie ?
     *
     * ⚠️ Une entreprise non assujettie n'a RIEN à déclarer. Continuer à
     * ventiler une TVA sur ses ventes lui présenterait un montant à reverser
     * qu'elle ne doit pas.
     */
    public function assujettie(): bool
    {
        return app(TvaSettingService::class)->active();
    }

    public function ht(float $ttc, float $rate): float
    {
        return round($ttc / (1 + $rate));
    }

    public function tva(float $ttc, float $rate): float
    {
        return round($ttc - $this->ht($ttc, $rate));
    }

    /**
     * @return array{rows: array<int, array<string, mixed>>, total_ht: float, total_tva: float, total_ttc: float}
     */
    public function tvaCollectee(string $startDate, string $endDate): array
    {
        $sales = Sale::with(['customer', 'lines.product', 'devis'])
            ->where('status', 'validee')
            ->where('mecef_status', 'transmise')
            ->soldBetween($startDate, $endDate)
            ->orderByEffectiveDate()
            ->get();

        $rows = $sales->map(function ($sale) {
            $ht = 0.0;
            $tva = 0.0;
            $ttc = 0.0;
            $rates = [];

            foreach ($sale->lines as $line) {
                $lineTtc = (float) ($line->manual_total_amount ?: ($line->qty * $line->unit_price));
                // Ticket 14.38 : taux neutralisé si l'exploitation n'est pas assujettie.
                $rate = app(TvaSettingService::class)->tauxPour((float) ($line->product->tva_rate ?? 0)) / 100;

                $rates[] = $rate;
                $ttc += $lineTtc;
                $ht += $this->ht($lineTtc, $rate);
                $tva += $this->tva($lineTtc, $rate);
            }

            // Ticket DEV3 — facture d'un devis : aucune ligne, la TVA est celle du devis (total TTC de la vente).
            if ($sale->lines->isEmpty() && $sale->devis) {
                $rate = app(TvaSettingService::class)->tauxPour((float) $sale->devis->tva_rate) / 100;
                $ttc = (float) $sale->total;
                $ht = $this->ht($ttc, $rate);
                $tva = $this->tva($ttc, $rate);
                $rates[] = $rate;
            }

            return [
                'reference' => strtoupper(substr($sale->id, 0, 8)),
                'tiers' => $sale->customer?->name ?? 'Client Anonyme',
                'date' => $sale->date_effective->format('Y-m-d'),
                'rate_label' => $this->rateLabel($rates),
                'ht' => round($ht, 2),
                'tva' => round($tva, 2),
                'ttc' => round($ttc, 2),
            ];
        })->all();

        // 🔴→✅ TICKET 14.27 : LES AVOIRS VIENNENT EN DÉDUCTION.
        //
        // Cette méthode ne lisait que les ventes. Un retour client réduit
        // pourtant la TVA réellement due : sans cette déduction, la
        // déclaration DGI SURDÉCLARAIT la TVA collectée du montant de tous
        // les retours de la période — l'entreprise aurait payé une taxe sur
        // un chiffre d'affaires annulé.
        //
        // Lignes NÉGATIVES plutôt que soustraction d'un total : la
        // déclaration reste justifiable pièce par pièce devant
        // l'administration, chaque avoir y figurant avec son propre numéro.
        $rows = array_merge($rows, $this->avoirsDeduits($startDate, $endDate));

        return $this->withTotals($rows);
    }

    /**
     * Avoirs de la période, en lignes négatives.
     *
     * ⚠️ Aucun filtre `mecef_status` ici, contrairement aux ventes : un avoir
     * n'est pas normalisé par la plateforme MeCeF, seule la facture d'origine
     * l'est. Exiger un statut de transmission sur l'avoir en écarterait la
     * totalité et la déduction n'aurait jamais lieu.
     *
     * En revanche, l'avoir n'est retenu que si **sa vente d'origine est
     * elle-même déclarée** (`validee` + `transmise`) : déduire la TVA d'une
     * vente qui n'a jamais été déclarée créerait un crédit de taxe sans
     * contrepartie collectée.
     *
     * @return array<int, array<string, mixed>>
     */
    private function avoirsDeduits(string $startDate, string $endDate): array
    {
        return CreditNote::with(['sale.customer', 'product'])
            ->whereDate('created_at', '>=', $startDate)
            ->whereDate('created_at', '<=', $endDate)
            ->whereHas('sale', fn ($q) => $q->where('status', 'validee')->where('mecef_status', 'transmise'))
            ->orderByDesc('created_at')
            ->get()
            ->map(function ($avoir) {
                $ttc = (float) $avoir->amount;
                $rate = app(TvaSettingService::class)->tauxPour((float) ($avoir->product->tva_rate ?? 0)) / 100;

                return [
                    'reference' => $avoir->credit_note_number,
                    'tiers' => $avoir->sale?->customer?->name ?? 'Client Anonyme',
                    'date' => $avoir->created_at->format('Y-m-d'),
                    'rate_label' => $this->rateLabel([$rate]),
                    'ht' => -round($this->ht($ttc, $rate), 2),
                    'tva' => -round($this->tva($ttc, $rate), 2),
                    'ttc' => -round($ttc, 2),
                ];
            })
            ->all();
    }

    /**
     * @return array{rows: array<int, array<string, mixed>>, total_ht: float, total_tva: float, total_ttc: float}
     */
    public function tvaDeductible(string $startDate, string $endDate): array
    {
        $purchases = Purchase::with(['supplier', 'lines.product'])
            ->whereDate('purchase_date', '>=', $startDate)
            ->whereDate('purchase_date', '<=', $endDate)
            ->orderByDesc('purchase_date')
            ->get();

        $rows = $purchases->map(function ($purchase) {
            $ht = 0.0;
            $tva = 0.0;
            $ttc = 0.0;
            $rates = [];

            foreach ($purchase->lines as $line) {
                $lineTtc = (float) ($line->qty * $line->unit_price);
                // Ticket 14.38 : taux neutralisé si l'exploitation n'est pas assujettie.
                $rate = app(TvaSettingService::class)->tauxPour((float) ($line->product->tva_rate ?? 0)) / 100;

                $rates[] = $rate;
                $ttc += $lineTtc;
                $ht += $this->ht($lineTtc, $rate);
                $tva += $this->tva($lineTtc, $rate);
            }

            return [
                'reference' => strtoupper(substr($purchase->id, 0, 8)),
                'tiers' => $purchase->supplier?->name ?? '—',
                'date' => $purchase->purchase_date->format('Y-m-d'),
                'rate_label' => $this->rateLabel($rates),
                'ht' => round($ht, 2),
                'tva' => round($tva, 2),
                'ttc' => round($ttc, 2),
            ];
        })->all();

        return $this->withTotals($rows);
    }

    /**
     * Déclaration complète de la période.
     *
     * TVA nette négative = **crédit de TVA reportable** sur la période
     * suivante, jamais un remboursement automatique : le distinguer
     * explicitement évite d'afficher « à payer : -X », qui n'a pas de sens
     * pour la Direction.
     */
    public function declaration(string $startDate, string $endDate): array
    {
        $collectee = $this->tvaCollectee($startDate, $endDate);
        $deductible = $this->tvaDeductible($startDate, $endDate);

        $net = round($collectee['total_tva'] - $deductible['total_tva'], 2);

        return [
            'collectee' => $collectee,
            'deductible' => $deductible,
            'tva_nette' => $net,
            'is_credit' => $net < 0,
            'montant_affiche' => abs($net),
        ];
    }

    /**
     * Le prototype affiche un taux unique par facture. Une facture réelle peut
     * mélanger des lignes à 0% (produits bruts, exonérés) et à 18%
     * (transformés/services) : on l'affiche alors comme « mixte » plutôt que
     * de retenir arbitrairement le taux de la première ligne.
     *
     * @param  array<int, float>  $rates
     */
    private function rateLabel(array $rates): string
    {
        $distinct = array_values(array_unique($rates));

        if ($distinct === []) {
            return '—';
        }

        if (count($distinct) > 1) {
            return 'mixte';
        }

        $rate = $distinct[0];

        return $rate == 0.0 ? '0% (exonéré)' : rtrim(rtrim(number_format($rate * 100, 2, ',', ' '), '0'), ',').'%';
    }

    /** @param array<int, array<string, mixed>> $rows */
    private function withTotals(array $rows): array
    {
        return [
            'rows' => $rows,
            'total_ht' => round(array_sum(array_column($rows, 'ht')), 2),
            'total_tva' => round(array_sum(array_column($rows, 'tva')), 2),
            'total_ttc' => round(array_sum(array_column($rows, 'ttc')), 2),
        ];
    }
}
