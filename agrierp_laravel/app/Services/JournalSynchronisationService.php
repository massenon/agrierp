<?php

namespace App\Services;

use App\Models\ControleCoherence;
use App\Models\JournalSynchronisation;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * Ticket H3 — JOURNAL ET ÉTAT DE SYNCHRONISATION DES POSTES (PRD `synchronisation-barre-superieure`, EF11-EF12).
 *
 * Le serveur EST la base : il ne « synchronise » rien lui-même. Il sait en revanche qui l'a contacté, quand, et
 * avec quel résultat. C'est ce que montre la modale « Synchronisation » du web, réservée à l'administrateur.
 */
class JournalSynchronisationService
{
    /** Au-delà, un poste est signalé « Inactif depuis N jours » (décision D-SYNC-6, recommandation : 3 jours). */
    public const JOURS_INACTIVITE = 3;

    /** Clés du tirage qui ne sont pas des enregistrements (identifiants, constantes) : non comptées. */
    private const CLES_NON_COMPTEES = ['accounting_entry_ids', 'expense_categories'];

    /** @param  array<string, mixed>  $reponse  corps du tirage */
    public function tirage(Request $request, array $reponse): void
    {
        $recus = 0;
        foreach ($reponse as $cle => $valeur) {
            if (! in_array($cle, self::CLES_NON_COMPTEES, true) && $valeur instanceof Collection) {
                $recus += $valeur->count();
            }
        }

        $this->ecrire($request, 'tirage', $recus, 0, 0);
    }

    /** @param  array<string, mixed>  $resultat  corps de la réponse d'envoi */
    public function envoi(Request $request, array $resultat): void
    {
        $acceptes = 0;
        $refuses = 0;
        foreach ($resultat as $table) {
            if (is_array($table) && array_key_exists('accepted', $table) && array_key_exists('rejected', $table)) {
                $acceptes += count($table['accepted']);
                $refuses += count($table['rejected']);
            }
        }

        $this->ecrire($request, 'envoi', 0, $acceptes, $refuses);
    }

    /**
     * Un échec du journal ne fait JAMAIS échouer la synchronisation : le poste a reçu ou envoyé ses données, ne pas
     * savoir l'écrire ici n'est pas une raison de le lui faire recommencer.
     */
    private function ecrire(Request $request, string $sens, int $recus, int $acceptes, int $refuses): void
    {
        try {
            JournalSynchronisation::create([
                'user_id' => $request->user()?->id,
                'poste' => $request->user()?->currentAccessToken()?->name ?? '—',
                'sens' => $sens,
                'nb_recus' => $recus,
                'nb_acceptes' => $acceptes,
                'nb_refuses' => $refuses,
            ]);
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * Un poste par jeton Sanctum non expiré, du plus récemment vu au plus ancien.
     *
     * Ticket CFG-1 — chaque ligne porte aussi son JETON (`jeton_id`, `cree_le` = appairage, `expire_le`) : l'onglet
     * « Postes & Appairage » de Paramètres liste ces mêmes lignes au lieu de refaire la requête.
     *
     * @return Collection<int, array{jeton_id: int|string, poste: string, utilisateur: string, cree_le: ?Carbon, expire_le: ?Carbon, dernier_contact: ?Carbon, dernier_envoi: ?Carbon, dernier_controle: ?Carbon, acceptes: ?int, refuses: ?int, etat: string, libelle_etat: string}>
     */
    public function etatDesPostes(?Carbon $maintenant = null): Collection
    {
        $maintenant ??= now();

        $jetons = PersonalAccessToken::query()
            ->where(fn ($q) => $q->whereNull('expires_at')->orWhere('expires_at', '>', $maintenant))
            ->with('tokenable')
            ->get();

        return $jetons
            ->map(function (PersonalAccessToken $jeton) use ($maintenant) {
                $envoi = JournalSynchronisation::query()
                    ->where('poste', $jeton->name)
                    ->where('sens', 'envoi')
                    ->latest('created_at')
                    ->first();

                $contact = $jeton->last_used_at;
                [$etat, $libelle] = $this->etat($envoi, $contact ?? $jeton->created_at, $maintenant);

                // Ticket S-T6 — dernier contrôle de cohérence demandé par ce poste (le résultat reste au poste).
                $controle = ControleCoherence::query()
                    ->where('poste', $jeton->name)
                    ->latest('created_at')
                    ->value('created_at');

                return [
                    'jeton_id' => $jeton->getKey(),
                    'poste' => $jeton->name,
                    'utilisateur' => $jeton->tokenable?->name ?? '—',
                    'cree_le' => $jeton->created_at,
                    'expire_le' => $this->expiration($jeton),
                    'dernier_contact' => $contact,
                    'dernier_envoi' => $envoi?->created_at,
                    'dernier_controle' => $controle === null ? null : Carbon::parse($controle),
                    'acceptes' => $envoi?->nb_acceptes,
                    'refuses' => $envoi?->nb_refuses,
                    'etat' => $etat,
                    'libelle_etat' => $libelle,
                ];
            })
            ->sortByDesc(fn ($ligne) => $ligne['dernier_contact']?->getTimestamp() ?? 0)
            ->values();
    }

    /**
     * Ticket CFG-1 — fin de validité d'un jeton : sa date propre (`expires_at`, posée par le poste ou un test), sinon
     * la durée globale de Sanctum (`sanctum.expiration`, en minutes) comptée depuis sa création ; `null` : sans fin.
     */
    private function expiration(PersonalAccessToken $jeton): ?Carbon
    {
        if ($jeton->expires_at !== null) {
            return Carbon::parse($jeton->expires_at);
        }

        $minutes = config('sanctum.expiration');

        return $minutes === null || $jeton->created_at === null
            ? null
            : Carbon::parse($jeton->created_at)->addMinutes((int) $minutes);
    }

    /**
     * Du plus grave au moins grave : un refus à corriger l'emporte sur l'inactivité (EF11).
     *
     * @return array{0: string, 1: string}
     */
    private function etat(?JournalSynchronisation $envoi, ?Carbon $contact, Carbon $maintenant): array
    {
        if ($envoi !== null && $envoi->nb_refuses > 0) {
            return ['refus', 'Refus à corriger'];
        }

        $jours = $contact === null ? null : (int) $contact->copy()->startOfDay()->diffInDays($maintenant->copy()->startOfDay());
        if ($jours === null || $jours > self::JOURS_INACTIVITE) {
            return ['inactif', $jours === null ? 'Inactif' : "Inactif depuis {$jours} jours"];
        }

        return ['a_jour', 'À jour'];
    }
}
