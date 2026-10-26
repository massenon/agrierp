<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Sprint VW (VW4) — chaque verrouillage, déverrouillage et échec laisse une trace dans `audit_logs`.
 * Le mot de passe saisi n'est écrit NULLE PART.
 */
class VerrouSessionAuditTest extends VerrouSessionBase
{
    public function test_verrouiller_est_journalise_une_seule_fois(): void
    {
        $u = $this->utilisateur();
        $this->actingAs($u);

        $this->postJson('/verrouiller')->assertOk();
        $this->postJson('/verrouiller')->assertOk();

        $lignes = AuditLog::where('action', 'session.verrouillee')->get();
        $this->assertCount(1, $lignes);
        $this->assertSame($u->id, $lignes[0]->user_id);
        $this->assertSame('auth', $lignes[0]->module);
        $this->assertSame('127.0.0.1', $lignes[0]->ip_address);
    }

    public function test_deverrouiller_est_journalise(): void
    {
        $u = $this->verrouille();

        $this->postJson('/deverrouiller', ['password' => self::MOT_DE_PASSE])->assertOk();

        $this->assertSame(1, AuditLog::where('action', 'session.deverrouillee')->where('user_id', $u->id)->count());
        $this->assertSame(0, AuditLog::where('action', 'session.deverrouillage_echec')->count());
    }

    public function test_un_echec_est_journalise_sans_le_mot_de_passe(): void
    {
        $u = $this->verrouille();

        $this->postJson('/deverrouiller', ['password' => 'SecretTape#123'])->assertStatus(422);

        $this->assertSame(1, AuditLog::where('action', 'session.deverrouillage_echec')->where('user_id', $u->id)->count());
        $this->assertSame(0, AuditLog::where('action', 'session.deverrouillee')->count());
        $this->assertStringNotContainsString('SecretTape', json_encode(DB::table('audit_logs')->get()));
    }

    public function test_la_deconnexion_apres_dix_echecs_est_journalisee(): void
    {
        $u = $this->verrouille();
        foreach (range(1, 10) as $i) {
            $this->postJson('/deverrouiller', ['password' => 'Faux'.$i]);
            RateLimiter::clear($this->cleLimiteur($u));
        }

        $this->assertSame(10, AuditLog::where('action', 'session.deverrouillage_echec')->count());
        $this->assertSame(1, AuditLog::where('action', 'session.deconnexion_apres_echecs')->where('user_id', $u->id)->count());
    }

    public function test_un_blocage_du_limiteur_n_ecrit_pas_de_ligne_de_plus(): void
    {
        $this->verrouille();
        foreach (range(1, 5) as $i) {
            $this->postJson('/deverrouiller', ['password' => 'Faux'.$i]);
        }
        $avant = AuditLog::where('action', 'session.deverrouillage_echec')->count();

        $this->postJson('/deverrouiller', ['password' => 'Faux6'])->assertStatus(429);

        $this->assertSame(5, $avant);
        $this->assertSame($avant, AuditLog::where('action', 'session.deverrouillage_echec')->count());
    }

    public function test_les_libelles_sont_lisibles_jamais_la_cle_brute(): void
    {
        $attendus = [
            'session.verrouillee' => 'Session verrouillée',
            'session.deverrouillee' => 'Session déverrouillée',
            'session.deverrouillage_echec' => 'Échec de déverrouillage de la session',
            'session.deconnexion_apres_echecs' => "Déconnexion après trop d'échecs de déverrouillage",
        ];
        foreach ($attendus as $cle => $libelle) {
            $this->assertSame($libelle, (new AuditLog(['action' => $cle]))->action_label, $cle);
        }
    }
}
