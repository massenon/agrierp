<?php

namespace App\Livewire\Stocks;

use App\Actions\AdjustStockAction;
use App\Actions\RecordStockAdjustmentEntryAction;
use App\Models\AuditLog;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\PurchaseLine;
use App\Models\StockMovement;
use App\Services\StockRotationService;
use App\Support\ExerciceChoisi;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;
use Livewire\WithPagination;

/**
 * Ticket 6.2 (Sprint 6) — gestion-stocks.html → Livewire\Stocks\GestionStocks
 * "Espace unifié : inventaire, mouvements et ajustements."
 * 3 onglets internes réels (Tableau & Valorisation, Journal des
 * Mouvements, Ajustement/Correction) — pas de pattern hub/iframe, fidèle
 * à la structure monolithique du prototype (un seul fichier, 3 panneaux
 * en JS, jamais 3 fichiers séparés comme pour les autres hubs).
 *
 * ⚠️ PMP (Prix Moyen Pondéré) RÉEL : calculé par moyenne pondérée des
 * `purchase_lines` historiques du produit (Σ qty×unit_price ÷ Σ qty) —
 * jamais une valeur statique. Produits sans historique d'achat (ex.
 * sujets vivants nés à la ferme, œufs) : PMP non calculable, affiché "—",
 * exclu de la Valorisation Stocks plutôt que remplacé par une estimation
 * inventée.
 *
 * ⚠️ "Écart d'Inventaire → écriture de charge exceptionnelle (compte
 * 657)" : 🔴→✅ LIVRÉE AU TICKET 14.41. Un manquant d'inventaire est
 * désormais porté en charge exceptionnelle (débit 657 / crédit 601),
 * valorisé au PMP. Un excédent, lui, ne produit aucune écriture : ce n'est
 * pas un profit mais le signe d'une entrée non saisie.
 *
 * "Rotation du Stock" (KPI) : 🔴→✅ LIVRÉ AU TICKET 14.47. Ce qui manquait
 * n'était pas une décision du client mais une convention de valorisation —
 * « à quel coût sort une marchandise ? ». Le ticket 14.41 l'a tranchée pour
 * l'écart d'inventaire (au PMP) ; la même vaut ici, sans quoi le projet en
 * aurait deux. Calcul dans `StockRotationService`, jamais en ligne dans cet
 * écran : Rotation = COGS du mois ÷ stock moyen du mois.
 *
 * "Ajouter Stock" (entrée manuelle simple) et l'ajustement d'inventaire
 * passent tous deux par `AdjustStockAction` (ticket 6.1) — jamais un
 * increment/decrement direct.
 *
 * ⚠️ ÉCART DÉLIBÉRÉ TROUVÉ PAR L'AUDIT DE FIDÉLITÉ : `mouvement-stock.html`
 * (variante autonome de cet onglet) affiche des boutons Modifier/Archiver
 * sur chaque ligne du journal — mais ce sont des `openModal(...)` de
 * démonstration sans logique réelle derrière dans le prototype. Le
 * Journal des Mouvements est ici un GRAND LIVRE (chaque ligne dérive
 * directement de `AdjustStockAction`, au même titre que les écritures
 * comptables du Sprint 10) — le rendre modifiable après coup romprait la
 * réconciliation de `products.stock_qty` (une somme cumulative de
 * mouvements immuables) exactement comme modifier une écriture comptable
 * validée romprait le grand livre financier. Boutons non repris
 * volontairement, même discipline que le retrait des outils de démo
 * depuis le Sprint 0 (sélecteur de rôle, "Tester Rappel") — jamais un
 * oubli.
 *
 * 🔴→✅ EXTENSION DU PATTERN RBAC CRUD AU NIVEAU ACTION (référence
 * initiale : `PlanComptable`) — `$this->authorize('manage-stocks')` sur
 * les 2 actions réellement mutantes (`submitAjouterStock`,
 * `validateAdjustment`) — toutes deux passent par `AdjustStockAction`,
 * le seul point d'entrée pour toute mutation de stock (ticket 6.1).
 *
 * 🔴→✅ TROUVÉ PAR COMPARAISON STRUCTURELLE RIGOUREUSE (ordre exact des
 * sections vs prototype) : le bouton "Exporter" de la barre d'outils
 * était totalement absent, alors que le prototype le montre entre le
 * filtre catégorie et "Ajouter Stock". Ajouté réellement
 * (`exportStocksPdf()`, réutilise `PdfExportService`).
 *
 * ⚠️ "Importer" (import en masse d'inventaire) reste DÉLIBÉRÉMENT NON
 * AJOUTÉ malgré sa présence dans le prototype juste après "Exporter" —
 * une vraie fonctionnalité d'import CSV/Excel (parsing, correspondance
 * SKU, validation, application en masse via `AdjustStockAction`) est un
 * chantier à part entière, aucune librairie d'import
 * (phpoffice/phpspreadsheet, maatwebsite/excel) n'est même présente dans
 * `composer.json`. Un bouton qui ouvrirait une modale sans rien
 * importer réellement violerait la règle "zéro placeholder" (Document
 * 00 §2.2) déjà respectée partout ailleurs dans ce projet — omis
 * honnêtement plutôt que simulé.
 *
 * 🔴→✅ TICKET 14.49 (AUDIT DE FIDÉLITÉ) — LA COLONNE "ACTIONS" DU TABLEAU
 * DE STOCK ÉTAIT ABSENTE, sans justification écrite : 8 colonnes dans le
 * prototype, 7 ici. L'écart d'omission documenté juste au-dessus concerne le
 * JOURNAL des mouvements, pas ce tableau-ci — la limite avait été lue plus
 * largement qu'elle ne portait. Colonne rétablie, son lien pointant sur
 * l'écran d'édition DÉJÀ existant (`stocks.produits.modifier`) : aucun second
 * formulaire produit n'est créé ici.
 *
 * ⚠️ La SUPPRESSION du prototype (`modal-delete-stock`) n'est en revanche pas
 * reprise sur cet écran : l'archivage logique existe déjà sur Catalogue
 * Produits (`CatalogueProduits::archive()`), point d'entrée unique. Un second
 * chemin d'archivage dupliquerait une décision, pas seulement du code.
 *
 * 🔴→✅ TICKET 14.49 — les 7 cellules du Journal des Mouvements ne portaient
 * AUCUN `data-label` alors que leur tableau porte la classe `rtable` : sous
 * 640 px, les valeurs s'empilaient sans libellé, illisibles. Le prototype a
 * le même oubli sur CE tableau, mais son propre tableau de stock les émet
 * bien depuis son JS — la convention est intentionnelle, l'oubli non.
 *
 * ⚠️ Lien "Configurer les Seuils d'Alerte" en en-tête : AJOUT au-delà du
 * prototype (qui ne le montre pas à cet endroit précis), conservé
 * volontairement — navigation utile vers un écran directement lié
 * (`/seuils-alerte`), n'altère aucune section structurelle existante.
 */
