<?php

namespace App\Services\Import;

use Illuminate\Support\Str;

/**
 * Ticket IMPORT-1 — lecture TYPÉE des cellules : les mêmes règles de normalisation au serveur et au poste
 * (`agrierp_flutter/lib/features/importation/importation_repository.dart`, prouvées par `importation_parite_php_test.dart`).
 *
 *  - espaces, espaces insécables et fines de milliers retirés avant lecture d'un nombre ;
 *  - virgule décimale = point ;
 *  - un montant en FCFA est un ENTIER (« 1500,50 » est refusé) ;
 *  - une valeur de liste se compare sans casse ni accents.
 */
final class LectureValeurs
{
    /** Retire espaces, insécables (U+00A0), fines (U+202F, U+2009) : « 1 500 » → « 1500 ». */
    public static function sansEspaces(string $texte): string
    {
        return (string) preg_replace('/[\s\x{00A0}\x{202F}\x{2009}]+/u', '', $texte);
    }

    /** Texte d'une cellule : espaces de bord et insécables retirés ; jamais `null`. */
    public static function texte(mixed $valeur): string
    {
        if ($valeur === null) {
            return '';
        }
        if (is_bool($valeur)) {
            return $valeur ? 'VRAI' : 'FAUX';
        }
        if (is_float($valeur) || is_int($valeur)) {
            return self::nombreEnTexte($valeur);
        }
        if ($valeur instanceof \PhpOffice\PhpSpreadsheet\RichText\RichText) {
            $valeur = $valeur->getPlainText();
        }

        return trim((string) preg_replace('/\x{00A0}/u', ' ', (string) $valeur));
    }

    /** 1500.0 → « 1500 » ; 2.5 → « 2.5 » ; jamais de notation scientifique. */
    public static function nombreEnTexte(int|float $nombre): string
    {
        if (is_int($nombre) || floor($nombre) === $nombre && abs($nombre) < 1e15) {
            return (string) (int) $nombre;
        }

        return rtrim(rtrim(sprintf('%.10F', $nombre), '0'), '.');
    }

    /** Entier de FCFA strict (chiffres seuls) ; `null` si la saisie n'en est pas un. Vide : `null`. */
    public static function entier(string $texte): ?int
    {
        $propre = self::sansEspaces($texte);

        return preg_match('/^\d{1,15}$/', $propre) === 1 ? (int) $propre : null;
    }

    /** Nombre décimal (virgule ou point) ; `null` si illisible. Négatifs admis (les règles du service les refusent). */
    public static function decimal(string $texte): ?float
    {
        $propre = str_replace(',', '.', self::sansEspaces($texte));

        return preg_match('/^-?\d+(\.\d+)?$/', $propre) === 1 ? (float) $propre : null;
    }

    /** Clé de comparaison d'une valeur de liste ou d'un nom : minuscules, sans accents, espaces réduits. */
    public static function cle(string $texte): string
    {
        return trim((string) preg_replace('/[^a-z0-9]+/', ' ', Str::lower(Str::ascii($texte))));
    }
}
