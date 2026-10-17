<?php

namespace App\Livewire\Shared;

use App\Models\Notification;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;

/**
 * Cloche de notifications du header — composant Livewire imbriqué monté
 * une seule fois dans layouts/app.blade.php (Document 02 §4 : composition
 * par imbrication de composants, jamais par iframe). Remplace, à partir du
 * ticket 1.7, le bloc statique "Aucune notification pour le moment" posé
 * au Sprint 0 en attendant que la table `notifications` existe.
 */
class NotificationBell extends Component
{
    public function getUnreadCountProperty(): int
    {
        return Notification::visibleTo(Auth::user())->where('is_read', false)->count();
    }

    public function getRecentProperty()
    {
        return Notification::visibleTo(Auth::user())
            ->latest('created_at')
            ->limit(4)
            ->get();
    }

    public function markAsRead(string $id): void
    {
        Notification::visibleTo(Auth::user())->findOrFail($id)->update([
            'is_read' => true,
            'read_at' => now(),
        ]);
    }

    public function render()
    {
        return view('livewire.shared.notification-bell');
    }
}
