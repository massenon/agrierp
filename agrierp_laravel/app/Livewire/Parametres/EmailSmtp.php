<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Mail;
use Livewire\Component;

/**
 * Ticket CFG-1 (décision client du 19/10/2026, D-CFG-1) — onglet « Email (SMTP) » du hub Paramètres.
 *
 * 🔴 Avant : la configuration SMTP se saisissait à DEUX endroits — « Données de l'Entreprise » (bloc « Configuration
 * Email (SMTP) ») et `/parametres-integrations` — avec deux jeux de valeurs pour la sécurité (`TLS` / `tls`) et deux
 * e-mails de test différents. Une seule saisie désormais, ici ; les deux écrans renvoient vers cet onglet.
 *
 * ⚠️⚠️ LE MOT DE PASSE EST CHIFFRÉ EN BASE (`smtp_password_encrypted`, cast `encrypted`) ET JAMAIS RÉAFFICHÉ. Le
 * champ reste vide : vide à l'enregistrement = mot de passe INCHANGÉ ; l'écran dit seulement s'il en existe un.
 * L'effacer est un geste explicite (« Effacer le mot de passe », avec confirmation), jamais l'effet d'un champ vide.
 * Il ne descend jamais aux postes (ticket 14.84) : chaque poste a son propre réglage, au coffre du système (CFG-2).
 *
 * Droits : ceux de l'écran Intégrations qu'il remplace pour le SMTP — réservé à qui gère les paramètres
 * (`manage-parametres`, l'administrateur au seeder), à l'ouverture comme à chaque écriture.
 */
class EmailSmtp extends Component
{
    /** Valeurs de `smtp_security` : celles de l'ancien écran Intégrations (le transport les attend en minuscules). */
    public const SECURITES = ['tls' => 'TLS', 'ssl' => 'SSL', '' => 'Aucune'];

    public string $smtpHost = '';

    public ?int $smtpPort = 587;

    public string $smtpSecurity = 'tls';

    public string $smtpUser = '';

    /** ⚠️ Jamais rempli depuis la base : sert seulement à SAISIR un nouveau mot de passe. */
    public string $smtpPassword = '';

    public string $fromAddress = '';

    public string $testEmailTo = '';

    public function mount(): void
    {
        abort_unless(Gate::allows('manage-parametres'), 403);

        $settings = CompanySetting::current();
        $this->smtpHost = (string) $settings->smtp_host;
        $this->smtpPort = $settings->smtp_port ?? 587;
        // « TLS » / « SSL » majuscules : valeurs écrites par l'ancien bloc de Données de l'Entreprise.
        $securite = strtolower((string) $settings->smtp_security);
        $this->smtpSecurity = array_key_exists($securite, self::SECURITES) ? $securite : 'tls';
        $this->smtpUser = (string) $settings->smtp_user;
        $this->fromAddress = (string) $settings->smtp_from_address;
        $this->testEmailTo = (string) ($settings->adresseExpedition() ?? '');
    }

    /** L'écran dit qu'un mot de passe est enregistré, sans jamais le montrer. */
    public function getMotDePasseEnregistreProperty(): bool
    {
        return filled(CompanySetting::current()->smtp_password_encrypted);
    }

    public function getContactEmailProperty(): ?string
    {
        return CompanySetting::current()->email ?: null;
    }

    public function save(): void
    {
        $this->authorize('manage-parametres');

        $this->validate([
            'smtpHost' => ['required', 'string', 'max:150'],
            'smtpPort' => ['required', 'integer', 'min:1', 'max:65535'],
            'smtpSecurity' => ['nullable', 'in:tls,ssl'],
            'smtpUser' => ['nullable', 'string', 'max:150'],
            'smtpPassword' => ['nullable', 'string', 'max:255'],
            'fromAddress' => ['nullable', 'email', 'max:150'],
        ], [], [
            'smtpHost' => 'hôte SMTP',
            'smtpPort' => 'port',
            'smtpSecurity' => 'sécurité',
            'smtpUser' => 'utilisateur SMTP',
            'smtpPassword' => 'mot de passe SMTP',
            'fromAddress' => "adresse d'expédition",
        ]);

        $payload = [
            'smtp_host' => trim($this->smtpHost),
            'smtp_port' => $this->smtpPort,
            'smtp_security' => $this->smtpSecurity ?: null,
            'smtp_user' => trim($this->smtpUser) ?: null,
            'smtp_from_address' => trim($this->fromAddress) ?: null,
        ];

        // ⚠️⚠️ CHAMP VIDE = MOT DE PASSE INCHANGÉ. Le formulaire ne le réaffiche jamais : l'écraser par une chaîne vide
        // à chaque enregistrement couperait l'envoi de tous les e-mails de la ferme sans que rien ne le dise.
        if ($this->smtpPassword !== '') {
            $payload['smtp_password_encrypted'] = $this->smtpPassword;
        }

        CompanySetting::current()->update($payload);
        $this->smtpPassword = '';

        AuditLog::record('company_settings.smtp_updated', 'parametres');
        $this->dispatch('toast', message: 'Configuration SMTP enregistrée avec succès.', type: 'success');
    }

    /** Effacement EXPLICITE du mot de passe enregistré (confirmé dans une modale). */
    public function effacerMotDePasse(): void
    {
        $this->authorize('manage-parametres');

        CompanySetting::current()->update(['smtp_password_encrypted' => null]);
        $this->smtpPassword = '';

        AuditLog::record('company_settings.smtp_password_cleared', 'parametres');
        $this->dispatch('toast', message: 'Mot de passe SMTP effacé.', type: 'success');
    }

    /**
     * « Envoyer un e-mail de test » — RÉEL : la configuration ENREGISTRÉE est appliquée (`applyMailConfig()`) puis un
     * e-mail part effectivement ; jamais une simulation de succès. Une saisie non enregistrée n'est pas testée.
     */
    public function sendTestEmail(): void
    {
        $this->authorize('manage-parametres');

        $this->validate(['testEmailTo' => ['required', 'email']], [], ['testEmailTo' => 'destinataire du test']);

        $settings = CompanySetting::current();

        if (! $settings->smtp_host) {
            $this->dispatch('toast', message: "Enregistrez d'abord l'hôte SMTP avant d'envoyer un e-mail de test.", type: 'error');

            return;
        }

        $settings->applyMailConfig();

        try {
            Mail::raw(
                'Ceci est un e-mail de test envoyé depuis LogiAgriERP (Paramètres > Email (SMTP)) — configuration SMTP validée avec succès.',
                fn ($message) => $message->to($this->testEmailTo)->subject('LogiAgriERP — Test de configuration SMTP')
            );

            AuditLog::record('company_settings.smtp_tested', 'parametres');
            $this->dispatch('toast', message: "E-mail de test envoyé à {$this->testEmailTo}.", type: 'success');
        } catch (\Throwable $e) {
            $this->dispatch('toast', message: "Échec de l'envoi — vérifiez la configuration SMTP ({$e->getMessage()}).", type: 'error');
        }
    }

    public function render()
    {
        return view('livewire.parametres.email-smtp');
    }
}
