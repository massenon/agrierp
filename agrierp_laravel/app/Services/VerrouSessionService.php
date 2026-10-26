<?php

namespace App\Services;

use App\Livewire\Auth\Login;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cookie;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;

/**
 * Sprint VW (VW1) — VERROU DE SESSION WEB : l'unique point de passage du verrouillage et du déverrouillage.
 *
 * Décision du client (26/10/2026) : « appliquer aussi le module de verrou session sur le web ». Le poste (VL-1/VL-2)
 * déverrouille par un PIN local, sans réseau ; le web est en ligne : le secret est le MOT DE PASSE DU COMPTE, vérifié
 * ICI, côté serveur. Même vocabulaire, mêmes durées, mécanisme propre à chaque côté (doctrine § 5.6).
 *
 * ⚠️ L'ÉTAT EST DANS LA SESSION LARAVEL (`session_locked`), pas dans le navigateur : `SessionVerrouillee` refuse
 * toute requête tant qu'il est posé. La minuterie du navigateur n'est qu'un déclencheur qui appelle `POST /verrouiller`.
 *
 * ⚠️ LIMITEUR DE LA CONNEXION RÉUTILISÉ : mêmes seuils que `Login` (5 essais, 15 minutes), clé propre au compte et à
 * l'adresse IP. Au-dessus, un compteur D'ÉCHECS CUMULÉS tenu dans la session : à 10, déconnexion complète (le poste fait
 * de même : 10 échecs = reconnexion exigée). Le blocage temporaire ne le remet pas à zéro ; seul un succès le fait.
 *
 * ⚠️ COOKIE « SE SOUVENIR DE MOI » : s'il restait, supprimer le cookie de session (outils du navigateur) rouvrirait
 * une session NEUVE et déverrouillée. Au verrouillage, le cookie de rappel est donc retiré du navigateur ; au
 * déverrouillage il est rétabli (seulement s'il existait).
 */
class VerrouSessionService
{
    /** Durées d'inactivité proposées, en minutes ; 0 = « Jamais ». Mêmes valeurs que `ReglageInactivite.choix` du poste. */
    public const DUREES = [0, 1, 5, 15, 30];

    /** Défaut : 5 minutes, comme le poste (décision VL-2). */
    public const DUREE_PAR_DEFAUT = 5;

    /** Échecs cumulés (dans la session) qui déconnectent. */
    public const ECHECS_MAX = 10;

    /** Seuils du limiteur : ceux de la connexion, jamais un second jeu de chiffres. */
    public const MAX_TENTATIVES = Login::MAX_TENTATIVES;

    public const DUREE_BLOCAGE = Login::DUREE_BLOCAGE;

    public const CLE_ETAT = 'session_locked';

    public const CLE_ECHECS = 'session_lock_failures';

    public const CLE_RETOUR = 'url.apres_deverrouillage';

    private const CLE_RAPPEL = 'session_lock_rappel';

    /** « Jamais », « 1 minute », « 5 minutes »… — le texte du poste (`ReglageInactivite.libelle`). */
    public static function libelleDuree(int $minutes): string
    {
        return match ($minutes) {
            0 => 'Jamais',
            1 => '1 minute',
            default => $minutes.' minutes',
        };
    }

    public static function dureeValide(mixed $minutes): bool
    {
        return is_int($minutes) && in_array($minutes, self::DUREES, true);
    }

    /** « 15 min 00 s », « 42 s » — la mise en forme du poste (`_formater`). */
    public static function formaterAttente(int $secondes): string
    {
        return $secondes >= 60
            ? intdiv($secondes, 60).' min '.str_pad((string) ($secondes % 60), 2, '0', STR_PAD_LEFT).' s'
            : $secondes.' s';
    }

    public static function cleLimiteur(string $idUtilisateur, ?string $ip): string
    {
        return 'deverrouillage|'.$idUtilisateur.'|'.($ip ?? '');
    }

    public static function estVerrouillee(): bool
    {
        return session(self::CLE_ETAT) === true;
    }

    /** Verrouille la session de l'utilisateur. Idempotent : un second appel ne journalise pas une seconde fois. */
    public function verrouiller(User $utilisateur): void
    {
        if (self::estVerrouillee()) {
            return;
        }

        session([self::CLE_ETAT => true]);

        // Cookie de rappel : retiré du navigateur le temps du verrou (voir l'en-tête de classe).
        $nomRappel = Auth::guard('web')->getRecallerName();
        if (request()->hasCookie($nomRappel)) {
            session([self::CLE_RAPPEL => true]);
            Cookie::queue(Cookie::forget($nomRappel));
        }

        AuditLog::record('session.verrouillee', 'auth', $utilisateur->id);
    }

    /**
     * Tente de déverrouiller.
     *
     * @return array{statut: 'ok'|'refuse'|'temporise'|'deconnecte', secondes?: int}
     */
    public function deverrouiller(User $utilisateur, string $motDePasse): array
    {
        if (! self::estVerrouillee()) {
            return ['statut' => 'ok'];
        }

        $cle = self::cleLimiteur($utilisateur->id, request()->ip());

        // Bloqué : on ne regarde même pas le mot de passe (un bon mot de passe ne contourne pas le blocage).
        if (RateLimiter::tooManyAttempts($cle, self::MAX_TENTATIVES)) {
            return ['statut' => 'temporise', 'secondes' => RateLimiter::availableIn($cle)];
        }

        if (! Hash::check($motDePasse, $utilisateur->password)) {
            RateLimiter::hit($cle, self::DUREE_BLOCAGE);
            $echecs = (int) session(self::CLE_ECHECS, 0) + 1;
            session([self::CLE_ECHECS => $echecs]);

            // ⚠️ Le mot de passe saisi n'est jamais journalisé.
            AuditLog::record('session.deverrouillage_echec', 'auth', $utilisateur->id);

            if ($echecs >= self::ECHECS_MAX) {
                AuditLog::record('session.deconnexion_apres_echecs', 'auth', $utilisateur->id);
                $this->deconnecter();

                return ['statut' => 'deconnecte'];
            }

            if (RateLimiter::tooManyAttempts($cle, self::MAX_TENTATIVES)) {
                return ['statut' => 'temporise', 'secondes' => RateLimiter::availableIn($cle)];
            }

            return ['statut' => 'refuse'];
        }

        RateLimiter::clear($cle);

        if (session(self::CLE_RAPPEL)) {
            // Rétablit le cookie de rappel retiré au verrouillage (le jeton, lui, n'a pas changé).
            Auth::guard('web')->login($utilisateur, true);
        }

        session()->forget([self::CLE_ETAT, self::CLE_ECHECS, self::CLE_RAPPEL]);
        AuditLog::record('session.deverrouillee', 'auth', $utilisateur->id);

        return ['statut' => 'ok'];
    }

    /** Page à rouvrir après le déverrouillage (celle qu'on demandait quand le verrou l'a interceptée). */
    public function retour(): string
    {
        $retour = session()->pull(self::CLE_RETOUR);

        return is_string($retour) && Str::startsWith($retour, url('/')) ? $retour : route('dashboard.index');
    }

    /** Déconnexion complète : même geste que `LogoutController`, sans passer par la requête. */
    private function deconnecter(): void
    {
        Auth::guard('web')->logout();
        session()->invalidate();
        session()->regenerateToken();
    }
}
