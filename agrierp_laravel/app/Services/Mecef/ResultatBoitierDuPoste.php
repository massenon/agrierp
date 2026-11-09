<?php

namespace App\Services\Mecef;

use App\Models\Sale;
use App\Support\MecefEtat;
use App\Support\MecefMode;
use Carbon\Carbon;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * MECEF-2 — LE RÉSULTAT D'UNE FACTURE NORMALISÉE PAR LE BOÎTIER D'UN POSTE.
 *
 * ⚠️ NON VÉRIFIÉ AVEC UN VRAI BOÎTIER : le contrat ci-dessous est éprouvé contre le faux pilote du poste, jamais un appareil.
 *
 * En mode `boitier`, le serveur hébergé ne peut pas joindre le boîtier (`http://localhost:38917` du poste) : c'est le POSTE qui
 * transmet, puis envoie avec la vente un bloc `mecef` = `{status, qr_ref, code, nim, normalise_le, message}`. Le serveur ne croit
 * pas aveuglément ce bloc :
 *  - il n'est lu QU'EN MODE BOÎTIER (sinon ignoré : en mode e-MECeF la normalisation appartient au serveur, jamais au poste) ;
 *  - la vente doit être une facture à déclarer (`estADeclarer`), pas une facture simple ;
 *  - une vente DÉJÀ normalisée n'est JAMAIS réécrite (ni par un second envoi, ni par un autre poste) ;
 *  - `transmise` exige un `qr_ref` NON VIDE (seul fait qui prouve la certification) ; `erreur` porte un motif ;
 *  - jamais `mecef_uid` (identifiant e-MECeF), jamais l'AIB calculé, jamais un jeton : ce bloc ne les connaît pas.
 * Un bloc invalide est ignoré SANS refuser la vente (elle a eu lieu) : elle reste « en attente », le poste la retransmettra.
 */
class ResultatBoitierDuPoste
{
    /**
     * @param  array<string, mixed>  $saleData  la vente telle que le poste l'envoie
     * @return array<string, mixed>|null  le bloc validé, ou null (absent, invalide, ou mode autre que boîtier)
     */
    public function valider(array $saleData): ?array
    {
        if (! isset($saleData['mecef']) || ! is_array($saleData['mecef'])) {
            return null;
        }

        if (app(MecefReglage::class)->mode() !== MecefMode::BOITIER) {
            return null;
        }

        try {
            $bloc = Validator::make($saleData['mecef'], [
                'status' => ['required', 'in:'.MecefEtat::NORMALISEE.','.MecefEtat::REFUSEE],
                'qr_ref' => ['required_if:status,'.MecefEtat::NORMALISEE, 'nullable', 'string', 'min:1', 'max:255'],
                'code' => ['nullable', 'string', 'max:100'],
                'nim' => ['nullable', 'string', 'max:50'],
                'normalise_le' => ['nullable', 'date'],
                'message' => ['nullable', 'string', 'max:1000'],
            ])->validate();
        } catch (ValidationException) {
            return null;
        }

        if ($bloc['status'] === MecefEtat::NORMALISEE && trim((string) ($bloc['qr_ref'] ?? '')) === '') {
            return null;
        }

        return $bloc;
    }

    /**
     * Applique le bloc validé à la vente. Rend vrai si la vente a été écrite.
     *
     * @param  array<string, mixed>  $bloc
     */
    public function appliquer(Sale $vente, array $bloc): bool
    {
        if (! $vente->estADeclarer() || $vente->estNormalisee()) {
            return false;
        }

        if ($bloc['status'] === MecefEtat::NORMALISEE) {
            $vente->update([
                'mecef_status' => MecefEtat::NORMALISEE,
                'mecef_qr_ref' => trim((string) $bloc['qr_ref']),
                'mecef_code' => $bloc['code'] ?? null,
                'mecef_nim' => $bloc['nim'] ?? null,
                'mecef_normalise_le' => $this->horodatage($bloc['normalise_le'] ?? null),
                'mecef_message' => null,
            ]);

            return true;
        }

        $vente->update([
            'mecef_status' => MecefEtat::REFUSEE,
            'mecef_message' => (string) ($bloc['message'] ?? 'Facture refusée par le boîtier.'),
        ]);

        return true;
    }

    private function horodatage(mixed $date): Carbon
    {
        try {
            return $date ? Carbon::parse((string) $date) : now();
        } catch (\Throwable) {
            return now();
        }
    }
}
