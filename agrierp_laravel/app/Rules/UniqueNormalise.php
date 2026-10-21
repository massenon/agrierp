<?php

namespace App\Rules;

use App\Models\LivestockLot;
use App\Support\CleUnicite;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Support\Facades\DB;

/**
 * Ticket UNI — règle `unique` INSENSIBLE à la casse, aux accents et aux espaces (voir `CleUnicite`), sur TOUTES les
 * lignes de la table : bandes archivées comprises (une bande archivée garde son code, sa fiche et ses ventes ; le
 * redonner à une nouvelle bande ferait deux lignes de même clé dans tous les écrans et rapports).
 *
 * La comparaison se fait en PHP, pas en SQL : `LOWER`/`TRIM` ne couvrent ni les mêmes accents ni les mêmes espaces
 * d'un moteur à l'autre (MySQL en production, SQLite en test), et le volume est celui d'une ferme (quelques dizaines
 * de bandes, quelques catégories).
 *
 * [$ignorer] : l'identifiant de la ligne en cours de modification (elle peut garder sa propre valeur).
 */
class UniqueNormalise implements ValidationRule
{
    /**
     * @param  Closure(string): string  $message  reçoit la valeur saisie, rend le message français
     */
    public function __construct(
        private readonly string $table,
        private readonly string $colonne,
        private readonly ?string $ignorer,
        private readonly Closure $message,
    ) {}

    /** Le code d'une bande : unique parmi toutes les bandes, en cours ou archivées. */
    public static function bande(?string $ignorer = null, bool $depuisPoste = false): self
    {
        return new self('livestock_lots', 'code', $ignorer, fn (string $code) => LivestockLot::messageCodePris($code, $depuisPoste));
    }

    /** Vrai quand une AUTRE ligne porte déjà cette valeur (même clé). */
    public static function estPris(string $table, string $colonne, ?string $valeur, ?string $ignorer = null): bool
    {
        $cle = CleUnicite::cle($valeur);
        if ($cle === '') {
            return false;
        }

        return DB::table($table)
            ->when($ignorer !== null, fn ($q) => $q->where('id', '!=', $ignorer))
            ->pluck($colonne)
            ->contains(fn ($existante) => CleUnicite::cle((string) $existante) === $cle);
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_string($value)) {
            return;   // `required` / `string` s'en chargent
        }

        if (self::estPris($this->table, $this->colonne, $value, $this->ignorer)) {
            $fail(($this->message)(trim($value)));
        }
    }
}
