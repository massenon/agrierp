<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * Ticket 4.7 (Sprint 4) — relances-clients.html, canal Email.
 * Même infrastructure Mail réelle que `ContactEditorMail` (ticket 1.6) —
 * `MAIL_MAILER=log` en développement, envoi réel dès qu'un transport SMTP
 * est configuré en production.
 */
class CustomerReminderMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $customerName,
        public string $messageBody,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: 'Ferme École OLOUWACHEGOUN — Rappel de règlement',
        );
    }

    public function content(): Content
    {
        return new Content(view: 'emails.customer-reminder');
    }
}
