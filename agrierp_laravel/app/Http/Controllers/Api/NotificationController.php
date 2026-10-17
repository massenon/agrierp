<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Ticket 15.10 — ACTIONS SUR LES NOTIFICATIONS DEPUIS UN POSTE.
 *
 * Le tirage (`/api/sync/pull`) fait DESCENDRE les notifications ; ces deux
 * routes laissent le poste les marquer lues ou les supprimer, comme le fait
 * `Livewire\Notifications\Index`.
 *
 * ⚠️ MÊME PORTÉE QUE LA SURFACE WEB : `visibleTo`. Une notification adressée à
 * quelqu'un d'autre répond 404, jamais 403 — l'existence d'un identifiant que
 * l'on ne peut pas voir ne doit pas se déduire de la réponse.
 */
class NotificationController extends Controller
{
    public function markAsRead(Request $request, string $id): JsonResponse
    {
        $notification = Notification::visibleTo($request->user())->findOrFail($id);

        $notification->update(['is_read' => true, 'read_at' => now()]);

        return response()->json(['message' => 'Notification marquée comme lue.']);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        Notification::visibleTo($request->user())->findOrFail($id)->delete();

        return response()->json(['message' => 'Notification supprimée.']);
    }
}
