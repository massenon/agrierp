<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\IncomeTaxBracket;
use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Ticket PA-7 — POINT DE PASSAGE UNIQUE DU BARÈME ITS (cohérence des tranches, verrou après première édition, remplacement).
 *
 * Appelé par `Parametres\BaremeIts` (le web) ET par l'envoi du poste (`SyncController::pushSettingsRequests`, type `bareme_its`).
 * Un barème troué ou chevauchant produit un impôt faux SANS lever d'erreur : chaque contrôle correspond à une manière réelle
 * de se tromper (voir le composant web pour le raisonnement d'origine, ticket 14.39).
 */
class BaremeItsService
{
    /** @param array<int, array{from: mixed, to: mixed, rate: mixed}> $tranches */
    public function verifierCoherence(array $tranches): ?string
    {
        if (empty($tranches)) {
            return 'Le barème doit comporter au moins une tranche.';
        }

        $tranches = collect($tranches)
            ->map(fn ($t) => [
                'from' => (float) $t['from'],
                'to' => $t['to'] === null || $t['to'] === '' ? null : (float) $t['to'],
                'rate' => (float) $t['rate'],
            ])
            ->sortBy('from')
            ->values();

        if ($tranches->first()['from'] != 0.0) {
            return 'La première tranche doit partir de 0 : sans elle, les revenus les plus bas ne seraient couverts par aucune tranche.';
        }

        foreach ($tranches as $i => $tranche) {
            if ($tranche['rate'] < 0 || $tranche['rate'] > 100) {
                return 'Un taux doit être compris entre 0 et 100 %.';
            }

            if ($i === $tranches->count() - 1) {
                if ($tranche['to'] !== null) {
                    return 'La dernière tranche doit être ouverte (sans plafond) : sinon les revenus au-delà ne seraient pas imposés du tout.';
                }

                continue;
            }

            if ($tranche['to'] === null) {
                return 'Seule la dernière tranche peut être sans plafond.';
            }

            if ($tranche['to'] <= $tranche['from']) {
                return 'Le plafond d\'une tranche doit être supérieur à son plancher.';
            }

            if ((float) $tranches[$i + 1]['from'] !== (float) $tranche['to']) {
                return 'Les tranches doivent se suivre sans trou ni chevauchement : la tranche suivante doit commencer exactement à '
                    .number_format($tranche['to'], 0, ',', ' ').' FCFA.';
            }
        }

        return null;
    }

    /**
     * Remplace le barème. Refuse (ValidationException, clé `tranches`) si le paramétrage est arrêté et que l'auteur n'est pas
     * administrateur, ou si les tranches sont incohérentes.
     *
     * @param array<int, array{from: mixed, to: mixed, rate: mixed}> $tranches
     */
    public function remplacer(array $tranches, ?User $auteur): void
    {
        $settings = CompanySetting::current();

        if (! $settings->payrollSettingsEditableBy($auteur)) {
            throw ValidationException::withMessages(['tranches' => 'Le barème a déjà été arrêté le '
                .$settings->payroll_settings_edited_at?->format('d/m/Y à H:i')
                .'. Seul un administrateur peut le modifier.']);
        }

        if (($erreur = $this->verifierCoherence($tranches)) !== null) {
            throw ValidationException::withMessages(['tranches' => $erreur]);
        }

        IncomeTaxBracket::query()->delete();

        foreach ($tranches as $tranche) {
            IncomeTaxBracket::create([
                'from_amount' => (float) $tranche['from'],
                'to_amount' => $tranche['to'] === null || $tranche['to'] === '' ? null : (float) $tranche['to'],
                'rate' => (float) $tranche['rate'],
                'is_active' => true,
            ]);
        }

        $settings->markPayrollSettingsEdited($auteur);

        AuditLog::record('payroll.brackets_updated', 'parametres');
    }
}
