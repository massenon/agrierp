<?php

namespace App\Livewire\Dashboard;

use Illuminate\Support\Facades\Schema;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 1.3 (Sprint 1) — dashboard.html → Livewire\Dashboard\Index
 * Référence : Document 05 Module 1.
 *
 * 🔴→✅ GAP SYSTÉMIQUE CRITIQUE TROUVÉ PAR VÉRIFICATION STRUCTURELLE
 * RIGOUREUSE, CORRIGÉ DANS CE TICKET : ce composant était resté figé
 * dans son état du ticket 1.3/1.4 — chaque section interrogeait bien
 * `Schema::hasTable(...)` (le "gate" fonctionnait, `pending` passait
 * correctement à `false`), MAIS la valeur réelle promise
 * ("valeur réelle calculée ici une fois la table disponible") n'avait
 * jamais été écrite — juste un commentaire resté en l'état. Résultat
 * concret : l'écran le PLUS consulté de tout le projet affichait encore
 * "en attente" ou un contenu vide pour la quasi-totalité de son contenu
 * métier (CA, Dépenses, Résultat Net, Créances, Dettes, Effectif
 * Animaux, graphique, 3 cartes élevage, 5 onglets de transactions
 * récentes, Top Produits) — alors que Sprints 2 à 10 sont TOUS terminés
 * depuis longtemps et que chaque table requise existe réellement.
 *
 * Toutes les requêtes réelles sont désormais écrites ci-dessous,
 * réutilisant les champs/accesseurs déjà établis ailleurs dans le projet
 * (`Receivable::balance`, `Payable::balance`, `SaleLine::manual_total_amount`
 * — toujours le total réel de ligne qu'il ait été saisi manuellement ou
 * calculé, `LivestockDailyEntry::mortality_rate`) — un seul point de
 * vérité par donnée, jamais une seconde formule inventée ici.
 *
 * `Schema::hasTable(...)` conservé malgré tout — filet de sécurité
 * légitime si ce projet est un jour déployé par étapes incomplètes,
 * coût de vérification négligeable.
 *
 * "Activités du Jour" interroge `audit_logs` sans filtre utilisateur
 * (contrairement à Mon Profil) — alimentée organiquement par chaque
 * `AuditLog::record()` métier déjà réel depuis plusieurs sprints.
 */
#[Layout('layouts.app')]
class Index extends Component
{
    public function getKpisProperty(): array
    {
        $monthStart = now()->startOfMonth();
        $prevMonthStart = now()->subMonthNoOverflow()->startOfMonth();
        $prevMonthEnd = now()->subMonthNoOverflow()->endOfMonth();

        $ca = $this->realOrPendingKpi('sales', 'Sprint 4 (Ventes Ferme)', function () use ($monthStart, $prevMonthStart, $prevMonthEnd) {
            $current = (float) \App\Models\Sale::soldSince($monthStart)->sum('total');
            $previous = (float) \App\Models\Sale::soldBetweenInstants($prevMonthStart, $prevMonthEnd)->sum('total');

            return ['value' => $current, 'previous' => $previous];
        });

        $depenses = $this->realOrPendingKpi('purchases', 'Sprint 5 (Achats & Charges)', function () use ($monthStart, $prevMonthStart, $prevMonthEnd) {
            $current = (float) \App\Models\Purchase::where('purchase_date', '>=', $monthStart)->sum('total');
            $previous = (float) \App\Models\Purchase::whereBetween('purchase_date', [$prevMonthStart, $prevMonthEnd])->sum('total');

            return ['value' => $current, 'previous' => $previous];
        });

        $resultatNet = null;
        if (! $ca['pending'] && ! $depenses['pending']) {
            $resultatNet = ['pending' => false, 'value' => $ca['value']['value'] - $depenses['value']['value']];
        } else {
            $resultatNet = ['pending' => true, 'since' => 'Sprints 4-5 (Ventes + Achats)'];
        }

        return [
            'ca' => ['pending' => $ca['pending'], 'since' => $ca['since'] ?? null, 'value' => $ca['value']['value'] ?? null, 'previous' => $ca['value']['previous'] ?? null],
            'tresorerie' => $this->realOrPendingKpi(
                'treasury_accounts',
                'Sprint 2 (Référentiels)',
                fn () => (float) \App\Models\TreasuryAccount::where('is_active', true)->sum('balance')
            ),
            'depenses' => ['pending' => $depenses['pending'], 'since' => $depenses['since'] ?? null, 'value' => $depenses['value']['value'] ?? null, 'previous' => $depenses['value']['previous'] ?? null],
            'resultat_net' => $resultatNet,
            'creances' => $this->realOrPendingKpi(
                'receivables',
                'Sprint 4 (Ventes Ferme)',
                fn () => (float) \App\Models\Receivable::whereColumn('amount_paid', '<', 'amount')->get()->sum('balance')
            ),
            'dettes' => $this->realOrPendingKpi(
                'payables',
                'Sprint 5 (Achats & Charges)',
                fn () => (float) \App\Models\Payable::whereColumn('amount_paid', '<', 'amount')->get()->sum('balance')
            ),
            // Corrigé au ticket 2.7 : dépendait à tort de `stock_movements`
            // (Sprint 6, ledger des mouvements) alors que le niveau de
            // stock COURANT vit déjà sur `products.stock_qty`/
            // `alert_threshold`, créée au ticket 2.2 — pas besoin d'
            // attendre le ledger de mouvements pour un simple comptage.
            'stock_critique' => $this->realOrPendingKpi(
                'products',
                'Sprint 2 (Référentiels)',
                fn () => \App\Models\Product::where('is_active', true)->whereColumn('stock_qty', '<=', 'alert_threshold')->count()
            ),
            'effectif_animaux' => $this->realOrPendingKpi(
                'livestock_lots',
                'Sprint 3 (Production Élevage)',
                fn () => (int) \App\Models\LivestockLot::where('is_active', true)->where('status', 'actif')->sum('current_quantity')
            ),
        ];
    }

