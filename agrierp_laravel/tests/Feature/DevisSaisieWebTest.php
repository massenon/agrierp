<?php

namespace Tests\Feature;

use App\Livewire\Ventes\Devis;
use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\Quote;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket DEV (web d'abord, article 5) — « Devis & Proforma » : créer, modifier, changer le statut, archiver un devis
 * par UN point de passage (`SaisieDevisAction`) que partagent l'écran web et l'envoi du poste.
 *
 * Valeurs attendues écrites à la main. Décor : `PreparationExercices` (exercices 2025 clos et 2026 ouvert), « 21/10/2026 ».
 */
class DevisSaisieWebTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private Customer $client;

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2026-10-21 09:00:00');
        $this->exercice(2025, 'cloture');
        $this->exercice(2026);

        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'phone' => '97123456', 'is_active' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function devis(array $remplace = []): Quote
    {
        return Quote::create(array_merge([
            'quote_number' => 'DEV-2026-'.str_pad((string) (Quote::count() + 1), 3, '0', STR_PAD_LEFT),
            'customer_id' => $this->client->id,
            'articles_description' => '2 cages galvanisées 6 compartiments',
            'amount' => 150000, 'tva_rate' => 18, 'validity_days' => 15,
            'quote_date' => '2026-10-20', 'status' => 'brouillon', 'is_active' => true,
        ], $remplace));
    }

    private function remplir($composant, array $remplace = [])
    {
        $valeurs = array_merge([
            'customerId' => $this->client->id,
            'articlesDescription' => '2 cages galvanisées 6 compartiments sur mesure',
            'amount' => 150000, 'tvaRate' => 18, 'validityDays' => 15,
            'quoteDate' => '2026-10-21', 'note' => '',
        ], $remplace);
        foreach ($valeurs as $champ => $valeur) {
            $composant->set($champ, $valeur);
        }

        return $composant;
    }

    public function test_creer_un_devis_attribue_dev_aaaa_nnn_en_brouillon_et_trace_l_audit(): void
    {
        $composant = Livewire::test(Devis::class)->call('newQuote');
        $this->remplir($composant)->call('saveQuote')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Devis créé avec succès.', type: 'success');
        $this->remplir($composant, ['articlesDescription' => '1 enclos'])->call('newQuote');
        $this->remplir($composant, ['articlesDescription' => '1 enclos'])->call('saveQuote');

        $numeros = Quote::orderBy('quote_number')->pluck('quote_number')->all();
        $this->assertSame(['DEV-2026-001', 'DEV-2026-002'], $numeros);
        $devis = Quote::where('quote_number', 'DEV-2026-001')->firstOrFail();
        $this->assertSame(['brouillon', true, 150000.0, 18.0, 15], [
            $devis->status, (bool) $devis->is_active, (float) $devis->amount, (float) $devis->tva_rate, (int) $devis->validity_days,
        ]);
        $this->assertSame('2026-11-05', $devis->valid_until->format('Y-m-d'));
        $this->assertSame(2, AuditLog::where('action', 'quote.created')->count());
    }

    public function test_les_champs_obligatoires_ont_les_messages_francais_du_web(): void
    {
        $composant = Livewire::test(Devis::class)->call('newQuote')
            ->set('amount', null)
            ->call('saveQuote');

        $this->assertErreurSousLeChamp($composant, 'customerId', 'Le champ client est obligatoire.');
        $this->assertErreurSousLeChamp($composant, 'articlesDescription', 'Le champ description des articles est obligatoire.');
        $this->assertErreurSousLeChamp($composant, 'amount', 'Le champ montant est obligatoire.');
        $this->assertSame(0, Quote::count());
    }

    public function test_un_devis_date_dans_un_exercice_clos_est_refuse_sous_la_date_et_rien_n_est_ecrit(): void
    {
        $composant = Livewire::test(Devis::class)->call('newQuote');
        $this->remplir($composant, ['quoteDate' => '2025-12-20'])->call('saveQuote');

        $this->assertErreurSousLeChamp($composant, 'quoteDate', "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.");
        $this->assertSame(0, Quote::count());
        $this->assertSame(0, AuditLog::where('action', 'quote.created')->count());
        $this->assertStringContainsString('aucune saisie ne peut être datée du 20/12/2025', $composant->html());
    }

    public function test_modifier_un_devis_garde_son_numero_et_son_statut(): void
    {
        $devis = $this->devis(['status' => 'envoye']);

        $composant = Livewire::test(Devis::class)->call('editQuote', $devis->id);
        $this->remplir($composant, ['amount' => 200000, 'tvaRate' => 0, 'validityDays' => 30, 'note' => 'Remise accordée', 'quoteDate' => '2026-10-20'])
            ->call('saveQuote')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Devis modifié avec succès.', type: 'success');

        $devis = $devis->fresh();
        $this->assertSame(['DEV-2026-001', 'envoye', 200000.0, 0.0, 30, 'Remise accordée'], [
            $devis->quote_number, $devis->status, (float) $devis->amount, (float) $devis->tva_rate, (int) $devis->validity_days, $devis->note,
        ]);
        $this->assertSame(1, AuditLog::where('action', 'quote.updated')->count());
    }

    public function test_enregistrer_sans_rien_changer_n_ecrit_rien_et_ne_laisse_aucune_trace(): void
    {
        $devis = $this->devis(['note' => 'Remise accordée']);
        $avant = $devis->updated_at;
        Carbon::setTestNow('2026-10-21 11:00:00');

        Livewire::test(Devis::class)->call('editQuote', $devis->id)->call('saveQuote')
            ->assertHasNoErrors()
            ->assertDispatched('toast', message: 'Devis modifié avec succès.', type: 'success');

        $this->assertSame(0, AuditLog::where('action', 'quote.updated')->count());
        $this->assertTrue($avant->equalTo($devis->fresh()->updated_at), 'aucune écriture');
    }

    public function test_le_cycle_brouillon_envoye_accepte_et_les_messages_du_web(): void
    {
        $devis = $this->devis();

        $composant = Livewire::test(Devis::class)
            ->call('markAsSent', $devis->id)
            ->assertDispatched('toast', message: 'Devis marqué comme envoyé.', type: 'success');
        $this->assertSame('envoye', $devis->fresh()->status);

        $composant->call('markAsAccepted', $devis->id)
            ->assertDispatched('toast', message: 'Devis marqué comme accepté.', type: 'success');
        $this->assertSame('accepte', $devis->fresh()->status);

        $this->assertSame([1, 1], [AuditLog::where('action', 'quote.sent')->count(), AuditLog::where('action', 'quote.accepted')->count()]);
    }

    public function test_un_devis_envoye_peut_etre_refuse_avec_un_avertissement(): void
    {
        $devis = $this->devis(['status' => 'envoye']);

        Livewire::test(Devis::class)->call('markAsRefused', $devis->id)
            ->assertDispatched('toast', message: 'Devis marqué comme refusé.', type: 'warning');

        $this->assertSame('refuse', $devis->fresh()->status);
        $this->assertSame(1, AuditLog::where('action', 'quote.refused')->count());
    }

    public function test_un_changement_de_statut_interdit_est_refuse_avec_son_motif_et_rien_n_est_ecrit(): void
    {
        $brouillon = $this->devis();
        $accepte = $this->devis(['status' => 'accepte']);

        Livewire::test(Devis::class)
            ->call('markAsAccepted', $brouillon->id)
            ->assertDispatched('toast', message: 'Changement de statut interdit : un devis « Brouillon » ne peut pas passer à « Accepté ».', type: 'error')
            ->call('markAsRefused', $accepte->id)
            ->assertDispatched('toast', message: 'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Refusé ».', type: 'error')
            ->call('markAsSent', $accepte->id)
            ->assertDispatched('toast', message: 'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Envoyé ».', type: 'error');

        $this->assertSame(['brouillon', 'accepte'], [$brouillon->fresh()->status, $accepte->fresh()->status]);
        $this->assertSame(0, AuditLog::whereIn('action', ['quote.sent', 'quote.accepted', 'quote.refused'])->count());
    }

    public function test_le_meme_statut_redemande_ne_fait_rien(): void
    {
        $devis = $this->devis(['status' => 'envoye']);

        Livewire::test(Devis::class)->call('markAsSent', $devis->id);

        $this->assertSame('envoye', $devis->fresh()->status);
        $this->assertSame(0, AuditLog::where('action', 'quote.sent')->count(), 'aucune seconde trace');
    }

    public function test_un_devis_d_un_exercice_clos_est_en_lecture_seule(): void
    {
        $devis = $this->devis(['quote_date' => '2025-12-20']);
        $motif = "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.";

        Livewire::test(Devis::class)
            ->call('markAsSent', $devis->id)->assertDispatched('toast', message: $motif, type: 'error')
            ->call('archiveQuote', $devis->id)->assertDispatched('toast', message: $motif, type: 'error');

        $this->assertSame(['brouillon', true], [$devis->fresh()->status, (bool) $devis->fresh()->is_active]);
    }

    public function test_archiver_est_logique_avec_confirmation_et_un_second_archivage_ne_fait_rien(): void
    {
        $devis = $this->devis();

        $composant = Livewire::test(Devis::class);
        $this->assertStringContainsString('archive-devis-'.$devis->id, $composant->html(), 'confirmation x-modal-confirm-delete');

        $composant->call('archiveQuote', $devis->id)
            ->assertDispatched('toast', message: 'Devis archivé avec succès.', type: 'warning');
        $composant->call('archiveQuote', $devis->id);

        $this->assertFalse((bool) $devis->fresh()->is_active);
        $this->assertSame(1, Quote::count(), 'la ligne est gardée, jamais supprimée');
        $this->assertSame(1, AuditLog::where('action', 'quote.archived')->count());
    }

    public function test_un_devis_archive_ou_facture_ne_se_modifie_plus(): void
    {
        $archive = $this->devis(['is_active' => false]);
        $facture = $this->devis(['status' => 'facture']);

        $composant = Livewire::test(Devis::class);
        foreach ([
            [$archive, 'Ce devis est archivé : il ne peut plus être modifié.'],
            [$facture, 'Ce devis est facturé : il ne peut plus être modifié.'],
        ] as [$devis, $message]) {
            $composant->call('editQuote', $devis->id)
                ->set('amount', 1)
                ->call('saveQuote')
                ->assertDispatched('toast', message: $message, type: 'error');
        }

        $this->assertSame([150000.0, 150000.0], [(float) $archive->fresh()->amount, (float) $facture->fresh()->amount]);
    }

    public function test_les_quatre_kpi_sont_calcules_comme_le_web(): void
    {
        $this->devis(['status' => 'brouillon', 'amount' => 1000]);
        $this->devis(['status' => 'envoye', 'amount' => 2000]);
        $this->devis(['status' => 'accepte', 'amount' => 3000]);
        $this->devis(['status' => 'refuse', 'amount' => 500]);
        $this->devis(['status' => 'accepte', 'amount' => 9999, 'is_active' => false]);
        $this->devis(['status' => 'accepte', 'amount' => 7777, 'quote_date' => '2026-09-30']);

        $kpis = Livewire::test(Devis::class)->instance()->kpis;

        // Actifs : brouillon + envoyé + accepté (3000) + accepté de septembre (7777) = 4 ; valeur 1000+2000+3000+7777.
        $this->assertSame(4, $kpis['devis_actifs']);
        $this->assertSame(13777.0, $kpis['valeur_totale']);
        // Octobre : 1 accepté actif / (1 accepté + 1 refusé) = 50 %.
        $this->assertSame(50.0, (float) $kpis['taux_conversion']);
        $this->assertSame(1, $kpis['en_attente_relance']);
    }

    public function test_les_filtres_recherche_statut_et_client(): void
    {
        $autre = Customer::create(['name' => 'KPADONOU Eric', 'phone' => '96000000', 'is_active' => true]);
        $a = $this->devis(['status' => 'envoye']);
        $b = $this->devis(['customer_id' => $autre->id]);
        $this->devis(['is_active' => false]);

        $quotes = fn ($c) => $c->instance()->quotes->pluck('id')->sort()->values()->all();

        $this->assertSame(collect([$a->id, $b->id])->sort()->values()->all(), $quotes(Livewire::test(Devis::class)));
        $this->assertSame([$a->id], $quotes(Livewire::test(Devis::class)->set('statusFilter', 'envoye')));
        $this->assertSame([$b->id], $quotes(Livewire::test(Devis::class)->set('clientFilter', $autre->id)));
        $this->assertSame([$b->id], $quotes(Livewire::test(Devis::class)->set('search', 'kpado')));
        $this->assertSame([$a->id], $quotes(Livewire::test(Devis::class)->set('search', 'DEV-2026-001')));
    }
}
