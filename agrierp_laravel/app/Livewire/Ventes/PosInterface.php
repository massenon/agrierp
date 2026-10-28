<?php

namespace App\Livewire\Ventes;

use App\Actions\AdjustStockAction;
use App\Actions\FlagSaleUnderWithdrawalAction;
use App\Actions\RecordSaleAccountingEntryAction;
use App\Actions\RecordSaleOnFicheElevageAction;
use App\Actions\VerifySaleDateAction;
use App\Exceptions\SaleDateRefusedException;
use App\Exceptions\TransactionInterbloqueeException;
use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\Product;
use App\Models\Receivable;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\VeterinaryWithdrawalPeriod;
use App\Services\Mecef\FacturationMecefService;
use App\Services\TransactionRejouable;
use App\Support\OrdreDesVerrous;
use Livewire\Component;

/**
 * Ticket 4.2 (Sprint 4) — pos-interface.html → Livewire\Ventes\PosInterface
 * PRIORITÉ URGENTE (Document 01 §6.7, message de lancement du projet).
 *
 * VENTE À LA PIÈCE UNIVERSELLE — RÈGLE NON NÉGOCIABLE : tout produit hors
 * devis technique (`pricing_mode = quote`) passe par la modale "Vente à
 * la Pièce" — quantité pré-remplie + montant global éditable
 * (`manual_total_amount`, source de vérité, Document 01 §6.7). JAMAIS un
 * prix unitaire multiplié automatiquement pour produire le total ; c'est
 * l'inverse qui est vrai — `unit_price` n'est dérivé qu'après coup pour
 * l'affichage (`manual_total_amount / qty`). Les produits `pricing_mode =
 * quote` ne rejoignent jamais le panier ici — clic → redirection vers
 * l'onglet Devis (ticket 4.3).
 *
 * BLOCAGE RÉMANENCE RÉEL, CÔTÉ SERVEUR : le prototype simule ce contrôle
 * via localStorage, avec un champ produit "bandeAssociee" inexistant dans
 * le schéma réel. Ici, pour tout produit lié à une espèce d'élevage
 * (`products.species_id` non nul — typiquement un sujet vivant), la
 * modale exige la Bande source réelle, et `confirmWeightAdd()` vérifie
 * `VeterinaryWithdrawalPeriod::isLotBlocked()` (ticket 3.11) avant
 * d'autoriser l'ajout au panier — un blocage réel, jamais contournable en
 * modifiant le DOM ou en désactivant le JavaScript.
 *
 * NON REPRIS DANS CE TICKET, SIGNALÉ EXPLICITEMENT :
 * - ~~Écriture comptable (`sales.accounting_entry_id`) : Sprint 10.~~
 *   🔴→✅ TICKET 14.23 — FAIT. Ce report annoncé « Sprint 10 » n'avait jamais
 *   été levé : AUCUNE vente ne produisait d'écriture, et toute la
 *   comptabilité (Bilan, Balance, Grand Livre, Compte de Résultat, Rapport
 *   Mensuel) affichait zéro produit quel que soit le chiffre d'affaires réel.
 *   `RecordSaleAccountingEntryAction` génère désormais l'écriture dans la
 *   transaction de vente. Les Achats et la Paie restent à câbler de la même
 *   façon — signalé, pas oublié.
 * - "Ajouter Produit Ferme" renvoie vers le vrai formulaire déjà construit
 *   (ticket 2.4) plutôt que de dupliquer un mini-formulaire.
 *
 * ⚠️ MISE À JOUR TICKET 7.1 : la transmission MeCeF (`mecef_qr_ref`,
 * `mecef_status`) est désormais réelle — voir
 * `App\Services\Mecef\MecefGatewayInterface`. TICKET S-T13 : la vente est une
 * transaction rejouée sur interblocage (`TransactionRejouable`) et la facture
 * part APRÈS elle, une seule fois (`FacturationMecefService`).
 *
 * 🔴→✅ EXTENSION DU PATTERN RBAC CRUD AU NIVEAU ACTION (référence
 * initiale : `PlanComptable`) — `$this->authorize('manage-ventes')` sur
 * les 3 actions réellement mutantes (`confirmWeightAdd`,
 * `removeFromCart`, `validateSale`) — pas sur `selectProduct` (ouvre
 * juste la modale, ne mute rien tant que rien n'est confirmé). L'action
 * la plus critique de ce screen (`validateSale`) déplace un vrai
 * mouvement d'argent et de stock — jamais accessible à un futur rôle
 * personnalisé en lecture seule sur le module Ventes.
 *
 * 🔴→✅ MODALE "LIVRAISON" TROUVÉE ABSENTE, CONSTRUITE : `sales.delivery_mode`/
 * `delivery_fee` existaient déjà sur le modèle (fillable depuis le tout
 * premier schéma) mais n'étaient renseignés par AUCUN écran — la modale
 * du prototype n'avait jamais été construite. `delivery_address`/
 * `delivery_contact` ajoutées par migration (n'existaient nulle part).
 *
 * ⚠️ 2 écarts mineurs restants, signalés plutôt que corrigés à la hâte :
 * (1) "Ajouter Produit Ferme" redirige vers le formulaire complet
 * (`/produits/ajouter`) plutôt que d'ouvrir une mini-modale comme le
 * prototype — perd le panier en cours si un caissier l'utilise en
 * pleine vente. Corriger proprement demanderait un vrai quick-add
 * inline, pas juste un lien changé. (2) Le bouton de catégorie
 * "Transformation" (libellé réel du seeder, partagé avec Achats/Stocks)
 * remplace "Produits finis" du prototype — même catégorie sémantique,
 * gardé cohérent avec le reste du projet plutôt que renommé isolément
 * ici.
 */