    public function getChartVentesDepensesProperty(): ?array
    {
        if (! Schema::hasTable('sales') || ! Schema::hasTable('purchases')) {
            return null; // Sprints 4-5
        }

        $labels = [];
        $ca = [];
        $depenses = [];

        for ($i = 5; $i >= 0; $i--) {
            $monthDate = now()->subMonthsNoOverflow($i);
            $labels[] = $monthDate->translatedFormat('M');
            $ca[] = (float) \App\Models\Sale::soldBetweenInstants($monthDate->copy()->startOfMonth(), $monthDate->copy()->endOfMonth())->sum('total');
            $depenses[] = (float) \App\Models\Purchase::whereBetween('purchase_date', [$monthDate->copy()->startOfMonth(), $monthDate->copy()->endOfMonth()])->sum('total');
        }

        return ['labels' => $labels, 'ca' => $ca, 'depenses' => $depenses];
    }

    public function getActivitesJourProperty()
    {
        // audit_logs existe depuis le ticket 1.2 et est déjà alimentée
        // réellement (connexion/déconnexion, modification de mot de passe).
        // Cette section s'enrichira organiquement à mesure que chaque
        // module métier appelle AuditLog::record() — aucune modification
        // de ce fichier ne sera nécessaire (voir docblock de la classe).
        return \App\Models\AuditLog::with('user:id,name')
            ->whereDate('created_at', now()->toDateString())
            ->latest('created_at')
            ->limit(8)
            ->get();
    }

