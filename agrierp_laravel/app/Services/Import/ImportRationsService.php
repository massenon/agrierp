<?php

namespace App\Services\Import;

use App\Models\FeedRationStandard;
use App\Services\RationStandardService;

/**
 * Ticket IMPORT-4 — MODULE « RATIONS » (barème de rationnement : Paramètres Élevage).
 *
 * Point de passage UNIQUE : `RationStandardService::creer` ; règles : `RationStandardService::regles()`, mot pour mot (noms de
 * colonne dans les messages = ceux du web : « espèce », « stade », « ration (grammes) »). Droit : `manage-elevage`.
 *
 * IDEMPOTENCE — clé NORMALISÉE filière + libellé du stade (`LectureValeurs::cle`) : une ration ACTIVE de même filière et de même
 * libellé est « déjà présente » (une ration archivée ne bloque pas). Création SEULE : une valeur différente pour un stade déjà
 * au barème est ignorée, jamais appliquée (la correction d'une ration se fait à l'écran). Le libellé de stade doit être EXACT :
 * il pilote les écrans de fiche (provende calculée).
 */
class ImportRationsService extends ModuleImport
{
    public const EMPREINTE_V1 = '6ddcf4239cd1c37fdedb21904a8d30368d05d205d6c7dd1e759a72b12d5adb8e';

    private const CHAMPS = ['species_code' => 'espece', 'stage_label' => 'stade', 'ration_g_per_day' => 'grammes'];

    /** @var array<string, true>|null */
    private ?array $index = null;

    public function cle(): string
    {
        return 'rations';
    }

    public function libelle(): string
    {
        return 'Rations';
    }

    public function description(): string
    {
        return 'Barème de rationnement : espèce, stade physiologique et ration normative en grammes par tête et par jour.';
    }

    public function icone(): string
    {
        return 'agriculture';
    }

    public function permission(): string
    {
        return 'manage-elevage';
    }

    public function moduleAudit(): string
    {
        return 'elevage';
    }

    public function version(): int
    {
        return 1;
    }

    public function empreinteAttendue(): string
    {
        return self::EMPREINTE_V1;
    }

    public function colonnes(): array
    {
        return [
            new ColonneImport('espece', 'Espèce', true, 'liste', 'Une espèce de la liste déroulante.', 'especes'),
            new ColonneImport('stade', 'Stade physiologique / tranche d\'âge', true, 'texte', '100 caractères au plus. Le libellé doit être EXACT : il pilote la provende calculée des fiches.'),
            new ColonneImport('grammes', 'Ration normative (g/tête/jour)', true, 'entier', 'Nombre entier de grammes, 1 au moins.'),
        ];
    }

    public function listes(): array
    {
        return ['especes' => array_values(RationStandardService::ESPECES)];
    }

    public function exemples(): array
    {
        return [
            ['espece' => 'Aviculture (Volailles)', 'stade' => 'Poulette (3 à 5 mois)', 'grammes' => '85'],
            ['espece' => 'Cuniculture (Lapins)', 'stade' => 'Lapine allaitante', 'grammes' => '250'],
        ];
    }

    public function notes(): array
    {
        return [
            'Une ration ACTIVE de même espèce et de même stade est IGNORÉE : le barème existant n\'est jamais modifié (corrigez-le à l\'écran Paramètres Élevage).',
            'Le libellé du stade doit être exactement celui que vos fiches attendent : demandez la liste de vos stades avant d\'importer.',
        ];
    }

    protected function attributs(): array
    {
        return ['espece' => 'espèce', 'stade' => 'stade', 'grammes' => 'ration (grammes)'];
    }

    public function designation(array $brut): string
    {
        return LectureValeurs::texte($brut['stade'] ?? null);
    }

    public function valider(array $brut): array
    {
        $erreurs = [];

        $texteEspece = LectureValeurs::texte($brut['espece'] ?? null);
        $espece = '';
        foreach (RationStandardService::ESPECES as $code => $libelle) {
            if ($texteEspece !== '' && in_array(LectureValeurs::cle($texteEspece), [LectureValeurs::cle($libelle), $code], true)) {
                $espece = $code;
            }
        }
        if ($texteEspece !== '' && $espece === '') {
            $erreurs['espece'] = "Espèce inconnue : « {$texteEspece} ». Choisissez une valeur de la liste déroulante.";
        }

        $donnees = [
            'species_code' => $espece,
            'stage_label' => LectureValeurs::texte($brut['stade'] ?? null),
            // Le texte tel quel : « 30,5 » est refusé par la règle `integer` du web (« doit être un nombre entier »).
            'ration_g_per_day' => LectureValeurs::sansEspaces(LectureValeurs::texte($brut['grammes'] ?? null)),
        ];

        $this->appliquerRegles($donnees, RationStandardService::regles(), [], self::CHAMPS, $erreurs);

        return ['valeurs' => $donnees, 'erreurs' => $erreurs];
    }

    public function cleLigne(array $valeurs): string
    {
        return $valeurs['species_code'].'|'.LectureValeurs::cle((string) $valeurs['stage_label']);
    }

    public function dejaPresente(array $valeurs): ?string
    {
        if (FeedRationStandard::whereKey($this->idLigne($valeurs))->exists()) {
            return 'Cette ration a déjà été importée : ignorée.';
        }

        $this->index ??= $this->construireIndex();
        if (isset($this->index[$this->cleLigne($valeurs)])) {
            return 'Cette ration existe déjà au barème (même espèce, même stade) : ignorée, la ration existante est gardée.';
        }

        return null;
    }

    public function ecrire(array $valeurs, string $id): void
    {
        app(RationStandardService::class)->creer($valeurs, $id);
        $this->index ??= $this->construireIndex();
        $this->index[$this->cleLigne($valeurs)] = true;
    }

    /** @return array<string, true> les rations ACTIVES */
    private function construireIndex(): array
    {
        $index = [];
        foreach (FeedRationStandard::where('is_active', true)->get(['species_code', 'stage_label']) as $r) {
            $index[$this->cleLigne(['species_code' => $r->species_code, 'stage_label' => $r->stage_label])] = true;
        }

        return $index;
    }
}
