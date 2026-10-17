<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Services\PdfExportService;
use Illuminate\Support\Facades\Response;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * DERNIER ONGLET DU HUB PARAMÈTRES — SPRINT 11 COMPLET UNE FOIS CE
 * TICKET LIVRÉ. audit-logs.html → Livewire\Parametres\AuditLogs
 * "Historique horodaté des actions sensibles effectuées dans AgriERP."
 *
 * `AuditLog` existait déjà en intégralité (~90 clés `action` réellement
 * utilisées dans tout le projet, recensées et traduites dans ce même
 * ticket — voir `AuditLog::ACTION_LABELS`) — cet écran est le PREMIER à
 * l'exposer réellement en lecture, jamais une seconde table de logs.
 *
 * ⚠️ Lecture seule, fidèle au prototype ("Les journaux d'audit sont
 * immuables : aucune modification ni suppression n'est possible.") —
 * aucun bouton modifier/supprimer, jamais une exception à cette règle
 * pour un journal d'audit dont l'intégrité est justement la raison d'être.
 *
 * "Connexions échouées" (KPI) : 🔴→✅ LIVRÉ AU TICKET 14.42. La
 * traçabilité manquait à la SOURCE, pas ici : `Livewire\Auth\Login`
 * n'appelait `AuditLog::record()` qu'en cas de SUCCÈS. Les tentatives
 * échouées (`login.failed`) et les verrouillages (`login.locked`) sont
 * désormais journalisés, et ce KPI les compte réellement.
 *
 * ⚠️ FENÊTRE DE 24 H, À CONFIRMER. Le prototype affiche « 2 » sans
 * préciser de période, contrairement à la carte voisine « Événements
 * (24h) ». Un cumul depuis l'origine croîtrait indéfiniment et ne
 * signalerait plus rien ; la fenêtre de 24 h de la carte voisine est
 * retenue par cohérence, et le sous-titre le dit à l'écran plutôt que de
 * laisser croire à un total. Choix à valider au prochain point client.
 *
 * ⚠️ ÉCART D'ICÔNE ASSUMÉ (relevé au ticket 14.49) : le prototype porte
 * `add_circle` sur le bouton « Exporter le Journal » — résidu manifeste du
 * gabarit « créer » dont l'écran est dérivé, sur un écran explicitement en
 * lecture seule où rien ne se crée. `file_download` retenu, cohérent avec
 * l'action réelle. Signalé plutôt que corrigé en silence : un nom d'icône
 * fait partie des éléments préservés à l'identique par défaut.
 *
 * Export réel : PDF via `PdfExportService` (déjà utilisé depuis le
 * ticket 5.5) et CSV réel généré directement — jamais une simulation de
 * téléchargement.
 */
class AuditLogs extends Component
{
    #[Url]
    public string $search = '';

    public string $exportPeriod = '';

    public string $exportFormat = '';

    public function getKpisProperty(): array
    {
        return [
            'evenements_24h' => AuditLog::where('created_at', '>=', now()->subDay())->count(),
            'connexions_echouees' => AuditLog::where('action', 'login.failed')
                ->where('created_at', '>=', now()->subDay())
                ->count(),
        ];
    }

    public function getLogsProperty()
    {
        return AuditLog::with('user')
            ->when($this->search, fn ($q) => $q->where(fn ($q2) => $q2->where('action', 'like', '%'.$this->search.'%')->orWhere('module', 'like', '%'.$this->search.'%')))
            ->orderByDesc('created_at')
            ->limit(200)
            ->get();
    }

    private function periodRange(string $period): array
    {
        return match ($period) {
            "Aujourd'hui" => [now()->startOfDay(), now()->endOfDay()],
            '7 derniers jours' => [now()->subDays(7)->startOfDay(), now()->endOfDay()],
            'Ce mois-ci' => [now()->startOfMonth(), now()->endOfMonth()],
            default => [now()->subDays(7)->startOfDay(), now()->endOfDay()],
        };
    }

    public function exportLogs()
    {
        $this->validate([
            'exportPeriod' => ['required', 'in:Aujourd\'hui,7 derniers jours,Ce mois-ci'],
            'exportFormat' => ['required', 'in:PDF,Excel (CSV)'],
        ]);

        [$start, $end] = $this->periodRange($this->exportPeriod);

        $logs = AuditLog::with('user')
            ->whereBetween('created_at', [$start, $end])
            ->orderByDesc('created_at')
            ->get();

        AuditLog::record('audit_logs.exported', 'parametres');
        $this->dispatch('close-modal', name: 'modal-create-audit-logs');

        if ($this->exportFormat === 'PDF') {
            $pdf = app(PdfExportService::class)->render(
                'exports.audit-logs',
                ['logs' => $logs],
                'Journal des Audits',
                $this->exportPeriod
            );

            return response()->streamDownload(fn () => print($pdf->output()), 'audit-logs-'.now()->format('Y-m-d').'.pdf');
        }

        $csv = "Horodatage,Utilisateur,Action,Module\n";
        foreach ($logs as $log) {
            $csv .= implode(',', [
                $log->created_at->format('d/m/Y H:i'),
                '"'.($log->user?->name ?? 'Inconnu').'"',
                '"'.$log->action_label.'"',
                '"'.($log->module_label ?? '').'"',
            ])."\n";
        }

        return Response::streamDownload(fn () => print($csv), 'audit-logs-'.now()->format('Y-m-d').'.csv', ['Content-Type' => 'text/csv']);
    }

    public function render()
    {
        return view('livewire.parametres.audit-logs');
    }
}