class PosInterface extends Component
{
    public string $search = '';

    public string $categoryFilter = '';

    public array $cart = [];

    public string $customerId = '';

    public float $discount = 0;

    public string $paymentMode = 'especes';

    public ?float $cashReceived = null;

    // 🔴→✅ TROUVÉ ABSENT PAR COMPARAISON STRUCTURELLE RIGOUREUSE : la
    // modale "Livraison" du prototype n'avait jamais été construite,
    // alors que `sales.delivery_mode`/`delivery_fee` existent déjà
    // réellement sur le modèle (fillable depuis le tout premier schéma)
    // — ces colonnes n'étaient donc jamais renseignées par aucun écran.
    public bool $deliveryConcerned = false;

    public string $deliveryMode = 'gratuite';

    public ?float $deliveryFrais = null;

    public string $deliveryAdresse = '';

    public string $deliveryContact = '';

    public ?string $weightProductId = null;

    public int $weightQty = 1;

    public ?float $weightPrice = null;

    public string $weightLotId = '';

    public string $newClientName = '';

    public string $newClientPhone = '';

    /**
     * Ticket 15.30 (socle) + 15.32 (champ) — « DATE DE LA VENTE » AU PANIER (AAAA-MM-JJ).
     *
     * Décision client du 14/10/2026 : UN SEUL champ, au PANIER (la modale « Vente à la
     * Pièce » est par ligne et n'en porte pas). Valeur par défaut = aujourd'hui, posée par
     * `mount()` : AUJOURD'HUI (ou vide) = vente du jour, comportement STRICTEMENT inchangé
     * (heure réelle, aucun garde de date : le comptoir ne s'arrête pas pour un mois clôturé).
     * Un jour antérieur passe par `VerifySaleDateAction`, le même point que la
     * synchronisation, et son refus s'affiche SOUS le champ.
     *
     * ÉCART ASSUMÉ AVEC LA MAQUETTE : `pos-interface.html` ne porte aucun champ de date
     * (ni au panier ni dans la modale). Il est ajouté par décision du client ; il ne faut
     * pas le « corriger » comme une dérive de portage.
     *
     * Propriété publique, donc modifiable par le client : le serveur re-juge tout.
     */
    public string $dateVente = '';

    public function mount(): void
    {
        $this->dateVente = now()->format('Y-m-d');
    }

    /** Bornes du sélecteur (indicatives : le serveur juge). Max = aujourd'hui, sans dépasser l'exercice ouvert. */
    public function getDateMaxProperty(): string
    {
        $today = now()->format('Y-m-d');
        $finExercice = FiscalYear::where('status', 'ouvert')->max('end_date');

        // Ticket EX3 — le 1er janvier sans la tâche planifiée, la vente du jour ouvrira l'exercice (filet R2) : le jour
        // reste sélectionnable.
        if ($finExercice && $today > substr((string) $finExercice, 0, 10)
            && app(\App\Services\OuvertureExerciceService::class)->filetCouvrirait($today)) {
            return $today;
        }

        return $finExercice ? min($today, substr((string) $finExercice, 0, 10)) : $today;
    }

    /** Ticket EX6 — la même borne que toutes les saisies datées (`AccountingEntryService::premierJourSaisissable`). */
    public function getDateMinProperty(): ?string
    {
        return app(\App\Services\AccountingEntryService::class)->premierJourSaisissable();
    }

    /** Retour immédiat sous le champ, avant même « Valider la Vente » (aucun effet, aucun toast). */
    public function updatedDateVente(): void
    {
        $this->resetErrorBag('dateVente');
        [, $refus] = $this->evaluerDateVente();

        if ($refus !== null) {
            $this->addError('dateVente', $refus);
        }
    }