#[Layout('layouts.app')]
class GestionStocks extends Component
{
    use \App\Livewire\Concerns\BornesCalendrierExercice;
    use WithPagination;

    /** Ticket U8 — les mouvements qui sont des écarts d'inventaire : cet écran (`adjustment`) et le poste (`inventaire`). */
    public const TYPES_ECART_INVENTAIRE = ['adjustment', 'inventaire'];

    #[Url]
    public string $tab = 'tableau';

    public string $search = '';

    public string $categoryFilter = '';

    public string $addDate = '';

    public string $addProductId = '';

    public ?int $addQty = null;

    public string $adjProductId = '';

    public ?float $adjPhysical = null;

    public string $adjReason = '';

    public function mount(): void
    {
        $this->addDate = now()->format('Y-m-d');
    }

    public function getCategoriesProperty()
    {
        return ProductCategory::where('is_active', true)->orderBy('label')->get();
    }

    public function getProductsProperty()
    {
        return Product::where('is_active', true)->orderBy('name')->get();
    }

    // PMP extrait vers Product::computePmp() au ticket 12.7 — un seul
    // point de vérité, réutilisé également par StocksSynth.

    private function stockRowsRaw()
    {
        return $this->products->map(function ($product) {
            $pmp = $product->computePmp();

            return [
                'product' => $product,
                'pmp' => $pmp,
                // Ticket 14.30 : plancher a zero (`Product::valeurStock()`) — un
                // stock negatif ne retranche plus de la valeur au tableau.
                'valeur' => $pmp !== null ? round($product->valeurStock()) : null,
                'stock_negatif' => $product->stockEstNegatif(),
                'urgence' => $product->alert_threshold > 0 && $product->stock_qty <= $product->alert_threshold,
            ];
        });
    }