    public function getAlertesCritiquesProperty(): array
    {
        $alerts = [];

        // Sprint 2 : alertes de stock réelles (products.stock_qty <= alert_threshold)
        if (Schema::hasTable('products')) {
            foreach (\App\Models\Product::where('is_active', true)
                ->whereColumn('stock_qty', '<=', 'alert_threshold')
                ->limit(5)
                ->get() as $product) {
                $alerts[] = [
                    'label' => "Stock critique — {$product->name} ({$product->stock_qty} {$product->unit} restant(s))",
                    'severity' => 'critique',
                    'link' => '/gestion-stocks',
                ];
            }
        }

        // Mortalité anormale sur les 7 derniers jours, un lot alerté au plus.
        //
        // 🔴→✅ TICKET F0.32 — LA BORNE ÉTAIT `> 5`, LE PROTOTYPE DIT `>= 5`.
        // `gestion-elevage.html` écrit noir sur blanc :
        //   if (tauxMortalite >= 5) { 'Attention : Seuil critique dépassé !' }
        //   else                    { 'Seuil normal < 5%' }
        // À exactement 5,0 %, le prototype alerte et ce code se taisait.
        //
        // ⚠️ **DIVERGENCE DE FORMULE, NON RÉSOLUE ICI — ARBITRAGE CLIENT.**
        // Trois calculs coexistent dans le projet :
        //   1. ici, le PIRE JOUR des sept derniers (`mortality_rate` d'une
        //      fiche) ;
        //   2. `gestion-elevage.html`, un CUMUL mensuel : (Cumul des Morts du
        //      Mois / Effectif Initial Cumulé) × 100 ;
        //   3. le poste Flutter, un CUMUL sur sept jours rapporté à
        //      l'effectif initial de la bande.
        // Le cumul est strictement plus sensible : une bande qui perd 4 % par
        // jour pendant une semaine n'alerte JAMAIS avec la règle du pire jour.
        // Aucun document du projet ne tranche la formule de l'ALERTE (la
        // maquette du tableau de bord n'affiche qu'un texte, « >10% »). En
        // choisir une ici sans mandat serait décider à la place du client.
        // Ticket 15.49 — la règle vit désormais dans `AlertesElevageService` (même seuil, bandes archivées exclues),
        // que la cloche partage : l'écran et la notification ne peuvent plus diverger.
        if (Schema::hasTable('livestock_daily_entries')) {
            foreach (app(\App\Services\AlertesElevageService::class)->mortalitesAnormales() as $worst) {
                $alerts[] = [
                    'label' => "Mortalité anormale — Lot {$worst->lot->code} (".number_format($worst->mortality_rate, 1, ',', ' ').'%)',
                    'severity' => 'critique',
                    'link' => '/gestion-bandes',
                ];
            }
        }

        // Créances en retard (échéance dépassée, solde non soldé).
        if (Schema::hasTable('receivables')) {
            foreach (\App\Models\Receivable::with('customer')
                ->whereColumn('amount_paid', '<', 'amount')
                ->where('due_date', '<', now())
                ->limit(3)
                ->get() as $receivable) {
                $days = (int) now()->diffInDays($receivable->due_date);
                $alerts[] = [
                    'label' => "Créance en retard — {$receivable->customer?->name} ({$days} jours)",
                    'severity' => 'moyen',
                    'link' => '/creances-clients',
                ];
            }
        }

        return array_slice($alerts, 0, 6);
    }

    public function getCartesElevageProperty(): ?array
    {
        if (! Schema::hasTable('livestock_lots') || ! Schema::hasTable('livestock_daily_entries')) {
            return null; // Sprint 3
        }

        $effectif = fn (string $code) => (int) \App\Models\LivestockLot::where('is_active', true)->where('status', 'actif')
            ->whereHas('species', fn ($q) => $q->where('code', $code))->sum('current_quantity');

        $mortaliteMois = function (string $code) {
            $lotIds = \App\Models\LivestockLot::where('is_active', true)->whereHas('species', fn ($q) => $q->where('code', $code))->pluck('id');   // bande archivée exclue
            $entries = \App\Models\LivestockDailyEntry::whereIn('lot_id', $lotIds)->where('entry_date', '>=', now()->startOfMonth())->get();
            $totalMorts = $entries->sum('mort');
            $effectifRef = $entries->sum(fn ($e) => max($e->effectif_final - $e->achat - $e->ne + $e->mort + $e->vente + $e->don, 1));

            return $effectifRef > 0 ? round(($totalMorts / $effectifRef) * 100, 1) : 0.0;
        };

        // "Gestantes" (Lapins/Porcs) : événements de reproduction en cours
        // (`status = 'en_cours'`, ticket 3.10) — un seul point de vérité,
        // même statut que celui posé/consulté par SuiviReproduction.
        $gestantes = fn (string $code) => \App\Models\LivestockReproductionEvent::whereHas('lot', fn ($q) => $q->whereHas('species', fn ($q2) => $q2->where('code', $code)))
            ->where('status', 'en_cours')->count();

        return [
            'lapins' => [
                'effectif' => $effectif('cuniculture'),
                'gestantes' => $gestantes('cuniculture'),
                // "Marchands" : sujets au stade Engraissement (prêts à la
                // vente) — interprétation directe du stage réellement posé
                // sur chaque bande (ticket 3.2), jamais un chiffre inventé.
                'marchands' => (int) \App\Models\LivestockLot::where('is_active', true)->where('status', 'actif')->where('stage', 'engraissement')
                    ->whereHas('species', fn ($q) => $q->where('code', 'cuniculture'))->sum('current_quantity'),
                'mortalite' => $mortaliteMois('cuniculture'),
            ],
            'volailles' => [
                'lots_actifs' => \App\Models\LivestockLot::where('is_active', true)->where('status', 'actif')->whereHas('species', fn ($q) => $q->where('code', 'aviculture'))->count(),
                'taux_ponte' => (function () {
                    $lotIds = \App\Models\LivestockLot::where('is_active', true)->whereHas('species', fn ($q) => $q->where('code', 'aviculture'))->pluck('id');   // bande archivée exclue
                    $entries = \App\Models\LivestockDailyEntry::whereIn('lot_id', $lotIds)->where('entry_date', '>=', now()->startOfMonth())->get();
                    $totalPonte = $entries->sum('ponte_total');
                    $effectifPondeuses = $entries->sum('effectif_final');

                    return $effectifPondeuses > 0 ? round(($totalPonte / $effectifPondeuses) * 100, 0) : 0;
                })(),
                'effectif' => $effectif('aviculture'),
                'mortalite' => $mortaliteMois('aviculture'),
            ],
            'porcs' => [
                'effectif' => $effectif('porciculture'),
                'gestantes' => $gestantes('porciculture'),
                // Approximation assumée : ventes du mois de produits de la
                // catégorie "Porciculture" (nom exact du seeder) — pas un
                // filtre par espèce individuelle sur chaque sujet vendu
                // (aucun lien direct vente↔lot n'existe dans le schéma).
                'ventes_mois' => (int) \App\Models\SaleLine::whereHas('product', fn ($q) => $q->whereHas('category', fn ($q2) => $q2->where('label', 'Porciculture')))
                    ->whereHas('sale', fn ($q) => $q->soldSince(now()->startOfMonth()))->count(),
                'mortalite' => $mortaliteMois('porciculture'),
            ],
        ];
    }

