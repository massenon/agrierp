<?php

namespace App\Livewire\Comptabilite;

use App\Models\FiscalYear;
use App\Services\FinancialReportService;
use App\Support\ExerciceChoisi;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 14.5 (Sprint 14) — balance-generale.html → Livewire\Comptabilite\BalanceGenerale
 * "Synthèse des soldes de tous les comptes utilisés — vérification de
 * l'équilibre avant clôture."
 *
 * 2e des 5 écrans comptables ajoutés au prototype après le Sprint 12 et
 * jamais convertis. Le log de livraison décrivait cet écran comme construit,
 * mais `app/Livewire/Comptabilite/BalanceGenerale.php` et ses 2 vues
 * n'existaient dans aucune des 4 installations du poste (audit du ticket
 * 14.5) — construit réellement ici, décisions de conception du log reprises.
 *
 * ⚠️ PLACEMENT EN COLONNE PAR LE SIGNE, JAMAIS PAR LA NATURE DU COMPTE —
 * décision reprise telle quelle du log et implémentée dans
 * `FinancialReportService::balanceGenerale()` : classer un solde selon la
 * nature théorique du compte ferait disparaître des deux colonnes tout
 * compte en anomalie, alors que révéler ces anomalies est la raison d'être
 * d'une balance.
 *
 * ⚠️ BANDEAU D'AVERTISSEMENT DU PROTOTYPE VOLONTAIREMENT NON REPRIS : le
 * prototype affiche une note expliquant un écart de 670 000 FCFA sur le
 * Capital (101) entre Balance et États Financiers. Cet écart n'existe QUE
 * parce que les deux écrans du prototype portent des jeux de chiffres écrits
 * en dur, ajustés séparément ("plug" de reconstruction, dit le commentaire
 * source lui-même). Ici les deux écrans liront le même grand livre : recopier
 * ce bandeau afficherait en permanence un avertissement sur un écart
 * structurellement impossible — ce serait de la fidélité de façade, pas de la
 * fidélité réelle. Écart documenté ici plutôt que reproduit à l'écran.
 *
 * Le contrôle d'équilibre, lui, est bien réel et conservé : si
 * Σ débits ≠ Σ crédits, l'alerte de déséquilibre s'affiche — c'est
 * exactement le service que rend cet écran avant une clôture.
 */
#[Layout('layouts.app')]
class BalanceGenerale extends Component
{
    /** 'mois' = période courante, 'exercice' = exercice comptable complet. */
    #[Url]
    public string $periode = 'mois';

    /**
     * Ticket EX7 (EF9) — l'exercice AFFICHÉ (`ExerciceChoisi`), et non plus `FiscalYear::current()` (le plus récent
     * ouvert) : avec 2026 et 2027 ouverts, 2026 ne s'affichait plus qu'en période libre.
     */
    public function getFiscalYearProperty(): ?FiscalYear
    {
        return ExerciceChoisi::exercice();
    }

    /**
     * Bornes réelles de la période choisie, toujours DANS l'exercice affiché (EF9) :
     *  - « exercice » : ses dates réelles (`fiscal_years`), jamais l'année civile supposée — l'année civile du jour
     *    seulement si aucun exercice n'existe encore ;
     *  - « mois » : le mois du jour quand l'exercice le contient, sinon son DERNIER mois (2026 lu en 2027 : décembre).
     *
     * @return array{0: string, 1: string}
     */
    public function periodBounds(): array
    {
        if ($this->periode === 'exercice') {
            return ExerciceChoisi::bornes();
        }

        $mois = ExerciceChoisi::moisDeReference();

        return [$mois->format('Y-m-d'), $mois->copy()->endOfMonth()->format('Y-m-d')];
    }

    /**
     * Libellés des deux options, repris tels quels au poste (`DonneesComptabilite.libellePeriodeBalance`) :
     * « Février 2027 (période courante) » — « Décembre 2026 » pour un mois qui n'est pas le mois courant — et
     * « Exercice 2026 » (PRD § 7 : l'option prend le libellé de l'exercice choisi ; « Exercice complet — 2026 » avant).
     *
     * @return array{mois: string, exercice: string}
     */
    public function getLibellesPeriodeProperty(): array
    {
        $mois = ExerciceChoisi::moisDeReference();

        return [
            'mois' => ucfirst($mois->translatedFormat('F Y')).(ExerciceChoisi::contientAujourdhui() ? ' (période courante)' : ''),
            'exercice' => 'Exercice '.ExerciceChoisi::annee(),
        ];
    }

    public function getPeriodLabelProperty(): string
    {
        return $this->libellesPeriode[$this->periode === 'exercice' ? 'exercice' : 'mois'];
    }

    public function getBalanceProperty(): array
    {
        [$start, $end] = $this->periodBounds();

        return app(FinancialReportService::class)->balanceGenerale($start, $end);
    }

    public function exportBalancePdf()
    {
        $this->authorize('view-comptabilite');

        $pdf = app(\App\Services\PdfExportService::class)->render(
            'exports.balance-generale',
            ['balance' => $this->balance],
            'Balance Générale',
            $this->periodLabel.($this->balance['ouverture']['provisoire'] ? ' — À-nouveaux provisoires' : '')
        );

        return response()->streamDownload(
            fn () => print ($pdf->output()),
            'balance-generale-'.now()->format('Y-m-d').'.pdf'
        );
    }

    public function render()
    {
        return view('livewire.comptabilite.balance-generale', ['title' => 'Comptabilité > Balance Générale']);
    }
}
