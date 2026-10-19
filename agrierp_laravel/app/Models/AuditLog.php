<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Un seul point de vérité pour la journalisation d'audit (AVOID_INSTRUCTIONS.md
 * § Difficult Debugging : logs d'audit sur toute action sensible, pas
 * seulement les erreurs). Tout point du code qui journalise une action
 * sensible (connexion, déconnexion, clôture d'exercice, modification RBAC,
 * désactivation de module — Document 06 §12) appelle `AuditLog::record()`,
 * jamais une insertion directe dupliquée localement.
 */
class AuditLog extends Model
{
    use HasUuids;

    public $timestamps = false;

    /**
     * Ticket 15.20a — `created_at` est écrit par l'application, dans SON fuseau (et non par la base en
     * UTC) : le tableau de bord filtre « les activités du jour » avec `now()`, et une action saisie entre
     * 00:00 et 01:00 heure du Bénin disparaissait de la liste (voir `Notification::booted`).
     */
    protected static function booted(): void
    {
        static::creating(function (self $log) {
            $log->created_at ??= now();
        });
    }

    protected $fillable = [
        'user_id',
        'action',
        'module',
        'ip_address',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
        ];
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public static function record(string $action, ?string $module = null, ?string $userId = null): self
    {
        return static::create([
            'user_id' => $userId ?? auth()->id(),
            'action' => $action,
            'module' => $module,
            'ip_address' => request()?->ip(),
        ]);
    }