    public function getTransactionsRecentesProperty(): array
    {
        return [
            'sale' => Schema::hasTable('sales') ? \App\Models\Sale::with('customer')->orderByEffectiveDate()->limit(5)->get() : null,
            'purchase' => Schema::hasTable('purchases') ? \App\Models\Purchase::with('supplier')->latest('purchase_date')->limit(5)->get() : null,
            'quotation' => Schema::hasTable('quotes') ? \App\Models\Quote::with('customer')->latest('created_at')->limit(5)->get() : null,
            // Corrigé : "Dépenses" est un modèle `Expense` réellement
            // distinct de `Purchase` (charges diverses hors achats de
            // marchandises — `SaisieDepenses`, ticket 5.8), pas un
            // sous-ensemble d'achats filtré par mode de paiement.
            'expenses' => Schema::hasTable('expenses') ? \App\Models\Expense::where('is_active', true)->latest('expense_date')->limit(5)->get() : null,
            // Facturation réutilise `Sale` directement (ticket 7.x, pas de
            // modèle `Invoice` séparé — un seul point de vérité).
            // `mecef_status` a une valeur par défaut ('en_attente'), jamais
            // NULL — filtrer sur 'transmise' pour ne retenir que les
            // factures réellement émises, pas toutes les ventes.
            'invoices' => Schema::hasTable('sales') ? \App\Models\Sale::with('customer')->where('mecef_status', 'transmise')->orderByEffectiveDate()->limit(5)->get() : null,
        ];
    }

    public function getTopProduitsProperty(): ?array
    {
        if (! Schema::hasTable('sale_lines')) {
            return null; // Sprint 4
        }

        return \App\Models\SaleLine::selectRaw('product_id, SUM(qty) as total_qty, SUM(manual_total_amount) as total_ca')
            ->whereHas('sale', fn ($q) => $q->soldSince(now()->startOfMonth()))
            ->groupBy('product_id')
            ->orderByDesc('total_ca')
            ->with('product')
            ->limit(5)
            ->get()
            ->map(function ($row) {
                $pmp = $row->product?->computePmp();
                $margePct = null;
                if ($pmp !== null && $row->total_qty > 0 && $row->total_ca > 0) {
                    $coutTotal = $pmp * $row->total_qty;
                    $margePct = round((($row->total_ca - $coutTotal) / $row->total_ca) * 100);
                }

                return [
                    'product' => $row->product,
                    'qty' => (float) $row->total_qty,
                    'ca' => (float) $row->total_ca,
                    'marge_pct' => $margePct,
                ];
            })
            ->toArray();
    }

    private function realOrPendingKpi(string $requiredTable, string $since, \Closure $computeValue): array
    {
        if (! Schema::hasTable($requiredTable)) {
            return ['pending' => true, 'since' => $since];
        }

        return ['pending' => false, 'value' => $computeValue()];
    }

    public function render()
    {
        return view('livewire.dashboard.index', ['title' => 'Tableau de Bord']);
    }
}
