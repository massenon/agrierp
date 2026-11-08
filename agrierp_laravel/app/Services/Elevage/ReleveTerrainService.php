<?php

namespace App\Services\Elevage;

use App\Models\AuditLog;
use App\Models\FieldSurveyEntry;
use App\Models\PurchaseOrder;
use Carbon\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ticket RELEVES-1 (08/11/2026) — POINT DE PASSAGE UNIQUE DE L'ONGLET « RELEVÉS DE TERRAIN » (Paramètres Élevage).
 *
 * Appelé par `Livewire\Elevage\ParametresElevage` (le web) ET par `SyncController::pushFieldSurveyEntries` (le poste,
 * clé d'envoi `field_survey_entries`) : mêmes règles, mêmes refus (français), même statut, même audit.
 *
 * ⚠️⚠️ RÈGLE « À VALIDER → VALIDÉ » (décision du client du 08/11/2026, DV-24) :
 *  - les lignes semées par défaut (les PROPOSITIONS de l'assistant) naissent `a_valider` — SEUL `semerParDefaut()` écrit
 *    ce statut ;
 *  - TOUT enregistrement humain (création, modification, bouton « Valider » de la modale, envoi du poste) écrit
 *    `valide` + `validated_by` + `validated_at` : le statut « À valider » ne subsiste JAMAIS sur une ligne qu'un
 *    humain a enregistrée. `RelevesTerrainTest::test_aucun_chemin_d_enregistrement_ne_laisse_a_valider` le garde.
 *
 * Trois familles : `incubation` (règles par espèce + relevés de lots), `provende` (règle du délai fournisseur ; le
 * tableau des délais constatés est CALCULÉ en lecture des bons de commande reçus), `technicien` (poissons-chats : marque,
 * barème du fabricant, température, densité). Aucune valeur zootechnique n'est une vérité ferme : ce sont des repères,
 * « à valider » tant que personne ne les a enregistrés.
 */
class ReleveTerrainService
{
    public const A_VALIDER = 'a_valider';

    public const VALIDE = 'valide';

    public const STATUTS = [self::A_VALIDER => 'À valider', self::VALIDE => 'Validé'];

    public const INCUBATION_REGLE = 'incubation_regle';

    public const INCUBATION_LOT = 'incubation_lot';

    public const DELAI_REGLE = 'delai_regle';

    public const POISSON_MARQUE = 'poisson_marque';

    public const POISSON_BAREME = 'poisson_bareme';

    public const POISSON_TEMPERATURE = 'poisson_temperature';

    public const POISSON_DENSITE = 'poisson_densite';

    /** type → famille (sous-onglet). */
    public const FAMILLES = [
        self::INCUBATION_REGLE => 'incubation',
        self::INCUBATION_LOT => 'incubation',
        self::DELAI_REGLE => 'provende',
        self::POISSON_MARQUE => 'technicien',
        self::POISSON_BAREME => 'technicien',
        self::POISSON_TEMPERATURE => 'technicien',
        self::POISSON_DENSITE => 'technicien',
    ];

    public const TYPES_LIBELLES = [
        self::INCUBATION_REGLE => 'Règle d\'incubation',
        self::INCUBATION_LOT => 'Relevé de lot',
        self::DELAI_REGLE => 'Règle du délai fournisseur',
        self::POISSON_MARQUE => 'Marque de granulés',
        self::POISSON_BAREME => 'Barème du fabricant',
        self::POISSON_TEMPERATURE => 'Température de l\'eau',
        self::POISSON_DENSITE => 'Densité d\'empoissonnement',
    ];

    public const MODES = [
        'couveuse_artificielle' => 'Couveuse artificielle',
        'couvaison_naturelle' => 'Couvaison naturelle (sous poule ou pintade)',
    ];

    public const MODES_DELAI = ['constate' => 'Le plus long des 5 derniers délais', 'manuel' => 'Valeurs saisies'];

    /** Nombre de bons de commande de provende retenus par fournisseur (DV-18). */
    public const NB_BONS = 5;

    /** Valeurs de départ du délai fournisseur (DV-04) : critique 3 j, alerte 7 j ; marge de sécurité 4 j (DV-14). */
    public const CRITIQUE_DEPART = 3;

    public const ALERTE_DEPART = 7;

    public const MARGE_DEFAUT = 4;

    // ===================== SEMIS (propositions « À valider ») =====================

    /**
     * Les valeurs par défaut = les PROPOSITIONS. [clé stable, type, libellé, espèce, data].
     *
     * @return array<int, array{0: string, 1: string, 2: string, 3: ?string, 4: array}>
     */
    public static function valeursParDefaut(): array
    {
        $regle = fn (int $duree, int $min, int $max, ?int $transfert) => [
            'duree_jours' => $duree, 'eclosion_min' => $min, 'eclosion_max' => $max, 'mode' => 'couveuse_artificielle',
            'mirages' => [7, 14], 'transfert_jour' => $transfert, 'conservation_max_jours' => 10,
        ];
        $bareme = fn (float $min, ?float $max, float $bmin, float $bmax) => [
            'poids_min_g' => $min, 'poids_max_g' => $max, 'biomasse_min_pct' => $bmin, 'biomasse_max_pct' => $bmax,
            'granule' => null, 'proteine_pct' => null,
        ];

        return [
            ['incubation_pintade', self::INCUBATION_REGLE, 'Pintade', 'pintade', $regle(28, 26, 28, 25)],
            ['incubation_goliath', self::INCUBATION_REGLE, 'Goliath', 'goliath', $regle(21, 19, 23, null)],
            ['delai_provende', self::DELAI_REGLE, 'Délai fournisseur de provende', null, [
                'mode' => 'constate', 'marge_jours' => self::MARGE_DEFAUT,
                'critique_jours' => self::CRITIQUE_DEPART, 'alerte_jours' => self::ALERTE_DEPART,
            ]],
            ['poisson_marque', self::POISSON_MARQUE, 'Marque de granulés', 'poisson_chat', ['marque' => null]],
            ['poisson_bareme_1', self::POISSON_BAREME, 'Alevin', 'poisson_chat', $bareme(0, 5, 10, 20)],
            ['poisson_bareme_2', self::POISSON_BAREME, 'Fingerling', 'poisson_chat', $bareme(5, 20, 6, 8)],
            ['poisson_bareme_3', self::POISSON_BAREME, 'Juvénile', 'poisson_chat', $bareme(20, 100, 3, 5)],
            ['poisson_bareme_4', self::POISSON_BAREME, 'Grossissement', 'poisson_chat', $bareme(100, 500, 2, 3)],
            ['poisson_bareme_5', self::POISSON_BAREME, 'Adulte', 'poisson_chat', $bareme(500, null, 1, 2)],
            ['poisson_temperature', self::POISSON_TEMPERATURE, 'Température de l\'eau', 'poisson_chat', [
                'optimale_min' => 26, 'optimale_max' => 30, 'reduire_sous' => 22,
            ]],
            ['poisson_densite', self::POISSON_DENSITE, 'Densité d\'empoissonnement', 'poisson_chat', ['densite' => null, 'unite' => null]],
        ];
    }

    /** Identifiant déterministe d'une ligne semée (UUID de forme v5) : le semis rejoué retrouve la même ligne. */
    public static function idDuSemis(string $cle): string
    {
        $h = sha1('agrierp:field_survey_entries:'.$cle);

        return sprintf('%s-%s-5%s-%s-%s', substr($h, 0, 8), substr($h, 8, 4), substr($h, 13, 3), dechex(8 | (hexdec($h[16]) & 3)).substr($h, 17, 3), substr($h, 20, 12));
    }

    /**
     * Sème les propositions « À valider ». IDEMPOTENT : une ligne déjà présente (même archivée, même modifiée ou
     * validée) n'est jamais réécrite. Écrit par `DB::table` (appelé aussi par la migration). @return int lignes créées
     */
    public static function semerParDefaut(): int
    {
        $crees = 0;
        foreach (self::valeursParDefaut() as [$cle, $type, $libelle, $espece, $data]) {
            $id = self::idDuSemis($cle);
            if (DB::table('field_survey_entries')->where('id', $id)->exists()) {
                continue;
            }
            DB::table('field_survey_entries')->insert([
                'id' => $id, 'type' => $type, 'label' => $libelle, 'species_code' => $espece,
                'data' => json_encode($data, JSON_UNESCAPED_UNICODE), 'status' => self::A_VALIDER,
                'sync_status' => 'synced', 'is_active' => true, 'created_at' => now(), 'updated_at' => now(),
            ]);
            $crees++;
        }

        return $crees;
    }

    // ===================== LECTURE =====================

    /** @return Collection<int, FieldSurveyEntry> */
    public function lignes(string $famille, bool $seulementActives = true): Collection
    {
        $types = array_keys(array_filter(self::FAMILLES, fn ($f) => $f === $famille));

        $lignes = FieldSurveyEntry::whereIn('type', $types)
            ->when($seulementActives, fn ($q) => $q->where('is_active', true))
            ->get();

        return $lignes->sortBy(fn (FieldSurveyEntry $l) => [
            array_search($l->type, array_keys(self::FAMILLES), true),
            $l->type === self::POISSON_BAREME ? (float) ($l->data['poids_min_g'] ?? 0) : 0,
            $l->type === self::INCUBATION_LOT ? ($l->data['mise_date'] ?? '') : '',
            mb_strtolower($l->label),
        ])->values();
    }

    public function nombreAValider(): int
    {
        return FieldSurveyEntry::where('is_active', true)->where('status', self::A_VALIDER)->count();
    }

    // ===================== ÉCRITURE (points d'entrée humains) =====================

    /**
     * Crée une ligne saisie par un humain : statut `valide`. @param array{label?: mixed, species_code?: mixed, data?: mixed} $saisie
     */
    public function creer(string $type, array $saisie, ?string $auteurId, ?string $id = null, ?string $poste = null): FieldSurveyEntry
    {
        $valide = $this->normaliser($type, $saisie, null);

        return DB::transaction(function () use ($type, $valide, $auteurId, $id, $poste) {
            $ligne = new FieldSurveyEntry($valide + $this->empreinteHumaine($auteurId) + [
                'type' => $type, 'device_id' => $poste, 'sync_status' => 'synced', 'is_active' => true,
            ]);
            if ($id !== null) {
                $ligne->id = $id;   // HasUuids ignorerait l'UUID du poste : on l'assigne
            }
            $ligne->save();
            AuditLog::record('releve.saved', 'elevage', $auteurId, $ligne);

            return $ligne;
        });
    }

    /** Modifie une ligne : ENREGISTRER = « Validé » (jamais « À valider » après un enregistrement humain). */
    public function modifier(FieldSurveyEntry $ligne, array $saisie, ?string $auteurId, ?string $poste = null): FieldSurveyEntry
    {
        $valide = $this->normaliser($ligne->type, $saisie, $ligne);

        return DB::transaction(function () use ($ligne, $valide, $auteurId, $poste) {
            $ligne->forceFill($valide + $this->empreinteHumaine($auteurId) + ['device_id' => $poste ?? $ligne->device_id])->save();
            AuditLog::record('releve.saved', 'elevage', $auteurId, $ligne);

            return $ligne;
        });
    }

    /**
     * Modale « Valider » : montre les valeurs, permet de les corriger ($saisie, sinon valeurs inchangées), puis la ligne
     * passe de « À valider » à « Validé » (validé par, validé le, audit `releve.valide`). Valider une ligne déjà
     * validée la re-signe (même chemin, aucun statut à rétrograder).
     */
    public function valider(FieldSurveyEntry $ligne, ?array $saisie, ?string $auteurId, ?string $poste = null): FieldSurveyEntry
    {
        $valide = $this->normaliser($ligne->type, $saisie ?? ['label' => $ligne->label, 'species_code' => $ligne->species_code, 'data' => $ligne->data], $ligne);

        return DB::transaction(function () use ($ligne, $valide, $auteurId, $poste) {
            $ligne->forceFill($valide + $this->empreinteHumaine($auteurId) + ['device_id' => $poste ?? $ligne->device_id])->save();
            AuditLog::record('releve.valide', 'elevage', $auteurId, $ligne);

            return $ligne;
        });
    }

    /** Archivage logique (jamais de DELETE) ; le statut n'est pas touché. */
    public function archiver(FieldSurveyEntry $ligne, ?string $auteurId): FieldSurveyEntry
    {
        if ($ligne->is_active) {
            $ligne->forceFill(['is_active' => false])->save();
            AuditLog::record('releve.archived', 'elevage', $auteurId, $ligne);
        }

        return $ligne;
    }

    /** @return array{status: string, validated_by: ?string, validated_at: Carbon} */
    private function empreinteHumaine(?string $auteurId): array
    {
        return ['status' => self::VALIDE, 'validated_by' => $auteurId, 'validated_at' => now()];
    }

    // ===================== VALIDATION (français) =====================

    private const ATTRIBUTS = [
        'label' => 'libellé', 'species_code' => 'espèce',
        'data.duree_jours' => 'durée d\'incubation', 'data.eclosion_min' => 'premier jour d\'éclosion',
        'data.eclosion_max' => 'dernier jour d\'éclosion', 'data.mode' => 'mode', 'data.mirages' => 'jours de mirage',
        'data.transfert_jour' => 'jour de transfert à l\'éclosoir', 'data.conservation_max_jours' => 'conservation maximale des œufs',
        'data.mise_date' => 'date de mise en incubation', 'data.oeufs_mis' => 'œufs mis', 'data.oeufs_fertiles' => 'œufs fertiles',
        'data.oeufs_eclos' => 'œufs éclos', 'data.premier_eclos_date' => 'date du premier éclos', 'data.dernier_eclos_date' => 'date du dernier éclos',
        'data.marge_jours' => 'marge de sécurité', 'data.critique_jours' => 'délai critique', 'data.alerte_jours' => 'délai d\'alerte',
        'data.marque' => 'marque', 'data.poids_min_g' => 'poids minimal', 'data.poids_max_g' => 'poids maximal',
        'data.biomasse_min_pct' => '% de biomasse minimal', 'data.biomasse_max_pct' => '% de biomasse maximal',
        'data.granule' => 'taille du granulé', 'data.proteine_pct' => 'protéine', 'data.optimale_min' => 'température optimale minimale',
        'data.optimale_max' => 'température optimale maximale', 'data.reduire_sous' => 'seuil de réduction de la ration',
        'data.densite' => 'densité', 'data.unite' => 'unité',
    ];

    /**
     * Valide et NORMALISE une saisie (même chemin web et poste). Retourne `label`, `species_code`, `data` canoniques
     * (clés inconnues retirées, nombres typés, « — » = null). @throws ValidationException messages français
     */
    public function normaliser(string $type, array $saisie, ?FieldSurveyEntry $existante): array
    {
        if (! isset(self::FAMILLES[$type])) {
            throw ValidationException::withMessages(['type' => 'Type de relevé inconnu.']);
        }

        $e = [];
        $label = trim((string) ($saisie['label'] ?? ''));
        $espece = $this->texte($saisie['species_code'] ?? null);
        $brut = is_array($saisie['data'] ?? null) ? $saisie['data'] : [];
        $d = [];

        if ($label === '') {
            $e['label'] = 'Le libellé est obligatoire.';
        } elseif (mb_strlen($label) > 150) {
            $e['label'] = 'Le libellé ne peut pas dépasser 150 caractères.';
        }

        switch ($type) {
            case self::INCUBATION_REGLE:
                $d = $this->regleIncubation($brut, $e);
                if ($espece === null || ! preg_match('/^[a-z0-9_-]{2,40}$/', $espece)) {
                    $e['species_code'] = 'L\'espèce est obligatoire (lettres minuscules, chiffres, tiret).';
                } elseif ($this->existeDeja($type, 'species_code', $espece, $existante)) {
                    $e['species_code'] = 'Une règle d\'incubation existe déjà pour cette espèce.';
                }
                break;
            case self::INCUBATION_LOT:
                $d = $this->lotIncubation($brut, $e);
                if ($espece === null) {
                    $e['species_code'] = 'L\'espèce est obligatoire.';
                } elseif (! FieldSurveyEntry::where('type', self::INCUBATION_REGLE)->where('is_active', true)->where('species_code', $espece)->exists()) {
                    $e['species_code'] = 'Aucune règle d\'incubation n\'existe pour cette espèce : créez-la d\'abord.';
                }
                if ($label !== '' && $this->existeDeja($type, 'label', $label, $existante)) {
                    $e['label'] = 'Un relevé existe déjà pour ce code de lot.';
                }
                break;
            case self::DELAI_REGLE:
                $d = $this->regleDelai($brut, $e);
                $espece = null;
                if ($existante === null && FieldSurveyEntry::where('type', $type)->where('is_active', true)->exists()) {
                    $e['label'] = 'La règle du délai fournisseur existe déjà : modifiez-la.';
                }
                break;
            case self::POISSON_MARQUE:
                $marque = $this->texte($brut['marque'] ?? null);
                if ($marque !== null && mb_strlen($marque) > 100) {
                    $e['data.marque'] = 'La marque ne peut pas dépasser 100 caractères.';
                }
                $d = ['marque' => $marque];
                $espece = 'poisson_chat';
                break;
            case self::POISSON_BAREME:
                $d = $this->baremePoisson($brut, $e);
                $espece = 'poisson_chat';
                break;
            case self::POISSON_TEMPERATURE:
                $d = $this->temperaturePoisson($brut, $e);
                $espece = 'poisson_chat';
                break;
            case self::POISSON_DENSITE:
                $densite = $this->nombre($brut['densite'] ?? null, $e, 'data.densite', 0, 100000);
                $d = ['densite' => $densite, 'unite' => $this->texte($brut['unite'] ?? null)];
                if ($d['unite'] !== null && mb_strlen($d['unite']) > 30) {
                    $e['data.unite'] = 'L\'unité ne peut pas dépasser 30 caractères.';
                }
                $espece = 'poisson_chat';
                break;
        }

        if ($e !== []) {
            throw ValidationException::withMessages($e);
        }

        return ['label' => $label, 'species_code' => $espece, 'data' => $d];
    }

    private function existeDeja(string $type, string $colonne, string $valeur, ?FieldSurveyEntry $existante): bool
    {
        return FieldSurveyEntry::where('type', $type)->where('is_active', true)->where($colonne, $valeur)
            ->when($existante, fn ($q) => $q->where('id', '!=', $existante->id))->exists();
    }

    private function texte(mixed $v): ?string
    {
        if ($v === null || is_array($v)) {
            return null;
        }
        $v = trim((string) $v);

        return $v === '' ? null : $v;
    }

    /** Nombre décimal (virgule acceptée) ou null ; hors bornes ou non numérique : erreur. */
    private function nombre(mixed $v, array &$e, string $cle, float $min, float $max): int|float|null
    {
        $t = $this->texte($v);
        if ($t === null) {
            return null;
        }
        $t = str_replace([',', ' '], ['.', ''], $t);
        if (! is_numeric($t) || (float) $t < $min || (float) $t > $max) {
            $e[$cle] = 'Le champ '.self::ATTRIBUTS[$cle].' doit être un nombre compris entre '.$this->fr($min).' et '.$this->fr($max).'.';

            return null;
        }
        $f = (float) $t;

        return floor($f) == $f ? (int) $f : round($f, 2);
    }

    private function entier(mixed $v, array &$e, string $cle, int $min, int $max): ?int
    {
        $t = $this->texte($v);
        if ($t === null) {
            return null;
        }
        if (! preg_match('/^\d+$/', $t) || (int) $t < $min || (int) $t > $max) {
            $e[$cle] = 'Le champ '.self::ATTRIBUTS[$cle].' doit être un nombre entier compris entre '.$min.' et '.$max.'.';

            return null;
        }

        return (int) $t;
    }

    private function requis(mixed $valeur, array &$e, string $cle): mixed
    {
        if ($valeur === null && ! isset($e[$cle])) {
            $e[$cle] = 'Le champ '.self::ATTRIBUTS[$cle].' est obligatoire.';
        }

        return $valeur;
    }

    private function fr(float $v): string
    {
        return rtrim(rtrim(number_format($v, 2, ',', ''), '0'), ',');
    }

    private function date(mixed $v, array &$e, string $cle): ?string
    {
        $t = $this->texte($v);
        if ($t === null) {
            return null;
        }
        try {
            $d = Carbon::createFromFormat('Y-m-d', substr($t, 0, 10));
            if ($d === false || $d->format('Y-m-d') !== substr($t, 0, 10)) {
                throw new \InvalidArgumentException;
            }

            return $d->format('Y-m-d');
        } catch (\Throwable) {
            $e[$cle] = 'Le champ '.self::ATTRIBUTS[$cle].' doit être une date valide (AAAA-MM-JJ).';

            return null;
        }
    }

    private function regleIncubation(array $b, array &$e): array
    {
        $duree = $this->requis($this->entier($b['duree_jours'] ?? null, $e, 'data.duree_jours', 1, 60), $e, 'data.duree_jours');
        $min = $this->requis($this->entier($b['eclosion_min'] ?? null, $e, 'data.eclosion_min', 1, 60), $e, 'data.eclosion_min');
        $max = $this->requis($this->entier($b['eclosion_max'] ?? null, $e, 'data.eclosion_max', 1, 60), $e, 'data.eclosion_max');
        if ($duree !== null && $min !== null && $min > $duree) {
            $e['data.eclosion_min'] = 'Le premier jour d\'éclosion ne peut pas dépasser la durée d\'incubation.';
        }
        if ($duree !== null && $max !== null && $max < $duree) {
            $e['data.eclosion_max'] = 'Le dernier jour d\'éclosion ne peut pas être inférieur à la durée d\'incubation.';
        }
        $mode = $this->texte($b['mode'] ?? null);
        if (! isset(self::MODES[$mode ?? ''])) {
            $e['data.mode'] = 'Choisissez un mode d\'incubation.';
        }

        // Jours de mirage : « 7, 14 » ou liste ; 1 à 3 entiers croissants, tous inférieurs à la durée.
        $mirages = $b['mirages'] ?? [];
        $jours = is_array($mirages) ? $mirages : preg_split('/[\s,;]+/', trim((string) $mirages), -1, PREG_SPLIT_NO_EMPTY);
        $ok = count($jours) >= 1 && count($jours) <= 3;
        $liste = [];
        foreach ($jours as $j) {
            if (! is_numeric($j) || (int) $j != $j || (int) $j < 1 || ($duree !== null && (int) $j >= $duree)) {
                $ok = false;
                break;
            }
            $liste[] = (int) $j;
        }
        for ($i = 1; $ok && $i < count($liste); $i++) {
            $ok = $liste[$i] > $liste[$i - 1];
        }
        if (! $ok) {
            $e['data.mirages'] = 'Les jours de mirage doivent être 1 à 3 entiers croissants, tous inférieurs à la durée d\'incubation.';
        }

        $transfert = $this->entier($b['transfert_jour'] ?? null, $e, 'data.transfert_jour', 1, 60);
        if ($transfert !== null && $ok && $duree !== null && ($transfert <= end($liste) || $transfert >= $duree)) {
            $e['data.transfert_jour'] = 'Le jour de transfert doit se situer après le dernier mirage et avant la fin de l\'incubation.';
        }
        $conservation = $this->requis($this->entier($b['conservation_max_jours'] ?? null, $e, 'data.conservation_max_jours', 1, 30), $e, 'data.conservation_max_jours');

        return [
            'duree_jours' => $duree, 'eclosion_min' => $min, 'eclosion_max' => $max, 'mode' => $mode,
            'mirages' => $ok ? $liste : [], 'transfert_jour' => $transfert, 'conservation_max_jours' => $conservation,
        ];
    }

    private function lotIncubation(array $b, array &$e): array
    {
        $mise = $this->requis($this->date($b['mise_date'] ?? null, $e, 'data.mise_date'), $e, 'data.mise_date');
        $mode = $this->texte($b['mode'] ?? null);
        if (! isset(self::MODES[$mode ?? ''])) {
            $e['data.mode'] = 'Choisissez un mode d\'incubation.';
        }
        $mis = $this->entier($b['oeufs_mis'] ?? null, $e, 'data.oeufs_mis', 1, 1000000);
        $fertiles = $this->entier($b['oeufs_fertiles'] ?? null, $e, 'data.oeufs_fertiles', 0, 1000000);
        $eclos = $this->entier($b['oeufs_eclos'] ?? null, $e, 'data.oeufs_eclos', 0, 1000000);
        if ($mis !== null && $fertiles !== null && $fertiles > $mis) {
            $e['data.oeufs_fertiles'] = 'Les œufs fertiles ne peuvent pas dépasser les œufs mis.';
        }
        if ($fertiles !== null && $eclos !== null && $eclos > $fertiles) {
            $e['data.oeufs_eclos'] = 'Les œufs éclos ne peuvent pas dépasser les œufs fertiles.';
        }
        if ($mis === null && $eclos !== null && $fertiles === null && $eclos > 0) {
            // éclos sans autre donnée : accepté, les taux resteront « — »
        }
        $premier = $this->date($b['premier_eclos_date'] ?? null, $e, 'data.premier_eclos_date');
        $dernier = $this->date($b['dernier_eclos_date'] ?? null, $e, 'data.dernier_eclos_date');
        if ($mise !== null && $premier !== null && $premier < $mise) {
            $e['data.premier_eclos_date'] = 'Le premier éclos ne peut pas précéder la mise en incubation.';
        }
        if ($premier !== null && $dernier !== null && $dernier < $premier) {
            $e['data.dernier_eclos_date'] = 'Le dernier éclos ne peut pas précéder le premier.';
        }

        return [
            'mise_date' => $mise, 'mode' => $mode, 'oeufs_mis' => $mis, 'oeufs_fertiles' => $fertiles, 'oeufs_eclos' => $eclos,
            'premier_eclos_date' => $premier, 'dernier_eclos_date' => $dernier,
        ];
    }

    private function regleDelai(array $b, array &$e): array
    {
        $mode = $this->texte($b['mode'] ?? null);
        if (! isset(self::MODES_DELAI[$mode ?? ''])) {
            $e['data.mode'] = 'Choisissez comment fixer les seuils.';
        }
        $marge = $this->requis($this->entier($b['marge_jours'] ?? null, $e, 'data.marge_jours', 0, 30), $e, 'data.marge_jours');
        $critique = $this->requis($this->entier($b['critique_jours'] ?? null, $e, 'data.critique_jours', 0, 60), $e, 'data.critique_jours');
        $alerte = $this->requis($this->entier($b['alerte_jours'] ?? null, $e, 'data.alerte_jours', 0, 90), $e, 'data.alerte_jours');
        if ($critique !== null && $alerte !== null && $alerte < $critique) {
            $e['data.alerte_jours'] = 'Le délai d\'alerte ne peut pas être inférieur au délai critique.';
        }

        return ['mode' => $mode, 'marge_jours' => $marge, 'critique_jours' => $critique, 'alerte_jours' => $alerte];
    }

    private function baremePoisson(array $b, array &$e): array
    {
        $min = $this->requis($this->nombre($b['poids_min_g'] ?? null, $e, 'data.poids_min_g', 0, 100000), $e, 'data.poids_min_g');
        $max = $this->nombre($b['poids_max_g'] ?? null, $e, 'data.poids_max_g', 0, 100000);
        if ($min !== null && $max !== null && $max <= $min) {
            $e['data.poids_max_g'] = 'Le poids maximal doit dépasser le poids minimal (laissez vide pour « sans limite »).';
        }
        $bmin = $this->requis($this->nombre($b['biomasse_min_pct'] ?? null, $e, 'data.biomasse_min_pct', 0, 100), $e, 'data.biomasse_min_pct');
        $bmax = $this->requis($this->nombre($b['biomasse_max_pct'] ?? null, $e, 'data.biomasse_max_pct', 0, 100), $e, 'data.biomasse_max_pct');
        if ($bmin !== null && $bmax !== null && $bmax < $bmin) {
            $e['data.biomasse_max_pct'] = 'Le % de biomasse maximal ne peut pas être inférieur au minimal.';
        }
        $granule = $this->texte($b['granule'] ?? null);
        if ($granule !== null && mb_strlen($granule) > 30) {
            $e['data.granule'] = 'La taille du granulé ne peut pas dépasser 30 caractères.';
        }

        return [
            'poids_min_g' => $min, 'poids_max_g' => $max, 'biomasse_min_pct' => $bmin, 'biomasse_max_pct' => $bmax,
            'granule' => $granule, 'proteine_pct' => $this->nombre($b['proteine_pct'] ?? null, $e, 'data.proteine_pct', 0, 100),
        ];
    }

    private function temperaturePoisson(array $b, array &$e): array
    {
        $min = $this->requis($this->nombre($b['optimale_min'] ?? null, $e, 'data.optimale_min', 0, 45), $e, 'data.optimale_min');
        $max = $this->requis($this->nombre($b['optimale_max'] ?? null, $e, 'data.optimale_max', 0, 45), $e, 'data.optimale_max');
        if ($min !== null && $max !== null && $max < $min) {
            $e['data.optimale_max'] = 'La température optimale maximale ne peut pas être inférieure à la minimale.';
        }
        $sous = $this->requis($this->nombre($b['reduire_sous'] ?? null, $e, 'data.reduire_sous', 0, 45), $e, 'data.reduire_sous');
        if ($min !== null && $sous !== null && $sous > $min) {
            $e['data.reduire_sous'] = 'Le seuil de réduction de la ration ne peut pas dépasser la température optimale minimale.';
        }

        return ['optimale_min' => $min, 'optimale_max' => $max, 'reduire_sous' => $sous];
    }

    // ===================== AFFICHAGE (résumé des valeurs ; le poste a le même, parité exécutée) =====================

    public static function nb(mixed $v): string
    {
        if ($v === null || $v === '') {
            return '—';
        }
        $f = (float) $v;

        return floor($f) == $f ? (string) (int) $f : rtrim(rtrim(number_format($f, 2, ',', ''), '0'), ',');
    }

    private static function dateFr(?string $d): string
    {
        return $d ? Carbon::parse($d)->format('d/m/Y') : '—';
    }

    /** Résumé lisible des valeurs d'une ligne (colonne « Valeurs » du tableau). « — » = non renseigné, jamais 0. */
    public static function resume(string $type, array $d): string
    {
        $nb = fn ($v) => self::nb($v);
        $parties = match ($type) {
            self::INCUBATION_REGLE => [
                $nb($d['duree_jours'] ?? null).' j',
                'éclosion J'.$nb($d['eclosion_min'] ?? null).' à J'.$nb($d['eclosion_max'] ?? null),
                self::MODES[$d['mode'] ?? ''] ?? '—',
                'mirages '.(($d['mirages'] ?? []) === [] ? '—' : 'J'.implode(', J', $d['mirages'])),
                'éclosoir '.(isset($d['transfert_jour']) ? 'J'.$nb($d['transfert_jour']) : '—'),
                'œufs conservés ≤ '.$nb($d['conservation_max_jours'] ?? null).' j',
            ],
            self::INCUBATION_LOT => (function () use ($d, $nb) {
                $c = self::calculsLot($d);

                return [
                    'mise le '.self::dateFr($d['mise_date'] ?? null),
                    self::MODES[$d['mode'] ?? ''] ?? '—',
                    'mis '.$nb($d['oeufs_mis'] ?? null), 'fertiles '.$nb($d['oeufs_fertiles'] ?? null), 'éclos '.$nb($d['oeufs_eclos'] ?? null),
                    'durée observée '.($c['duree_jours'] === null ? '—' : $c['duree_jours'].' j'),
                    'fertilité '.($c['taux_fertilite'] === null ? '—' : $nb($c['taux_fertilite']).' %'),
                    'éclosion '.($c['taux_eclosion'] === null ? '—' : $nb($c['taux_eclosion']).' %'),
                ];
            })(),
            self::DELAI_REGLE => [
                self::MODES_DELAI[$d['mode'] ?? ''] ?? '—',
                'critique '.$nb($d['critique_jours'] ?? null).' j', 'alerte '.$nb($d['alerte_jours'] ?? null).' j', 'marge '.$nb($d['marge_jours'] ?? null).' j',
            ],
            self::POISSON_MARQUE => [($d['marque'] ?? null) ?: '—'],
            self::POISSON_BAREME => [
                match (true) {
                    ($d['poids_max_g'] ?? null) === null => 'plus de '.$nb($d['poids_min_g'] ?? null).' g',
                    (float) ($d['poids_min_g'] ?? 0) == 0.0 => 'moins de '.$nb($d['poids_max_g']).' g',
                    default => $nb($d['poids_min_g'] ?? null).' à '.$nb($d['poids_max_g']).' g',
                },
                $nb($d['biomasse_min_pct'] ?? null).' à '.$nb($d['biomasse_max_pct'] ?? null).' % de la biomasse par jour',
                'granulé : '.(($d['granule'] ?? null) ?: '—'), 'protéine : '.(isset($d['proteine_pct']) ? $nb($d['proteine_pct']).' %' : '—'),
            ],
            self::POISSON_TEMPERATURE => [
                'optimale '.$nb($d['optimale_min'] ?? null).' à '.$nb($d['optimale_max'] ?? null).' °C',
                'réduire la ration sous '.$nb($d['reduire_sous'] ?? null).' °C',
            ],
            self::POISSON_DENSITE => [isset($d['densite']) ? $nb($d['densite']).' '.($d['unite'] ?? '') : '— (à renseigner)'],
            default => [],
        };

        return trim(implode(' · ', $parties));
    }

    // ===================== CALCULS (jamais « 0 » quand une donnée manque : null → « — ») =====================

    /**
     * Calculs d'un relevé de lot : durée observée = premier éclos − mise en incubation (jours), taux de fertilité =
     * fertiles ÷ mis, taux d'éclosion = éclos ÷ fertiles (en %, 1 décimale). Donnée manquante ou dénominateur nul :
     * `null` (affiché « — »). Le poste fait le même calcul (`ReleveTerrain.calculsLot`, parité exécutée).
     *
     * @return array{duree_jours: ?int, taux_fertilite: ?float, taux_eclosion: ?float}
     */
    public static function calculsLot(array $data): array
    {
        $mise = $data['mise_date'] ?? null;
        $premier = $data['premier_eclos_date'] ?? null;
        $duree = null;
        if ($mise && $premier) {
            $duree = (int) Carbon::parse($mise)->startOfDay()->diffInDays(Carbon::parse($premier)->startOfDay(), false);
        }
        $mis = $data['oeufs_mis'] ?? null;
        $fertiles = $data['oeufs_fertiles'] ?? null;
        $eclos = $data['oeufs_eclos'] ?? null;

        return [
            'duree_jours' => $duree,
            'taux_fertilite' => ($mis !== null && $fertiles !== null && $mis > 0) ? round($fertiles / $mis * 100, 1) : null,
            'taux_eclosion' => ($fertiles !== null && $eclos !== null && $fertiles > 0) ? round($eclos / $fertiles * 100, 1) : null,
        ];
    }

    /**
     * Délais constatés par fournisseur de provende : les 5 DERNIERS bons de commande REÇUS portant une ligne de la
     * catégorie « Aliments », du jour du bon (`created_at`) au jour de la réception (`purchase_date` de l'achat que la
     * réception — `ReceptionBonCommandeService` — a écrit). Lecture seule.
     *
     * @return array<int, array{supplier_id: string, supplier: string, nb: int, bons: array, critique_propose: ?int}>
     */
    public static function delaisFournisseurs(): array
    {
        $bons = PurchaseOrder::with(['supplier', 'purchase', 'lines.product.category'])
            ->where('status', 'recu')->whereHas('purchase')->get()
            ->filter(fn (PurchaseOrder $b) => $b->lines->contains(fn ($l) => $l->product?->category?->label === 'Aliments'));

        $sortie = [];
        foreach ($bons->groupBy('supplier_id') as $supplierId => $groupe) {
            $tries = $groupe->sortByDesc(fn (PurchaseOrder $b) => $b->purchase->purchase_date->format('Y-m-d').$b->created_at->format('Y-m-d H:i:s').$b->id)
                ->take(self::NB_BONS)->values();
            $lignes = $tries->map(function (PurchaseOrder $b) {
                $date = $b->created_at->copy()->startOfDay();
                $recu = $b->purchase->purchase_date->copy()->startOfDay();

                return [
                    'bon_id' => $b->id, 'date_bon' => $date->format('Y-m-d'), 'date_reception' => $recu->format('Y-m-d'),
                    'delai_jours' => max(0, (int) $date->diffInDays($recu, false)),
                ];
            })->all();
            $sortie[] = [
                'supplier_id' => (string) $supplierId, 'supplier' => $tries->first()->supplier?->name ?? '—', 'nb' => count($lignes),
                'bons' => $lignes,
                'critique_propose' => count($lignes) >= self::NB_BONS ? max(array_column($lignes, 'delai_jours')) : null,
            ];
        }
        usort($sortie, fn ($a, $b) => strcmp(mb_strtolower($a['supplier']), mb_strtolower($b['supplier'])));

        return $sortie;
    }

    /**
     * Règle du délai fournisseur EN VIGUEUR : critique et alerte (jours) et leur source.
     *  - `constate` : la règle est VALIDÉE, en mode « le plus long des 5 » et au moins un fournisseur a 5 bons :
     *    critique = le plus long des 5 délais (le plus grand parmi les fournisseurs qui en ont 5), alerte = critique + marge ;
     *  - `manuel` : règle validée en mode « valeurs saisies » : les valeurs de la ligne ;
     *  - `depart` : sinon (moins de 5 bons, ou règle encore « À valider ») : valeurs de départ de la ligne (3 j / 7 j).
     * ⚠️ Tant que la règle n'est pas validée, le comportement reste celui d'avant (3 j) : rien ne change à l'insu de l'exploitant.
     *
     * @return array{critique: int, alerte: int, source: string, marge: int, statut: ?string}
     */
    public static function regleEnVigueur(): array
    {
        $ligne = FieldSurveyEntry::where('type', self::DELAI_REGLE)->where('is_active', true)->orderBy('id')->first();
        $d = $ligne?->data ?? [];
        $critique = (int) ($d['critique_jours'] ?? self::CRITIQUE_DEPART);
        $alerte = (int) ($d['alerte_jours'] ?? self::ALERTE_DEPART);
        $marge = (int) ($d['marge_jours'] ?? self::MARGE_DEFAUT);
        $mode = $d['mode'] ?? 'constate';
        $source = 'depart';

        if ($ligne !== null && $ligne->status === self::VALIDE) {
            if ($mode === 'manuel') {
                $source = 'manuel';
            } else {
                $propositions = array_filter(array_column(self::delaisFournisseurs(), 'critique_propose'), fn ($v) => $v !== null);
                if ($propositions !== []) {
                    $critique = max($propositions);
                    $alerte = $critique + $marge;
                    $source = 'constate';
                }
            }
        }

        return ['critique' => $critique, 'alerte' => $alerte, 'source' => $source, 'marge' => $marge, 'statut' => $ligne?->status];
    }

    /** Seuil CRITIQUE d'autonomie (jours) lu par l'alerte d'autonomie alimentaire : 3 j tant que rien n'est validé. */
    public static function seuilCritiqueJours(): float
    {
        return (float) self::regleEnVigueur()['critique'];
    }

    /**
     * Synthèse du bloc « Relevés de terrain » du Dashboard Élevage (le poste la calcule à l'identique) : référentiels
     * « À valider », taux moyens (moyenne des taux des lots relevés, « — » sans lot), durée observée moyenne et durée
     * de la règle des mêmes lots, règle du délai fournisseur retenue.
     *
     * @return array<string, mixed>
     */
    public function synthese(): array
    {
        $lots = FieldSurveyEntry::where('type', self::INCUBATION_LOT)->where('is_active', true)->get();
        $regles = FieldSurveyEntry::where('type', self::INCUBATION_REGLE)->where('is_active', true)->get()->keyBy('species_code');

        $fertilite = $eclosion = $durees = $dureesRegle = [];
        foreach ($lots as $lot) {
            $c = self::calculsLot($lot->data ?? []);
            if ($c['taux_fertilite'] !== null) {
                $fertilite[] = $c['taux_fertilite'];
            }
            if ($c['taux_eclosion'] !== null) {
                $eclosion[] = $c['taux_eclosion'];
            }
            if ($c['duree_jours'] !== null) {
                $durees[] = $c['duree_jours'];
                $regle = $regles->get($lot->species_code)?->data['duree_jours'] ?? null;
                if ($regle !== null) {
                    $dureesRegle[] = (int) $regle;
                }
            }
        }
        $moy = fn (array $v) => $v === [] ? null : round(array_sum($v) / count($v), 1);
        $delais = self::delaisFournisseurs();

        return [
            'a_valider' => $this->nombreAValider(),
            'nb_lots' => $lots->count(),
            'fertilite_moyenne' => $moy($fertilite),
            'eclosion_moyenne' => $moy($eclosion),
            'duree_observee_moyenne' => $moy($durees),
            'duree_regle_moyenne' => $moy($dureesRegle),
            'delai' => self::regleEnVigueur(),
            'delai_constate_max' => $delais === [] ? null : max(array_map(fn ($f) => max(array_column($f['bons'], 'delai_jours')), $delais)),
        ];
    }
}
