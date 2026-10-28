<?php

namespace App\Services;

use App\Actions\RecordSettlementAccountingEntryAction;
use App\Models\AdvanceImputation;
use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\Receivable;
use App\Models\TreasuryAccount;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Ticket 15.19 — AVANCES CLIENTS : UNE SEULE IMPLÉMENTATION, pour la page web
 * « Historique des Avances » ET pour `/api/sync/push`.
 *
 * Avant ce ticket, la page web faisait trois choses fausses et le poste en aurait fait une quatrième :
 *   - une avance « enregistrée » n'entrait NI dans un compte de trésorerie NI au grand livre :
 *     l'argent d'un acompte n'existait nulle part (D2) ;
 *   - l'imputation réduisait la créance sans aucune écriture : 411 restait débité alors que la
 *     créance était payée (D3) ;
 *   - rien n'empêchait d'archiver une avance qui avait encore un reste, ni de changer le montant
 *     d'une avance déjà entamée (D4, D5).
 *
 * ⚠️⚠️ CE QUE FONT LES DEUX OPÉRATIONS
 *   recevoir : avance + trésorerie (compte choisi, +montant) + écriture Débit 5xx / Crédit 419,
 *              datée du jour de l'ENCAISSEMENT, dans UNE transaction. Les DEUX livres de
 *              trésorerie (solde du compte ET classe 5) bougent ensemble ou pas du tout.
 *   imputer  : avance.amount_used et créance.amount_paid montent de la part IMPUTÉE, plus
 *              une écriture Débit 419 / Crédit 411 SANS trésorerie (l'argent est déjà entré à la
 *              réception). Jamais d'écriture à zéro.
 *
 * ⚠️ `receivables.amount_paid` ne change, pour une imputation, QUE par `imputer()` : un test
 * lit le code source pour le verrouiller.
 *
 * ⚠️ IDEMPOTENCE PAR `id` DU POSTE. Un renvoi dont l'accusé s'est perdu est un ACQUITTEMENT, jamais un
 * rejeu : sinon l'argent entrerait deux fois en caisse, ou l'avance serait entamée deux fois. Le
 * contrôle précède toute validation : un renvoi acquitté doit le rester même si, entre-temps,
 * l'exercice a été clos.
 *
 * ⚠️ PROPOSITIONS COMPTABLES (419, schémas D 5xx/C 419 et D 419/C 411) À FAIRE VALIDER PAR LE
 * CABINET FAGUEZ.
 */
class CustomerAdvanceService
{
    /**
     * Modes de paiement acceptés. Ceux de la maquette `historique-avances.html` (Espèces, MTN
     * Mobile Money, Moov Money, Chèque) : les deux opérateurs mobiles se confondent en
     * `mobile_money` ; `virement` est le mode bancaire déjà connu des ventes.
     */
    public const MODES_PAIEMENT = ['especes', 'mobile_money', 'virement', 'cheque'];

    /**
     * Reçoit une avance : la crée, fait entrer l'argent en trésorerie et passe l'écriture.
     *
     * @param  string|null  $id  UUID du poste, conservé tel quel ; null = page web (UUID généré)
     */
    public function recevoir(
        string $customerId,
        float $montant,
        string $tresorerieId,
        ?string $date = null,
        ?string $paymentMode = null,
        ?string $motif = null,
        ?string $id = null,
        ?string $deviceId = null,
    ): CustomerAdvance {
        if ($id !== null && ($existante = CustomerAdvance::find($id)) !== null) {
            return $existante;   // renvoi : acquittement, rien n'est rejoué
        }

        $montant = round($montant, 2);

        if ($montant <= 0) {
            throw ValidationException::withMessages(['amount' => "Le montant de l'avance doit être supérieur à zéro."]);
        }

        if ($paymentMode !== null && ! in_array($paymentMode, self::MODES_PAIEMENT, true)) {
            throw ValidationException::withMessages(['payment_mode' => 'Mode de paiement inconnu.']);
        }

        $date ??= now()->toDateString();

        try {
            return DB::transaction(function () use ($customerId, $montant, $tresorerieId, $date, $paymentMode, $motif, $id, $deviceId) {
                $client = Customer::find($customerId);

                if (! $client) {
                    throw ValidationException::withMessages(['customer_id' => 'Client introuvable.']);
                }

                $tresorerie = TreasuryAccount::find($tresorerieId);

                if (! $tresorerie) {
                    throw ValidationException::withMessages(['treasury_account_id' => 'Compte de trésorerie introuvable.']);
                }

                $avance = new CustomerAdvance();

                if ($id !== null) {
                    $avance->id = $id;
                }

                $avance->fill([
                    'customer_id' => $client->id,
                    'treasury_account_id' => $tresorerie->id,
                    'amount' => $montant,
                    'amount_used' => 0,
                    'advance_date' => $date,
                    'payment_mode' => $paymentMode,
                    'motif' => $motif !== null ? mb_substr($motif, 0, 255) : null,
                    'device_id' => $deviceId,
                    'is_active' => true,
                ]);
                $avance->save();

                $tresorerie->increment('balance', $montant);

                $ecriture = app(RecordSettlementAccountingEntryAction::class)->receiveCustomerAdvance(
                    $tresorerie->fresh(), $montant, $client->name, $avance->id, $date
                );

                // ⚠️ Jamais d'argent encaissé sans écriture : si le plan comptable ne permet pas
                // de la passer, tout est annulé et le motif est rendu.
                if ($ecriture === null) {
                    throw ValidationException::withMessages([
                        'treasury_account_id' => "Écriture impossible : le compte 419 (avances et acomptes reçus) est absent du plan comptable, ou ce compte de trésorerie n'a pas de compte comptable.",
                    ]);
                }

                AuditLog::record('customer_advance.created', 'ventes');

                return $avance->fresh();
            });
        } catch (UniqueConstraintViolationException $e) {
            // Deux envois simultanés du même `id` : l'autre a gagné, celui-ci est un renvoi.
            if ($id !== null && ($existante = CustomerAdvance::find($id)) !== null) {
                return $existante;
            }

            throw $e;
        }
    }

