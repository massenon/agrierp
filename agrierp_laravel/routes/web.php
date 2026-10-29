<?php

use Illuminate\Support\Facades\Route;

/**
 * Sprint 0 — squelette minimal.
 *
 * Aucune route d'écran métier n'est enregistrée ici tant que son ticket
 * n'a pas été traité (Document 00 §2.2, zéro placeholder — enregistrer une
 * route vers un composant Livewire qui n'existe pas romprait le routing).
 *
 * Convention à respecter pour CHAQUE route ajoutée à partir du Sprint 1
 * (PROMPT_AVOID_ERREURS_LARAVEL_LIVEWIRE.md Règle 1) :
 *
 *   Route::get('/gestion-elevage', \App\Livewire\Elevage\GestionElevage::class)
 *       ->name('elevage.gestion')
 *       ->middleware(['auth', 'can:view-elevage']);
 *
 * Jamais la syntaxe tableau réservée aux Contrôleurs classiques
 * (`[Component::class, 'method']`) pour un composant Livewire plein-page.
 *
 * 🔴→✅ TICKET 13.1 (Sprint 13, QA finale) — GAP RBAC CRITIQUE CORRIGÉ :
 * cette convention était déjà écrite ci-dessus depuis le Sprint 0, mais
 * seule 1 route sur 42 l'appliquait réellement avant ce ticket — les 41
 * autres n'étaient protégées que par `'auth'` seul, sans jamais vérifier
 * la permission Spatie correspondante. N'importe quel utilisateur
 * connecté, quel que soit son rôle, pouvait donc atteindre n'importe quel
 * écran par URL directe — les permissions existaient et étaient
 * correctement assignées aux 4 rôles (`RolesAndPermissionsSeeder`),
 * elles n'étaient simplement jamais vérifiées à ce niveau. Découvert en
 * écrivant le parcours critique 6/8 de Document 07 §4 ("un lien masqué ne
 * suffit pas — vérifier qu'une requête directe sur l'URL est aussi
 * bloquée"), corrigé dans la foulée plutôt que simplement documenté :
 * chaque route métier porte désormais `can:{permission}` en plus de
 * `auth`, mappée au module réel de l'écran. Seules les 5 routes
 * réellement universelles (dashboard, profil, aide, contact,
 * notifications) restent `auth` seul — aucune permission dédiée n'existe
 * ni ne devrait exister pour elles, tout rôle authentifié y a accès par
 * nature. L'exemple ci-dessus a également été corrigé : la version
 * précédente citait `can:view-dashboard`, une permission qui n'a jamais
 * existé dans `RolesAndPermissionsSeeder` — un exemple qui invente une
 * permission inexistante enseigne la mauvaise habitude à quiconque le
 * copie pour une future route.
 */

Route::get('/up', function () {
    return response()->json(['status' => 'ok', 'app' => 'LogiAgriERP', 'sprint' => 0]);
})->name('health-check');

// Ticket 1.1 (Sprint 1) — login.html → Livewire\Auth\Login
Route::middleware('guest')->group(function () {
    Route::get('/login', \App\Livewire\Auth\Login::class)->name('login');
});

// Sprint 14, ticket 14.15 : welcome.html + landing-page.html → pages publiques
// Accessibles à tous (y compris connecté) : ce sont des pages de présentation,
// pas des écrans applicatifs — les enfermer derrière `guest` renverrait une
// erreur à un utilisateur connecté qui suit simplement un lien.
Route::get('/welcome', \App\Livewire\PublicPages\Welcome::class)->name('public.welcome');
Route::get('/presentation', \App\Livewire\PublicPages\Presentation::class)->name('public.presentation');