    /**
     * Juge la date choisie. Retourne [instant|null, refus|null] : instant nul = vente du jour
     * (champ vide ou aujourd'hui), aucun garde de date appliqué.
     *
     * @return array{0: ?\Carbon\Carbon, 1: ?string}
     */
    private function evaluerDateVente(): array
    {
        if ($this->dateVente === '' || $this->dateVente === now()->format('Y-m-d')) {
            return [null, null];
        }

        if (! $this->dateVenteBienFormee()) {
            return [null, 'La date de la vente est invalide.'];
        }

        // Le jour même garde l'heure réelle ; un jour passé prend l'heure courante de ce jour.
        $soldAt = \Carbon\Carbon::parse($this->dateVente)->setTimeFrom(now());

        try {
            app(VerifySaleDateAction::class)->execute($soldAt);
        } catch (SaleDateRefusedException $e) {
            return [null, $e->getMessage()];
        }

        return [$soldAt, null];
    }

    private function dateVenteBienFormee(): bool
    {
        return (bool) preg_match('/^\d{4}-\d{2}-\d{2}$/', $this->dateVente)
            && checkdate((int) substr($this->dateVente, 5, 2), (int) substr($this->dateVente, 8, 2), (int) substr($this->dateVente, 0, 4));
    }

    /** Vente ANTÉRIEURE : la rémanence est alors enregistrée et SIGNALÉE, jamais refusée (décision client). */
    private function estVenteAnterieure(): bool
    {
        return $this->dateVente !== '' && $this->dateVenteBienFormee() && $this->dateVente < now()->format('Y-m-d');
    }

    public function getProductsProperty()
    {
        return Product::with('species')
            ->where('is_active', true)
            ->when($this->search, fn ($q) => $q->where('name', 'like', '%'.$this->search.'%'))
            ->when($this->categoryFilter, fn ($q) => $q->whereHas('category', fn ($q2) => $q2->where('label', $this->categoryFilter)))
            ->orderBy('name')
            ->get();
    }

    public function getCustomersProperty()
    {
        return Customer::where('is_active', true)->orderBy('name')->get();
    }

    public function getWeightProductProperty(): ?Product
    {
        return $this->weightProductId ? Product::find($this->weightProductId) : null;
    }

    public function getLotsForWeightModalProperty()
    {
        if (! $this->weightProduct || ! $this->weightProduct->species_id) {
            return collect();
        }

        return LivestockLot::where('species_id', $this->weightProduct->species_id)
            ->where('status', 'actif')->where('is_active', true)
            ->where('current_quantity', '>', 0)
            ->get();
    }

    public function getSubtotalProperty(): float
    {
        return collect($this->cart)->sum('montant');
    }

    public function getTotalProperty(): float
    {
        return max(0, $this->subtotal - $this->discount);
    }

    public function getChangeDueProperty(): float
    {
        if ($this->paymentMode !== 'especes' || $this->cashReceived === null) {
            return 0;
        }

        return max(0, $this->cashReceived - $this->total);
    }

    public function selectProduct(string $productId): void
    {
        $product = Product::find($productId);

        if (! $product) {
            return;
        }

        if ($product->pricing_mode === 'quote') {
            $this->dispatch('toast', message: $product->name.' — redirection vers Devis pour un chiffrage technique.', type: 'warning');
            $this->redirect(route('ventes.devis-hub', ['tab' => 'devis']), navigate: false);

            return;
        }

        $this->weightProductId = $productId;
        $this->weightQty = 1;
        $this->weightPrice = null;
        $this->weightLotId = '';
        $this->dispatch('open-modal', name: 'modal-weight');
    }

