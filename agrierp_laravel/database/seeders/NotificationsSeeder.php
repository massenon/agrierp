<?php

namespace Database\Seeders;

use App\Models\Notification;
use App\Models\User;
use Illuminate\Database\Seeder;

/**
 * Contenu volontairement générique ("system") — jamais une fausse alerte
 * métier (ex. "Stock aliment lapins bas") qui référencerait des lots ou
 * seuils de stock inexistants sur une base fraîchement installée
 * (Document 00 §2.1, zéro donnée fictive). Ces 2 entrées servent
 * uniquement à valider que le Centre de Notifications (ticket 1.7)
 * fonctionne réellement de bout en bout.
 *
 * ⚠️ CORRECTION (trouvée par l'audit des seeders) : la 2e notification
 * annonçait "Sprint 1 — Fondations en place" — un artefact du processus
 * de développement, périmé maintenant que le système est substantiellement
 * complet (13 sprints traités). Un vrai Directeur Général se connectant
 * aujourd'hui n'a aucune raison de voir une référence à un sprint
 * interne d'équipe de développement. Reformulée pour rester honnête
 * (toujours zéro donnée métier fictive) sans référencer le processus de
 * construction du logiciel.
 */
class NotificationsSeeder extends Seeder
{
    public function run(): void
    {
        $admin = User::where('email', 'dg@olouwachegoun.bj')->first();

        if (! $admin) {
            return;
        }

        Notification::firstOrCreate(
            ['user_id' => $admin->id, 'title' => 'Bienvenue sur AgriERP'],
            [
                'type' => 'system',
                'severity' => 'info',
                'message' => 'Votre espace AgriERP est prêt. Les alertes automatiques (stock, élevage, finance) apparaîtront ici au fil de l\'utilisation réelle des modules.',
                'icon' => 'celebration',
                'is_read' => false,
            ]
        );

        Notification::firstOrCreate(
            ['target_role' => 'admin', 'title' => 'Système opérationnel'],
            [
                'type' => 'system',
                'severity' => 'info',
                'message' => "Tous les modules (élevage, ventes, achats, stocks, comptabilité, RH) sont opérationnels et prêts pour la saisie réelle.",
                'icon' => 'task_alt',
                'is_read' => true,
                'read_at' => now()->subHours(2),
            ]
        );
    }
}
