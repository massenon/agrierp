<?php

namespace App\Actions;

use App\Models\Sale;
use App\Models\TreasuryAccount;

/**
 * Ticket 14.32 (Sprint 14) — ENCAISSEMENT RÉEL D'UNE VENTE.
 *
 * 🔴 DÉFAUT TROUVÉ EN SIMULANT L'EXPLOITATION (ticket 14.31) : `PosInterface`
 * ne contenait **aucune référence à `TreasuryAccount`**. Une vente réglée en
 * espèces n'augmentait donc jamais la caisse.
 *
 * La trésorerie de ce projet est tenue en DEUX livres qui doivent concorder :
 *   - `treasury_accounts.balance`, lu par le KPI « Trésorerie Disponible » du
 *     tableau de bord et par le hub Comptabilité ;
 *   - les comptes de classe 5 du GRAND LIVRE (531 Caisse, 521101 Banque,
 *     521201 Mobile Money), lus par le Bilan et le Rapprochement Bancaire.
 *
 * Or l'écriture de vente (ticket 14.23) débitait bien le compte de trésorerie
 * au grand livre, tandis que la table, elle, ne bougeait pas. **Les deux
 * livres divergeaient dès la première vente**, et dans un seul sens : les
 * achats, la paie et les dépenses décrémentent la table, rien ne la
 * recréditait jamais depuis une vente. Le solde affiché dérivait donc
 * mécaniquement vers le bas — jusqu'au négatif — quel que soit le chiffre
 * d'affaires encaissé. Constaté sur la simulation : −3 330 500 FCFA de banque
 * après cinq mois d'achats, sans qu'aucune vente ne puisse jamais le relever.
 *
 * ⚠️ MÊME TABLE DE CORRESPONDANCE QUE L'ÉCRITURE COMPTABLE, réutilisée depuis
 * `RecordSaleAccountingEntryAction` plutôt que recopiée : deux tables de
 * correspondance mode → compte finiraient par diverger, et les deux livres
 * cesseraient de concorder pour une autre raison que celle-ci.
 *
 * ⚠️ VENTE À CRÉDIT : aucun encaissement. Le règlement viendra plus tard, et
 * c'est `ProfileClient`/`SuiviDettes` qui créditent alors la trésorerie.
 * Créditer ici anticiperait un encaissement qui n'a pas eu lieu.
 */
class CreditTreasuryForSaleAction
{
    public function execute(Sale $sale): ?TreasuryAccount
    {
        $code = RecordSaleAccountingEntryAction::COMPTES_PAR_MODE[$sale->payment_mode] ?? null;

        // 411 = vente à crédit : rien n'est encaissé à cet instant.
        // null = mode non mappé (avance) : aucune trésorerie mouvementée non plus.
        if ($code === null || $code === '411') {
            return null;
        }

        $compte = TreasuryAccount::where('account_code', $code)->where('is_active', true)->first();

        if (! $compte) {
            return null;   // compte de trésorerie absent — signalé, jamais deviné
        }

        $compte->increment('balance', round((float) $sale->total, 2));

        return $compte->fresh();
    }
}
