<?php

namespace App\Actions;

use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Services\EffectifParCategorieService;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 14.53 (Sprint 14) — LA VENTE SE RÉPERCUTE SUR LA FICHE D'ÉLEVAGE.
 *
 * Spécification d'origine : `assets/js/agrisync-store.js` du prototype
 * (`addVente()` → `recordFicheVente()`). Vendre un sujet vivant ne décrémente
 * pas seulement le stock produit : il quitte aussi la bande.
 *
 * 🔴 POURQUOI CETTE EXTRACTION. La routine vivait en méthode PRIVÉE de
 * `PosInterface`, donc inatteignable depuis la synchronisation. Une vente
 * saisie hors ligne sur le poste Desktop puis remontée au serveur n'avait donc
 * AUCUN effet sur la fiche : l'effectif de la bande restait celui d'avant la
 * vente, indéfiniment. Recopier la routine dans le contrôleur de
 * synchronisation aurait produit deux implémentations d'une même règle — elles
 * finissent toujours par diverger, et la ferme lirait alors deux effectifs
 * différents selon le chemin qu'a pris la vente.
 *
 * ⚠️ L'EFFECTIF EST RECALCULÉ PAR `computeEffectifFinal()`, le même point de
 * vérité que les cinq fiches et que le client Flutter. Jamais une soustraction
 * écrite ici « à l'équivalent ».
 *
 * ⚠️ LA FICHE DU JOUR EST COMPLÉTÉE, JAMAIS ÉCRASÉE. Si l'animalier a déjà
 * enregistré sa journée, la vente s'ajoute à ce qu'il a saisi — `firstOrCreate`
 * puis incrément, et non un `updateOrCreate` qui remettrait morts et naissances
 * à zéro.
 *
 * ⚠️ RÈGLE D'ANNULATION, EXPLICITE DANS LE PROTOTYPE : `annulerVente()`
 * restitue le stock mais « ne retire PAS le mouvement déjà comptabilisé dans
 * les fiches d'élevage du jour ». Aucune reprise n'est donc prévue ici : c'est
 * la règle, pas un oubli.
 */
