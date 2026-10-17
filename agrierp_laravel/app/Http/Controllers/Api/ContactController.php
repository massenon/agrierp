<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Mail\ContactEditorMail;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Ticket 15.11 — « CONTACTEZ L'ÉDITEUR » DEPUIS UN POSTE.
 *
 * Même effet que `Livewire\Contact\Index` : un e-mail réel vers l'éditeur
 * (`ContactEditorMail`), journalisé `contact.message_sent` ou
 * `contact.bug_reported`. Aucune table : un envoi ponctuel n'est pas une donnée
 * d'exploitation (décision du ticket 1.6, conservée).
 *
 * ⚠️ L'APPAREIL EST NOMMÉ DANS LE MESSAGE : un signalement de bug venu d'un poste
 * doit dire LEQUEL. C'est le nom du jeton Sanctum, donné par le client à la
 * connexion.
 *
 * ⚠️ UN ÉCHEC DE TRANSPORT EST RENDU, JAMAIS AVALÉ NI JOURNALISÉ COMME ENVOYÉ :
 * 502 avec une phrase, et AUCUNE ligne d'audit « envoyé ». La surface web laisse
 * l'exception remonter ; un poste, lui, doit pouvoir dire à l'utilisateur de
 * garder son texte et de réessayer.
 *
 * ⚠️ PAS DE CAPTURE D'ÉCRAN : le poste n'a pas de sélecteur de fichier. Le champ
 * est absent de l'API plutôt qu'accepté puis ignoré.
 */
class ContactController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $type = $request->validate([
            'type' => ['required', 'in:message,bug'],
        ])['type'];

        $payload = $type === 'bug'
            ? $request->validate([
                'module' => ['required', 'string', 'max:100'],
                'description' => ['required', 'string', 'max:5000'],
                'steps' => ['nullable', 'string', 'max:5000'],
            ], [
                'module.required' => 'Ce champ est obligatoire.',
                'description.required' => 'Ce champ est obligatoire.',
            ])
            : $request->validate([
                'subject' => ['required', 'string', 'max:150'],
                'message' => ['required', 'string', 'max:5000'],
            ], [
                'subject.required' => 'Ce champ est obligatoire.',
                'message.required' => 'Ce champ est obligatoire.',
            ]);

        $user = $request->user();
        $payload['type'] = $type;
        $payload['device'] = $user->currentAccessToken()?->name;

        try {
            CompanySetting::current()->applyMailConfig();

            Mail::to(config('mail.support_address', 'contact@massenonrhodes.com'))
                ->send(new ContactEditorMail(
                    senderName: $user->name,
                    senderEmail: $user->email,
                    payload: $payload,
                ));
        } catch (Throwable $e) {
            Log::error('Contact éditeur : envoi impossible', ['erreur' => $e->getMessage()]);

            return response()->json([
                'message' => "Le serveur n'a pas pu envoyer l'e-mail. Conservez votre texte et réessayez plus tard.",
            ], 502);
        }

        AuditLog::record(
            $type === 'bug' ? 'contact.bug_reported' : 'contact.message_sent',
            'auth',
            $user->id,
        );

        return response()->json([
            'message' => $type === 'bug'
                ? 'Signalement envoyé — merci pour votre retour.'
                : 'Message envoyé avec succès.',
        ]);
    }
}
