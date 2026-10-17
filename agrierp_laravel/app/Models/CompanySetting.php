<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Config;

/**
 * Table singleton — une seule ligne. Secrets (`*_encrypted`) chiffrés par
 * le cast Eloquent `encrypted` (clé `APP_KEY`), jamais stockés en clair.
 */
class CompanySetting extends Model
{
    use HasUuids;

    protected $fillable = [
        // Ticket 14.56 — bascule du mode demonstration (faux par defaut).
        'demo_mode_enabled',
        // Ticket 15.50 — instant de la dernière réinitialisation des données (servi au tirage).
        'data_reset_at',
        'company_name', 'promoter_name', 'address', 'phone', 'email', 'ifu', 'rccm',
        'smtp_host', 'smtp_port', 'smtp_security', 'smtp_user', 'smtp_password_encrypted',
        'logo_path', 'favicon_path',
        'sms_provider', 'twilio_account_sid', 'twilio_auth_token_encrypted', 'twilio_from_number',
        'vonage_api_key', 'vonage_api_secret_encrypted', 'vonage_from_name',
        // Ticket 14.38 — regime de TVA et parametres de paie beninoise.
        'tva_enabled', 'tva_default_rate', 'vps_rate', 'cnss_employee_rate',
        'cnss_employer_pension_rate', 'cnss_employer_family_rate', 'cnss_employer_risk_rate',
        'payroll_settings_edited_at', 'payroll_settings_edited_by',
    ];

    protected function casts(): array
    {
        return [
            'smtp_password_encrypted' => 'encrypted',
            'twilio_auth_token_encrypted' => 'encrypted',
            'vonage_api_secret_encrypted' => 'encrypted',
            'payroll_settings_edited_at' => 'datetime',
            'data_reset_at' => 'datetime',
        ];
    }

    public static function current(): self
    {
        return static::query()->firstOrCreate([]);
    }

    /**
     * Configure dynamiquement `mail.mailers.smtp.*` depuis la base avant
     * tout envoi — appelée explicitement au point d'envoi (jamais au boot
     * global de l'application), plutôt qu'une config `.env` statique
     * uniquement. Ne fait rien si aucun SMTP n'est encore renseigné : le
     * `.env` (`MAIL_MAILER=log` en développement) reste alors la config
     * active, comportement Laravel standard déjà en place depuis le
     * ticket 1.6.
     */
    public function applyMailConfig(): void
    {
        if (! $this->smtp_host) {
            return;
        }

        Config::set('mail.default', 'smtp');
        Config::set('mail.mailers.smtp.host', $this->smtp_host);
        Config::set('mail.mailers.smtp.port', $this->smtp_port ?? 587);
        Config::set('mail.mailers.smtp.encryption', $this->smtp_security ?: null);
        Config::set('mail.mailers.smtp.username', $this->smtp_user);
        Config::set('mail.mailers.smtp.password', $this->smtp_password_encrypted);

        if ($this->email) {
            Config::set('mail.from.address', $this->email);
            Config::set('mail.from.name', $this->company_name);
        }
    }

    public function hasSmsConfigured(): bool
    {
        return match ($this->sms_provider) {
            'twilio' => (bool) ($this->twilio_account_sid && $this->twilio_auth_token_encrypted && $this->twilio_from_number),
            'vonage' => (bool) ($this->vonage_api_key && $this->vonage_api_secret_encrypted),
            default => false,
        };
    }

    /**
     * Ticket 14.39 — les paramètres de paie sont-ils figés ?
     *
     * ⚠️ LA PREMIÈRE ÉDITION RESTE OUVERTE. Le barème et les taux sont semés
     * avec des valeurs par défaut qui doivent être validées : c'est cette
     * première saisie qui entre les valeurs réellement arrêtées par le client.
     * Exiger l'administrateur dès le départ aurait bloqué la mise en service.
     *
     * ⚠️ TOUTE ÉDITION ULTÉRIEURE EST RÉSERVÉE À L'ADMINISTRATEUR. Un barème
     * fiscal et des taux de cotisation déterminent le net versé à chaque
     * salarié et les montants déclarés aux organismes : une fois arrêtés, ils
     * ne se modifient plus au fil de l'eau.
     */
    public function payrollSettingsLocked(): bool
    {
        return $this->payroll_settings_edited_at !== null;
    }

    /** L'utilisateur courant peut-il modifier les paramètres de paie ? */
    public function payrollSettingsEditableBy(?User $user): bool
    {
        if (! $this->payrollSettingsLocked()) {
            return true;   // première configuration : ouverte
        }

        return $user?->hasRole('admin') ?? false;
    }

    /** Trace de qui a figé le paramétrage, et quand. */
    public function markPayrollSettingsEdited(?User $user): void
    {
        $this->update([
            'payroll_settings_edited_at' => now(),
            'payroll_settings_edited_by' => $user?->id,
        ]);
    }

    public function payrollSettingsEditor()
    {
        return $this->belongsTo(User::class, 'payroll_settings_edited_by');
    }
}
