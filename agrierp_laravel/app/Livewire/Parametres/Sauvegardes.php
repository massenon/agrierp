<?php

namespace App\Livewire\Parametres;

use App\Models\AuditLog;
use App\Services\ImportModuleService;
use App\Services\SauvegardeService;
use Livewire\Component;

/**
 * Ticket 14.57 (Sprint 14) — SAUVEGARDES DE LA BASE DE DONNÉES.
 *
 * ⚠️ **ÉCRAN HORS MAQUETTE**, demandé par le client. À valider au prochain
 * point, comme les autres ajouts de ce sprint.
 *
 * La génération réelle existait depuis le ticket 11.1 (`agrierp:backup`,
 * `mysqldump`, rétention 30 jours, planifiée quotidiennement) mais était
 * **enfouie dans l'écran Rôles & Permissions** — un endroit où personne ne
 * pense à chercher une sauvegarde. Cet onglet lui donne sa place, et ajoute ce
 * qui manquait : la portée par module et un listing exploitable.
 *
 * ⚠️ **RÉSERVÉ À L'ADMINISTRATEUR, SUR CHAQUE MÉTHODE.** Une sauvegarde
 * contient l'INTÉGRALITÉ de la base : salaires, coordonnées de clients,
 * identifiants comptables. C'est le fichier le plus sensible que produise
 * l'application.
 */
class Sauvegardes extends Component
{
    public string $moduleAExporter = '';

    public function getFichiersProperty(): array
    {
        $this->authorize('manage-parametres');

        return app(SauvegardeService::class)->lister();
    }

    public function getModulesProperty(): array
    {
        return SauvegardeService::modules();
    }

    public function genererComplete(): void
    {
        $this->authorize('manage-parametres');

        $resultat = app(SauvegardeService::class)->genererComplete();

        AuditLog::record('database.backup_generated', 'parametres');

        // ⚠️ LE MOTEUR EST DIT. Un export de données seules ne restaure rien
        // sur une base vierge : laisser croire à une sauvegarde complète serait
        // découvert au pire moment — celui de la restauration.
        $this->dispatch(
            'toast',
            message: $resultat['moteur'] === 'mysqldump'
                ? 'Sauvegarde complète générée : '.$resultat['fichier']
                : 'mysqldump indisponible sur ce serveur — export des DONNÉES seules généré ('
                    .$resultat['fichier'].'). Ce fichier ne contient pas le schéma.',
            type: $resultat['moteur'] === 'mysqldump' ? 'success' : 'warning',
        );
    }

    public function genererModule(): void
    {
        $this->authorize('manage-parametres');

        if ($this->moduleAExporter === '') {
            $this->addError('moduleAExporter', 'Choisissez un module à exporter.');

            return;
        }

        $fichier = app(SauvegardeService::class)->genererModule($this->moduleAExporter);

        if ($fichier === null) {
            $this->dispatch('toast', message: 'Module inconnu.', type: 'error');

            return;
        }

        AuditLog::record('database.backup_module_generated', 'parametres');

        $this->dispatch('toast', message: 'Export généré : '.$fichier, type: 'success');
    }

    /**
     * ⚠️⚠️ LE NOM EST VÉRIFIÉ CONTRE LA LISTE RÉELLE. Une méthode Livewire est
     * appelable depuis le navigateur avec n'importe quel argument : un chemin
     * concaténé permettrait de remonter l'arborescence et de télécharger le
     * fichier d'environnement du serveur.
     */
    public function telecharger(string $fichier)
    {
        $this->authorize('manage-parametres');

        $chemin = app(SauvegardeService::class)->chemin(basename($fichier));

        if ($chemin === null) {
            $this->dispatch('toast', message: 'Sauvegarde introuvable.', type: 'error');

            return null;
        }

        AuditLog::record('database.backup_downloaded', 'parametres');

        return response()->download($chemin);
    }

    // ─────────────────────────── Import par module ───────────────────────────

    public string $fichierAImporter = '';

    public string $moduleAImporter = '';

    /**
     * Importe un module depuis une sauvegarde présente sur le serveur.
     *
     * ⚠️⚠️ **SEULS LES FICHIERS DU DOSSIER DE SAUVEGARDE SONT ACCEPTÉS**, et
     * leur contenu est ANALYSÉ, jamais exécuté : voir `ImportModuleService`.
     * Faire tourner un fichier SQL tel quel reviendrait à accepter `DROP TABLE`
     * ou `UPDATE users SET password = …`.
     */
    public function importerModule(): void
    {
        $this->authorize('manage-parametres');

        if ($this->fichierAImporter === '' || $this->moduleAImporter === '') {
            $this->addError('fichierAImporter', 'Choisissez un fichier et un module.');

            return;
        }

        $chemin = app(SauvegardeService::class)->chemin(basename($this->fichierAImporter));

        if ($chemin === null) {
            $this->dispatch('toast', message: 'Sauvegarde introuvable.', type: 'error');

            return;
        }

        $resultat = app(ImportModuleService::class)
            ->importer(file_get_contents($chemin), $this->moduleAImporter);

        $this->dispatch('close-modal', name: 'modal-import');

        // ⚠️ LES REJETS SONT ANNONCÉS AVEC LEUR MOTIF. Un fichier contenant des
        // instructions refusées doit alerter : c'est le signe qu'il ne vient pas
        // de cette application, ou qu'il vise d'autres tables.
        $this->dispatch(
            'toast',
            message: $resultat['rejetees'] > 0
                ? "{$resultat['inserees']} ligne(s) importée(s), {$resultat['rejetees']} instruction(s) refusée(s) — "
                    .implode(' · ', $resultat['motifs'])
                : "{$resultat['inserees']} ligne(s) importée(s).",
            type: $resultat['rejetees'] > 0 ? 'warning' : 'success',
        );
    }

    public function render()
    {
        return view('livewire.parametres.sauvegardes');
    }
}
