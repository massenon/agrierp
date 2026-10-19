<?php

namespace App\Services;

use App\Actions\RaiseFeedAutonomyAlertAction;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\Notification;
use App\Support\CategorieRationLapin;
use App\Support\CategorieRationPorc;

/**
 * 🔴→✅ Ticket U13 — L'ALERTE D'AUTONOMIE ALIMENTAIRE EST LEVÉE AUSSI POUR UNE FICHE REÇUE D'UN POSTE.
 *
 * Au web, `saveDay()` des fiches Lapins et Porcs lève `RaiseFeedAutonomyAlertAction` (la cloche : « Stock … bas »)
 * avec la provende théorique du jour enregistré (ticket 14.40). Une fiche saisie au poste et acceptée par
 * `/api/sync/push` ne la levait pas : la rupture annoncée au web restait muette dès que l'animalier travaillait hors
 * ligne — c'est-à-dire le plus souvent.
 *
 * ⚠️⚠️ MÊMES RÈGLES QUE LE WEB, ÉTAPE PAR ÉTAPE (et non une approximation) :
 *  - seules les fiches Lapins (`cuniculture`) et Porcs (`porciculture`) lèvent l'alerte, et seulement sur une bande
 *    que la fiche du web peut ouvrir (`getLotsProperty()` : statut `actif`, active) ;
 *  - provende du jour = Σ effectif de catégorie × ration du barème (`getProvendeCalculationProperty()`, clés stables
 *    `CategorieRationLapin` / `CategorieRationPorc`), en kg arrondis à 2 décimales ; une catégorie INCONNUE rend la
 *    provende inconnue — et l'alerte n'est pas levée (« jamais sur un 0 inventé », 15.41 / 15.42) ;
 *  - les effectifs de catégorie sont ceux du jour APRÈS enregistrement : connus seulement si la bande a une chaîne
 *    pour ce jour (`EffectifParCategorieService::etatPourJour()`, mode `chaine`) ; ce sont alors les `cat_eff_*` que
 *    la cascade (`recalculerChaine`, appelée par l'envoi comme par `saveDay`) vient d'écrire sur la fiche — le même
 *    `calculerJour` que la fiche web (« le serveur en réécrit la valeur stockée à chaque enregistrement ») ;
 *  - produit de provende et autonomie : `AutonomieAlimentaireService` (le calcul commun des deux fiches), puis
 *    `RaiseFeedAutonomyAlertAction` elle-même — même seuil, même message, même DÉDOUBLONNAGE (une alerte par
 *    produit et par jour : une fiche RENVOYÉE par un poste qui n'a pas reçu l'accusé ne crée pas une seconde alerte),
 *    même résorption (stock revenu au-dessus du seuil : les alertes ouvertes sont marquées lues).
 *
 * La parité avec le web est prouvée par `tests/Feature/AlerteAutonomieFichePosteTest.php` : la MÊME journée
 * enregistrée par le composant Livewire et envoyée par un poste produit la même notification.
 */
class AlerteAutonomieFicheService
{
    /** Espèce → [classe des rations, clé de ration par emplacement de catégorie (`repro`, `sevre`, `jeune`)]. */
    private const FICHES = [
        'cuniculture' => [CategorieRationLapin::class, [
            'repro' => CategorieRationLapin::REPRODUCTEUR,
            'sevre' => CategorieRationLapin::SOUS_MERES,
            'jeune' => CategorieRationLapin::CHAIR,
        ]],
        'porciculture' => [CategorieRationPorc::class, [
            'repro' => CategorieRationPorc::REPRODUCTEUR,
            'sevre' => CategorieRationPorc::PORCELET,
            'jeune' => CategorieRationPorc::MARCHAND,
        ]],
    ];

    /**
     * Provende théorique du jour de [fiche], en kg (`null` : inconnue, ou fiche qui ne lève pas d'alerte au web).
     */
    public function provendeDuJour(LivestockDailyEntry $fiche): ?float
    {
        $lot = $fiche->lot()->with('species')->first();
        $code = $lot?->species?->code;

        if ($lot === null || ! isset(self::FICHES[$code]) || $lot->status !== 'actif' || ! $lot->is_active) {
            return null;
        }

        $etat = app(EffectifParCategorieService::class)->etatPourJour($lot, $fiche->entry_date->format('Y-m-d'));
        if ($etat['mode'] !== 'chaine' || $etat['veille'] === null) {
            return null;
        }

        [$classe, $cles] = self::FICHES[$code];
        $rations = FeedRationStandard::where('species_code', $code)->get();
        $fraiche = $fiche->fresh();
        $total = 0;
        foreach ($cles as $emplacement => $cle) {
            $effectif = $fraiche->{'cat_eff_'.$emplacement};
            if ($effectif === null) {
                return null;
            }
            $total += (int) $effectif * $classe::ration($rations, $cle);
        }

        return round($total / 1000, 2);
    }

    /**
     * Lève (ou résorbe) l'alerte de la fiche [ficheId] acceptée d'un poste, comme `saveDay()` du web.
     */
    public function apresFicheDuPoste(string $ficheId): ?Notification
    {
        $fiche = LivestockDailyEntry::find($ficheId);
        if ($fiche === null) {
            return null;
        }

        $totalKg = $this->provendeDuJour($fiche);
        if ($totalKg === null) {
            return null;
        }

        $service = app(AutonomieAlimentaireService::class);
        $provende = $service->evaluer($service->produitProvende($fiche->lot->species->code), $totalKg);

        // Condition de `saveDay()` : provende suivie en stock, consommation connue.
        if (! ($provende['available'] ?? false) || empty($provende['product']) || ! empty($provende['inconnu'])) {
            return null;
        }

        return app(RaiseFeedAutonomyAlertAction::class)->execute($provende['product'], $totalKg);
    }
}