    public function getStockRowsProperty()
    {
        return $this->stockRowsRaw()
            ->when($this->search, fn ($rows) => $rows->filter(fn ($r) => str_contains(mb_strtolower($r['product']->name), mb_strtolower($this->search)) || str_contains(mb_strtolower($r['product']->sku ?? ''), mb_strtolower($this->search))))
            ->when($this->categoryFilter, fn ($rows) => $rows->filter(fn ($r) => $r['product']->category_id === $this->categoryFilter));
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR COMPARAISON STRUCTURELLE RIGOUREUSE
     * (ordre exact des sections vs prototype) : le bouton "Exporter" de
     * l'onglet Tableau & Valorisation n'avait jamais été construit —
     * absent purement et simplement, alors que le prototype le montre
     * juste avant "Importer" et "Ajouter Stock". Réutilise
     * `PdfExportService` (même pattern que `StocksSynth::exportReport()`,
     * ticket 12.7) — exporte le tableau FILTRÉ (recherche + catégorie
     * actives), pas l'inventaire complet non filtré. Gardé par
     * `view-stocks` (pas de permission `export-stocks` dédiée dans le
     * seeder — module Stocks n'a que `view-stocks`/`manage-stocks`,
     * contrairement à Élevage/Ventes/Rapports qui ont un `export-X`
     * explicite ; réutiliser `view-stocks` plutôt qu'inventer une
     * permission absente du seeder, cohérent avec les rôles réels).
     */
    public function exportStocksPdf()
    {
        $this->authorize('view-stocks');

        $rows = $this->stockRows;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.gestion-stocks',
            ['rows' => $rows],
            'Gestion des Stocks — Tableau & Valorisation',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'stocks-'.now()->format('Y-m-d').'.pdf');
    }

    public function getKpisProperty(): array
    {
        $rows = $this->stockRowsRaw();
        $valorisation = $rows->sum(fn ($r) => $r['valeur'] ?? 0);
        $alertes = $rows->filter(fn ($r) => $r['urgence'])->count();

        // 🔴→✅ TICKET U8 — L'INVENTAIRE SAISI AU POSTE EST UN ÉCART D'INVENTAIRE. Le poste envoie ses ajustements
        // (`stock_adjustments`) avec `reference_type = 'inventaire'`, rejoués par `AdjustStockAction` ET passés en
        // perte comme ceux de cet écran (`RecordStockAdjustmentEntryAction`) — mais cette carte ne lisait que
        // `adjustment` : un manquant constaté hors ligne n'apparaissait jamais dans les « Écarts d'Inventaire » de
        // la ferme, alors que le poste, lui, le compte.
        // Ticket EX7 — le mois de référence de l'exercice affiché (le mois du jour, ou le dernier mois de 2026 lu en 2027).
        $mois = ExerciceChoisi::moisDeReference();
        $ecartsMois = StockMovement::whereIn('reference_type', self::TYPES_ECART_INVENTAIRE)
            ->whereMonth('movement_date', $mois->month)->whereYear('movement_date', $mois->year)
            ->get();

        $ecartsValeur = $ecartsMois->sum(function ($m) {
            $product = Product::find($m->product_id);
            $pmp = $product?->computePmp();
            $signedQty = $m->type === 'sortie' ? -$m->quantity : $m->quantity;

            return $pmp !== null ? $signedQty * $pmp : 0;
        });

        return [
            'valorisation' => $valorisation,
            'alertes' => $alertes,
            'ecarts' => round($ecartsValeur),
            // Ticket 14.47 — la rotation vit dans un service : le mois en
            // cours ici, mais la formule sert aussi tout rapport ultérieur.
            'rotation' => app(StockRotationService::class)->pourLeMois(),
        ];
    }

    public function openAddStockModal(): void
    {
        $this->reset(['addProductId', 'addQty']);
        $this->addDate = now()->format('Y-m-d');
        $this->dispatch('open-modal', name: 'modal-ajouter-stock');
    }

    public function submitAjouterStock(): void
    {
        $this->authorize('manage-stocks');

        $this->validate([
            'addDate' => ['required', 'date'],
            'addProductId' => ['required', 'exists:products,id'],
            'addQty' => ['required', 'integer', 'min:1'],
        ]);

        $product = Product::findOrFail($this->addProductId);

        try {
            app(AdjustStockAction::class)->execute($product, (float) $this->addQty, 'manual_addition', null, \Carbon\Carbon::parse($this->addDate));
        } catch (\App\Exceptions\ClosedFiscalYearException $e) {
            // Ticket EX5 — exercice clos : le motif R4 sous le champ « Date », rien n'est écrit.
            $this->addError('addDate', $e->getMessage());

            return;
        }

        AuditLog::record('stock.manual_addition', 'stocks');
        $this->dispatch('close-modal', name: 'modal-ajouter-stock');
        $this->dispatch('toast', message: 'Stock ajouté avec succès.', type: 'success');
    }

    /**
     * Ticket EX7 (EF9) — le Journal des Mouvements de l'exercice AFFICHÉ, PAGINÉ (25 par page), au lieu des 100 derniers
     * toutes années confondues.
     */
    public function getMovementsProperty()
    {
        [$debut, $fin] = ExerciceChoisi::bornes();

        return StockMovement::with('product')
            ->whereDate('movement_date', '>=', $debut)
            ->whereDate('movement_date', '<=', $fin)
            ->orderByDesc('movement_date')
            ->orderByDesc('id')
            ->paginate(ExerciceChoisi::PAR_PAGE, pageName: 'pageMouvements');
    }

