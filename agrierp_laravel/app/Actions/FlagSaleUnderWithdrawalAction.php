<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\Notification;
use App\Models\Sale;
use App\Models\VeterinaryWithdrawalPeriod;

/**
 * Ticket 14.68 (Sprint 14) — VENTE REÇUE D'UNE BANDE SOUS RÉMANENCE.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  ⚠️⚠️ LE TROU, ET POURQUOI IL N'EST PAS THÉORIQUE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Vendre la viande d'une bande sous délai d'attente expose le consommateur à
 * des résidus d'antibiotiques. La caisse **web** refuse cette vente, et le
 * poste Desktop la refuse aussi — mais **uniquement avec les rémanences qu'il a
 * tirées**.
 *
 * Le cas réel n'a rien d'une attaque : l'animalier traite une bande à 9 h depuis
 * le web ; le poste du caissier n'a pas synchronisé depuis la veille ; à 11 h il
 * vend cette bande **en toute bonne foi**, sans aucun moyen de savoir. Le
 * serveur est alors le SEUL endroit qui puisse s'en apercevoir — et il ne
 * regardait pas.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  ⚠️⚠️ POURQUOI ON ENREGISTRE LA VENTE AU LIEU DE LA REFUSER
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * À la réception, la vente **a déjà eu lieu** : l'argent est encaissé, la
 * marchandise est partie. La refuser aurait deux effets, tous deux mauvais :
 *
 * 1. **Les livres ne refléteraient plus la réalité** — une recette encaissée
 *    n'apparaîtrait nulle part, et la caisse physique ne tomberait plus juste ;
 * 2. **On perdrait la traçabilité** : c'est précisément l'enregistrement de
 *    cette vente qui dit QUI a acheté, QUAND et de QUELLE bande. Sans lui, un
 *    rappel sanitaire est impossible.
 *
 * De plus, un rejet laisserait la vente `pending` sur le poste, rejouée
 * indéfiniment à chaque synchronisation — un refus permanent que personne ne
 * peut lever.
 *
 * La vente est donc **enregistrée ET signalée** : une notification pour
 * l'administrateur, une trace dans le journal d'audit. L'incident devient
 * visible et actionnable au lieu de rester muet.
 *
 * ⚠️ LA PRÉVENTION RESTE EN AMONT : la caisse web et le poste continuent de
 * REFUSER la vente. Ce contrôle-ci est le filet, pas la barrière.
 */
class FlagSaleUnderWithdrawalAction
{
    /**
     * @return array<int, string> Codes des bandes concernées, vide si aucune.
     */
    public function execute(Sale $vente): array
    {
        $lotIds = $vente->lines
            ->pluck('lot_id')
            ->filter()
            ->unique()
            ->all();

        if ($lotIds === []) {
            return [];
        }

        // ⚠️ LA RÉMANENCE EST JUGÉE À LA DATE DE LA VENTE, pas à celle de la
        // réception. Une vente d'il y a trois jours, poussée aujourd'hui alors
        // que le délai vient d'expirer, était bel et bien interdite au moment
        // où elle a eu lieu.
        //
        // 🔴→✅ TICKET 15.30 — « la date de la vente » EST `sold_at`. Le contrôle lisait
        // `created_at` (le tirage) : une vente du 04/10 reçue le 14/10 était jugée au 14/10.
        // Et une période se BORNE des deux côtés : un traitement commencé APRÈS la vente ne
        // la rendait pas illégale — sans `start_date <=`, une vente antérieure serait signalée
        // à tort (fausse alerte, et un signal qui crie à tort cesse d'être lu).
        // Repli sur `created_at` pour l'historique et les postes qui n'envoient pas `sold_at`.
        $dateVente = $vente->date_effective?->toDateString() ?? now()->toDateString();

        $bloquees = VeterinaryWithdrawalPeriod::whereIn('lot_id', $lotIds)
            ->where(fn ($q) => $q->whereNull('start_date')->orWhereDate('start_date', '<=', $dateVente))
            ->whereDate('end_date', '>=', $dateVente)
            ->pluck('lot_id')
            ->unique();

        if ($bloquees->isEmpty()) {
            return [];
        }

        $codes = LivestockLot::whereIn('id', $bloquees)->pluck('code', 'id');

        foreach ($bloquees as $lotId) {
            $code = $codes[$lotId] ?? $lotId;

            Notification::create([
                'target_role' => 'admin',
                'type' => 'sale_under_withdrawal',
                // Ticket 15.49 — `error` est hors des gravités autorisées par la colonne : incident sanitaire = critique.
                'severity' => 'critique',
                'title' => 'Vente reçue sur une bande sous délai d\'attente',
                'message' => "Bande {$code} — vente {$vente->id} encaissée hors ligne alors "
                    ."que le délai d'attente vétérinaire courait. La vente est enregistrée "
                    ."pour rester traçable : vérifiez l'acheteur et la nécessité d'un rappel.",
                'icon' => 'gpp_bad',
                'is_read' => false,
            ]);
        }

        AuditLog::record('sale.under_withdrawal_received', 'ventes');

        return $codes->values()->all();
    }
}
