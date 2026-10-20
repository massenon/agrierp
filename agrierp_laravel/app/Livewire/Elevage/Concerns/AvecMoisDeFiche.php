<?php

namespace App\Livewire\Elevage\Concerns;

use App\Models\FiscalYear;
use App\Support\ExerciceChoisi;
use Carbon\Carbon;

/**
 * 🔴→✅ Ticket EX8 (EF12, PRD `docs/prd/exercices-comptables.md` § 4) — LE MOIS AFFICHÉ D'UNE FICHE D'ÉLEVAGE.
 *
 * Les cinq fiches (Pondeuses, Reproducteurs, Lapins, Porcs, Escargots) ne montraient que le mois civil EN COURS
 * (`now()->startOfMonth()` partout : tableau mensuel, cartes du mois, soins du mois, PDF) : une fois en 2027, les fiches
 * de 2026 n'étaient plus consultables. Le mois affiché est désormais celui du JOUR CHOISI (`selectedDate`) :
 *  - « ‹ » (`moisPrecedent`) : premier jour du mois précédent ;
 *  - « › » (`moisSuivant`) : premier jour du mois suivant — le jour même quand c'est le mois en cours ; jamais au-delà
 *    du mois en cours ;
 *  - choisir une date d'un autre mois y amène le tableau.
 * Le jour se charge par `loadDay()` de chaque fiche, qui relit la fiche de n'importe quel jour (U11, U12a) : une fiche
 * existante n'est jamais remise à zéro.
 *
 * Lecture seule (`motifLectureSeule`) : un jour d'un exercice CLOS se consulte, mais le formulaire est grisé ; le bandeau
 * est celui d'EX7 (`x-bandeau-lecture-seule`, fusion EX7 + EX8), jugé sur l'exercice du JOUR CHOISI. Le refus de
 * `saveDay` (message R4 du serveur, EX5) reste la garantie.
 *
 * Exige du composant : `public string $selectedDate` et `loadDay(string $date)`.
 */
trait AvecMoisDeFiche
{
    /** Premier jour du mois affiché : celui du jour choisi, le mois en cours si la date est illisible. */
    public function debutMoisFiche(): Carbon
    {
        $jour = preg_match('/^\d{4}-\d{2}-\d{2}$/', (string) $this->selectedDate) === 1
            ? Carbon::createFromFormat('!Y-m-d', $this->selectedDate)
            : null;

        return ($jour ?: now())->copy()->startOfMonth();
    }

    public function finMoisFiche(): Carbon
    {
        return $this->debutMoisFiche()->endOfMonth();
    }

    /** « Septembre 2026 » — en-tête de la navigation de mois. */
    public function getLibelleMoisProperty(): string
    {
        return ucfirst($this->debutMoisFiche()->translatedFormat('F Y'));
    }

    /** Le mois affiché est-il le mois en cours ? (« › » grisé : pas de mois à venir.) */
    public function getEstMoisCourantProperty(): bool
    {
        return $this->moisCourant();
    }

    /**
     * ⚠️ Jamais la propriété calculée dans une action : Livewire MÉMORISE une propriété `getXProperty` pour toute la
     * requête — lue dans `moisSuivant()` AVANT de changer de mois, elle restait « faux » au rendu qui suit, et « › »
     * restait actif une fois revenu sur le mois en cours.
     */
    private function moisCourant(): bool
    {
        return $this->debutMoisFiche()->format('Y-m') >= now()->format('Y-m');
    }

    public function moisPrecedent(): void
    {
        $this->loadDay($this->debutMoisFiche()->subMonthNoOverflow()->format('Y-m-d'));
    }

    public function moisSuivant(): void
    {
        if ($this->moisCourant()) {
            return;
        }

        $suivant = $this->debutMoisFiche()->addMonthNoOverflow();
        $this->loadDay($suivant->format('Y-m') === now()->format('Y-m') ? now()->format('Y-m-d') : $suivant->format('Y-m-d'));
    }

    /** Jours du tableau mensuel : du 1er au dernier jour du mois affiché. */
    public function getDaysInMonthProperty(): array
    {
        return range(1, $this->debutMoisFiche()->daysInMonth);
    }

    /**
     * Motif de la lecture seule (exercice du JOUR CHOISI clos), ou `null` quand le jour se saisit : grise le formulaire
     * (`<fieldset disabled>`) et « Enregistrer ce Jour » (info-bulle). Fusion EX7 + EX8 : le motif d'EX7
     * (`ExerciceChoisi::motifLectureSeuleDe`, « Exercice 2026 clôturé — lecture seule »), jugé sur l'exercice du jour et
     * non sur l'exercice affiché (EX-Q8) ; le refus de `saveDay` garde le message R4 du serveur (EX5).
     */
    public function getMotifLectureSeuleProperty(): ?string
    {
        $exercice = $this->exerciceDuJourChoisi();

        return $exercice === null ? null : ExerciceChoisi::motifLectureSeuleDe($exercice);
    }

    /**
     * Le bandeau de lecture seule de la fiche — celui d'EX7, même texte (`ExerciceChoisi::bandeauDe`), pour l'exercice
     * du jour choisi. `null` aussi quand l'exercice du jour EST l'exercice affiché : le bandeau du haut de page dit déjà
     * la même chose (jamais deux fois le même bandeau).
     *
     * @return array{texte: string, cible: ?int}|null
     */
    public function getBandeauLectureSeuleProperty(): ?array
    {
        $exercice = $this->exerciceDuJourChoisi();
        if ($exercice === null || ExerciceChoisi::exercice()?->is($exercice)) {
            return null;
        }

        return ExerciceChoisi::bandeauDe($exercice);
    }

    /**
     * « Passer à 2027 » du bandeau de la fiche : le jour de saisie de l'exercice cible (aujourd'hui s'il le contient —
     * `ExerciceChoisi::arreteDe`), jamais au-delà d'aujourd'hui (pas de mois à venir, comme « › »). L'exercice affiché
     * ne change pas (la fiche ne le lit pas, EX-Q8).
     */
    public function passerALExerciceDeSaisie(): void
    {
        $exercice = $this->exerciceDuJourChoisi();
        $cible = $exercice === null ? null : (ExerciceChoisi::bandeauDe($exercice)['cible'] ?? null);
        if ($cible === null) {
            return;
        }

        $this->loadDay(min(ExerciceChoisi::arreteDe($cible), now()->format('Y-m-d')));
    }

    private function exerciceDuJourChoisi(): ?FiscalYear
    {
        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', (string) $this->selectedDate) !== 1) {
            return null;
        }

        return ExerciceChoisi::exerciceDuJour($this->selectedDate);
    }

    /** Sous-titre et nom du PDF « Exporter PDF » : le mois affiché (`septembre 2026`, `fiche-2026-09.pdf`). */
    protected function moisDuPdf(): string
    {
        return $this->debutMoisFiche()->translatedFormat('F Y');
    }

    protected function fichierDuPdf(): string
    {
        return 'fiche-'.$this->debutMoisFiche()->format('Y-m').'.pdf';
    }
}