    public function referenceLabel(string $type): string
    {
        return match ($type) {
            'sale' => 'Vente',
            'purchase' => 'Achat',
            'purchase_return' => 'Retour Fournisseur',
            'credit_note' => 'Retour Client',
            'transformation' => 'Transformation',
            'daily_entry' => 'Production',
            'manual_addition' => 'Ajout Manuel',
            'adjustment' => 'Ajustement',
            default => ucfirst($type),
        };
    }

    public function getAdjSelectedProductProperty(): ?Product
    {
        return $this->adjProductId ? Product::find($this->adjProductId) : null;
    }

    public function getAdjDiffProperty(): float
    {
        if (! $this->adjSelectedProduct || $this->adjPhysical === null) {
            return 0;
        }

        return round($this->adjPhysical - $this->adjSelectedProduct->stock_qty, 2);
    }

    public function validateAdjustment(): void
    {
        $this->authorize('manage-stocks');

        $this->validate([
            'adjProductId' => ['required', 'exists:products,id'],
            'adjPhysical' => ['required', 'numeric', 'min:0'],
        ]);

        $diff = $this->adjDiff;

        if ($diff == 0) {
            $this->dispatch('toast', message: 'Aucun écart détecté — rien à ajuster.', type: 'warning');

            return;
        }

        $product = Product::findOrFail($this->adjProductId);

        // 🔴→✅ TICKET EX5 (EF6) — LE MOUVEMENT ET SA PERTE, ENSEMBLE OU PAS DU TOUT. Ils partaient l'un après l'autre :
        // un exercice absent faisait échouer l'écriture de perte (erreur 500) APRÈS que le stock avait bougé — un
        // manquant au stock, sans sa charge 657. Une transaction ; le refus devient un toast, rien n'est écrit.
        try {
            $ecriture = \Illuminate\Support\Facades\DB::transaction(function () use ($product, $diff) {
                app(AdjustStockAction::class)->execute($product, $diff, 'adjustment', null, now(), $this->adjReason ?: null);

                // 🔴→✅ TICKET 14.41 — LA PERTE EST ENFIN COMPTABILISÉE.
                //
                // Le CDC exige que « toute opération financière (vente, achat, paie,
                // **perte**) déclenche automatiquement la génération de l'écriture ».
                // Les trois premiers flux ont été câblés aux tickets 14.23 à 14.25 ; la
                // perte ne l'était pas, et cet écran l'annonçait lui-même à
                // l'utilisateur depuis le Sprint 6. Un manquant d'inventaire faisait
                // baisser le stock sans jamais réduire le résultat.
                // Ticket EX5 — datée du jour du comptage (ici, maintenant), comme le mouvement.
                return app(RecordStockAdjustmentEntryAction::class)
                    ->execute($product, $diff, $this->adjReason ?: null, now());
            });
        } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
            $this->dispatch('toast', message: $e->getMessage(), type: 'error');

            return;
        }

        AuditLog::record('stock.adjusted', 'stocks');

        if ($diff > 0) {
            // ⚠️ Un excédent n'est PAS un profit : c'est le signe d'une entrée
            // non saisie. Régularisé en stock, jamais inscrit au résultat.
            $message = "Ajustement enregistré — écart positif de {$diff}. Aucune écriture : un excédent signale une entrée non saisie, jamais un gain.";
            $type = 'success';
        } elseif ($ecriture) {
            $message = "Ajustement enregistré — perte de ".number_format((float) $ecriture->total_debit, 0, ',', ' ')
                ." FCFA portée en charge exceptionnelle (débit 657 / crédit 601).";
            $type = 'warning';
        } else {
            // Jamais silencieux : produit sans PMP connu, ou plan comptable
            // incomplet. Chiffrer la perte exigerait d'inventer une valeur.
            AuditLog::record('stock.adjustment_entry_missing', 'comptabilite');
            $message = "Ajustement enregistré — ATTENTION : perte non comptabilisée (aucun coût d'achat connu pour ce produit, ou compte manquant). À régulariser au Journal Comptable.";
            $type = 'warning';
        }

        $this->dispatch('toast', message: $message, type: $type);
        $this->reset(['adjProductId', 'adjPhysical', 'adjReason']);

        // 🔴→✅ TICKET 14.3 — la lecture de `$this->adjDiff` plus haut a mis en
        // cache `adjDiff` ET `adjSelectedProduct` (que `adjDiff` consulte). Le
        // formulaire venant d'être réinitialisé, ces deux propriétés doivent
        // repartir de l'état vide, sinon le panneau d'ajustement continue
        // d'afficher le produit et l'écart de l'ajustement déjà validé.
        unset($this->adjSelectedProduct, $this->adjDiff);
    }

    public function render()
    {
        return view('livewire.stocks.gestion-stocks', ['title' => 'Gestion des Stocks']);
    }
}
