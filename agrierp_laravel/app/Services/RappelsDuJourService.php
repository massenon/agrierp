<?php

namespace App\Services;

use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use App\Models\VeterinaryWithdrawalPeriod;
use Carbon\Carbon;

/**
 * Ticket POP1 — LA FENÊTRE « RAPPELS DU JOUR » : UN SEUL CALCUL, APPELÉ, JAMAIS RECOPIÉ.
 *
 * ═══ RÈGLE R-RAPPELS-01 (rédigée le 26/10/2026, PRD `docs/prd/popup-rappels.md` § 5) ═══
 * Horizon N = délai de rappel des soins déjà réglé (`AlertesElevageService::joursRappelSoins`, R-SOINS-01).
 * Aucun seuil nouveau : trois sources, chacune déjà calculée ailleurs.
 *  1. SOIN PLANIFIÉ (`AlertesElevageService::soinsAVenir`, la règle R-SOINS-01 telle quelle ; le calendrier ne porte aucun
 *     produit : « — ») : date dépassée =
 *     « En retard », date du jour = « Aujourd'hui », jusqu'à aujourd'hui + N = « À venir ».
 *  2. TRAITEMENT DU BARÈME PROPHYLACTIQUE dû et non encore administré (moteur UNIQUE `ProtocoleDuJourService`, comme le
 *     Dashboard Élevage), pour chacun des jours J à J+N : « Aujourd'hui » ou « À venir ». Jamais « En retard » : le
 *     jour de cycle raté n'est pas rattrapé par la règle (c'est celle du Dashboard).
 *  3. FIN DE DÉLAI D'ATTENTE (rémanence) entre aujourd'hui et aujourd'hui + N : « Aujourd'hui » ou « À venir ».
 * Bandes vivantes seulement ; une espèce désactivée dans Modules Actifs ne génère aucun rappel.
 * Tri : urgence, date prévue croissante, code de bande, type (soin, prophylaxie, délai d'attente), libellé.
 *
 * ⚠️ Le poste recalcule la même règle en local (`RappelsDuJourRepository`) ; la parité est EXÉCUTÉE contre ce service.
 * Toute évolution se fait ici d'abord (Doctrine, article 5).
 */
class RappelsDuJourService
{
    public const PERMISSION = 'view-elevage';

    private const RANG_URGENCE = ['retard' => 0, 'aujourdhui' => 1, 'avenir' => 2];

    private const RANG_TYPE = ['soin' => 0, 'prophylaxie' => 1, 'remanence' => 2];

    public function __construct(
        private readonly AlertesElevageService $alertes,
        private readonly ProtocoleDuJourService $protocole,
    ) {}

    /**
     * Les rappels que CET utilisateur doit voir : vide s'il n'a pas le droit de voir Soins et vaccins.
     *
     * @return array<int, array<string, mixed>>
     */
    public function pourUtilisateur(?User $utilisateur): array
    {
        if (! $utilisateur || ! $utilisateur->can(self::PERMISSION)) {
            return [];
        }

        return $this->calculer();
    }

    /**
     * @return array<int, array{urgence: string, type: string, type_libelle: string, bande: string, espece: string,
     *     libelle: string, produit: string, date: string, date_texte: string, jours: int, echeance: string}>
     */
    public function calculer(): array
    {
        $aujourdhui = Carbon::today();
        $horizon = $this->alertes->joursRappelSoins();
        $codesActifs = LivestockSpecies::enabled()->pluck('code')->all();
        $lignes = [];

        foreach ($this->alertes->soinsAVenir() as $soin) {
            $bande = $soin->lot;
            if (! $bande || ! in_array($bande->species?->code, $codesActifs, true)) {
                continue;
            }
            $lignes[] = $this->ligne('soin', $bande, $soin->task_type, null, $soin->scheduled_date, $aujourdhui);
        }

        $bandes = LivestockLot::vivantes()->with('species')->orderBy('code')->get()
            ->filter(fn (LivestockLot $b) => $b->species && in_array($b->species->code, $codesActifs, true));

        foreach ($bandes as $bande) {
            for ($d = 0; $d <= $horizon; $d++) {
                $jour = $aujourdhui->copy()->addDays($d);
                foreach ($this->protocole->pourBande($bande, $jour)->traitements as $t) {
                    if ($t['deja_administre']) {
                        continue;   // un traitement déjà administré n'est plus un rappel : l'afficher ferait redoser
                    }
                    $lignes[] = $this->ligne('prophylaxie', $bande, $t['standard']->treatment, $t['standard']->product_recommended, $jour, $aujourdhui);
                }
            }
        }

        $periodes = VeterinaryWithdrawalPeriod::with('lot.species')
            ->whereDate('end_date', '>=', $aujourdhui->toDateString())
            ->whereDate('end_date', '<=', $aujourdhui->copy()->addDays($horizon)->toDateString())
            ->get();
        foreach ($periodes as $periode) {
            $bande = $periode->lot;
            if (! $bande || $bande->status !== 'actif' || ! $bande->is_active || ! in_array($bande->species?->code, $codesActifs, true)) {
                continue;
            }
            $lignes[] = $this->ligne('remanence', $bande, "Fin du délai d'attente", $periode->product_used, $periode->end_date, $aujourdhui);
        }

        // Comparaisons de chaînes OCTET PAR OCTET (strcmp) : jamais le « numérique » de <=> sur deux chaînes, que le poste
        // ne reproduirait pas.
        usort($lignes, fn ($a, $b) => (self::RANG_URGENCE[$a['urgence']] <=> self::RANG_URGENCE[$b['urgence']])
            ?: strcmp($a['date'], $b['date'])
            ?: strcmp($a['bande'], $b['bande'])
            ?: (self::RANG_TYPE[$a['type']] <=> self::RANG_TYPE[$b['type']])
            ?: strcmp($a['libelle'], $b['libelle']));

        return $lignes;
    }

    /** Une ligne de la fenêtre. */
    private function ligne(string $type, LivestockLot $bande, string $libelle, ?string $produit, \DateTimeInterface $date, Carbon $aujourdhui): array
    {
        $jour = Carbon::instance($date)->startOfDay();
        $jours = (int) round($aujourdhui->diffInDays($jour, false));
        $pluriel = fn (int $n) => $n.' jour'.($n > 1 ? 's' : '');

        return [
            'urgence' => $jours < 0 ? 'retard' : ($jours === 0 ? 'aujourdhui' : 'avenir'),
            'type' => $type,
            'type_libelle' => ['soin' => 'Soin planifié', 'prophylaxie' => 'Barème prophylactique', 'remanence' => "Délai d'attente"][$type],
            'bande' => $bande->code,
            'espece' => (string) $bande->species?->label,
            'libelle' => $libelle,
            'produit' => $produit !== null && trim($produit) !== '' ? $produit : '—',
            'date' => $jour->toDateString(),
            'date_texte' => $jour->format('d/m/Y'),
            'jours' => $jours,
            'echeance' => $jours < 0 ? 'En retard de '.$pluriel(-$jours) : ($jours === 0 ? "Aujourd'hui" : 'Dans '.$pluriel($jours)),
        ];
    }
}
