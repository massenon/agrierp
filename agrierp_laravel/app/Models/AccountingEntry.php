<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class AccountingEntry extends Model
{
    use HasUuids;

    protected $fillable = [
        'fiscal_year_id', 'entry_date', 'reference', 'source_type', 'source_id', 'is_locked', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'entry_date' => 'date',
            'is_locked' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    public function fiscalYear()
    {
        return $this->belongsTo(FiscalYear::class, 'fiscal_year_id');
    }

    public function lines()
    {
        return $this->hasMany(AccountingEntryLine::class, 'entry_id');
    }

    /**
     * Ticket DEP2 — le NUMÉRO de pièce (« OD-2026-0012 »), RELU de la référence de l'écriture : le début, avant le
     * libellé (« OD-2026-0012 — Dépense Provende »). Une dépense ne le recopie jamais.
     */
    public function getNumeroAttribute(): string
    {
        return trim(Str::before((string) $this->reference, ' — '));
    }

    public function getTotalDebitAttribute(): float
    {
        return (float) $this->lines->sum('debit');
    }

    public function getTotalCreditAttribute(): float
    {
        return (float) $this->lines->sum('credit');
    }

    /** Journal des opérations diverses : le seul journal numéroté aujourd'hui. */
    public const JOURNAL_OD = 'OD';

    /**
     * Gabarit de numéro, de la MÊME longueur qu'un vrai numéro (« OD-2026-0001 », 12 caractères) :
     * les appelants tronquent `reference` à 100 caractères AVANT l'enregistrement, et le remplacement
     * ne doit jamais la faire déborder.
     */
    public const GABARIT_NUMERO = 'OD-????-NNNN';

    /**
     * Ticket 15.20a — ne rend PLUS un numéro : rend le GABARIT que `AccountingEntryService::record()`
     * remplace, DANS sa transaction, par le numéro réel de l'exercice de l'écriture.
     *
     * 🔴 L'ancienne version relisait les 4 derniers caractères de la dernière référence. Une référence
     * finissant par un libellé (« … — AMOUSSOU ») valait 0, donc le numéro suivant était toujours 0001 :
     * deux règlements successifs portaient la même pièce. Et même corrigée, une lecture « max + 1 »
     * faite AVANT la transaction laisse deux postes simultanés tirer le même numéro.
     *
     * Usage inchangé pour les appelants : `generateReference().' — Libellé'`, passé à `record()`.
     * ⚠️ Ne jamais stocker ce gabarit sans passer par `record()` : c'est lui qui le résout.
     */
    public static function generateReference(): string
    {
        return self::GABARIT_NUMERO;
    }

    /**
     * Attribue le numéro suivant du journal pour l'exercice. À appeler DANS la transaction qui crée
     * l'écriture : le compteur est lu sous verrou (une seule transaction à la fois sur MySQL/InnoDB)
     * et son incrément est annulé avec l'écriture — pas de doublon, pas de trou.
     *
     * Ticket 15.20b : à CHAQUE attribution, numéro = max(compteur, plus grand numéro DÉJÀ présent dans les
     * références `OD-{année}-NNNN…`, lu au début de la référence, jamais à la fin) + 1. Les écritures existantes ne
     * sont jamais renumérotées ; les doublons passés se détectent par `comptabilite:doublons-references`.
     */
    public static function attribuerNumero(FiscalYear $exercice, string $journal = self::JOURNAL_OD): string
    {
        $cle = ['journal' => $journal, 'fiscal_year_id' => $exercice->id];

        $ligne = DB::table('accounting_reference_sequences')->where($cle)->lockForUpdate()->first();

        if (! $ligne) {
            // Deux transactions simultanées peuvent arriver ici : la seconde ignore l'insertion de la
            // première, puis relit la ligne sous verrou — toutes deux repartent du même compteur.
            DB::table('accounting_reference_sequences')->insertOrIgnore($cle + ['last_number' => 0]);
            $ligne = DB::table('accounting_reference_sequences')->where($cle)->lockForUpdate()->first();
        }

        $compteur = (int) $ligne->last_number;

        // Ticket 15.20b : à CHAQUE attribution, jamais seulement au premier usage. Une écriture manuelle
        // (`recordManual` avec référence en dur) ou un import peut avoir pris un numéro APRÈS l'amorçage :
        // le compteur seul le dépasserait sans le voir et rendrait un numéro déjà pris.
        $numero = max($compteur, self::plusGrandNumeroExistant($journal, $exercice->year, $compteur)) + 1;

        DB::table('accounting_reference_sequences')->where($cle)->update(['last_number' => $numero]);

        return "{$journal}-{$exercice->year}-".str_pad((string) $numero, 4, '0', STR_PAD_LEFT);
    }

    /**
     * Plus grand numéro déjà porté par une écriture du journal et de l'exercice, lu au DÉBUT de la
     * référence (`OD-AAAA-NNNN…`), jamais à la fin.
     *
     * Coût borné : seules les références lexicalement APRÈS le compteur courant sont lues (borne de
     * plage sur le préfixe `OD-AAAA-`, indexé — migration 2026_10_09_000005). En régime normal le
     * compteur est le maximum : la requête ne rend aucune ligne. Les numéros sont zéro-remplis sur
     * 4 chiffres, donc l'ordre lexical est l'ordre numérique tant que le compteur reste sous 9999 ;
     * au-delà (cinq chiffres), la comparaison lexicale ne suffit plus et tout le préfixe est lu.
     */
    private static function plusGrandNumeroExistant(string $journal, int $annee, int $compteur): int
    {
        $prefixe = "{$journal}-{$annee}-";

        $requete = DB::table('accounting_entries')->where('reference', 'like', $prefixe.'%');

        if ($compteur < 9999) {
            $requete->where('reference', '>', $prefixe.str_pad((string) $compteur, 4, '0', STR_PAD_LEFT));
        }

        $max = 0;

        foreach ($requete->pluck('reference') as $ref) {
            if (preg_match('/^'.preg_quote($prefixe, '/').'(\d+)/', (string) $ref, $m)) {
                $max = max($max, (int) $m[1]);
            }
        }

        return $max;
    }
}