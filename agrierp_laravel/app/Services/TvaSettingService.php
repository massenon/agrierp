<?php

namespace App\Services;

use App\Models\CompanySetting;

/**
 * Ticket 14.38 (Sprint 14) — TVA ACTIVABLE OU NON.
 *
 * Toutes les exploitations ne sont pas assujetties à la TVA. Une ferme sous le
 * régime du micro-entrepreneur, ou exonérée au titre de ses productions
 * agricoles brutes, ne collecte rien : lui présenter des montants TTC et une
 * déclaration à déposer lui montrerait des chiffres faux.
 *
 * ⚠️ CE DRAPEAU PILOTE DEUX CHOSES, ET C'EST VOLONTAIRE :
 *
 *   1. L'AFFICHAGE — TVA active : les rubriques de TVA apparaissent et les
 *      montants sont présentés TTC. TVA inactive : ni rubrique ni ligne de
 *      taxe, et les montants sont des montants HT.
 *
 *   2. LES ÉCRITURES COMPTABLES — TVA inactive, aucune ligne 443 (collectée)
 *      ni 445 (déductible) n'est produite : la totalité du montant va au
 *      compte de produit ou de charge.
 *
 * Ne piloter que l'affichage aurait été le piège : les écrans auraient montré
 * du HT pendant que le grand livre continuait de ventiler une taxe, et la
 * Déclaration TVA aurait affiché des montants à reverser sur une entreprise
 * non assujettie. Les deux doivent basculer ensemble.
 *
 * ⚠️ Point de vérité unique : personne ne relit `company_settings.tva_enabled`
 * ailleurs. Un second point de lecture finirait par diverger — c'est
 * exactement ce qui est arrivé aux deux livres de trésorerie (ticket 14.32).
 */
class TvaSettingService
{
    private static ?bool $cache = null;

    /** L'exploitation est-elle assujettie à la TVA ? */
    public function active(): bool
    {
        if (self::$cache !== null) {
            return self::$cache;
        }

        $parametres = CompanySetting::first();

        // Assujettie par défaut : c'est le régime le plus courant, et une
        // application qui cesserait silencieusement de collecter la TVA parce
        // qu'aucun paramètre n'a encore été saisi serait bien plus grave que
        // l'inverse.
        return self::$cache = (bool) ($parametres->tva_enabled ?? true);
    }

    public function inactive(): bool
    {
        return ! $this->active();
    }

    /**
     * Taux applicable à un produit.
     *
     * ⚠️ Retourne TOUJOURS 0 quand la TVA est désactivée, quel que soit le taux
     * porté par le produit. Le taux du catalogue reste inchangé en base — le
     * jour où l'exploitation devient assujettie, rien n'est à ressaisir.
     */
    public function tauxPour(?float $tauxProduit): float
    {
        return $this->active() ? (float) ($tauxProduit ?? 0) : 0.0;
    }

    /** Libellé du montant affiché, selon le régime. */
    public function libelleMontant(): string
    {
        return $this->active() ? 'TTC' : 'HT';
    }

    /** Réinitialise le cache — indispensable en test, où le réglage change. */
    public static function oublier(): void
    {
        self::$cache = null;
    }
}