/*
 * Racine du site — ticket 14.15.
 *
 * Le prototype passe par `index.html` : un écran d'attente de 3 secondes qui
 * redirige ensuite vers `welcome.html` à la première visite (drapeau
 * `localStorage`), vers `login.html` ensuite.
 *
 * NON REPRIS TEL QUEL, et c'est délibéré : une temporisation artificielle de
 * 3 secondes à chaque ouverture est un coût réel pour un utilisateur qui se
 * connecte plusieurs fois par jour, et le drapeau « déjà visité » en
 * localStorage n'est pas une donnée de session fiable (navigation privée,
 * poste partagé au comptoir). L'INTENTION est conservée — la page d'accueil
 * publique reste accessible — sans le délai ni l'état côté navigateur.
 *
 * DEPUIS LE 24/08/2026, LA RACINE MÈNE DIRECTEMENT À `/login` : c'est un
 * outil de travail, pas une vitrine, et l'écrasante majorité des ouvertures
 * vise la connexion. `/welcome` et `/presentation` restent servies telles
 * quelles, atteignables par lien direct ou depuis la page de connexion —
 * elles ne sont plus le passage obligé.
 */
Route::get('/', function () {
    return auth()->check()
        ? redirect()->route('dashboard.index')
        : redirect()->route('login');
});

// Ticket 1.2 (Sprint 1) — logout.html → action /logout
Route::post('/logout', \App\Http\Controllers\Auth\LogoutController::class)
    ->name('logout')
    ->middleware('auth');

// Sprint VW — verrou de session web (PRD docs/prd/verrou-web.md). Routes `auth` seul, comme /mon-profil : le verrou
// protège la session de tout compte connecté. `SessionVerrouillee` (groupe web) les laisse passer verrouillées.
Route::post('/verrouiller', [\App\Http\Controllers\Auth\VerrouSessionController::class, 'verrouiller'])
    ->name('session.verrouiller')
    ->middleware('auth');
Route::post('/deverrouiller', [\App\Http\Controllers\Auth\VerrouSessionController::class, 'deverrouiller'])
    ->name('session.deverrouiller')
    ->middleware('auth');
Route::get('/verrouillage', \App\Livewire\Auth\EcranVerrouillage::class)
    ->name('session.verrou')
    ->middleware('auth');

// Ticket 1.3 (Sprint 1) — dashboard.html → Livewire\Dashboard\Index
Route::get('/dashboard', \App\Livewire\Dashboard\Index::class)
    ->name('dashboard.index')
    ->middleware('auth');

// Sprint 1, ticket 1.4 : mon-profil.html → Livewire\Profil\MonProfil
Route::get('/mon-profil', \App\Livewire\Profil\MonProfil::class)
    ->name('profil.index')
    ->middleware('auth');

// Sprint 1, ticket 1.5 : aide-a-propos.html → page statique
Route::get('/aide-a-propos', \App\Livewire\Aide\Index::class)
    ->name('aide.index')
    ->middleware('auth');

// Sprint 1, ticket 1.6 : contact-editeur.html → formulaire simple
Route::get('/contact-editeur', \App\Livewire\Contact\Index::class)
    ->name('contact.index')
    ->middleware('auth');

// Sprint 1, ticket 1.7 : notifications.html → panneau notifications
Route::get('/notifications', \App\Livewire\Notifications\Index::class)
    ->name('notifications.index')
    ->middleware('auth');

// Sprint 2, ticket 2.3 : catalogue-produits.html → Livewire\Stocks\CatalogueProduits
Route::get('/catalogue-produits', \App\Livewire\Stocks\CatalogueProduits::class)
    ->name('stocks.catalogue')
    ->middleware(['auth', 'can:view-stocks']);

// Sprint 2, ticket 2.4 : ajouter-produit.html → formulaire (create + edit, même composant)
Route::get('/produits/ajouter', \App\Livewire\Stocks\AjouterProduit::class)
    ->name('stocks.produits.ajouter')
    ->middleware(['auth', 'can:manage-stocks']);
Route::get('/produits/{product}/modifier', \App\Livewire\Stocks\AjouterProduit::class)
    ->name('stocks.produits.modifier')
    ->middleware(['auth', 'can:manage-stocks']);

