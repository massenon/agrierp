<?php

namespace App\Services\Mecef;

use App\Support\MecefMode;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * « Tester la configuration » du formulaire e-MECeF — SANS JAMAIS CRÉER DE FACTURE.
 *
 *  1. VÉRIFICATIONS LOCALES (aucun réseau) : mode, IFU à 13 chiffres, adresse, jeton présent (et, s'il se lit comme un JWT, non
 *     expiré — la date d'expiration n'est pas un secret) ;
 *  2. UN SEUL APPEL DE LECTURE, SANS EFFET : `GET {adresse}/info/status` (état du service e-MECeF — paquet de référence
 *     Banelsems/laraSgmefQR, `SgmefApiClient::getStatus()`), jeton en `Bearer`. Jamais `POST /invoice`, jamais une confirmation.
 *     Si l'adresse ne répond pas à cette lecture, rien d'autre n'est tenté.
 *
 * Résultat en français : « Jeton refusé (401) », « Hôte injoignable », « Configuration valide »… Le jeton n'est JAMAIS affiché
 * ni journalisé (ni dans le résultat, ni dans une exception rapportée) ; une réponse de la DGI n'est lue que pour son statut et
 * trois champs publics (`ifu`, `tokenValid`, `status`).
 *
 * ⚠️ NON VÉRIFIÉ contre la vraie DGI (ni jeton ni IFU) : le chemin `/info/status` et les noms de champs de sa réponse viennent
 * du paquet de référence non officiel ; une réponse inattendue est dite telle quelle (« réponse inattendue »), jamais devinée.
 */
class MecefConfigurationTesteur
{
    public const DELAI = 8;

    public const DELAI_CONNEXION = 5;

    /**
     * @param  array{mode?: ?string, ifu?: ?string, url?: ?string, jeton?: ?string}  $saisie  valeurs du formulaire ; un jeton vide = celui qui est enregistré
     * @return array{ok: bool, resume: string, lignes: array<int, array{ok: bool, libelle: string, detail: string}>}
     */
    public function tester(array $saisie): array
    {
        $enregistre = app(MecefReglage::class)->emecef();
        $mode = (string) ($saisie['mode'] ?? '');
        $ifu = trim((string) ($saisie['ifu'] ?? $enregistre['ifu']));
        $url = rtrim(trim((string) ($saisie['url'] ?? '')) ?: $enregistre['url'], '/');
        $jeton = trim((string) ($saisie['jeton'] ?? '')) ?: $enregistre['jeton'];

        $lignes = [];
        $bloquant = false;
        $ajoute = function (bool $ok, string $libelle, string $detail, bool $bloque = true) use (&$lignes, &$bloquant): void {
            $lignes[] = ['ok' => $ok, 'libelle' => $libelle, 'detail' => $detail];
            $bloquant = $bloquant || (! $ok && $bloque);
        };

        // 1. Local.
        if ($mode === MecefMode::EMECEF) {
            $ajoute(true, 'Mode', 'e-MECeF (en ligne).');
        } elseif ($mode === MecefMode::BOITIER) {
            $ajoute(false, 'Mode', 'Mode boîtier : la transmission par le poste n\'est pas encore disponible. Choisissez « e-MECeF (en ligne) » pour tester.');
        } else {
            $ajoute(false, 'Mode', 'Facturation normalisée désactivée : choisissez « e-MECeF (en ligne) » pour tester.');
        }

        $ajoute((bool) preg_match('/^\d{13}$/', $ifu), 'IFU de l\'entreprise', preg_match('/^\d{13}$/', $ifu) ? $ifu : 'L\'IFU doit comporter 13 chiffres.');

        $parties = parse_url($url);
        $urlValide = filter_var($url, FILTER_VALIDATE_URL) !== false && in_array($parties['scheme'] ?? '', ['http', 'https'], true) && ! empty($parties['host']);
        $ajoute($urlValide, 'Adresse de l\'API', $urlValide ? $url : 'Adresse invalide : elle doit commencer par https://.');

        if ($jeton === '') {
            $ajoute(false, 'Jeton', 'Aucun jeton : saisissez celui du compte e-MECeF de votre IFU (portail de la DGI).');
        } else {
            $expire = $this->expirationDuJeton($jeton);
            if ($expire !== null && $expire < time()) {
                $ajoute(false, 'Jeton', 'Jeton expiré depuis le '.date('d/m/Y', $expire).' : demandez-en un nouveau sur le portail e-MECeF.');
            } else {
                $ajoute(true, 'Jeton', $expire !== null ? 'Présent, valable jusqu\'au '.date('d/m/Y', $expire).'.' : 'Présent.');
            }
        }

        if ($bloquant) {
            return ['ok' => false, 'resume' => 'Configuration incomplète : corrigez les points signalés, aucun appel n\'a été fait.', 'lignes' => $lignes];
        }

        // 2. UN appel de lecture, sans effet.
        [$ok, $detail] = $this->lireLEtat($url, $jeton, $ifu);
        $lignes[] = ['ok' => $ok, 'libelle' => 'Appel de lecture (état du service e-MECeF)', 'detail' => $detail];

        return [
            'ok' => $ok,
            'resume' => $ok ? 'Configuration valide.' : $detail,
            'lignes' => $lignes,
        ];
    }

