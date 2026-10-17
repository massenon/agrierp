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
 * "Personnalisez les modèles officiels, puis générez et téléchargez les
 * attestations certifiées au format PDF."
 *
 * ⚠️ EN-TÊTE : écart entre les deux "documents officiels" du prototype
 * lui-même — cet écran affiche IFU 3202601234567 / RCCM RB/ADJ/26 B 0123,
 * alors que `DIRECTIVE_PDF_HEADER_OFFICIEL_ENTETE_EXACT.md` (qui fait foi
 * en cas de divergence, déjà utilisée pour `PdfExportService`, ticket 5.5)
 * indique RCCM RB/PNO/22 A 33870 sans IFU. La directive étant la source
 * la plus fiable (extraite directement d'un document officiel réel),
 * son RCCM est utilisé ici pour rester cohérent avec tous les autres
 * documents officiels du système ; aucun IFU n'est affiché faute de
 * confirmation par la directive — jamais un numéro inventé ou copié
 * d'une valeur de démonstration non confirmée.
 *
 * PDF généré directement (`Barryvdh\DomPDF`, pas via `PdfExportService`)
 * : une attestation est un document autonome au format certificat, pas
 * un rapport tabulaire — sa mise en page ne correspond pas au gabarit
 * partagé `exports/layout.blade.php` (Document 06 §5.2, réservé aux
 * exports tabulaires).
 *
 * Table `attestation_templates` ajoutée, absente du schéma documenté —
 * 2 modèles réels (employé/stagiaire), personnalisation persistée.
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

    public string $tplEmployeText = '';

    public string $tplStagiaireText = '';

    public function mount(): void
    {
        $this->tplEmployeText = AttestationTemplate::forType('employe')->body_text;
        $this->tplStagiaireText = AttestationTemplate::forType('stagiaire')->body_text;
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
            $this->startDate = $person->start_date->format('Y-m-d');
            $this->endDate = $person->end_date?->format('Y-m-d') ?? '';
        }
    }

    public function getPreviewBodyProperty(): string
    {
        $person = $this->selectedPerson;

        if (! $person) {
            return '';
        }

        // ⚠️ TICKET 15.13 — LE TEXTE EST COMPOSÉ PAR `AttestationService`,
        // partagé avec l'API du poste : un seul texte « certifié ».
        return app(AttestationService::class)->corps(
            $this->personType,
            $person,
            $this->contractType,
            $this->startDate ?: null,
            $this->endDate ?: null,
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
            $this->endDate ?: null,
            $this->note ?: null,
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
