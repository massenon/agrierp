<?php

namespace App\Services;

use App\Actions\AdjustStockAction;
use App\Actions\RecordCreditNoteAccountingEntryAction;
use App\Exceptions\AvoirClientRefuseException;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\CreditNote;
use App\Models\Product;
use App\Models\Sale;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket AV1 — LE RETOUR D'UNE VENTE ET SON AVOIR, UN SEUL POINT DE PASSAGE.
 *
 * Appelé par `Livewire\Ventes\RetoursAvoirs::saveReturn()` (formulaire « Nouveau Retour » du web) ET par
 * `SyncController::pushCreditNotes()` (demande de retour saisie sur un poste hors ligne) : les deux produisent le même
 * avoir, avec les mêmes refus, les mêmes effets et le même message. Une seconde implémentation côté synchronisation
 * ferait diverger deux règles de retour (Doctrine de portage, article 5).
 *
 * 🔴→✅ TROIS REFUS QUE LE WEB N'AVAIT PAS (le web est le maître : le critère est construit ici d'abord, le poste le
 * reprend) :
 *  1. **Quantité au-delà du vendu.** `saveReturn()` n'exigeait que `qty ≥ 0,01` : un retour de 50 plaquettes sur une
 *     vente de 10 rentrait 50 au stock et passait 50 plaquettes de chiffre d'affaires en avoir. Le retournable d'un
 *     produit sur une vente est « vendu − déjà retourné » (tous avoirs confondus, réintégrés ou réformés).
 *  2. **Montant au-delà de la ligne.** Le montant reste SAISISSABLE (retour partiel, avoir commercial inférieur au prix
 *     payé) mais ne dépasse pas « montant de la ligne − déjà crédité ».
 *  3. **Exercice absent ou clos, ou plan comptable incomplet.** L'avoir était créé et le stock réintégré AVANT que
 *     l'écriture ne soit refusée (le web disait « Retour enregistré SANS écriture comptable », et le stock d'un exercice
 *     clos bougeait en 500 non rattrapé). Tout est désormais jugé AVANT d'écrire et le tout s'écrit dans UNE transaction :
 *     un refus n'écrit rien.
 *
 * ⚠️ DATE DU FAIT. Le web date l'avoir de l'instant de la saisie (`now()`). Un poste hors ligne envoie la date où le
 * retour a eu lieu (`$quand`, jamais dans le futur, jamais avant la vente) : l'écriture inverse et le mouvement de stock
 * portent CE jour, pas celui de la réception — même doctrine que la date d'une vente (14.71).
 *
 * ⚠️ IDEMPOTENCE (envoi d'un poste). `$id` est l'UUID de l'avoir né sur le poste : un avoir déjà enregistré sous cet
 * identifiant est rendu tel quel, sans second effet.
 */
class AvoirClientService
{
    /**
     * @param  array{sale_id: string, product_id: string, qty: float|int|string, amount: float|int|string, reason: string, decision: string, inspection_notes?: ?string}  $d
     *
     * @throws ValidationException  champs `saleId`, `productId`, `qty`, `amount` (les noms de propriétés du formulaire)
     * @throws AvoirClientRefuseException  plan comptable incomplet
     * @throws \App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException
     */
    public function enregistrer(array $d, ?string $id = null, ?Carbon $quand = null): CreditNote
    {
        if ($id !== null && ($existant = CreditNote::find($id)) !== null) {
            return $existant;
        }

        $quand ??= now();

        $sale = Sale::with('lines')->find($d['sale_id']);
        $this->verifier($sale, $d, $quand);

        $jour = $quand->format('Y-m-d');
        app(AccountingEntryService::class)->exerciceOuvertPour($jour);
        $this->verifierPlanComptable($d);

        return DB::transaction(function () use ($d, $id, $quand) {
            $avoir = new CreditNote([
                'credit_note_number' => CreditNote::generateCreditNoteNumber($quand),
                'sale_id' => $d['sale_id'],
                'product_id' => $d['product_id'],
                'qty' => $d['qty'],
                'amount' => $d['amount'],
                'reason' => $d['reason'],
                'decision' => $d['decision'],
                'inspection_notes' => ($d['inspection_notes'] ?? '') !== '' ? $d['inspection_notes'] : null,
                'status' => 'en_attente',
            ]);
            if ($id !== null) {
                $avoir->id = $id;
            }
            // ⚠️ `created_at` = le JOUR DU FAIT ; `updated_at` reste l'instant d'écriture du serveur (curseur du tirage).
            $avoir->created_at = $quand;
            $avoir->save();

            if ($d['decision'] === 'reintegre') {
                $produit = Product::find($d['product_id']);
                if ($produit) {
                    app(AdjustStockAction::class)->execute($produit, (float) $d['qty'], 'credit_note', $avoir->id, $quand);
                }
            }

            app(RecordCreditNoteAccountingEntryAction::class)->execute($avoir->load('product'));

            AuditLog::record('credit_note.created', 'ventes');

            return $avoir->fresh();
        });
    }

    /** Un avoir en attente est marqué « traité » ; déjà traité : rien ne se rejoue. */
    public function marquerTraite(CreditNote $avoir): CreditNote
    {
        if ($avoir->status === 'traite') {
            return $avoir;
        }

        $avoir->update(['status' => 'traite']);
        AuditLog::record('credit_note.treated', 'ventes');

        return $avoir;
    }

    /**
     * Quantité encore retournable d'un produit sur une vente : vendu − déjà retourné (tous avoirs).
     *
     * @return array{vendu: float, retourne: float, montant_ligne: float, montant_credite: float}
     */
    public function retournable(Sale $sale, string $produitId): array
    {
        $lignes = $sale->lines->where('product_id', $produitId);
        $avoirs = CreditNote::where('sale_id', $sale->id)->where('product_id', $produitId);

        return [
            'vendu' => round((float) $lignes->sum('qty'), 2),
            'retourne' => round((float) (clone $avoirs)->sum('qty'), 2),
            'montant_ligne' => round((float) $lignes->sum('manual_total_amount'), 2),
            'montant_credite' => round((float) (clone $avoirs)->sum('amount'), 2),
        ];
    }

    private function verifier(?Sale $sale, array $d, Carbon $quand): void
    {
        if ($sale === null) {
            throw ValidationException::withMessages(['saleId' => 'Cette vente est inconnue.']);
        }

        if ($sale->status === 'annulee') {
            throw ValidationException::withMessages(['saleId' => 'Cette vente est annulée : aucun retour n\'est possible.']);
        }

        // Jugé au JOUR : l'horloge d'un poste peut avancer de quelques minutes sur celle du serveur.
        if ($quand->copy()->startOfDay()->greaterThan(now()->startOfDay())) {
            throw ValidationException::withMessages(['saleId' => 'La date du retour ne peut pas être dans le futur.']);
        }

        if ($sale->date_effective !== null && $quand->copy()->startOfDay()->lessThan($sale->date_effective->copy()->startOfDay())) {
            throw ValidationException::withMessages(['saleId' => 'La date du retour ne peut pas précéder celle de la vente.']);
        }

        if (! $sale->lines->contains('product_id', $d['product_id'])) {
            throw ValidationException::withMessages(['productId' => 'Ce produit ne figure pas sur cette vente.']);
        }

        $r = $this->retournable($sale, $d['product_id']);
        $reste = round($r['vendu'] - $r['retourne'], 2);

        if (round((float) $d['qty'], 2) > $reste) {
            throw ValidationException::withMessages(['qty' => $reste <= 0
                ? 'Ce produit a déjà été retourné en totalité sur cette vente.'
                : 'La quantité retournée dépasse ce qui reste retournable : '.$this->nombre($r['vendu']).' vendu(s), '
                    .$this->nombre($r['retourne']).' déjà retourné(s), '.$this->nombre($reste).' restant(s).']);
        }

        $resteMontant = round($r['montant_ligne'] - $r['montant_credite'], 2);

        if (round((float) $d['amount'], 2) > $resteMontant) {
            throw ValidationException::withMessages(['amount' => 'Le montant de l\'avoir dépasse ce qui reste à créditer sur cette ligne : '
                .number_format(max($resteMontant, 0), 0, ',', ' ').' FCFA.']);
        }
    }

    /** Les comptes de l'écriture inverse (701, 411, et 443 si le produit porte de la TVA) existent, sinon refus. */
    private function verifierPlanComptable(array $d): void
    {
        if ((float) $d['amount'] <= 0) {
            return;
        }

        $codes = ['701', '411'];
        $taux = app(TvaSettingService::class)->tauxPour((float) (Product::find($d['product_id'])?->tva_rate ?? 0));
        if ($taux > 0) {
            $codes[] = '443';
        }

        $presents = ChartOfAccount::whereIn('code', $codes)->pluck('code')->all();
        $manquants = array_values(array_diff($codes, $presents));

        if ($manquants !== []) {
            throw new AvoirClientRefuseException(
                'Retour refusé : plan comptable incomplet (compte '.implode(', ', $manquants).' absent). Rien n\'a été enregistré.'
            );
        }
    }

    private function nombre(float $v): string
    {
        return rtrim(rtrim(number_format($v, 2, ',', ''), '0'), ',');
    }
}
