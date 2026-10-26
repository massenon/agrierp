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
 * Ticket 15.13 / ATT-1 — ATTESTATIONS DE TRAVAIL ET DE STAGE : UNE SEULE FABRIQUE.
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

    /** Domaines de formation cochables dans l'attestation officielle. */
    public const DOMAINES = [
        'maraichage' => 'Maraîchage',
        'elevage'    => 'Élevage',
        'rations'    => 'Rations alimentaires',
        'gestion'    => "Gestion d'entreprise",
    ];

    public function titre(string $type): string
    {
        return $type === 'employe' ? 'Attestation de Travail' : 'Attestation de Formation';
    }

    public function personne(string $type, string $id): Employee|Internship|null
    {
        return $type === 'employe' ? Employee::find($id) : Internship::find($id);
    }

    /**
     * Texte du certificat : le modèle, balises remplacées.
     *
     * Balises disponibles :
     * - [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN]  (employe)
     * - [NOM], [SPECIALITE], [ETABLISSEMENT], [DATE_DEBUT], [DATE_FIN]  (stagiaire)
     * - [DUREE]  → « six (06) mois », « un (01) an et trois (03) mois »…
     * - [CIVILITE]  → « M. » ou « Mme »
     * - [TITRE_NOM]  → « Monsieur NOM » ou « Madame NOM »
     * - [ACCORD_E]  → « » (masculin) ou « e » (féminin)
     * - [DATE_NAISSANCE], [LIEU_NAISSANCE]  (stagiaire)
     *
     * ⚠️ « ce jour » quand il n'y a pas de date de fin : un CDI n'a pas de fin, et
     * « du 01/03/2024 au  » serait une phrase brisée sur un document officiel.
     */
    public function corps(
        string $type,
        Employee|Internship $personne,
        string $contrat,
        ?string $debut,
        ?string $fin,
        string $civilite = 'M.',
    ): string {
        $modele = AttestationTemplate::forType($type)->body_text;
        $nom = $personne->last_name.' '.$personne->first_name;
        $d = $debut ? Carbon::parse($debut)->format('d/m/Y') : '';
        $f = $fin ? Carbon::parse($fin)->format('d/m/Y') : 'ce jour';
        $titreNom = ($civilite === 'Mme' ? 'Madame' : 'Monsieur').' '.$nom;
        $accordE = $civilite === 'Mme' ? 'e' : '';

        $remplacements = [
            '[NOM]'        => $nom,
            '[CIVILITE]'   => $civilite,
            '[TITRE_NOM]'  => $titreNom,
            '[ACCORD_E]'   => $accordE,
            '[DATE_DEBUT]' => $d,
            '[DATE_FIN]'   => $f,
            '[DUREE]'      => static::formatDuree($debut, $fin),
        ];

        if ($type === 'employe') {
            $remplacements += [
                '[POSTE]'   => $personne->position ?? '',
                '[CONTRAT]' => $contrat,
            ];
        } else {
            $naissance = $personne instanceof Internship
                ? ($personne->birth_date?->format('d/m/Y') ?? '')
                : '';
            $remplacements += [
                '[SPECIALITE]'     => $personne->school ?? '',
                '[ETABLISSEMENT]'  => $personne->school ?? '',
                '[DATE_NAISSANCE]' => $naissance,
                '[LIEU_NAISSANCE]' => ($personne instanceof Internship ? $personne->birth_place : '') ?? '',
            ];
        }

        return strtr($modele, $remplacements);
    }

    /**
     * Génère le PDF ET journalise la génération.
     *
     * Les signataires sont éditables par attestation (valeurs par défaut issues
     * du modèle). Les domaines et la civilité sont spécifiques à chaque émission.
     *
     * @return array{octets: string, fichier: string}
     */
    public function generer(
        string $type,
        Employee|Internship $personne,
        string $contrat,
        ?string $debut,
        ?string $fin,
        ?string $note,
        array $domaines = [],
        string $civilite = 'M.',
        ?string $sig1Nom = null,
        ?string $sig1Titre = null,
        ?string $sig2Nom = null,
        ?string $sig2Titre = null,
        ?string $sig3Nom = null,
        ?string $sig3Titre = null,
    ): array {
        $nom = $personne->last_name.' '.$personne->first_name;
        $numero = $this->prochainNumero();

        AuditLog::record('attestation.generated.'.$type, 'rh');

        $tpl = AttestationTemplate::forType($type);

        $moisFr = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
                   'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
        $now = now();
        $dateLieu = $now->day.' '.$moisFr[$now->month - 1].' '.$now->year;

        $pdf = Pdf::loadView('exports.attestation', [
            'title'     => $this->titre($type),
            'body'      => $this->corps($type, $personne, $contrat, $debut, $fin, $civilite),
            'note'      => $note,
            'numero'    => $numero,
            'dateLieu'  => $dateLieu,
            'domaines'  => $domaines,
            'sig1Titre' => $sig1Titre ?? $tpl->sig1_titre ?? 'Le Directeur Général',
            'sig1Nom'   => $sig1Nom   ?? $tpl->sig1_nom   ?? 'M. Olouchègoun',
            'sig2Titre' => $sig2Titre ?? $tpl->sig2_titre ?? "L'Examinateur",
            'sig2Nom'   => $sig2Nom   ?? $tpl->sig2_nom   ?? '',
            'sig3Titre' => $sig3Titre ?? $tpl->sig3_titre ?? 'Le Président du Jury',
            'sig3Nom'   => $sig3Nom   ?? $tpl->sig3_nom   ?? '',
        ])->setPaper('a4', 'landscape');

        return [
            'octets'  => $pdf->output(),
            'fichier' => 'attestation-'.Str::slug($nom).'.pdf',
        ];
    }

    /**
     * Prochain numéro de référence au format `N°04/2026/FEO/DG`.
     * Compte toutes les attestations déjà émises cette année (tous types confondus).
     */
    public function prochainNumero(): string
    {
        $annee = now()->year;
        $seq = AuditLog::where('action', 'like', 'attestation.generated.%')
            ->whereYear('created_at', $annee)
            ->count() + 1;

        return sprintf('N°%02d/%d/FEO/DG', $seq, $annee);
    }

    /**
     * Durée grammaticalement correcte entre deux dates.
     *
     * Exemples : « six (06) mois », « un (01) an », « un (01) an et trois (03) mois »,
     * « dix-huit (18) mois ».
     * ⚠️ « an » (jamais « ans ») pour 1 an exactement.
     */
    public static function formatDuree(?string $debut, ?string $fin): string
    {
        if (! $debut) {
            return '';
        }

        $d = Carbon::parse($debut);
        $f = $fin ? Carbon::parse($fin) : now();
        $totalMois = (int) $d->diffInMonths($f);

        if ($totalMois <= 0) {
            return '';
        }

        $ans  = intdiv($totalMois, 12);
        $mois = $totalMois % 12;
        $parties = [];

        if ($ans > 0) {
            $unite = $ans === 1 ? 'an' : 'ans';
            $parties[] = static::motNombre($ans).' ('.str_pad((string) $ans, 2, '0', STR_PAD_LEFT).') '.$unite;
        }

        if ($mois > 0) {
            $parties[] = static::motNombre($mois).' ('.str_pad((string) $mois, 2, '0', STR_PAD_LEFT).') mois';
        }

        return implode(' et ', $parties);
    }

    /** Nombre en lettres françaises (1–24). */
    private static function motNombre(int $n): string
    {
        return [
            1 => 'un', 2 => 'deux', 3 => 'trois', 4 => 'quatre', 5 => 'cinq',
            6 => 'six', 7 => 'sept', 8 => 'huit', 9 => 'neuf', 10 => 'dix',
            11 => 'onze', 12 => 'douze', 13 => 'treize', 14 => 'quatorze',
            15 => 'quinze', 16 => 'seize', 17 => 'dix-sept', 18 => 'dix-huit',
            19 => 'dix-neuf', 20 => 'vingt', 21 => 'vingt et un',
            22 => 'vingt-deux', 23 => 'vingt-trois', 24 => 'vingt-quatre',
        ][$n] ?? (string) $n;
    }

    /**
     * Nombre d'attestations générées, par type, sur TOUT l'historique d'audit.
     *
     * @return array{employe: int, stagiaire: int}
     */
    public function compteurs(): array
    {
        return [
            'employe'   => AuditLog::where('action', 'attestation.generated.employe')->count(),
            'stagiaire' => AuditLog::where('action', 'attestation.generated.stagiaire')->count(),
        ];
    }
}
