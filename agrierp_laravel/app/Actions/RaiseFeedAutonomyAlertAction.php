<?php

namespace App\Actions;

use App\Models\Notification;
use App\Models\Product;

/**
 * Ticket 14.40 (Sprint 14) — ALERTE D'AUTONOMIE ALIMENTAIRE.
 *
 * 🔴 GAP DOCUMENTÉ DEPUIS LE TICKET 13.1, comblé ici. Le calcul d'autonomie
 * (« Stock ÷ Consommation théorique, alerte si ≤ 3 jours ») existait bien, mais
 * **uniquement comme propriété affichée à l'intérieur de la fiche consultée**.
 * Aucun code, nulle part, ne créait de notification : l'éleveur ne voyait
 * l'alerte que s'il ouvrait précisément la bonne fiche — c'est-à-dire jamais au
 * moment où elle est utile.
 *
 * Le prototype, lui, affiche « Stock aliment lapins bas » dans la cloche de la
 * barre supérieure : l'alerte est censée venir CHERCHER l'utilisateur.
 *
 * ⚠️ DÉDUPLICATION PAR PRODUIT ET PAR JOUR. Une fiche journalière se sauvegarde
 * plusieurs fois — l'éleveur corrige sa saisie. Sans déduplication, chaque
 * enregistrement empilerait une notification identique et la cloche deviendrait
 * illisible en une matinée. Le comportement inverse — n'alerter qu'une fois
 * pour toutes — serait pire : une rupture qui dure doit se rappeler chaque
 * jour.
 *
 * ⚠️ L'ALERTE SE RÉSORBE. Dès que le stock repasse au-dessus du seuil, les
 * alertes non lues de ce produit sont marquées lues. Une alerte de rupture qui
 * survit au réapprovisionnement apprend à l'utilisateur à ignorer la cloche —
 * et le jour où une vraie rupture survient, il l'ignorera aussi.
 */
class RaiseFeedAutonomyAlertAction
{
    /** Seuil du CDC : alerte à trois jours d'autonomie ou moins. */
    public const SEUIL_JOURS = 3.0;

    /**
     * @param  float  $consommationKgParJour  consommation théorique quotidienne
     * @return Notification|null              null si aucune alerte n'était à lever
     */
    public function execute(Product $aliment, float $consommationKgParJour): ?Notification
    {
        if ($consommationKgParJour <= 0) {
            // Aucun animal nourri sur ce produit : l'autonomie est infinie, pas
            // nulle. Diviser par zéro donnerait l'alerte la plus grave sur le
            // lot le plus vide.
            return null;
        }

        $autonomie = round($aliment->stockEnKg() / $consommationKgParJour, 1);

        if ($autonomie > self::SEUIL_JOURS) {
            $this->resorber($aliment);

            return null;
        }

        // Déjà signalé aujourd'hui pour ce produit : on ne réempile pas.
        $dejaAlerte = Notification::where('type', 'stock_low')
            ->where('link_url', $this->lien($aliment))
            ->whereDate('created_at', now()->toDateString())
            ->exists();

        if ($dejaAlerte) {
            return null;
        }

        return Notification::create([
            // ⚠️ Destinée au RÔLE, pas à un utilisateur : c'est l'animalier de
            // service qui doit la voir, quel que soit celui qui a saisi la
            // fiche. Une notification nominative resterait invisible au reste
            // de l'équipe.
            'target_role' => 'animalier',
            'type' => 'stock_low',
            'severity' => $autonomie <= 1.0 ? 'critique' : 'moyen',
            'title' => 'Stock '.$aliment->name.' bas',
            'message' => 'Autonomie restante : '.number_format($autonomie, 1, ',', ' ')
                .' jour'.($autonomie >= 2 ? 's' : '').' — '
                .number_format($aliment->stockEnKg(), 0, ',', ' ').' kg en stock pour '
                .number_format($consommationKgParJour, 1, ',', ' ').' kg consommés par jour. '
                .'Réapprovisionnez avant rupture.',
            'icon' => 'inventory_2',
            'link_url' => $this->lien($aliment),
            'is_read' => false,
        ]);
    }

    /** Le stock est reconstitué : les alertes ouvertes n'ont plus lieu d'être. */
    private function resorber(Product $aliment): void
    {
        Notification::where('type', 'stock_low')
            ->where('link_url', $this->lien($aliment))
            ->where('is_read', false)
            ->update(['is_read' => true, 'read_at' => now()]);
    }

    private function lien(Product $aliment): string
    {
        return '/gestion-stocks?produit='.$aliment->sku;
    }
}
