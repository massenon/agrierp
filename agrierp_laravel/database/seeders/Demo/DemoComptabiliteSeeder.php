<?php

namespace Database\Seeders\Demo;

use App\Actions\RecordAssetAcquisitionEntryAction;
use App\Actions\RecordDepreciationEntryAction;
use App\Models\AccountingEntry;
use App\Models\BankStatementLine;
use App\Models\FixedAsset;
use App\Models\Payable;
use App\Models\PeriodicClosure;
use App\Models\TreasuryAccount;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.31 (Sprint 14) — COMPTABILITÉ de démonstration, arrêtée en dernier.
 *
 * ⚠️ CE SEEDER NE CRÉE AUCUNE ÉCRITURE À LA MAIN. Il se contente de déclencher
 * les Actions qui CONSTATENT ce que les autres modules ont produit :
 * capitalisation des immobilisations, puis dotation aux amortissements. Toutes
 * les autres écritures — ventes, achats, paie, avoirs — ont déjà été générées
 * par leurs flux respectifs. C'est pour cela qu'il passe en dernier.
 *
 * ⚠️ LA DOTATION EST CALCULÉE, PAS INVENTÉE. `RecordDepreciationEntryAction`
 * poste l'ÉCART entre l'amortissement cumulé théorique à la date d'arrêté et
 * ce qui est déjà porté au crédit de 281 (ticket 14.26). Le montant dépend donc
 * réellement des immobilisations et de leur ancienneté.
 */
class DemoComptabiliteSeeder extends Seeder
{
    public function __construct(private DemoContexte $ctx) {}

    public function run(): void
    {
        $this->capitaliserLesImmobilisations();
        $this->reglerDettes();
        $this->deposerLesRecettesEnBanque();
        $dotation = $this->passerLaDotation();
        $this->creerReleveBancaire();
        $this->cloturerLesMoisRevolus();

        $this->command?->info('  Comptabilité : '.AccountingEntry::count().' écritures, '
            .'dotation '.number_format($dotation, 0, ',', ' ').' FCFA, '
            .BankStatementLine::count().' lignes de relevé, '
            .PeriodicClosure::count().' périodes clôturées.');
    }

    /**
     * Les 3 immobilisations semées le sont en reprise d'antériorité
     * (`is_capitalized = false`, ticket 14.26). En simulation, on les fait
     * entrer à l'actif au premier jour de la période — sans quoi l'Actif
     * Immobilisé du Bilan resterait vide et la dotation n'aurait rien à
     * amortir.
     *
     * ⚠️ Contrepartie 401 Fournisseurs (acquisition à crédit) plutôt qu'une
     * trésorerie : faire sortir 3,87 M FCFA de la caisse au premier jour
     * viderait une trésorerie qui n'a pas encore encaissé la moindre vente.
     */
    private function capitaliserLesImmobilisations(): void
    {
        foreach (FixedAsset::active()->where('is_capitalized', false)->orderBy('code')->get() as $bien) {
            // Date d'acquisition ramenée dans l'exercice ouvert : une écriture
            // datée hors exercice serait refusée par `AccountingEntryService`.
            $bien->update(['acquisition_date' => $this->ctx->debut->format('Y-m-d')]);

            // ⚠️ APPORT EN CAPITAL, jamais dette ni décaissement. Ces 3 biens
            // sont semés en REPRISE D'ANTÉRIORITÉ : la ferme les possède déjà.
            // Les porter au crédit de 401 créait 3 870 000 FCFA de dettes
            // fournisseurs fantômes — que le règlement automatique s'employait
            // ensuite à « payer », vidant une trésorerie qui n'aurait jamais dû
            // être ponctionnée. Contrepartie juste : le capital (ticket 14.34).
            app(RecordAssetAcquisitionEntryAction::class)
                ->recordOpeningContribution($bien->fresh(), $this->ctx->debut->format('Y-m-d'));
        }
    }

    private function passerLaDotation(): float
    {
        $ecriture = app(RecordDepreciationEntryAction::class)->execute($this->ctx->fin->format('Y-m-d'));

        return $ecriture ? (float) $ecriture->total_debit : 0.0;
    }

    /**
     * Règlement partiel des dettes fournisseurs, par la même Action que
     * l'écran (ticket 14.34).
     *
     * ⚠️ Toutes ne sont pas soldées : une dette qui subsiste est ce qui rend
     * l'écran Dettes Fournisseurs et son suivi d'échéances démontrables.
     *
     * ⚠️ PLACÉE ICI, APRÈS LES VENTES, ET NON DANS LE SEEDER DES ACHATS. Le
     * seeder passe cinq mois d'achats avant la première vente — un ordre
     * d'exécution, jamais une chronologie réelle. Régler les dettes à ce
     * moment-là ponctionnait une trésorerie qui n'avait encore rien encaissé,
     * et le compte le mieux pourvu finissait à −2,8 M. Les règlements suivent
     * donc les encaissements, comme dans la vie de l'exploitation.
     */
    private function reglerDettes(): void
    {
        $action = app(\App\Actions\RecordSettlementAccountingEntryAction::class);

        foreach (Payable::with('supplier')->orderBy('due_date')->orderBy('id')->get() as $dette) {
            if (! $this->ctx->chance(60)) {
                continue;
            }

            $reste = (float) $dette->amount - (float) $dette->amount_paid;
            $montant = round($reste * ($this->ctx->chance(50) ? 1.0 : 0.5), 2);

            if ($montant <= 0) {
                continue;
            }

            $tresorerie = $this->ctx->compteSolvable($montant);

            if (! $tresorerie) {
                return;
            }

            $date = \Carbon\CarbonImmutable::parse($dette->due_date ?? $this->ctx->fin);

            if ($date->gt($this->ctx->fin)) {
                $date = $this->ctx->fin;
            }

            $dette->update([
                'amount_paid' => (float) $dette->amount_paid + $montant,
                'status' => $montant >= $reste ? 'soldee' : 'en_cours',
            ]);

            $tresorerie->decrement('balance', $montant);

            $action->payToSupplier(
                $tresorerie, $montant, $dette->supplier?->name, $dette->id, $date->format('Y-m-d')
            );
        }
    }

