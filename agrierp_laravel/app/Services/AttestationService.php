<?php

namespace App\Services;

use App\Models\AttestationEmission;
use App\Models\AttestationTemplate;
use App\Models\AuditLog;
use App\Models\Employee;
use App\Models\Internship;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Str;

/**
 * Ticket 15.13 / ATT-1 — ATTESTATIONS DE TRAVAIL ET DE STAGE : UNE SEULE FABRIQUE.
 *
 * Extrait de `Livewire\RH\Attestations` pour que la page web ET `POST
 * /api/attestations` (le poste Flutter) composent le MÊME texte et produisent le
 * MÊME PDF. L'attestation est un document officiel : deux implémentations qui
 * divergent d'une virgule donneraient deux textes « certifiés » différents.
 *
 * ⚠️ LE PDF DU WEB EST PRODUIT ICI ; LE POSTE FABRIQUE LE SIEN (ATT-3, hors ligne comprise) et ne fait que déclarer son
 * émission (`emettre()`) : le SERVEUR reste l'autorité du numéro et de la trace. Le PDF porte l'en-tête de la ferme, son
 * RCCM, la mention du Directeur Général : des éléments d'identité qui n'ont pas à
 * être recopiés sur chaque machine. Et la génération laisse sa TRACE d'audit
 * (`attestation.generated.employe|stagiaire`) — le compteur « Attestations
 * émises » du registre des stagiaires n'est que ce décompte.
 */
class AttestationService
{
    public const TYPES = ['employe', 'stagiaire'];

    /** Domaines de formation cochables dans l'attestation officielle (libellés de l'écran). */
    public const DOMAINES = [
        'maraichage' => 'Maraîchage',
        'elevage'    => 'Élevage',
        'rations'    => 'Rations alimentaires',
        'gestion'    => "Gestion d'entreprise",
    ];

    /**
     * Les mêmes domaines tels que le modèle officiel les imprime : une ligne à puce (➢) par domaine coché,
     * dans cet ordre (modèle fourni par le client, attestation de formation du 24/10/2026).
     */
    public const DOMAINES_PUCES = [
        'maraichage' => "Conduite de cultures maraîchères et vivrières (Mais, Manioc, Soja, Tomate, Piment, Légumes divers) ;",
        'elevage'    => "Conduite d'élevages et applications de soins vétérinaires (Cuniculture, Aviculture, Héliciculture, Porciculture, Petits Ruminant) ;",
        'rations'    => "Notion de formulation des rations alimentaires des animaux d'élevage ;",
        'gestion'    => 'Notion de gestion des entreprises agricoles.',
    ];

    /** `entity_type` de la ligne d'audit d'une attestation fabriquée au poste (`entity_id` = identifiant d'émission du poste). */
    public const ENTITE_EMISSION = 'attestation_emission';

    public const PALIER_COURT = 'court';

    public const PALIER_LONG = 'long';

    /** Ordre d'impression des signataires, de gauche à droite : Examinateur (2), Président du Jury (3), Directeur Général (1). */
    public const ORDRE_SIGNATURES = [2, 3, 1];

    private const MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
        'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

    public function titre(string $type): string
    {
        return $type === 'employe' ? 'Attestation de Travail' : 'Attestation de Formation';
    }

    public function personne(string $type, string $id): Employee|Internship|null
    {
        return $type === 'employe' ? Employee::find($id) : Internship::find($id);
    }

    /**
     * Texte du certificat : le modèle, balises remplacées, SANS les marques de gras (`**`).
     *
     * C'est le texte de l'aperçu (web et poste) et celui que lisent les tests ; le PDF, lui, imprime
     * `corpsMarque()` (gras et vert du modèle officiel).
     *
     * Balises disponibles :
     * - [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN]  (employe)
     * - [NOM], [SPECIALITE], [ETABLISSEMENT], [DATE_DEBUT], [DATE_FIN]  (stagiaire)
     * - [DUREE]  → « six (06) mois », « un (01) an et trois (03) mois »…
     * - [DE_DUREE]  → « d'un (01) an », « de six (06) mois » (avec son espace d'attache ; vide sans durée)
     * - [DATE_DEBUT_LONGUE], [DATE_FIN_LONGUE], [DATE_NAISSANCE_LONGUE]  → « 15 octobre 2025 »
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
        return str_replace('**', '', $this->corpsMarque($type, $personne, $contrat, $debut, $fin, $civilite));
    }

    /** Le texte du modèle, balises remplacées, marques `**gras**` conservées (entrée du PDF). */
    public function corpsMarque(
        string $type,
        Employee|Internship $personne,
        string $contrat,
        ?string $debut,
        ?string $fin,
        string $civilite = 'M.',
    ): string {
        return $this->remplacer(
            AttestationTemplate::forType($type)->body_text,
            $type, $personne, $contrat, $debut, $fin, $civilite,
        );
    }

