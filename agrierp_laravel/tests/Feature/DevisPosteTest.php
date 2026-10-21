<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Customer;
use App\Models\Quote;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket DEV — ENVOI ET TIRAGE DES DEVIS DU POSTE (`quotes`).
 *
 * Mêmes règles et mêmes droits que le web (`SaisieDevisAction`) : le poste envoie le FAIT (le devis tel qu'il est), le
 * serveur attribue le numéro `DEV-AAAA-NNN`, refuse un exercice clos et un changement de statut interdit, et un renvoi
 * du même `id` est un acquittement, jamais un doublon. Valeurs attendues écrites à la main.
 *
 * Décor : `PreparationExercices` (exercice 2025 clos, 2026 ouvert), « 21/10/2026 ».
 */
class DevisPosteTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const DEVIS = 'dddd1111-0000-4000-8000-000000000001';

    private const DEVIS_2 = 'dddd1111-0000-4000-8000-000000000002';

    private Customer $client;

    /** Le compte du poste quand le test n'est pas celui de l'administrateur du décor (tirage : `actingAs`, sans jeton). */
    private ?User $compte = null;

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

    /** Un devis tel que le poste l'envoie (colonnes de la table, UUID créé au poste, sans numéro). */
    private function devis(array $remplace = []): array
    {
        return array_merge([
            'id' => self::DEVIS, 'customer_id' => $this->client->id,
            'articles_description' => '2 cages galvanisées 6 compartiments sur mesure',
            'amount' => 150000, 'tva_rate' => 18, 'validity_days' => 15, 'quote_date' => '2026-10-20',
            'note' => null, 'status' => 'brouillon', 'is_active' => true, 'device_id' => 'poste-bureau',
        ], $remplace);
    }

    /** Un devis déjà au serveur (l'`id` n'est pas remplissable : posé explicitement). */
    private function enBase(array $colonnes): Quote
    {
        $devis = new Quote();
        $devis->id = $colonnes['id'];
        unset($colonnes['id']);
        $devis->fill($colonnes);
        $devis->save();

        return $devis;
    }

    private function pousser(array ...$devis)
    {
        return $this->envoyer(['quotes' => $devis]);
    }

    private function jetonDe(string $role): void
    {
        $utilisateur = User::create([
            'name' => $role, 'username' => $role.'-dev', 'email' => $role.'-dev@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $utilisateur->assignRole($role);
        $this->compte = $utilisateur;
        $this->app['auth']->forgetGuards();
        $this->jeton = $this->postJson('/api/auth/login', [
            'identifiant' => $role.'-dev', 'password' => 'AgriERP@2026', 'device_name' => 'poste-'.$role,
        ])->assertOk()->json('token');
    }

    // ── Envoi : accepté ────────────────────────────────────────────────────────────────────────────────────────────

    public function test_un_devis_cree_au_poste_est_accepte_avec_son_uuid_et_le_serveur_attribue_le_numero(): void
    {
        $reponse = $this->pousser($this->devis())->assertOk();

        $reponse->assertJsonPath('quotes.accepted', [self::DEVIS])->assertJsonPath('quotes.rejected', []);
        $devis = Quote::findOrFail(self::DEVIS);
        $this->assertSame(['DEV-2026-001', 'brouillon', true, 150000.0, 18.0, 15, $this->client->id], [
            $devis->quote_number, $devis->status, (bool) $devis->is_active, (float) $devis->amount,
            (float) $devis->tva_rate, (int) $devis->validity_days, $devis->customer_id,
        ]);
        $this->assertSame('2026-10-20', $devis->quote_date->format('Y-m-d'));
        $this->assertSame(1, AuditLog::where('action', 'quote.created')->count());
    }

    public function test_le_numero_envoye_par_le_poste_est_ignore_et_la_numerotation_est_continue(): void
    {
        $this->pousser(
            $this->devis(['quote_number' => 'DEV-2026-999']),
            $this->devis(['id' => self::DEVIS_2, 'quote_date' => '2026-10-21']),
        )->assertJsonPath('quotes.rejected', []);

        $this->assertSame('DEV-2026-001', Quote::findOrFail(self::DEVIS)->quote_number);
        $this->assertSame('DEV-2026-002', Quote::findOrFail(self::DEVIS_2)->quote_number);
    }

    public function test_le_renvoi_d_un_devis_connu_est_acquitte_sans_rien_reecrire(): void
    {
        $this->pousser($this->devis())->assertOk();
        $avant = Quote::findOrFail(self::DEVIS)->updated_at;
        Carbon::setTestNow('2026-10-21 11:00:00');

        $this->pousser($this->devis())->assertJsonPath('quotes.accepted', [self::DEVIS]);

        $this->assertSame(1, Quote::count());
        $this->assertSame(1, AuditLog::where('action', 'quote.created')->count());
        $this->assertSame(0, AuditLog::where('action', 'quote.updated')->count());
        $this->assertTrue($avant->equalTo(Quote::findOrFail(self::DEVIS)->updated_at), 'aucune écriture au renvoi');
    }

    public function test_modifier_les_champs_d_un_devis_connu_garde_son_numero(): void
    {
        $this->pousser($this->devis())->assertOk();

        $this->pousser($this->devis(['amount' => 200000, 'tva_rate' => 0, 'validity_days' => 30, 'note' => 'Remise accordée']))
            ->assertJsonPath('quotes.accepted', [self::DEVIS]);

        $devis = Quote::findOrFail(self::DEVIS);
        $this->assertSame(['DEV-2026-001', 200000.0, 0.0, 30, 'Remise accordée'], [
            $devis->quote_number, (float) $devis->amount, (float) $devis->tva_rate, (int) $devis->validity_days, $devis->note,
        ]);
        $this->assertSame(1, AuditLog::where('action', 'quote.updated')->count());
    }

    public function test_un_devis_cree_puis_envoye_et_accepte_hors_ligne_parcourt_le_cycle_et_trace_chaque_etape(): void
    {
        $this->pousser($this->devis(['status' => 'accepte']))->assertJsonPath('quotes.accepted', [self::DEVIS]);

        $this->assertSame('accepte', Quote::findOrFail(self::DEVIS)->status);
        $this->assertSame([1, 1, 1], [
            AuditLog::where('action', 'quote.created')->count(),
            AuditLog::where('action', 'quote.sent')->count(),
            AuditLog::where('action', 'quote.accepted')->count(),
        ]);
    }

    public function test_un_devis_refuse_apres_envoi(): void
    {
        $this->pousser($this->devis(['status' => 'envoye']))->assertOk();
        $this->pousser($this->devis(['status' => 'refuse']))->assertJsonPath('quotes.accepted', [self::DEVIS]);

        $this->assertSame('refuse', Quote::findOrFail(self::DEVIS)->status);
        $this->assertSame(1, AuditLog::where('action', 'quote.refused')->count());
    }

    public function test_archiver_au_poste_est_logique_et_idempotent(): void
    {
        $this->pousser($this->devis())->assertOk();

        $this->pousser($this->devis(['is_active' => false]))->assertJsonPath('quotes.accepted', [self::DEVIS]);
        $this->pousser($this->devis(['is_active' => false]))->assertJsonPath('quotes.accepted', [self::DEVIS]);

        $this->assertFalse((bool) Quote::findOrFail(self::DEVIS)->is_active);
        $this->assertSame(1, Quote::count(), 'la ligne est gardée');
        $this->assertSame(1, AuditLog::where('action', 'quote.archived')->count(), 'second archivage : aucune seconde trace');
    }

    public function test_un_devis_cree_puis_archive_hors_ligne_arrive_archive(): void
    {
        $this->pousser($this->devis(['is_active' => false]))->assertJsonPath('quotes.accepted', [self::DEVIS]);

        $devis = Quote::findOrFail(self::DEVIS);
        $this->assertFalse((bool) $devis->is_active);
        $this->assertSame('DEV-2026-001', $devis->quote_number);
    }

    public function test_quotes_n_est_pas_un_referentiel_ignore(): void
    {
        $this->pousser($this->devis())->assertJsonPath('referentiels_ignored', 0);
    }

    // ── Envoi : rejeté ────────────────────────────────────────────────────────────────────────────────────────────

    public function test_un_devis_date_dans_un_exercice_clos_est_rejete_avec_le_motif_et_rien_n_est_ecrit(): void
    {
        $reponse = $this->pousser($this->devis(['quote_date' => '2025-12-20']))->assertOk();

        $reponse->assertJsonPath('quotes.accepted', []);
        $this->assertSame(self::DEVIS, $reponse->json('quotes.rejected.0.id'));
        $this->assertSame("L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.", $reponse->json('quotes.rejected.0.reason'));
        $this->assertSame(0, Quote::count());
    }

    public function test_modifier_ou_archiver_un_devis_d_un_exercice_clos_est_refuse(): void
    {
        $this->enBase([
            'id' => self::DEVIS, 'quote_number' => 'DEV-2025-001', 'customer_id' => $this->client->id,
            'articles_description' => 'Cages', 'amount' => 100000, 'tva_rate' => 18, 'validity_days' => 15,
            'quote_date' => '2025-12-20', 'status' => 'brouillon', 'is_active' => true,
        ]);
        $motif = "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.";

        $modif = $this->pousser($this->devis(['quote_date' => '2025-12-20', 'amount' => 1]));
        $archive = $this->pousser($this->devis(['quote_date' => '2025-12-20', 'amount' => 100000, 'articles_description' => 'Cages', 'is_active' => false]));

        $this->assertSame($motif, $modif->json('quotes.rejected.0.reason'));
        $this->assertSame($motif, $archive->json('quotes.rejected.0.reason'));
        $this->assertSame([100000.0, true], [(float) Quote::findOrFail(self::DEVIS)->amount, (bool) Quote::findOrFail(self::DEVIS)->is_active]);
    }

    public function test_un_changement_de_statut_interdit_est_rejete_et_rien_n_est_ecrit(): void
    {
        $this->pousser($this->devis(['status' => 'accepte']))->assertOk();

        foreach ([
            ['brouillon', 'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Brouillon ».'],
            ['envoye', 'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Envoyé ».'],
            ['refuse', 'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Refusé ».'],
        ] as [$statut, $motif]) {
            $reponse = $this->pousser($this->devis(['status' => $statut]));
            $this->assertSame([], $reponse->json('quotes.accepted'), $statut);
            $this->assertSame($motif, $reponse->json('quotes.rejected.0.reason'), $statut);
        }

        $this->assertSame('accepte', Quote::findOrFail(self::DEVIS)->status);
    }

    public function test_le_poste_ne_pose_jamais_le_statut_facture(): void
    {
        $reponse = $this->pousser($this->devis(['status' => 'facture']));

        $this->assertSame([], $reponse->json('quotes.accepted'));
        $this->assertSame(self::DEVIS, $reponse->json('quotes.rejected.0.id'));
        $this->assertNotEmpty($reponse->json('quotes.rejected.0.reason'));
        $this->assertSame(0, Quote::count());
    }

    public function test_un_devis_facture_ou_archive_ne_se_modifie_plus(): void
    {
        $this->enBase([
            'id' => self::DEVIS, 'quote_number' => 'DEV-2026-001', 'customer_id' => $this->client->id,
            'articles_description' => '2 cages galvanisées 6 compartiments sur mesure', 'amount' => 150000, 'tva_rate' => 18,
            'validity_days' => 15, 'quote_date' => '2026-10-20', 'status' => 'facture', 'is_active' => true,
        ]);
        $this->enBase([
            'id' => self::DEVIS_2, 'quote_number' => 'DEV-2026-002', 'customer_id' => $this->client->id,
            'articles_description' => 'Enclos', 'amount' => 90000, 'tva_rate' => 0, 'validity_days' => 15,
            'quote_date' => '2026-10-20', 'status' => 'brouillon', 'is_active' => false,
        ]);

        $facture = $this->pousser($this->devis(['status' => 'brouillon', 'amount' => 1]));
        $archive = $this->pousser($this->devis(['id' => self::DEVIS_2, 'articles_description' => 'Enclos', 'amount' => 1, 'tva_rate' => 0]));

        $this->assertSame('Ce devis est facturé : il ne peut plus être modifié.', $facture->json('quotes.rejected.0.reason'));
        $this->assertSame('Ce devis est archivé : il ne peut plus être modifié.', $archive->json('quotes.rejected.0.reason'));
        $this->assertSame([150000.0, 90000.0], [(float) Quote::findOrFail(self::DEVIS)->amount, (float) Quote::findOrFail(self::DEVIS_2)->amount]);
    }

    public function test_les_champs_invalides_sont_rejetes_avec_les_motifs_francais(): void
    {
        $reponse = $this->pousser(
            $this->devis(['customer_id' => 'dddd0000-0000-4000-8000-00000000ffff']),
            $this->devis(['id' => self::DEVIS_2, 'amount' => -5, 'articles_description' => '', 'validity_days' => 0]),
            ['id' => 'pas-un-uuid'],
        );

        $motifs = collect($reponse->json('quotes.rejected'))->pluck('reason', 'id');
        $this->assertStringContainsString('client', $motifs[self::DEVIS]);
        $this->assertStringContainsString('montant', $motifs[self::DEVIS_2]);
        $this->assertStringContainsString('articles', $motifs[self::DEVIS_2]);
        $this->assertStringContainsString('validité', $motifs[self::DEVIS_2]);
        $this->assertSame(0, Quote::count());
        $this->assertCount(3, $reponse->json('quotes.rejected'));
    }

    public function test_un_compte_sans_manage_ventes_est_refuse_devis_par_devis(): void
    {
        $this->jetonDe('animalier');

        $reponse = $this->pousser($this->devis())->assertOk();

        $this->assertSame([], $reponse->json('quotes.accepted'));
        $this->assertSame(self::DEVIS, $reponse->json('quotes.rejected.0.id'));
        $this->assertSame(0, Quote::count());
    }

    public function test_un_caissier_peut_envoyer_ses_devis(): void
    {
        $this->jetonDe('caissier');

        $this->pousser($this->devis())->assertJsonPath('quotes.accepted', [self::DEVIS]);
    }

    public function test_le_client_fusionne_du_meme_envoi_rattache_le_devis_au_client_du_serveur(): void
    {
        $idPoste = 'cccc1111-0000-4000-8000-0000000000aa';

        $reponse = $this->envoyer([
            'customers' => [[
                'id' => $idPoste, 'name' => 'AMOUSSOU Régis', 'phone' => '+229 97 12 34 56', 'is_active' => true,
            ]],
            'quotes' => [$this->devis(['customer_id' => $idPoste])],
        ])->assertOk();

        $reponse->assertJsonPath('quotes.accepted', [self::DEVIS]);
        $this->assertSame($this->client->id, Quote::findOrFail(self::DEVIS)->customer_id);
        $this->assertSame(1, Customer::count());
    }

    // ── Tirage ────────────────────────────────────────────────────────────────────────────────────────────────────

    private function tirer(string $requete = 'page=1')
    {
        $this->app['auth']->forgetGuards();

        return $this->actingAs($this->compte ?? $this->admin, 'sanctum')->getJson('/api/sync/pull?'.$requete)->assertOk();
    }

    public function test_le_tirage_sert_les_devis_actifs_et_archives_avec_numero_dates_et_updated_at(): void
    {
        $this->pousser($this->devis(['note' => 'Remise accordée']))->assertOk();
        $this->pousser($this->devis(['id' => self::DEVIS_2, 'is_active' => false, 'quote_date' => '2026-10-19']))->assertOk();

        $corps = $this->tirer();

        $this->assertContains('quotes', $corps->json('tables_servies'));
        $lignes = collect($corps->json('quotes'))->keyBy('id');
        $this->assertCount(2, $lignes);
        $this->assertEqualsCanonicalizing(
            ['id', 'quote_number', 'customer_id', 'articles_description', 'amount', 'tva_rate', 'validity_days', 'quote_date',
                'note', 'status', 'is_active', 'updated_at'],
            array_keys($lignes[self::DEVIS]),
        );
        $this->assertSame(['DEV-2026-001', '2026-10-20', 150000.0, 18.0, 15, 'brouillon', true, 'Remise accordée'], [
            $lignes[self::DEVIS]['quote_number'], $lignes[self::DEVIS]['quote_date'], (float) $lignes[self::DEVIS]['amount'],
            (float) $lignes[self::DEVIS]['tva_rate'], $lignes[self::DEVIS]['validity_days'], $lignes[self::DEVIS]['status'],
            $lignes[self::DEVIS]['is_active'], $lignes[self::DEVIS]['note'],
        ]);
        $this->assertFalse($lignes[self::DEVIS_2]['is_active']);
    }

    public function test_le_tirage_incremental_ne_sert_que_ce_qui_a_change_depuis_since(): void
    {
        $this->pousser($this->devis())->assertOk();
        Carbon::setTestNow('2026-10-21 12:00:00');
        $this->pousser($this->devis(['id' => self::DEVIS_2, 'quote_date' => '2026-10-21']))->assertOk();

        $corps = $this->tirer('page=1&since='.urlencode('2026-10-21T10:00:00Z'));

        $this->assertSame([self::DEVIS_2], collect($corps->json('quotes'))->pluck('id')->all());
    }

    public function test_un_compte_qui_ne_lit_pas_les_ventes_ne_recoit_pas_les_devis(): void
    {
        $this->pousser($this->devis())->assertOk();
        $this->jetonDe('animalier');

        $corps = $this->tirer();

        $this->assertNotContains('quotes', $corps->json('tables_servies'));
        $this->assertArrayNotHasKey('quotes', $corps->json());
    }

    public function test_le_tirage_sans_page_d_un_poste_ancien_sert_aussi_les_devis(): void
    {
        $this->pousser($this->devis())->assertOk();

        $corps = $this->tirer('');

        $this->assertSame([self::DEVIS], collect($corps->json('quotes'))->pluck('id')->all());
    }
}
