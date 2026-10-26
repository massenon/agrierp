<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockTransfer;
use App\Models\User;
use App\Services\EffectifParCategorieService;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket 15.46 — TRANSFERT DE SUJETS ENTRE DEUX BANDES (A2 : écran dédié, décision client du 17/10/2026).
 *
 * Un transfert est un FAIT daté : N sujets quittent la bande source et entrent dans la bande cible le même jour.
 * Il est enregistré dans `livestock_transfers` (source de vérité), puis reporté sur la fiche du jour de chaque
 * bande (colonnes `transfert_*`, dérivées) et répercuté en cascade sur les jours suivants, par le point unique
 * `RecordSaleOnFicheElevageAction::recalculerEnCascade()`. Jamais supprimé : annulé, et les fiches suivent.
 *
 * ⚠️⚠️ CONSTITUTION DE BANDE — la correction des bandes déjà saisies. Une bande créée pour accueillir une
 * portée a un effectif INITIAL qui compte déjà ces sujets ; ils étaient encore comptés dans la bande mère (leurs
 * naissances y sont saisies). Un transfert « constitution » inscrit la SORTIE de la bande mère à la date de
 * création de la nouvelle bande, sans entrée dans la cible : chaque sujet n'est plus compté qu'une fois.
 *
 * Contrôles RÉELS, jamais d'effectif inventé :
 *  - les deux bandes existent, sont distinctes, de la même espèce et non archivées ;
 *  - la date n'est ni future ni antérieure à la création d'une des bandes ; une constitution est datée du jour
 *    de création de la bande cible et ne dépasse pas son effectif initial ;
 *  - la bande source compte assez de sujets ce jour-là ET chaque jour suivant (sinon un effectif deviendrait
 *    négatif et serait ramené à 0 en silence) ; même contrôle sur la catégorie pour une bande à chaîne ;
 *  - lapins et porcs : la catégorie transférée (Reproducteur / Sous-mères ou Porcelet / Jeune ou Marchand) est
 *    obligatoire ; elle est la même à l'arrivée (un sujet ne change pas de stade en changeant de bande).
 */
class TransferBetweenLotsAction
{
    public const CATEGORIES = ['repro', 'sevre', 'jeune'];

    /**
     * @param  array{source_lot_id: string, target_lot_id: string, transfer_date: string, quantity: int|string,
     *               categorie?: ?string, constitution?: bool, motif?: ?string}  $donnees
     */
    public function execute(array $donnees, ?User $utilisateur = null, ?string $deviceId = null, ?string $id = null): LivestockTransfer
    {
        return DB::transaction(function () use ($donnees, $utilisateur, $deviceId, $id) {
            $source = LivestockLot::with('species')->lockForUpdate()->find($donnees['source_lot_id'] ?? null);
            $cible = LivestockLot::with('species')->lockForUpdate()->find($donnees['target_lot_id'] ?? null);
            $date = Carbon::parse($donnees['transfer_date'] ?? 'now')->format('Y-m-d');
            $quantite = (int) ($donnees['quantity'] ?? 0);
            $constitution = (bool) ($donnees['constitution'] ?? false);
            $categorie = $donnees['categorie'] ?? null;
            $categorie = $categorie === '' ? null : $categorie;

            $this->verifier($source, $cible, $date, $quantite, $categorie, $constitution);

            $transfert = new LivestockTransfer();
            if ($id !== null) {
                $transfert->id = $id;
            }
            $transfert->fill([
                'source_lot_id' => $source->id,
                'target_lot_id' => $cible->id,
                'transfer_date' => $date,
                'quantity' => $quantite,
                'categorie' => $categorie,
                'constitution' => $constitution,
                'motif' => $donnees['motif'] ?? null,
                'user_id' => $utilisateur?->id,
                'device_id' => $deviceId,
                'is_active' => true,
            ]);
            $transfert->save();

            if ($constitution && $cible->lot_source_id === null) {
                $cible->lot_source_id = $source->id;
                $cible->save();
            }

            $this->reporterSurFiche($source, $date);
            $this->reporterSurFiche($cible, $date);

            return $transfert;
        });
    }

