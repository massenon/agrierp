<?php

namespace App\Livewire\Parametres;

use App\Services\ViderSessionsService;
use App\Models\AuditLog;
use App\Models\Role;
use App\Models\User;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Suite du Sprint 11 — gestion-utilisateurs.html → Livewire\Parametres\GestionUtilisateurs
 * "Administration des comptes d'accès à AgriERP."
 *
 * CRUD réel sur `User` — `is_active` (archivage) et
 * `getRoleLabelAttribute()` existaient déjà, explicitement anticipés
 * pour cet écran (docblock `User`, "Sprint 11") : réutilisés tels quels,
 * jamais une seconde logique de libellé de rôle inventée ici.
 *
 * Liste de rôles réelle et dynamique (`Role::pluck('name')`) — cohérente
 * avec la révision du ticket Rôles & Permissions qui a rendu la création
 * de rôle réelle : un rôle nouvellement créé apparaît ici automatiquement,
 * jamais une liste de rôles codée en dur qui se déconnecterait de la
 * vraie table `roles`.
 *
 * Mot de passe réel ajouté au formulaire de création (absent du
 * prototype, qui ne montre aucun champ mot de passe malgré un vrai
 * compte à créer) — nécessaire pour qu'un compte créé ici soit
 * réellement utilisable pour se connecter. Réinitialisation optionnelle
 * à l'édition (laisser vide pour conserver le mot de passe actuel).
 *
 * ⚠️ Un administrateur ne peut pas s'archiver lui-même — évite de se
 * retrouver déconnecté de son propre compte sans personne pour le
 * réactiver.
 *
 * 🔴→✅ EXTENSION DU PATTERN RBAC CRUD AU NIVEAU ACTION (référence
 * initiale : `PlanComptable`) — `$this->authorize('manage-users')` sur
 * les 5 méthodes mutantes. L'écran le plus sensible du projet (création
 * de comptes, attribution de rôles) : bien que la route soit déjà
 * réservée à `admin` seul aujourd'hui (`view-parametres`), un futur rôle
 * personnalisé avec `view-parametres` sans `manage-users` (ex. un
 * "Auditeur Système" en lecture seule) doit être bloqué au niveau action
 * également, pas seulement supposé bloqué par la route actuelle.
 */
class GestionUtilisateurs extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $statusFilter = '';

    public ?string $editingUserId = null;

    public string $name = '';

    /**
     * Ticket 14.50 — identifiant de connexion court. Sans ce champ, tout
     * utilisateur cree depuis cet ecran naitrait SANS identifiant et ne
     * pourrait se connecter que par son adresse : la fonctionnalite serait
     * livree a moitie des le premier compte cree.
     */
    public string $username = '';

    public string $email = '';

    public string $role = '';

    public string $password = '';

    public function getKpisProperty(): array
    {
        return [
            'utilisateurs_actifs' => User::where('is_active', true)->count(),
            'roles_definis' => Role::count(),
        ];
    }

    public function getRolesListProperty()
    {
        return Role::orderBy('name')->get();
    }

    public function getUsersProperty()
    {
        return User::with('roles')
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('name', 'like', '%'.$this->search.'%')->orWhere('email', 'like', '%'.$this->search.'%')->orWhere('username', 'like', '%'.$this->search.'%')))
            ->when($this->statusFilter === 'Actif', fn ($q) => $q->where('is_active', true))
            ->when($this->statusFilter === 'Désactivé', fn ($q) => $q->where('is_active', false))
            ->orderBy('name')
            ->get();
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR VÉRIFICATION NIVEAU 2 : bouton "Exporter
     * PDF" totalement absent — même schéma déjà trouvé sur de nombreux
     * écrans de ce projet.
     */
    public function exportUtilisateursPdf()
    {
        $this->authorize('manage-users');

        $users = $this->users;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.gestion-utilisateurs',
            ['users' => $users],
            'Gestion des Utilisateurs',
            'État au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'utilisateurs-'.now()->format('Y-m-d').'.pdf');
    }

    public function newUser(): void
    {
        $this->authorize('manage-users');

        $this->reset(['editingUserId', 'name', 'username', 'email', 'role', 'password']);
        $this->dispatch('open-modal', name: 'modal-create-gestion-utilisateurs');
    }

    public function editUser(string $id): void
    {
        $this->authorize('manage-users');

        $user = User::with('roles')->findOrFail($id);
        $this->editingUserId = $user->id;
        $this->name = $user->name;
        $this->username = (string) $user->username;
        $this->email = $user->email;
        $this->role = $user->roles->first()?->name ?? '';
        $this->password = '';
        $this->dispatch('open-modal', name: 'modal-create-gestion-utilisateurs');
    }

    /** Ticket UT-1 — les règles et les effets vivent dans `SaisieUtilisateurAction`, partagée avec l'envoi des postes. */
    public function saveUser(): void
    {
        $this->authorize('manage-users');

        $this->validate(\App\Actions\SaisieUtilisateurAction::regles($this->editingUserId, $this->editingUserId === null));

        $donnees = [
            'name' => $this->name, 'username' => $this->username, 'email' => $this->email,
            'role' => $this->role, 'password' => $this->password,
        ];
        $saisie = app(\App\Actions\SaisieUtilisateurAction::class);
        if ($this->editingUserId) {
            $saisie->modifier($this->editingUserId, $donnees);
            $message = 'Utilisateur modifié avec succès.';
        } else {
            $saisie->creer($donnees);
            $message = 'Utilisateur créé avec succès.';
        }

        $this->dispatch('close-modal', name: 'modal-create-gestion-utilisateurs');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    public function archiveUser(string $id): void
    {
        $this->authorize('manage-users');

        try {
            app(\App\Actions\SaisieUtilisateurAction::class)->archiver($id, Auth::id());
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->dispatch('toast', message: $e->validator->errors()->first(), type: 'error');

            return;
        }
        $this->dispatch('toast', message: 'Utilisateur archivé avec succès.', type: 'warning');
    }

    public function reactivateUser(string $id): void
    {
        $this->authorize('manage-users');

        app(\App\Actions\SaisieUtilisateurAction::class)->reactiver($id);
        $this->dispatch('toast', message: 'Utilisateur réactivé avec succès.', type: 'success');
    }

    /**
     * Ticket 15.54 — déconnecte tout le monde (sessions web, jetons des postes), sauf la session en cours.
     * Journalisé ; le nombre réel est annoncé.
     */
    public function viderSessions(): void
    {
        $this->authorize('manage-users');

        $resultat = app(ViderSessionsService::class)->vider(session()->getId());
        AuditLog::record('sessions.videes', 'administration');

        $this->dispatch('close-modal', name: 'modal-vider-sessions');
        $this->dispatch('toast', type: 'success', message: "{$resultat['sessions']} session(s) web fermée(s), "
            ."{$resultat['jetons']} poste(s) déconnecté(s). Votre session est conservée.");
    }

    public function render()
    {
        return view('livewire.parametres.gestion-utilisateurs');
    }
}
