<?php

namespace App\Livewire\Parametres;

use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Ticket 11.1 (Sprint 11) — parametres-hub.html → Livewire\Parametres\ParametresHub
 * Hub à 6 onglets (le prototype charge 6 iframes — roles-permissions.html,
 * parametres.html [via l'onglet "Données de l'Entreprise"], modules-actifs.html,
 * gestion-utilisateurs.html, modes-paiement.html, audit-logs.html — converties
 * en composition, même traitement que les autres hubs).
 *
 * ⚠️ Résout par avance la question du ticket 11.2 ("parametres.html →
 * vérifier redondance avant de porter") : `parametres.html` N'EST PAS un
 * écran redondant avec ce hub, c'est littéralement l'un de ses 6 onglets
 * ("Données de l'Entreprise") — chargé en iframe directement par
 * `parametres-hub.html` dans le prototype. Aucun doublon à trancher, un
 * seul écran à construire sous cet onglet.
 *
 * Seul l'onglet "Rôles & Permissions" est réel dans ce ticket. Les 5
 * autres ont chacun leurs propres tickets et affichent un bandeau
 * d'attente jusque-là.
 *
 * Ticket CFG-1 (décision client du 19/10/2026) — deux onglets HORS PROTOTYPE : « Email (SMTP) » (`email`, la seule
 * saisie SMTP de l'application, `EmailSmtp`) et « Postes & Appairage » (`postes`, `PostesAppairage`). Chacun garde
 * ses droits à l'ouverture (`manage-parametres`, `manage-users`) : le hub, lui, n'exige que `view-parametres`.
 */
#[Layout('layouts.app')]
class ParametresHub extends Component
{
    #[Url]
    public string $tab = 'roles';

    public function render()
    {
        return view('livewire.parametres.parametres-hub', ['title' => 'Paramètres']);
    }
}
