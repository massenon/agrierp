<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Services\SauvegardeService;
use App\Models\Permission;
use App\Models\Role;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Storage;
use Livewire\Component;

/**
 * Ticket 11.1 (Sprint 11) — roles-permissions.html → Livewire\Parametres\RolesPermissions
 * "Matrice de droits d'accès et sauvegardes de la base de données."
 *
 * ⚠️ RÉVISION SUITE À DIRECTIVE EXPLICITE : la version initiale de ce
 * ticket désactivait la création/suppression de rôle par prudence
 * architecturale (RBAC à 4 rôles fixes, règle répétée tout au long du
 * projet). Instruction reçue de suivre le prototype à la lettre : CRUD
 * complet réel des rôles, réservé au rôle `admin` uniquement, avec deux
 * garde-fous explicitement demandés :
 *   1. Le rôle `admin` lui-même ne peut jamais être supprimé (protection
 *      dure, quel que soit le nombre d'utilisateurs qui le portent).
 *   2. Aucun rôle ne peut être supprimé s'il est encore assigné à au
 *      moins un utilisateur — évite d'orpheliner des comptes.
 * Le nombre de rôles n'est donc plus figé à 4 par ce composant — la
 * responsabilité de ne pas en multiplier sans raison revient désormais à
 * l'administrateur qui les crée, pas à une contrainte applicative.
 *
 * Toutes les actions (créer/modifier/supprimer un rôle, modifier ses
 * permissions) sont réservées au rôle `admin` — vérifié côté serveur
 * (`authorizeAdmin()`), jamais seulement par un bouton masqué côté vue.
 *
 * Suppression via modale de confirmation nommant le rôle
 * (`x-modal-confirm-hard-delete` — suppression RÉELLE, distincte de
 * `x-modal-confirm-delete` qui est spécifiquement câblée pour
 * l'archivage/soft-delete utilisé partout ailleurs dans ce projet ; un
 * rôle Spatie n'a pas de colonne `is_active`, sa suppression est
 * nécessairement définitive) — jamais une suppression en un clic sans
 * avertissement.
 *
 * Matrice dérivée des vraies permissions Spatie (`RolesAndPermissionsSeeder`
 * pour les 4 rôles d'origine, plus tout rôle créé depuis cet écran) —
 * "Dashboard" n'a pas de permission dédiée (accessible à tout utilisateur
 * authentifié), affiché coché par cohérence avec ce comportement réel.
 *
 * Sauvegardes : réelles (`GenerateDatabaseBackup`), fichiers listés
 * depuis `storage/app/backups/` — jamais une liste statique inventée.
 */
class RolesPermissions extends Component
{
    public ?string $editingRoleName = null;

    public string $roleName = '';

    /** @var array<string, bool> */
    public array $editingPermissions = [];

    private function modules(): array
    {
        return [
            'Dashboard' => null,
            'Ventes & Devis' => 'view-ventes',
            'Achats & Charges' => 'view-achats',
            'Stocks' => 'view-stocks',
            'Élevage & Soins' => 'view-elevage',
            'RH' => 'view-rh',
            'Comptabilité' => 'view-comptabilite',
            'Administration' => 'view-administration',
            'Paramètres' => 'view-parametres',
        ];
    }

    private function authorizeAdmin(): void
    {
        abort_unless(Auth::user()?->hasRole('admin'), 403, "Seul l'administrateur peut gérer les rôles.");
    }

    public function getIsAdminProperty(): bool
    {
        return (bool) Auth::user()?->hasRole('admin');
    }

    public function getModulesProperty(): array
    {
        return array_keys($this->modules());
    }

    public function getKpisProperty(): array
    {
        return [
            'roles' => Role::count(),
            'utilisateurs' => \App\Models\User::role(Role::pluck('name'))->where('is_active', true)->count(),
            'modules' => count($this->modules()),
            'derniere_sauvegarde' => $this->backupFiles()->first()['date'] ?? 'Aucune',
        ];
    }

    public function getRolesProperty()
    {
        return Role::with('permissions')->orderBy('name')->get()->map(function ($role) {
            $modulesStatus = [];
            foreach ($this->modules() as $label => $permission) {
                $modulesStatus[$label] = $permission === null || $role->hasPermissionTo($permission);
            }

            // ⚠️ Role::withCount('users') échoue — Spatie ne porte pas de
            // relation users() sur son modèle Role (apprentissage déjà
            // documenté dans ce projet). User::role() est la seule voie fiable.
            $usersCount = \App\Models\User::role($role->name)->where('is_active', true)->count();   // compte archivé exclu

            return ['role' => $role, 'modules' => $modulesStatus, 'users_count' => $usersCount];
        });
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT PAR VÉRIFICATION NIVEAU 2 : bouton "Exporter
     * PDF" totalement absent — réutilise `getRolesProperty()`/`getModulesProperty()`
     * déjà réels, un seul point de vérité pour la matrice de droits.
     */
    public function exportRolesPdf()
    {
        $this->authorize('manage-users');

        $rows = $this->roles;
        $modules = $this->modules;

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.roles-permissions',
            ['rows' => $rows, 'modules' => $modules],
            'Rôles & Permissions',
            'Matrice des droits d\'accès — état au '.now()->format('d/m/Y')
        );

        return response()->streamDownload(fn () => print($pdf->output()), 'roles-permissions-'.now()->format('Y-m-d').'.pdf');
    }

