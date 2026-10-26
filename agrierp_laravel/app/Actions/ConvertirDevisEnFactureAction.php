<?php

namespace App\Actions;

use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\ConversionDevisRefuseeException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Exceptions\SaleDateRefusedException;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Customer;
use App\Models\Quote;
use App\Models\Receivable;
use App\Models\Sale;
use App\Services\AccountingEntryService;
use App\Services\TvaSettingService;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Ticket DEV3 — POINT DE PASSAGE UNIQUE : « Convertir en Facture » un devis accepté (DEV-Q1 close, PRD
 * `docs/prd/devis-poste.md` § 11). Appelé par `Livewire\Ventes\Devis::convertToInvoice()` ET par la demande de
 * conversion du poste (`SyncController::pushQuoteConversions`) : mêmes règles, mêmes motifs, mêmes effets.
 *
 * ⚠️ UNE FACTURE EST UNE VENTE (`Facturation` : « chaque vente validée EST une facture », jamais de table `invoices`).
 * La facture d'un devis est donc une vente `sales` :
 *  - À CRÉDIT (`payment_mode = credit`) : un devis se facture avant d'être payé, le règlement viendra par les créances
 *    (`Receivable`, échéance +30 jours comme la caisse) ;
 *  - SANS LIGNE : un devis est une prestation libre (description + montant), jamais un produit du catalogue — d'où ni
 *    `sale_lines` (qui exige un `product_id`), ni stock, ni cascade d'effectifs ;
 *  - au TOTAL TTC du devis (HT + TVA du devis ; une exploitation non assujettie, `TvaSettingService`, est facturée au
 *    montant HT, sans TVA : le même drapeau pilote l'affichage et les écritures) ;
 *  - liée au devis par `quotes.converted_sale_id` (le devis passe à `facture`, il ne se modifie plus).
 * L'écriture SYSCOHADA (D 411 / C 701 / C 443) est passée par `RecordSaleAccountingEntryAction`, qui lit la TVA du devis
 * quand la vente n'a aucune ligne. La facture normalisée MeCeF suit le circuit NORMAL de toute vente : l'appelant
 * invoque `FacturationMecefService::facturer()` APRÈS sa transaction ; rien n'est ajouté côté DGI (D-MECEF-1).
 *
 * Règles (refus par [ConversionDevisRefuseeException], dans cet ordre, rien n'est écrit) :
 *  1. devis inconnu ; 2. déjà converti → IDEMPOTENT (rend la même facture, `deja = true`, aucune seconde pièce) ;
 *  3. devis archivé ; 4. statut autre qu'`accepte` ; 5. client absent ou archivé ; 6. devis d'un exercice CLOS
 *  (lecture seule, motif R4) ; 7. date de la facture future, dans un mois clôturé ou dans un exercice absent ou clos
 *  (`VerifySaleDateAction`, le juge de toute vente) ; 8. plan comptable incomplet (411, 701, et 443 si TVA).
 */
class ConvertirDevisEnFactureAction
{
    /** Comptes que l'écriture de la facture exige (libellés du plan SYSCOHADA du projet). */
    private const COMPTES = ['411' => 'Clients', '701' => 'Ventes de produits', '443' => 'TVA facturée'];

    /** Délai de règlement de la créance, comme la caisse (`PosInterface::enregistrerVente`). */
    private const JOURS_ECHEANCE = 30;

    /**
     * @param  Carbon|null  $le  l'instant de la facture : celui de la demande du poste (hors ligne), sinon maintenant
     * @return array{vente: Sale, deja: bool}
     *
     * @throws ConversionDevisRefuseeException
     */
    public function execute(string $devisId, ?Carbon $le = null): array
    {
        return DB::transaction(function () use ($devisId, $le) {
            $devis = Quote::lockForUpdate()->find($devisId);

            if ($devis === null) {
                throw new ConversionDevisRefuseeException('Devis introuvable.');
            }

            if ($devis->status === 'facture') {
                $vente = $devis->converted_sale_id ? Sale::find($devis->converted_sale_id) : null;

                if ($vente === null) {
                    throw new ConversionDevisRefuseeException('Ce devis est déjà facturé.');
                }

                return ['vente' => $vente, 'deja' => true];
            }

            if (! $devis->is_active) {
                throw new ConversionDevisRefuseeException('Ce devis est archivé : il ne peut pas être converti en facture.');
            }

            if ($devis->status !== 'accepte') {
                throw new ConversionDevisRefuseeException(
                    'Seul un devis accepté peut être converti en facture : celui-ci est « '
                    .(Quote::STATUTS[$devis->status] ?? $devis->status).' ».'
                );
            }

            $client = $devis->customer_id ? Customer::find($devis->customer_id) : null;

            if ($client === null) {
                throw new ConversionDevisRefuseeException('Ce devis n\'a pas de client : une facture à crédit en exige un.');
            }
            if (! $client->is_active) {
                throw new ConversionDevisRefuseeException(
                    "Le client « {$client->name} » est archivé : réactivez-le avant de facturer ce devis."
                );
            }

            // Le devis d'un exercice clos est en lecture seule (EF6) : passer à « facturé » le modifierait.
            if ($refus = app(AccountingEntryService::class)->refusExerciceClos($devis->quote_date->format('Y-m-d'))) {
                throw new ConversionDevisRefuseeException($refus);
            }

            $instant = ($le ?? now())->copy()->setTimezone(config('app.timezone'));

            try {
                app(VerifySaleDateAction::class)->execute($instant);
            } catch (SaleDateRefusedException $e) {
                throw new ConversionDevisRefuseeException(str_replace('Vente refusée', 'Facture refusée', $e->getMessage()));
            }

            $taux = app(TvaSettingService::class)->tauxPour((float) $devis->tva_rate);
            $this->exigerLePlanComptable($taux > 0);

            $total = round((float) $devis->amount * (1 + $taux / 100), 2);

            $vente = Sale::create([
                'customer_id' => $client->id,
                'payment_mode' => 'credit',
                'subtotal' => $total,
                'discount' => 0,
                'total' => $total,
                'status' => 'validee',
                'sold_at' => $instant,
                'delivery_fee' => 0,
            ]);

            $devis->update(['status' => 'facture', 'converted_sale_id' => $vente->id]);

            Receivable::create([
                'customer_id' => $client->id,
                'sale_id' => $vente->id,
                'amount' => $total,
                'amount_paid' => 0,
                'due_date' => $instant->copy()->addDays(self::JOURS_ECHEANCE),
                'status' => 'en_cours',
            ]);

            try {
                $ecriture = app(RecordSaleAccountingEntryAction::class)->execute($vente->fresh());
            } catch (NoOpenFiscalYearException|ClosedFiscalYearException $e) {
                throw new ConversionDevisRefuseeException(str_replace('Vente refusée', 'Facture refusée', VerifySaleDateAction::prefixe($e->getMessage())));
            }

            if ($ecriture === null) {
                // Jamais une facture sans sa pièce : tout est annulé avec la transaction.
                throw new ConversionDevisRefuseeException('Écriture comptable non générée : la conversion est annulée, rien n\'a été écrit.');
            }

            AuditLog::record('sale.validated', 'ventes');
            AuditLog::record('quote.invoiced', 'ventes');

            return ['vente' => $vente->fresh(), 'deja' => false];
        });
    }

    /** @throws ConversionDevisRefuseeException  un compte de l'écriture manque au plan comptable */
    private function exigerLePlanComptable(bool $avecTva): void
    {
        foreach (self::COMPTES as $code => $libelle) {
            $code = (string) $code; // une clé de tableau numérique devient un entier
            if ($code === '443' && ! $avecTva) {
                continue;
            }
            if (! ChartOfAccount::where('code', $code)->exists()) {
                throw new ConversionDevisRefuseeException(
                    "Plan comptable incomplet : le compte {$code} ({$libelle}) est introuvable. "
                    .'Complétez le plan comptable puis relancez la conversion.'
                );
            }
        }
    }
}
