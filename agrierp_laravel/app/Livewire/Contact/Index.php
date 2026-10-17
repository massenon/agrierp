<?php

namespace App\Livewire\Contact;

use App\Mail\ContactEditorMail;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use Illuminate\Support\Facades\Mail;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Livewire\WithFileUploads;

/**
 * Ticket 1.6 (Sprint 1) — contact-editeur.html → formulaire simple
 * Voir docblock de `App\Mail\ContactEditorMail` pour la décision
 * d'architecture (envoi e-mail réel, pas de table dédiée).
 *
 * Écart documenté : la capture d'écran ("optionnel", zone glisser-déposer
 * dans le prototype) est un simple bloc visuel statique dans le HTML
 * source (aucun `<input type="file">`, aucun handler JS). Implémentée ici
 * comme un véritable upload Livewire (`WithFileUploads`), joint à l'e-mail
 * envoyé — la zone visuelle est conservée à l'identique, son comportement
 * est complété pour ne pas laisser un bouton qui n'agit sur rien (Document
 * 00 §2.2, zéro fonctionnalité inachevée).
 */
#[Layout('layouts.app')]
class Index extends Component
{
    use WithFileUploads;

    public string $activeTab = 'message';

    // Onglet "Envoyer un Message"
    public string $subject = '';

    public string $message = '';

    // Onglet "Signaler un Bug"
    public string $module = '';

    public string $description = '';

    public string $steps = '';

    public $screenshot = null;

    public array $moduleOptions = [
        'Élevage & Soins',
        'Ventes & POS',
        'Stocks',
        'Comptabilité',
        'Ressources Humaines',
        'Autre',
    ];

    public function sendMessage(): void
    {
        $this->validate([
            'subject' => ['required', 'string', 'max:150'],
            'message' => ['required', 'string', 'max:5000'],
        ], [
            'subject.required' => 'Ce champ est obligatoire.',
            'message.required' => 'Ce champ est obligatoire.',
        ]);

        CompanySetting::current()->applyMailConfig();

        Mail::to(config('mail.support_address', 'contact@massenonrhodes.com'))
            ->send(new ContactEditorMail(
                senderName: auth()->user()->name,
                senderEmail: auth()->user()->email,
                payload: ['type' => 'message', 'subject' => $this->subject, 'message' => $this->message],
            ));

        AuditLog::record('contact.message_sent', 'auth');

        $this->reset(['subject', 'message']);
        $this->dispatch('toast', message: 'Message envoyé avec succès.', type: 'success');
    }

    public function reportBug(): void
    {
        $this->validate([
            'module' => ['required', 'string'],
            'description' => ['required', 'string', 'max:5000'],
            'steps' => ['nullable', 'string', 'max:5000'],
            'screenshot' => ['nullable', 'image', 'max:4096'],
        ], [
            'module.required' => 'Ce champ est obligatoire.',
            'description.required' => 'Ce champ est obligatoire.',
            'screenshot.image' => 'Le fichier joint doit être une image.',
            'screenshot.max' => "L'image ne doit pas dépasser 4 Mo.",
        ]);

        $attachmentPath = $this->screenshot?->getRealPath();
        $attachmentName = $this->screenshot?->getClientOriginalName();

        CompanySetting::current()->applyMailConfig();

        Mail::to(config('mail.support_address', 'contact@massenonrhodes.com'))
            ->send(new ContactEditorMail(
                senderName: auth()->user()->name,
                senderEmail: auth()->user()->email,
                payload: [
                    'type' => 'bug',
                    'module' => $this->module,
                    'description' => $this->description,
                    'steps' => $this->steps,
                ],
                attachmentPath: $attachmentPath,
                attachmentName: $attachmentName,
            ));

        AuditLog::record('contact.bug_reported', 'auth');

        $this->reset(['module', 'description', 'steps', 'screenshot']);
        $this->dispatch('toast', message: 'Signalement envoyé — merci pour votre retour.', type: 'success');
    }

    public function render()
    {
        return view('livewire.contact.index', ['title' => "Contactez l'Éditeur"]);
    }
}
