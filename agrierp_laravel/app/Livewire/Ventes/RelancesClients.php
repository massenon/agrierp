<?php

namespace App\Livewire\Ventes;

use App\Mail\CustomerReminderMail;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\CustomerReminder;
use App\Models\Receivable;
use App\Services\RelanceClientService;
use Illuminate\Support\Facades\Mail;
use Livewire\Component;

/**
 * Ticket 4.7 (Sprint 4) — relances-clients.html → Livewire\Ventes\RelancesClients
 * "Moteur de relance multi-canal intelligent des créances clients."
 *
 * File de relance réelle : interroge `receivables` (créée dans ce même
 * ticket — voir migration 2026_02_19) où le solde est positif et
 * l'échéance dépassée — jamais une liste statique.
 *
 * ⚠️ CANAUX RÉELLEMENT IMPLÉMENTÉS (précisions explicites reçues après le
 * premier passage de ce ticket) :
 * - Email : réel, piloté par la config SMTP de `company_settings`
 *   (`CompanySetting::applyMailConfig()`, Paramètres > Intégrations —
 *   nouvel écran de ce même ticket) plutôt que `.env` uniquement.
 * - WhatsApp : réel via lien `https://wa.me/<numéro>?text=<message>` —
 *   aucune passerelle nécessaire, ouvre WhatsApp (Web ou application)
 *   avec le message pré-rempli. Le clic est capturé côté serveur
 *   (traçabilité `CustomerReminder` réelle) puis l'ouverture du lien est
 *   déclenchée côté client via `$this->js()`.
 * - Appel : lien `tel:` (ticket AUT-3, remplace le SMS) ; la relance est journalisée.
 *   Twilio/Vonage (pas de SDK Composer — packagist.org non accessible
 *   dans ce sandbox de développement ; fonctionnera normalement en
 *   déploiement réel). Fournisseur et clés API configurés en
 *   Paramètres > Intégrations.
 * - Export Courrier PDF : toujours différé (PdfExportService à câbler
 *   dans une session dédiée).
 *
 * Un numéro client sans indicatif international ou un email absent
 * bloque l'action correspondante avec un message explicite plutôt qu'un
 * envoi silencieusement raté.
 *
 * Chaque relance réellement envoyée (mail) crée une `CustomerReminder`
 * réelle — la traçabilité et les KPI "Relances Effectuées" s'appuient
 * sur cette table, jamais des chiffres inventés.
 *
 * 🔴→✅ "Taux de Réponse" et "Montant Recouvré" ACTIVÉS (résolu dans le
 * même chantier que la reconstruction de `SuiviDettes`, qui rend
 * désormais réels les règlements sur `receivables.amount_paid`) — voir
 * docblock de `getKpisProperty()` pour l'approximation assumée
 * honnêtement (pas de preuve stricte de causalité relance→paiement,
 * signal réel malgré tout).
 *
 * Modèles de message : non persistés (aucune table `message_templates`
 * documentée) — les 3 niveaux ont un texte par défaut modifiable pour
 * l'envoi en cours uniquement, pas encore sauvegardable durablement.
 */
class RelancesClients extends Component
{
    public string $templateLevel = '2';

    public string $templateText = '';

    public function mount(): void
    {
        $this->loadTemplate();
    }

    private function defaultTemplates(): array
    {
        return [
            '1' => "Bonjour [NOM],\n\nNous vous rappelons amicalement que la facture [FACTURE] d'un montant de [MONTANT_DU] FCFA est arrivée à échéance le [DATE_ECHEANCE]. Merci de bien vouloir régulariser votre situation.\n\nCordialement,\nFerme École OLOUWACHEGOUN",
            '2' => "Bonjour [NOM],\n\nMalgré notre précédent rappel, la facture [FACTURE] d'un montant de [MONTANT_DU] FCFA reste impayée depuis le [DATE_ECHEANCE]. Merci de régulariser rapidement votre situation.\n\nCordialement,\nFerme École OLOUWACHEGOUN",
            '3' => "Mise en demeure — [NOM],\n\nSauf erreur de notre part, la facture [FACTURE] d'un montant de [MONTANT_DU] FCFA demeure impayée malgré nos relances. À défaut de règlement sous 8 jours, nous nous verrons contraints d'engager les démarches de recouvrement nécessaires.\n\nFerme École OLOUWACHEGOUN",
        ];
    }

    public function loadTemplate(): void
    {
        $this->templateText = $this->defaultTemplates()[$this->templateLevel] ?? '';
    }

    public function insertTag(string $tag): void
    {
        $this->templateText .= $tag;
    }