    public function confirmWeightAdd(): void
    {
        $this->authorize('manage-ventes');

        $this->validate([
            'weightQty' => ['required', 'integer', 'min:1'],
            'weightPrice' => ['required', 'numeric', 'min:0'],
        ]);

        $product = $this->weightProduct;

        if (! $product) {
            return;
        }

        if ($product->species_id) {
            if (! $this->weightLotId) {
                $this->addError('weightLotId', 'La bande source est obligatoire pour un sujet vivant.');

                return;
            }

            // 15.32 — vente antérieure : pas de refus à l'ajout, la rémanence sera signalée à la validation.
            if (! $this->estVenteAnterieure() && VeterinaryWithdrawalPeriod::isLotBlocked($this->weightLotId)) {
                $lot = LivestockLot::find($this->weightLotId);
                $this->dispatch('toast', message: "Vente interdite - Bande {$lot?->code} sous remanence veterinaire active. Blocage automatique du systeme.", type: 'error');

                return;
            }
        }

        $lot = $this->weightLotId ? LivestockLot::find($this->weightLotId) : null;

        $this->cart[] = [
            'product_id' => $product->id,
            'name' => $product->name,
            'unit' => $product->unit,
            'qty' => $this->weightQty,
            'montant' => $this->weightPrice,
            'lot_id' => $this->weightLotId ?: null,
            'lot_code' => $lot?->code,
        ];

        AuditLog::record('pos.item_added', 'ventes');
        $this->dispatch('close-modal', name: 'modal-weight');

        // 🔴→✅ TICKET 14.30 — ALERTE DE STOCK, NON BLOQUANTE.
        //
        // Avant ce ticket, cet ecran ne consultait le stock A AUCUN MOMENT :
        // `PosInterface` ne contenait pas une seule reference a `stock_qty`.
        // Une vente pouvait donc faire passer un produit en negatif sans que
        // rien ne le signale, ni au vendeur ni ensuite.
        //
        // ⚠️ ALERTE, ET NON BLOCAGE — decision validee par l'utilisateur
        // (ticket 14.30), a faire confirmer par le Cabinet FAGUEZ : aucun
        // document du projet ne tranche la vente en rupture. Trois raisons
        // metier :
        //   1. l'ERP n'est pas la source de la verite physique — au comptoir le
        //      produit est deja dans les mains du client. Bloquer n'empeche pas
        //      la vente, seulement son ENREGISTREMENT : on perdrait le stock
        //      PLUS la caisse, la TVA et l'ecriture comptable ;
        //   2. le projet est offline-first (Flutter, synchronisation) : deux
        //      postes vendant hors ligne les dernieres unites verraient un lot
        //      rejete a la synchro, argent deja encaisse ;
        //   3. le garde-fou dur existe deja la ou l'enjeu est sanitaire — le
        //      controle de remanence veterinaire ci-dessus, lui, bloque.
        //
        // Un stock negatif signale une ENTREE NON SAISIE, regularisable par
        // l'ajustement manuel de `GestionStocks`.
        $manquant = $this->manquantApresPanier($product);

        if ($manquant > 0) {
            AuditLog::record('pos.stock_insuffisant', 'ventes');

            $this->dispatch(
                'toast',
                message: $product->name.' ajoute au panier — ATTENTION : stock insuffisant de '
                    .rtrim(rtrim(number_format($manquant, 2, ',', ' '), '0'), ',').' '.$product->unit
                    .'. Une entree n a probablement pas ete saisie : regularisez par un ajustement de stock.',
                type: 'warning',
            );

            return;
        }

        $this->dispatch('toast', message: $product->name.' ajoute au panier.', type: 'success');
    }

    /**
     * Quantite manquante pour ce produit une fois TOUT le panier servi.
     *
     * ⚠️ Le cumul porte sur l'ENSEMBLE des lignes du panier portant ce produit,
     * jamais sur la seule ligne ajoutee : deux lignes de 3 unites sur un stock
     * de 5 sont une rupture, alors qu'aucune des deux ne l'est prise seule.
     */
    private function manquantApresPanier(Product $product): float
    {
        $demande = 0.0;

        foreach ($this->cart as $ligne) {
            if (($ligne['product_id'] ?? null) === $product->id) {
                $demande += (float) ($ligne['qty'] ?? 0);
            }
        }

        return round(max(0, $demande - (float) $product->stock_qty), 2);
    }

    public function removeFromCart(int $index): void
    {
        $this->authorize('manage-ventes');

        unset($this->cart[$index]);
        $this->cart = array_values($this->cart);
    }

    public function openAddClientModal(): void
    {
        $this->reset(['newClientName', 'newClientPhone']);
        $this->dispatch('open-modal', name: 'modal-add-client');
    }

    public function saveNewClient(): void
    {
        $this->authorize('manage-ventes');
        $this->validate([
            'newClientName' => ['required', 'string', 'max:150'],
            'newClientPhone' => ['nullable', 'string', 'max:30'],
        ]);

        $customer = Customer::create([
            'name' => $this->newClientName,
            'phone' => $this->newClientPhone ?: null,
            'is_active' => true,
        ]);

        $this->customerId = $customer->id;
        AuditLog::record('customer.created', 'ventes');
        $this->dispatch('close-modal', name: 'modal-add-client');
        $this->dispatch('toast', message: 'Client ajoute avec succes.', type: 'success');
    }

