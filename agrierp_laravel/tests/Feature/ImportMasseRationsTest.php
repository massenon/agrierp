<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\FeedRationStandard;
use Illuminate\Auth\Access\AuthorizationException;

/**
 * Ticket IMPORT-4 — l'importation en masse du BARÈME DE RATIONNEMENT (`RationStandardService::creer`, droit `manage-elevage`).
 */
class ImportMasseRationsTest extends ImportMasseBase
{
    private function ligne(array $remplace = []): array
    {
        return array_merge(['espece' => 'Aviculture (Volailles)', 'stade' => 'Poulette test (3 à 5 mois)', 'grammes' => '85'], $remplace);
    }

    public function test_un_fichier_valide_cree_les_rations(): void
    {
        $user = $this->utilisateur(['manage-elevage']);

        $lot = $this->analyser('rations', [
            $this->ligne(),
            $this->ligne(['espece' => 'cuniculture', 'stade' => 'Lapine test', 'grammes' => 250]),
            $this->ligne(['espece' => 'PORCICULTURE (porcs)', 'stade' => 'Truie test', 'grammes' => '2 500']),
        ], $user);
        $this->assertSame([3, 0, 0], [$lot->valides, $lot->ignorees, $lot->refusees]);

        $this->service()->importer($lot, $user);

        $r = FeedRationStandard::where('stage_label', 'Poulette test (3 à 5 mois)')->firstOrFail();
        $this->assertSame('aviculture', $r->species_code);
        $this->assertSame(85, (int) $r->ration_g_per_day);
        $this->assertTrue($r->is_active);
        $this->assertSame('cuniculture', FeedRationStandard::where('stage_label', 'Lapine test')->value('species_code'));
        $this->assertSame(2500, (int) FeedRationStandard::where('stage_label', 'Truie test')->value('ration_g_per_day'));
        $this->assertSame(3, AuditLog::where('action', 'feed_ration_standard.saved')->count());
        $this->assertSame(1, AuditLog::where('action', 'import.masse')->where('module', 'elevage')->count());
    }

    public function test_les_lignes_erronees_sont_refusees_avec_les_motifs_du_web(): void
    {
        $user = $this->utilisateur(['manage-elevage']);

        $lot = $this->analyser('rations', [
            $this->ligne(['espece' => '']),
            $this->ligne(['espece' => 'Apiculture']),
            $this->ligne(['stade' => '']),
            $this->ligne(['stade' => str_repeat('S', 101)]),
            $this->ligne(['stade' => 'S5', 'grammes' => '']),
            $this->ligne(['stade' => 'S6', 'grammes' => '30,5']),
            $this->ligne(['stade' => 'S7', 'grammes' => '0']),
            $this->ligne(['stade' => 'S8', 'grammes' => '-4']),
            $this->ligne(['stade' => 'S9']),
        ], $user);

        $this->assertSame([1, 0, 8], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $m = collect($lot->lignes)->keyBy('ligne')->map(fn ($l) => $l['motif']);
        $this->assertSame('Feuille « Données », ligne 2, colonne « Espèce * » : Le champ espèce est obligatoire.', $m[2]);
        $this->assertSame('Feuille « Données », ligne 3, colonne « Espèce * » : Espèce inconnue : « Apiculture ». Choisissez une valeur de la liste déroulante.', $m[3]);
        $this->assertSame("Feuille « Données », ligne 4, colonne « Stade physiologique / tranche d'âge * » : Le champ stade est obligatoire.", $m[4]);
        $this->assertSame("Feuille « Données », ligne 5, colonne « Stade physiologique / tranche d'âge * » : Le champ stade ne doit pas dépasser 100 caractères.", $m[5]);
        $this->assertSame('Feuille « Données », ligne 6, colonne « Ration normative (g/tête/jour) * » : Le champ ration (grammes) est obligatoire.', $m[6]);
        $this->assertSame('Feuille « Données », ligne 7, colonne « Ration normative (g/tête/jour) * » : Le champ ration (grammes) doit être un nombre entier.', $m[7]);
        $this->assertSame('Feuille « Données », ligne 8, colonne « Ration normative (g/tête/jour) * » : Le champ ration (grammes) doit être au moins égal à 1.', $m[8]);
        $this->assertSame('Feuille « Données », ligne 9, colonne « Ration normative (g/tête/jour) * » : Le champ ration (grammes) doit être au moins égal à 1.', $m[9]);
    }

    public function test_doublon_du_fichier_et_ration_deja_au_bareme(): void
    {
        $user = $this->utilisateur(['manage-elevage']);
        $existante = FeedRationStandard::create(['species_code' => 'aviculture', 'stage_label' => 'Pondeuse (adulte)', 'ration_g_per_day' => 120, 'is_active' => true]);
        FeedRationStandard::create(['species_code' => 'aviculture', 'stage_label' => 'Stade archivé', 'ration_g_per_day' => 10, 'is_active' => false]);

        $lot = $this->analyser('rations', [
            $this->ligne(),
            $this->ligne(['stade' => 'POULETTE test  (3 à 5 mois)', 'grammes' => '99']),
            $this->ligne(['stade' => 'pondeuse (adulte)', 'grammes' => '999']),
            $this->ligne(['espece' => 'cuniculture', 'stade' => 'Pondeuse (adulte)', 'grammes' => '50']),
            $this->ligne(['stade' => 'Stade archivé', 'grammes' => '20']),
        ], $user);

        $this->assertSame([3, 1, 1], [$lot->valides, $lot->ignorees, $lot->refusees]);
        $this->assertSame('Ligne 3 : doublon de la ligne 2.', $lot->lignes[1]['motif']);
        $this->assertSame('Cette ration existe déjà au barème (même espèce, même stade) : ignorée, la ration existante est gardée.', $lot->lignes[2]['motif']);

        $this->service()->importer($lot, $user);
        $this->assertSame(120, (int) $existante->fresh()->ration_g_per_day, 'Jamais d\'écrasement.');
    }

    public function test_un_reimport_ne_cree_aucun_doublon(): void
    {
        $user = $this->utilisateur(['manage-elevage']);
        $lignes = [$this->ligne(), $this->ligne(['stade' => 'Second'])];
        $avant = FeedRationStandard::count();

        $this->service()->importer($this->analyser('rations', $lignes, $user), $user);
        $second = $this->analyser('rations', $lignes, $user);

        $this->assertSame([0, 2, 0], [$second->valides, $second->ignorees, $second->refusees]);
        $this->assertSame($avant + 2, FeedRationStandard::count());
    }

    public function test_les_droits_exigent_manage_elevage(): void
    {
        $sans = $this->utilisateur(['manage-rh', 'manage-comptabilite']);
        $this->assertArrayNotHasKey('rations', $this->service()->modulesAutorises($sans));

        $this->expectException(AuthorizationException::class);
        $this->analyser('rations', [$this->ligne()], $sans);
    }
}