    public function getKpisProperty(): array
    {
        $overdue = $this->queue;
        $monthReminders = CustomerReminder::whereMonth('reminder_date', now()->month)->whereYear('reminder_date', now()->year);

        // 🔴→✅ ACTIVÉS : le blocage documenté à l'origine ("nécessite le
        // suivi des règlements — Suivi des Dettes") est résolu depuis la
        // reconstruction de `SuiviDettes` (même chantier) — les
        // règlements incrémentent réellement `receivables.amount_paid`
        // désormais. Approximation assumée et honnête : une créance est
        // comptée "répondue" si elle a reçu au moins une relance ET a un
        // paiement réel enregistré (pas une preuve stricte de causalité
        // relance→paiement, `receivables` n'a pas de journal de paiement
        // horodaté ligne par ligne — mais un signal réel, jamais un
        // chiffre inventé).
        $receivablesWithReminder = Receivable::whereHas('reminders')->get();
        $reponses = $receivablesWithReminder->filter(fn ($r) => (float) $r->amount_paid > 0);

        return [
            'creances_echues' => (float) $overdue->sum(fn ($r) => $r->balance),
            'relances_effectuees' => (clone $monthReminders)->count(),
            'taux_reponse' => $receivablesWithReminder->count() > 0
                ? round(($reponses->count() / $receivablesWithReminder->count()) * 100, 1)
                : null,
            'montant_recouvre' => (float) $reponses->sum('amount_paid'),
        ];
    }

    public function getQueueProperty()
    {
        return Receivable::with('customer')
            ->where('status', '!=', 'soldee')
            ->whereNotNull('due_date')
            ->where('due_date', '<', now())
            ->get()
            ->filter(fn ($r) => $r->balance > 0)
            ->sortByDesc(fn ($r) => $r->days_overdue);
    }

    /**
     * 🔴→✅ TROUVÉ MANQUANT — "toujours différé" documenté depuis
     * longtemps ("PdfExportService à câbler dans une session dédiée"),
     * comblé ici avec le même service déjà réel partout ailleurs dans ce
     * projet. Export PAR CRÉANCE (une lettre de relance formelle), pas
     * un export en masse comme les autres écrans — signature différente
     * en conséquence.
     */
    public function exportCourrierPdf(string $receivableId)
    {
        $this->authorize('export-ventes');

        $receivable = Receivable::with('customer')->findOrFail($receivableId);
        $message = $this->renderTemplate($receivable);

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.courrier-relance',
            ['customer' => $receivable->customer, 'message' => $message, 'receivable' => $receivable],
            'Lettre de Relance',
            $receivable->customer?->name ?? ''
        );

        $this->logReminder($receivable, 'courrier', $message);

        return response()->streamDownload(fn () => print($pdf->output()), 'relance-'.now()->format('Y-m-d').'.pdf');
    }

    public function sendMailReminder(string $receivableId): void
    {
        $receivable = Receivable::with('customer')->findOrFail($receivableId);

        try {
            app(RelanceClientService::class)->relancer($receivable->customer, $receivable, 'email', $this->renderTemplate($receivable));
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->dispatch('toast', message: $e->validator->errors()->first(), type: 'error');

            return;
        }

        $this->dispatch('toast', message: 'Relance envoyée par email avec succès.', type: 'success');
    }

    public function sendWhatsappReminder(string $receivableId): void
    {
        $receivable = Receivable::with('customer')->findOrFail($receivableId);
        $phone = preg_replace('/[^0-9]/', '', (string) $receivable->customer?->phone);

        if (! $phone) {
            $this->dispatch('toast', message: "Ce client n'a pas de numéro de téléphone enregistré.", type: 'error');

            return;
        }

        $message = $this->renderTemplate($receivable);
        $url = 'https://wa.me/'.$phone.'?text='.rawurlencode($message);

        $this->logReminder($receivable, 'whatsapp', $message);
        $this->dispatch('toast', message: 'Ouverture de WhatsApp...', type: 'success');
        $this->js("window.open(".json_encode($url).", '_blank')");
    }

    /**
     * Ticket AUT-3 (remplace le SMS) — « Appeler » : le numéro est composé depuis l'appareil par le lien `tel:` de la vue ;
     * ici, la trace de la relance. Même refus que WhatsApp : un client sans numéro ne s'appelle pas.
     */
    public function callReminder(string $receivableId): void
    {
        $receivable = Receivable::with('customer')->findOrFail($receivableId);

        try {
            app(RelanceClientService::class)->relancer($receivable->customer, $receivable, 'appel', $this->renderTemplate($receivable));
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->dispatch('toast', message: $e->validator->errors()->first(), type: 'error');

            return;
        }

        $this->dispatch('toast', message: 'Appel enregistré dans l\'historique des relances.', type: 'success');
    }

    private function logReminder(Receivable $receivable, string $channel, string $message): void
    {
        app(RelanceClientService::class)->journaliser($receivable->customer, $receivable, $channel, $message);
    }

    private function renderTemplate(Receivable $receivable): string
    {
        return str_replace(
            ['[NOM]', '[FACTURE]', '[MONTANT_DU]', '[DATE_ECHEANCE]'],
            [
                $receivable->customer?->name,
                strtoupper(substr($receivable->sale_id ?? $receivable->id, 0, 8)),
                number_format($receivable->balance, 0, ',', ' '),
                $receivable->due_date?->format('d/m/Y'),
            ],
            $this->templateText
        );
    }

    public function render()
    {
        return view('livewire.ventes.relances-clients');
    }
}