    public function validateSale(): void
    {
        $this->authorize('manage-ventes');

        if (empty($this->cart)) {
            $this->dispatch('toast', message: 'Le panier est vide.', type: 'error');

            return;
        }

        // 🔴→✅ TICKET VTE-1 — CRÉDIT OU AVANCE SANS CLIENT : REFUS MOTIVÉ, AVANT TOUT EFFET. Sans client, la créance (ou
        // l'avance à déduire) n'aurait aucun propriétaire : la vente passait, l'écriture débitait 411, mais aucune ligne
        // `receivables` n'existait (`$sale->customer_id` nul, plus bas) — une créance envers personne. Le comptant, lui,
        // s'enregistre TOUJOURS sans client (« Client Anonyme »). Le poste applique la même règle, avec le même message.
        if (in_array($this->paymentMode, ['credit', 'avance'], true) && $this->customerId === '') {
            $message = $this->paymentMode === 'avance'
                ? 'Une vente sur avance exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».'
                : 'Une vente à crédit exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».';
            $this->addError('customerId', $message);
            $this->dispatch('toast', message: $message, type: 'error');

            return;
        }

        $this->resetErrorBag('customerId');

        // 🔴→✅ TICKET 15.30 — UNE DATE PASSÉE EST JUGÉE AVANT TOUT EFFET (futur, mois clôturé,
        // exercice absent ou clos) par le MÊME point de passage que la synchronisation.
        [$soldAt, $refus] = $this->evaluerDateVente();

        if ($refus !== null) {
            $this->addError('dateVente', $refus);
            $this->dispatch('toast', message: $refus, type: 'error');

            return;
        }

        $this->resetErrorBag('dateVente');

        // 🔴→✅ TICKET 14.21 — CONTOURNEMENT RÉEL DU BLOCAGE DE RÉMANENCE, FERMÉ ICI.
        //
        // Le contrôle de rémanence vétérinaire n'existait QUE dans
        // `confirmWeightAdd()`, l'étape d'ajout au panier. Or `$cart` est une
        // propriété PUBLIQUE Livewire, donc alimentée depuis la requête du
        // client : un panier pouvait arriver directement ici sans jamais
        // rencontrer ce contrôle. Vérifié par test — la vente d'un sujet sous
        // traitement était bel et bien enregistrée, stock décrémenté compris.
        //
        // Second cas, tout aussi réel et sans aucune manipulation : une
        // rémanence déclarée par le vétérinaire APRÈS la mise au panier. Le
        // contrôle doit porter sur l'instant de la VENTE, pas sur celui de la
        // sélection.
        //
        // Le CDC est explicite (Document 00 §7) : « blocage réel, côté serveur,
        // jamais contournable en modifiant le DOM ou en désactivant le
        // JavaScript ». Un garde-fou placé sur l'étape de saisie ne satisfait
        // pas cette exigence — seul un contrôle sur l'action qui engage la
        // vente le peut. Enjeu de sécurité alimentaire, pas de confort.
        //
        // Placé AVANT la transaction : aucune écriture partielle ne doit
        // survivre à un refus.
        foreach ($this->cart as $item) {
            // 15.32 — vente antérieure : enregistrée, rémanence signalée après coup (FlagSaleUnderWithdrawalAction).
            if ($this->estVenteAnterieure() || empty($item['lot_id']) || ! VeterinaryWithdrawalPeriod::isLotBlocked($item['lot_id'])) {
                continue;
            }

            $lot = LivestockLot::find($item['lot_id']);

            $this->dispatch(
                'toast',
                message: "Vente interdite - Bande {$lot?->code} sous remanence veterinaire active. Retirez ce sujet du panier avant de valider.",
                type: 'error',
            );

            return;
        }

        // 🔴→✅ TICKET S-T13 — LA VENTE EST REJOUÉE SUR UN INTERBLOCAGE, COMME L'ENVOI DES POSTES (S-T9).
        //
        // Sur MariaDB, quand des postes envoient au même instant des ventes de la même bande, la caisse du web et leur
        // envoi s'interbloquent (fiche du jour, bande, stock du produit) : la vente du web était annulée et PERDUE
        // (graine 314 de l'essai à plusieurs postes). Toute la vente — pièce, lignes, stock, fiche, créance, écriture,
        // encaissement — est une transaction rejouée jusqu'à 3 fois par `TransactionRejouable`, le même point que
        // l'envoi des postes. Chaque essai annulé n'a rien laissé ; le suivant repart du panier, intact.
        //
        // ⚠️ RIEN DANS L'ESSAI QUI NE S'ANNULE PAS AVEC LUI : ni l'appel MeCeF (une facture partirait deux fois), ni
        // les toasts, ni la remise à zéro du panier (l'essai suivant vendrait un panier vide). Tout cela suit la
        // validation de la transaction, ci-dessous.
        try {
            [$sale, $ecriture, $bandesSignalees] = app(TransactionRejouable::class)->executer(
                fn () => $this->enregistrerVente($soldAt),
                'vente de la caisse web',
            );
        } catch (TransactionInterbloqueeException $e) {
            // Trois interblocages de suite : rien n'est écrit, le panier est gardé tel quel pour revalider.
            $this->dispatch('toast', message: 'Vente NON enregistrée — '.$e->getMessage().' Le panier est conservé : validez à nouveau.', type: 'error');

            return;
        } catch (\App\Exceptions\NoOpenFiscalYearException|\App\Exceptions\ClosedFiscalYearException $e) {
            // 🔴→✅ Ticket EX5 (EF6) — LA VENTE DU JOUR n'est pas jugée par `VerifySaleDateAction` (15.32) : un exercice
            // absent (le filet R2 n'a pas pu ouvrir l'année) remontait de `record()` en erreur 500. Rien n'est écrit
            // (transaction annulée), le panier est gardé, le motif R4 s'affiche sous la date et en toast.
            $refus = VerifySaleDateAction::prefixe($e->getMessage());
            $this->addError('dateVente', $refus);
            $this->dispatch('toast', message: $refus, type: 'error');

            return;
        }

        // 🔴→✅ TICKET S-T13 — LA FACTURE NORMALISÉE, APRÈS LA VENTE VALIDÉE, UNE SEULE FOIS (Document 06 §7, ticket
        // 7.1 : jamais un appel direct à FakeMecefGateway). Un échec ne défait pas la vente : elle passe en « Erreur
        // MeCeF », à retransmettre depuis Facturation & MeCeF (règle du projet depuis le ticket 7.1).
        $facture = app(FacturationMecefService::class)->facturer($sale);

        if ($ecriture === null) {
            // Jamais silencieux : mode de règlement non mappé (« avance »)
            // ou plan comptable incomplet. La vente reste enregistrée — le
            // fait commercial prime — mais l'écart est signalé pour
            // régularisation au Journal, pas dissimulé.
            $this->dispatch('toast', message: 'Vente enregistree - ATTENTION : ecriture comptable non generee (mode de reglement ou compte manquant). A regulariser au Journal Comptable.', type: 'warning');
        } else {
            $this->dispatch('toast', message: 'Vente enregistree avec succes - total '.number_format($this->total, 0, ',', ' ').' FCFA.', type: 'success');
        }

        if (! $facture['transmise'] && ! ($facture['inactif'] ?? false)) {
            $this->dispatch('toast', message: 'Vente enregistrée — ATTENTION : facture normalisée MeCeF non transmise ('.$facture['message'].'). La vente reste à facturer : retransmettez-la depuis Facturation & MeCeF.', type: 'warning');
        }

        if ($bandesSignalees !== []) {
            $this->dispatch('toast', message: 'Vente antérieure enregistrée — ATTENTION : bande(s) '.implode(', ', $bandesSignalees)." sous délai d'attente vétérinaire à cette date. Signalée à l'administrateur.", type: 'warning');
        }

        $this->cart = [];
        $this->dateVente = now()->format('Y-m-d');
        $this->customerId = '';
        $this->discount = 0;
        $this->cashReceived = null;
        $this->deliveryConcerned = false;
        $this->deliveryMode = 'gratuite';
        $this->deliveryFrais = null;
        $this->deliveryAdresse = '';
        $this->deliveryContact = '';

        // 🔴→✅ TICKET 14.2 — MÊME DÉFAUT QUE `ClotureExercice`, trouvé par
        // recherche systématique du motif et non par hasard : `subtotal`,
        // `total` et `changeDue` sont des propriétés calculées, mémoïsées
        // par Livewire pour la durée de la requête (elles viennent d'être
        // lues plus haut pour construire la vente). Le panier étant vidé
        // juste au-dessus, le rendu qui suit réaffichait le total de la
        // vente DÉJÀ ENCAISSÉE au-dessus d'un panier vide — la caissière
        // voyait un montant ne correspondant plus à rien.
        unset($this->subtotal, $this->total, $this->changeDue);
    }