// Sprint 2, ticket 2.8 : parametres-elevage.html → Livewire\Elevage\ParametresElevage
Route::get('/parametres-elevage', \App\Livewire\Elevage\ParametresElevage::class)
    ->name('elevage.parametres')
    ->middleware(['auth', 'can:manage-elevage']);

// Sprint 3, ticket 3.2 : gestion-elevage.html → Livewire\Elevage\GestionElevage
Route::get('/gestion-elevage', \App\Livewire\Elevage\GestionElevage::class)
    ->name('elevage.gestion')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.3 : gestion-bandes.html → Livewire\Elevage\GestionBandes
Route::get('/gestion-bandes', \App\Livewire\Elevage\GestionBandes::class)
    ->name('elevage.bandes')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.4 : enregistrer-sujets.html → Livewire\Elevage\EnregistrerSujets
Route::get('/enregistrer-sujets', \App\Livewire\Elevage\EnregistrerSujets::class)
    ->name('elevage.enregistrer-sujets')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.5 : fiche-lapins.html → Livewire\Elevage\FicheLapins
Route::get('/fiche-lapins', \App\Livewire\Elevage\FicheLapins::class)
    ->name('elevage.fiche-lapins')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.6 : fiche-volailles-pondeuses.html → Livewire\Elevage\FichePondeuses
Route::get('/fiche-volailles-pondeuses', \App\Livewire\Elevage\FichePondeuses::class)
    ->name('elevage.fiche-pondeuses')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.7 : fiche-volailles-reproducteurs.html → Livewire\Elevage\FicheReproducteurs
Route::get('/fiche-volailles-reproducteurs', \App\Livewire\Elevage\FicheReproducteurs::class)
    ->name('elevage.fiche-reproducteurs')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.8 : fiche-porcs.html → Livewire\Elevage\FichePorcs
Route::get('/fiche-porcs', \App\Livewire\Elevage\FichePorcs::class)
    ->name('elevage.fiche-porcs')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.9 : fiche-escargots.html → Livewire\Elevage\FicheEscargots
Route::get('/fiche-escargots', \App\Livewire\Elevage\FicheEscargots::class)
    ->name('elevage.fiche-escargots')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.10 : suivi-reproduction.html → Livewire\Elevage\SuiviReproduction
Route::get('/suivi-reproduction', \App\Livewire\Elevage\SuiviReproduction::class)
    ->name('elevage.suivi-reproduction')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.11 : soins-vaccins-hub.html → Livewire\Elevage\SoinsVaccinsHub
Route::get('/soins-vaccins-hub', \App\Livewire\Elevage\SoinsVaccinsHub::class)
    ->name('elevage.soins-vaccins')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.12 : transformation.html → Livewire\Elevage\TransformationForm
Route::get('/transformation', \App\Livewire\Elevage\TransformationForm::class)
    ->name('elevage.transformation')
    ->middleware(['auth', 'can:view-elevage']);

// Ticket 15.46 : écran dédié des transferts entre bandes (absent du prototype, décision client du 17/10/2026).
Route::get('/transferts-bandes', \App\Livewire\Elevage\TransfertsBandes::class)
    ->name('elevage.transferts')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.13 : elevage-dashboard.html → Livewire\Elevage\DashboardElevage
Route::get('/elevage-dashboard', \App\Livewire\Elevage\DashboardElevage::class)
    ->name('elevage.dashboard')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 3, ticket 3.14 : bilan-technico-economique.html → Livewire\Elevage\BilanTechnicoEconomique
Route::get('/bilan-technico-economique', \App\Livewire\Elevage\BilanTechnicoEconomique::class)
    ->name('elevage.bilan')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 4, ticket 4.2 : ventes-devis.html (+ enfant pos-interface.html) → Livewire\Ventes\VentesDevisHub
