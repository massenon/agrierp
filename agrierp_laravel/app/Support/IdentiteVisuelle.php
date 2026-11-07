<?php

namespace App\Support;

use App\Models\CompanySetting;
use Illuminate\Support\Facades\Storage;

/**
 * Ticket CONF-1 — L'IDENTITÉ VISUELLE DE L'ENTREPRISE : UN SEUL POINT DE PASSAGE.
 *
 * Le logo et le favicon que l'administrateur téléverse (`company_settings.logo_path` / `favicon_path`, disque public,
 * dossier `company/`) étaient lus par l'écran de réglage seul : le menu, la connexion, l'onglet du navigateur et les PDF
 * pointaient des fichiers FIXES. Tout ce qui affiche le logo ou l'icône de la ferme passe désormais ici :
 *
 *  - `logoUrl()` : URL du logo choisi (avec `?v=<date du fichier>` pour que le changement se voie tout de suite), `null` si aucun ;
 *  - `logoCheminPdf()` : chemin DISQUE lisible par DomPDF (jamais une URL distante), repli sur le logo d'installation ;
 *  - `faviconUrl()` / `faviconType()` : l'icône choisie, son type MIME DÉDUIT DU CONTENU du fichier (jamais « image/png » écrit
 *    en dur pour un `.webp` ou un `.ico`), repli sur l'icône d'installation.
 *
 * ⚠️ Un chemin enregistré dont le fichier a disparu du disque vaut « aucun » (repli), jamais une image cassée.
 */
final class IdentiteVisuelle
{
    /** Logo et icône d'INSTALLATION : le repli quand rien n'est choisi. */
    public const LOGO_REPLI = 'assets/images/logo.png';

    public const FAVICON_REPLI = 'assets/images/logo_favicon.webp';

    /** Types MIME que DomPDF sait dessiner (le webp n'en fait pas partie : un logo webp sert au web, le PDF garde le repli). */
    private const TYPES_PDF = ['image/png', 'image/jpeg', 'image/gif'];

    public static function logoUrl(): ?string
    {
        return self::urlDe('logo');
    }

    /** Chemin disque du logo pour un PDF : le logo choisi s'il est PNG/JPEG/GIF, sinon le logo d'installation. */
    public static function logoCheminPdf(): string
    {
        $chemin = self::cheminDisque('logo');

        if ($chemin !== null && in_array(self::typeMime((string) @file_get_contents($chemin, false, null, 0, 16)), self::TYPES_PDF, true)) {
            return $chemin;
        }

        return public_path(self::LOGO_REPLI);
    }

    public static function faviconUrl(): string
    {
        return self::urlDe('favicon') ?? asset(self::FAVICON_REPLI);
    }

    /** Type MIME de l'icône servie, lu dans le fichier lui-même. */
    public static function faviconType(): string
    {
        $chemin = self::cheminDisque('favicon');

        if ($chemin === null) {
            return 'image/webp';
        }

        return self::typeMime((string) @file_get_contents($chemin, false, null, 0, 16)) ?? 'application/octet-stream';
    }

    /** Type MIME d'une image d'après ses premiers octets (ICO, PNG, JPEG, WEBP, GIF) ; `null` si ce n'en est pas une. */
    public static function typeMime(string $octets): ?string
    {
        if (str_starts_with($octets, "\x89PNG\r\n\x1a\n")) {
            return 'image/png';
        }

        if (str_starts_with($octets, "\xFF\xD8\xFF")) {
            return 'image/jpeg';
        }

        if (strlen($octets) >= 12 && str_starts_with($octets, 'RIFF') && substr($octets, 8, 4) === 'WEBP') {
            return 'image/webp';
        }

        if (str_starts_with($octets, 'GIF87a') || str_starts_with($octets, 'GIF89a')) {
            return 'image/gif';
        }

        // ICO : 00 00 01 00, puis le nombre d'images (1 à 255, petit-boutiste).
        if (strlen($octets) >= 6 && str_starts_with($octets, "\x00\x00\x01\x00") && unpack('v', substr($octets, 4, 2))[1] >= 1) {
            return 'image/vnd.microsoft.icon';
        }

        return null;
    }

    private static function urlDe(string $genre): ?string
    {
        $chemin = self::cheminRelatif($genre);

        if ($chemin === null) {
            return null;
        }

        $version = Storage::disk('public')->lastModified($chemin);

        return asset('storage/'.$chemin).'?v='.$version;
    }

    private static function cheminRelatif(string $genre): ?string
    {
        try {
            $chemin = CompanySetting::query()->first()?->{$genre.'_path'};
        } catch (\Throwable) {
            return null; // base pas encore migrée (page de connexion d'une installation neuve) : le repli s'applique.
        }

        return is_string($chemin) && $chemin !== '' && Storage::disk('public')->exists($chemin) ? $chemin : null;
    }

    private static function cheminDisque(string $genre): ?string
    {
        $chemin = self::cheminRelatif($genre);

        return $chemin === null ? null : Storage::disk('public')->path($chemin);
    }
}
