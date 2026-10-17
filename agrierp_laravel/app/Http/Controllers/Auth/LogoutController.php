<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Http\Request;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;

/**
 * Ticket 1.2 (Sprint 1) — logout.html → action /logout
 * Référence comportementale : Document 06 §13.2.
 *
 * ÉCART DOCUMENTÉ PAR RAPPORT AU PROTOTYPE :
 * Le prototype affiche un écran de transition avec spinner
 * ("Déconnexion en cours…", délai artificiel de 1200ms) avant de rediriger
 * vers login.html — nécessaire dans une maquette HTML statique sans
 * backend réel pour simuler un traitement. Ici, la déconnexion serveur
 * réelle (invalidation de session, régénération CSRF) est quasi instantanée
 * : ajouter un délai artificiel identique serait un anti-pattern (fausse
 * latence dans une action réelle). Document 06 §13.2 offre explicitement
 * l'alternative retenue : "confirmation visuelle (toast OU message sur la
 * page de login elle-même)" — implémentée via le toast de bienvenue déjà
 * câblé au Sprint 0 (`<x-flash-toast />`, présent sur `layouts.guest`).
 *
 * Cette action n'est PAS un composant Livewire (routage Rule 1,
 * PROMPT_AVOID_ERREURS_LARAVEL_LIVEWIRE.md, ne s'applique qu'aux composants
 * Livewire plein-page) — un simple contrôleur à action unique est la forme
 * standard Laravel pour ce type d'action ponctuelle (POST sans état affiché).
 */
class LogoutController extends Controller
{
    public function __invoke(Request $request): RedirectResponse
    {
        AuditLog::record('logout', 'auth');

        Auth::guard('web')->logout();

        $request->session()->invalidate();
        $request->session()->regenerateToken();

        session()->flash('toast', [
            'message' => 'Déconnexion réussie. À bientôt !',
            'type' => 'success',
        ]);

        return redirect()->route('login');
    }
}
