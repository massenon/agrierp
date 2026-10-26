<?php

namespace Tests\Feature;

use App\Livewire\Facturation\Facturation;
use App\Livewire\Ventes\Devis;
use App\Models\Customer;
use App\Models\Quote;
use App\Models\Receivable;
use App\Models\Sale;
use App\Models\User;
use App\Services\Mecef\MecefGatewayInterface;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket DEV3 (web d'abord, article 5) — le bouton « Convertir en Facture » de « Devis & Proforma » : il n'affichait
 * qu'un toast d'attente ; il crée désormais la facture par `ConvertirDevisEnFactureAction` (voir
 * `ConversionDevisFactureTest` pour les règles et les écritures). Ici : l'écran, ses toasts, ses droits, sa visibilité.
 *
 * Jeu : devis « 2 cages galvanisées » 150 000 F HT, TVA 18 % → facture de 177 000 F TTC ; décor du 21/10/2026.
 */
class ConversionDevisWebTest extends TestCase
{
    use PreparationExercices;
    use RefreshDatabase;

    private const DEVIS = 'dddd3333-0000-4000-8000-000000000001';

    private Customer $client;

    private bool $dispositifAccepte = true;

    protected function setUp(): void
    {
        parent::setUp();

        $this->preparerDecor('2026-10-21 09:00:00');
        $this->exercice(2025, 'cloture');
        $this->exercice(2026);

        $this->client = Customer::create(['name' => 'AMOUSSOU Régis', 'phone' => '97123456', 'is_active' => true]);
        $this->dispositif(true);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function dispositif(bool $accepte): void
    {
        $this->app->instance(MecefGatewayInterface::class, new class($accepte) implements MecefGatewayInterface
        {
            public function __construct(private bool $accepte) {}

            public function transmit(Sale $sale): array
            {
                return $this->accepte
                    ? ['success' => true, 'qr_ref' => 'NIM-TEST|SIG', 'message' => 'Facture transmise (essai).']
                    : ['success' => false, 'qr_ref' => null, 'message' => 'Dispositif injoignable (essai).'];
            }
        });
    }

    private function devis(array $remplace = []): Quote
    {
        $devis = new Quote();
        $devis->id = self::DEVIS;
        $devis->fill(array_merge([
            'quote_number' => 'DEV-2026-001', 'customer_id' => $this->client->id,
            'articles_description' => '2 cages galvanisées 6 compartiments', 'amount' => 150000, 'tva_rate' => 18,
            'validity_days' => 15, 'quote_date' => '2026-10-20', 'status' => 'accepte', 'is_active' => true,
        ], $remplace));
        $devis->save();

        return $devis;
    }

    private function compte(string $role, array $droitsEnPlus = []): User
    {
        $utilisateur = User::create([
            'name' => $role, 'username' => $role.'-web', 'email' => $role.'-web@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $utilisateur->assignRole($role);
        if ($droitsEnPlus !== []) {
            \App\Models\Role::firstOrCreate(['name' => 'facturier', 'guard_name' => 'web'])->givePermissionTo($droitsEnPlus);
            $utilisateur->assignRole('facturier');
        }

        return $utilisateur;
    }

    public function test_convertir_cree_la_facture_et_le_toast_porte_son_numero(): void
    {
        $this->devis();

        $composant = Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS);

        $vente = Sale::firstOrFail();
        $numero = 'FV-2026-'.strtoupper(substr($vente->id, 0, 6));
        $composant->assertDispatched('toast', message: "Devis converti en facture {$numero} avec succès.", type: 'success');
        $devis = Quote::findOrFail(self::DEVIS);
        $this->assertSame(['facture', $vente->id], [$devis->status, $devis->converted_sale_id]);
        $this->assertSame(177000.0, (float) $vente->total);
        $this->assertSame(1, Receivable::count());
    }

    public function test_la_facture_est_transmise_par_le_circuit_normal(): void
    {
        $this->devis();

        Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS);

        $this->assertSame(['transmise', 'NIM-TEST|SIG'], [Sale::firstOrFail()->mecef_status, Sale::firstOrFail()->mecef_qr_ref]);
    }

    public function test_un_echec_du_dispositif_ne_defait_pas_la_facture_et_avertit(): void
    {
        $this->devis();
        $this->dispositif(false);

        $composant = Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS);

        $vente = Sale::firstOrFail();
        $numero = 'FV-2026-'.strtoupper(substr($vente->id, 0, 6));
        $this->assertSame(['erreur', 'facture'], [$vente->mecef_status, Quote::findOrFail(self::DEVIS)->status]);
        $composant->assertDispatched('toast', message: "Facture {$numero} créée — ATTENTION : facture normalisée MeCeF non transmise (Dispositif injoignable (essai).). La facture reste à transmettre : retransmettez-la depuis Facturation & MeCeF.", type: 'warning');
    }

    public function test_un_second_clic_ne_cree_pas_de_seconde_facture(): void
    {
        $this->devis();

        $composant = Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS)->call('convertToInvoice', self::DEVIS);

        $numero = 'FV-2026-'.strtoupper(substr(Sale::firstOrFail()->id, 0, 6));
        $composant->assertDispatched('toast', message: "Ce devis est déjà facturé : facture {$numero}.", type: 'warning');
        $this->assertSame(1, Sale::count());
    }

    public function test_un_devis_non_accepte_est_refuse_en_toast_d_erreur(): void
    {
        $this->devis(['status' => 'envoye']);

        Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS)
            ->assertDispatched('toast', message: 'Seul un devis accepté peut être converti en facture : celui-ci est « Envoyé ».', type: 'error');

        $this->assertSame([0, 'envoye'], [Sale::count(), Quote::findOrFail(self::DEVIS)->status]);
    }

    public function test_un_exercice_clos_est_refuse_en_toast_d_erreur(): void
    {
        $this->devis(['quote_date' => '2025-12-20']);

        Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS)
            ->assertDispatched('toast', message: "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.", type: 'error');

        $this->assertSame(0, Sale::count());
    }

    public function test_le_droit_exige_manage_ventes_et_manage_facturation(): void
    {
        $this->devis();

        $this->actingAs($this->compte('caissier'));
        Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS)->assertForbidden();
        $this->assertSame(0, Sale::count());

        $this->actingAs($this->compte('animalier'));
        Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS)->assertForbidden();

        $this->actingAs($this->compte('comptable', ['manage-facturation']));
        Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS)->assertForbidden();
        $this->assertSame(0, Sale::count(), 'manage-facturation seul ne suffit pas : manage-ventes aussi');
    }

    public function test_le_bouton_n_est_montre_qu_a_un_devis_accepte_et_aux_deux_droits(): void
    {
        $this->devis();

        $admin = Livewire::test(Devis::class)->html();
        $this->assertStringContainsString("convertToInvoice('".self::DEVIS."')", $admin);
        $this->assertStringContainsString('title="Convertir en Facture"', $admin);

        $this->actingAs($this->compte('caissier'));
        $this->assertStringNotContainsString('convertToInvoice', Livewire::test(Devis::class)->html(), 'sans droit facturation : pas de bouton');

        $this->actingAs($this->admin);
        Quote::findOrFail(self::DEVIS)->update(['status' => 'envoye']);
        $this->assertStringNotContainsString('convertToInvoice', Livewire::test(Devis::class)->html(), 'un devis envoyé n\'a pas le bouton');
    }

    public function test_un_devis_facture_montre_son_numero_de_facture_et_un_lien_vers_facturation(): void
    {
        $this->devis();
        Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS);
        $vente = Sale::firstOrFail();

        $html = Livewire::test(Devis::class)->html();

        $this->assertStringContainsString('FV-2026-'.strtoupper(substr($vente->id, 0, 6)), $html);
        $this->assertStringContainsString('Facturé', $html);
        $this->assertStringContainsString('title="Voir la facture"', $html);
        $this->assertStringContainsString('search='.$vente->id, $html);
        $this->assertStringNotContainsString('convertToInvoice', $html, 'plus de bouton une fois facturé');
    }

    public function test_la_facture_du_devis_est_listee_par_facturation_au_numero_fv(): void
    {
        $this->devis();
        Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS);
        $vente = Sale::firstOrFail();

        $html = Livewire::test(Facturation::class)->html();

        $this->assertStringContainsString('FV-2026-'.strtoupper(substr($vente->id, 0, 6)), $html);
        $this->assertStringContainsString('AMOUSSOU Régis', $html);
        $this->assertStringContainsString('177 000', $html);
        $this->assertSame(1, Livewire::test(Facturation::class)->instance()->kpis['factures_mois']);
    }

    public function test_la_declaration_de_tva_reprend_la_tva_du_devis_pour_une_facture_transmise(): void
    {
        $this->devis();
        Livewire::test(Devis::class)->call('convertToInvoice', self::DEVIS);

        $declaration = app(\App\Services\VatDeclarationService::class)->tvaCollectee('2026-10-01', '2026-10-31');

        $this->assertSame([150000.0, 27000.0, 177000.0], [$declaration['total_ht'], $declaration['total_tva'], $declaration['total_ttc']]);
    }
}