    // --- Création ---

    public function newRole(): void
    {
        $this->authorizeAdmin();

        $this->reset(['editingRoleName', 'roleName']);
        $this->editingPermissions = [];
        foreach (Permission::pluck('name') as $permission) {
            $this->editingPermissions[$permission] = false;
        }

        $this->dispatch('open-modal', name: 'modal-edit-role');
    }

    // --- Édition ---

    public function editRole(string $roleName): void
    {
        $this->authorizeAdmin();

        $role = Role::where('name', $roleName)->firstOrFail();
        $this->editingRoleName = $role->name;
        $this->roleName = $role->name;

        $this->editingPermissions = [];
        foreach (Permission::pluck('name') as $permission) {
            $this->editingPermissions[$permission] = $role->hasPermissionTo($permission);
        }

        $this->dispatch('open-modal', name: 'modal-edit-role');
    }

    public function saveRole(): void
    {
        $this->authorizeAdmin();

        $service = app(\App\Services\RoleService::class);

        $this->validate($service->regles($this->editingRoleName), [
            'roleName.regex' => \App\Services\RoleService::MESSAGE_NOM,
        ]);

        $role = $service->enregistrer($this->editingRoleName, $this->roleName, array_keys(array_filter($this->editingPermissions)), Auth::user());
        $message = $this->editingRoleName
            ? "Rôle « {$role->name} » modifié avec succès."
            : "Rôle « {$role->name} » créé avec succès.";

        $this->dispatch('close-modal', name: 'modal-edit-role');
        $this->dispatch('toast', message: $message, type: 'success');
    }

    // --- Suppression ---

    public function deleteRole(string $roleName): void
    {
        $this->authorizeAdmin();

        $motif = app(\App\Services\RoleService::class)->supprimer($roleName, Auth::user());

        if ($motif !== null) {
            $this->dispatch('toast', message: $motif, type: 'error');

            return;
        }

        $roleLabel = $roleName;
        $this->dispatch('toast', message: "Rôle « {$roleLabel} » supprimé avec succès.", type: 'warning');
    }

    // --- Sauvegardes ---

    private function backupFiles()
    {
        Storage::disk('local')->makeDirectory('backups');

        return collect(Storage::disk('local')->files('backups'))
            ->filter(fn ($f) => str_ends_with($f, '.sql'))
            ->map(fn ($f) => [
                'name' => basename($f),
                'date' => \Carbon\Carbon::createFromTimestamp(Storage::disk('local')->lastModified($f))->format('d/m/Y H:i'),
                'size' => $this->formatBytes(Storage::disk('local')->size($f)),
                'path' => $f,
            ])
            ->sortByDesc('name')
            ->values();
    }

    public function getBackupsProperty()
    {
        return $this->backupFiles();
    }

    private function formatBytes(int $bytes): string
    {
        return $bytes >= 1048576 ? round($bytes / 1048576, 1).' Mo' : round($bytes / 1024, 1).' Ko';
    }

    public function generateBackup(): void
    {
        $this->authorizeAdmin();
        Artisan::call('agrierp:backup');
        $output = Artisan::output();

        AuditLog::record('database.backup_generated', 'parametres');

        if (str_contains($output, 'Échec')) {
            $this->dispatch('toast', message: 'Échec de la sauvegarde — mysqldump indisponible sur ce serveur.', type: 'error');
        } else {
            $this->dispatch('toast', message: 'Sauvegarde générée avec succès.', type: 'success');
        }
    }

    /**
     * 🔴→✅ TICKET 14.57 — DEUX DÉFAUTS DE SÉCURITÉ RÉELS CORRIGÉS ICI.
     *
     * ⚠️⚠️ **TRAVERSÉE DE RÉPERTOIRE.** Le chemin arrivait du navigateur et
     * partait tel quel à `Storage::download()`. Une méthode Livewire est
     * appelable avec n'importe quel argument : `../../.env` aurait servi le
     * fichier d'environnement — identifiants de base, clé applicative, mots de
     * passe SMTP. Le nom est désormais vérifié contre la liste RÉELLE des
     * sauvegardes ; hors de ce dossier, rien n'est servi.
     *
     * ⚠️ **AUCUNE AUTORISATION.** Toutes les autres méthodes mutantes de cette
     * classe appellent `authorizeAdmin()` ; celle-ci, qui sert le contenu
     * intégral de la base — salaires compris — ne le faisait pas.
     */
    public function downloadBackup(string $path)
    {
        $this->authorizeAdmin();

        $chemin = app(SauvegardeService::class)->chemin(basename($path));

        if ($chemin === null) {
            $this->dispatch('toast', message: 'Sauvegarde introuvable.', type: 'error');

            return null;
        }

        AuditLog::record('database.backup_downloaded', 'parametres');

        return response()->download($chemin);
    }

    public function render()
    {
        return view('livewire.parametres.roles-permissions');
    }
}