    /**
     * Libellés lisibles — un seul point de vérité (AVOID_INSTRUCTIONS.md
     * § Inconsistent Coding Patterns), réutilisé par tout écran affichant
     * le journal d'audit (Mon Profil aujourd'hui ; Administration/Paramètres
     * > Journal d'Audit plus tard, Sprint 9/11). Complété au fil des
     * sprints à mesure que de nouvelles clés `action`/`module` apparaissent
     * (`AuditLog::record('sale.created', 'ventes')`, etc.) — jamais un
     * libellé français recréé localement dans une vue.
     */
    /**
     * Libellés lisibles — un seul point de vérité (AVOID_INSTRUCTIONS.md
     * § Inconsistent Coding Patterns), réutilisé par tout écran affichant
     * le journal d'audit (Mon Profil ; Paramètres > Audit Logs, ticket
     * dédié Sprint 11). Liste complétée exhaustivement à ce ticket avec
     * les ~90 clés `action` réellement utilisées dans le code du projet
     * (recensées par grep sur tous les appels `AuditLog::record()`) —
     * jamais un libellé français recréé localement dans une vue, jamais
     * une clé affichée brute faute de traduction.
     */
    private const ACTION_LABELS = [
        'login' => 'Connexion réussie',
        // Ticket 14.42 — l'utilisateur rattaché est le compte VISÉ par la
        // tentative, jamais son auteur (inconnu par nature).
        'login.failed' => 'Tentative de connexion échouée',
        'login.locked' => 'Compte verrouillé (trop de tentatives)',
        'logout' => 'Déconnexion',
        'password.updated' => 'Mot de passe modifié',
        'user.created' => 'Utilisateur créé',
        'user.updated' => 'Utilisateur modifié',
        'user.archived' => 'Utilisateur archivé',
        'user.reactivated' => 'Utilisateur réactivé',
        'role.created' => 'Rôle créé',
        'role.updated' => 'Rôle modifié',
        'role.deleted' => 'Rôle supprimé',
        'module.toggled' => 'Module basculé',
        'company_settings.updated' => "Données de l'entreprise modifiées",
        'company_settings.smtp_updated' => 'Configuration SMTP modifiée',
        'company_settings.smtp_tested' => 'Test SMTP envoyé',
        // Ticket CFG-1 — effacement explicite du mot de passe SMTP (onglet Email (SMTP)).
        'company_settings.smtp_password_cleared' => 'Mot de passe SMTP effacé',
        'company_settings.sms_updated' => 'Configuration SMS modifiée',
        'database.backup_generated' => 'Sauvegarde générée',
        'database.backup_downloaded' => 'Sauvegarde téléchargée',
        'treasury_account.bank_created' => 'Compte bancaire ajouté',
        'treasury_account.momo_created' => 'Ligne Mobile Money ajoutée',
        'sale.created' => 'Vente enregistrée',
        'sale.validated' => 'Vente validée',
        'sale.cancelled' => 'Vente annulée',
        'sale.mecef_retried' => 'Retransmission MeCeF',
        'pos.item_added' => 'Article ajouté au panier POS',
        'quote.created' => 'Devis créé',
        'quote.updated' => 'Devis modifié',
        'quote.sent' => 'Devis envoyé',
        'quote.accepted' => 'Devis accepté',
        'quote.refused' => 'Devis refusé',
        'quote.archived' => 'Devis archivé',
        'customer.created' => 'Client créé',
        'customer.updated' => 'Client modifié',
        'customer.archived' => 'Client archivé',
        // Ticket S-T5 — création d'un poste fusionnée avec une fiche existante (même clé naturelle).
        'customer.merged' => 'Client du poste fusionné avec une fiche existante',
        'customer_reminder.sent_' => 'Relance client envoyée',
        'credit_note.created' => 'Avoir créé',
        'credit_note.treated' => 'Avoir traité',
        'purchase.recorded' => 'Achat enregistré',
        'purchase.returned' => 'Achat retourné',
        'purchase_order.created' => 'Bon de commande créé',
        'purchase_order.received' => 'Bon de commande réceptionné',
        'purchase_order.pdf_exported' => 'Bon de commande exporté en PDF',
        'supplier.created' => 'Fournisseur créé',
        'supplier.updated' => 'Fournisseur modifié',
        'supplier.archived' => 'Fournisseur archivé',
        'supplier.merged' => 'Fournisseur du poste fusionné avec une fiche existante',
        'supplier_refund.recorded' => 'Remboursement fournisseur enregistré',
        'payable.payment_recorded' => 'Règlement fournisseur enregistré',
        // Ticket 15.19 — avances clients (clés posées depuis le Sprint 4, jamais libellées).
        'customer_advance.created' => 'Avance client enregistrée',
        'customer_advance.updated' => 'Avance client modifiée',
        'customer_advance.imputed' => 'Avance client imputée sur une créance',
        'customer_advance.archived' => 'Avance client archivée',
        'expense.created' => 'Dépense enregistrée',
        'expense.updated' => 'Dépense modifiée',
        'expense.archived' => 'Dépense archivée',
        'product.created' => 'Produit créé',
        'product.updated' => 'Produit modifié',
        'product.archived' => 'Produit archivé',
        'product.merged' => 'Produit du poste fusionné avec une fiche existante',
        'product.threshold_updated' => "Seuil d'alerte modifié",
        'stock.adjusted' => 'Stock ajusté',
        'stock.manual_addition' => 'Ajout manuel de stock',
        // Ticket S-T10 — inventaire du poste acquitté sans mouvement.
        'stock.inventaire_sans_ecart' => "Inventaire du poste sans écart au serveur",
        'stock.inventaire_depasse' => 'Inventaire du poste remplacé par un inventaire plus récent',
        'transformation.recorded' => 'Transformation enregistrée',
        'livestock_lot.created' => 'Lot créé',
        'livestock_lot.updated' => 'Lot modifié',
        'livestock_lot.archived' => 'Lot archivé',
        'livestock_entry.recorded' => 'Sujet enregistré',
        'livestock_daily_entry.saved' => 'Saisie quotidienne enregistrée',
        'reproduction_event.created' => 'Événement de reproduction créé',
        'reproduction_event.palpation_recorded' => 'Palpation enregistrée',
        'reproduction_event.misebas_recorded' => 'Mise-bas enregistrée',
        'reproduction_event.closed' => 'Événement de reproduction clôturé',
        'veterinary_record.created' => 'Soin vétérinaire enregistré',
        'veterinary_record.archived' => 'Soin vétérinaire archivé',
        'veterinary_calendar_event.created' => 'Événement vétérinaire planifié',
        'veterinary_calendar_event.confirmed' => 'Événement vétérinaire confirmé',
        'infirmary_record.created' => "Entrée à l'infirmerie enregistrée",
        'infirmary_record.reintegrated' => 'Sujet réintégré depuis l\'infirmerie',
        'infirmary_record.death_declared' => 'Décès déclaré',
        'feed_ration_standard.saved' => 'Barème de rationnement enregistré',
        'feed_ration_standard.deleted' => 'Barème de rationnement supprimé',
        'feed_type.saved' => "Type d'aliment enregistré",
        'feed_type.deleted' => "Type d'aliment supprimé",
        'prophylaxis_schedule.saved' => 'Calendrier de prophylaxie enregistré',
        'prophylaxis_schedule.deleted' => 'Calendrier de prophylaxie supprimé',
        'elevage_numbering.updated' => 'Numérotation élevage modifiée',
        // Ticket H9b — l'écran web et le poste ARCHIVENT (14.55) : ces clés s'affichaient brutes au journal.
        'feed_ration_standard.archived' => 'Barème de rationnement archivé',
        'feed_type.archived' => "Type d'aliment archivé",
        'prophylaxis_schedule.archived' => 'Calendrier de prophylaxie archivé',
        'rappel_soins.updated' => 'Délai de rappel des soins modifié',
        'employee.created' => 'Employé créé',
        'employee.updated' => 'Employé modifié',
        'employee.archived' => 'Employé archivé',
        'internship.created' => 'Stagiaire créé',
        'internship.updated' => 'Stagiaire modifié',
        'internship_absence.recorded' => 'Absence de stagiaire enregistrée',
        'internship_absence.deleted' => 'Absence de stagiaire supprimée',
        'attendance.archived' => 'Pointage archivé',
        'payslip.paid' => 'Bulletin de paie réglé',
        'attestation.generated' => 'Attestation générée',
        'api.login' => 'Connexion API (appareil Flutter)',
        'api.logout' => 'Déconnexion API (appareil Flutter)',
        'api.sync_push' => 'Synchronisation — données envoyées par un appareil',
        // Ticket CFG-1 — onglet Postes & Appairage : jetons d'un poste supprimés.
        'sync.appairage_revoque' => "Appairage d'un poste révoqué",
        'sale.negative_stock_received' => 'Vente reçue d\'un poste : stock passé sous zéro',
        // Ticket U14 — écrit par l'envoi des postes quand la facture d'une vente reçue n'a pas pu être transmise au
        // MeCeF (vente gardée, statut « erreur », retransmission depuis Facturation). Il était écrit avant S-T13 sans
        // libellé : le journal d'audit montrait la clé technique.
        'sale.mecef_failed_on_sync' => 'Vente reçue d\'un poste : échec de la transmission MeCeF',
        'reproduction_event.updated_from_device' => 'Cycle de reproduction mis à jour depuis un poste',
        'attestation.generated.employe' => 'Attestation de travail générée',
        'attestation.generated.stagiaire' => 'Attestation de stage générée',
        'attestation_template.updated' => "Modèle d'attestation modifié",
        'mail.created' => 'Courrier enregistré',
        'mail.updated' => 'Courrier modifié',
        'mail.archived' => 'Courrier archivé',
        'archived_document.created' => 'Document archivé',
        'archived_document.updated' => 'Document archivé modifié',
        'archived_document.deleted' => 'Document retiré des archives',
        'administrative_document.created' => 'Document administratif créé',
        'administrative_document.updated' => 'Document administratif modifié',
        'administrative_document.archived' => 'Document administratif archivé',
        'chart_of_account.created' => 'Compte comptable créé',
        'chart_of_account.updated' => 'Compte comptable modifié',
        'chart_of_account.archived' => 'Compte comptable archivé',
        'accounting_entry.created' => 'Écriture comptable créée',
        'accounting_entry.updated' => 'Écriture comptable modifiée',
        'accounting_entry.archived' => 'Écriture comptable archivée',
        'fiscal_year.step1_confirmed' => "Travaux d'inventaire confirmés",
        'fiscal_year.gestion_accounts_closed' => 'Comptes de gestion soldés',
        'fiscal_year.closed' => 'Exercice clôturé',
        'contact.message_sent' => 'Message envoyé à l\'éditeur',
        'contact.bug_reported' => 'Bug signalé à l\'éditeur',
    ];

    private const MODULE_LABELS = [
        'auth' => 'Authentification',
        'elevage' => 'Élevage',
        'ventes' => 'Ventes & Devis',
        'achats' => 'Achats & Commandes',
        'stocks' => 'Gestion Stocks',
        'facturation' => 'Facturation',
        'rh' => 'Personnel & Stages',
        'administration' => 'Administration',
        'comptabilite' => 'Comptabilité',
        'parametres' => 'Paramètres',
        'rapports' => 'Rapports & Exports',
        'fournisseurs' => 'Fournisseurs',
    ];

    public function getActionLabelAttribute(): string
    {
        return self::ACTION_LABELS[$this->action] ?? $this->action;
    }

    public function getModuleLabelAttribute(): ?string
    {
        if (! $this->module) {
            return null;
        }

        return self::MODULE_LABELS[$this->module] ?? $this->module;
    }
}
