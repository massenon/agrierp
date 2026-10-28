<?php

namespace App\Actions;

use App\Exceptions\ClosedFiscalYearException;
use App\Models\AuditLog;
use App\Models\LivestockLot;
use App\Models\Product;
use App\Models\Transformation;
use App\Services\AccountingEntryService;
use App\Support\OrdreDesVerrous;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket EL-1 — POINT DE PASSAGE UNIQUE d'une transformation (« Bon d'Abattage & Transformation »).
 *
 * Cette règle vivait dans `Livewire\Elevage\TransformationForm::validateTransformation`. Le poste saisit désormais ses
 * transformations hors ligne et les envoie (`SyncController::pushTransformations`) : les deux chemins passent ici, avec
 * les mêmes règles, les mêmes effets et les mêmes messages.
 *
 * Effets (dans UNE transaction, verrous dans l'ordre de `OrdreDesVerrous`, ticket U14) :
 *  1. la transformation est écrite ;
 *  2. élevage : les sujets sortent comme une VENTE de la fiche du jour de transformation (`RecordSaleOnFicheElevageAction`,
 *     cascade des jours suivants, bande = dernière fiche — décision client du 17/10/2026) ;
 *  3. stock produits finis : `AdjustStockAction` (type `transformation`).
 * Puis l'audit `transformation.recorded`.
 *
 * Règles de refus (sous le nom de la propriété du composant, que le web affiche sous le champ) :
 *  - `lotId` / `productId` : bande ou produit inconnus ;
 *  - `qtyAnimals` : au plus l'effectif disponible de la bande, relu SOUS VERROU ;
 *  - `transformationDate` : un exercice clos est en lecture seule (motif R4) — jour d'un exercice clos, ou stock refusé
 *    par `AdjustStockAction`.
 *
 * ⚠️ IDEMPOTENCE : un identifiant déjà connu (l'UUID posé par le poste) rend la transformation existante SANS rien
 * rejouer — un renvoi ne retire pas deux fois les sujets, n'ajoute pas deux fois le stock.
 */
class SaisieTransformationAction
{
    /**
     * Règles de forme (celles du formulaire web, reprises à l'identique par l'envoi du poste). Les libellés des champs
     * (« bande », « nombre d'animaux », « produit », « quantité produite », « date de transformation ») sont ceux de
     * `lang/fr/validation.php` : le poste affiche donc les mêmes refus que le web.
     */
    public const REGLES = [
        'lotId' => ['required', 'exists:livestock_lots,id'],
        'qtyAnimals' => ['required', 'integer', 'min:1'],
        'productId' => ['required', 'exists:products,id'],
        'qtyProduced' => ['required', 'numeric', 'min:0'],
        'transformationDate' => ['required', 'date'],
    ];

    public static function messageEffectifInsuffisant(int $disponible): string
    {
        return "La quantité ne peut pas dépasser l'effectif disponible du lot ({$disponible}).";
    }

    /**
     * @param  array{lotId: string, qtyAnimals: int|string, productId: string, qtyProduced: int|float|string, transformationDate: string}  $donnees
     * @param  string|null  $id  UUID posé par le poste (idempotence) ; `null` au web (généré)
     *
     * @throws ValidationException
     */
    public function enregistrer(array $donnees, ?string $operateurId, ?string $id = null): Transformation
    {
        $jour = Carbon::parse($donnees['transformationDate'])->format('Y-m-d');

        if ($id !== null && ($existante = Transformation::find($id)) !== null) {
            return $existante;
        }

        if ($refus = app(AccountingEntryService::class)->refusExerciceClos($jour)) {
            throw ValidationException::withMessages(['transformationDate' => $refus]);
        }

        $transformation = DB::transaction(function () use ($donnees, $operateurId, $id, $jour) {
            $produit = Product::find($donnees['productId']);
            if ($produit === null) {
                throw ValidationException::withMessages(['productId' => trans('validation.exists', ['attribute' => trans('validation.attributes.productId')])]);
            }

            // 🔴→✅ Ticket U14 — le stock (produit fini, et ce que la fiche de la bande mouvemente) AVANT la fiche du jour.
            OrdreDesVerrous::stock([$produit->id, ...OrdreDesVerrous::produitsDesFiches([$donnees['lotId']])]);

            $lot = LivestockLot::query()->lockForUpdate()->find($donnees['lotId']);
            if ($lot === null) {
                throw ValidationException::withMessages(['lotId' => trans('validation.exists', ['attribute' => trans('validation.attributes.lotId')])]);
            }

            $sujets = (int) $donnees['qtyAnimals'];
            if ($sujets > (int) $lot->current_quantity) {
                throw ValidationException::withMessages(['qtyAnimals' => self::messageEffectifInsuffisant((int) $lot->current_quantity)]);
            }

            $transformation = new Transformation([
                'lot_id' => $lot->id,
                'product_id' => $produit->id,
                'qty_animals' => $sujets,
                'qty_produced' => $donnees['qtyProduced'],
                'operator_id' => $operateurId,
                'transformation_date' => $jour,
            ]);
            if ($id !== null) {
                // ⚠️ `id` n'est pas remplissable et `HasUuids` en génère un : on assigne celui du poste explicitement.
                $transformation->id = $id;
            }
            $transformation->save();

            // 1. Élevage — sortie des sujets, comme une vente, dans la fiche du jour.
            app(RecordSaleOnFicheElevageAction::class)->execute([['lot_id' => $lot->id, 'qty' => $sujets]], $jour);

            // 2. Stock Produits Finis — incrémentation.
            try {
                app(AdjustStockAction::class)->execute($produit, (float) $donnees['qtyProduced'], 'transformation', $transformation->id);
            } catch (ClosedFiscalYearException $e) {
                throw ValidationException::withMessages(['transformationDate' => $e->getMessage()]);
            }

            return $transformation;
        });

        AuditLog::record('transformation.recorded', 'elevage', $operateurId);

        return $transformation;
    }
}
