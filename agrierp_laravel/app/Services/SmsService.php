<?php

namespace App\Services;

use App\Models\CompanySetting;
use Illuminate\Support\Facades\Http;

/**
 * Envoi SMS réel via appel direct aux API REST Twilio/Vonage — pas de SDK
 * Composer (packagist.org n'est pas dans les domaines réseau autorisés de
 * cet environnement de développement ; les deux fournisseurs exposent une
 * API REST simple, un SDK n'est pas nécessaire pour un envoi basique).
 * Fournisseur choisi dynamiquement depuis `company_settings.sms_provider`
 * (ticket 4.7, demande explicite : "l'utilisateur met à jour ses clés API
 * SMS dans Settings").
 */
class SmsService
{
    /**
     * @return array{success: bool, message: string}
     */
    public function send(string $toPhone, string $message): array
    {
        $settings = CompanySetting::current();

        if (! $settings->hasSmsConfigured()) {
            return ['success' => false, 'message' => "Aucun fournisseur SMS n'est configuré (Paramètres > Intégrations)."];
        }

        return match ($settings->sms_provider) {
            'twilio' => $this->sendViaTwilio($settings, $toPhone, $message),
            'vonage' => $this->sendViaVonage($settings, $toPhone, $message),
            default => ['success' => false, 'message' => 'Fournisseur SMS inconnu.'],
        };
    }

    private function sendViaTwilio(CompanySetting $settings, string $to, string $message): array
    {
        $response = Http::asForm()
            ->withBasicAuth($settings->twilio_account_sid, $settings->twilio_auth_token_encrypted)
            ->post("https://api.twilio.com/2010-04-01/Accounts/{$settings->twilio_account_sid}/Messages.json", [
                'From' => $settings->twilio_from_number,
                'To' => $to,
                'Body' => $message,
            ]);

        return [
            'success' => $response->successful(),
            'message' => $response->successful() ? 'SMS envoyé via Twilio.' : 'Échec Twilio : '.($response->json('message') ?? $response->status()),
        ];
    }

    private function sendViaVonage(CompanySetting $settings, string $to, string $message): array
    {
        $response = Http::asForm()->post('https://rest.nexmo.com/sms/json', [
            'api_key' => $settings->vonage_api_key,
            'api_secret' => $settings->vonage_api_secret_encrypted,
            'to' => preg_replace('/[^0-9]/', '', $to),
            'from' => $settings->vonage_from_name ?: 'AgriERP',
            'text' => $message,
        ]);

        $status = $response->json('messages.0.status');

        return [
            'success' => $response->successful() && $status === '0',
            'message' => $status === '0' ? 'SMS envoyé via Vonage.' : 'Échec Vonage : '.($response->json('messages.0.error-text') ?? 'erreur inconnue'),
        ];
    }
}
