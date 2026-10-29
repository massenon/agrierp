<?php

namespace App\Services;

use App\Livewire\Auth\Login;
use App\Models\AuditLog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;

/**
 * Ticket MDP-1 — CODE DE SECOURS DE L'ADMINISTRATEUR : POINT DE PASSAGE UNIQUE (génération, vérification, consommation,
 * limiteur d'essais).
 *
 * Le dernier administrateur qui oublie son mot de passe ne peut pas être réinitialisé par un autre (il n'y en a plus) ni
 * par e-mail (supprimé). Il reste le serveur : `php artisan agrierp:reinitialiser-admin <identifiant>`, qui demande ce code.
 *
 *  - un seul code ACTIF à la fois (table `recovery_codes`, UUID) ; un nouveau code remplace le précédent ;
 *  - 24 caractères tirés de 31 symboles lisibles (ni 0/O ni 1/I/L), groupés par 4 : `ABCD-EFGH-…` (~119 bits) ;
 *  - ⚠️ seule l'EMPREINTE (SHA-256 du code normalisé) est stockée, jamais le code. Pas de bcrypt : l'entropie du code
 *    rend le hachage lent inutile, et SHA-256 ne dépend pas de `APP_KEY` (une restauration sur un autre serveur garde
 *    le code valable) ;
 *  - comparaison en TEMPS CONSTANT (`hash_equals`), y compris quand aucun code n'est actif ;
 *  - usage unique : la consommation est atomique (`UPDATE … WHERE used_at IS NULL`), deux commandes simultanées ne
 *    peuvent pas réussir toutes les deux ;
 *  - limiteur : 5 échecs puis blocage de 15 minutes (les seuils de la connexion web), clé GLOBALE (un attaquant ne
 *    contourne pas le blocage en changeant d'identifiant), journalisé.
 */
class CodeSecoursService
{
    /** 31 symboles : les chiffres 2-9 et les lettres sans I, L, O. */
    public const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

    public const LONGUEUR = 24;

    public const TAILLE_GROUPE = 4;

    public const CLE_LIMITEUR = 'code-secours-admin';

    public const MAX_ECHECS = Login::MAX_TENTATIVES;

    public const DUREE_BLOCAGE = Login::DUREE_BLOCAGE;

    /** Génère un nouveau code, REMPLACE le code actif et rend le code en clair (à afficher UNE seule fois). */
    public function generer(): string
    {
        $brut = '';
        for ($i = 0; $i < self::LONGUEUR; $i++) {
            $brut .= self::ALPHABET[random_int(0, strlen(self::ALPHABET) - 1)];
        }

        DB::transaction(function () use ($brut) {
            DB::table('recovery_codes')->whereNull('used_at')->update(['used_at' => now(), 'used_reason' => 'remplace']);
            DB::table('recovery_codes')->insert([
                'id' => (string) Str::uuid(),
                'empreinte' => $this->empreinte($brut),
                'created_at' => now(),
            ]);
            // ⚠️ L'événement ne contient pas le code.
            AuditLog::record('recovery_code.generated', 'administration');
        });

        return $this->formater($brut);
    }

    public function existeUnCodeActif(): bool
    {
        return DB::table('recovery_codes')->whereNull('used_at')->exists();
    }

    /** Majuscules, sans séparateur ni espace : « abcd-efgh … » et « ABCDEFGH… » désignent le même code. */
    public function normaliser(string $code): string
    {
        return strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $code) ?? '');
    }

    public function empreinte(string $codeNormalise): string
    {
        return hash('sha256', $this->normaliser($codeNormalise));
    }

    public function formater(string $codeNormalise): string
    {
        return implode('-', str_split($this->normaliser($codeNormalise), self::TAILLE_GROUPE));
    }

    /** Vrai si le code saisi est le code ACTIF (temps constant, même quand aucun code n'existe). */
    public function verifier(string $saisi): bool
    {
        $actif = DB::table('recovery_codes')->whereNull('used_at')->latest('created_at')->first();
        $attendue = $actif->empreinte ?? str_repeat('0', 64);

        return hash_equals($attendue, $this->empreinte($saisi)) && $actif !== null;
    }

    /** Consomme le code (usage unique, atomique). Faux si le code n'est pas/plus actif. */
    public function consommer(string $saisi): bool
    {
        $actif = DB::table('recovery_codes')->whereNull('used_at')->latest('created_at')->first();
        if ($actif === null || ! hash_equals($actif->empreinte, $this->empreinte($saisi))) {
            return false;
        }

        return DB::table('recovery_codes')
            ->where('id', $actif->id)->whereNull('used_at')
            ->update(['used_at' => now(), 'used_reason' => 'utilise']) === 1;
    }

    /** Secondes de blocage restantes, ou null si les essais ne sont pas épuisés. */
    public function secondesDeBlocage(): ?int
    {
        return RateLimiter::tooManyAttempts(self::CLE_LIMITEUR, self::MAX_ECHECS)
            ? RateLimiter::availableIn(self::CLE_LIMITEUR)
            : null;
    }

    /** Compte un échec ; vrai si c'est celui qui déclenche le blocage. */
    public function enregistrerEchec(): bool
    {
        RateLimiter::hit(self::CLE_LIMITEUR, self::DUREE_BLOCAGE);

        return RateLimiter::tooManyAttempts(self::CLE_LIMITEUR, self::MAX_ECHECS);
    }

    public function effacerEchecs(): void
    {
        RateLimiter::clear(self::CLE_LIMITEUR);
    }
}
