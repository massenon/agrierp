<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\FiscalYear;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;

/**
 * Ticket EX3 (PRD `docs/prd/exercices-comptables.md`, règle R2, EF2, défaut C2) — POINT DE PASSAGE UNIQUE de l'ouverture
 * de l'exercice N+1 SANS attendre la clôture de N.
 *
 * ⚠️⚠️ LE DÉFAUT. N+1 n'était créé que par la clôture de N (`ClotureExercice::confirmCloture`) ou par l'assistant de
 * démarrage, qui disparaît une fois la mise en route terminée. Le 1er janvier, toute vente, dépense, achat ou paie datée
 * du jour finissait en `NoOpenFiscalYearException` (erreur 500 à la caisse) jusqu'à la clôture — qui se fait en mars,
 * après le bilan.
 *
 * Trois chemins, une seule règle (`refusOuverture`) :
 *  - la TÂCHE PLANIFIÉE du 01/01 à 00:00, heure du Bénin (`agrierp:ouvrir-exercice`, `routes/console.php`) ;
 *  - le FILET (`filet`) : si la tâche n'a pas tourné (cron absent), la première saisie datée de N+1 crée N+1 avant tout
 *    refus — seulement si N est l'exercice ouvert le plus récent et que l'on est déjà en N+1 (le filet remplace la tâche,
 *    il ne la devance pas) ;
 *  - le BOUTON « Ouvrir l'exercice N+1 » de l'écran Clôture, à partir du 1er décembre de N (`close-fiscal-year`).
 *
 * Refus communs : l'exercice précédent doit exister (jamais d'année sautée : N+2 n'existe jamais tant que N+1 manque),
 * et jamais plus de DEUX exercices ouverts en même temps (N et N+1) — donc jamais N+2 tant que N est ouvert. L'exercice
 * créé est civil (01/01 → 31/12), ouvert. Jamais de doublon : `year` est unique en base, et une création simultanée
 * (deux envois de postes au même instant) relit l'exercice créé par l'autre au lieu d'échouer.
 */
class OuvertureExerciceService
{
    public const TACHE = 'tache';

    public const FILET = 'filet';

    public const BOUTON = 'bouton';

    /** Action d'audit par origine (libellés : `AuditLog::ACTION_LABELS`, copiés au poste par `libelles_audit.py`). */
    private const AUDIT = [
        self::TACHE => 'fiscal_year.opened_auto',
        self::FILET => 'fiscal_year.opened_on_first_entry',
        self::BOUTON => 'fiscal_year.opened',
    ];

    /**
     * Pourquoi l'exercice [$annee] ne peut pas être ouvert aujourd'hui par [$origine] — `null` s'il le peut.
     */
    public function refusOuverture(int $annee, string $origine, ?CarbonInterface $aujourdhui = null): ?string
    {
        $aujourdhui = $this->aujourdhui($aujourdhui);

        if (FiscalYear::where('year', $annee)->exists()) {
            return "L'exercice {$annee} existe déjà.";
        }

        $precedent = FiscalYear::where('year', $annee - 1)->first();
        if ($precedent === null) {
            return "L'exercice {$annee} ne peut s'ouvrir qu'à la suite de l'exercice ".($annee - 1).", qui n'existe pas.";
        }

        // Le bouton dès le 1er décembre de N ; la tâche et le filet le 1er janvier de N+1.
        $premierJour = $origine === self::BOUTON
            ? Carbon::create($annee - 1, 12, 1, 0, 0, 0, $aujourdhui->getTimezone())
            : Carbon::create($annee, 1, 1, 0, 0, 0, $aujourdhui->getTimezone());
        if ($aujourdhui->lt($premierJour)) {
            return "L'exercice {$annee} ne peut s'ouvrir qu'à partir du {$premierJour->format('d/m/Y')}.";
        }

        // Le filet ne joue que si N est l'exercice OUVERT le plus récent (R2).
        if ($origine === self::FILET && $precedent->status !== 'ouvert') {
            return "L'exercice ".($annee - 1)." est clôturé et l'exercice {$annee} n'existe pas.";
        }

        $ouverts = FiscalYear::where('status', 'ouvert')->orderBy('year')->pluck('year')->all();
        if (count($ouverts) >= 2) {
            return 'Deux exercices sont déjà ouverts ('.implode(' et ', $ouverts).") : clôturez l'exercice {$ouverts[0]} avant d'ouvrir {$annee}.";
        }

        return null;
    }

    /**
     * Ouvre l'exercice [$annee] (01/01 → 31/12, ouvert) et laisse sa trace d'audit.
     *
     * @throws \DomainException  avec le motif de `refusOuverture`, si l'ouverture n'est pas admise
     */
    public function ouvrir(int $annee, string $origine, ?CarbonInterface $aujourdhui = null): FiscalYear
    {
        $refus = $this->refusOuverture($annee, $origine, $aujourdhui);
        if ($refus !== null) {
            throw new \DomainException($refus);
        }

        try {
            // Point de sauvegarde : une violation d'unicité n'annule pas la transaction de l'appelant (envoi d'un poste).
            $exercice = DB::transaction(fn () => FiscalYear::create([
                'year' => $annee,
                'start_date' => "{$annee}-01-01",
                'end_date' => "{$annee}-12-31",
                'status' => 'ouvert',
            ]));
        } catch (UniqueConstraintViolationException) {
            // Ouvert au même instant par une autre requête : relu SOUS VERROU (une lecture simple verrait l'instantané
            // de la transaction en cours, où il n'existe pas encore — piège S-T12).
            return FiscalYear::where('year', $annee)->lockForUpdate()->firstOrFail();
        }

        AuditLog::record(self::AUDIT[$origine] ?? 'fiscal_year.opened', 'comptabilite');

        return $exercice;
    }

    /**
     * Le FILET de R2 : aucun exercice ne couvre [$date] — l'exercice de cette année peut-il être ouvert maintenant, à la
     * place de la tâche du 1er janvier qui n'a pas tourné ? L'ouvre et le rend, ou `null` (le refus R4 suivra).
     */
    public function filet(string $date): ?FiscalYear
    {
        $annee = (int) Carbon::parse($date)->format('Y');

        if ($this->refusOuverture($annee, self::FILET) !== null) {
            return null;
        }

        return $this->ouvrir($annee, self::FILET);
    }

    /** Le filet ouvrirait-il l'exercice de [$date] ? Sans rien écrire (bornes indicatives d'un calendrier). */
    public function filetCouvrirait(string $date): bool
    {
        return $this->refusOuverture((int) Carbon::parse($date)->format('Y'), self::FILET) === null;
    }

    /** Aujourd'hui à l'heure du Bénin (`app.timezone`), jamais à l'heure UTC d'un serveur mal réglé. */
    private function aujourdhui(?CarbonInterface $aujourdhui): CarbonInterface
    {
        return ($aujourdhui ?? now())->copy()->setTimezone('Africa/Porto-Novo');
    }
}
