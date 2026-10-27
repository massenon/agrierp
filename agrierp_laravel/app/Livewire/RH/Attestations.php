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

    /**
     * Signataires de CETTE attestation : `sig1` (Directeur Général), `sig2` (Examinateur), `sig3` (Président du Jury),
     * chacun `titre` / `nom` / `fonction`. Un champ laissé vide reprend le modèle (placeholder) — rien n'est
     * prérempli : changer le modèle ou la durée change donc aussi ce qui s'imprime, sans valeur périmée dans le formulaire.
     *
     * @var array<string, array<string, string>>
     */
    public array $sigs = [];

    /**
     * Règle de signature de chaque modèle (ATT-2) : seuil en mois, signataires, qui signe le palier court / long,
     * appréciation par défaut. Modifiable dans « Personnaliser les Modèles ».
     *
     * @var array<string, array<string, mixed>>
     */
    public array $reglage = [];

    public string $tplEmployeText   = '';
    public string $tplStagiaireText = '';

    public function mount(): void
    {
        $tplE = AttestationTemplate::forType('employe');
        $tplS = AttestationTemplate::forType('stagiaire');

        $this->tplEmployeText   = $tplE->body_text;
        $this->tplStagiaireText = $tplS->body_text;

        foreach (AttestationService::TYPES as $type) {
            $champs = AttestationTemplate::forType($type)->pourLePoste();
            unset($champs['id'], $champs['type'], $champs['body_text']);
            $this->reglage[$type] = $champs;
        }
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
            type: $this->personType,
            personne: $this->selectedPerson,
            contrat: $this->contractType,
            debut: $this->startDate ?: null,
            fin: $this->endDate ?: null,
            note: $this->note ?: null,
            domaines: $this->domaines,
            civilite: $this->civilite,
            signataires: $this->surcharges(),
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

    /** Les surcharges saisies pour cette attestation (champs vides ignorés : ils reprennent le modèle). */
    public function surcharges(): array
    {
        $surcharges = [];

        foreach ($this->sigs as $cle => $champs) {
            foreach (['titre', 'nom', 'fonction'] as $champ) {
                $valeur = trim((string) ($champs[$champ] ?? ''));

                if ($valeur !== '') {
                    $surcharges[$cle][$champ] = $valeur;
                }
            }
        }

        return $surcharges;
    }

    /** Palier de durée de l'attestation en cours (« court » : le promoteur seul ; « long » : trois signataires). */
    public function getPalierProperty(): string
    {
        return AttestationService::palier(
            $this->startDate ?: null,
            $this->endDate ?: null,
            (int) ($this->reglage[$this->personType]['seuil_signature_mois'] ?? 12),
        );
    }

    /** Les signataires que la durée appelle, tels qu'ils s'imprimeront. */
    public function getSignatairesRequisProperty(): array
    {
        return app(AttestationService::class)->signataires(
            $this->personType,
            $this->startDate ?: null,
            $this->endDate ?: null,
            $this->surcharges(),
        );
    }

    public function getPreviewAppreciationProperty(): ?string
    {
        $person = $this->selectedPerson;

        if (! $person) {
            return null;
        }

        $texte = app(AttestationService::class)->appreciation(
            $this->personType,
            $person,
            $this->note ?: null,
            $this->startDate ?: null,
            $this->endDate ?: null,
            $this->civilite,
        );

        return $texte === null ? null : AttestationService::sansMarques($texte);
    }

    /**
     * Enregistre la règle de signature et les signataires d'un modèle (ATT-2).
     * Les mêmes champs, les mêmes limites que `PUT /api/attestation-templates/{type}` (le poste).
     */
    public function saveReglage(string $type): void
    {
        $this->authorize('manage-rh');
        abort_unless(in_array($type, AttestationService::TYPES, true), 404);

        $regles = [
            "reglage.{$type}.seuil_signature_mois" => ['required', 'integer', 'min:1', 'max:120'],
            "reglage.{$type}.appreciation_text" => ['nullable', 'string', 'max:1000'],
        ];
        foreach ([1, 2, 3] as $n) {
            $regles["reglage.{$type}.sig{$n}_titre"] = ['nullable', 'string', 'max:120'];
            $regles["reglage.{$type}.sig{$n}_nom"] = ['nullable', 'string', 'max:160'];
            $regles["reglage.{$type}.sig{$n}_fonction"] = ['nullable', 'string', 'max:300'];
        }

        $this->validate($regles, [
            "reglage.{$type}.seuil_signature_mois.required" => 'Indiquez la durée en mois.',
            "reglage.{$type}.seuil_signature_mois.min" => "La durée doit être d'au moins 1 mois.",
            "reglage.{$type}.seuil_signature_mois.max" => 'La durée ne peut pas dépasser 120 mois.',
            "reglage.{$type}.seuil_signature_mois.integer" => 'La durée est un nombre entier de mois.',
        ]);

        $r = $this->reglage[$type];
        $champs = [
            'seuil_signature_mois' => (int) $r['seuil_signature_mois'],
            'appreciation_text' => ($r['appreciation_text'] ?? '') === '' ? null : $r['appreciation_text'],
            'appreciation_imprimee' => (bool) ($r['appreciation_imprimee'] ?? true),
        ];
        foreach ([1, 2, 3] as $n) {
            foreach (['titre', 'nom', 'fonction'] as $champ) {
                $champs["sig{$n}_{$champ}"] = (string) ($r["sig{$n}_{$champ}"] ?? '');
            }
            $champs["sig{$n}_court"] = (bool) ($r["sig{$n}_court"] ?? false);
            $champs["sig{$n}_long"] = (bool) ($r["sig{$n}_long"] ?? false);
        }

        AttestationTemplate::forType($type)->update($champs);

        AuditLog::record('attestation_template.updated', 'rh');
        $this->dispatch('toast', message: 'Règle de signature enregistrée.', type: 'success');
    }

    public function render()
    {
        return view('livewire.rh.attestations');
    }
}
