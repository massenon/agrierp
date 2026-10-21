<?php

namespace App\Services;

use App\Models\Animal;
use Illuminate\Support\Collection;

/**
 * Ticket 15.14 — LA FICHE D'UN SUJET : UNE SEULE FABRIQUE.
 *
 * Extrait de `Livewire\Elevage\AnimalDetails` pour que la page web ET l'export PDF
 * servi au poste (`GET /api/animals/{id}/pdf`) racontent la même histoire du sujet.
 * Les règles — chacune a sa raison — sont celles du ticket 14.16, inchangées.
 *
 * ⚠️ RIEN N'EST FABRIQUÉ. Un mouvement, une saillie, un soin y figurent parce
 * qu'ils ont été SAISIS. Aucun historique de cage n'est modélisé : en inventer un
 * afficherait des lignes que personne n'a jamais écrites.
 */
class AnimalFicheService
{
    /** Événements de reproduction : mère OU géniteur, par correspondance de référence. */
    public function reproduction(Animal $animal): Collection
    {
        return $animal->reproductionEvents()->get();
    }

    /**
     * Soins de la BANDE du sujet.
     *
     * ⚠️ `veterinary_records` est rattaché au lot, jamais au sujet : la prophylaxie
     * est administrée par bande sur cette ferme. Ces soins concernent le sujet, ils
     * ne sont pas des traitements individuels — et l'écran le dit.
     */
    public function soins(Animal $animal): Collection
    {
        return $animal->lot_id ? $animal->lotVeterinaryRecords()->get() : collect();
    }

    /**
     * Mouvements réels : l'entrée, et la sortie si elle a eu lieu.
     *
     * @return array<int, array{date: string, libelle: string, detail: string}>
     */
    public function mouvements(Animal $animal): array
    {
        $mouvements = [[
            'date' => $animal->entry_date->format('Y-m-d'),
            'libelle' => 'Entrée en élevage',
            'detail' => $animal->origin ?: 'Origine non précisée',
        ]];

        if ($animal->exit_date) {
            $mouvements[] = [
                'date' => $animal->exit_date->format('Y-m-d'),
                'libelle' => 'Sortie — '.$animal->status_label,
                'detail' => $animal->exit_reason ?: 'Motif non précisé',
            ];
        }

        return $mouvements;
    }

    /**
     * Historique consolidé, du plus récent au plus ancien.
     *
     * @return array<int, array{date: string, type: string, libelle: string}>
     */
    public function historique(Animal $animal): array
    {
        $lignes = [];

        foreach ($this->mouvements($animal) as $m) {
            $lignes[] = ['date' => $m['date'], 'type' => 'Mouvement', 'libelle' => $m['libelle'].' — '.$m['detail']];
        }

        foreach ($this->reproduction($animal) as $e) {
            $lignes[] = [
                'date' => $e->saillie_date->format('Y-m-d'),
                'type' => 'Reproduction',
                'libelle' => 'Saillie'.($e->mise_bas_date_actual ? ' — mise bas le '.$e->mise_bas_date_actual->format('d/m/Y') : ' (en cours)'),
            ];
        }

        foreach ($this->soins($animal) as $v) {
            $lignes[] = [
                'date' => $v->record_date->format('Y-m-d'),
                'type' => 'Soin (bande)',
                'libelle' => $v->action_type.($v->product_used ? ' — '.$v->product_used : ''),
            ];
        }

        usort($lignes, fn ($a, $b) => strcmp($b['date'], $a['date']));

        return $lignes;
    }

    /**
     * Données de l'export PDF « Fiche Sujet ».
     *
     * @return array{animal: Animal, reproduction: Collection, soins: Collection, mouvements: array}
     */
    public function donneesPdf(Animal $animal): array
    {
        return [
            'animal' => $animal,
            'reproduction' => $this->reproduction($animal),
            'soins' => $this->soins($animal),
            'mouvements' => $this->mouvements($animal),
        ];
    }
}
