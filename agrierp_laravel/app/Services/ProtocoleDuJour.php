<?php

namespace App\Services;

use Illuminate\Support\Collection;

/**
 * Ce que le serveur sait dire du protocole d'une bande à une date donnée.
 *
 * ⚠️ L'INDÉTERMINATION EST UNE RÉPONSE, PAS UNE LISTE VIDE. Une liste vide se
 * lit « rien de prévu aujourd'hui » ; or le jour de cycle peut être impossible
 * à calculer (bande en reproduction sans saillie connue). Confondre les deux
 * ferait sauter un traitement sans que personne ne s'en aperçoive — même
 * principe que `ProtocoleDuJour` au poste (F0.12).
 */
final class ProtocoleDuJour
{
    /**
     * @param  Collection<int, array{standard: \App\Models\ProphylaxisScheduleStandard, deja_administre: bool}>  $traitements
     */
    public function __construct(
        public readonly Collection $traitements,
        public readonly ?int $jourDeCycle,
        public readonly ?string $motifIndetermine,
        public readonly int $calendairesNonEvalues,
    ) {}

    public function determinable(): bool
    {
        return $this->jourDeCycle !== null;
    }

    /** Traitements dus et pas encore consignés au registre vétérinaire. */
    public function enAttente(): int
    {
        return $this->traitements->where('deja_administre', false)->count();
    }

    /** Libellé d'état de la section — quatre états, dont « Indéterminé » que la maquette ne connaît pas. */
    public function etat(): string
    {
        if (! $this->determinable()) {
            return 'Indéterminé';
        }

        if ($this->traitements->isEmpty()) {
            return 'Libre';
        }

        return $this->enAttente() === 0
            ? 'Validé / Effectué'
            : $this->traitements->count().' Prévu(s)';
    }
}
