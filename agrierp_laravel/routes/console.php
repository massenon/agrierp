<?php

use Illuminate\Support\Facades\Schedule;

/**
 * Ticket 13.2 (Sprint 13, checklist de pré-déploiement) — planification
 * Laravel 11 (`Schedule::command()`, remplace `app/Console/Kernel.php`
 * des versions antérieures).
 *
 * ⚠️ GAP RÉEL COMBLÉ : `LISTE_DES_CRON_JOBS_CPANEL.md` documentait déjà
 * "Sauvegarde MySQL... quotidienne, hors heures d'activité (ex. 02h00)"
 * avec l'exemple de code exact `Schedule::command('backup:run')->dailyAt('02:00')`
 * — mais ce fichier `routes/console.php` n'existait pas du tout avant ce
 * ticket : la commande `agrierp:backup` (ticket 11.1) existait et
 * fonctionnait, mais n'était jamais réellement planifiée nulle part. Une
 * sauvegarde documentée mais jamais programmée n'aurait jamais tourné en
 * production tant que quelqu'un ne l'aurait pas remarqué.
 *
 * `agrierp:backup` (pas `backup:run`, qui suppose le package
 * `spatie/laravel-backup` non installé dans ce projet — Document 08
 * mentionne ce package comme "recommandé" mais la commande réellement
 * construite au ticket 11.1 est `agrierp:backup`, une implémentation
 * mysqldump directe équivalente sur le fond).
 *
 * Rappel du modèle de planification en un seul point d'entrée cPanel
 * (LISTE_DES_CRON_JOBS_CPANEL.md §"Cron 1") : UNE SEULE entrée Cron
 * cPanel (`php artisan schedule:run`, chaque minute) déclenche ensuite
 * toutes les tâches planifiées ici — jamais une entrée Cron cPanel
 * distincte par tâche métier.
 */
Schedule::command('agrierp:backup')
    ->dailyAt('02:00')
    ->onOneServer()
    ->runInBackground()
    ->emailOutputOnFailure(config('mail.from.address'));

/**
 * ⚠️ 4 TÂCHES SUPPLÉMENTAIRES AJOUTÉES — GAP TROUVÉ SUR QUESTION DIRECTE
 * ("as-tu documenté les cron jobs ?"). `LISTE_DES_CRON_JOBS_CPANEL.md`
 * exige 5 tâches planifiées au total ; seule la sauvegarde (ci-dessus)
 * avait été câblée jusqu'ici. Les 4 restantes, absentes jusqu'à ce
 * ticket :
 */

// Rappel de Prophylaxie du Jour — Document 03 §3.23,
// RAPPEL_DE_PROPHYLAXIE_DU_JOUR.md. Le Job lui-même (App\Jobs\DailyProphylaxyReminderJob)
// n'existait nulle part avant ce ticket malgré une spécification complète
// déjà écrite — construit dans ce même geste (voir docblock du Job pour
// les 2 écarts honnêtement documentés : jours calendaires non couverts,
// push Reverb non câblé).
Schedule::job(new \App\Jobs\DailyProphylaxyReminderJob())
    ->dailyAt('06:00')
    ->timezone('Africa/Porto-Novo')
    ->onOneServer();

// Ticket 15.49 — alertes de la cloche : stock sous seuil, mortalité anormale, soins planifiés à venir ou en
// retard, échecs de reproduction (règles dans AlertesElevageService). Juste après le rappel de prophylaxie.
Schedule::job(new \App\Jobs\DailyElevageAlertsJob())
    ->dailyAt('06:05')
    ->timezone('Africa/Porto-Novo')
    ->onOneServer();

// Ticket EX3 (PRD exercices comptables, R2) — OUVERTURE DE L'EXERCICE DE L'ANNÉE, le 1er janvier à 00:00 heure du
// Bénin. Sans elle, l'exercice N+1 n'existait qu'après la clôture de N (mars, après le bilan) : toute vente, dépense,
// achat ou paie du 1er janvier finissait en erreur. Idempotente ; si elle ne tourne pas (cron absent), la première
// saisie de l'année ouvre l'exercice (filet, `AccountingEntryService::exerciceOuvertPour`).
Schedule::command('agrierp:ouvrir-exercice')
    ->yearlyOn(1, 1, '00:00')
    ->timezone('Africa/Porto-Novo')
    ->onOneServer();

// Nettoyage des sessions expirées — hebdomadaire.
Schedule::command('session:gc')->weekly();

// Nettoyage des notifications lues de plus de 90 jours.
Schedule::call(function () {
    \App\Models\Notification::where('is_read', true)
        ->where('read_at', '<', now()->subDays(90))
        ->delete();
})->weekly();

// Purge des jobs échoués de plus de 30 jours (720 heures).
Schedule::command('queue:prune-failed', ['--hours' => 720])->weekly();

/**
 * Ticket 14.57 (Sprint 14) — RAPPEL HEBDOMADAIRE DE TÉLÉCHARGEMENT.
 *
 * ⚠️ LA SAUVEGARDE QUOTIDIENNE EXISTE DEPUIS LE TICKET 11.1, MAIS ELLE RESTE
 * SUR LE SERVEUR. Un fichier de sauvegarde stocké à côté de la base qu'il
 * protège ne protège de rien : l'incendie, le vol du serveur ou la panne de
 * disque emportent les deux. Personne ne pensait à le télécharger, faute d'être
 * prévenu — la notification comble ce trou.
 *
 * ⚠️ ADRESSÉE AU RÔLE `admin`, pas à un utilisateur nommé : le destinataire ne
 * doit pas disparaître avec le départ d'une personne.
 */
Schedule::call(function () {
    $derniere = collect(app(\App\Services\SauvegardeService::class)->lister())->first();

    \App\Models\Notification::create([
        'target_role' => 'admin',
        // Ticket 15.49 — `backup.reminder`, `error` et `warning` sont HORS des valeurs autorisées par la colonne
        // (MySQL strict refusait l'écriture) : type `system`, gravités du référentiel.
        'type' => 'system',
        'severity' => $derniere === null ? 'critique' : 'moyen',
        'title' => 'Sauvegarde à télécharger',
        'message' => $derniere === null
            // Le cas « aucune sauvegarde » est le plus grave : il signale que la
            // tâche quotidienne elle-même ne tourne pas.
            ? "Aucune sauvegarde n'a été générée : la tâche planifiée ne s'exécute peut-être pas sur ce serveur."
            : 'Dernière sauvegarde : '.$derniere['fichier'].' ('.$derniere['date']->format('d/m/Y').
              "). Téléchargez-la hors du serveur : un fichier resté à côté de la base ne protège de rien.",
        'icon' => 'backup',
        'link_url' => '/parametres-hub?tab=sauvegardes',
    ]);
})->weeklyOn(1, '08:00');
