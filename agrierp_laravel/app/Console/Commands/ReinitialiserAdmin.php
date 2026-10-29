<?php

namespace App\Console\Commands;

use App\Actions\SaisieUtilisateurAction;
use App\Models\AuditLog;
use App\Models\User;
use App\Services\CodeSecoursService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;

/**
 * Ticket MDP-1 — RÉINITIALISE LE MOT DE PASSE D'UN ADMINISTRATEUR avec le CODE DE SECOURS (cas du dernier administrateur
 * qui a oublié son mot de passe).
 *
 * Déroulé : le code est demandé en saisie MASQUÉE (jamais en argument, il resterait dans l'historique du shell) et vérifié
 * en temps constant contre son empreinte ; puis un mot de passe TEMPORAIRE (mêmes règles que la création de compte). Le
 * compte est marqué `must_change_password`, ses jetons et sessions sont fermés, l'audit `user.password_reset_secours` est
 * écrit (jamais le code, jamais le mot de passe), le code utilisé est invalidé et un NOUVEAU code est généré et affiché
 * une seule fois. 5 échecs de code : commande bloquée 15 minutes, chaque échec et le blocage sont journalisés.
 */
class ReinitialiserAdmin extends Command
{
    protected $signature = 'agrierp:reinitialiser-admin {identifiant : nom d\'utilisateur ou adresse e-mail du compte administrateur}';

    protected $description = "Réinitialise le mot de passe d'un administrateur avec le code de secours (mot de passe temporaire à changer à la prochaine connexion)";

    public function handle(CodeSecoursService $codes, SaisieUtilisateurAction $saisie): int
    {
        if (($secondes = $codes->secondesDeBlocage()) !== null) {
            Log::warning('Code de secours : tentative pendant le blocage.', ['reste_secondes' => $secondes]);
            $this->error('Trop d\'échecs : la commande est bloquée pendant encore '.ceil($secondes / 60).' minute(s).');

            return self::FAILURE;
        }

        $identifiant = (string) $this->argument('identifiant');
        $utilisateur = User::where(str_contains($identifiant, '@') ? 'email' : 'username', $identifiant)->first();
        if ($utilisateur === null || ! $utilisateur->is_active || ! $utilisateur->hasRole('admin')) {
            $this->error("Aucun compte administrateur actif ne porte l'identifiant « {$identifiant} ».");

            return self::FAILURE;
        }

        $saisi = (string) $this->secret('Code de secours (24 caractères)');
        if (! $codes->verifier($saisi)) {
            $bloque = $codes->enregistrerEchec();
            Log::warning('Code de secours : code refusé.', ['compte' => $utilisateur->id, 'bloque' => $bloque]);
            AuditLog::record($bloque ? 'user.password_reset_secours_bloque' : 'user.password_reset_secours_echec', 'auth', $utilisateur->id, $utilisateur);
            $this->error($bloque
                ? 'Code de secours incorrect. Trop d\'échecs : la commande est bloquée pendant 15 minutes.'
                : 'Code de secours incorrect ou déjà utilisé.');

            return self::FAILURE;
        }

        $motDePasse = (string) $this->secret('Nouveau mot de passe TEMPORAIRE');
        $confirmation = (string) $this->secret('Confirmez le mot de passe temporaire');
        if ($motDePasse !== $confirmation) {
            $this->error('La confirmation ne correspond pas au mot de passe saisi. Le code de secours n\'a pas été consommé.');

            return self::FAILURE;
        }
        $validation = Validator::make(['password' => $motDePasse], SaisieUtilisateurAction::reglesMotDePasseTemporaire(), [], ['password' => 'mot de passe']);
        if ($validation->fails()) {
            foreach ($validation->errors()->all() as $message) {
                $this->error($message);
            }
            $this->line('Le code de secours n\'a pas été consommé.');

            return self::FAILURE;
        }

        $nouveauCode = null;
        $consomme = DB::transaction(function () use ($codes, $saisie, $saisi, $utilisateur, $motDePasse, &$nouveauCode) {
            if (! $codes->consommer($saisi)) {
                return false; // consommé entre-temps par une autre commande
            }
            $saisie->poserMotDePasseTemporaire($utilisateur, $motDePasse);
            // ⚠️ Ni le code ni le mot de passe : seulement QUEL compte a été réinitialisé par le code de secours.
            AuditLog::record('user.password_reset_secours', 'auth', $utilisateur->id, $utilisateur);
            $nouveauCode = $codes->generer();

            return true;
        });

        if (! $consomme) {
            $this->error('Code de secours déjà utilisé.');

            return self::FAILURE;
        }

        $codes->effacerEchecs();

        $this->info("Mot de passe de « {$utilisateur->username} » réinitialisé : il devra être changé à la prochaine connexion.");
        $this->newLine();
        $this->warn('NOUVEAU CODE DE SECOURS — affiché UNE SEULE FOIS : imprimez-le et rangez-le au coffre (l\'ancien est invalide).');
        $this->line('');
        $this->line("    {$nouveauCode}");
        $this->line('');

        return self::SUCCESS;
    }
}