    /** Annule un transfert : il reste tracé (`is_active = false`), les deux bandes sont recalculées. */
    public function annuler(LivestockTransfer $transfert): void
    {
        DB::transaction(function () use ($transfert) {
            if (! $transfert->is_active) {
                return;
            }

            $source = LivestockLot::with('species')->lockForUpdate()->findOrFail($transfert->source_lot_id);
            $cible = LivestockLot::with('species')->lockForUpdate()->findOrFail($transfert->target_lot_id);
            $date = $transfert->transfer_date->format('Y-m-d');

            // Retirer l'entrée de la cible ne doit pas rendre son effectif négatif (sujets déjà vendus, morts…).
            if (! $transfert->constitution) {
                $this->verifierDisponible($cible, $date, (int) $transfert->quantity, $transfert->categorie, 'la bande '.$cible->code);
            }

            $transfert->is_active = false;
            $transfert->save();
            AuditLog::record('livestock_transfer.cancelled', 'elevage', null, $transfert);

            if ($transfert->constitution && $cible->lot_source_id === $source->id
                && ! LivestockTransfer::actifs()->where('target_lot_id', $cible->id)->where('constitution', true)->exists()) {
                $cible->lot_source_id = null;
                $cible->save();
            }

            $this->reporterSurFiche($source, $date);
            $this->reporterSurFiche($cible, $date);
        });
    }

