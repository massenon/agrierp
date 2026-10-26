<?php

namespace App\Livewire\RH;

use App\Models\AttestationTemplate;
use App\Models\AuditLog;
use App\Models\Employee;
use App\Models\Internship;
use App\Services\AttestationService;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * rh-attestations.html → Livewire\RH\Attestations
 * DERNIER ONGLET DU HUB PERSONNEL & STAGES.
 *
 * PDF généré directement (`Barryvdh\DomPDF`, pas via `PdfExportService`)
 * : une attestation est un document autonome au format certificat, pas
 * un rapport tabulaire — sa mise en page ne correspond pas au gabarit
 * partagé `exports/layout.blade.php` (Document 06 §5.2, réservé aux
 * exports tabulaires).
 */
class Attestations extends Component
{
    #[Url]
    public string $tab = 'generer';

    public string $personType = 'employe';

    public string $personId = '';

    public string $contractType = 'CDI';

    public string $startDate = '';

    public string $endDate = '';

    public string $note = '';

    /** Civilité de la personne — préremplie depuis la fiche, modifiable. */
    public string $civilite = 'M.';

    /** Domaines de formation cochés (4 cases). */
    public array $domaines = [];

    /** Signataires — préremplis depuis le modèle, éditables par attestation. */
    public string $sig1Titre = 'Le Directeur Général';
    public string $sig1Nom   = 'M. Olouchègoun';
    public string $sig2Titre = "L'Examinateur";
    public string $sig2Nom   = '';
    public string $sig3Titre = 'Le Président du Jury';
    public string $sig3Nom   = '';

    public string $tplEmployeText   = '';
    public string $tplStagiaireText = '';

    public function mount(): void
    {
        $tplE = AttestationTemplate::forType('employe');
        $tplS = AttestationTemplate::forType('stagiaire');

        $this->tplEmployeText   = $tplE->body_text;
        $this->tplStagiaireText = $tplS->body_text;

        // Signataires : valeurs par défaut issues du modèle actuel
        $this->sig1Titre = $tplE->sig1_titre ?? 'Le Directeur Général';
        $this->sig1Nom   = $tplE->sig1_nom   ?? 'M. Olouchègoun';
        $this->sig2Titre = $tplE->sig2_titre ?? "L'Examinateur";
        $this->sig2Nom   = $tplE->sig2_nom   ?? '';
        $this->sig3Titre = $tplE->sig3_titre ?? 'Le Président du Jury';
        $this->sig3Nom   = $tplE->sig3_nom   ?? '';
    }

    public function getPeopleProperty()
    {
        return $this->personType === 'employe'
            ? Employee::where('is_active', true)->orderBy('last_name')->get()
            : Internship::orderBy('last_name')->get();
    }

    public function setPersonType(string $type): void
    {
        $this->personType = $type;
        $this->personId = '';
        $this->domaines = [];
        $this->civilite = 'M.';
    }

    public function getSelectedPersonProperty()
    {
        if (! $this->personId) {
            return null;
        }

        return $this->personType === 'employe'
            ? Employee::find($this->personId)
            : Internship::find($this->personId);
    }

    public function updatedPersonId(): void
    {
        $person = $this->selectedPerson;

        if (! $person) {
            return;
        }

        if ($this->personType === 'employe') {
            $this->startDate = $person->hire_date?->format('Y-m-d') ?? '';
            $this->endDate = '';
        } else {
            $this->startDate = $person->start_date?->format('Y-m-d') ?? '';
            $this->endDate = $person->end_date?->format('Y-m-d') ?? '';
            // Pré-remplir la civilité depuis la fiche stagiaire
            $this->civilite = $person->civilite ?? 'M.';
        }
    }

    public function getPreviewBodyProperty(): string
    {
        $person = $this->selectedPerson;

        if (! $person) {
            return '';
        }

        return app(AttestationService::class)->corps(
            $this->personType,
            $person,
            $this->contractType,
            $this->startDate ?: null,
            $this->endDate ?: null,
            $this->civilite,
        );
    }

    public function getPreviewDureeProperty(): string
    {
        if (! $this->startDate) {
            return '';
        }

        return AttestationService::formatDuree(
            $this->startDate ?: null,
            $this->endDate   ?: null,
        );
    }

    public function generateAttestation()
    {
        $this->validate([
            'personId' => ['required'],
        ]);

        $resultat = app(AttestationService::class)->generer(
            $this->personType,
            $this->selectedPerson,
            $this->contractType,
            $this->startDate ?: null,
            $this->endDate   ?: null,
            $this->note      ?: null,
            $this->domaines,
            $this->civilite,
            $this->sig1Nom   ?: null,
            $this->sig1Titre ?: null,
            $this->sig2Nom   ?: null,
            $this->sig2Titre ?: null,
            $this->sig3Nom   ?: null,
            $this->sig3Titre ?: null,
        );

        return response()->streamDownload(
            fn () => print($resultat['octets']),
            $resultat['fichier']
        );
    }

    public function saveTemplate(string $type): void
    {
        $this->authorize('manage-rh');

        $text = $type === 'employe' ? $this->tplEmployeText : $this->tplStagiaireText;

        AttestationTemplate::forType($type)->update(['body_text' => $text]);

        AuditLog::record('attestation_template.updated', 'rh');
        $this->dispatch('toast', message: 'Modèle enregistré avec succès.', type: 'success');
    }

    public function render()
    {
        return view('livewire.rh.attestations');
    }
}