    /**
     * Ticket S-T13 — UN ESSAI de la transaction de vente (rejoué sur interblocage par `validateSale`) : uniquement des
     * écritures en base, qui s'annulent avec lui. Rend la vente, son écriture (nulle si non générée) et les bandes
     * signalées sous délai d'attente.
     *
     * @return array{0: Sale, 1: ?\App\Models\AccountingEntry, 2: array<int, string>}
     */
    private function enregistrerVente(?\Carbon\Carbon $soldAt): array
    {
        // 🔴→✅ Ticket U14 — ORDRE DES VERROUS (`OrdreDesVerrous`) : le stock du panier, par identifiant croissant, AVANT la
        // fiche du jour — le même ordre que l'envoi des postes et que les fiches. Le tri évite aussi l'interblocage entre
        // deux paniers aux mêmes produits saisis dans un ordre différent.
        OrdreDesVerrous::stock([
            ...array_column($this->cart, 'product_id'),
            ...OrdreDesVerrous::produitsDesFiches(array_column($this->cart, 'lot_id')),
        ]);

        $sale = Sale::create([
            'customer_id' => $this->customerId ?: null,
            'payment_mode' => $this->paymentMode,
            'subtotal' => $this->subtotal,
            'discount' => $this->discount,
            'total' => $this->total,
            'cash_received' => $this->paymentMode === 'especes' ? $this->cashReceived : null,
            'change_due' => $this->paymentMode === 'especes' ? $this->changeDue : null,
            'status' => 'validee',
            // TICKET 14.71 — au comptoir, date de vente = maintenant. La
            // colonne est renseignee ici AUSSI pour qu'elle soit toujours
            // exploitable : un rapport qui ferait `sold_at ?? created_at`
            // par endroits et `sold_at` ailleurs divergerait de lui-meme.
            'sold_at' => $soldAt ?? now(),
            'delivery_mode' => $this->deliveryConcerned ? $this->deliveryMode : null,
            // 🔴→✅ TICKET 14.2 — BUG BLOQUANT TROUVÉ EN EXÉCUTANT RÉELLEMENT
            // UNE VENTE : `sales.delivery_fee` est `decimal(14,2) NOT NULL
            // DEFAULT 0` (migration 2026_02_16_000002). Écrire `null`
            // explicitement écrase le DEFAULT et viole la contrainte —
            // vérifié sur le MySQL réel du projet, en `STRICT_TRANS_TABLES` :
            // « Column 'delivery_fee' cannot be null ». La condition n'étant
            // vraie QUE pour une livraison facturée, **toute vente ordinaire
            // échouait à l'enregistrement**. Jamais détecté jusqu'ici :
            // aucune vente n'avait encore été passée sur une base réelle
            // (table `sales` vide) et la suite de tests était elle-même
            // inexécutable avant le ticket 14.1.
            // 0 plutôt que `null` : c'est la valeur que le schéma prévoit
            // pour « aucun frais de livraison ».
            'delivery_fee' => $this->deliveryConcerned && $this->deliveryMode === 'facturee' ? ($this->deliveryFrais ?? 0) : 0,
            'delivery_address' => $this->deliveryConcerned ? ($this->deliveryAdresse ?: null) : null,
            'delivery_contact' => $this->deliveryConcerned ? ($this->deliveryContact ?: null) : null,
        ]);

        foreach ($this->cart as $item) {
            SaleLine::create([
                'sale_id' => $sale->id,
                'product_id' => $item['product_id'],
                // Ticket 14.44 — la bande vendue était connue du panier
                // (exigée par le contrôle de rémanence) mais n'était
                // jamais conservée : aucun revenu par bande n'était donc
                // chiffrable au Bilan Technico-Économique.
                'lot_id' => $item['lot_id'] ?? null,
                'qty' => $item['qty'],
                'unit_price' => $item['qty'] > 0 ? round($item['montant'] / $item['qty'], 2) : 0,
                'manual_total_amount' => $item['montant'],
                'is_manual_price' => true,
            ]);

            $product = Product::find($item['product_id']);
            if ($product) {
                app(AdjustStockAction::class)->execute($product, -$item['qty'], 'sale', $sale->id, $soldAt);
            }
        }

        // Ticket 14.4 — répercussion réelle sur les fiches d'élevage.
        $this->recordFicheVente($soldAt);

        // 15.32 — rémanence d'une vente ANTÉRIEURE : enregistrée ET signalée (notification admin + audit).
        $bandesSignalees = $soldAt !== null
            ? app(FlagSaleUnderWithdrawalAction::class)->execute($sale->fresh('lines'))
            : [];

        // Correction rétroactive (ticket 4.7) : une vente à crédit crée
        // réellement une créance — plus jamais un solde dérivé approximativement.
        if ($this->paymentMode === 'credit' && $sale->customer_id) {
            Receivable::create([
                'customer_id' => $sale->customer_id,
                'sale_id' => $sale->id,
                'amount' => $sale->total,
                'amount_paid' => 0,
                'due_date' => ($soldAt ?? now())->copy()->addDays(30),
                'status' => 'en_cours',
            ]);
        }

        // 🔴→✅ TICKET 14.23 — ÉCRITURE COMPTABLE ENFIN GÉNÉRÉE.
        //
        // Jusqu'ici AUCUNE vente ne produisait d'écriture : Bilan, Balance,
        // Grand Livre, Compte de Résultat et Rapport Mensuel affichaient
        // zéro produit quel que soit le chiffre d'affaires réel. Le CDC
        // l'exige pourtant ("toute opération financière déclenche la
        // génération automatique de l'écriture correspondante"), et le
        // rétro-câblage était annoncé comme différé au ticket 10.2 —
        // jamais réalisé.
        //
        // Dans la transaction : une vente enregistrée sans son écriture
        // laisserait la comptabilité en retard sur l'exploitation, ce que
        // ce ticket corrige précisément.
        $ecriture = app(RecordSaleAccountingEntryAction::class)->execute($sale);

        // 🔴→✅ TICKET 14.32 — ENCAISSEMENT RÉEL. Avant ce ticket, une vente
        // au comptant n'augmentait jamais la caisse : l'écriture débitait
        // bien 531 au grand livre, mais `treasury_accounts.balance` ne
        // bougeait pas. Les deux livres de trésorerie divergeaient dès la
        // première vente, et seuls les décaissements faisaient bouger le
        // solde affiché — qui dérivait donc vers le négatif.
        app(\App\Actions\CreditTreasuryForSaleAction::class)->execute($sale);

        AuditLog::record('sale.validated', 'ventes');

        // Ticket 14.30 : le negatif se produit ICI, a la decrementation
        // reelle. Journalise nommement pour qu'une anomalie de stock reste
        // investigable meme si le vendeur a ignore l'alerte au panier.
        foreach ($this->cart as $item) {
            $produitVendu = Product::find($item['product_id']);

            if ($produitVendu && $produitVendu->stockEstNegatif()) {
                AuditLog::record('stock.negatif_apres_vente', 'stocks');
            }
        }

        if ($ecriture === null) {
            AuditLog::record('sale.accounting_entry_missing', 'comptabilite');
        }

        return [$sale, $ecriture, $bandesSignalees];
    }

