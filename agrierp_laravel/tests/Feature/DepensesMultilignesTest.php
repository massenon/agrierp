<?php

namespace Tests\Feature;

use App\Actions\SaisieDepenseAction;
use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\DepenseNonComptabilisableException;
use App\Exceptions\DepenseNonModifiableException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Models\AccountingEntry;
use App\Models\Expense;
use App\Models\ExpenseLine;
use App\Models\FiscalYear;
use App\Models\TreasuryAccount;
use App\Services\ConversionDepensesEnLignes;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

/**
 * Ticket DEP1 (PRD `docs/prd/depenses-multilignes.md`) — UNE DÉPENSE, PLUSIEURS LIGNES, par le point de passage unique
 * `SaisieDepenseAction`. Exemple calculé à la main (PRD § 5) : 15/06/2026, Caisse Principale (531), « Provende ponte »
 * 601 45 000 + « Vermifuge » 602 10 000 + « Sac d'aliment bis » 601 5 000 = 60 000.
 *   Écriture : D 601 = 50 000 ; D 602 = 10 000 ; C 531 = 60 000. Caisse : 500 000 → 440 000.
 *   Contre-passation (20/06/2026) : D 531 = 60 000 ; C 601 = 50 000 ; C 602 = 10 000. Caisse : retour à 500 000.
 */
class DepensesMultilignesTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();
    }

    private function action(): SaisieDepenseAction
    {
        return app(SaisieDepenseAction::class);
    }

    /** @return array<string, array{debit: float, credit: float}> les lignes d'une écriture, par code de compte */
    private function ecriture(AccountingEntry $e): array
    {
        $r = [];
        foreach ($e->lines()->with('account')->get() as $l) {
            $r[$l->account->code] = ['debit' => (float) $l->debit, 'credit' => (float) $l->credit];
        }

        return $r;
    }

    public function test_une_depense_a_trois_lignes_passe_une_ecriture_equilibree_regroupee_par_compte(): void
    {
        $depense = $this->action()->creer($this->document());

        $this->assertEquals(60_000.0, (float) $depense->amount, 'le total est la SOMME des lignes');
        $this->assertSame('Provende ponte (+2 autres)', $depense->label, 'le résumé de l\'en-tête');
        $this->assertSame('caisse', $depense->payment_mode);
        $this->assertSame($this->admin->id, $depense->created_by);
        $this->assertCount(3, $depense->lines);
        $this->assertSame(['Provende ponte', 'Vermifuge', 'Sac d\'aliment bis'], $depense->lines->pluck('label')->all());
        $this->assertSame([0, 1, 2], $depense->lines->pluck('position')->all());

        $entry = AccountingEntry::with('lines')->findOrFail($depense->accounting_entry_id);
        $this->assertSame('2026-06-15', $entry->entry_date->format('Y-m-d'));
        $this->assertEquals([
            '601' => ['debit' => 50_000.0, 'credit' => 0.0],
            '602' => ['debit' => 10_000.0, 'credit' => 0.0],
            '531' => ['debit' => 0.0, 'credit' => 60_000.0],
        ], $this->ecriture($entry));
        $this->assertCount(3, $entry->lines, 'un débit par COMPTE (601 regroupé), pas par ligne');
        $this->assertEquals($entry->lines->sum('debit'), $entry->lines->sum('credit'));
        $this->assertEquals(440_000.0, (float) $this->caisse->fresh()->balance);
        $this->assertSame(1, AccountingEntry::count());
    }

    public function test_le_centre_de_cout_de_l_en_tete_est_porte_par_chaque_ligne_d_ecriture(): void
    {
        $depense = $this->action()->creer($this->document(['cost_center_id' => $this->filiere->id, 'supplier_id' => $this->fournisseur->id, 'beneficiary' => '  M. Dossou  ']));

        $this->assertSame($this->filiere->id, $depense->cost_center_id);
        $this->assertSame($this->fournisseur->id, $depense->supplier_id);
        $this->assertSame('M. Dossou', $depense->beneficiary);
        $this->assertEquals([$this->filiere->id], AccountingEntry::findOrFail($depense->accounting_entry_id)->lines->pluck('cost_center_id')->unique()->values()->all());
    }

    public function test_la_piece_refusee_annule_tout_compte_de_tresorerie_sans_compte_du_plan(): void
    {
        $orphelin = TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse orpheline', 'account_code' => '999', 'balance' => 100_000, 'is_active' => true]);

        try {
            $this->action()->creer($this->document(['treasury_account_id' => $orphelin->id]));
            $this->fail('La dépense aurait dû être refusée.');
        } catch (DepenseNonComptabilisableException $e) {
            $this->assertStringContainsString('Caisse orpheline', $e->getMessage());
        }

        $this->assertSame(0, Expense::count());
        $this->assertSame(0, ExpenseLine::count(), 'ni dépense, ni lignes');
        $this->assertSame(0, AccountingEntry::count());
        $this->assertEquals(100_000.0, (float) $orphelin->fresh()->balance);
    }

    public function test_la_piece_refusee_annule_tout_aucun_exercice_ne_couvre_la_date(): void
    {
        try {
            $this->action()->creer($this->document(['expense_date' => '2019-03-10']));
            $this->fail('La dépense aurait dû être refusée.');
        } catch (NoOpenFiscalYearException) {
        }

        $this->assertSame(0, Expense::count());
        $this->assertSame(0, ExpenseLine::count());
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_un_exercice_clos_refuse_la_depense_avant_tout_effet(): void
    {
        FiscalYear::where('year', 2026)->update(['status' => 'cloture']);

        $this->expectException(ClosedFiscalYearException::class);
        try {
            $this->action()->creer($this->document());
        } finally {
            $this->assertSame(0, Expense::count());
            $this->assertSame(0, ExpenseLine::count());
            $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
        }
    }

    /** @return array<string, array{0: array<string, mixed>, 1: string}> */
    public static function refus(): array
    {
        return [
            'aucune ligne' => [['lines' => []], 'Ajoutez au moins une ligne'],
            'lignes absentes' => [['lines' => null, 'label' => null, 'category' => null], 'catégorie'],
            'libellé vide' => [['lines.0.label' => ''], 'libellé de la ligne'],
            'libellé trop long' => [['lines.0.label' => str_repeat('a', 256)], 'libellé de la ligne'],
            'compte inconnu' => [['lines.0.charge_account_id' => '11111111-1111-4111-8111-111111111111'], 'plan comptable (classe 6)'],
            'compte de classe 5' => [['lines.0.charge_account' => '531'], 'plan comptable (classe 6)'],
            'compte de classe 4' => [['lines.0.charge_account' => '411'], 'plan comptable (classe 6)'],
            'montant nul' => [['lines.0.amount' => 0], 'montant de la ligne'],
            'montant négatif' => [['lines.0.amount' => -5], 'montant de la ligne'],
            'montant décimal' => [['lines.0.amount' => 100.5], 'nombre entier'],
            'montant absent' => [['lines.0.amount' => null], 'montant de la ligne'],
            'trésorerie absente' => [['treasury_account_id' => null], 'compte de trésorerie'],
            'trésorerie inconnue' => [['treasury_account_id' => '11111111-1111-4111-8111-111111111111'], 'compte de trésorerie'],
            'date absente' => [['expense_date' => null], 'date de la dépense'],
            'mode incohérent' => [['payment_mode' => 'banque'], 'mode de paiement'],
            'total annoncé faux' => [['amount' => 59_000], 'somme de ses lignes'],
            'centre inconnu' => [['cost_center_id' => '11111111-1111-4111-8111-111111111111'], 'centre de coût'],
            'fournisseur inconnu' => [['supplier_id' => '11111111-1111-4111-8111-111111111111'], 'fournisseur'],
        ];
    }

    /**
     * @dataProvider refus
     *
     * @param  array<string, mixed>  $modifs  clé « lines.N.champ » : remplace ce champ de la ligne N
     */
    public function test_chaque_regle_de_validation_refuse_avant_d_ecrire(array $modifs, string $extrait): void
    {
        $doc = $this->document();
        foreach ($modifs as $cle => $valeur) {
            if (preg_match('/^lines\.(\d+)\.charge_account$/', $cle, $m)) {
                $doc['lines'][(int) $m[1]]['charge_account_id'] = match ($valeur) {
                    '531' => $this->plan['531']->id, '411' => $this->plan['411']->id,
                };
            } elseif (preg_match('/^lines\.(\d+)\.(\w+)$/', $cle, $m)) {
                $doc['lines'][(int) $m[1]][$m[2]] = $valeur;
            } else {
                $doc[$cle] = $valeur;
            }
        }

        try {
            $this->action()->creer($doc);
            $this->fail('La dépense aurait dû être refusée.');
        } catch (ValidationException $e) {
            $this->assertStringContainsString($extrait, collect($e->errors())->flatten()->implode(' | '));
        }

        $this->assertSame(0, Expense::count());
        $this->assertSame(0, ExpenseLine::count());
        $this->assertSame(0, AccountingEntry::count());
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_un_total_annonce_juste_est_accepte_et_le_total_est_toujours_la_somme(): void
    {
        $depense = $this->action()->creer($this->document(['amount' => 60_000]));

        $this->assertEquals(60_000.0, (float) $depense->amount);
    }

    public function test_l_archivage_contre_passe_l_ecriture_d_origine_et_reintegre_la_tresorerie(): void
    {
        $depense = $this->action()->creer($this->document());

        $this->assertSame(SaisieDepenseAction::ARCHIVEE, $this->action()->archiver($depense->id));

        $this->assertFalse($depense->fresh()->is_active);
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance);
        $annulation = AccountingEntry::with('lines')->where('source_type', 'expense_reversal')->firstOrFail();
        $this->assertSame('2026-06-20', $annulation->entry_date->format('Y-m-d'), 'datée du jour de l\'annulation');
        $this->assertEquals([
            '531' => ['debit' => 60_000.0, 'credit' => 0.0],
            '601' => ['debit' => 0.0, 'credit' => 50_000.0],
            '602' => ['debit' => 0.0, 'credit' => 10_000.0],
        ], $this->ecriture($annulation));
        $this->assertSame(2, AccountingEntry::count(), 'l\'originale est conservée, jamais supprimée');

        $this->assertSame(SaisieDepenseAction::DEJA_ARCHIVEE, $this->action()->archiver($depense->id));
        $this->assertSame(2, AccountingEntry::count());
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance, 'jamais réintégrée deux fois');
    }

    public function test_une_depense_comptabilisee_est_immuable_meme_pour_un_libelle(): void
    {
        $depense = $this->action()->creer($this->document());
        $doc = $this->document();
        $doc['lines'][0]['label'] = 'Provende renommée';

        try {
            $this->action()->modifier($depense->id, $doc);
            $this->fail('La modification aurait dû être refusée.');
        } catch (DepenseNonModifiableException $e) {
            $this->assertSame(SaisieDepenseAction::MESSAGE_DEJA_COMPTABILISEE, $e->getMessage());
        }

        $this->assertSame('Provende ponte', $depense->fresh()->lines->first()->label);
        $this->assertEquals(440_000.0, (float) $this->caisse->fresh()->balance);
    }

    public function test_une_depense_sans_piece_reste_modifiable_lignes_et_tresorerie_recalculees(): void
    {
        $depense = $this->depenseSansPiece();
        $this->assertEquals(475_000.0, (float) $this->caisse->fresh()->balance);

        $modifiee = $this->action()->modifier($depense->id, $this->document([
            'treasury_account_id' => $this->banque->id, 'payment_mode' => 'banque',
            'lines' => [['label' => 'Gasoil', 'charge_account_id' => $this->plan['605']->id, 'amount' => 30_000]],
        ]));

        $this->assertSame('Gasoil', $modifiee->label);
        $this->assertEquals(30_000.0, (float) $modifiee->amount);
        $this->assertCount(1, $modifiee->lines);
        $this->assertSame(1, ExpenseLine::count(), 'l\'ancienne ligne est remplacée');
        $this->assertEquals(500_000.0, (float) $this->caisse->fresh()->balance, 'ancien total réintégré');
        $this->assertEquals(770_000.0, (float) $this->banque->fresh()->balance, 'nouveau total décaissé');
        $this->assertNull($modifiee->accounting_entry_id, 'jamais de pièce rétroactive');
        $this->assertSame(0, AccountingEntry::count());
    }

    public function test_une_depense_archivee_ne_se_modifie_plus(): void
    {
        $depense = $this->depenseSansPiece();
        $depense->update(['is_active' => false]);

        $this->expectExceptionMessage(SaisieDepenseAction::MESSAGE_ARCHIVEE);
        $this->action()->modifier($depense->id, $this->document());
    }

    public function test_l_exercice_clos_refuse_modification_et_archivage_comme_avant(): void
    {
        $depense = $this->depenseSansPiece();
        FiscalYear::where('year', 2026)->update(['status' => 'cloture']);

        try {
            $this->action()->modifier($depense->id, $this->document());
            $this->fail('Modification attendue refusée.');
        } catch (ClosedFiscalYearException) {
        }
        $this->expectException(ClosedFiscalYearException::class);
        $this->action()->archiver($depense->id);
    }

    public function test_le_document_plat_d_un_ancien_poste_devient_une_ligne(): void
    {
        $id = '99999999-9999-4999-8999-999999999999';

        $depense = $this->action()->creer([
            'expense_date' => '2026-06-15', 'label' => 'Gasoil livraison', 'category' => '605 - Énergie',
            'amount' => 25_000, 'treasury_account_id' => $this->caisse->id,
        ], $id);

        $this->assertCount(1, $depense->lines);
        $ligne = $depense->lines->first();
        $this->assertSame(ExpenseLine::idDeConversion($id), $ligne->id);
        $this->assertSame($this->plan['605']->id, $ligne->charge_account_id);
        $this->assertSame('Gasoil livraison', $ligne->label);
        $this->assertEquals(25_000.0, (float) $depense->amount);
        $this->assertSame('605 - Énergie', $depense->category, 'catégorie de compatibilité pour les postes non migrés');
        $this->assertEquals(475_000.0, (float) $this->caisse->fresh()->balance);
        $this->assertEquals(['605' => ['debit' => 25_000.0, 'credit' => 0.0], '531' => ['debit' => 0.0, 'credit' => 25_000.0]],
            $this->ecriture(AccountingEntry::findOrFail($depense->accounting_entry_id)));
    }

    public function test_un_document_plat_a_categorie_inconnue_est_refuse(): void
    {
        $this->expectException(ValidationException::class);
        $this->action()->creer([
            'expense_date' => '2026-06-15', 'label' => 'X', 'category' => '699 - Inexistant',
            'amount' => 1_000, 'treasury_account_id' => $this->caisse->id,
        ]);
    }

    public function test_le_resume_de_l_en_tete(): void
    {
        $this->assertSame('Gasoil', Expense::resume(['Gasoil']));
        $this->assertSame('Gasoil (+1 autre)', Expense::resume(['Gasoil', 'Huile']));
        $this->assertSame('Gasoil (+2 autres)', Expense::resume(['Gasoil', 'Huile', 'Filtre']));
    }

    /** Une dépense de l'ancien régime : 25 000 F sur la caisse, une ligne, AUCUNE pièce. */
    private function depenseSansPiece(): Expense
    {
        $depense = new Expense();
        $depense->fill([
            'expense_date' => '2026-06-10', 'label' => 'Ancienne', 'category' => '605 - Énergie', 'amount' => 25_000,
            'treasury_account_id' => $this->caisse->id, 'payment_mode' => 'caisse', 'status' => 'payee', 'is_active' => true,
        ]);
        $depense->save();
        $ligne = new ExpenseLine();
        $ligne->id = ExpenseLine::idDeConversion($depense->id);
        $ligne->fill(['expense_id' => $depense->id, 'position' => 0, 'label' => 'Ancienne', 'charge_account_id' => $this->plan['605']->id, 'amount' => 25_000]);
        $ligne->save();
        $this->caisse->decrement('balance', 25_000);

        return $depense;
    }

    // ── Migration : chaque ancienne dépense devient 1 en-tête + 1 ligne, les pièces restent intactes ─────────────────

    public function test_la_conversion_transforme_chaque_ancienne_depense_en_une_ligne_sans_toucher_aux_pieces(): void
    {
        $comptabilisee = $this->action()->creer($this->document(['lines' => [
            ['label' => 'Transport marché', 'charge_account_id' => $this->plan['614']->id, 'amount' => 8_000],
        ]]));
        // On la remet à l'état d'AVANT la migration : plus de ligne, catégorie texte, pièce déjà passée.
        $comptabilisee->lines()->delete();
        $comptabilisee->update(['category' => '614 - Transports', 'payment_mode' => null]);
        $pieceAvant = AccountingEntry::with('lines')->findOrFail($comptabilisee->accounting_entry_id)->toArray();

        $divers = $this->ancienne('Réparation toiture', 'Entretien divers', 12_500.50);
        $illisible = $this->ancienne('Sans catégorie lisible', null, 3_000);
        $archivee = $this->ancienne('Ancienne archivée', '605 - Énergie', 4_000, false);

        $bilan = ConversionDepensesEnLignes::convertir();

        $this->assertSame(['converties' => 4, 'divers' => 2, 'ignorees' => 0], $bilan);
        $this->assertSame(4, Expense::count(), 'aucune dépense perdue');
        $this->assertSame(4, ExpenseLine::count(), '1 en-tête = 1 ligne');

        $l = $comptabilisee->fresh()->lines->sole();
        $this->assertSame($this->plan['614']->id, $l->charge_account_id);
        $this->assertSame('Transport marché', $l->label);
        $this->assertEquals(8_000.0, (float) $l->amount);
        $this->assertSame(ExpenseLine::idDeConversion($comptabilisee->id), $l->id);
        $this->assertSame('caisse', $comptabilisee->fresh()->payment_mode, 'mode déduit du compte de trésorerie');

        $this->assertSame($this->plan['628']->id, $divers->fresh()->lines->sole()->charge_account_id, 'sans correspondance : charges diverses');
        $this->assertEquals(12_500.50, (float) $divers->fresh()->lines->sole()->amount, 'le total historique reste cohérent');
        $this->assertSame($this->plan['628']->id, $illisible->fresh()->lines->sole()->charge_account_id);
        $this->assertSame($this->plan['605']->id, $archivee->fresh()->lines->sole()->charge_account_id);
        $this->assertFalse($archivee->fresh()->is_active);

        $this->assertSame(1, AccountingEntry::count(), 'aucune pièce régénérée');
        $this->assertEquals($pieceAvant, AccountingEntry::with('lines')->findOrFail($comptabilisee->accounting_entry_id)->toArray(), 'pièce intacte');
        $this->assertNotNull($comptabilisee->fresh()->accounting_entry_id);

        // Idempotente : une seconde exécution ne reconvertit rien.
        $this->assertSame(['converties' => 0, 'divers' => 0, 'ignorees' => 0], ConversionDepensesEnLignes::convertir());
        $this->assertSame(4, ExpenseLine::count());
    }

    public function test_la_migration_elle_meme_convertit_les_depenses_existantes(): void
    {
        $this->ancienne('Avant migration', '601 - Aliments', 9_000);

        $migration = require database_path('migrations/2026_10_22_000002_convertir_les_depenses_en_lignes.php');
        $migration->up();

        $this->assertSame(1, ExpenseLine::count());
        $this->assertSame($this->plan['601']->id, ExpenseLine::firstOrFail()->charge_account_id);
    }

    private function ancienne(string $libelle, ?string $categorie, float $montant, bool $active = true): Expense
    {
        $d = new Expense();
        $d->fill([
            'expense_date' => '2026-05-02', 'label' => $libelle, 'category' => $categorie, 'amount' => $montant,
            'treasury_account_id' => $this->caisse->id, 'status' => 'payee', 'is_active' => $active,
        ]);
        $d->save();

        return $d;
    }
}