    /**
     * Phrase d'appréciation du document : la saisie de l'émetteur, sinon celle du modèle
     * (`appreciation_text`, phrase standard du modèle fourni pour une formation). `null` = rien à imprimer.
     * Les marques `**gras**` sont CONSERVÉES (le nom y est en gras, comme au modèle) : `enHtml()` pour le PDF,
     * `sansMarques()` pour un aperçu.
     * ⚠️ Un modèle dont `appreciation_imprimee` est faux n'imprime que ce que l'émetteur saisit.
     */
    public function appreciation(
        string $type,
        Employee|Internship $personne,
        ?string $saisie,
        ?string $debut,
        ?string $fin,
        string $civilite = 'M.',
    ): ?string {
        if ($saisie !== null && trim($saisie) !== '') {
            return trim($saisie);
        }

        $tpl = AttestationTemplate::forType($type);

        if (! $tpl->appreciation_imprimee) {
            return null;
        }

        $texte = $tpl->appreciation_text ?? ($type === 'stagiaire' ? AttestationTemplate::APPRECIATION_STAGIAIRE : '');

        if (trim($texte) === '') {
            return null;
        }

        return $this->remplacer($texte, $type, $personne, '', $debut, $fin, $civilite);
    }

    private function remplacer(
        string $modele,
        string $type,
        Employee|Internship $personne,
        string $contrat,
        ?string $debut,
        ?string $fin,
        string $civilite,
    ): string {
        $nom = $personne->last_name.' '.$personne->first_name;
        $d = $debut ? Carbon::parse($debut)->format('d/m/Y') : '';
        $f = $fin ? Carbon::parse($fin)->format('d/m/Y') : 'ce jour';
        $dLongue = $debut ? static::dateLongue(Carbon::parse($debut)) : '';
        $fLongue = $fin ? static::dateLongue(Carbon::parse($fin)) : 'ce jour';
        $titreNom = ($civilite === 'Mme' ? 'Madame' : 'Monsieur').' '.$nom;
        $accordE = $civilite === 'Mme' ? 'e' : '';

        $remplacements = [
            '[NOM]'        => $nom,
            '[CIVILITE]'   => $civilite,
            '[TITRE_NOM]'  => $titreNom,
            '[CIVILITE_LONGUE]' => $civilite === 'Mme' ? 'Madame' : 'Monsieur',
            '[ACCORD_E]'   => $accordE,
            '[DATE_DEBUT]' => $d,
            '[DATE_FIN]'   => $f,
            '[DATE_DEBUT_LONGUE]' => $dLongue,
            '[DATE_FIN_LONGUE]'   => $fLongue,
            '[DUREE]'      => static::formatDuree($debut, $fin),
            '[DE_DUREE]'   => static::deDuree($debut, $fin),
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
            $naissanceLongue = $personne instanceof Internship && $personne->birth_date
                ? static::dateLongue($personne->birth_date)
                : '';
            $remplacements += [
                '[SPECIALITE]'     => $personne->school ?? '',
                '[ETABLISSEMENT]'  => $personne->school ?? '',
                '[DATE_NAISSANCE]' => $naissance,
                '[DATE_NAISSANCE_LONGUE]' => $naissanceLongue,
                '[LIEU_NAISSANCE]' => ($personne instanceof Internship ? $personne->birth_place : '') ?? '',
            ];
        }

        return strtr($modele, $remplacements);
    }

    /**
     * Texte marqué → HTML du PDF : échappé, `**…**` en gras, et en gras VERT quand il porte le nom de la
     * ferme (comme le modèle officiel : « FERME ECOLE OLOUWACHEGOUN »).
     */
    public static function enHtml(string $texte): string
    {
        return preg_replace_callback('/\*\*(.+?)\*\*/su', function (array $m): string {
            $vert = stripos($m[1], 'OLOUWACHEGOUN') !== false;

            return '<strong'.($vert ? ' class="vert"' : '').'>'.$m[1].'</strong>';
        }, e($texte));
    }

