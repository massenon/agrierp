<?php

namespace Tests\Feature;

use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\Feature\Concerns\AvecEmecef;
use Tests\TestCase;

/**
 * MECEF-2 — LE RÉSULTAT DU BOÎTIER D'UN POSTE, REÇU AVEC LA VENTE (`ResultatBoitierDuPoste`, appliqué par `pushSales`).
 *
 * ⚠️ NON VÉRIFIÉ AVEC UN VRAI BOÎTIER : aucun appareil ici, le poste est simulé par le JSON qu'il envoie.
 * Règles éprouvées : appliqué en mode boîtier SEULEMENT ; facture normalisée à déclarer SEULEMENT ; JAMAIS par-dessus une facture
 * déjà normalisée ; `transmise` exige un `qr_ref` non vide ; jamais `mecef_uid` ; aucun appel réseau du serveur (le boîtier est local).
 */
class MecefBoitierPosteEnvoiTest extends TestCase
{
    use AvecEmecef;
    use RefreshDatabase;

    private const SALE = 'c2222222-2222-4222-8222-222222222222';

    protected function setUp(): void
    {
        parent::setUp();
        $this->decorVentes();
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
        Http::fake();
    }

    /** @return array<string, mixed> */
    private function lignePoste(array $plus = []): array
    {
        return array_merge([
            'id' => self::SALE, 'payment_mode' => 'especes', 'status' => 'validee',
            'subtotal' => 11800, 'discount' => 0, 'total' => 11800, 'sold_at' => now()->subMinute()->toDateTimeString(),
            'facture_type' => 'normalisee', 'client_nom_facture' => 'AMOUSSOU Régis', 'aib_taux' => 'N/A',
            'lines' => [['product_id' => $this->taxable->id, 'qty' => 2, 'unit_price' => 5900, 'manual_total_amount' => 11800]],
        ], $plus);
    }

    /** @return array<string, mixed> */
    private function bloc(array $plus = []): array
    {
        return array_merge([
            'status' => 'transmise', 'qr_ref' => 'F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;3201910768821;20200503135002',
            'code' => 'NW34NID6ZHANFNMZ2IU7LL3H', 'nim' => 'ED04000623', 'normalise_le' => '2026-11-09 10:15:00', 'message' => null,
        ], $plus);
    }

    private function pousser(array $vente)
    {
        return $this->actingAs(User::first(), 'sanctum')->postJson('/api/sync/push', ['sales' => [$vente]]);
    }

    public function test_en_mode_boitier_une_vente_nouvelle_porte_la_normalisation_du_poste(): void
    {
        $this->reglerEmecef('boitier', null);

        $r = $this->pousser($this->lignePoste(['mecef' => $this->bloc()]));

        $this->assertSame([self::SALE], $r->json('sales.accepted'));
        $v = Sale::findOrFail(self::SALE);
        $this->assertSame('transmise', $v->mecef_status);
        $this->assertStringStartsWith('F;ED04000623;', $v->mecef_qr_ref);
        $this->assertSame('NW34NID6ZHANFNMZ2IU7LL3H', $v->mecef_code);
        $this->assertSame('ED04000623', $v->mecef_nim);
        $this->assertNull($v->mecef_uid, 'jamais d\'identifiant e-MECeF pour une facture du boîtier');
        $this->assertNull($v->mecef_message);
        Http::assertNothingSent();
    }

    public function test_vente_deja_poussee_puis_transmise_par_le_poste_est_normalisee_au_second_envoi(): void
    {
        $this->reglerEmecef('boitier', null);

        // 1er envoi (hors ligne puis en ligne) : la vente part SANS résultat, elle attend le poste.
        $this->pousser($this->lignePoste());
        $this->assertSame('en_attente', Sale::findOrFail(self::SALE)->mecef_status);

        // 2e envoi : le poste a transmis entre-temps, il renvoie la vente avec le résultat. Vente connue : succès silencieux + résultat.
        $r = $this->pousser($this->lignePoste(['mecef' => $this->bloc()]));

        $this->assertSame([self::SALE], $r->json('sales.accepted'));
        $this->assertSame('transmise', Sale::findOrFail(self::SALE)->mecef_status);
        $this->assertSame(1, Sale::count(), 'jamais une seconde vente');
    }