    /**
     * Impute une avance sur une créance, plafonnée à min(montant demandé, reste de l'avance, solde
     * de la créance).
     *
     * @param  string|null  $imputationId  UUID du poste ; null = page web (UUID généré)
     * @return float part RÉELLEMENT imputée
     */
    public function imputer(
        string $advanceId,
        string $receivableId,
        float $montant,
        ?string $date = null,
        ?string $imputationId = null,
        ?string $deviceId = null,
    ): float {
        if ($imputationId !== null && ($deja = AdvanceImputation::find($imputationId)) !== null) {
            return (float) $deja->applied_amount;   // renvoi : acquittement, rien n'est rejoué
        }

        $montant = round($montant, 2);

        if ($montant <= 0) {
            throw ValidationException::withMessages(['amount' => "Le montant à imputer doit être supérieur à zéro."]);
        }

        $date ??= now()->toDateString();

        try {
            return DB::transaction(function () use ($advanceId, $receivableId, $montant, $date, $imputationId, $deviceId) {
                $avance = CustomerAdvance::lockForUpdate()->find($advanceId);

                if (! $avance) {
                    throw ValidationException::withMessages(['customer_advance_id' => 'Avance introuvable.']);
                }

                $creance = Receivable::lockForUpdate()->find($receivableId);

                if (! $creance) {
                    throw ValidationException::withMessages(['receivable_id' => 'Créance introuvable.']);
                }

                if (! $avance->is_active) {
                    throw ValidationException::withMessages(['customer_advance_id' => 'Cette avance est archivée.']);
                }

                // ⚠️ Une avance ne solde que les créances de SON client : le poste pourrait en
                // viser une autre par erreur, et la page web ne propose que celles du client.
                if ($creance->customer_id !== $avance->customer_id) {
                    throw ValidationException::withMessages(['receivable_id' => "Cette créance n'appartient pas au client de l'avance."]);
                }

                if ($avance->remaining <= 0) {
                    throw ValidationException::withMessages(['customer_advance_id' => 'Cette avance est déjà entièrement imputée : rien à imputer.']);
                }

                if ($creance->balance <= 0) {
                    throw ValidationException::withMessages(['receivable_id' => 'Cette créance est déjà soldée : rien à imputer.']);
                }

                $applique = round(min($montant, $avance->remaining, $creance->balance), 2);

                $avance->update(['amount_used' => round((float) $avance->amount_used + $applique, 2)]);
                $creance->update(['amount_paid' => round((float) $creance->amount_paid + $applique, 2)]);

                $imputation = new AdvanceImputation();
                $imputation->id = $imputationId ?? (string) Str::uuid();
                $imputation->fill([
                    'customer_advance_id' => $avance->id,
                    'receivable_id' => $creance->id,
                    'amount' => $montant,
                    'applied_amount' => $applique,
                    'imputation_date' => $date,
                    'device_id' => $deviceId,
                ]);
                $imputation->save();

                $ecriture = app(RecordSettlementAccountingEntryAction::class)->applyCustomerAdvance(
                    $applique, $avance->customer?->name, $imputation->id, $date
                );

                if ($ecriture === null) {
                    throw ValidationException::withMessages([
                        'receivable_id' => "Écriture impossible : le compte 419 (avances et acomptes reçus) ou 411 (clients) est absent du plan comptable.",
                    ]);
                }

                AuditLog::record('customer_advance.imputed', 'ventes');

                return $applique;
            });
        } catch (UniqueConstraintViolationException $e) {
            if ($imputationId !== null && ($deja = AdvanceImputation::find($imputationId)) !== null) {
                return (float) $deja->applied_amount;
            }

            throw $e;
        }
    }

