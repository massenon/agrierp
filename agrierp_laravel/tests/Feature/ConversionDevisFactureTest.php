<?php

namespace Tests\Feature;

use App\Actions\ConvertirDevisEnFactureAction;
use App\Exceptions\ConversionDevisRefuseeException;
use App\Models\AccountingEntry;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\Customer;
use App\Models\Quote;
use App\Models\Receivable;
use App\Models\Sale;
use App\Models\User;
use App\Services\Mecef\MecefGatewayInterface;
use App\Services\TvaSettingService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket DEV3 — CONVERSION D'UN DEVIS ACCEPTÉ EN FACTURE (PRD `docs/prd/devis-poste.md`, § 11, DEV-Q1 close).
 *
 * UN point de passage (`ConvertirDevisEnFactureAction`) que partagent l'écran web « Convertir en Facture » et la DEMANDE
 * de conversion du poste (`quote_conversions` de `/api/sync/push`). Une facture EST une vente (`sales`) : celle d'un
 * devis est une vente À CRÉDIT, SANS LIGNE (une prestation libre : ni produit, ni stock), liée au devis par
 * `quotes.converted_sale_id`.
 *
 * Jeu calculé à la main (21/10/2026) : devis « 2 cages galvanisées » 150 000 F HT, TVA 18 %.
 *   TVA = 150 000 × 18 % = 27 000 ; TTC = 177 000 ; échéance de la créance = +30 jours = 20/11/2026.
 *   Écriture : Débit 411 Clients 177 000 / Crédit 701 Ventes 150 000 / Crédit 443 TVA facturée 27 000.
 * Devis à 0 % : 90 000 F → facture 90 000, écriture Débit 411 90 000 / Crédit 701 90 000 (aucune ligne 443).
 */
class ConversionDevisFactureTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const DEVIS = 'dddd2222-0000-4000-8000-000000000001';

    private const DEVIS_2 = 'dddd2222-0000-4000-8000-000000000002';

    private Customer $client;

    private ?User $compte = null;

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2026-10-21 09:00:00');
        $this->exercice(2025, 'cloture');
        $this->exercice(2026);
        TvaSettingService::oublier();

        // Le dispositif MeCeF du projet est factice et échoue au hasard (5 %) : un essai déterministe en fixe l'issue.
        $this->app->instance(MecefGatewayInterface::class, new class implements MecefGatewayInterface
        {
            public function transmit(Sale $sale): array
            {
                return ['success' => true, 'qr_ref' => 'NIM-TEST|SIGNATURE', 'message' => 'Facture transmise (essai).'];
            }
        });

        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'phone' => '97123456', 'is_active' => true]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        TvaSettingService::oublier();
        parent::tearDown();
    }

    private function devis(array $remplace = [], string $id = self::DEVIS): Quote
    {
        $devis = new Quote();
        $devis->id = $id;
        $devis->fill(array_merge([
            'quote_number' => 'DEV-2026-'.str_pad((string) (Quote::count() + 1), 3, '0', STR_PAD_LEFT),
            'customer_id' => $this->client->id,
            'articles_description' => '2 cages galvanisées 6 compartiments sur mesure',
            'amount' => 150000, 'tva_rate' => 18, 'validity_days' => 15,
            'quote_date' => '2026-10-20', 'status' => 'accepte', 'is_active' => true,
        ], $remplace));
        $devis->save();

        return $devis;
    }

    private function convertir(string $id = self::DEVIS, ?Carbon $le = null): array
    {
        return app(ConvertirDevisEnFactureAction::class)->execute($id, $le);
    }

    private function assertRefus(string $message, callable $geste): void
    {
        try {
            $geste();
            $this->fail('Le refus « '.$message.' » était attendu.');
        } catch (ConversionDevisRefuseeException $e) {
            $this->assertSame($message, $e->getMessage());
        }
    }

    // ── Le geste : une facture, une créance, une écriture, un lien ───────────────────────────────────────────────────

    public function test_un_devis_accepte_devient_une_facture_a_credit_sans_ligne_au_total_ttc_du_devis(): void
    {
        $this->devis();

        $resultat = $this->convertir();

        $this->assertFalse($resultat['deja']);
        /** @var Sale $vente */
        $vente = $resultat['vente'];
        $this->assertSame(1, Sale::count());
        $this->assertSame(0, $vente->lines()->count(), 'une prestation libre : aucune ligne, aucun produit');
        $this->assertSame(
            [$this->client->id, 'credit', 177000.0, 0.0, 177000.0, 'validee', '2026-10-21'],
            [$vente->customer_id, $vente->payment_mode, (float) $vente->subtotal, (float) $vente->discount,
                (float) $vente->total, $vente->status, $vente->sold_at->format('Y-m-d')],
        );
    }

    public function test_le_devis_passe_a_facture_et_garde_le_lien_vers_la_facture(): void
    {
        $this->devis();

        $vente = $this->convertir()['vente'];

        $devis = Quote::findOrFail(self::DEVIS);
        $this->assertSame(['facture', $vente->id, true], [$devis->status, $devis->converted_sale_id, (bool) $devis->is_active]);
        $this->assertSame($vente->id, $devis->sale->id);
        $this->assertSame(self::DEVIS, $vente->devis->id);
        $this->assertMatchesRegularExpression('/^FV-2026-[0-9A-F]{6}$/', $devis->numero_facture);
        $this->assertSame('FV-2026-'.strtoupper(substr($vente->id, 0, 6)), $devis->numero_facture);
    }

    public function test_la_facture_cree_sa_creance_a_trente_jours(): void
    {
        $this->devis();

        $vente = $this->convertir()['vente'];

        $creance = Receivable::where('sale_id', $vente->id)->firstOrFail();
        $this->assertSame(
            [$this->client->id, 177000.0, 0.0, 'en_cours', '2026-11-20'],
            [$creance->customer_id, (float) $creance->amount, (float) $creance->amount_paid, $creance->status, $creance->due_date->format('Y-m-d')],
        );
    }

    public function test_l_ecriture_de_vente_est_passee_au_serveur_avec_la_tva_du_devis(): void
    {
        $this->devis();

        $vente = $this->convertir()['vente'];

        $ecriture = AccountingEntry::with('lines.account')->where('source_type', 'sale')->where('source_id', $vente->id)->firstOrFail();
        $this->assertSame($ecriture->id, $vente->fresh()->accounting_entry_id);
        $lignes = $ecriture->lines->mapWithKeys(fn ($l) => [$l->account->code => [(float) $l->debit, (float) $l->credit]])->all();
        ksort($lignes);
        $this->assertSame(['411' => [177000.0, 0.0], '443' => [0.0, 27000.0], '701' => [0.0, 150000.0]], $lignes);
        $this->assertSame('2026-10-21', $ecriture->entry_date->format('Y-m-d'));
    }

    public function test_un_devis_a_zero_pour_cent_ne_ventile_aucune_tva(): void
    {
        $this->devis(['amount' => 90000, 'tva_rate' => 0]);

        $vente = $this->convertir()['vente'];

        $this->assertSame(90000.0, (float) $vente->total);
        $ecriture = AccountingEntry::with('lines.account')->where('source_id', $vente->id)->firstOrFail();
        $lignes = $ecriture->lines->mapWithKeys(fn ($l) => [$l->account->code => [(float) $l->debit, (float) $l->credit]])->all();
        $this->assertSame(['411' => [90000.0, 0.0], '701' => [0.0, 90000.0]], $lignes);
    }

    public function test_une_exploitation_non_assujettie_facture_le_montant_ht_sans_tva(): void
    {
        CompanySetting::create(['company_name' => 'FERME ÉCOLE OLOUWACHEGOUN', 'tva_enabled' => false]);
        TvaSettingService::oublier();
        $this->devis();

        $vente = $this->convertir()['vente'];

        $this->assertSame(150000.0, (float) $vente->total);
        $ecriture = AccountingEntry::with('lines.account')->where('source_id', $vente->id)->firstOrFail();
        $this->assertSame(
            ['411' => [150000.0, 0.0], '701' => [0.0, 150000.0]],
            $ecriture->lines->mapWithKeys(fn ($l) => [$l->account->code => [(float) $l->debit, (float) $l->credit]])->all(),
        );
    }

    public function test_aucun_stock_n_est_touche_et_la_caisse_ne_bouge_pas(): void
    {
        $this->devis();
        $avant = [(float) $this->mais->fresh()->stock_qty, (float) $this->caisse->fresh()->balance];

        $this->convertir();

        $this->assertSame($avant, [(float) $this->mais->fresh()->stock_qty, (float) $this->caisse->fresh()->balance]);
        $this->assertSame(0, \App\Models\StockMovement::where('reference_type', 'sale')->count());
    }

    public function test_la_conversion_laisse_sa_trace_d_audit(): void
    {
        $this->devis();

        $this->convertir();

        $this->assertSame(1, AuditLog::where('action', 'quote.invoiced')->count());
        $this->assertSame(1, AuditLog::where('action', 'sale.validated')->count());
    }

    public function test_la_facture_est_datee_de_la_demande_quand_le_poste_l_a_faite_hors_ligne(): void
    {
        $this->devis();

        $vente = $this->convertir(self::DEVIS, Carbon::parse('2026-10-19 16:30:00', 'Africa/Porto-Novo'))['vente'];

        $this->assertSame('2026-10-19', $vente->sold_at->format('Y-m-d'));
        $this->assertSame('2026-11-18', Receivable::where('sale_id', $vente->id)->firstOrFail()->due_date->format('Y-m-d'));
        $this->assertSame('2026-10-19', AccountingEntry::where('source_id', $vente->id)->firstOrFail()->entry_date->format('Y-m-d'));
    }

    // ── Idempotence : une seule facture par devis ───────────────────────────────────────────────────────────────────

    public function test_convertir_deux_fois_ne_cree_qu_une_facture(): void
    {
        $this->devis();

        $premiere = $this->convertir();
        $seconde = $this->convertir();

        $this->assertFalse($premiere['deja']);
        $this->assertTrue($seconde['deja']);
        $this->assertSame($premiere['vente']->id, $seconde['vente']->id);
        $this->assertSame([1, 1, 1, 1], [
            Sale::count(), Receivable::count(), AccountingEntry::where('source_type', 'sale')->count(),
            AuditLog::where('action', 'quote.invoiced')->count(),
        ]);
    }

    public function test_deux_devis_ne_peuvent_pas_porter_la_meme_facture(): void
    {
        $this->devis();
        $vente = $this->convertir()['vente'];
        $autre = $this->devis(['status' => 'accepte'], self::DEVIS_2);

        $this->expectException(\Illuminate\Database\UniqueConstraintViolationException::class);
        $autre->update(['converted_sale_id' => $vente->id]);
    }

    // ── Refus : chaque règle, son motif, et rien n'est écrit ───────────────────────────────────────────────────────

    public function test_seul_un_devis_accepte_est_convertible(): void
    {
        foreach ([['brouillon', 'Brouillon'], ['envoye', 'Envoyé'], ['refuse', 'Refusé']] as $i => [$statut, $libelle]) {
            $this->devis(['status' => $statut], 'dddd2222-0000-4000-8000-00000000010'.$i);
            $this->assertRefus(
                "Seul un devis accepté peut être converti en facture : celui-ci est « {$libelle} ».",
                fn () => $this->convertir('dddd2222-0000-4000-8000-00000000010'.$i),
            );
        }

        $this->assertSame([0, 0, 0], [Sale::count(), Receivable::count(), AccountingEntry::count()]);
    }

    public function test_un_devis_archive_n_est_pas_convertible(): void
    {
        $this->devis(['is_active' => false]);

        $this->assertRefus('Ce devis est archivé : il ne peut pas être converti en facture.', fn () => $this->convertir());
        $this->assertSame(0, Sale::count());
    }

    public function test_un_devis_inconnu_est_refuse(): void
    {
        $this->assertRefus('Devis introuvable.', fn () => $this->convertir('dddd2222-0000-4000-8000-0000000000ff'));
    }

    public function test_un_devis_d_un_exercice_clos_est_en_lecture_seule_et_n_est_pas_convertible(): void
    {
        $this->devis(['quote_date' => '2025-12-20']);

        $this->assertRefus(
            "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.",
            fn () => $this->convertir(),
        );
        $this->assertSame(['accepte', 0], [Quote::findOrFail(self::DEVIS)->status, Sale::count()]);
    }

    public function test_une_facture_datee_d_un_exercice_clos_ou_du_futur_est_refusee(): void
    {
        $this->devis();

        $this->assertRefus(
            "Facture refusée : l'exercice 2025 est clôturé : aucune saisie ne peut être datée du 15/12/2025.",
            fn () => $this->convertir(self::DEVIS, Carbon::parse('2025-12-15 10:00:00', 'Africa/Porto-Novo')),
        );
        $this->assertRefus(
            'Facture refusée : la date du 22/10/2026 est dans le futur.',
            fn () => $this->convertir(self::DEVIS, Carbon::parse('2026-10-22 10:00:00', 'Africa/Porto-Novo')),
        );
        $this->assertSame(0, Sale::count());
    }

    public function test_un_client_archive_ou_absent_refuse_la_conversion(): void
    {
        $this->devis();
        $this->client->update(['is_active' => false]);

        $this->assertRefus(
            'Le client « AMOUSSOU Régis » est archivé : réactivez-le avant de facturer ce devis.',
            fn () => $this->convertir(),
        );

        Quote::findOrFail(self::DEVIS)->update(['customer_id' => null]);
        $this->assertRefus('Ce devis n\'a pas de client : une facture à crédit en exige un.', fn () => $this->convertir());
        $this->assertSame(0, Sale::count());
    }

    public function test_un_plan_comptable_incomplet_refuse_la_conversion_et_ne_laisse_aucune_facture(): void
    {
        $this->devis();
        ChartOfAccount::where('code', '701')->delete();

        $this->assertRefus(
            'Plan comptable incomplet : le compte 701 (Ventes de produits) est introuvable. Complétez le plan comptable puis relancez la conversion.',
            fn () => $this->convertir(),
        );

        $this->assertSame(['accepte', null, 0, 0, 0], [
            Quote::findOrFail(self::DEVIS)->status, Quote::findOrFail(self::DEVIS)->converted_sale_id,
            Sale::count(), Receivable::count(), AccountingEntry::count(),
        ]);
    }

    public function test_le_compte_de_tva_manquant_refuse_un_devis_a_18_pour_cent_mais_pas_a_0(): void
    {
        ChartOfAccount::where('code', '443')->delete();
        $this->devis();
        $this->devis(['amount' => 90000, 'tva_rate' => 0], self::DEVIS_2);

        $this->assertRefus(
            'Plan comptable incomplet : le compte 443 (TVA facturée) est introuvable. Complétez le plan comptable puis relancez la conversion.',
            fn () => $this->convertir(),
        );
        $this->assertFalse($this->convertir(self::DEVIS_2)['deja']);
        $this->assertSame(1, Sale::count());
    }

    // ── L'envoi du poste : la DEMANDE de conversion ─────────────────────────────────────────────────────────────────

    private function jetonDe(string $role, array $permissionsEnPlus = []): void
    {
        $utilisateur = User::create([
            'name' => $role, 'username' => $role.'-cv'.User::count(), 'email' => $role.'-cv'.User::count().'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $utilisateur->assignRole($role);
        if ($permissionsEnPlus !== []) {
            // Un droit s'attribue par un rôle (le jeton d'un poste lit les rôles) : un rôle de test qui porte les deux.
            \App\Models\Role::firstOrCreate(['name' => 'facturier', 'guard_name' => 'web'])->givePermissionTo(['manage-ventes', ...$permissionsEnPlus]);
            $utilisateur->assignRole('facturier');
        }
        $this->compte = $utilisateur;
        // Le jeton du compte précédent reste en en-tête par défaut : sans cela, le garde garderait son utilisateur.
        $this->flushHeaders();
        $this->app['auth']->forgetGuards();
        $this->jeton = $this->postJson('/api/auth/login', [
            'identifiant' => $utilisateur->username, 'password' => 'AgriERP@2026', 'device_name' => 'poste-'.$utilisateur->username,
        ])->assertOk()->json('token');
    }

    private function demander(array ...$demandes)
    {
        return $this->envoyer(['quote_conversions' => $demandes]);
    }

    public function test_le_poste_demande_la_conversion_le_serveur_cree_la_facture_et_rend_le_lien(): void
    {
        $this->devis();

        $reponse = $this->demander(['id' => self::DEVIS])->assertOk();

        $vente = Sale::firstOrFail();
        $reponse->assertJsonPath('quote_conversions.accepted', [self::DEVIS])
            ->assertJsonPath('quote_conversions.rejected', [])
            ->assertJsonPath('quote_conversions.invoices.'.self::DEVIS.'.sale_id', $vente->id)
            ->assertJsonPath('quote_conversions.invoices.'.self::DEVIS.'.invoice_number', 'FV-2026-'.strtoupper(substr($vente->id, 0, 6)));
        $this->assertSame('facture', Quote::findOrFail(self::DEVIS)->status);
        $this->assertSame(177000.0, (float) $vente->total);
    }

    public function test_la_facture_d_un_devis_suit_le_circuit_normal_de_la_facturation(): void
    {
        $this->devis();

        $this->demander(['id' => self::DEVIS])->assertOk();

        // Comme toute vente reçue du poste : `FacturationMecefService::facturer`, après la transaction (aucun code DGI
        // nouveau, D-MECEF-1 laissé de côté). Le dispositif du projet est la passerelle factice.
        $vente = Sale::firstOrFail();
        $this->assertContains($vente->mecef_status, ['transmise', 'erreur', 'en_attente']);
        $this->assertSame('transmise', $vente->mecef_status);
    }

    public function test_le_renvoi_de_la_demande_est_acquitte_sans_seconde_facture(): void
    {
        $this->devis();
        $this->demander(['id' => self::DEVIS])->assertOk();

        $reponse = $this->demander(['id' => self::DEVIS])->assertOk();

        $reponse->assertJsonPath('quote_conversions.accepted', [self::DEVIS]);
        $this->assertSame(1, Sale::count());
        $this->assertSame(1, AuditLog::where('action', 'quote.invoiced')->count());
        $this->assertSame(Sale::firstOrFail()->id, $reponse->json('quote_conversions.invoices.'.self::DEVIS.'.sale_id'));
    }

    public function test_le_renvoi_du_devis_accepte_apres_sa_conversion_est_acquitte_sans_refus(): void
    {
        $this->devis();
        $this->demander(['id' => self::DEVIS])->assertOk();

        // Le poste n'a pas reçu la réponse : il renvoie le devis tel qu'il l'a vu (`accepte`) avec sa demande.
        $reponse = $this->envoyer([
            'quotes' => [[
                'id' => self::DEVIS, 'customer_id' => $this->client->id,
                'articles_description' => '2 cages galvanisées 6 compartiments sur mesure',
                'amount' => 150000, 'tva_rate' => 18, 'validity_days' => 15, 'quote_date' => '2026-10-20',
                'status' => 'accepte', 'is_active' => true,
            ]],
            'quote_conversions' => [['id' => self::DEVIS]],
        ])->assertOk();

        $reponse->assertJsonPath('quotes.accepted', [self::DEVIS])->assertJsonPath('quotes.rejected', [])
            ->assertJsonPath('quote_conversions.accepted', [self::DEVIS]);
        $this->assertSame(['facture', 1], [Quote::findOrFail(self::DEVIS)->status, Sale::count()]);
    }

    public function test_une_demande_peut_arriver_avec_le_devis_dans_le_meme_envoi_meme_hors_ligne(): void
    {
        $reponse = $this->envoyer([
            'quotes' => [[
                'id' => self::DEVIS, 'customer_id' => $this->client->id, 'articles_description' => 'Cages sur mesure',
                'amount' => 150000, 'tva_rate' => 18, 'validity_days' => 15, 'quote_date' => '2026-10-20',
                'status' => 'accepte', 'is_active' => true,
            ]],
            'quote_conversions' => [['id' => self::DEVIS, 'requested_at' => '2026-10-20T15:00:00+01:00']],
        ])->assertOk();

        $reponse->assertJsonPath('quotes.accepted', [self::DEVIS])->assertJsonPath('quote_conversions.accepted', [self::DEVIS]);
        $this->assertSame('2026-10-20', Sale::firstOrFail()->sold_at->format('Y-m-d'));
        $this->assertSame('facture', Quote::findOrFail(self::DEVIS)->status);
    }

    public function test_chaque_refus_revient_au_poste_avec_son_motif_et_rien_n_est_ecrit(): void
    {
        $this->devis(['status' => 'envoye']);
        $this->devis(['status' => 'accepte', 'is_active' => false], self::DEVIS_2);

        $reponse = $this->demander(
            ['id' => self::DEVIS],
            ['id' => self::DEVIS_2],
            ['id' => 'dddd2222-0000-4000-8000-0000000000ff'],
            ['id' => 'pas-un-uuid'],
        )->assertOk();

        $motifs = collect($reponse->json('quote_conversions.rejected'))->pluck('reason', 'id');
        $this->assertSame([], $reponse->json('quote_conversions.accepted'));
        $this->assertSame('Seul un devis accepté peut être converti en facture : celui-ci est « Envoyé ».', $motifs[self::DEVIS]);
        $this->assertSame('Ce devis est archivé : il ne peut pas être converti en facture.', $motifs[self::DEVIS_2]);
        $this->assertSame('Devis introuvable.', $motifs['dddd2222-0000-4000-8000-0000000000ff']);
        $this->assertStringContainsString('identifiant', $motifs['pas-un-uuid']);
        $this->assertSame(0, Sale::count());
    }

    public function test_un_refus_ne_fait_echouer_ni_l_envoi_ni_les_autres_demandes(): void
    {
        $this->devis(['status' => 'envoye']);
        $this->devis(['status' => 'accepte', 'amount' => 90000, 'tva_rate' => 0], self::DEVIS_2);

        $reponse = $this->demander(['id' => self::DEVIS], ['id' => self::DEVIS_2])->assertOk();

        $this->assertSame([self::DEVIS_2], $reponse->json('quote_conversions.accepted'));
        $this->assertSame(self::DEVIS, $reponse->json('quote_conversions.rejected.0.id'));
        $this->assertSame(1, Sale::count());
    }

    public function test_le_plan_comptable_incomplet_et_l_exercice_clos_sont_refuses_avec_leur_motif(): void
    {
        $this->devis();
        $this->devis(['quote_date' => '2025-12-20'], self::DEVIS_2);
        ChartOfAccount::where('code', '411')->delete();

        $reponse = $this->demander(['id' => self::DEVIS], ['id' => self::DEVIS_2])->assertOk();

        $motifs = collect($reponse->json('quote_conversions.rejected'))->pluck('reason', 'id');
        $this->assertSame('Plan comptable incomplet : le compte 411 (Clients) est introuvable. Complétez le plan comptable puis relancez la conversion.', $motifs[self::DEVIS]);
        $this->assertSame("L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.", $motifs[self::DEVIS_2]);
        $this->assertSame(0, Sale::count());
    }

    public function test_une_demande_datee_du_futur_est_refusee(): void
    {
        $this->devis();

        $reponse = $this->demander(['id' => self::DEVIS, 'requested_at' => '2026-10-25T10:00:00+01:00'])->assertOk();

        $this->assertSame('Facture refusée : la date du 25/10/2026 est dans le futur.', $reponse->json('quote_conversions.rejected.0.reason'));
        $this->assertSame(0, Sale::count());
    }

    public function test_le_droit_est_manage_ventes_ET_manage_facturation(): void
    {
        $this->devis();

        $this->jetonDe('caissier');
        $caissier = $this->demander(['id' => self::DEVIS])->assertOk();
        $this->assertSame(
            'Refusé : votre rôle ne permet pas de convertir un devis en facture (droits « ventes » et « facturation » requis). Connectez-vous au poste avec un compte autorisé.',
            $caissier->json('quote_conversions.rejected.0.reason'),
        );
        $this->assertSame(0, Sale::count());

        $this->jeton = '';
        $this->jetonDe('animalier');
        $animalier = $this->demander(['id' => self::DEVIS])->assertOk();
        $this->assertSame([], $animalier->json('quote_conversions.accepted'));

        $this->jeton = '';
        $this->jetonDe('caissier', ['manage-facturation']);
        $this->demander(['id' => self::DEVIS])->assertJsonPath('quote_conversions.accepted', [self::DEVIS]);
        $this->assertSame(1, Sale::count());
    }

    public function test_le_poste_ne_peut_toujours_pas_poser_le_statut_facture_lui_meme(): void
    {
        $reponse = $this->envoyer(['quotes' => [[
            'id' => self::DEVIS, 'customer_id' => $this->client->id, 'articles_description' => 'Cages',
            'amount' => 150000, 'tva_rate' => 18, 'validity_days' => 15, 'quote_date' => '2026-10-20',
            'status' => 'facture', 'is_active' => true,
        ]]])->assertOk();

        $this->assertSame([], $reponse->json('quotes.accepted'));
        $this->assertSame(0, Quote::count());
    }

    // ── Le tirage descend la facture et le lien ──────────────────────────────────────────────────────────────────────

    private function tirer(string $requete = 'page=1')
    {
        $this->app['auth']->forgetGuards();

        return $this->actingAs($this->compte ?? $this->admin, 'sanctum')->getJson('/api/sync/pull?'.$requete)->assertOk();
    }

    public function test_le_tirage_sert_le_lien_et_le_numero_de_facture_du_devis_et_la_facture_elle_meme(): void
    {
        $this->devis();
        $this->devis(['status' => 'brouillon'], self::DEVIS_2);
        $this->demander(['id' => self::DEVIS])->assertOk();
        $vente = Sale::firstOrFail();

        $corps = $this->tirer();

        $lignes = collect($corps->json('quotes'))->keyBy('id');
        $this->assertSame(
            ['facture', $vente->id, 'FV-2026-'.strtoupper(substr($vente->id, 0, 6))],
            [$lignes[self::DEVIS]['status'], $lignes[self::DEVIS]['converted_sale_id'], $lignes[self::DEVIS]['invoice_number']],
        );
        $this->assertSame([null, null], [$lignes[self::DEVIS_2]['converted_sale_id'], $lignes[self::DEVIS_2]['invoice_number']]);
        // Les ventes sont une famille d'historique : servies à la page suivante du tirage paginé, ou en bloc sans `page`.
        $complet = $this->tirer('');
        $facture = collect($complet->json('sales'))->firstWhere('id', $vente->id);
        $this->assertSame(['credit', 177000.0, 'validee', $this->client->id], [
            $facture['payment_mode'], (float) $facture['total'], $facture['status'], $facture['customer_id'],
        ]);
        $this->assertSame([], collect($complet->json('sale_lines'))->where('sale_id', $vente->id)->all());
    }

    public function test_le_devis_converti_redescend_au_tirage_incremental(): void
    {
        $this->devis();
        Carbon::setTestNow('2026-10-21 12:00:00');
        $this->demander(['id' => self::DEVIS])->assertOk();

        $corps = $this->tirer('page=1&since='.urlencode('2026-10-21T10:00:00Z'));

        $this->assertSame([self::DEVIS], collect($corps->json('quotes'))->pluck('id')->all());
    }
}
