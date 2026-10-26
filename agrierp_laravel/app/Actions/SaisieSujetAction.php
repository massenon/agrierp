<?php

namespace App\Actions;

use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Services\AccountingEntryService;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket BS2 — POINT DE PASSAGE UNIQUE du journal « Enregistrer des Sujets » : ajouter, modifier, archiver une entrée.
 *
 * Une entrée est UNE ORIGINE d'une fiche du jour (`livestock_daily_entries`) : Naissance → `ne`, Achat → `achat`,
 * Don → `don` (A3 : le don est une sortie, la formule le soustrait). Le journal n'a pas de table à lui : ajouter,
 * c'est AJOUTER la quantité à la colonne de la fiche (bande, jour) ; modifier, c'est la changer (quantité, origine,
 * jour) ; archiver, c'est RETIRER l'entrée (colonne remise à 0, la ligne quitte le journal ; la fiche, elle, est
 * gardée, avec ses autres colonnes). Chaque geste laisse sa ligne d'audit.
 *
 * ⚠️ LA CASCADE UNIQUE N'EST JAMAIS CONTOURNÉE. Le composant retirait Modifier / Archiver parce qu'une entrée passée
 * « romprait la cascade » : depuis A1 la cascade sait corriger un jour passé. Chaque geste écrit les colonnes, refait
 * l'effectif final de la fiche touchée, puis appelle `RecordSaleOnFicheElevageAction::recalculerEnCascade()` — jours
 * suivants recalculés, bande = dernière fiche.
 *
 * Refus (avant toute écriture, `ValidationException`, rien n'est écrit) :
 *  - `entry_date` : la date (ancienne ou nouvelle) tombe dans un exercice CLOS — décision Q3, motif R4 ;
 *  - `quantite` : l'effectif de la bande deviendrait négatif un jour (la formule le ramènerait à 0 en silence, comme
 *    pour les transferts) ;
 *  - `entry` : l'entrée n'existe plus (déjà modifiée ou archivée, au web ou depuis un poste).
 */
class SaisieSujetAction
{
    public const ORIGINES = ['Naissance' => 'ne', 'Achat' => 'achat', 'Don' => 'don'];

    public const MESSAGE_INTROUVABLE = "Cette entrée n'existe plus : elle a déjà été modifiée ou archivée.";

    public function ajouter(string $lotId, string $origine, int $quantite, string $date): LivestockDailyEntry
    {
        $date = substr($date, 0, 10);
        $this->refuserSiExerciceClos($date);

        return DB::transaction(function () use ($lotId, $origine, $quantite, $date) {
            $lot = LivestockLot::lockForUpdate()->findOrFail($lotId);
            $fiche = $this->ajouterSurLaFiche($lotId, $origine, $quantite, $date);

            $this->terminer($lot, [$date]);
            AuditLog::record('livestock_entry.recorded', 'elevage');

            return $fiche->fresh();
        });
    }

    /**
     * @param  string  $dateAncienne  jour de la ligne modifiée
     * @param  string  $origineAncienne  origine de la ligne modifiée
     */
    public function modifier(string $lotId, string $dateAncienne, string $origineAncienne, string $origine, int $quantite, string $date): LivestockDailyEntry
    {
        $dateAncienne = substr($dateAncienne, 0, 10);
        $date = substr($date, 0, 10);
        $this->refuserSiExerciceClos($dateAncienne);
        $this->refuserSiExerciceClos($date);

        return DB::transaction(function () use ($lotId, $dateAncienne, $origineAncienne, $origine, $quantite, $date) {
            $lot = LivestockLot::lockForUpdate()->findOrFail($lotId);
            $ancienne = $this->ficheAvecEntree($lotId, $dateAncienne, $origineAncienne);

            if ($dateAncienne === $date && $origineAncienne === $origine) {
                // Même cellule : la quantité REMPLACE l'ancienne (ajouter la doublerait).
                $colonne = self::ORIGINES[$origine];
                $ancienne->{$colonne} = $quantite;
                $this->enregistrerLaFiche($ancienne);
                $fiche = $ancienne;
            } else {
                $ancienne->{self::ORIGINES[$origineAncienne]} = 0;
                $this->enregistrerLaFiche($ancienne);
                $fiche = $this->ajouterSurLaFiche($lotId, $origine, $quantite, $date);
            }

            $this->terminer($lot, [$dateAncienne, $date]);
            AuditLog::record('livestock_entry.updated', 'elevage');

            return $fiche->fresh();
        });
    }

