<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * ⚠️ Nommée `Correspondence` (et non `Mail`) volontairement : ce projet
 * a déjà un dossier `app/Mail/` pour les Mailables (envoi d'e-mails,
 * ex. relances clients, ticket 4.7) — nommer ce modèle `Mail` aurait créé
 * un risque réel de collision avec `Illuminate\Support\Facades\Mail`
 * dans un fichier qui aurait besoin des deux en même temps.
 */
class Correspondence extends Model
{
    use HasUuids;

    protected $table = 'mails';

    protected $fillable = ['reference', 'type', 'subject', 'party', 'mail_date', 'is_active'];

    protected function casts(): array
    {
        return [
            'mail_date' => 'date',
            'is_active' => 'boolean',
        ];
    }

    /**
     * Prochaine référence `CR-AAAA-NNN` (NNN sur 3 chiffres jusqu'à 999, puis 4 chiffres ou plus).
     *
     * ⚠️ Ticket 15.23 : l'ancienne version triait les références comme du TEXTE
     * (« CR-2026-999 » > « CR-2026-1000 ») et lisait les 3 derniers caractères (« 000 » → 0 + 1) :
     * le 1000e courrier recevait une référence déjà prise. Le plus grand numéro est maintenant
     * cherché NUMÉRIQUEMENT.
     *
     * ⚠️ Ce calcul seul n'est pas atomique : l'atomicité vient de la contrainte UNIQUE de
     * `reference` + la reprise de `CourrierService::creer()`, qui recalcule si deux écritures
     * se sont disputé le même numéro.
     */
    public static function generateReference(): string
    {
        $prefix = 'CR-'.now()->format('Y').'-';
        $longueur = strlen($prefix);

        $max = static::where('reference', 'like', $prefix.'%')
            ->pluck('reference')
            ->map(fn (string $r) => substr($r, $longueur))
            ->filter(fn (string $n) => $n !== '' && ctype_digit($n))
            ->map(fn (string $n) => (int) $n)
            ->max() ?? 0;

        return $prefix.str_pad((string) ($max + 1), 3, '0', STR_PAD_LEFT);
    }
}
