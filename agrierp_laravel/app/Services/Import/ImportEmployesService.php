<?php

namespace App\Services\Import;

use App\Actions\SaisieEmployeAction;
use App\Models\Employee;

/**
 * Ticket IMPORT-2 — MODULE « EMPLOYÉS ».
 *
 * Point de passage UNIQUE : `SaisieEmployeAction::creer` ; règles : `SaisieEmployeAction::regles()`, mot pour mot (noms de
 * colonne dans les messages = ceux du web : « prénom », « nom », « poste », « date d'embauche », « salaire de base »,
 * « statut »). Droit : `manage-rh`.
 *
 * IDEMPOTENCE — clé NORMALISÉE nom + prénom + date d'embauche (`LectureValeurs::cle`, dates AAAA-MM-JJ) ; les employés ne sont
 * PAS un référentiel fusionné entre postes (`FusionReferentielsService::MODELES`) : l'index est lu ici. DÉCISION : seul un
 * employé ACTIF compte comme « déjà présent » (un employé archivé ne bloque pas, comme pour clients et fournisseurs) ; l'employé
 * déjà importé (même identifiant déterministe) est toujours reconnu, archivé ou non. Création SEULE : jamais de modification.
 *
 * ⚠️ DONNÉE SENSIBLE : le salaire de base ne figure JAMAIS au rapport ni au journal (`colonnesSensibles`).
 */
class ImportEmployesService extends ModuleImport
{
    public const EMPREINTE_V1 = '1f72d43e9afee29825419dbe125cda1bf2a942dd213911d78669236ce0af35be';

    /** champ du service → clé de colonne */
    private const CHAMPS = [
        'last_name' => 'nom', 'first_name' => 'prenom', 'position' => 'poste',
        'hire_date' => 'date_embauche', 'base_salary' => 'salaire', 'status' => 'statut',
    ];

    /** Libellés de la liste « Statut » (l'écran Employés : « Actif », « Congé », « Suspendu »). */
    public const STATUTS = ['actif' => 'Actif', 'conge' => 'Congé', 'suspendu' => 'Suspendu'];

    /** @var array<string, true>|null */
    private ?array $index = null;

    public function cle(): string
    {
        return 'employes';
    }

    public function libelle(): string
    {
        return 'Employés';
    }

    public function description(): string
    {
        return "Registre des employés : nom, prénom, poste, date d'embauche, salaire de base et statut.";
    }

    public function icone(): string
    {
        return 'badge';
    }

    public function permission(): string
    {
        return 'manage-rh';
    }

    public function moduleAudit(): string
    {
        return 'rh';
    }

    public function version(): int
    {
        return 1;
    }

    public function empreinteAttendue(): string
    {
        return self::EMPREINTE_V1;
    }

    public function colonnes(): array
    {
        return [
            new ColonneImport('nom', 'Nom', true, 'texte', '100 caractères au plus.'),
            new ColonneImport('prenom', 'Prénom', true, 'texte', '100 caractères au plus.'),
            new ColonneImport('poste', 'Poste', true, 'texte', 'La fonction de l\'employé (exemple : Gardien).'),
            new ColonneImport('date_embauche', 'Date d\'embauche', true, 'date', 'Au format AAAA-MM-JJ (exemple : 2026-11-08).'),
            new ColonneImport('salaire', 'Salaire de base (FCFA)', false, 'entier', 'Nombre entier de FCFA, 0 ou plus. Donnée sensible : jamais reproduite au rapport.'),
            new ColonneImport('statut', 'Statut', false, 'liste', 'Une valeur de la liste déroulante. Vide : Actif.', 'statuts'),
        ];
    }

    public function listes(): array
    {
        return ['statuts' => array_values(self::STATUTS)];
    }

    public function exemples(): array
    {
        return [
            ['nom' => 'AGBOTON', 'prenom' => 'Pascal', 'poste' => 'Gardien', 'date_embauche' => '2024-03-01', 'salaire' => '45000', 'statut' => 'Actif'],
            ['nom' => 'DOSSOU', 'prenom' => 'Clarisse', 'poste' => 'Aide-soignante des animaux', 'date_embauche' => '2025-09-15', 'salaire' => '', 'statut' => ''],
        ];
    }

