<?php

namespace App\Livewire\Achats;

use App\Actions\AdjustStockAction;
use App\Actions\RecordPurchaseAction;
use App\Actions\RecordPurchaseAccountingEntryAction;
use App\Exceptions\AchatNonComptabilisableException;
use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Models\AuditLog;
use App\Models\Payable;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\Supplier;
use App\Models\TreasuryAccount;
use Illuminate\Support\Facades\DB;
use Livewire\Component;
use Livewire\WithFileUploads;

/**
 * Ticket 5.2 (Sprint 5) — enregistrer-achat.html → Livewire\Achats\EnregistrerAchat
 * "Réception de marchandises auprès d'un fournisseur."
 *
 * Impacts réels appliqués à la validation :
 *   1. Stock — Incrémentation : `products.stock_qty` augmenté de la
 *      quantité reçue pour chaque ligne.
 *   2. Trésorerie — Décrémentation : le compte débité choisi
 *      (`treasury_accounts.balance`) diminue du montant réellement payé
 *      — même correctif que `RecordPosSaleAction` (bug historique déjà
 *      corrigé sur les autres flux de paiement, mémoire du projet).
 *   3. Dette Fournisseur — si le montant payé < total, une `Payable`
 *      réelle est créée pour le solde restant (même mécanique que
 *      `Receivable` côté ventes, ticket 4.7).
 *
 * "Pièce Justificative" : upload réel (`WithFileUploads`), stockée sur le
 * disque local — même traitement que la capture d'écran de
 * `contact-editeur.html` (ticket 1.6).
 *
 * "Nouveau Fournisseur" : quick-add réel (nom + téléphone, fidèle à la
 * modale du prototype). "Nouveau Produit" : quick-add réel minimal
 * (nom, catégorie, unité) plutôt qu'une redirection qui ferait perdre la
 * saisie du bon d'achat en cours — le formulaire complet
 * (`AjouterProduit`, ticket 2.4) reste disponible pour compléter la fiche
 * ensuite (tarification, seuils...).
 *
 * 🔴→✅ EXTENSION DU PATTERN RBAC CRUD AU NIVEAU ACTION (référence
 * initiale : `PlanComptable`) — `$this->authorize('manage-achats')` sur
 * les 5 actions réellement mutantes (`addLine`, `removeLine`,
 * `saveNewSupplier`, `saveNewProduct`, `submitAchat`) — pas sur
 * `openAddSupplierModal`/`openAddProductModal` (ouverture de modale
 * seulement). `submitAchat` est l'action la plus critique : déplace un
 * vrai mouvement de stock et de trésorerie.
 */
class EnregistrerAchat extends Component
{
    use WithFileUploads;

    public string $supplierId = '';

    public array $cart = [];

    public string $lineProductId = '';

    public int $lineQty = 1;

    public ?float $linePrice = null;

    public string $paymentMode = 'especes';

    public string $treasuryAccountId = '';

    public ?float $amountPaid = null;

    public $receiptFile = null;

    public string $purchaseDate = '';

    public string $newSupplierName = '';

    public string $newSupplierPhone = '';

    public string $newProductName = '';

    public string $newProductCategoryId = '';

    public string $newProductUnit = 'u';

    public function mount(): void
    {
        $this->treasuryAccountId = (string) (TreasuryAccount::where('is_active', true)->first()?->id ?? '');
        $this->purchaseDate = now()->format('Y-m-d');
    }

    public function getSuppliersProperty()
    {
        return Supplier::where('is_active', true)->orderBy('name')->get();
    }

    public function getProductsProperty()
    {
        return Product::where('is_active', true)->orderBy('name')->get();
    }

    public function getCategoriesProperty()
    {
        return ProductCategory::where('is_active', true)->orderBy('label')->get();
    }

    public function getTreasuryAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    public function getTotalProperty(): float
    {
        return collect($this->cart)->sum(fn ($l) => $l['qty'] * $l['unit_price']);
    }

    public function getRecentPurchasesProperty()
    {
        return Purchase::with('supplier')->orderByDesc('created_at')->limit(10)->get();
    }

    public function updatedLineProductId(): void
    {
        $product = Product::find($this->lineProductId);
        $this->linePrice = $product ? (float) ($product->price_min ?? 0) : null;
    }

    public function addLine(): void
    {
        $this->authorize('manage-achats');

        $this->validate([
            'lineProductId' => ['required', 'exists:products,id'],
            'lineQty' => ['required', 'integer', 'min:1'],
            'linePrice' => ['required', 'numeric', 'min:0'],
        ]);

        $product = Product::findOrFail($this->lineProductId);

        $this->cart[] = [
            'product_id' => $product->id,
            'name' => $product->name,
            'unit' => $product->unit,
            'qty' => $this->lineQty,
            'unit_price' => $this->linePrice,
        ];

        $this->reset(['lineProductId', 'linePrice']);
        $this->lineQty = 1;
    }

    public function removeLine(int $index): void
    {
        $this->authorize('manage-achats');

        unset($this->cart[$index]);
        $this->cart = array_values($this->cart);
    }

    public function openAddSupplierModal(): void
    {
        $this->reset(['newSupplierName', 'newSupplierPhone']);
        $this->dispatch('open-modal', name: 'modal-add-supplier');
    }