    /**
     * Modifie une avance (page web). D4 : le MONTANT d'une avance entamée ou comptabilisée est
     * figé. Par conséquence directe, le client d'une telle avance l'est aussi (les imputations et
     * l'écriture lui sont rattachées) et la date d'une avance comptabilisée (l'écriture est datée
     * du jour de l'encaissement).
     */
    public function modifier(CustomerAdvance $avance, string $customerId, float $montant, string $date): CustomerAdvance
    {
        // VC-4 : une avance archivée ne se modifie plus (jamais de réactivation, ni au web ni au poste).
        if (! $avance->is_active) {
            throw ValidationException::withMessages(['advance' => 'Cette avance est archivée : elle ne peut plus être modifiée.']);
        }

        $montant = round($montant, 2);
        $figee = $avance->estEntamee() || $avance->estComptabilisee();
        $raison = $avance->estEntamee() ? 'déjà entamée' : 'déjà comptabilisée';

        if ($figee && abs($montant - (float) $avance->amount) >= 0.01) {
            throw ValidationException::withMessages([
                'amount' => "Le montant d'une avance {$raison} ne peut plus être modifié.",
            ]);
        }

        if ($figee && $customerId !== $avance->customer_id) {
            throw ValidationException::withMessages([
                'customerId' => "Le client d'une avance {$raison} ne peut plus être modifié.",
            ]);
        }

        if ($avance->estComptabilisee() && $date !== $avance->advance_date->format('Y-m-d')) {
            throw ValidationException::withMessages([
                'advanceDate' => "La date d'une avance comptabilisée ne peut plus être modifiée : l'écriture est datée du jour de l'encaissement.",
            ]);
        }

        $avance->update(['customer_id' => $customerId, 'amount' => $montant, 'advance_date' => $date]);
        AuditLog::record('customer_advance.updated', 'ventes');

        return $avance->fresh();
    }

    /**
     * Archive une avance (archivage logique). D5 : refusé tant qu'il reste quelque chose à
     * imputer — archiver une avance non soldée la ferait disparaître des listes alors que la ferme
     * doit encore ce montant au client (et que 419 le porte au passif).
     */
    public function archiver(CustomerAdvance $avance): void
    {
        if ($avance->remaining > 0) {
            throw ValidationException::withMessages([
                'advance' => 'Cette avance a encore un reste de '.number_format($avance->remaining, 0, ',', ' ').' FCFA : imputez-la avant de l\'archiver.',
            ]);
        }

        $avance->update(['is_active' => false]);
        AuditLog::record('customer_advance.archived', 'ventes', null, $avance);
    }

    /**
     * VC-4 — LA LIGNE D'UNE AVANCE DÉJÀ CONNUE, REÇUE D'UN POSTE : modification des champs permis
     * (client, montant, date : mêmes refus que la page web via `modifier()`) ou archivage
     * (`$active` faux : mêmes refus que `archiver()`). JAMAIS de réactivation.
     *
     * Une ligne identique à celle du serveur, ou une avance déjà archivée qu'on demande d'archiver,
     * est un ACQUITTEMENT : rien n'est réécrit, rien n'est journalisé. Le contrôle se fait sous
     * verrou : une imputation simultanée ne passe pas entre la lecture du reste et l'archivage.
     *
     * @return bool vrai si quelque chose a été écrit
     */
    public function appliquerDuPoste(string $id, string $customerId, float $montant, string $date, bool $active): bool
    {
        return DB::transaction(function () use ($id, $customerId, $montant, $date, $active) {
            $avance = CustomerAdvance::lockForUpdate()->find($id);

            if (! $avance) {
                throw ValidationException::withMessages(['customer_advance_id' => 'Avance introuvable.']);
            }

            if (! $active) {
                if (! $avance->is_active) {
                    return false;   // déjà archivée : acquittement
                }

                $this->archiver($avance);

                return true;
            }

            if (! $avance->is_active) {
                throw ValidationException::withMessages(['advance' => 'Cette avance est archivée : elle ne peut pas être rouverte ni modifiée.']);
            }

            $montant = round($montant, 2);

            if ($montant < 1) {
                throw ValidationException::withMessages(['amount' => 'Le montant doit être au moins 1 FCFA.']);
            }

            $identique = $customerId === $avance->customer_id
                && abs($montant - (float) $avance->amount) < 0.01
                && $date === $avance->advance_date->format('Y-m-d');

            if ($identique) {
                return false;
            }

            if (! Customer::whereKey($customerId)->exists()) {
                throw ValidationException::withMessages(['customerId' => 'Client introuvable.']);
            }

            $this->modifier($avance, $customerId, $montant, $date);

            return true;
        });
    }
}
