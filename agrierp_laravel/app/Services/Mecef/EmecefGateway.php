<?php

namespace App\Services\Mecef;

use App\Exceptions\MecefFactureInvalideException;
use App\Models\CreditNote;
use App\Models\Sale;
use App\Support\MecefEtat;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * MECEF-1 — PASSERELLE e-MECeF (API en ligne de la DGI du Bénin), transmission par le SERVEUR.
 *
 * Flux : `POST /invoice` (création, renvoie l'`uid`) puis `PUT /invoice/{uid}/confirm` (code MeCeF/DGI, QR, NIM, compteurs,
 * horodatage). Une facture créée mais non confirmée EXPIRE côté DGI au bout de ~2 minutes.
 *
 * ⚠️ NON IDEMPOTENT, jamais rejoué à l'aveugle :
 *  - UN SEUL essai de création (pas de nouvel essai automatique). Une réponse perdue laisse au pire une facture non
 *    confirmée, qui expire d'elle-même chez la DGI ;
 *  - une vente dont la création a réussi (`mecef_uid` connu) ne se re-crée JAMAIS : elle reprend par `GET /invoice/{uid}`
 *    (synchronisation) puis la CONFIRMATION seule ;
 *  - une vente déjà normalisée n'arrive jamais ici (`FacturationMecefService` la verrouille).
 *
 * Jamais d'exception qui bloque la vente : tout échec est un motif français, et l'`etat` dit quoi faire — `en_attente` (réseau,
 * 401/403, 5xx, jeton absent : à retenter), `erreur` (refus 4xx de la DGI : à corriger), `expiree`.
 *
 * Noms de champs et chemins : relevés dans le paquet de référence non officiel Banelsems/laraSgmefQR (lu, JAMAIS une
 * dépendance) ; NON vérifiés contre la documentation DGI ni contre un vrai compte (aucun jeton ni IFU disponible).
 */
class EmecefGateway implements MecefAvoirGatewayInterface, MecefGatewayInterface
{
    public function __construct(private readonly MecefReglage $reglage, private readonly MecefFactureBuilder $constructeur) {}

    public function transmit(Sale $sale): array
    {
        return $this->traiter(
            $sale->mecef_uid,
            fn (array $emetteur) => $this->constructeur->pourVente($sale, $emetteur),
        );
    }

    public function transmitAvoir(CreditNote $avoir): array
    {
        return $this->traiter(
            $avoir->mecef_uid,
            fn (array $emetteur) => $this->constructeur->pourAvoir($avoir, $emetteur),
        );
    }