Route::get('/ventes-devis', \App\Livewire\Ventes\VentesDevisHub::class)
    ->name('ventes.devis-hub')
    ->middleware(['auth', 'can:view-ventes']);

// Sprint 4, ticket 4.6 : creances-clients.html → Livewire\Ventes\CreancesClientsHub
Route::get('/creances-clients', \App\Livewire\Ventes\CreancesClientsHub::class)
    ->name('ventes.creances-hub')
    ->middleware(['auth', 'can:view-ventes']);

// Ticket audit de fidélité (Sprint 14+) : profile-client.html → Livewire\Ventes\ProfileClient
// ÉCRAN CONFIRMÉ MANQUANT par le cross-check systématique des 94 écrans
// prototype — atteint depuis 4 écrans (devis, historique-avances,
// relances-clients, suivi-dettes) par lien direct, jamais construit
// jusqu'ici.
Route::get('/clients/{customer}/profil', \App\Livewire\Ventes\ProfileClient::class)
    ->name('ventes.profile-client')
    ->middleware(['auth', 'can:view-ventes']);

// Ticket AC-3 — LECTURE d'une pièce justificative (achat ou dépense), sur le disque privé : jamais d'URL publique.
Route::get('/justificatifs/{type}/{id}', function (string $type, string $id) {
    abort_unless(in_array($type, ['achat', 'depense'], true), 404);

    $reponse = app(\App\Services\JustificatifService::class)->lire($type, $id);
    abort_if($reponse === null, 404, 'Aucune pièce justificative pour cet enregistrement.');

    return $reponse;
})->name('justificatifs.show')->middleware(['auth', 'can:view-achats']);

// Sprint 5, ticket 5.2 : achats-commandes.html → Livewire\Achats\AchatsCommandesHub
Route::get('/achats-commandes', \App\Livewire\Achats\AchatsCommandesHub::class)
    ->name('achats.commandes-hub')
    ->middleware(['auth', 'can:view-achats']);

// Sprint 5, ticket 5.6 : fournisseurs.html (+ fiches-fournisseurs.html, profile-fournisseur.html) → Livewire\Achats\FournisseursHub
Route::get('/fournisseurs', \App\Livewire\Achats\FournisseursHub::class)
    ->name('achats.fournisseurs-hub')
    ->middleware(['auth', 'can:view-achats']);

// Ticket audit de fidélité (Sprint 14+) : profile-fournisseur.html → Livewire\Achats\ProfileFournisseur
// ÉCRAN RECONSTRUIT — le prototype est une page standalone à 3 onglets,
// pas un simple tiroir (le tiroir léger de FichesFournisseurs reste
// disponible en complément, pas remplacé).
Route::get('/fournisseurs/{supplier}/profil', \App\Livewire\Achats\ProfileFournisseur::class)
    ->name('achats.profile-fournisseur')
    ->middleware(['auth', 'can:view-achats']);

// Sprint 5, ticket 5.8 : saisie-depenses.html → Livewire\Achats\SaisieDepenses
Route::get('/saisie-depenses', \App\Livewire\Achats\SaisieDepenses::class)
    ->name('achats.depenses')
    ->middleware(['auth', 'can:view-achats']);

// Sprint 6, ticket 6.2 : gestion-stocks.html → Livewire\Stocks\GestionStocks
Route::get('/gestion-stocks', \App\Livewire\Stocks\GestionStocks::class)
    ->name('stocks.gestion')
    ->middleware(['auth', 'can:view-stocks']);

// Sprint 6, ticket 6.2 : seuils-alerte.html → Livewire\Stocks\SeuilsAlerte (écran standalone, pas un onglet du hub)
Route::get('/seuils-alerte', \App\Livewire\Stocks\SeuilsAlerte::class)
    ->name('stocks.seuils')
    ->middleware(['auth', 'can:view-stocks']);