    /**
     * Ticket 14.4 — LIEN VENTE → FICHE ÉLEVAGE, enfin réel.
     *
     * Spécification trouvée dans le prototype lui-même
     * (`assets/js/agrisync-store.js`, `addVente()` → `recordFicheVente()`) :
     * *"incremente le compteur de ventes du jour pour chaque espece
     * concernee"*. Un moteur de démonstration JavaScript peut porter une
     * spécification métier complète — c'est le cas ici, et elle n'avait
     * jamais été transposée côté Laravel.
     *
     * DIFFÉRENCE ASSUMÉE AVEC LE PROTOTYPE, DANS LE SENS DE LA PRÉCISION :
     * le store JS compte par ESPÈCE (`data[espece][dateISO]`), faute de
     * notion de bande. Ici, `confirmWeightAdd()` **exige déjà** la bande
     * source pour tout produit lié à une espèce (`products.species_id`,
     * contrôle de rémanence vétérinaire) — la vente est donc imputée à la
     * BANDE RÉELLE vendue, jamais répartie par une heuristique. Aucune
     * hypothèse FIFO n'est nécessaire : l'information exacte existe déjà
     * dans le panier.
     *
     * L'effectif final du jour est recalculé par
     * `LivestockDailyEntry::computeEffectifFinal()` — le même point de
     * vérité que les 5 fiches, jamais une seconde formule ici. Si
     * l'animalier a déjà enregistré sa journée, l'écriture est complétée,
     * jamais écrasée.
     *
     * ⚠️ RÈGLE D'ANNULATION, EXPLICITE DANS LE PROTOTYPE : `annulerVente()`
     * restitue le stock mais *"ne retire PAS le mouvement deja comptabilise
     * dans les fiches d'elevage du jour"* — l'historique zootechnique reste
     * distinct de l'aspect commercial. Aucun code de reprise n'est donc
     * ajouté ici : c'est la règle, pas un oubli.
     */
    private function recordFicheVente(?\Carbon\Carbon $soldAt = null): void
    {
        // ⚠️ TICKET 14.53 — LA ROUTINE A ÉTÉ EXTRAITE DANS
        // `RecordSaleOnFicheElevageAction`. Elle vivait ici en méthode privée,
        // donc inatteignable depuis la synchronisation : une vente saisie hors
        // ligne sur le poste Desktop n'avait aucun effet sur la fiche. La
        // recopier là-bas aurait produit deux implémentations d'une même règle.
        app(RecordSaleOnFicheElevageAction::class)->execute(
            array_map(
                fn ($item) => ['lot_id' => $item['lot_id'] ?? null, 'qty' => (int) $item['qty']],
                $this->cart,
            ),
            $soldAt?->format('Y-m-d'),
        );
    }

    public function render()
    {
        return view('livewire.ventes.pos-interface');
    }
}
