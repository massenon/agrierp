<?php

namespace App\Actions;

use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use Carbon\Carbon;

/**
 * Ticket 14.54 (Sprint 14) — UN SOIN ENREGISTRÉ DÉCLENCHE SA RÉMANENCE.
 *
 * ⚠️⚠️ RÈGLE DE SANTÉ PUBLIQUE, pas une commodité. Un délai d'attente > 0
 * bloque la bande à la vente : sans ce blocage, la ferme écoulerait une viande
 * porteuse de résidus d'antibiotiques. Le prototype l'énonce sans détour —
 * « Si > 0, la bande sera automatiquement bloquée à la vente ».
 *
 * 🔴 POURQUOI CETTE EXTRACTION. La règle vivait dans `SoinsVaccinsHub::saveSoin()`,
 * donc inatteignable depuis la synchronisation. Un soin administré HORS LIGNE
 * puis remonté aurait créé le registre vétérinaire **sans sa période de
 * rémanence** : la bande serait restée vendable, et le blocage sanitaire
 * n'aurait existé que pour les soins saisis au bureau. Recopier la règle dans
 * le contrôleur de synchronisation aurait produit deux implémentations d'une
 * protection sanitaire — la pire des choses à laisser diverger.
 *
 * ⚠️ LA RÉMANENCE N'EST CRÉÉE QUE SI UN PRODUIT EST NOMMÉ. Un délai sans
 * produit ne permet pas de dire de quoi la viande doit se purger ; la
 * condition est celle de l'écran d'origine, reprise telle quelle.
 */
class RecordVeterinaryCareAction
{
    /**
     * @param  array<string, mixed>  $donnees  champs du soin
     * @param  int  $remanenceJours  délai d'attente ; 0 = aucun blocage
     */
    public function execute(array $donnees, int $remanenceJours = 0): VeterinaryRecord
    {
        $soin = new VeterinaryRecord();

        // ⚠️ `id` n'est pas assignable en masse (protection contre l'écrasement
        // d'UUID) : affectation explicite pour préserver l'identifiant généré
        // côté client Flutter au moment du soin hors ligne.
        if (! empty($donnees['id'])) {
            $soin->id = $donnees['id'];
        }

        $soin->fill(collect($donnees)->except('id')->toArray());
        $soin->is_active = $donnees['is_active'] ?? true;
        $soin->save();

        if ($remanenceJours > 0 && ! empty($donnees['product_used'])) {
            $debut = $donnees['record_date'] ?? now()->toDateString();

            VeterinaryWithdrawalPeriod::create([
                'lot_id' => $donnees['lot_id'],
                'product_used' => $donnees['product_used'],
                'start_date' => $debut,
                'withdrawal_days' => $remanenceJours,
                'end_date' => Carbon::parse($debut)->addDays($remanenceJours),
            ]);
        }

        return $soin;
    }
}