    /** @return array{0: bool, 1: string} */
    private function lireLEtat(string $url, string $jeton, string $ifu): array
    {
        try {
            $reponse = Http::baseUrl($url)->withToken($jeton)->acceptJson()
                ->connectTimeout(self::DELAI_CONNEXION)->timeout(self::DELAI)
                ->get('/info/status');
        } catch (ConnectionException) {
            return [false, 'Hôte injoignable : vérifiez l\'adresse de l\'API et la connexion internet.'];
        } catch (Throwable) {
            // Jamais le message de l'exception (il peut reprendre l'adresse) : un motif fixe.
            return [false, 'Appel impossible : l\'adresse de l\'API est inutilisable.'];
        }

        $statut = $reponse->status();

        if (in_array($statut, [401, 403], true)) {
            return [false, 'Jeton refusé ('.$statut.') : vérifiez-le ou remplacez-le.'];
        }

        if ($statut === 404) {
            return [false, 'Adresse introuvable (404) : l\'hôte répond mais ce n\'est pas l\'API e-MECeF attendue.'];
        }

        if ($statut === 429 || $statut >= 500) {
            return [false, 'Service e-MECeF indisponible ('.$statut.') : réessayez plus tard.'];
        }

        if ($reponse->failed()) {
            return [false, 'Réponse inattendue de l\'API e-MECeF ('.$statut.').'];
        }

        $corps = $reponse->json();

        if (! is_array($corps)) {
            return [false, 'Réponse inattendue : l\'hôte répond, mais pas comme l\'API e-MECeF.'];
        }

        if (($corps['tokenValid'] ?? null) === false || (is_string($corps['tokenValid'] ?? null) && strtolower($corps['tokenValid']) === 'false')) {
            return [false, 'Jeton refusé par la DGI (jeton non valide).'];
        }

        if (($corps['status'] ?? null) === false) {
            return [false, 'Le service e-MECeF se déclare indisponible.'];
        }

        $ifuDuJeton = is_string($corps['ifu'] ?? null) ? trim($corps['ifu']) : '';
        if ($ifuDuJeton !== '' && $ifuDuJeton !== $ifu) {
            return [false, 'L\'IFU du jeton ('.$ifuDuJeton.') n\'est pas celui de l\'entreprise ('.$ifu.') : corrigez l\'IFU ou utilisez le jeton de cet IFU.'];
        }

        return [true, 'Le service e-MECeF répond et accepte le jeton.'];
    }

    /** Date d'expiration (`exp`) d'un jeton qui se lit comme un JWT, sinon null. Rien du jeton n'est conservé. */
    private function expirationDuJeton(string $jeton): ?int
    {
        $parties = explode('.', $jeton);

        if (count($parties) !== 3) {
            return null;
        }

        $json = base64_decode(strtr($parties[1], '-_', '+/'), true);
        $charge = $json === false ? null : json_decode($json, true);

        return is_array($charge) && isset($charge['exp']) && is_numeric($charge['exp']) ? (int) $charge['exp'] : null;
    }
}