    /**
     * Dépôt mensuel des recettes en banque — ticket 14.35.
     *
     * ⚠️ C'EST L'USAGE RÉEL, et la raison d'être du virement interne : la ferme
     * encaisse l'essentiel en espèces et par Mobile Money, puis dépose
     * périodiquement en banque pour régler ses gros postes. Sans cette
     * fonction, la simulation devait choisir son compte payeur selon le solde
     * disponible — un contournement, faute de pouvoir déplacer l'argent.
     *
     * Le dépôt porte sur la moitié de l'excédent de caisse : une exploitation
     * garde du liquide pour ses achats courants, elle ne vide pas son tiroir.
     */
    private function deposerLesRecettesEnBanque(): void
    {
        $banque = $this->ctx->tresorerie('521101');
        $caisse = $this->ctx->tresorerie('531');

        if (! $banque || ! $caisse) {
            return;
        }

        $action = app(\App\Actions\RecordTreasuryTransferAction::class);

        for ($mois = $this->ctx->debut->addMonth(); $mois->lte($this->ctx->fin); $mois = $mois->addMonth()) {
            $date = $mois->startOfMonth()->addDays(4);

            if ($date->gt($this->ctx->fin)) {
                break;
            }

            $disponible = (float) $caisse->fresh()->balance;
            $montant = round(max(0, $disponible - 500_000) / 2, 2);

            if ($montant < 50_000) {
                continue;
            }

            try {
                $action->execute(
                    $caisse->fresh(), $banque->fresh(), $montant,
                    'Dépôt des recettes du mois', $date->format('Y-m-d')
                );
            } catch (\InvalidArgumentException $e) {
                // Solde insuffisant à cette date : on ne dépose pas, c'est tout.
                continue;
            }
        }
    }

    /**
     * Relevé bancaire à rapprocher.
     *
     * ⚠️ CONSTRUIT DEPUIS LES ÉCRITURES RÉELLES du compte 521101, avec
     * quelques lignes volontairement absentes et deux lignes bancaires sans
     * contrepartie comptable (frais de tenue de compte). Un relevé qui
     * correspondrait exactement au grand livre ne démontrerait rien : c'est
     * l'ÉCART que l'écran de rapprochement sert à trouver.
     */
    private function creerReleveBancaire(): void
    {
        $compte = $this->ctx->compte('521101');

        if (! $compte) {
            return;
        }

        $lignes = \App\Models\AccountingEntryLine::where('account_id', $compte->id)
            ->with('entry')
            ->get()
            ->filter(fn ($l) => $l->entry && $l->entry->entry_date)
            ->sortBy(fn ($l) => $l->entry->entry_date)
            ->values();

        foreach ($lignes as $i => $ligne) {
            // Une ligne sur six n'est pas encore parvenue sur le relevé :
            // c'est l'écart normal qu'un rapprochement doit mettre au jour.
            if ($i % 6 === 5) {
                continue;
            }

            $montant = (float) $ligne->debit > 0 ? (float) $ligne->debit : -(float) $ligne->credit;

            BankStatementLine::create([
                'account_id' => $compte->id,
                'statement_date' => $ligne->entry->entry_date->format('Y-m-d'),
                'label' => $ligne->entry->reference ?? 'Mouvement bancaire',
                'amount' => $montant,
                'is_reconciled' => false,
            ]);
        }

        // Frais bancaires : présents au relevé, absents du grand livre — la
        // situation inverse, tout aussi réelle, et que le comptable doit
        // régulariser par une écriture.
        foreach ([1, 3] as $moisAvant) {
            $date = $this->ctx->fin->subMonths($moisAvant)->endOfMonth();

            BankStatementLine::create([
                'account_id' => $compte->id,
                'statement_date' => $date->format('Y-m-d'),
                'label' => 'Frais de tenue de compte',
                'amount' => -$this->ctx->entre(2, 6) * 1_000,
                'is_reconciled' => false,
            ]);
        }
    }

    /**
     * Clôture périodique des mois révolus, sauf le dernier.
     *
     * ⚠️ Le mois le plus récent reste OUVERT à dessein : l'écran de clôture
     * périodique doit avoir quelque chose à clôturer, sinon la fonctionnalité
     * ne se démontre pas.
     */
    private function cloturerLesMoisRevolus(): void
    {
        $mois = [];

        for ($m = $this->ctx->debut->startOfMonth(); $m->lt($this->ctx->fin->startOfMonth()); $m = $m->addMonth()) {
            $mois[] = $m;
        }

        // Le dernier mois révolu reste ouvert.
        array_pop($mois);

        foreach ($mois as $m) {
            PeriodicClosure::create([
                'period' => $m->format('Y-m'),
                'closed_at' => $m->endOfMonth()->addDays(3),
                'closed_by' => \App\Models\User::where('email', 'compta@olouwachegoun.bj')->value('id'),
            ]);
        }
    }
}