    /**
     * Reporte sur la fiche (bande, jour) la somme des transferts ACTIFS de ce jour, puis recalcule l'effectif du
     * jour et la cascade. Crée la fiche si un transfert existe et qu'aucune fiche n'a été saisie ce jour-là.
     */
    public function reporterSurFiche(LivestockLot $lot, string $date): void
    {
        $sorties = LivestockTransfer::actifs()->where('source_lot_id', $lot->id)->whereDate('transfer_date', $date)->get();
        $entrees = LivestockTransfer::actifs()->where('target_lot_id', $lot->id)->where('constitution', false)
            ->whereDate('transfer_date', $date)->get();

        $colonnes = [
            'transfert_entree' => (int) $entrees->sum('quantity'),
            'transfert_sortie' => (int) $sorties->sum('quantity'),
        ];
        foreach (self::CATEGORIES as $cat) {
            $colonnes["transfert_entree_{$cat}"] = (int) $entrees->where('categorie', $cat)->sum('quantity');
            $colonnes["transfert_sortie_{$cat}"] = (int) $sorties->where('categorie', $cat)->sum('quantity');
        }

        $fiche = LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', $date)->first();

        if ($fiche === null) {
            if (array_sum($colonnes) === 0) {
                return;
            }

            $fiche = new LivestockDailyEntry(['lot_id' => $lot->id, 'entry_date' => $date]);
            $fiche->fill(['achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0]);
            $fiche->setRelation('lot', $lot);

            $service = app(EffectifParCategorieService::class);
            if (EffectifParCategorieService::especeDuLot($lot) !== null) {
                $fiche->fill(EffectifParCategorieService::MOUVEMENTS_CONNUS_A_ZERO);

                // Première fiche d'une bande à catégories : le départ est DÉDUIT du stade (même règle que les fiches
                // Lapins et Porcs, `departDepuisStade`), pour que les catégories du transfert soient calculables.
                if (! $service->aUneChaine($lot->id)) {
                    $depart = EffectifParCategorieService::departDepuisStade($lot, $fiche->previousEffectif());
                    if ($depart !== null) {
                        $fiche->fill([
                            'cat_depart_repro' => $depart['repro'],
                            'cat_depart_sevre' => $depart['sevre'],
                            'cat_depart_jeune' => $depart['jeune'],
                        ]);
                    }
                }
            }
        }

        foreach ($colonnes as $colonne => $valeur) {
            $fiche->{$colonne} = $valeur;
        }
        $fiche->effectif_final = $fiche->effectifFinalDepuis($fiche->previousEffectif());
        $fiche->save();

        app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot->id, $date);
    }

    private function verifier(?LivestockLot $source, ?LivestockLot $cible, string $date, int $quantite, ?string $categorie, bool $constitution): void
    {
        $refus = fn (string $message) => throw ValidationException::withMessages(['transfert' => $message]);

        if ($source === null || $cible === null) {
            $refus('Bande source ou bande cible introuvable.');
        }
        if ($source->id === $cible->id) {
            $refus('La bande source et la bande cible doivent être différentes.');
        }
        if ($source->species_id !== $cible->species_id) {
            $refus("Les deux bandes doivent être de la même espèce ({$source->code} et {$cible->code} ne le sont pas).");
        }
        if (! $source->is_active || ! $cible->is_active) {
            $refus('Une bande archivée ne peut ni céder ni recevoir de sujets.');
        }
        if ($quantite < 1) {
            $refus('Le nombre de sujets transférés doit être au moins 1.');
        }
        if ($date > now()->format('Y-m-d')) {
            $refus('Un transfert ne peut pas être daté dans le futur.');
        }
        foreach ([$source, $cible] as $lot) {
            if ($lot->created_date !== null && $date < $lot->created_date->format('Y-m-d')) {
                $refus("Le transfert est antérieur à la création de la bande {$lot->code} ({$lot->created_date->format('d/m/Y')}).");
            }
        }

        $aCategories = EffectifParCategorieService::especeDuLot($source) !== null;
        if ($aCategories && ! in_array($categorie, self::CATEGORIES, true)) {
            $refus('Lapins et porcs : précisez la catégorie des sujets transférés.');
        }
        if (! $aCategories && $categorie !== null) {
            $refus("Cette espèce n'est pas suivie par catégorie : aucune catégorie ne doit être choisie.");
        }

        if ($constitution) {
            if ($cible->created_date === null || $date !== $cible->created_date->format('Y-m-d')) {
                $refus('Une constitution de bande est datée du jour de création de la bande cible ('
                    .($cible->created_date?->format('d/m/Y') ?? 'inconnu').').');
            }
            $dejaRattaches = (int) LivestockTransfer::actifs()->where('target_lot_id', $cible->id)->where('constitution', true)->sum('quantity');
            if ($dejaRattaches + $quantite > (int) $cible->initial_quantity) {
                $refus("La bande {$cible->code} a été créée avec {$cible->initial_quantity} sujet(s) ; "
                    ."{$dejaRattaches} sont déjà rattachés à leur bande d'origine. Impossible d'en rattacher {$quantite} de plus.");
            }
        }

        $this->verifierDisponible($source, $date, $quantite, $categorie, 'la bande source '.$source->code);
    }

    /**
     * La bande compte-t-elle au moins `$quantite` sujets (et dans la catégorie, si sa chaîne est connue) à la fin du
     * jour et chaque jour suivant ? Sinon le retrait rendrait un effectif négatif.
     */
    private function verifierDisponible(LivestockLot $lot, string $date, int $quantite, ?string $categorie, string $libelle): void
    {
        $fiches = LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', '>=', $date)->orderBy('entry_date')->get();

        $duJour = $fiches->first(fn ($f) => $f->entry_date->format('Y-m-d') === $date);
        if ($duJour === null) {
            $sonde = new LivestockDailyEntry(['lot_id' => $lot->id, 'entry_date' => $date]);
            $sonde->setRelation('lot', $lot);
            $points = [[$date, $sonde->previousEffectif()]];
        } else {
            $points = [];
        }
        foreach ($fiches as $f) {
            $points[] = [$f->entry_date->format('Y-m-d'), (int) $f->effectif_final];
        }

        foreach ($points as [$jour, $effectif]) {
            if ($effectif < $quantite) {
                throw ValidationException::withMessages(['transfert' => sprintf(
                    'Transfert refusé : %s ne compte que %d sujet(s) le %s, moins que les %d à transférer.',
                    $libelle, $effectif, Carbon::parse($jour)->format('d/m/Y'), $quantite,
                )]);
            }
        }

        if ($categorie === null) {
            return;
        }

        $etat = app(EffectifParCategorieService::class)->etatPourJour($lot, $date);
        if ($etat['mode'] !== 'chaine') {
            return;
        }

        $libellesCategories = ['repro' => 'Reproducteur', 'sevre' => $this->libelleSevre($lot), 'jeune' => $this->libelleJeune($lot)];
        $parJour = [];
        if ($duJour === null && $etat['veille'][$categorie] !== null) {
            $parJour[] = [$date, (int) $etat['veille'][$categorie]];
        }
        foreach ($fiches as $f) {
            $valeur = $f->{"cat_eff_{$categorie}"};
            if ($valeur !== null) {
                $parJour[] = [$f->entry_date->format('Y-m-d'), (int) $valeur];
            }
        }

        foreach ($parJour as [$jour, $effectif]) {
            if ($effectif < $quantite) {
                throw ValidationException::withMessages(['transfert' => sprintf(
                    'Transfert refusé : %s ne compte que %d %s le %s, moins que les %d à transférer.',
                    $libelle, $effectif, $libellesCategories[$categorie], Carbon::parse($jour)->format('d/m/Y'), $quantite,
                )]);
            }
        }
    }

    private function libelleSevre(LivestockLot $lot): string
    {
        return EffectifParCategorieService::especeDuLot($lot) === EffectifParCategorieService::PORCS ? 'Porcelet' : 'Sous-mères';
    }

    private function libelleJeune(LivestockLot $lot): string
    {
        return EffectifParCategorieService::especeDuLot($lot) === EffectifParCategorieService::PORCS ? 'Porc Marchand' : 'Jeune';
    }
}
