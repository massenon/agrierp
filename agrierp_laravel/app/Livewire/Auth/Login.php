<?php

namespace App\Livewire\Auth;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ticket 1.1 (Sprint 1) — login.html → Livewire\Auth\Login
 * Référence comportementale : Document 06 §13.1 (06_DEVELOPMENT_STANDARDS.md).
 *
 * ÉCARTS DOCUMENTÉS PAR RAPPORT AU PROTOTYPE (à signaler/valider) :
 * 1. Le prototype (login.html, JS statique) authentifie contre DEUX e-mails
 *    codés en dur ('dg@...', 'caisse@...') — c'est un mock de démonstration
 *    HTML sans backend. Ici, authentification réelle contre la table
 *    `users` via `Auth::attempt()` (Document 00 §2.1, zéro donnée statique).
 * 2. Verrouillage de compte : le prototype gère un compteur JS local
 *    (5 tentatives → blocage 15 min, remis à zéro au rechargement de page,
 *    donc contournable trivialement). Document 06 §12 exige un throttling
 *    SERVEUR réel (`RateLimiter` Laravel). Implémenté ici avec une durée de
 *    blocage de 900s (15 min) — alignée sur la copie exacte du prototype
 *    ("Accès bloqué pendant 15min") tout en étant appliquée côté serveur,
 *    par clé email+IP (prévention d'énumération de comptes, Document 06 §12).
 * 3. Message d'erreur : phrase générique "Identifiants incorrects." exacte
 *    (Document 06 §13.1), jamais différenciée entre e-mail inconnu et mot
 *    de passe incorrect — le prototype affichait un compteur de tentatives
 *    restantes dans le toast d'erreur ; retiré ici pour ne pas faciliter
 *    l'énumération/le brute-force (seul le bandeau de verrouillage, lui
 *    déjà présent dans le DOM du prototype, reste visible une fois bloqué).
 * 4. Modale "Mot de passe oublié" : le prototype simule l'envoi ("Lien de
 *    réinitialisation envoyé.") sans aucun backend. Ici, envoi RÉEL via
 *    `Password::sendResetLink()` (Laravel natif, table
 *    `password_reset_tokens` déjà créée au Sprint 0). Le même message de
 *    succès est affiché que l'adresse existe ou non en base, par principe
 *    de non-énumération de comptes (Document 06 §12).
 * 5. La page de confirmation de réinitialisation (saisie du nouveau mot de
 *    passe après clic sur le lien reçu par e-mail) n'existe dans AUCUN
 *    fichier du prototype (absente de l'inventaire des 94 pages, Document
 *    00 §4) — nécessaire pour ne pas laisser le mécanisme d'envoi de lien
 *    sans destination (Document 00 §2.2, zéro fonctionnalité inachevée).
 *    Ajoutée en tant que `Livewire\Auth\ResetPassword`, minimale, stylée
 *    cohérence AgriERP — À VALIDER explicitement avec le promoteur au
 *    prochain point de synchronisation, puisqu'elle sort du périmètre
 *    strict des 94 pages recensées.
 * 6. Journalisation d'audit de connexion (`AuditLog::record('login', 'auth')`)
 *    ajoutée après-coup, une fois la table `audit_logs` créée au ticket 1.2
 *    (avancée depuis sa position normale dans l'ordre de dépendance général
 *    — voir docblock de la migration `audit_logs`). Ce point était resté
 *    en attente à la fin du ticket 1.1, la table n'existant pas encore.
 * 7. 🔴→✅ TICKET 14.42 : seule la connexion RÉUSSIE était journalisée. Les
 *    tentatives ÉCHOUÉES (`login.failed`) et le verrouillage effectif du
 *    compte (`login.locked`) le sont désormais aussi — sans quoi le blocage
 *    serveur du point 2 ne laissait aucune trace consultable, et le KPI
 *    « Connexions échouées » de l'écran Audit Logs n'avait pas de source.
 *    Le mot de passe saisi n'est évidemment jamais journalisé.
 * 8. 🔴→✅ TICKET 14.50 : le champ portait le libellé « NOM D'UTILISATEUR OU
 *    EMAIL » — repris mot pour mot de la maquette — mais n'acceptait QUE
 *    l'e-mail (`type="email"` côté vue, règle de validation `email` côté
 *    composant). L'écran promettait donc quelque chose qu'il refusait
 *    ensuite. Les deux sont désormais acceptés, la colonne
 *    d'authentification étant choisie selon la présence d'un « @ ».
 *    ⚠️ L'e-mail n'est PAS supprimé : il porte la réinitialisation de mot de
 *    passe et reste le seul canal hors application.
 */
#[Layout('layouts.guest')]
class Login extends Component
{
    /**
     * Ticket 14.50 — NOM D'UTILISATEUR **OU** E-MAIL, comme l'annonce le
     * libellé du champ depuis la maquette. La propriete ne s'appelle plus
     * `email` : elle ne contient plus forcement une adresse, et un nom qui
     * ment est le debut d'une regle qui derape.
     */
    public string $identifiant = '';

    public string $password = '';

