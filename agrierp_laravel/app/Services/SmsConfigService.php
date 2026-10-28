<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\CompanySetting;

/**
 * Ticket PA-8 — POINT DE PASSAGE UNIQUE DE LA CONFIGURATION SMS : `Parametres\Integrations::saveSms` ET l'envoi du poste
 * (type `sms` de `settings_requests`). ⚠️ Un secret saisi vide est CONSERVÉ (il ne sert jamais en retour) ; il n'est jamais journalisé.
 */
class SmsConfigService
{
    /** @param array{smsProvider: string, twilioSid?: ?string, twilioFrom?: ?string, twilioToken?: ?string, vonageKey?: ?string, vonageFrom?: ?string, vonageSecret?: ?string} $v */
    public function enregistrer(array $v): void
    {
        $payload = ['sms_provider' => $v['smsProvider']];

        if ($v['smsProvider'] === 'twilio') {
            $payload['twilio_account_sid'] = ($v['twilioSid'] ?? null) ?: null;
            $payload['twilio_from_number'] = ($v['twilioFrom'] ?? null) ?: null;
            if (! empty($v['twilioToken'])) {
                $payload['twilio_auth_token_encrypted'] = $v['twilioToken'];
            }
        } else {
            // Une clé ABSENTE de la demande est conservée (le poste ne reçoit jamais la clé API : il ne peut pas la réafficher) ;
            // vide, elle est effacée comme au web.
            if (array_key_exists('vonageKey', $v)) {
                $payload['vonage_api_key'] = $v['vonageKey'] ?: null;
            }
            $payload['vonage_from_name'] = ($v['vonageFrom'] ?? null) ?: null;
            if (! empty($v['vonageSecret'])) {
                $payload['vonage_api_secret_encrypted'] = $v['vonageSecret'];
            }
        }

        CompanySetting::current()->update($payload);

        AuditLog::record('company_settings.sms_updated', 'parametres');
    }
}
