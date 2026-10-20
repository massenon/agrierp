<?php

namespace App\Support;

use App\Models\FiscalYear;
use Carbon\CarbonInterface;
use Illuminate\Support\Carbon;

/**
 * Ticket EX7 (EF8, EF9, EF10 du PRD `docs/prd/exercices-comptables.md`) — L'EXERCICE AFFICHÉ, point de passage unique.
 *
 * Toute lecture de « l'exercice que l'utilisateur regarde » passe par ici : le sélecteur de la barre supérieure
 * (`Shared\SelecteurExercice`), le bandeau de lecture seule (`Shared\BandeauExercice`), la Balance (« Exercice 2026 »),
 * les États financiers, le Plan comptable, le tableau de bord, les périodes par défaut des états et des écrans de
 * modules, et les listes paginées dans l'exercice. Le poste a sa copie (`lib/core/comptabilite/exercice_choisi.dart`),
 * tenue identique par `test/selecteur_exercice_test.dart`.
 *
 * ⚠️ AFFICHER ≠ ÉCRIRE. Ce choix ne décide JAMAIS de l'exercice d'une saisie : une saisie appartient à l'exercice qui
 * contient SA DATE (R4), jugé au serveur par `AccountingEntryService::exerciceOuvertPour()` / `refusExerciceClos()`
 * (EX5), quel que soit l'exercice affiché. `FiscalYear::current()` (le plus récent ouvert) reste donc là où il sert à
 * écrire ou à décider (clôture, ouverture), et ne sert plus à afficher.
 *
 * ⚠️ Le grisé des boutons dans un exercice clos (`@lectureSeule`, EF10) est un CONFORT : la garantie reste le refus du
 * serveur. Un appel direct à une méthode Livewire est jugé sur sa date, comme avant.
 *
 * Choix mémorisé en SESSION (`exercice_choisi` : l'année) ; par défaut, l'exercice qui contient la date du jour à
 * l'heure du Bénin, sinon le plus récent (le 1er janvier avant l'ouverture de N+1, par exemple).
 */
final class ExerciceChoisi
{
    public const CLE_SESSION = 'exercice_choisi';

    /** Lignes par page des listes paginées dans l'exercice (doctrine, § 2 : 10 ou 25). */
    public const PAR_PAGE = 25;

    /** Libellés des badges du sélecteur (PRD § 7). Le poste les reprend mot pour mot. */
    public const LIBELLES = ['ouvert' => 'Ouvert', 'provisoire' => 'Provisoire', 'cloture' => 'Clôturé'];

    /** Aujourd'hui à l'heure du Bénin, jamais à l'heure UTC d'un serveur mal réglé (comme `OuvertureExerciceService`). */
    public static function aujourdhui(): CarbonInterface
    {
        return now()->copy()->setTimezone('Africa/Porto-Novo')->startOfDay();
    }

    /** L'exercice affiché : celui de la session s'il existe encore, sinon le défaut. `null` : aucun exercice en base. */
    public static function exercice(): ?FiscalYear
    {
        $annee = session(self::CLE_SESSION);

        if (is_int($annee) || ctype_digit((string) $annee)) {
            $choisi = FiscalYear::where('year', (int) $annee)->first();
            if ($choisi) {
                return $choisi;
            }
        }

        return self::parDefaut();
    }

    /** L'exercice qui contient le jour (heure du Bénin) ; à défaut le plus récent. */
    public static function parDefaut(): ?FiscalYear
    {
        $jour = self::aujourdhui()->format('Y-m-d');

        return FiscalYear::whereDate('start_date', '<=', $jour)->whereDate('end_date', '>=', $jour)->orderBy('start_date')->first()
            ?? FiscalYear::orderByDesc('year')->first();
    }

    /** Année affichée ; l'année civile du jour si aucun exercice n'existe encore. */
    public static function annee(): int
    {
        return (int) (self::exercice()?->year ?? self::aujourdhui()->year);
    }

    /** Mémorise le choix. Faux (et rien ne change) si l'exercice n'existe pas. */
    public static function choisir(int $annee): bool
    {
        if (! FiscalYear::where('year', $annee)->exists()) {
            return false;
        }

        session([self::CLE_SESSION => $annee]);

        return true;
    }

