<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\PosteSynchronisation;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Date;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * Ticket SW-1 (correction du client du 21/10/2026) — LE WEB FAIT AUSSI REVENIR LES DONNÉES VERS LES POSTES.
 *
 * Le serveur est la base, mais un poste n'a pas forcément tout reçu : le portable a servi au web pendant la panne du
 * poste de bureau, et celui-ci, réparé, doit récupérer ce qui a été saisi entre-temps. Ce service répond à
 * « quels postes n'ont pas encore reçu ce qui a été fait au web ? » et porte le geste « Renvoyer vers ce poste » :
 *
 *  1. [noterTirage] — à la dernière page de chaque tirage, le serveur mémorise le curseur rendu au poste (son futur
 *     `since`) ; sans cela, il ne pourrait pas compter ce qui lui reste à recevoir ;
 *  2. [retard] — nombre de lignes modifiées depuis ce curseur (`updated_at > curseur`, comme le tirage), par type ;
 *  3. [demanderPoste] / [demanderTous] — lèvent le drapeau `resync_demandee_le`. Le poste le lit au tirage et au ping
 *     (`GET /api/sync/demande`), repart d'un tirage COMPLET (sans `since`), puis l'[acquitter] : le drapeau tombe.
 *
 * ⚠️ Le compte vaut pour TOUT ce que le serveur sert (web et saisies des autres postes), pas pour les seules saisies du
 * web : c'est ce que ce poste doit encore recevoir. Les lignes que CE poste a lui-même envoyées depuis son tirage
 * comptent aussi tant qu'il n'a pas retiré (au plus un tirage de confirmation).
 */
class ResynchronisationPostesService
{
    /**
     * Types comptés : table → [pluriel, singulier]. Seules les tables que le tirage sert d'après `updated_at` ; les
     * lignes de pièces (lignes de vente, d'écriture) voyagent avec leur pièce et ne sont pas comptées à part.
     *
     * @var array<string, array{0: string, 1: string}>
     */
    public const TYPES = [
        'sales' => ['ventes', 'vente'],
        'purchases' => ['achats', 'achat'],
        'expenses' => ['dépenses', 'dépense'],
        'products' => ['articles', 'article'],
        'customers' => ['clients', 'client'],
        'suppliers' => ['fournisseurs', 'fournisseur'],
        'livestock_lots' => ['bandes', 'bande'],
        'livestock_daily_entries' => ['fiches journalières', 'fiche journalière'],
        'veterinary_records' => ['soins', 'soin'],
        'customer_advances' => ['avances', 'avance'],
        'stock_movements' => ['mouvements de stock', 'mouvement de stock'],
        'accounting_entries' => ['écritures comptables', 'écriture comptable'],
    ];

    /**
     * Nom du poste qui parle : celui de son jeton Sanctum (S-T2). `null` pour un jeton transitoire (session web,
     * `actingAs` des tests) : il ne nomme aucun poste, et lire son `name` serait une erreur.
     */
    public static function nomDuPoste(?\Illuminate\Http\Request $request): ?string
    {
        $jeton = $request?->user()?->currentAccessToken();

        return $jeton instanceof PersonalAccessToken && is_string($jeton->name) && $jeton->name !== '' ? $jeton->name : null;
    }

    /** Mémorise le curseur rendu à un poste par un tirage terminé (dernière page). Ne lève jamais vers l'appelant. */
    public function noterTirage(string $poste, Carbon $curseur, ?Carbon $maintenant = null): void
    {
        PosteSynchronisation::updateOrCreate(
            ['poste' => $poste],
            [
                // Instant en heure MURALE du serveur, comme `updated_at` (même règle que le tirage lui-même, S-T12).
                'curseur_tirage' => Date::instance($curseur)->setTimezone(config('app.timezone')),
                'dernier_tirage_le' => $maintenant ?? now(),
            ],
        );
    }