    /** Texte marqué → texte brut (aperçu) : retire les `**`. */
    public static function sansMarques(string $texte): string
    {
        return str_replace('**', '', $texte);
    }

    /** « 15 octobre 2025 ». */
    public static function dateLongue(Carbon $date): string
    {
        return $date->day.' '.self::MOIS[$date->month - 1].' '.$date->year;
    }

    /**
     * Durée de la période : « court » (jusqu'à `seuil_signature_mois` mois INCLUS) ou « long » (au-delà).
     *
     * ⚠️ Compté en mois CALENDAIRES depuis la date de début : du 15/10/2025 au 15/10/2026 = 12 mois exactement
     * = palier court ; le 16/10/2026 = palier long. Sans date de fin, la durée court jusqu'à aujourd'hui ;
     * sans date de début, rien n'est mesurable : palier court (le promoteur seul).
     */
    public static function palier(?string $debut, ?string $fin, int $seuilMois): string
    {
        if (! $debut) {
            return self::PALIER_COURT;
        }

        $d = Carbon::parse($debut)->startOfDay();
        $f = ($fin ? Carbon::parse($fin) : now())->startOfDay();

        return $f->greaterThan($d->copy()->addMonthsNoOverflow($seuilMois))
            ? self::PALIER_LONG
            : self::PALIER_COURT;
    }

    /**
     * Les signataires à imprimer, de gauche à droite (Examinateur, Président du Jury, Directeur Général).
     *
     * ⚠️ QUI SIGNE EST UNE RÈGLE DU MODÈLE, PAS UNE CONSTANTE (ATT-2) : chaque signataire a un drapeau
     * « signe les attestations courtes » et « signe les attestations longues », et le seuil des deux paliers est
     * `seuil_signature_mois` (défaut 12 : d'un mois à un an, le promoteur seul ; au-delà, trois signataires).
     * Les intitulés, noms et fonctions sont ceux du modèle, remplacés par `$surcharges` (« sig1 » … « sig3 »)
     * quand l'émetteur les a modifiés pour CETTE attestation — jamais pour désigner un signataire que la
     * règle n'appelle pas.
     *
     * @param  array<string, array{titre?: ?string, nom?: ?string, fonction?: ?string}>  $surcharges
     * @return list<array{position: int, titre: string, nom: string, fonction: string}>
     */
    public function signataires(string $type, ?string $debut, ?string $fin, array $surcharges = []): array
    {
        $modele = AttestationTemplate::forType($type);
        $palier = static::palier($debut, $fin, (int) $modele->seuil_signature_mois);
        $liste = [];

        foreach (self::ORDRE_SIGNATURES as $position) {
            if (! $modele->{'sig'.$position.'_'.$palier}) {
                continue;
            }

            $modif = $surcharges['sig'.$position] ?? [];
            $titre = trim((string) ($modif['titre'] ?? $modele->{'sig'.$position.'_titre'}));
            $nom = trim((string) ($modif['nom'] ?? $modele->{'sig'.$position.'_nom'}));
            $fonction = trim((string) ($modif['fonction'] ?? $modele->{'sig'.$position.'_fonction'}));

            if ($titre === '' && $nom === '' && $fonction === '') {
                continue;
            }

            $liste[] = ['position' => $position, 'titre' => $titre, 'nom' => $nom, 'fonction' => $fonction];
        }

        return $liste;
    }

