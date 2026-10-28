<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Services\SmsService;
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
 *
 * Ticket CFG-1 (19/10/2026) — LE SMTP A QUITTÉ CET ÉCRAN pour l'onglet
 * « Email (SMTP) » du hub Paramètres (`EmailSmtp`) : il se saisissait ici ET
 * dans « Données de l'Entreprise ». L'écran garde les SMS et renvoie vers
 * l'onglet pour l'e-mail.
 */
#[Layout('layouts.app')]
class Integrations extends Component
{
    public string $smsProvider = '';

    public string $twilioSid = '';

    public string $twilioToken = '';

    public string $twilioFrom = '';

    public string $vonageKey = '';

    public string $vonageSecret = '';

    public string $vonageFrom = '';

    public string $testSmsTo = '';

    public function mount(): void
    {
        abort_unless(auth()->user()->hasRole('admin'), 403);

        $settings = CompanySetting::current();
        $this->smsProvider = (string) $settings->sms_provider;
        $this->twilioSid = (string) $settings->twilio_account_sid;
        $this->twilioFrom = (string) $settings->twilio_from_number;
        $this->vonageKey = (string) $settings->vonage_api_key;
        $this->vonageFrom = (string) $settings->vonage_from_name;
        // Les secrets déjà enregistrés ne sont jamais réaffichés en clair
        // dans le formulaire — laissés vides ; un champ vide au
        // save() ne les écrase pas (voir saveSms).
    }

    public function saveSms(): void
    {
        $this->authorize('manage-parametres');

        $this->validate([
            'smsProvider' => ['required', 'in:twilio,vonage'],
        ]);

        app(\App\Services\SmsConfigService::class)->enregistrer([
            'smsProvider' => $this->smsProvider, 'twilioSid' => $this->twilioSid, 'twilioFrom' => $this->twilioFrom,
            'twilioToken' => $this->twilioToken, 'vonageKey' => $this->vonageKey, 'vonageFrom' => $this->vonageFrom,
            'vonageSecret' => $this->vonageSecret,
        ]);
        $this->twilioToken = '';
        $this->vonageSecret = '';

        $this->dispatch('toast', message: 'Configuration SMS enregistrée avec succès.', type: 'success');
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