class RecordSaleOnFicheElevageAction
{
    /**
     * @param  array<int, array{lot_id: ?string, qty: int|float}>  $lignes
     *                          lignes de vente, seules celles portant une
     *                          bande étant répercutées
     * @param  array<string, true>  $fichesPortantDejaLaVente
     *                          Ticket 15.30 — clés `lot_id|AAAA-MM-JJ` des fiches REÇUES du poste
     *                          dans le même envoi : elles portent déjà la vente (le poste la
     *                          répercute localement avant d'envoyer). Pour celles-là le `vente`
     *                          n'est PAS incrémenté une seconde fois (2N) ; la bande, elle, suit
     *                          quand même l'effectif de la fiche.
     * @return int  nombre de bandes réellement mises à jour
     */
    public function execute(array $lignes, ?string $date = null, array $fichesPortantDejaLaVente = []): int
    {
        $jour = $date ?: now()->format('Y-m-d');
        $bandesTouchees = 0;

        foreach ($lignes as $ligne) {
            $lotId = $ligne['lot_id'] ?? null;
            $qty = (int) ($ligne['qty'] ?? 0);

            // Produit non lié à une bande (provende, intrant) : rien à
            // répercuter. Une quantité nulle non plus.
            if (empty($lotId) || $qty <= 0) {
                continue;
            }

            // 🔴→✅ TICKET 15.39 — bande À CHAÎNE (départ par catégorie saisi) : la fiche créée par la vente
            // naît avec ses mouvements ventilés CONNUS À ZÉRO (morts et dons du jour sont déjà à 0 ci-dessus :
            // la ventilation l'est aussi), faute de quoi des `null` « inconnu » rendraient ses catégories
            // inconnues. Bande SANS chaîne : valeurs par défaut STRICTEMENT inchangées (colonnes à null).
            $defauts = ['achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => 0];
            if (app(EffectifParCategorieService::class)->aUneChaine($lotId)) {
                $defauts += EffectifParCategorieService::MOUVEMENTS_CONNUS_A_ZERO;
            }

            $entry = $this->ficheDuJour($lotId, $jour, $defauts);

            if (! isset($fichesPortantDejaLaVente[$lotId.'|'.$jour])) {
                // 🔴→✅ TICKET S-T12 (trouvé par l'essai à plusieurs postes, graine 7, sur MariaDB) — LA FICHE EST RELUE
                // SOUS VERROU AVANT L'INCRÉMENT. Deux caisses qui vendent dans la même bande le même jour envoient en
                // même temps : chaque transaction lisait `vente` = 5 (lecture cohérente, sans verrou), écrivait 6, et la
                // seconde écrasait la première — une vente comptée ZÉRO fois sur la fiche, sans erreur (5 → 6 au lieu de
                // 7). La lecture verrouillante attend la transaction concurrente et rend la valeur à jour. (SQLite
                // sérialise tout : invisible dans la suite Feature, d'où le garde-fou qui lit ce code.)
                $entry = LivestockDailyEntry::query()->whereKey($entry->getKey())->lockForUpdate()->first() ?? $entry;
                $entry->vente = (int) $entry->vente + $qty;
                $entry->effectif_final = $entry->effectifFinalDepuis($entry->previousEffectif());
                $entry->save();
            }

            // 🔴→✅ TICKET 15.31 — RECALCUL EN CASCADE (décision client du 14/10/2026).
            // Une vente antérieure à des fiches DÉJÀ saisies change l'effectif de départ de
            // chacune d'elles : on les recalcule dans l'ordre, avec la même formule que les
            // fiches (`computeEffectifFinal`), puis la bande prend l'effectif de la DERNIÈRE
            // fiche — et non celui du jour de la vente, qui écrasait `current_quantity` avec
            // un effectif ancien (la caisse proposait alors des sujets déjà vendus).
            $this->recalculerEnCascade($lotId, $jour);

            $bandesTouchees++;
        }

        return $bandesTouchees;
    }

    /**
     * La fiche (bande, jour) que la vente met à jour — créée si elle n'existe pas.
     *
     * 🔴→✅ TICKET S-T12 (trouvé par l'essai à plusieurs postes, graine 314, sur MariaDB) — DEUX CRÉATIONS SIMULTANÉES DE
     * LA MÊME FICHE. `firstOrCreate` lit, ne trouve rien, insère : quand un poste envoie au même instant une vente (ou
     * une fiche) de la même bande pour un jour encore sans fiche, les deux transactions insèrent, et la seconde tombe sur
     * l'unicité (bande, jour) — `SQLSTATE 1062`. L'envoi d'un poste repartait en 500 (renvoyé plus tard) ; la caisse du
     * WEB, elle, affichait l'erreur et la vente était perdue. L'insertion qui heurte l'unicité relit désormais la fiche
     * que l'autre vient de créer, SOUS VERROU (une lecture cohérente ne la verrait pas encore), et la vente s'y ajoute.
     */
    private function ficheDuJour(string $lotId, string $jour, array $defauts): LivestockDailyEntry
    {
        $cle = ['lot_id' => $lotId, 'entry_date' => $jour];
        $existante = LivestockDailyEntry::where($cle)->first();
        if ($existante !== null) {
            return $existante;
        }

        try {
            return LivestockDailyEntry::create($cle + $defauts);
        } catch (UniqueConstraintViolationException) {
            return LivestockDailyEntry::where($cle)->lockForUpdate()->firstOrFail();
        }
    }

    /**
     * Recalcule l'effectif final de toutes les fiches de la bande POSTÉRIEURES au
     * jour donné, puis aligne `livestock_lots.current_quantity` sur la dernière fiche.
     *
     * ⚠️ Point de départ : l'effectif final STOCKÉ de la fiche du jour donné (ou, à défaut
     * de fiche ce jour-là, celui de la dernière fiche antérieure, ou l'effectif initial de
     * la bande — exactement `previousEffectif()`). Les mouvements saisis (achats, nés,
     * morts, ventes, dons) des jours suivants ne sont JAMAIS modifiés : seul l'effectif
     * final, qui en dérive, est recalculé.
     *
     * ⚠️ IDEMPOTENT : le résultat ne dépend que des mouvements stockés. Rejouer l'appel
     * (ou l'enchaîner avec lui-même) ne change plus rien. Une fiche dont l'effectif est
     * déjà juste n'est pas réécrite (pas d'`updated_at` inutile à resynchroniser).
     *
     * ⚠️ Ne couvre PAS `effectif_m`, `effectif_f`, `effectif_sevres` (saisies). Depuis 15.39, les
     * `cat_eff_*` sont recalculés par EffectifParCategorieService UNIQUEMENT pour une bande à chaîne
     * (départ par catégorie saisi) ; sinon ils restent des saisies.
     */
    public function recalculerEnCascade(string $lotId, string $apresDate): void
    {
        DB::transaction(function () use ($lotId, $apresDate) {
            $jour = LivestockDailyEntry::where('lot_id', $lotId)->whereDate('entry_date', $apresDate)->first();

            if ($jour !== null) {
                $courant = (int) $jour->effectif_final;
            } else {
                // Aucune fiche ce jour-là : on part de l'effectif de la veille « logique ».
                $sonde = new LivestockDailyEntry(['lot_id' => $lotId, 'entry_date' => $apresDate]);
                $courant = $sonde->previousEffectif();
            }

            $suivantes = LivestockDailyEntry::where('lot_id', $lotId)
                ->whereDate('entry_date', '>', $apresDate)
                ->orderBy('entry_date')
                ->get();

            foreach ($suivantes as $fiche) {
                // Ticket 15.46 : transferts entre bandes compris (`effectifFinalDepuis`).
                $juste = $fiche->effectifFinalDepuis($courant);

                if ((int) $fiche->effectif_final !== $juste) {
                    $fiche->effectif_final = $juste;
                    $fiche->save();
                }

                $courant = $juste;
            }

            // La bande suit la DERNIÈRE fiche, quelle que soit la date de la vente.
            $derniere = LivestockDailyEntry::where('lot_id', $lotId)->orderByDesc('entry_date')->first();

            if ($derniere !== null) {
                // 🔴→✅ TICKET 15.40 — N'ÉCRIRE QUE SI ÇA CHANGE : `Builder::update()` pose `updated_at` même quand la
                // valeur est identique ; la cascade du push des fiches (idempotente) réécrirait la bande à chaque renvoi.
                $cible = max(0, (int) $derniere->effectif_final);
                LivestockLot::whereKey($lotId)
                    ->where(fn ($q) => $q->whereNull('current_quantity')->orWhere('current_quantity', '<>', $cible))
                    ->update(['current_quantity' => $cible]);
            }

            // 🔴→✅ TICKET 15.39 — LES CATÉGORIES SUIVENT, DANS LA MÊME TRANSACTION. Les effectifs finaux
            // viennent d'être recalculés : la chaîne par catégorie (vente → Chair / Marchand) repart du
            // départ et des mouvements stockés. Sans chaîne (bande non ventilée) : aucune écriture, le
            // comportement antérieur est inchangé.
            app(EffectifParCategorieService::class)->recalculerChaine($lotId);
        });
    }
}
