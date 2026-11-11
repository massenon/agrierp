<?php

namespace App\Actions\CloturesCaisse;

use App\Models\AuditLog;
use App\Models\CashClosure;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\Sale;
use App\Services\AccountingEntryService;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Sprint C — VALIDER LA CLÔTURE DE CAISSE.
 *
 * Point de passage unique partagé par le Livewire ClotureCaisse (web) et le
 * SyncController (poste). Toute clôture — d'où qu'elle vienne — passe ici.
 *
 * Règles métier :
 *   - Exercice non clôturé requis.
 *   - Une seule clôture par jour par poste (null = web).
 *   - ecart = montant_compte − (fond_de_caisse + ventes_especes + ventes_mobile_money + ventes_virement)
 *   - ecart > 0 → gain : D 571 / C 718  (comptes SYSCOHADA)
 *   - ecart < 0 → perte : D 658 / C 571
 *   - ecart = 0 → pas d'écriture
 *
 * @throws ValidationException
 */
class ValiderClotureCaisseAction
{
    public function __construct(
        private readonly AccountingEntryService $comptabilite,
    ) {}

    /**
     * @param  string  $closureDate  Format YYYY-MM-DD
     * @param  float   $fondDeCaisse  Monnaie de fond disponible en début de journée
     * @param  float   $montantCompte Montant physiquement compté dans la caisse en fin de journée
     * @param  int     $userId        Utilisateur qui valide
     * @param  string|null $deviceId  Identifiant du poste (null = web)
     * @return CashClosure
     *
     * @throws ValidationException
     */
    public function execute(
        string   $closureDate,
        float    $fondDeCaisse,
        float    $montantCompte,
        int      $userId,
        ?string  $deviceId = null,
    ): CashClosure {
        // 1. Exercice ouvert pour cette date.
        $exercice = FiscalYear::where('start_date', '<=', $closureDate)
            ->where('end_date', '>=', $closureDate)
            ->where('status', 'active')
            ->first();

        if (! $exercice) {
            throw ValidationException::withMessages([
                'closure_date' => 'Aucun exercice ouvert ne couvre cette date.',
            ]);
        }

        // 2. Pas de double clôture le même jour sur le même poste.
        $dejaFaite = CashClosure::where('closure_date', $closureDate)
            ->where('device_id', $deviceId)
            ->whereIn('statut', ['en_cours', 'validée'])
            ->exists();

        if ($dejaFaite) {
            throw ValidationException::withMessages([
                'closure_date' => 'Une clôture de caisse a déjà été effectuée pour cette date.',
            ]);
        }

        // 3. Totaux des ventes du jour par mode de paiement.
        $query = Sale::whereDate('sold_at', $closureDate)
            ->where('status', '!=', 'annulee');

        if ($deviceId !== null) {
            $query->where('device_id', $deviceId);
        }

        $ventesEspeces      = (float) (clone $query)->where('payment_mode', 'especes')->sum('total');
        $ventesMobileMoney  = (float) (clone $query)->where('payment_mode', 'mobile_money')->sum('total');
        $ventesVirement     = (float) (clone $query)->where('payment_mode', 'virement')->sum('total');

        // 4. Calcul de l'écart.
        $ecart = $montantCompte - ($fondDeCaisse + $ventesEspeces + $ventesMobileMoney + $ventesVirement);
        $ecart = round($ecart, 2);

        return DB::transaction(function () use (
            $exercice, $closureDate, $deviceId, $fondDeCaisse, $montantCompte, $ecart,
            $ventesEspeces, $ventesMobileMoney, $ventesVirement, $userId,
        ) {
            // 5. Écriture SYSCOHADA si l'écart n'est pas nul.
            $entryId = null;

            if ($ecart !== 0.0) {
                $compte571 = ChartOfAccount::where('code', '571')->first();
                $reference = 'CLOT-CAISSE-' . str_replace('-', '', $closureDate);

                if ($ecart > 0) {
                    // Gain : D 571 / C 718
                    $compte718 = ChartOfAccount::where('code', '718')->first();
                    $entry = $this->comptabilite->record(
                        lines: [
                            ['account_id' => $compte571?->id, 'account_code' => '571', 'debit' => $ecart, 'credit' => 0, 'label' => 'Excédent de caisse'],
                            ['account_id' => $compte718?->id, 'account_code' => '718', 'debit' => 0, 'credit' => $ecart, 'label' => 'Excédent de caisse'],
                        ],
                        entryDate: $closureDate,
                        reference: $reference,
                        sourceType: 'cash_closure',
                        sourceId: null,
                    );
                } else {
                    // Perte : D 658 / C 571
                    $perte = abs($ecart);
                    $compte658 = ChartOfAccount::where('code', '658')->first();
                    $entry = $this->comptabilite->record(
                        lines: [
                            ['account_id' => $compte658?->id, 'account_code' => '658', 'debit' => $perte, 'credit' => 0, 'label' => 'Déficit de caisse'],
                            ['account_id' => $compte571?->id, 'account_code' => '571', 'debit' => 0, 'credit' => $perte, 'label' => 'Déficit de caisse'],
                        ],
                        entryDate: $closureDate,
                        reference: $reference,
                        sourceType: 'cash_closure',
                        sourceId: null,
                    );
                }

                $entryId = $entry->id;
            }

            // 6. Enregistrement de la clôture.
            $cloture = CashClosure::create([
                'fiscal_year_id'      => $exercice->id,
                'closure_date'        => $closureDate,
                'device_id'           => $deviceId,
                'ventes_especes'      => $ventesEspeces,
                'ventes_mobile_money' => $ventesMobileMoney,
                'ventes_virement'     => $ventesVirement,
                'fond_de_caisse'      => $fondDeCaisse,
                'montant_compte'      => $montantCompte,
                'ecart'               => $ecart,
                'statut'              => 'validée',
                'accounting_entry_id' => $entryId,
                'created_by'          => $userId,
            ]);

            AuditLog::record('cloture_caisse.validée', 'ventes', $userId, $cloture);

            return $cloture;
        });
    }
}