    public function test_un_refus_du_boitier_est_garde_avec_son_motif(): void
    {
        $this->reglerEmecef('boitier', null);

        $this->pousser($this->lignePoste(['mecef' => ['status' => 'erreur', 'message' => 'Le boîtier a refusé la facture (price requis).']]));

        $v = Sale::findOrFail(self::SALE);
        $this->assertSame('erreur', $v->mecef_status);
        $this->assertSame('Le boîtier a refusé la facture (price requis).', $v->mecef_message);
        $this->assertNull($v->mecef_qr_ref);
    }

    public function test_hors_mode_boitier_le_bloc_est_ignore(): void
    {
        foreach (['emecef', 'desactive'] as $mode) {
            Sale::query()->delete();
            $this->reglerEmecef($mode);
            if ($mode === 'emecef') {
                $this->fauxEmecefSucces();
            }

            $this->pousser($this->lignePoste(['mecef' => $this->bloc()]));

            $v = Sale::findOrFail(self::SALE);
            $this->assertNotSame('F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;3201910768821;20200503135002', $v->mecef_qr_ref, "mode $mode : le poste n'écrit pas la normalisation");
            $this->assertNull($v->mecef_nim, "mode $mode");
        }
    }

    public function test_une_facture_simple_ne_devient_jamais_normalisee_par_le_poste(): void
    {
        $this->reglerEmecef('boitier', null);

        $this->pousser($this->lignePoste(['facture_type' => 'simple', 'client_nom_facture' => null, 'mecef' => $this->bloc()]));

        $v = Sale::findOrFail(self::SALE);
        $this->assertSame('simple', $v->facture_type);
        $this->assertNotSame('transmise', $v->mecef_status);
        $this->assertNull($v->mecef_qr_ref);
    }

    public function test_une_vente_deja_normalisee_n_est_jamais_reecrite(): void
    {
        $this->reglerEmecef('boitier', null);
        $this->pousser($this->lignePoste(['mecef' => $this->bloc()]));

        // Un autre envoi (autre poste, ou rejeu) tente d'écraser : un refus, puis un autre QR.
        $this->pousser($this->lignePoste(['mecef' => ['status' => 'erreur', 'message' => 'autre']]))->assertOk()->assertJsonPath('sales.accepted.0', self::SALE);
        $this->pousser($this->lignePoste(['mecef' => $this->bloc(['qr_ref' => 'F;AUTRE;AUTRE;1;20260101000000', 'code' => 'AUTRE'])]))->assertOk()->assertJsonPath('sales.accepted.0', self::SALE);

        $v = Sale::findOrFail(self::SALE);
        $this->assertSame('transmise', $v->mecef_status);
        $this->assertStringStartsWith('F;ED04000623;', $v->mecef_qr_ref);
        $this->assertSame('NW34NID6ZHANFNMZ2IU7LL3H', $v->mecef_code);
    }

    public function test_transmise_sans_qr_est_ignoree_la_vente_reste_en_attente(): void
    {
        $this->reglerEmecef('boitier', null);

        foreach ([null, '', '   '] as $qr) {
            Sale::query()->delete();
            $r = $this->pousser($this->lignePoste(['mecef' => $this->bloc(['qr_ref' => $qr])]));

            $this->assertSame([self::SALE], $r->json('sales.accepted'), 'la vente a eu lieu : elle est acceptée');
            $v = Sale::findOrFail(self::SALE);
            $this->assertNotSame('transmise', $v->mecef_status);
            $this->assertNull($v->mecef_qr_ref);
        }
    }

    public function test_le_bloc_ne_peut_pas_ecrire_d_autres_colonnes(): void
    {
        $this->reglerEmecef('boitier', null);

        $this->pousser($this->lignePoste(['mecef' => $this->bloc() + ['uid' => 'uid-pirate', 'mecef_uid' => 'uid-pirate', 'aib_montant' => 999, 'jeton' => 'x']]));

        $v = Sale::findOrFail(self::SALE);
        $this->assertNull($v->mecef_uid);
        $this->assertNull($v->mecef_aib_montant);
    }

    public function test_la_passerelle_boitier_du_serveur_garde_la_vente_en_attente_sans_reseau(): void
    {
        $this->reglerEmecef('boitier', null);
        $vente = $this->venteAFacturer();

        $r = app(\App\Services\Mecef\FacturationMecefService::class)->facturer($vente);

        $this->assertFalse($r['transmise']);
        $this->assertSame('en_attente', $vente->fresh()->mecef_status);
        Http::assertNothingSent();
    }
}
