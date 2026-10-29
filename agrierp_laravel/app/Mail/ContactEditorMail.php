<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * Ticket 1.6 (Sprint 1) — contact-editeur.html → formulaire simple
 *
 * DÉCISION DOCUMENTÉE : aucune table `contact_messages`/`bug_reports`
 * n'existe dans le schéma documenté (26 tables, `FULL_MIGRATIONS_DATABASE.md`)
 * — un formulaire "Contactez l'Éditeur" est par nature un envoi ponctuel,
 * pas une donnée d'exploitation à conserver dans AgriERP. Implémenté par
 * envoi d'e-mail réel (`Mail::send`) vers l'éditeur (FAGUEZ SARL), plutôt
 * que par une table dédiée — aucun changement de schéma nécessaire.
 * `MAIL_MAILER=log` en développement (`.env.example`, Sprint 0) : les
 * e-mails sont écrits dans `storage/logs/laravel.log` plutôt qu'envoyés
 * réellement tant qu'un vrai transport SMTP n'est pas configuré en
 * production — comportement standard Laravel, pas une fonctionnalité
 * simulée.
 */
class ContactEditorMail extends Mailable
{
    use Queueable, SerializesModels;

    /**
     * @param  array{type: string, subject?: string, message?: string, module?: string, description?: string, steps?: string}  $payload
     */
    public function __construct(
        public string $senderName,
        public string $senderEmail,
        public array $payload,
        public ?string $attachmentPath = null,
        public ?string $attachmentName = null,
    ) {}

    public function envelope(): Envelope
    {
        $subject = $this->payload['type'] === 'bug'
            ? 'LogiAgriERP — Signalement de bug : '.($this->payload['module'] ?? 'Non précisé')
            : 'LogiAgriERP — Message : '.($this->payload['subject'] ?? 'Sans objet');

        return new Envelope(
            subject: $subject,
            replyTo: [$this->senderEmail => $this->senderName],
        );
    }

    public function content(): Content
    {
        return new Content(view: 'emails.contact-editor');
    }

    public function attachments(): array
    {
        if (! $this->attachmentPath) {
            return [];
        }

        return [
            \Illuminate\Mail\Mailables\Attachment::fromPath($this->attachmentPath)
                ->as($this->attachmentName ?? 'capture-ecran.png'),
        ];
    }
}