    /**
     * @param  callable(array): array  $construire
     * @return array<string, mixed>
     */
    private function traiter(?string $uidConnu, callable $construire): array
    {
        $emetteur = $this->reglage->emecef();

        if ($emetteur['jeton'] === '') {
            return $this->echec(MecefEtat::EN_ATTENTE, 'Jeton e-MECeF non configuré : renseignez-le dans Paramètres, Données de l\'Entreprise. La facture reste en attente.');
        }

        if (! preg_match('/^\d{13}$/', $emetteur['ifu'])) {
            return $this->echec(MecefEtat::EN_ATTENTE, 'IFU de l\'entreprise invalide pour e-MECeF (13 chiffres exigés) : corrigez-le dans Paramètres, Données de l\'Entreprise. La facture reste en attente.');
        }

        try {
            $uid = $uidConnu;
            // Montant d'AIB CALCULÉ PAR LA DGI (champ `aib` de sa réponse de création ou de consultation) : jamais calculé ici.
            $aib = null;

            if ($uid === null || $uid === '') {
                $charge = $construire($emetteur);
                $reponse = $this->requete($emetteur)->post('/invoice', $charge);

                if ($reponse->failed() || $this->erreurDansCorps($reponse)) {
                    return $this->echecHttp($reponse, 'Création refusée');
                }

                $uid = (string) ($reponse->json('uid') ?? '');
                $aib = $reponse->json('aib');

                if ($uid === '') {
                    return $this->echec(MecefEtat::EN_ATTENTE, 'Réponse e-MECeF sans identifiant de facture : la facture reste en attente.');
                }
            } else {
                // Reprise : la facture existe déjà chez la DGI, on la consulte puis on confirme — jamais une seconde création.
                $etat = $this->requete($emetteur)->get('/invoice/'.rawurlencode($uid));

                if (in_array($etat->status(), [404, 410], true) || in_array(strtolower((string) $etat->json('status')), ['expired', 'cancelled', 'canceled'], true)) {
                    return $this->echec(MecefEtat::EXPIREE, 'Facture expirée chez la DGI (non confirmée à temps) : retransmettez-la.', ['uid' => null]);
                }

                if ($etat->failed()) {
                    return $this->echecHttp($etat, 'Synchronisation impossible', ['uid' => $uid]);
                }

                $aib = $etat->json('aib');
            }

            $confirmation = $this->requete($emetteur)->put('/invoice/'.rawurlencode($uid).'/confirm');

            if ($confirmation->failed() || $this->erreurDansCorps($confirmation)) {
                $texte = strtolower($this->motifDgi($confirmation));

                if (str_contains($texte, 'expir') || in_array($confirmation->status(), [404, 410], true)) {
                    return $this->echec(MecefEtat::EXPIREE, 'Facture expirée chez la DGI (non confirmée dans les 2 minutes) : retransmettez-la.', ['uid' => null]);
                }

                // L'uid est gardé : la reprise se fera par la confirmation seule.
                return $this->echecHttp($confirmation, 'Confirmation non obtenue', ['uid' => $uid]);
            }

            $qr = (string) ($confirmation->json('qrCode') ?? '');

            if ($qr === '') {
                return $this->echec(MecefEtat::EN_ATTENTE, 'Confirmation e-MECeF sans code QR : la facture reste en attente.', ['uid' => $uid]);
            }

            return [
                'success' => true,
                'qr_ref' => $qr,
                'message' => 'Facture normalisée par e-MECeF.',
                'etat' => MecefEtat::NORMALISEE,
                'details' => [
                    'uid' => $uid,
                    'code' => $confirmation->json('codeMECeFDGI'),
                    'nim' => $confirmation->json('nim'),
                    'compteurs' => $confirmation->json('counters'),
                    'date' => $confirmation->json('dateTime'),
                    'aib' => is_numeric($aib) ? (float) $aib : null,
                ],
            ];
        } catch (MecefFactureInvalideException $e) {
            return $this->echec(MecefEtat::REFUSEE, $e->getMessage());
        } catch (ConnectionException $e) {
            return $this->echec(MecefEtat::EN_ATTENTE, 'Réseau indisponible ou e-MECeF injoignable : la facture reste en attente, retransmettez-la plus tard.', $uidConnu ? ['uid' => $uidConnu] : []);
        } catch (Throwable $e) {
            report($e);

            return $this->echec(MecefEtat::EN_ATTENTE, 'Transmission e-MECeF impossible : la facture reste en attente.', $uidConnu ? ['uid' => $uidConnu] : []);
        }
    }

    private function requete(array $emetteur): PendingRequest
    {
        // CONF-1 : délais et vérification SSL viennent de `SGMEF_*` (défauts 30 s / 10 s / vérifiée).
        $reseau = $this->reglage->reseau();

        return Http::baseUrl($emetteur['url'])
            ->withToken($emetteur['jeton'])
            ->acceptJson()
            ->asJson()
            ->connectTimeout($reseau['delai_connexion'])
            ->timeout($reseau['delai'])
            ->withOptions(['verify' => $reseau['verifier_ssl']]);
    }

    private function erreurDansCorps(Response $r): bool
    {
        $code = $r->json('errorCode');

        return is_string($code) && $code !== '' && strtoupper($code) !== 'OK';
    }

    private function motifDgi(Response $r): string
    {
        return trim((string) ($r->json('errorDesc') ?? $r->json('message') ?? ''));
    }

    /** @param array<string, mixed> $details */
    private function echecHttp(Response $r, string $debut, array $details = []): array
    {
        $statut = $r->status();
        $motif = $this->motifDgi($r);

        if (in_array($statut, [401, 403], true)) {
            return $this->echec(MecefEtat::EN_ATTENTE, 'Jeton e-MECeF refusé par la DGI ('.$statut.') : vérifiez-le ou remplacez-le dans Paramètres. La facture reste en attente.', $details);
        }

        if ($statut === 429 || $statut >= 500) {
            return $this->echec(MecefEtat::EN_ATTENTE, 'Service e-MECeF indisponible ('.$statut.') : la facture reste en attente, retransmettez-la plus tard.', $details);
        }

        return $this->echec(MecefEtat::REFUSEE, $debut.' par e-MECeF ('.$statut.')'.($motif !== '' ? ' : '.$motif : '').'.', $details);
    }

    /** @param array<string, mixed> $details */
    private function echec(string $etat, string $message, array $details = []): array
    {
        return ['success' => false, 'qr_ref' => null, 'message' => $message, 'etat' => $etat, 'details' => $details];
    }
}