    public function archiver(string $lotId, string $date, string $origine): void
    {
        $date = substr($date, 0, 10);
        $this->refuserSiExerciceClos($date);

        DB::transaction(function () use ($lotId, $date, $origine) {
            $lot = LivestockLot::lockForUpdate()->findOrFail($lotId);
            $fiche = $this->ficheAvecEntree($lotId, $date, $origine);

            $fiche->{self::ORIGINES[$origine]} = 0;
            $this->enregistrerLaFiche($fiche);

            $this->terminer($lot, [$date]);
            AuditLog::record('livestock_entry.archived', 'elevage', null, $fiche);
        });
    }

    private function refuserSiExerciceClos(string $date): void
    {
        if ($refus = app(AccountingEntryService::class)->refusExerciceClos($date)) {
            throw ValidationException::withMessages(['entry_date' => $refus]);
        }
    }

    /** La fiche (bande, jour) dont l'origine porte une quantité > 0, sinon « entrée introuvable ». */
    private function ficheAvecEntree(string $lotId, string $date, string $origine): LivestockDailyEntry
    {
        $colonne = self::ORIGINES[$origine] ?? null;
        $fiche = $colonne === null ? null : LivestockDailyEntry::where('lot_id', $lotId)->whereDate('entry_date', $date)->first();

        if ($fiche === null || (int) $fiche->{$colonne} <= 0) {
            throw ValidationException::withMessages(['entry' => self::MESSAGE_INTROUVABLE]);
        }

        return $fiche;
    }

    /** `firstOrNew` + quantité ajoutée à la colonne de l'origine (le code historique de `saveEntry`). */
    private function ajouterSurLaFiche(string $lotId, string $origine, int $quantite, string $date): LivestockDailyEntry
    {
        $colonne = self::ORIGINES[$origine];
        $fiche = LivestockDailyEntry::firstOrNew(['lot_id' => $lotId, 'entry_date' => $date]);
        $fiche->{$colonne} = ($fiche->{$colonne} ?? 0) + $quantite;
        $this->enregistrerLaFiche($fiche);

        return $fiche;
    }

    /**
     * 🔴→✅ CORRECTIF « EFFECTIF TOTAL VIVANT » (repris de `saveEntry`) — la veille RÉELLE de la date saisie fait foi,
     * que la fiche existe ou non ; transferts entre bandes compris (15.46).
     */
    private function enregistrerLaFiche(LivestockDailyEntry $fiche): void
    {
        $fiche->effectif_final = $fiche->effectifFinalDepuis($fiche->previousEffectif());
        $fiche->save();
    }

    /**
     * Refuse tout effectif négatif à partir du premier jour touché (calcul SANS la borne à 0 de la formule), puis
     * la cascade unique : jours suivants recalculés, bande = dernière fiche. Dans la transaction du geste : un refus
     * annule tout.
     *
     * @param  array<int, string>  $jours
     */
    private function terminer(LivestockLot $lot, array $jours): void
    {
        sort($jours);
        $premier = $jours[0];

        $sonde = new LivestockDailyEntry(['lot_id' => $lot->id, 'entry_date' => $premier]);
        $courant = $sonde->previousEffectif();
        $fiches = LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', '>=', $premier)->orderBy('entry_date')->get();

        foreach ($fiches as $f) {
            $courant += (int) $f->achat + (int) $f->ne + (int) ($f->transfert_entree ?? 0)
                - ((int) $f->mort + (int) $f->vente + (int) ($f->don ?? 0) + (int) ($f->transfert_sortie ?? 0));

            if ($courant < 0) {
                throw ValidationException::withMessages(['quantite' => sprintf(
                    "Saisie refusée : l'effectif de la bande %s deviendrait négatif le %s (%d).",
                    $lot->code, Carbon::parse($f->entry_date)->format('d/m/Y'), $courant,
                )]);
            }
        }

        app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot->id, $premier);
    }
}