    /**
     * Génère le PDF ET journalise la génération.
     *
     * Les signataires sont ceux que la durée appelle (`signataires()`), éditables par attestation (`$signataires`
     * = surcharges « sig1 » … « sig3 »). Les domaines et la civilité sont spécifiques à chaque émission.
     *
     * @param  array<string, array{titre?: ?string, nom?: ?string, fonction?: ?string}>  $signataires
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
        array $signataires = [],
        ?string $dateAttestation = null,
    ): array {
        $nom = $personne->last_name.' '.$personne->first_name;
        $numero = $this->prochainNumero();

        AuditLog::record('attestation.generated.'.$type, 'rh');

        // DomPDF range ici les polices converties (ufm) ; le dossier doit exister et être inscriptible.
        File::ensureDirectoryExists(storage_path('fonts'));

        $pdf = Pdf::loadView('exports.attestation', [
            'title'      => $this->titre($type),
            'corps'      => $this->corpsMarque($type, $personne, $contrat, $debut, $fin, $civilite),
            'puces'      => array_values(array_intersect_key(
                self::DOMAINES_PUCES,
                array_flip(array_filter($domaines, fn ($c) => isset(self::DOMAINES_PUCES[$c]))),
            )),
            'appreciation' => $this->appreciation($type, $personne, $note, $debut, $fin, $civilite),
            'numero'     => $numero,
            'dateLieu'   => static::dateLongue($dateAttestation ? Carbon::parse($dateAttestation) : now()),
            'signataires' => $this->signataires($type, $debut, $fin, $signataires),
            'entete'     => config('attestation'),
            'images'     => [
                'logo'      => resource_path('attestation/images/logo-ferme.png'),
                'filigrane' => resource_path('attestation/images/filigrane.png'),
                'decor'     => resource_path('attestation/images/decor-floral.png'),
                'signature' => resource_path('attestation/images/signature-directeur.png'),
            ],
            'polices'    => resource_path('attestation/fonts'),
        ])->setPaper('a4', 'landscape')
            // Caladea (équivalent libre de Cambria) a une boîte englobante très haute : DomPDF en tire un interligne de
            // 1,6 em, bien au-delà de celui du modèle (1,25 em). Le ratio ramène l'interligne à celui du modèle.
            ->setOption(['font_height_ratio' => 0.86]);

        return [
            'octets'  => $pdf->output(),
            'fichier' => 'attestation-'.Str::slug($nom).'.pdf',
        ];
    }

    /**
     * ATT-3 — ÉMISSION D'UNE ATTESTATION FABRIQUÉE AU POSTE : attribue le numéro et journalise, sans produire de PDF.
     *
     * Le poste fabrique lui-même le document (hors ligne comprise) ; le serveur reste l'AUTORITÉ DU NUMÉRO
     * (`N°04/2026/FEO/DG`, jamais inventé au poste) et de la TRACE d'audit (`attestation.generated.*`, que décompte le
     * registre des stagiaires). **Idempotent par l'identifiant d'émission du poste** : un envoi rejoué (réponse perdue,
     * émission restée en file hors ligne) rend le même numéro et ne compte qu'une fois.
     *
     * ⚠️ Le numéro est FIGÉ dans `attestation_emissions` : l'année est celle de l'INSTANT de l'émission, le rang le
     * nombre d'attestations de cette année une fois la trace écrite (comme `prochainNumero()`, qui compte aussi celles
     * du web). Une émission faite hors ligne et reçue tard prend le rang suivant — jamais un rang déjà donné.
     *
     * @return array{numero: string, deja_enregistree: bool}
     */
    public function emettre(string $type, string $emissionId, ?Carbon $quand = null): array
    {
        return DB::transaction(function () use ($type, $emissionId, $quand) {
            $existante = AttestationEmission::find($emissionId);

            if ($existante) {
                return ['numero' => $existante->numero, 'deja_enregistree' => true];
            }

            // Un instant du poste ne peut pas être dans le futur (horloge déréglée) : au-delà de maintenant, c'est maintenant.
            $instant = $quand && $quand->lessThanOrEqualTo(now()) ? $quand : now();

            // Insertion directe : `AuditLog::record()` ne sait désigner qu'un modèle, ici l'entité est une émission du poste.
            $trace = new AuditLog([
                'user_id' => auth()->id(),
                'action' => 'attestation.generated.'.$type,
                'module' => 'rh',
                'entity_type' => self::ENTITE_EMISSION,
                'entity_id' => $emissionId,
                'ip_address' => request()->ip(),
            ]);
            $trace->created_at = $instant; // hors `$fillable` : l'instant de l'ÉMISSION, pas celui de la réception
            $trace->save();

            $rang = AuditLog::where('action', 'like', 'attestation.generated.%')->whereYear('created_at', $instant->year)->count();
            $numero = sprintf('N°%02d/%d/FEO/DG', $rang, $instant->year);

            AttestationEmission::create([
                'id' => $emissionId, 'type' => $type, 'numero' => $numero, 'issued_at' => $instant, 'user_id' => auth()->id(),
            ]);

            return ['numero' => $numero, 'deja_enregistree' => false];
        });
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

    /**
     * « d'un (01) an » / « de six (06) mois » — avec l'espace qui l'attache au mot précédent ; vide sans durée.
     * L'élision ne vaut que devant « un » (« d'un an ») : « de onze », « de huit »…
     */
    public static function deDuree(?string $debut, ?string $fin): string
    {
        $duree = static::formatDuree($debut, $fin);

        if ($duree === '') {
            return '';
        }

        return str_starts_with($duree, 'un ') ? " d'".$duree : ' de '.$duree;
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
