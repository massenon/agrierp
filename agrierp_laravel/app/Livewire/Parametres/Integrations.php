<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Services\SmsService;
use Illuminate\Support\Facades\Mail;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Paramètres > Intégrations & Notifications — pas un écran du prototype
 * (aucun fichier `parametres-integrations.html` n'existe dans le
 * prototype fourni). Construit suite à une demande explicite : l'envoi
 * d'email doit être piloté par une config SMTP réelle en Paramètres, et
 * l'envoi de SMS par des clés API Twilio/Vonage également modifiables en
 * Paramètres (ticket 4.7).
 *
 * Périmètre volontairement limité à SMTP + SMS. L'écran complet "Données
 * Entreprise" (nom, logo, IFU, RCCM...) reste un ticket séparé
 * (Sprint 11) — seuls les champs déjà nécessaires à ce besoin précis sont
 * exposés ici, pas l'intégralité de `company_settings`.
 *
 * Réservé Admin uniquement (Document 00, `manage-modules`) — les secrets
 * de connexion externe ne doivent pas être visibles/modifiables par un
 * rôle non-administrateur.
 */
#[Layout('layouts.app')]
class Integrations extends Component
{
    public string $smtpHost = '';

    public ?int $smtpPort = 587;

    public string $smtpSecurity = 'tls';

    public string $smtpUser = '';

    public string $smtpPassword = '';

    public string $fromEmail = '';

    public string $smsProvider = '';

    public string $twilioSid = '';

    public string $twilioToken = '';

    public string $twilioFrom = '';

    public string $vonageKey = '';

    public string $vonageSecret = '';

    public string $vonageFrom = '';

    public string $testEmailTo = '';

    public string $testSmsTo = '';

    public function mount(): void
    {
        abort_unless(auth()->user()->hasRole('admin'), 403);

        $settings = CompanySetting::current();
        $this->smtpHost = (string) $settings->smtp_host;
        $this->smtpPort = $settings->smtp_port ?? 587;
        $this->smtpSecurity = (string) ($settings->smtp_security ?: 'tls');
        $this->smtpUser = (string) $settings->smtp_user;
        $this->fromEmail = (string) $settings->email;
        $this->smsProvider = (string) $settings->sms_provider;
        $this->twilioSid = (string) $settings->twilio_account_sid;
        $this->twilioFrom = (string) $settings->twilio_from_number;
        $this->vonageKey = (string) $settings->vonage_api_key;
        $this->vonageFrom = (string) $settings->vonage_from_name;
        // Les secrets déjà enregistrés ne sont jamais réaffichés en clair
        // dans le formulaire — laissés vides ; un champ vide au
        // save() ne les écrase pas (voir saveSmtp/saveSms).
    }

    public function saveSmtp(): void
    {
        $this->authorize('manage-parametres');

        $this->validate([
            'smtpHost' => ['required', 'string', 'max:150'],
            'smtpPort' => ['required', 'integer', 'min:1', 'max:65535'],
            'smtpUser' => ['nullable', 'string', 'max:150'],
            'fromEmail' => ['nullable', 'email'],
        ]);

        $settings = CompanySetting::current();
        $payload = [
            'smtp_host' => $this->smtpHost,
            'smtp_port' => $this->smtpPort,
            'smtp_security' => $this->smtpSecurity,
            'smtp_user' => $this->smtpUser ?: null,
            'email' => $this->fromEmail ?: null,
        ];

        if ($this->smtpPassword) {
            $payload['smtp_password_encrypted'] = $this->smtpPassword;
        }

        $settings->update($payload);
        $this->smtpPassword = '';

        AuditLog::record('company_settings.smtp_updated', 'parametres');
        $this->dispatch('toast', message: 'Configuration SMTP enregistrée avec succès.', type: 'success');
    }

    public function saveSms(): void
    {
        $this->authorize('manage-parametres');

        $this->validate([
            'smsProvider' => ['required', 'in:twilio,vonage'],
        ]);

        $settings = CompanySetting::current();
        $payload = ['sms_provider' => $this->smsProvider];

        if ($this->smsProvider === 'twilio') {
            $payload['twilio_account_sid'] = $this->twilioSid ?: null;
            $payload['twilio_from_number'] = $this->twilioFrom ?: null;
            if ($this->twilioToken) {
                $payload['twilio_auth_token_encrypted'] = $this->twilioToken;
            }
        } else {
            $payload['vonage_api_key'] = $this->vonageKey ?: null;
            $payload['vonage_from_name'] = $this->vonageFrom ?: null;
            if ($this->vonageSecret) {
                $payload['vonage_api_secret_encrypted'] = $this->vonageSecret;
            }
        }

        $settings->update($payload);
        $this->twilioToken = '';
        $this->vonageSecret = '';

        AuditLog::record('company_settings.sms_updated', 'parametres');
        $this->dispatch('toast', message: 'Configuration SMS enregistrée avec succès.', type: 'success');
    }

    public function sendTestEmail(): void
    {
        $this->validate(['testEmailTo' => ['required', 'email']]);

        CompanySetting::current()->applyMailConfig();

        try {
            Mail::raw('Ceci est un email de test envoyé depuis AgriERP (Paramètres > Intégrations).', function ($msg) {
                $msg->to($this->testEmailTo)->subject('AgriERP — Email de test');
            });
            $this->dispatch('toast', message: 'Email de test envoyé avec succès.', type: 'success');
        } catch (\Throwable $e) {
            $this->dispatch('toast', message: "Échec de l'envoi : ".$e->getMessage(), type: 'error');
        }
    }

    public function sendTestSms(): void
    {
        $this->validate(['testSmsTo' => ['required', 'string']]);

        $result = app(SmsService::class)->send($this->testSmsTo, 'Ceci est un SMS de test envoyé depuis AgriERP.');
        $this->dispatch('toast', message: $result['message'], type: $result['success'] ? 'success' : 'error');
    }

    public function render()
    {
        return view('livewire.parametres.integrations', ['title' => 'Paramètres > Intégrations & Notifications']);
    }
}