    /**
     * Statut d'un exercice pour son badge : `cloture` ; `provisoire` = ouvert ET l'exercice précédent n'est pas clos
     * (ses à-nouveaux sont calculés, R3) ; `ouvert` sinon (précédent clos, ou premier exercice).
     *
     * ⚠️ MÊME PRÉDICAT que `FinancialReportService::ouverture()` (mode `provisoire`) : un exercice enregistré commence
     * avant celui-ci, et l'exercice qui contient la veille de son premier jour n'est pas clos (absent = traité comme
     * ouvert, comme au service).
     */
    public static function statutDe(FiscalYear $exercice): string
    {
        if ($exercice->status === 'cloture') {
            return 'cloture';
        }

        $debut = $exercice->start_date->format('Y-m-d');
        if (! FiscalYear::whereDate('start_date', '<', $debut)->exists()) {
            return 'ouvert';
        }

        $veille = $exercice->start_date->copy()->subDay()->format('Y-m-d');
        $precedent = FiscalYear::whereDate('start_date', '<=', $veille)->whereDate('end_date', '>=', $veille)->orderBy('start_date')->first();

        return $precedent?->status === 'cloture' ? 'ouvert' : 'provisoire';
    }

    /**
     * Les exercices du sélecteur, le plus récent d'abord.
     *
     * @return array<int, array{annee: int, statut: string, libelle: string, choisi: bool}>
     */
    public static function liste(): array
    {
        $choisi = self::exercice()?->year;

        return FiscalYear::orderByDesc('year')->get()
            ->map(function (FiscalYear $e) use ($choisi) {
                $statut = self::statutDe($e);

                return ['annee' => (int) $e->year, 'statut' => $statut, 'libelle' => self::LIBELLES[$statut], 'choisi' => (int) $e->year === (int) $choisi];
            })
            ->all();
    }

    /**
     * Bornes de l'exercice affiché (`Y-m-d`) ; l'année civile du jour si aucun exercice n'existe.
     *
     * @return array{0: string, 1: string}
     */
    public static function bornes(): array
    {
        $exercice = self::exercice();

        if ($exercice) {
            return [$exercice->start_date->format('Y-m-d'), $exercice->end_date->format('Y-m-d')];
        }

        $annee = self::aujourdhui()->year;

        return ["{$annee}-01-01", "{$annee}-12-31"];
    }

    /** L'exercice affiché contient-il le jour ? */
    public static function contientAujourdhui(): bool
    {
        [$debut, $fin] = self::bornes();
        $jour = self::aujourdhui()->format('Y-m-d');

        return $debut <= $jour && $jour <= $fin;
    }

    public static function estClos(): bool
    {
        return self::exercice()?->status === 'cloture';
    }

    /**
     * L'exercice où se font les saisies du jour (texte du bandeau, lien « Passer à … ») : l'exercice OUVERT qui
     * contient le jour, sinon le plus récent ouvert (`FiscalYear::current()`, qui sert ici à ÉCRIRE).
     */
    public static function exerciceDeSaisie(): ?FiscalYear
    {
        $jour = self::aujourdhui()->format('Y-m-d');

        return FiscalYear::where('status', 'ouvert')->whereDate('start_date', '<=', $jour)->whereDate('end_date', '>=', $jour)->first()
            ?? FiscalYear::current();
    }

    /** Motif des boutons grisés (info-bulle) : « Exercice 2026 clôturé — lecture seule » ; `null` : exercice ouvert. */
    public static function motifLectureSeule(): ?string
    {
        return self::motifLectureSeuleDe(self::exercice());
    }

    /**
     * Le motif de lecture seule d'un exercice DONNÉ : celui de l'exercice affiché (`motifLectureSeule`), ou, pour une
     * fiche d'élevage (EF12, ticket EX8), celui de l'exercice qui contient le jour choisi (`exerciceDuJour`).
     */
    public static function motifLectureSeuleDe(?FiscalYear $exercice): ?string
    {
        return $exercice?->status === 'cloture' ? "Exercice {$exercice->year} clôturé — lecture seule" : null;
    }

    /**
     * L'exercice qui contient [$date] (le premier par date de début, comme `AccountingEntryService::exerciceQuiCouvre`) ;
     * `null` si aucun ne la couvre — rien n'est alors en lecture seule (le refus du serveur, R4, ne joue pas non plus).
     */
    public static function exerciceDuJour(string $date): ?FiscalYear
    {
        $jour = substr($date, 0, 10);

        return FiscalYear::whereDate('start_date', '<=', $jour)->whereDate('end_date', '>=', $jour)->orderBy('start_date')->first();
    }

    /**
     * Le bandeau de lecture seule (EF10, PRD § 7) : `texte` et l'année vers laquelle « Passer à … » mène (`null` : aucun
     * exercice ouvert, pas de lien). `null` : exercice ouvert, pas de bandeau.
     *
     * @return array{texte: string, cible: ?int}|null
     */
    public static function bandeau(): ?array
    {
        return self::bandeauDe(self::exercice());
    }