    public function notes(): array
    {
        return [
            'Un employé ACTIF dont le nom, le prénom ET la date d\'embauche existent déjà est IGNORÉ ; la fiche existante n\'est jamais modifiée.',
            'Le salaire de base est facultatif et ne figure jamais dans le rapport d\'importation.',
            'La date d\'embauche s\'écrit AAAA-MM-JJ, comme du texte (les cellules du modèle sont déjà au format texte).',
        ];
    }

    public function colonnesSensibles(): array
    {
        return ['salaire'];
    }

    protected function attributs(): array
    {
        return [
            'nom' => 'nom', 'prenom' => 'prénom', 'poste' => 'poste', 'date_embauche' => "date d'embauche",
            'salaire' => 'salaire de base', 'statut' => 'statut',
        ];
    }

    public function designation(array $brut): string
    {
        return trim(LectureValeurs::texte($brut['prenom'] ?? null).' '.LectureValeurs::texte($brut['nom'] ?? null));
    }

    public function valider(array $brut): array
    {
        $erreurs = [];

        $texteDate = LectureValeurs::texte($brut['date_embauche'] ?? null);
        $date = '';
        if ($texteDate !== '') {
            if (preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $texteDate, $m) === 1 && checkdate((int) $m[2], (int) $m[3], (int) $m[1])) {
                $date = $texteDate;
            } else {
                $erreurs['date_embauche'] = "Date invalide : « {$texteDate} ». Écrivez la date au format AAAA-MM-JJ (exemple : 2026-11-08).";
            }
        }

        $texteStatut = LectureValeurs::texte($brut['statut'] ?? null);
        $statut = 'actif';
        if ($texteStatut !== '') {
            $statut = '';
            foreach (self::STATUTS as $cle => $libelle) {
                if (in_array(LectureValeurs::cle($texteStatut), [LectureValeurs::cle($libelle), $cle], true)) {
                    $statut = $cle;
                }
            }
            if ($statut === '') {
                $erreurs['statut'] = "Statut inconnu : « {$texteStatut} ». Choisissez une valeur de la liste déroulante.";
            }
        }

        $texteSalaire = LectureValeurs::texte($brut['salaire'] ?? null);
        $salaire = null;
        if ($texteSalaire !== '') {
            $salaire = LectureValeurs::entier($texteSalaire);
            if ($salaire === null) {
                $erreurs['salaire'] = 'Montant invalide : un nombre entier de FCFA est attendu.';
            }
        }

        $donnees = [
            'last_name' => LectureValeurs::texte($brut['nom'] ?? null),
            'first_name' => LectureValeurs::texte($brut['prenom'] ?? null),
            'position' => LectureValeurs::texte($brut['poste'] ?? null),
            'hire_date' => $date,
            'base_salary' => $salaire,
            'status' => $statut,
        ];

        $this->appliquerRegles($donnees, SaisieEmployeAction::regles(), [], self::CHAMPS, $erreurs);

        return ['valeurs' => $donnees, 'erreurs' => $erreurs];
    }

    public function cleLigne(array $valeurs): string
    {
        return LectureValeurs::cle((string) $valeurs['last_name']).'|'.LectureValeurs::cle((string) $valeurs['first_name']).'|'.substr((string) $valeurs['hire_date'], 0, 10);
    }

    public function dejaPresente(array $valeurs): ?string
    {
        if (Employee::whereKey($this->idLigne($valeurs))->exists()) {
            return 'Cet employé a déjà été importé : ignoré.';
        }

        $this->index ??= $this->construireIndex();
        if (isset($this->index[$this->cleLigne($valeurs)])) {
            return 'Cet employé existe déjà (même nom, même prénom, même date d\'embauche) : ignoré, la fiche existante est gardée.';
        }

        return null;
    }

    public function ecrire(array $valeurs, string $id): void
    {
        app(SaisieEmployeAction::class)->creer($valeurs, $id);
        $this->index ??= $this->construireIndex();
        $this->index[$this->cleLigne($valeurs)] = true;
    }

    /** @return array<string, true> les employés ACTIFS, sous la clé de ligne */
    private function construireIndex(): array
    {
        $index = [];
        foreach (Employee::where('is_active', true)->get(['last_name', 'first_name', 'hire_date']) as $e) {
            $index[$this->cleLigne([
                'last_name' => $e->last_name, 'first_name' => $e->first_name, 'hire_date' => $e->hire_date?->format('Y-m-d') ?? '',
            ])] = true;
        }

        return $index;
    }
}
