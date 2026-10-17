<?php

namespace Tests\Feature;

use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Services\AccountingEntryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Ticket 15.20a — NUMÉROS D'ÉCRITURE : séquentiels, sans doublon, sans trou.
 *
 * Défaut (relevé à l'audit de 15.19) : `generateReference()` lisait `substr($last->reference, -4)`.
 * Les références de règlement finissent par un libellé (« … — AMOUSSOU »), `(int)` valait 0 et le
 * numéro suivant était TOUJOURS `OD-AAAA-0001`. Aucune erreur, aucun test rouge : seulement un
 * journal où dix pièces portent le même numéro.
 */
class NumerotationEcrituresTest extends TestCase
{
    use RefreshDatabase;

    private ChartOfAccount $caisse;
    private ChartOfAccount $ventes;
    private FiscalYear $exercice;

    protected function setUp(): void
    {
        parent::setUp();

        $this->exercice = FiscalYear::create([
            'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert',
        ]);
        $this->caisse = ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);
        $this->ventes = ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);
    }

    /** Passe une écriture comme le font les Actions : référence générée + libellé, via le point de passage unique. */
    private function passer(string $libelle, string $date = '2026-07-01'): AccountingEntry
    {
        return app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $this->caisse->id, 'debit' => 1000, 'credit' => 0],
                ['account_id' => $this->ventes->id, 'debit' => 0, 'credit' => 1000],
            ],
            entryDate: $date,
            reference: AccountingEntry::generateReference().' — '.$libelle,
        );
    }

    private function numero(AccountingEntry $e): string
    {
        return explode(' — ', $e->reference, 2)[0];
    }

    public function test_deux_reglements_successifs_ne_portent_pas_le_meme_numero(): void
    {
        $a = $this->passer('AMOUSSOU');
        $b = $this->passer('AMOUSSOU');
        $c = $this->passer('KPADONOU');

        $this->assertSame('OD-2026-0001', $this->numero($a));
        $this->assertSame('OD-2026-0002', $this->numero($b));
        $this->assertSame('OD-2026-0003', $this->numero($c));
        $this->assertSame('OD-2026-0002 — AMOUSSOU', $b->reference, 'Le format « numéro — libellé » (exports) est inchangé.');
    }

    public function test_la_sequence_est_continue_sur_cinquante_ecritures_a_libelles_varies(): void
    {
        foreach (range(1, 50) as $i) {
            $this->passer($i % 2 ? 'Vente 3F9A'.$i : 'Règlement fournisseur n° '.$i);
        }

        $numeros = AccountingEntry::all()->map(fn ($e) => $this->numero($e))->sort()->values()->all();

        $attendus = array_map(fn ($n) => 'OD-2026-'.str_pad((string) $n, 4, '0', STR_PAD_LEFT), range(1, 50));
        $this->assertSame($attendus, $numeros, 'Ni doublon ni trou.');
    }

    public function test_une_ecriture_annulee_ne_consomme_pas_de_numero(): void
    {
        $this->passer('A');

        try {
            DB::transaction(function () {
                $this->passer('B (annulée)');
                throw new \RuntimeException('incident après l\'écriture');
            });
        } catch (\RuntimeException) {
        }

        $this->assertSame('OD-2026-0002', $this->numero($this->passer('C')), 'Le numéro de l\'écriture annulée est rendu : pas de trou.');
    }

    public function test_chaque_exercice_a_sa_propre_sequence(): void
    {
        FiscalYear::create(['year' => 2027, 'start_date' => '2027-01-01', 'end_date' => '2027-12-31', 'status' => 'ouvert']);

        $this->passer('A');
        $this->passer('B');
        $e2027 = $this->passer('C', '2027-02-01');
        $suite = $this->passer('D');

        $this->assertSame('OD-2027-0001', $this->numero($e2027), 'Numérotée selon l\'exercice de la date, pas selon l\'année du jour.');
        $this->assertSame('OD-2026-0003', $this->numero($suite));
    }

    public function test_le_compteur_reprend_apres_les_numeros_deja_presents_sans_les_toucher(): void
    {
        // Écritures d'avant le correctif : un numéro bien formé, et DES DOUBLONS « 0001 ».
        foreach (['OD-2026-0041 — ancienne', 'OD-2026-0001 — doublon X', 'OD-2026-0001 — doublon Y'] as $ref) {
            AccountingEntry::create([
                'fiscal_year_id' => $this->exercice->id, 'entry_date' => '2026-03-01', 'reference' => $ref,
                'is_locked' => false, 'is_active' => true,
            ]);
        }

        $this->assertSame('OD-2026-0042', $this->numero($this->passer('nouvelle')));

        // Rien n'a été renumérotée en silence.
        $this->assertSame(2, AccountingEntry::where('reference', 'like', 'OD-2026-0001 — doublon%')->count());
    }

    public function test_le_gabarit_est_remplace_et_la_reference_reste_dans_les_100_caracteres(): void
    {
        $e = app(AccountingEntryService::class)->record(
            lines: [
                ['account_id' => $this->caisse->id, 'debit' => 5, 'credit' => 0],
                ['account_id' => $this->ventes->id, 'debit' => 0, 'credit' => 5],
            ],
            entryDate: '2026-07-01',
            reference: mb_substr(AccountingEntry::generateReference().' — '.str_repeat('X', 200), 0, 100),
        );

        $this->assertSame(100, mb_strlen($e->reference));
        $this->assertStringStartsWith('OD-2026-0001 — ', $e->reference);
        $this->assertStringNotContainsString('????', $e->reference);
    }

    public function test_une_reference_saisie_a_la_main_n_est_pas_modifiee(): void
    {
        $e = app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->ventes->id, 10, '2026-07-01', 'OD-2026-0511 — Achat aliment');

        $this->assertSame('OD-2026-0511 — Achat aliment', $e->reference);
    }

    public function test_la_commande_de_detection_liste_les_doublons_sans_rien_modifier(): void
    {
        foreach (['OD-2026-0001 — A', 'OD-2026-0001 — B', 'OD-2026-0001 — C', 'OD-2026-0002 — D', 'OD-2026-0003 — E', 'OD-2026-0003 — F'] as $ref) {
            AccountingEntry::create([
                'fiscal_year_id' => $this->exercice->id, 'entry_date' => '2026-03-01', 'reference' => $ref,
                'is_locked' => false, 'is_active' => true,
            ]);
        }
        $avant = AccountingEntry::orderBy('reference')->pluck('reference', 'id')->all();

        $this->artisan('comptabilite:doublons-references')
            ->expectsOutputToContain('OD-2026-0001')
            ->expectsOutputToContain('OD-2026-0003')
            ->expectsOutputToContain('2 numéro(s) en doublon')
            ->expectsOutputToContain('3 écriture(s) en trop')
            ->assertExitCode(1);

        $this->assertSame($avant, AccountingEntry::orderBy('reference')->pluck('reference', 'id')->all(), 'Lecture seule.');
    }

    public function test_la_commande_de_detection_est_muette_quand_tout_est_unique(): void
    {
        $this->passer('A');
        $this->passer('A');

        $this->artisan('comptabilite:doublons-references')
            ->expectsOutputToContain('Aucun numéro d\'écriture en doublon')
            ->assertExitCode(0);
    }

    /**
     * Ticket 15.20b — COLLISION : le compteur n'était amorcé qu'une fois par exercice. Une écriture
     * manuelle `OD-2026-0002 — manuelle` passée ENSUITE n'était pas vue : la suivante rendait à nouveau 0002.
     */
    public function test_une_ecriture_manuelle_passee_apres_amorcage_n_est_pas_dupliquee(): void
    {
        $this->assertSame('OD-2026-0001', $this->numero($this->passer('A')));

        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->ventes->id, 10, '2026-07-01', 'OD-2026-0002 — manuelle');

        $this->assertSame('OD-2026-0003', $this->numero($this->passer('B')), 'Ne doit pas retomber sur 0002.');
    }

    public function test_un_numero_manuel_tres_superieur_au_compteur_est_depasse_et_la_suite_reprend_sans_trou(): void
    {
        $this->passer('A');
        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->ventes->id, 10, '2026-07-01', 'OD-2026-0511 — manuelle');
        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->ventes->id, 10, '2026-07-01', 'OD-2027-0900 — autre exercice');
        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->ventes->id, 10, '2026-07-01', 'XX-2026-0999 — autre journal');

        $this->assertSame('OD-2026-0512', $this->numero($this->passer('B')));
        $this->assertSame('OD-2026-0513', $this->numero($this->passer('C')));
    }

    public function test_un_numero_manuel_a_cinq_chiffres_est_vu(): void
    {
        $this->passer('A');
        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->ventes->id, 10, '2026-07-01', 'OD-2026-10005 — manuelle');

        $this->assertSame('OD-2026-10006', $this->numero($this->passer('B')));
    }

    public function test_une_ecriture_annulee_apres_un_numero_manuel_ne_cree_pas_de_trou(): void
    {
        $this->passer('A');
        app(AccountingEntryService::class)->recordManual($this->caisse->id, $this->ventes->id, 10, '2026-07-01', 'OD-2026-0005 — manuelle');

        try {
            DB::transaction(function () {
                $this->passer('Annulée');
                throw new \RuntimeException('rollback');
            });
        } catch (\RuntimeException) {
        }

        $this->assertSame('OD-2026-0006', $this->numero($this->passer('B')));
    }

    /** Garde-fou source : plus aucune lecture de la fin de la référence. */
    public function test_le_modele_ne_relit_plus_la_fin_de_la_reference(): void
    {
        $src = file_get_contents(app_path('Models/AccountingEntry.php'));

        $this->assertStringNotContainsString('substr($last->reference', $src);
    }
}