    /**
     * Ce que ce poste n'a pas encore reçu.
     *
     * @return array{curseur: ?Carbon, dernier_tirage: ?Carbon, nombre: ?int, details: array<string, int>, resume: string, jours: ?int, etat: string, libelle: string, resync_demandee_le: ?Carbon, resync_acquittee_le: ?Carbon}
     */
    public function retard(string $poste, ?Carbon $maintenant = null): array
    {
        $maintenant ??= now();
        $ligne = PosteSynchronisation::query()->where('poste', $poste)->first();

        $base = [
            'curseur' => $ligne?->curseur_tirage,
            'dernier_tirage' => $ligne?->dernier_tirage_le,
            'resync_demandee_le' => $ligne?->resync_demandee_le,
            'resync_acquittee_le' => $ligne?->resync_acquittee_le,
        ];

        if ($ligne === null || $ligne->curseur_tirage === null) {
            // Inconnu : « — », jamais 0 (Doctrine, article 2).
            return $base + ['nombre' => null, 'details' => [], 'resume' => '—', 'jours' => null, 'etat' => 'jamais', 'libelle' => 'Jamais synchronisé'];
        }

        $details = [];
        $morceaux = [];
        foreach (self::TYPES as $table => [$pluriel, $singulier]) {
            $n = DB::table($table)->where('updated_at', '>', $ligne->curseur_tirage)->count();
            if ($n > 0) {
                $details[ucfirst($pluriel)] = $n;
                $morceaux[] = $n.' '.($n > 1 ? $pluriel : $singulier);
            }
        }
        $nombre = array_sum($details);

        $jours = $ligne->dernier_tirage_le === null
            ? null
            : (int) $ligne->dernier_tirage_le->copy()->startOfDay()->diffInDays($maintenant->copy()->startOfDay());

        if ($nombre === 0) {
            [$etat, $libelle] = ['a_jour', 'À jour'];
        } elseif ($jours !== null && $jours >= 1) {
            [$etat, $libelle] = ['retard', 'En retard de '.$jours.' '.($jours > 1 ? 'jours' : 'jour')];
        } else {
            [$etat, $libelle] = ['a_recevoir', 'À recevoir'];
        }

        return $base + [
            'nombre' => $nombre, 'details' => $details, 'resume' => $morceaux === [] ? 'Rien à recevoir' : implode(', ', $morceaux),
            'jours' => $jours, 'etat' => $etat, 'libelle' => $libelle,
        ];
    }

    /** « Renvoyer vers ce poste » : lève le drapeau et l'audite (qui, quand, quel poste). */
    public function demanderPoste(string $poste, User $par): void
    {
        $this->lever($poste, $par);
        AuditLog::record('sync.renvoi_poste:'.$poste, 'sync', $par->id);
    }

    /** « Renvoyer vers tous les postes » : un drapeau par poste appairé (jeton non expiré), un seul audit. */
    public function demanderTous(User $par, ?Carbon $maintenant = null): int
    {
        $maintenant ??= now();
        $postes = PersonalAccessToken::query()
            ->where(fn ($q) => $q->whereNull('expires_at')->orWhere('expires_at', '>', $maintenant))
            ->pluck('name')->unique()->values();

        foreach ($postes as $poste) {
            $this->lever($poste, $par);
        }
        AuditLog::record('sync.renvoi_tous', 'sync', $par->id);

        return $postes->count();
    }

    private function lever(string $poste, User $par): void
    {
        PosteSynchronisation::updateOrCreate(
            ['poste' => $poste],
            ['resync_demandee_le' => now(), 'resync_demandee_par' => $par->id],
        );
    }

    /** Instant du drapeau levé pour ce poste, `null` s'il n'y en a pas. */
    public function drapeau(string $poste): ?Carbon
    {
        return PosteSynchronisation::query()->where('poste', $poste)->first()?->resync_demandee_le;
    }

    /**
     * Le poste a refait un tirage complet : le drapeau tombe — SEULEMENT s'il n'a pas été relevé depuis la demande que
     * le poste a honorée ([demandeeLe] : l'instant qu'il a lu). Une nouvelle demande arrivée pendant son tirage reste.
     */
    public function acquitter(string $poste, Carbon $demandeeLe, ?Carbon $maintenant = null): bool
    {
        $ligne = PosteSynchronisation::query()->where('poste', $poste)->first();
        if ($ligne === null || $ligne->resync_demandee_le === null || $ligne->resync_demandee_le->gt($demandeeLe)) {
            return false;
        }

        $ligne->forceFill(['resync_demandee_le' => null, 'resync_demandee_par' => null, 'resync_acquittee_le' => $maintenant ?? now()])->save();

        return true;
    }
}
