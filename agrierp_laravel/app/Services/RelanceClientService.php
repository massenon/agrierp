<?php

namespace App\Services;

use App\Mail\CustomerReminderMail;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\Customer;
use App\Models\CustomerReminder;
use App\Models\Receivable;
use Illuminate\Support\Facades\Mail;
use Illuminate\Validation\ValidationException;

/**
 * Ticket VC-2 — RELANCE D'UN CLIENT : UNE SEULE IMPLÉMENTATION.
 *
 * Elle vivait dans quatre écrans web (`RelancesClients` : WhatsApp, e-mail, appel, courrier ; `SuiviDettes` et
 * `ProfileClient` : relance « rapide »). Le web ET l'envoi des postes (`SyncController::pushCustomerReminders`) passent
 * désormais ici : mêmes canaux, mêmes messages d'erreur, même trace (`customer_reminders` + audit).
 *
 * Qui fait quoi, par canal :
 *  - `whatsapp` : l'APPAREIL ouvre le lien `wa.me` (navigateur du web, système du poste) ; le serveur ne fait que TENIR LA TRACE ;
 *  - `courrier` : l'appareil produit la lettre PDF ; le serveur tient la trace ;
 *  - `email` : le SERVEUR envoie (SMTP de l'entreprise) — un poste hors ligne demande l'envoi, qui part à la synchronisation ;
 *  - `appel` : le numéro est composé depuis l'appareil (lien `tel:`) ; le serveur tient seulement la trace (ticket AUT-3,
 *    qui remplace le SMS).
 *
 * ⚠️ La trace n'est écrite QU'APRÈS un envoi réussi (e-mail) : un envoi refusé ne compte pas comme une relance faite
 * (le client serait sinon considéré comme relancé aujourd'hui sans l'avoir été). Un rejeu du même identifiant ne renvoie
 * RIEN (idempotence par l'UUID de l'appareil).
 */
class RelanceClientService
{
    /** CONF-1 — motif du refus d'une relance e-mail quand aucun envoi réel n'est possible (web et poste : le même). */
    public const MOTIF_SANS_SMTP = "Aucun serveur SMTP n'est configuré : la relance n'a pas été envoyée. Configurez l'e-mail dans Paramètres > Email (SMTP).";

    /** Mailers qui « réussissent » sans rien livrer. */
    private const MAILERS_SANS_LIVRAISON = ['log', 'array'];

    public const CANAUX = ['whatsapp', 'email', 'appel', 'courrier'];

    /**
     * Fait la relance (envoi si le canal l'exige) puis la journalise.
     *
     * @throws ValidationException canal inconnu, destinataire sans coordonnée, envoi refusé (motif en clair)
     */
    public function relancer(
        Customer $client,
        ?Receivable $creance,
        string $canal,
        string $message,
        ?string $date = null,
        ?string $reminderId = null,
        bool $dejaEnvoye = false,
    ): CustomerReminder {
        if (! in_array($canal, self::CANAUX, true)) {
            throw ValidationException::withMessages(['channel' => 'Canal de relance inconnu.']);
        }

        match ($canal) {
            // Ticket AUT-3 — un e-mail déjà parti du poste (son propre SMTP) n'est pas renvoyé : le serveur ne fait que la trace.
            'email' => $dejaEnvoye ? $this->exigerAdresse($client) : $this->envoyerEmail($client, $message),
            // « appel » : le numéro est composé depuis l'appareil (`tel:`) ; le serveur n'envoie rien, il tient la trace.
            'whatsapp', 'appel' => $this->exigerTelephone($client),
            default => null,
        };

        return $this->journaliser($client, $creance, $canal, $message, $date, $reminderId);
    }

    /** Numéro de téléphone exigé pour WhatsApp : même message que le web. */
    public function exigerTelephone(Customer $client): string
    {
        $telephone = preg_replace('/[^0-9]/', '', (string) $client->phone);
        if ($telephone === '') {
            throw ValidationException::withMessages(['customer_id' => "Ce client n'a pas de numéro de téléphone enregistré."]);
        }

        return $telephone;
    }

    public function envoyerEmail(Customer $client, string $message): void
    {
        if (! $client->email) {
            throw ValidationException::withMessages(['customer_id' => "Ce client n'a pas d'adresse email enregistrée."]);
        }

        $reglage = CompanySetting::current();

        // CONF-1 — jamais « envoyée » sans envoi réel : sans hôte SMTP et avec un mailer qui n'écrit que dans un fichier ou en mémoire.
        if (! $this->envoiReelPossible($reglage)) {
            throw ValidationException::withMessages(['channel' => self::MOTIF_SANS_SMTP]);
        }

        $reglage->applyMailConfig();
        Mail::to($client->email)->send(new CustomerReminderMail($client->name, $message));
    }

    /**
     * Un e-mail peut-il PARTIR pour de vrai ? Oui si un hôte SMTP est enregistré (Paramètres > Email (SMTP)) ou si le mailer
     * du serveur (`MAIL_MAILER`) livre réellement ; non si c'est `log` ou `array` (le courrier y « réussit » sans partir).
     */
    public function envoiReelPossible(?CompanySetting $reglage = null): bool
    {
        $reglage ??= CompanySetting::current();

        return (string) $reglage->smtp_host !== '' || ! in_array(config('mail.default'), self::MAILERS_SANS_LIVRAISON, true);
    }

    /** Adresse e-mail exigée : même message que le web. */
    public function exigerAdresse(Customer $client): void
    {
        if (! $client->email) {
            throw ValidationException::withMessages(['customer_id' => "Ce client n'a pas d'adresse email enregistrée."]);
        }
    }

    /** Écrit la ligne `customer_reminders` (UUID du poste conservé) et la trace d'audit du canal. */
    public function journaliser(
        Customer $client,
        ?Receivable $creance,
        string $canal,
        string $message,
        ?string $date = null,
        ?string $reminderId = null,
    ): CustomerReminder {
        $relance = new CustomerReminder();
        if ($reminderId !== null) {
            // ⚠️ `id` n'est pas remplissable : `create(['id' => …])` l'ignorerait en silence (piège 14.78).
            $relance->id = $reminderId;
        }
        $relance->fill([
            'customer_id' => $client->id,
            'receivable_id' => $creance?->id,
            'channel' => $canal,
            'reminder_date' => $date ?? now()->format('Y-m-d'),
            'message' => $message,
        ]);
        $relance->save();

        AuditLog::record('customer_reminder.sent_'.$canal, 'ventes');

        return $relance;
    }
}