    /**
     * Le bandeau de lecture seule d'un exercice DONNÉ — même texte, même lien, que ce soit l'exercice affiché (en haut
     * du contenu) ou celui du jour d'une fiche d'élevage (EF12). `null` : exercice ouvert (ou inconnu).
     *
     * @return array{texte: string, cible: ?int}|null
     */
    public static function bandeauDe(?FiscalYear $exercice): ?array
    {
        $motif = self::motifLectureSeuleDe($exercice);
        if ($motif === null) {
            return null;
        }

        $saisie = self::exerciceDeSaisie();

        return [
            'texte' => $motif.'.'.($saisie ? " Les saisies se font dans l'exercice {$saisie->year}." : ''),
            'cible' => $saisie ? (int) $saisie->year : null,
        ];
    }

    /**
     * Attributs HTML d'un bouton de saisie (Nouveau, Modifier, Archiver, Enregistrer) quand l'exercice affiché est clos :
     * grisé (`data-lecture-seule`, voir `app.css`), désactivé, motif en info-bulle. Vide sinon. Émis par la directive
     * `@lectureSeule`, placée JUSTE APRÈS `<button` : le premier `title` d'un élément est celui que le navigateur garde.
     */
    public static function attributs(?string $motif): string
    {
        return $motif === null ? '' : ' disabled aria-disabled="true" data-lecture-seule title="'.e($motif).'"';
    }

    /** Une date ramenée dans l'exercice affiché. */
    public static function borner(string $date): string
    {
        [$debut, $fin] = self::bornes();
        $jour = substr($date, 0, 10);

        return $jour < $debut ? $debut : ($jour > $fin ? $fin : $jour);
    }

    /**
     * Période par défaut d'un écran : celle de l'écran (`$debut` → `$fin`, ex. du 1er du mois à aujourd'hui), ramenée
     * dans l'exercice affiché quand il contient le jour ; l'exercice entier sinon (2026 consulté en 2027).
     *
     * @return array{0: string, 1: string}
     */
    public static function periodeParDefaut(string $debut, string $fin): array
    {
        if (! self::contientAujourdhui()) {
            return self::bornes();
        }

        return [self::borner($debut), self::borner($fin)];
    }

    /** Une période saisie, ramenée dans l'exercice affiché (début ≤ fin). @return array{0: string, 1: string} */
    public static function bornerPeriode(string $debut, string $fin): array
    {
        $debut = self::borner($debut === '' ? self::bornes()[0] : $debut);
        $fin = self::borner($fin === '' ? self::bornes()[1] : $fin);

        return $debut <= $fin ? [$debut, $fin] : [$debut, $debut];
    }

    /**
     * Date d'arrêté par défaut d'un état de l'exercice affiché (Bilan, États financiers et leurs colonnes N / N-1,
     * Balance « mois ») : aujourd'hui s'il le contient, sinon sa fin (ou son début) — `arreteDe(annee())`.
     */
    public static function dateArrete(): string
    {
        return self::arreteDe(self::annee());
    }

    /**
     * Tickets EX7 + EX8 — LA RÈGLE de la date d'arrêté des états d'un exercice [$annee] : aujourd'hui (heure du Bénin)
     * s'il est en cours, sa clôture s'il est passé, son premier jour s'il est à venir ; l'année civile s'il n'est pas
     * enregistré. `FinancialReportService::arreteDeLExercice()` (EX8) y renvoie : une seule règle, un seul fuseau.
     */
    public static function arreteDe(int $annee): string
    {
        $exercice = FiscalYear::where('year', $annee)->first();
        $debut = $exercice?->start_date->format('Y-m-d') ?? "{$annee}-01-01";
        $fin = $exercice?->end_date->format('Y-m-d') ?? "{$annee}-12-31";
        $jour = self::aujourdhui()->format('Y-m-d');

        return $jour < $debut ? $debut : ($jour > $fin ? $fin : $jour);
    }

    /** Premier jour du mois de référence : le mois du jour s'il est dans l'exercice affiché, sinon son dernier mois. */
    public static function moisDeReference(): Carbon
    {
        return Carbon::parse(self::dateArrete())->startOfMonth();
    }

    /**
     * Les mois de l'exercice affiché, du mois de référence au premier (`Y-m` => « Décembre 2026 »), comme les listes
     * de périodes de la Déclaration TVA et du Rapport mensuel.
     *
     * @return array<string, string>
     */
    public static function moisDeLExercice(): array
    {
        $debut = Carbon::parse(self::bornes()[0])->startOfMonth();
        $mois = [];

        for ($m = self::moisDeReference(); $m->greaterThanOrEqualTo($debut); $m = $m->copy()->subMonthNoOverflow()) {
            $mois[$m->format('Y-m')] = ucfirst($m->translatedFormat('F Y'));
        }

        return $mois;
    }

    /** Un mois `Y-m` ramené dans l'exercice affiché (le mois de référence s'il en sort). */
    public static function bornerMois(string $mois): string
    {
        return array_key_exists($mois, self::moisDeLExercice()) ? $mois : self::moisDeReference()->format('Y-m');
    }
}
