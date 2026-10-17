<?php

namespace App\Livewire\Comptabilite;

use App\Services\FinancialReportService;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 10.8 (Sprint 10) — comptabilite-hub.html → Livewire\Comptabilite\ComptabiliteHub
 * DERNIER TICKET DU SPRINT LE PLUS SENSIBLE. Point d'entrée unique
 * "Comptabilité" (Document 01 §Rôles) assemblant les 5 écrans construits
 * aux tickets 10.3-10.7 — le lien sidebar `/comptabilite-hub`, présent
 * depuis le Sprint 0, devient enfin fonctionnel.
 *
 * ⚠️ LES 4 KPI SONT 100% DYNAMIQUES, AUCUNE DONNÉE STATIQUE (demande
 * explicite) : le prototype affichait 4 montants codés en dur
 * (6 818 500 / 850 000 / 28% / 1 600 000). Remplacés par de vrais
 * calculs, tous réutilisant `FinancialReportService` (extrait de
 * `Bilan`, ticket 10.5, dans ce même ticket) — jamais une seconde
 * implémentation du même calcul :
 * - "Total Actif" et "Trésorerie Disponible" : `FinancialReportService::bilan()`.
 * - "Recettes du Mois" : `FinancialReportService::produitsPeriode()` sur le mois en cours.
 * - "Marge Nette (Analytique)" : Résultat de l'exercice ÷ Recettes du mois × 100,
 *   dérivé du même bilan — jamais une troisième source de vérité pour la
 *   même notion de marge déjà calculée dans `ComptabiliteAnalytique`
 *   (ticket 10.7) au niveau filière ; ici c'est la marge nette globale de
 *   l'exercice, une notion réellement différente, pas dupliquée.
 *
 * Cartes de navigation : simples liens statiques vers les routes déjà
 * réelles (10.3-10.7) — rien à calculer, la navigation elle-même n'est
 * pas une "donnée".
 */
#[Layout('layouts.app')]
class ComptabiliteHub extends Component
{
    public function getKpisProperty(): array
    {
        $service = app(FinancialReportService::class);
        $today = now()->format('Y-m-d');
        $monthStart = now()->startOfMonth()->format('Y-m-d');

        $bilan = $service->bilan($today);
        $recettesMois = $service->produitsPeriode($monthStart, $today);

        // 🔴→✅ TROUVÉ PAR VÉRIFICATION NIVEAU 2 : le libellé du prototype
        // est "Marge Nette (Analytique)", pas "(Exercice)" — corrigé
        // (vue). Le calcul suivait jusqu'ici un ratio bilan générique
        // (résultat global / recettes), pas la méthodologie réelle du
        // module Comptabilité Analytique (classes 6/7 par centre de
        // coût, `ComptabiliteAnalytique::getRowsProperty()`) — recalculé
        // ici avec la même requête que ce module réel, agrégée sur tous
        // les centres de coût plutôt que dupliquée filière par filière
        // (inutile pour un seul chiffre global), pour que le libellé
        // corrigé corresponde réellement à sa source.
        $lines = \App\Models\AccountingEntryLine::query()
            ->join('accounting_entries', 'accounting_entries.id', '=', 'accounting_entry_lines.entry_id')
            ->where('accounting_entries.is_active', true)
            ->whereDate('accounting_entries.entry_date', '>=', $monthStart)
            ->whereDate('accounting_entries.entry_date', '<=', $today)
            ->join('chart_of_accounts', 'chart_of_accounts.id', '=', 'accounting_entry_lines.account_id')
            ->whereNotNull('accounting_entry_lines.cost_center_id')
            ->whereIn('chart_of_accounts.class', [6, 7])
            ->selectRaw('chart_of_accounts.class, SUM(accounting_entry_lines.debit) as total_debit, SUM(accounting_entry_lines.credit) as total_credit')
            ->groupBy('chart_of_accounts.class')
            ->get();

        $caAnalytique = (float) $lines->where('class', 7)->sum(fn ($l) => $l->total_credit - $l->total_debit);
        $chargesAnalytique = (float) $lines->where('class', 6)->sum(fn ($l) => $l->total_debit - $l->total_credit);
        $margeAnalytique = $caAnalytique > 0 ? round((($caAnalytique - $chargesAnalytique) / $caAnalytique) * 100, 1) : null;

        return [
            'total_actif' => $bilan['total_actif'],
            'recettes_mois' => $recettesMois,
            'marge_nette' => $margeAnalytique,
            'tresorerie' => $bilan['total_tresorerie'],
        ];
    }

    public function render()
    {
        return view('livewire.comptabilite.comptabilite-hub', ['title' => 'Comptabilité']);
    }
}
