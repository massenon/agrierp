<?php

namespace App\Livewire\Profil;

use App\Models\AuditLog;
use App\Services\VerrouSessionService;
use App\Support\PolitiqueMotDePasse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 1.4 (Sprint 1) — mon-profil.html → Livewire\Profil\MonProfil
 *
 * ÉCARTS DOCUMENTÉS :
 * ⚠️ TICKET 15.9 — LA RÈGLE DE L'ÉCART N° 1 CI-DESSOUS EST ABROGÉE : le
 *    commanditaire a tranché pour 8 caractères, 1 majuscule, 1 chiffre
 *    (`PolitiqueMotDePasse`), comme le prototype.
 *
 * 1. Règle de complexité du mot de passe : le placeholder du prototype
 *    suggère "Min. 8 caractères, 1 majuscule, 1 chiffre", mais Document 06
 *    §12 fixe explicitement la politique réelle : "8 caractères, pas de
 *    règle de complexité excessive... privilégier la longueur." Implémenté
 *    ici selon Document 06 (min:8 uniquement) — le document de règles
 *    l'emporte sur un texte d'aide non normatif du prototype.
 * 2. Champ "Ancien mot de passe" validé avec la règle Laravel native
 *    `current_password` (vérifie le hash réel en base) — le prototype
 *    n'avait aucun moyen de le faire (pas de backend).
 * 3. "Dernière connexion" / "Adresse IP" : dérivées de la dernière entrée
 *    `audit_logs` de type 'login' pour l'utilisateur courant (un seul
 *    point de vérité, plutôt qu'une colonne `last_login_at` dupliquée sur
 *    `users` — cf. AVOID_INSTRUCTIONS.md § Difficult Debugging).
 * 4. Journal d'Audit : les 10 dernières entrées RÉELLES de `audit_logs`
 *    pour l'utilisateur courant uniquement (Document 06 §6.3 : "un
 *    utilisateur non-admin ne voit, le cas échéant, que son propre
 *    historique (Mon Profil)"). Contient déjà de vraies données dès cette
 *    session (connexion, déconnexion) — pas un bandeau d'attente.
 */
#[Layout('layouts.app')]
class MonProfil extends Component
{
    public string $current_password = '';

    public string $new_password = '';

    public string $new_password_confirmation = '';

    /**
     * Sprint VW — durée d'inactivité avant le verrouillage automatique de la session web (minutes ; 0 = « Jamais »).
     * Réglage PROPRE À L'UTILISATEUR, tenu sur le serveur (`users.verrouillage_minutes`) : il suit la personne d'un
     * navigateur à l'autre. Mêmes choix et même défaut (5 min) que le poste.
     */
    public int $verrouillage_minutes = VerrouSessionService::DUREE_PAR_DEFAUT;

    public function mount(): void
    {
        $this->verrouillage_minutes = Auth::user()->delaiVerrouillage();
    }

    /** Enregistre le choix dès qu'il change (liste déroulante `wire:model.live`) ; une valeur hors liste est refusée. */
    public function updatedVerrouillageMinutes(): void
    {
        $this->validate([
            'verrouillage_minutes' => ['required', 'integer', Rule::in(VerrouSessionService::DUREES)],
        ], [
            'verrouillage_minutes.*' => 'Choisissez une durée dans la liste.',
        ]);

        Auth::user()->forceFill(['verrouillage_minutes' => $this->verrouillage_minutes])->save();

        // Le navigateur applique la nouvelle durée aussitôt (minuterie de `components/verrou-session`).
        $this->dispatch('verrou-delai-modifie', minutes: $this->verrouillage_minutes);
        $this->dispatch('toast', message: 'Verrouillage automatique : '.VerrouSessionService::libelleDuree($this->verrouillage_minutes).'.', type: 'success');
    }

    public function getLastLoginProperty(): ?AuditLog
    {
        return AuditLog::where('user_id', Auth::id())
            ->where('action', 'login')
            ->latest('created_at')
            ->first();
    }

    public function getRecentActionsProperty()
    {
        return AuditLog::where('user_id', Auth::id())
            ->latest('created_at')
            ->limit(10)
            ->get();
    }

    public function updatePassword(): void
    {
        $this->validate([
            'current_password' => ['required', 'current_password'],
            'new_password' => [...PolitiqueMotDePasse::regles(), 'confirmed'],
        ], [
            'current_password.current_password' => "L'ancien mot de passe ne correspond pas à votre mot de passe actuel.",
            ...PolitiqueMotDePasse::messages(),
            'new_password.confirmed' => 'La confirmation ne correspond pas au mot de passe saisi.',
        ]);

        Auth::user()->forceFill([
            'password' => Hash::make($this->new_password),
        ])->save();

        AuditLog::record('password.updated', 'auth');

        $this->reset(['current_password', 'new_password', 'new_password_confirmation']);

        $this->dispatch('toast', message: 'Mot de passe mis à jour avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.profil.mon-profil', ['title' => 'Mon Profil']);
    }
}
