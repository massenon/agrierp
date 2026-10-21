<?php

namespace App\Console\Commands;

use App\Services\DetectionDoublons;
use Illuminate\Console\Command;

/**
 * Ticket UNI — DÉTECTION (lecture seule) des codes de bande et des libellés de catégorie de produits en double.
 *
 * Liste chaque groupe avec les identifiants des lignes et le nombre de lignes qui s'y rattachent (fiches, ventes,
 * transferts, sujets ; produits pour une catégorie). Elle NE RENOMME ET NE SUPPRIME RIEN : renommer une bande ou une
 * catégorie déjà utilisée est une décision du client. Le code de sortie est toujours 0 (c'est un état des lieux).
 */
class DetecterDoublonsCodes extends Command
{
    protected $signature = 'agrierp:doublons';

    protected $description = 'Liste les bandes de même code et les catégories de produits de même libellé (lecture seule, ne modifie rien)';

    public function handle(DetectionDoublons $detection): int
    {
        $bandes = $detection->bandes();
        $categories = $detection->categories();

        if ($bandes === [] && $categories === []) {
            $this->info('Aucun doublon : chaque code de bande et chaque libellé de catégorie est unique.');

            return self::SUCCESS;
        }

        $this->afficher('bandes', 'le code', $bandes);
        $this->afficher('catégories de produits', 'le libellé', $categories);
        $this->line('');
        $this->line('Rien n\'a été modifié. Renommez les lignes en double depuis l\'application (la bande ou la catégorie la moins utilisée).');

        return self::SUCCESS;
    }

    /** @param list<array{cle: string, lignes: list<array{id: string, valeur: string, actif: bool, liees: array<string, int>}>}> $groupes */
    private function afficher(string $nature, string $champ, array $groupes): void
    {
        foreach ($groupes as $groupe) {
            $this->warn(count($groupe['lignes']).' '.$nature.' partagent '.$champ.' « '.$groupe['cle'].' » :');
            foreach ($groupe['lignes'] as $l) {
                $liees = collect($l['liees'])->map(fn ($n, $nom) => "{$n} {$nom}")->implode(', ');
                $this->line('  - '.$l['id'].'  « '.$l['valeur'].' »  '.($l['actif'] ? 'active' : 'archivée').'  ('.$liees.')');
            }
        }
    }
}