    public function saveNewSupplier(): void
    {
        $this->authorize('manage-achats');

        $this->validate([
            'newSupplierName' => ['required', 'string', 'max:150'],
            'newSupplierPhone' => ['required', 'string', 'max:30'],
        ]);

        $supplier = Supplier::create([
            'name' => $this->newSupplierName,
            'phone' => $this->newSupplierPhone,
            // Ticket AC-2 — la catégorie est EXIGÉE par `SupplierCatalogService` (donc par le poste, à l'envoi) : une fiche créée
            // à la volée porte « Autre », comme celle du poste, pour qu'une fiche du web ne soit jamais sans catégorie.
            'category' => 'Autre',
            'is_active' => true,
        ]);

        $this->supplierId = $supplier->id;
        AuditLog::record('supplier.created', 'achats');
        $this->dispatch('close-modal', name: 'modal-add-supplier');
        $this->dispatch('toast', message: 'Fournisseur enregistré avec succès.', type: 'success');
    }

    public function openAddProductModal(): void
    {
        $this->reset(['newProductName', 'newProductCategoryId']);
        $this->newProductUnit = 'u';
        $this->dispatch('open-modal', name: 'modal-add-product');
    }

    public function saveNewProduct(): void
    {
        $this->authorize('manage-achats');

        $this->validate([
            'newProductName' => ['required', 'string', 'max:150'],
            'newProductCategoryId' => ['required', 'exists:product_categories,id'],
            'newProductUnit' => ['required', 'string', 'max:20'],
        ]);

        $categoryLabel = ProductCategory::find($this->newProductCategoryId)?->label ?? 'PRD';

        $product = Product::create([
            'sku' => Product::generateSku($categoryLabel),
            'name' => $this->newProductName,
            'category_id' => $this->newProductCategoryId,
            'unit' => $this->newProductUnit,
            'pricing_mode' => 'fourchette',
            'price_min' => 0,
            'price_max' => 0,
            'tva_rate' => 0,
            'stock_qty' => 0,
            'alert_threshold' => 0,
            'is_active' => true,
        ]);

        $this->lineProductId = $product->id;
        $this->linePrice = 0;
        AuditLog::record('product.created', 'achats');
        $this->dispatch('close-modal', name: 'modal-add-product');
        $this->dispatch('toast', message: 'Produit ajouté au catalogue — complétez sa fiche (tarification) depuis le Catalogue.', type: 'success');
    }

    public function submitAchat(): void
    {
        $this->authorize('manage-achats');

        if (empty($this->cart)) {
            $this->dispatch('toast', message: "Ajoutez au moins un article au bon d'achat.", type: 'error');

            return;
        }

        $this->validate([
            'supplierId' => ['required', 'exists:suppliers,id'],
            'purchaseDate' => ['required', 'date', 'date_format:Y-m-d'],
            'treasuryAccountId' => ['required', 'exists:treasury_accounts,id'],
            'amountPaid' => ['nullable', 'numeric', 'min:0'],
            'receiptFile' => ['nullable', 'file', 'mimes:'.\App\Services\JustificatifService::FORMATS, 'max:'.\App\Services\JustificatifService::TAILLE_MAX_KO],
        ]);

        $total = $this->total;
        $paid = min($this->amountPaid ?? 0, $total);

        // ⚠️ LES CINQ EFFETS D'UN ACHAT VIVENT DANS `RecordPurchaseAction`
        // depuis le ticket 14.78 — pièce et lignes, entrée en stock, décaissement,
        // dette si le règlement est partiel, écriture SYSCOHADA. Le poste
        // Desktop enregistre les mêmes achats hors ligne et passe par la MÊME
        // action : deux copies de cinq effets auraient divergé.
        // Ticket 15.22 — REFUS EXACTEMENT COMME LA RÉCEPTION D'UN BON (15.21) : exercice clos/absent, compte manquant ou
        // total nul annulent TOUT (la transaction de l'action) et s'affichent en français, jamais en erreur 500.
        // Le panier est conservé pour que l'utilisateur corrige et réessaie.
        try {
            $achat = app(RecordPurchaseAction::class)->execute(
                supplierId: $this->supplierId,
                lignes: array_map(fn (array $item) => [
                    'product_id' => $item['product_id'],
                    'qty' => $item['qty'],
                    'unit_price' => $item['unit_price'],
                ], array_values($this->cart)),
                paymentMode: $this->paymentMode,
                treasuryAccountId: $this->treasuryAccountId,
                montantRegle: (float) $paid,
                purchaseDate: $this->purchaseDate,
            );
        } catch (NoOpenFiscalYearException|ClosedFiscalYearException|AchatNonComptabilisableException $e) {
            $this->dispatch('toast', message: 'Achat refusé : '.$e->getMessage(), type: 'error');

            return;
        }

        // Ticket AC-3 — le justificatif est RATTACHÉ à l'achat (avant : rangé sur le disque sans lien), par le service que le
        // poste utilise aussi.
        if ($this->receiptFile) {
            app(\App\Services\JustificatifService::class)->rattacher('achat', $achat->id, $this->receiptFile);
        }

        $this->dispatch('toast', message: 'Achat enregistré avec succès — total '.number_format($total, 0, ',', ' ').' FCFA.', type: 'success');
        $this->reset(['cart', 'amountPaid', 'receiptFile']);

        // 🔴→✅ TICKET 14.3 — `total` est une propriété calculée dérivée de
        // `$this->cart`, lue plus haut et donc mémoïsée pour la requête. Le
        // panier venant d'être vidé, le rendu réaffichait le total de l'achat
        // déjà enregistré au-dessus d'un panier vide. Même défaut que
        // `PosInterface::validateSale()` (ticket 14.2).
        unset($this->total);
    }

    public function render()
    {
        return view('livewire.achats.enregistrer-achat');
    }
}