    public bool $remember = false;

    public string $forgotEmail = '';

    public ?int $lockedSecondsRemaining = null;

    public function mount(): void
    {
        if (Auth::check()) {
            $this->redirect(route('dashboard.index'), navigate: false);

            return;
        }
    }

    public function submit(): void
    {
        $this->refreshLockState();

        if ($this->lockedSecondsRemaining !== null) {
            return;
        }

        // ⚠️ AUCUNE REGLE `email` ICI : elle rejetterait « admin » avant meme
        // la tentative d'authentification, ce qui etait exactement le defaut
        // corrige par ce ticket.
        $this->validate([
            'identifiant' => ['required', 'string', 'max:150'],
            'password' => ['required'],
        ], [
            'identifiant.required' => "Le nom d'utilisateur ou l'adresse e-mail est obligatoire.",
            'password.required' => 'Le mot de passe est obligatoire.',
        ]);

        $throttleKey = $this->throttleKey();

        if (! Auth::attempt([$this->champIdentifiant() => $this->identifiant, 'password' => $this->password, 'is_active' => true], $this->remember)) {
            RateLimiter::hit($throttleKey, 900);

            // 🔴→✅ TICKET 14.42 — L'ÉCHEC EST ENFIN TRACÉ.
            //
            // Seule la connexion RÉUSSIE était journalisée : le KPI
            // « Connexions échouées » de l'écran Audit Logs n'avait donc
            // aucune donnée à afficher, et une attaque par force brute ne
            // laissait aucune trace consultable. Le blocage serveur existait
            // (RateLimiter, 5 tentatives / 15 min) mais restait invisible
            // après coup.
            //
            // ⚠️ LE COMPTE VISÉ EST RÉSOLU, LE MOT DE PASSE JAMAIS ÉCRIT.
            // Rattacher la tentative au compte ciblé (quand l'adresse existe)
            // est ce qui rend le journal exploitable : « 5 échecs sur
            // compta@ depuis la même IP » se lit, « 5 échecs anonymes » non.
            // Une adresse inconnue donne user_id = null — l'IP reste, elle.
            AuditLog::record('login.failed', 'auth', $this->idDuCompteVise());

            $this->refreshLockState();

            if ($this->lockedSecondsRemaining === null) {
                $this->addError('identifiant', 'Identifiants incorrects.');
            } else {
                // Le verrouillage lui-même est l'événement de sécurité :
                // journalisé une seule fois, à la tentative qui le déclenche.
                AuditLog::record('login.locked', 'auth', $this->idDuCompteVise());
            }

            return;
        }

        RateLimiter::clear($throttleKey);

        // `session()` et non `request()->session()` : forme idiomatique, déjà
        // celle des deux appels suivants de cette même méthode, et qui ne
        // dépend pas du store attaché à l'objet Request.
        session()->regenerate();

        AuditLog::record('login', 'auth');

        session()->flash('toast', [
            'message' => 'Connexion réussie — Bienvenue !',
            'type' => 'success',
        ]);

        $this->redirect(session()->pull('url.intended', route('dashboard.index')), navigate: false);
    }

    public function sendResetLink(): void
    {
        $this->validate([
            'forgotEmail' => ['required', 'email'],
        ], [], ['forgotEmail' => 'adresse e-mail']); // U5 : « Le champ adresse e-mail… », pas « Le champ l'adresse… »

        // Le statut réel n'est jamais exposé à l'utilisateur (prévention
        // d'énumération de comptes, Document 06 §12) — même message de
        // succès que l'e-mail existe en base ou non.
        Password::sendResetLink(['email' => $this->forgotEmail]);

        $this->reset('forgotEmail');
        $this->dispatch('close-modal', name: 'forgot-password');
        $this->dispatch('toast', message: 'Lien de réinitialisation envoyé.', type: 'success');
    }

    /**
     * La colonne sur laquelle authentifier. Une adresse contient un « @ », un
     * nom d'utilisateur n'en contient jamais — la validation de creation
     * l'interdit, sans quoi un tel compte serait inatteignable.
     */
    private function champIdentifiant(): string
    {
        return str_contains($this->identifiant, '@') ? 'email' : 'username';
    }

    /**
     * Compte VISE par une tentative echouee, resolu sur les deux colonnes.
     * Rattacher l'echec au compte cible est ce qui rend le journal d'audit
     * exploitable (ticket 14.42) ; le faire sur une seule colonne l'aurait
     * rendu aveugle a la moitie des tentatives des ce ticket.
     */
    private function idDuCompteVise(): ?string
    {
        return User::where($this->champIdentifiant(), $this->identifiant)->value('id');
    }

    private function throttleKey(): string
    {
        return Str::transliterate(Str::lower($this->identifiant).'|'.request()->ip());
    }

    private function refreshLockState(): void
    {
        $throttleKey = $this->throttleKey();

        $this->lockedSecondsRemaining = RateLimiter::tooManyAttempts($throttleKey, 5)
            ? RateLimiter::availableIn($throttleKey)
            : null;
    }

    public function render()
    {
        return view('livewire.auth.login');
    }
}