// Sprint 7, ticket 7.1 : facturation.html → Livewire\Facturation\Facturation
Route::get('/facturation', \App\Livewire\Facturation\Facturation::class)
    ->name('facturation.index')
    ->middleware(['auth', 'can:view-facturation']);

// Sprint 8, ticket 8.2 : personnel-stages.html → Livewire\RH\PersonnelStagesHub
Route::get('/personnel-stages', \App\Livewire\RH\PersonnelStagesHub::class)
    ->name('rh.personnel-stages-hub')
    ->middleware(['auth', 'can:view-rh']);

// Sprint 9, ticket 9.1 : administration.html → Livewire\Administration\AdministrationHub
// RÉSOUT LE GAP HISTORIQUE CRITIQUE identifié à l'ultra-review de fin de
// session précédente : lien sidebar présent depuis le Sprint 0, jamais
// relié à une route ni à un composant réel jusqu'à ce ticket.
Route::get('/administration', \App\Livewire\Administration\AdministrationHub::class)
    ->name('administration.hub')
    ->middleware(['auth', 'can:view-administration']);

// Sprint 10, ticket 10.3 : plan-comptable.html → Livewire\Comptabilite\PlanComptable
Route::get('/plan-comptable', \App\Livewire\Comptabilite\PlanComptable::class)
    ->name('comptabilite.plan')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 10, ticket 10.4 : journal-comptable.html → Livewire\Comptabilite\JournalComptable
Route::get('/journal-comptable', \App\Livewire\Comptabilite\JournalComptable::class)
    ->name('comptabilite.journal')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 10, ticket 10.5 : rapport-bilan.html → Livewire\Comptabilite\Bilan
Route::get('/rapport-bilan', \App\Livewire\Comptabilite\Bilan::class)
    ->name('comptabilite.bilan')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 10, ticket 10.6 : cloture-exercice.html → Livewire\Comptabilite\ClotureExercice
Route::get('/cloture-exercice', \App\Livewire\Comptabilite\ClotureExercice::class)
    ->name('comptabilite.cloture')
    ->middleware(['auth', 'can:close-fiscal-year']);

// Sprint 10, ticket 10.7 : comptabilite-analytique.html → Livewire\Comptabilite\ComptabiliteAnalytique
Route::get('/comptabilite-analytique', \App\Livewire\Comptabilite\ComptabiliteAnalytique::class)
    ->name('comptabilite.analytique')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 10, ticket 10.8 : comptabilite-hub.html → Livewire\Comptabilite\ComptabiliteHub
// Lien sidebar présent depuis le Sprint 0, enfin relié à un composant réel.
Route::get('/comptabilite-hub', \App\Livewire\Comptabilite\ComptabiliteHub::class)
    ->name('comptabilite.hub')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 14, ticket 14.1 : grand-livre.html → Livewire\Comptabilite\GrandLivre
// 1er des 5 écrans comptables ajoutés au prototype après le Sprint 12 et
// jamais convertis (Grand Livre, Balance Générale, États Financiers,
// Déclaration TVA, Rapprochement Bancaire).
Route::get('/grand-livre', \App\Livewire\Comptabilite\GrandLivre::class)
    ->name('comptabilite.grand-livre')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 14, ticket 14.5 : balance-generale.html → Livewire\Comptabilite\BalanceGenerale
// 2e des 5 écrans comptables jamais convertis. Décrit comme livré au log,
// mais absent des 4 installations du poste (audit du ticket 14.5).
Route::get('/balance-generale', \App\Livewire\Comptabilite\BalanceGenerale::class)
    ->name('comptabilite.balance')
    ->middleware(['auth', 'can:view-comptabilite']);

// Ticket 14.66 (Sprint 14) — BALANCE ÂGÉE, écran ajouté HORS MAQUETTE à la
// demande du client comptable. ⚠️ Lecture seule : aucune méthode mutante, la
// route porte donc `can:view-comptabilite` et rien de plus.
Route::get('/balance-agee', \App\Livewire\Comptabilite\BalanceAgee::class)
    ->name('comptabilite.balance-agee')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 14, ticket 14.6 : etats-financiers.html → Livewire\Comptabilite\EtatsFinanciers
