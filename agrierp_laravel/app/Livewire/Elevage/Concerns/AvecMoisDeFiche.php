<?php

namespace App\Livewire\Elevage\Concerns;

use App\Services\AccountingEntryService;
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
 * Lecture seule (`motifLectureSeule`) : un jour d'un exercice CLOS se consulte, mais le formulaire est grisé avec le
 * motif R4 du serveur (`AccountingEntryService::refusExerciceClos`, le refus qu'applique déjà `saveDay`, EX5).
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
        return $this->debutMoisFiche()->format('Y-m') >= now()->format('Y-m');
    }

    public function moisPrecedent(): void
    {
        $this->loadDay($this->debutMoisFiche()->subMonthNoOverflow()->format('Y-m-d'));
    }

    public function moisSuivant(): void
    {
        if ($this->estMoisCourant) {
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

    /** Motif de la lecture seule (exercice clos, message R4), ou `null` quand le jour se saisit. */
    public function getMotifLectureSeuleProperty(): ?string
    {
        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', (string) $this->selectedDate) !== 1) {
            return null;
        }

        return app(AccountingEntryService::class)->refusExerciceClos($this->selectedDate);
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
