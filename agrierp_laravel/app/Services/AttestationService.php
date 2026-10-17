<?php

namespace App\Services;

use App\Models\AttestationTemplate;
use App\Models\AuditLog;
use App\Models\Employee;
use App\Models\Internship;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\Carbon;
use Illuminate\Support\Str;

/**
 * Ticket 15.13 — ATTESTATIONS DE TRAVAIL ET DE STAGE : UNE SEULE FABRIQUE.
 *
 * Extrait de `Livewire\RH\Attestations` pour que la page web ET `POST
 * /api/attestations` (le poste Flutter) composent le MÊME texte et produisent le
 * MÊME PDF. L'attestation est un document officiel : deux implémentations qui
 * divergent d'une virgule donneraient deux textes « certifiés » différents.
 *
 * ⚠️ LE PDF EST PRODUIT ICI, JAMAIS AU POSTE. Il porte l'en-tête de la ferme, son
 * RCCM, la mention du Directeur Général : des éléments d'identité qui n'ont pas à
 * être recopiés sur chaque machine. Et la génération laisse sa TRACE d'audit
 * (`attestation.generated.employe|stagiaire`) — le compteur « Attestations
 * émises » du registre des stagiaires n'est que ce décompte.
 */
class AttestationService
{
    public const TYPES = ['employe', 'stagiaire'];

    public function titre(string $type): string
    {
        return $type === 'employe' ? 'Attestation de Travail' : 'Attestation de Stage';
    }

    public function personne(string $type, string $id): Employee|Internship|null
    {
        return $type === 'employe' ? Employee::find($id) : Internship::find($id);
    }

    /**
     * Texte du certificat : le modèle, balises remplacées.
     *
     * ⚠️ « ce jour » quand il n'y a pas de date de fin : un CDI n'a pas de fin, et
     * « du 01/03/2024 au  » serait une phrase brisée sur un document officiel.
     */
    public function corps(string $type, Employee|Internship $personne, string $contrat, ?string $debut, ?string $fin): string
    {
        $modele = AttestationTemplate::forType($type)->body_text;
        $nom = $personne->last_name.' '.$personne->first_name;
        $d = $debut ? Carbon::parse($debut)->format('d/m/Y') : '';
        $f = $fin ? Carbon::parse($fin)->format('d/m/Y') : 'ce jour';

        $remplacements = $type === 'employe'
            ? [
                '[NOM]' => $nom,
                '[POSTE]' => $personne->position ?? '',
                '[CONTRAT]' => $contrat,
                '[DATE_DEBUT]' => $d,
                '[DATE_FIN]' => $f,
            ]
            : [
                '[NOM]' => $nom,
                '[SPECIALITE]' => $personne->school ?? '',
                '[ETABLISSEMENT]' => $personne->school ?? '',
                '[DATE_DEBUT]' => $d,
                '[DATE_FIN]' => $f,
            ];

        return strtr($modele, $remplacements);
    }

    /**
     * Génère le PDF ET journalise la génération.
     *
     * @return array{octets: string, fichier: string}
     */
    public function generer(string $type, Employee|Internship $personne, string $contrat, ?string $debut, ?string $fin, ?string $note): array
    {
        $nom = $personne->last_name.' '.$personne->first_name;

        AuditLog::record('attestation.generated.'.$type, 'rh');

        $pdf = Pdf::loadView('exports.attestation', [
            'title' => $this->titre($type),
            'body' => $this->corps($type, $personne, $contrat, $debut, $fin),
            'note' => $note,
            'date' => now()->format('d/m/Y'),
        ])->setPaper('a4', 'landscape');

        return [
            'octets' => $pdf->output(),
            'fichier' => 'attestation-'.Str::slug($nom).'.pdf',
        ];
    }

    /**
     * Nombre d'attestations générées, par type, sur TOUT l'historique d'audit.
     *
     * ⚠️ PAS DE BORNE : le poste ne détient que les cent dernières lignes d'audit
     * de la ferme ; ce décompte, lui, porte sur la table entière.
     *
     * @return array{employe: int, stagiaire: int}
     */
    public function compteurs(): array
    {
        return [
            'employe' => AuditLog::where('action', 'attestation.generated.employe')->count(),
            'stagiaire' => AuditLog::where('action', 'attestation.generated.stagiaire')->count(),
        ];
    }
}
