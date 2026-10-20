<?php

namespace App\Actions;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\Product;
use App\Services\AccountingEntryService;

/**
 * Ticket 14.41 (Sprint 14) — ÉCART D'INVENTAIRE : la PERTE enfin comptabilisée.
 *
 * 🔴 LE QUATRIÈME FLUX DU CDC, resté ouvert. Le cahier des charges exige que
 * « toute opération financière (vente, achat, paie, **perte**) déclenche
 * automatiquement la génération de l'écriture comptable ». Les trois premiers
 * ont été câblés aux tickets 14.23 à 14.25 — la **perte** ne l'était pas, et
 * l'écran l'annonçait lui-même à l'utilisateur : « l'écriture de charge
 * exceptionnelle (compte 657) arrive avec la Comptabilité (Sprint 10) ».
 *
 * Un inventaire physique qui trouve moins que le stock théorique constate une
 * perte réelle — vol, casse, péremption, mortalité non déclarée. Sans écriture,
 * cette perte n'apparaissait nulle part au Compte de Résultat : le stock
 * baissait, le résultat non.
 *
 * ÉCRITURE PRODUITE (SYSCOHADA) :
 *     Débit  657 Charges exceptionnelles ..... valeur de la perte au PMP
 *     Crédit 601 Achats de marchandises ...... même montant
 *
 * ⚠️ CONTREPARTIE AU COMPTE D'ACHATS, ET NON À UN COMPTE DE STOCK. Ce projet
 * ne tient PAS d'inventaire permanent : les achats partent directement en
 * charges (601), aucun compte de classe 3 n'est mouvementé à chaque
 * mouvement. La marchandise perdue a donc déjà été passée en charge à l'achat ;
 * l'écriture ne fait que la RECLASSER d'une charge d'exploitation vers une
 * charge exceptionnelle. Débiter 657 en créditant un compte de stock inexistant
 * aurait doublé la charge — la perte aurait été comptée deux fois.
 *
 * ⚠️ VALORISÉE AU PMP, jamais au prix de vente. Perdre une marchandise coûte ce
 * qu'elle a coûté, pas ce qu'elle aurait rapporté : valoriser au prix de vente
 * inscrirait au résultat une marge qui n'a jamais existé.
 *
 * ⚠️ UN ÉCART POSITIF NE PRODUIT AUCUNE ÉCRITURE. Trouver plus que prévu n'est
 * pas un produit : c'est le signe d'une entrée non saisie ou d'un comptage
 * antérieur erroné. L'inscrire en profit exceptionnel transformerait une erreur
 * de saisie en enrichissement. L'écart est régularisé en stock, et signalé.
 */
class RecordStockAdjustmentEntryAction
{
    /**
     * 🔴→✅ Ticket EX5 (R4) — l'écriture est datée du JOUR DU COMPTAGE (`$dateDuComptage`), jamais de l'instant où
     * elle est enregistrée : un inventaire du 30/12/2026 reçu d'un poste le 03/01/2027 passait sa perte en 2027, et
     * dans un exercice clos le stock refusé laissait sa perte acceptée. Même date que le mouvement de stock (S-T10 :
     * l'instant du comptage), donc le même exercice — et le même refus R4 s'il est clos.
     *
     * @param  float  $ecart  négatif = manquant constaté, positif = excédent
     * @return AccountingEntry|null  null si rien n'était à comptabiliser
     */
    public function execute(Product $produit, float $ecart, ?string $motif = null, ?\DateTimeInterface $dateDuComptage = null): ?AccountingEntry
    {
        // Excédent : régularisation de stock seule, jamais un profit.
        if ($ecart >= 0) {
            return null;
        }

        $pmp = $produit->computePmp();

        if ($pmp === null || $pmp <= 0) {
            // Produit sans historique d'achat (sujet né à la ferme, œufs) :
            // aucun coût connu. Chiffrer la perte exigerait d'inventer une
            // valeur — l'appelant DOIT le signaler plutôt que compter zéro.
            return null;
        }

        $valeur = round(abs($ecart) * $pmp, 2);

        if ($valeur < 0.01) {
            return null;
        }

        $chargesExceptionnelles = ChartOfAccount::where('code', '657')->first();
        $achats = ChartOfAccount::where('code', '601')->first();

        if (! $chargesExceptionnelles || ! $achats) {
            return null;   // plan comptable incomplet — signalé, jamais deviné
        }

        return app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $chargesExceptionnelles->id, 'debit' => $valeur, 'credit' => 0],
                ['account_id' => $achats->id, 'debit' => 0, 'credit' => $valeur],
            ],
            entryDate: $this->jourDuComptage($dateDuComptage),
            reference: mb_substr(
                AccountingEntry::generateReference().' — Écart inventaire '.$produit->sku
                    .($motif ? ' ('.$motif.')' : ''),
                0, 100
            ),
            sourceType: 'stock_adjustment',
            sourceId: $produit->id,
        );
    }

    /**
     * Ticket S-T12 — UNE PERTE D'INVENTAIRE QUI N'EN ÉTAIT PAS UNE, RECLASSÉE. Un comptage avait constaté un manquant
     * (D 657 / C 601) ; une vente datée d'avant ce comptage arrive ensuite au serveur (caisse restée hors ligne) : les
     * [$quantite] unités « manquantes » avaient en fait été vendues. `InventaireAuComptageService` recalcule l'écart du
     * comptage ; cette écriture défait la part de perte qu'il n'y a plus — exactement l'inverse de `execute` :
     *
     *     Débit  601 Achats de marchandises ...... valeur au PMP
     *     Crédit 657 Charges exceptionnelles ..... même montant
     *
     * ⚠️ Mêmes garde-fous que `execute` : produit sans PMP (aucun coût connu) ou plan comptable incomplet → aucune
     * écriture, jamais une valeur devinée.
     */
    public function annulerPerte(Product $produit, float $quantite, ?string $motif = null, ?\DateTimeInterface $dateDuComptage = null): ?AccountingEntry
    {
        $pmp = $produit->computePmp();
        if ($quantite <= 0 || $pmp === null || $pmp <= 0) {
            return null;
        }

        $valeur = round($quantite * $pmp, 2);
        $chargesExceptionnelles = ChartOfAccount::where('code', '657')->first();
        $achats = ChartOfAccount::where('code', '601')->first();
        if ($valeur < 0.01 || ! $chargesExceptionnelles || ! $achats) {
            return null;
        }

        return app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $achats->id, 'debit' => $valeur, 'credit' => 0],
                ['account_id' => $chargesExceptionnelles->id, 'debit' => 0, 'credit' => $valeur],
            ],
            entryDate: $this->jourDuComptage($dateDuComptage),
            reference: mb_substr(
                AccountingEntry::generateReference().' — Écart inventaire annulé '.$produit->sku
                    .($motif ? ' ('.$motif.')' : ''),
                0, 100
            ),
            sourceType: 'stock_adjustment',
            sourceId: $produit->id,
        );
    }

    /** Le jour du comptage à l'heure du Bénin (`app.timezone`, celle des mouvements de stock) ; aujourd'hui à défaut. */
    private function jourDuComptage(?\DateTimeInterface $dateDuComptage): string
    {
        return $dateDuComptage === null
            ? now()->format('Y-m-d')
            : \Carbon\Carbon::instance($dateDuComptage)->setTimezone(config('app.timezone'))->format('Y-m-d');
    }
}