// 3e écran comptable réellement construit de la série (4 onglets).
Route::get('/etats-financiers', \App\Livewire\Comptabilite\EtatsFinanciers::class)
    ->name('comptabilite.etats-financiers')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 14, ticket 14.7 : declaration-tva.html -> Livewire\Comptabilite\DeclarationTva
// Module M14, exigence imperative (CGI Benin art. 162 bis et 1084-40).
Route::get('/declaration-tva', \App\Livewire\Comptabilite\DeclarationTva::class)
    ->name('comptabilite.declaration-tva')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 14, ticket 14.8 : rapprochement-bancaire.html -> Livewire\Comptabilite\RapprochementBancaire
Route::get('/rapprochement-bancaire', \App\Livewire\Comptabilite\RapprochementBancaire::class)
    ->name('comptabilite.rapprochement')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 14, ticket 14.39 : bareme IR-PTS / ITS, editable et verrouillable.
// Absent du prototype : le bareme n'y figure pas, seule la CNSS est citee.
Route::get('/bareme-its', \App\Livewire\Parametres\BaremeIts::class)
    ->name('parametres.bareme-its')
    ->middleware(['auth', 'can:view-parametres']);

// Sprint 14, ticket 14.26 : ecran IMMOBILISATIONS (sans page source dans le
// prototype ; maquette de reference = Note 2 des Etats Financiers, que ce
// registre alimente desormais reellement) -> Livewire\Comptabilite\Immobilisations
Route::get('/immobilisations', \App\Livewire\Comptabilite\Immobilisations::class)
    ->name('comptabilite.immobilisations')
    ->middleware(['auth', 'can:view-comptabilite']);

// Sprint 14, ticket 14.9 : analyse-croissance.html -> Livewire\Elevage\AnalyseCroissance
Route::get('/analyse-croissance', \App\Livewire\Elevage\AnalyseCroissance::class)
    ->name('elevage.analyse-croissance')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 14, ticket 14.10 : rapport-mensuel.html -> Livewire\Rapports\RapportMensuel
Route::get('/rapport-mensuel', \App\Livewire\Rapports\RapportMensuel::class)
    ->name('rapports.mensuel')
    ->middleware(['auth', 'can:view-rapports']);

// Sprint 14, ticket 14.17 : registre des reproducteurs (suivi individuel)
// Ferme la boucle du ticket 14.16 : enregistrer -> lister -> consulter.
Route::get('/registre-reproducteurs', \App\Livewire\Elevage\RegistreReproducteurs::class)
    ->name('elevage.reproducteurs')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 14, ticket 14.16 : animal-details.html -> Livewire\Elevage\AnimalDetails
// Suivi individuel limite aux reproducteurs (arbitrage client) — voir le
// docblock du composant pour les onglets sans source reelle.
Route::get('/sujets/{animal}', \App\Livewire\Elevage\AnimalDetails::class)
    ->name('elevage.animal-details')
    ->middleware(['auth', 'can:view-elevage']);

// Sprint 11, ticket 11.1 : parametres-hub.html → Livewire\Parametres\ParametresHub
// Lien sidebar présent depuis le Sprint 0, enfin relié à un composant réel.
Route::get('/parametres-hub', \App\Livewire\Parametres\ParametresHub::class)
    ->name('parametres.hub')
    ->middleware(['auth', 'can:view-parametres']);

// Sprint 12, ticket 12.1 : rapports-exports.html → Livewire\Rapports\RapportsExportsHub
// Lien sidebar présent depuis le Sprint 0, enfin relié à un composant réel.
Route::get('/rapports-exports', \App\Livewire\Rapports\RapportsExportsHub::class)
    ->name('rapports.hub')
    ->middleware(['auth', 'can:view-rapports']);
