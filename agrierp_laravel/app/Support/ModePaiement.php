<?php

namespace App\Support;

/**
 * Ticket CONF-3 (DV-22) — LIBELLÉ FRANÇAIS D'UN MODE DE RÈGLEMENT : l'UNIQUE point de passage des documents et des écrans.
 *
 * La clé stockée (`sales.payment_mode`, `customer_advances.payment_mode`…) ne change JAMAIS : seul l'affichage passe par ici
 * (facture, historique des ventes). Clés connues : `especes`, `mobile_money`, `virement`, `cheque` (avances), `credit`,
 * `avance`. Clé inconnue : la clé telle quelle, « _ » lus comme des espaces, première lettre en capitale (« carte_bancaire »
 * → « Carte bancaire ») ; clé absente ou vide : « — », jamais une chaîne vide.
 *
 * Même table que `ModePaiement` du poste (`lib/features/ventes/mode_paiement.dart`) : prouvée par une parité exécutée.
 */
final class ModePaiement
{
    /** @var array<string, string> */
    public const LIBELLES = [
        'especes' => 'Espèces',
        'mobile_money' => 'Mobile Money',
        'virement' => 'Virement bancaire',
        'cheque' => 'Chèque',
        'credit' => 'Crédit client',
        'avance' => 'Avance',
    ];

    public static function libelle(?string $cle): string
    {
        $cle = trim((string) $cle);
        if ($cle === '') {
            return '—';
        }
        if (isset(self::LIBELLES[$cle])) {
            return self::LIBELLES[$cle];
        }

        $lisible = trim(str_replace('_', ' ', $cle));
        if ($lisible === '') {
            return $cle; // « _ » seul : la clé telle quelle, jamais vide
        }

        return mb_strtoupper(mb_substr($lisible, 0, 1)).mb_substr($lisible, 1);
    }
}
