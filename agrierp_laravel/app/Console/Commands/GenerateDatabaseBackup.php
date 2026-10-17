<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;

/**
 * Ticket 11.1 (Sprint 11) — sauvegarde réelle de la base de données via
 * `mysqldump`, cohérente avec l'environnement de déploiement cPanel déjà
 * documenté (`LISTE_DES_CRON_JOBS_CPANEL.md`, `CPANEL_DEPLOYMENT.md`) —
 * cette même commande est destinée à être appelée par un vrai cron cPanel
 * en production, ET déclenchable à la demande depuis l'écran Rôles &
 * Permissions (bouton "Générer une Sauvegarde", ticket 11.1).
 *
 * Écrit un fichier .sql horodaté dans `storage/app/backups/` (disque
 * `local`) — jamais un fichier de démonstration, jamais une liste
 * statique de sauvegardes inventées.
 *
 * ⚠️ TICKET 13.2 (Sprint 13, checklist de pré-déploiement) : rétention 30
 * jours ajoutée (Document 01 §5, NFRS — "rétention 30 jours" explicitement
 * chiffrée, jamais approximée). La commande existait depuis le ticket
 * 11.1 mais ne purgeait jamais les sauvegardes anciennes — sans cette
 * purge, `storage/app/backups/` aurait grossi indéfiniment sur un serveur
 * de production tournant plusieurs années. Purge exécutée APRÈS la
 * nouvelle sauvegarde réussie, jamais avant (ne jamais risquer de se
 * retrouver sans aucune sauvegarde valide entre la purge et l'échec
 * éventuel d'une nouvelle sauvegarde).
 */
class GenerateDatabaseBackup extends Command
{
    protected $signature = 'agrierp:backup';

    protected $description = "Génère une sauvegarde réelle de la base de données (mysqldump) dans storage/app/backups, purge les sauvegardes de plus de 30 jours.";

    private const RETENTION_DAYS = 30;

    public function handle(): int
    {
        $connection = config('database.default');
        $config = config("database.connections.{$connection}");

        if (($config['driver'] ?? null) !== 'mysql') {
            $this->error('Cette commande ne prend en charge que le pilote mysql.');

            return self::FAILURE;
        }

        Storage::disk('local')->makeDirectory('backups');
        $filename = 'backup_'.now()->format('Y-m-d_Hi').'.sql';
        $path = Storage::disk('local')->path('backups/'.$filename);

        $command = sprintf(
            'mysqldump --host=%s --port=%s --user=%s --password=%s %s > %s 2>&1',
            escapeshellarg($config['host'] ?? '127.0.0.1'),
            escapeshellarg((string) ($config['port'] ?? 3306)),
            escapeshellarg($config['username'] ?? ''),
            escapeshellarg($config['password'] ?? ''),
            escapeshellarg($config['database'] ?? ''),
            escapeshellarg($path)
        );

        exec($command, $output, $exitCode);

        if ($exitCode !== 0 || ! file_exists($path) || filesize($path) === 0) {
            @unlink($path);
            $this->error("Échec de la sauvegarde — vérifiez que mysqldump est disponible sur ce serveur.");

            return self::FAILURE;
        }

        $this->info("Sauvegarde générée : {$filename}");

        $this->purgeOldBackups();

        return self::SUCCESS;
    }

    /** Purge réelle, exécutée uniquement après une sauvegarde réussie — jamais avant. */
    private function purgeOldBackups(): void
    {
        $cutoff = now()->subDays(self::RETENTION_DAYS);
        $purged = 0;

        foreach (Storage::disk('local')->files('backups') as $file) {
            $lastModified = Storage::disk('local')->lastModified($file);

            if ($lastModified < $cutoff->timestamp) {
                Storage::disk('local')->delete($file);
                $purged++;
            }
        }

        if ($purged > 0) {
            $this->info("{$purged} sauvegarde(s) de plus de ".self::RETENTION_DAYS." jours purgée(s).");
        }
    }
}
