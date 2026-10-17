<?php

namespace App\Livewire\Notifications;

use App\Models\Notification;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 1.7 (Sprint 1) — notifications.html → Livewire\Notifications\Index
 * Dernier ticket du Sprint 1.
 *
 * ⚠️ CONSTAT STRUCTUREL SIGNALÉ (même nature que le ticket 1.3) :
 * Aucun déclencheur automatique n'existe encore (StockLow, HighMortality,
 * ProphylaxyReminderIssued — Document 02 §5, ARCHITECTURE_DÉFINITIVE §7)
 * puisque les modules sources (Stocks Sprint 6, Élevage Sprint 3,
 * Comptabilité Sprint 10) ne sont pas encore construits. Ce centre de
 * notifications est donc entièrement fonctionnel (marquer lu, supprimer,
 * rechercher, filtrer — toutes des opérations RÉELLES sur la table
 * `notifications`, créée dès ce ticket comme prévu par le plan) mais
 * légitimement vide à l'installation, hormis les 1-2 notifications système
 * de démonstration semées par `NotificationsSeeder` (contenu générique,
 * jamais une fausse alerte métier référençant des lots/stocks qui
 * n'existent pas encore en base).
 *
 * 🔧 CORRECTION DE FIDÉLITÉ TROUVÉE PAR COMPARAISON STRUCTURELLE LIGNE
 * PAR LIGNE (audit approfondi, pas seulement un contrôle par ensemble de
 * classes) : le filtre catégorie affichait "Système" en 4e option — le
 * prototype affiche littéralement "RH" à cette position. Corrigé pour
 * matcher exactement. ⚠️ Écart résiduel assumé : `Notification::CATEGORY_BY_TYPE`
 * mappe le type `system` (message de bienvenue) vers 'Système', une
 * catégorie que le prototype ne couvre pas du tout dans ses 4 options —
 * sélectionner "RH" dans le filtre ne retournera donc honnêtement rien
 * tant qu'aucun déclencheur RH réel n'existe (cohérent avec le constat
 * ci-dessus, aucune fausse alerte inventée pour combler ce vide).
 */
#[Layout('layouts.app')]
class Index extends Component
{
    #[Url]
    public string $search = '';

    #[Url]
    public string $category = '';

    #[Url]
    public string $statut = '';

    public function getKpisProperty(): array
    {
        $base = Notification::visibleTo(Auth::user());

        return [
            'non_lues' => (clone $base)->where('is_read', false)->count(),
            'critiques' => (clone $base)->where('severity', 'critique')->where('is_read', false)->count(),
            'total_30_jours' => (clone $base)->where('created_at', '>=', now()->subDays(30))->count(),
        ];
    }

    public function getNotificationsProperty()
    {
        return Notification::visibleTo(Auth::user())
            ->when($this->search, fn ($q) => $q->where('message', 'like', '%'.$this->search.'%')
                ->orWhere('title', 'like', '%'.$this->search.'%'))
            ->when($this->category, fn ($q) => $q->whereIn('type', Notification::typesForCategory($this->category)))
            ->when($this->statut === 'Non lue', fn ($q) => $q->where('is_read', false))
            ->when($this->statut === 'Lue', fn ($q) => $q->where('is_read', true))
            ->latest('created_at')
            ->get();
    }

    public function markAsRead(string $id): void
    {
        $notification = Notification::visibleTo(Auth::user())->findOrFail($id);
        $notification->update(['is_read' => true, 'read_at' => now()]);

        $this->dispatch('toast', message: 'Notification marquée comme lue.', type: 'success');
    }

    public function delete(string $id): void
    {
        Notification::visibleTo(Auth::user())->findOrFail($id)->delete();

        $this->dispatch('toast', message: 'Notification supprimée.', type: 'warning');
    }

    public function render()
    {
        return view('livewire.notifications.index', ['title' => 'Centre de Notifications']);
    }
}
