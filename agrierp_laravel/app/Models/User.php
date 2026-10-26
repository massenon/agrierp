<?php

namespace App\Models;

use App\Services\VerrouSessionService;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use Spatie\Permission\Traits\HasRoles;

/**
 * Remplace app/Models/User.php généré par défaut par `laravel new`.
 * Décision documentée (Sprint 0, ticket 0.1) : `HasUuids` aligne la clé
 * primaire sur le reste du schéma (voir docblock migration users) ;
 * `HasRoles` (Spatie) porte le RBAC à 4 rôles exactement (Document 06 §6.1).
 *
 * `HasApiTokens` (Sanctum) ajouté pour l'API de synchronisation Flutter
 * (`LARAVEL_SYNC_FLUTTER.md`) — jamais construite avant ce ticket. Les
 * rôles/permissions Spatie restent valables identiquement qu'un
 * utilisateur soit authentifié via session web ou token Sanctum : le
 * `guard_name` des rôles reste `web`, indépendant du garde
 * d'authentification de la requête.
 */
class User extends Authenticatable
{
    use HasApiTokens;
    use HasFactory;
    use HasRoles;
    use HasUuids;
    use Notifiable;

    protected $guard_name = 'web';

    protected $fillable = [
        'name',
        // Ticket 14.50 — identifiant court de connexion (« admin », « compta »).
        // L'e-mail reste, il porte la reinitialisation de mot de passe.
        'username',
        'email',
        'password',
        'is_active',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_active' => 'boolean',
            'verrouillage_minutes' => 'integer',
        ];
    }

    /**
     * Sprint VW — durée d'inactivité (minutes) avant le verrouillage automatique de la session web ; 0 = « Jamais ».
     * Une valeur inconnue en base retombe sur le défaut (5 min) : mieux vaut verrouiller que ne jamais verrouiller
     * par accident. Hors `$fillable` : seul Mon Profil l'écrit, après validation.
     */
    public function delaiVerrouillage(): int
    {
        $minutes = $this->verrouillage_minutes;

        return VerrouSessionService::dureeValide($minutes) ? $minutes : VerrouSessionService::DUREE_PAR_DEFAUT;
    }

    /**
     * Libellés métier des 4 rôles (Document 08 §6) — un seul point de
     * vérité, réutilisé par Mon Profil et, plus tard, l'écran Gestion des
     * Utilisateurs (Sprint 11).
     */
    private const ROLE_LABELS = [
        'admin' => 'Administrateur Principal',
        'comptable' => 'Comptable',
        'caissier' => 'Caissière POS',
        'animalier' => "Chef d'Élevage",
    ];

    public function getRoleLabelAttribute(): ?string
    {
        $role = $this->roles->first()?->name;

        return $role ? (self::ROLE_LABELS[$role] ?? $role) : null;
    }

    public function getInitialsAttribute(): string
    {
        $words = preg_split('/\s+/', trim($this->name));
        $initials = collect($words)->map(fn ($w) => mb_strtoupper(mb_substr($w, 0, 1)))->take(2)->implode('');

        return $initials ?: '?';
    }
}
