<?php

namespace App\Services\Mecef;

use App\Models\CreditNote;
use App\Models\Sale;
use App\Support\MecefEtat;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Throwable;

/**
 * Ticket S-T13 — LA FACTURE NORMALISÉE D'UNE VENTE, APRÈS SA TRANSACTION, UNE SEULE FOIS.
 *
 * Pourquoi hors de la transaction de vente : celle-ci est rejouée sur un interblocage (`TransactionRejouable`). Un
 * appel au dispositif MeCeF fait DANS un essai annulé serait refait à l'essai suivant — la DGI recevrait deux factures
 * pour une vente. La vente est donc d'abord validée (statut `en_attente` = à facturer, défaut de la colonne), puis
 * facturée ici, par la caisse du web, l'envoi des postes et la retransmission de l'écran Facturation.
 *
 * Idempotent : la vente est relue SOUS VERROU ; déjà normalisée (`transmise`), elle n'est JAMAIS retransmise (un second
 * clic, une retransmission depuis une page restée ouverte, deux appels simultanés : le second attend le premier, puis
 * voit `transmise`).
 *
 * MECEF-1 — la passerelle suit le mode réglé (`MecefGatewayFactory`). Le résultat porte l'état (`MecefEtat` : normalisée,
 * en attente, refusée, expirée) et ce que la DGI a renvoyé (uid, code MeCeF/DGI, NIM, compteurs, horodatage, QR) ; l'`uid`
 * d'une facture créée mais pas confirmée est GARDÉ : la reprise confirme, elle ne recrée jamais. Un AVOIR sur une vente
 * normalisée se transmet comme facture d'avoir `FA` (`facturerAvoir`), par le même mécanisme.
 *
 * Règle d'un échec (celle du projet depuis le ticket 7.1, reprise par l'envoi des postes au ticket 14.80) : la vente n'est
 * JAMAIS défaite — elle a eu lieu, l'argent est encaissé. Une exception du dispositif est traitée comme un échec de
 * transmission ; seule l'erreur de la base qui empêche même de noter l'échec laisse la vente `en_attente`.
 */
class FacturationMecefService
{
    /**
     * @return array{transmise: bool, deja: bool, message: string, inactif?: bool, simple?: bool}
     */
    public function facturer(Sale|string $vente): array
    {
        // Ticket VC-5 : module désactivé — rien n'est transmis, la vente reste « en attente », aucun appelant ne lève d'alerte.
        if (! app(MecefReglage::class)->actif()) {
            return ['transmise' => false, 'deja' => false, 'inactif' => true, 'message' => 'module MeCeF désactivé'];
        }

        // Une FACTURE SIMPLE n'est JAMAIS transmise (même module actif) : décision du client, une correction passe par un avoir.
        $enregistree = $vente instanceof Sale ? $vente : Sale::query()->find($vente);
        if ($enregistree !== null && ! $enregistree->estADeclarer()) {
            return ['transmise' => false, 'deja' => false, 'simple' => true, 'message' => 'Facture simple : aucune transmission à la DGI.'];
        }

        return $this->transmettre(
            Sale::class,
            $vente instanceof Sale ? $vente->getKey() : $vente,
            fn (Sale $s) => app(MecefGatewayInterface::class)->transmit($s->load('lines')),
            'Facture déjà transmise au MeCeF : aucune nouvelle transmission.',
            true,
        );
    }

    /**
     * MECEF-1 — l'avoir d'une vente NORMALISÉE part comme facture d'avoir `FA` (référence = uid de la facture d'origine).
     * Un avoir sur une vente non normalisée n'a pas d'objet : rien n'est transmis, son statut reste vide.
     *
     * @return array{transmise: bool, deja: bool, message: string, inactif?: bool, sans_objet?: bool}
     */
    public function facturerAvoir(CreditNote|string $avoir): array
    {
        $id = $avoir instanceof CreditNote ? $avoir->getKey() : $avoir;
        $note = CreditNote::query()->with('sale')->find($id);

        if ($note === null || $note->sale === null || ! $note->sale->estNormalisee()) {
            return ['transmise' => false, 'deja' => false, 'sans_objet' => true, 'message' => 'Avoir sur une facture non normalisée : rien à transmettre.'];
        }

        if (! app(MecefReglage::class)->actif()) {
            // La facture d'origine EST normalisée : l'avoir attend la réactivation, il ne disparaît pas des registres.
            if ($note->mecef_status === null) {
                $note->update(['mecef_status' => MecefEtat::EN_ATTENTE, 'mecef_message' => 'Module MeCeF désactivé : avoir à transmettre dès sa réactivation.']);
            }

            return ['transmise' => false, 'deja' => false, 'inactif' => true, 'message' => 'module MeCeF désactivé'];
        }

        return $this->transmettre(
            CreditNote::class,
            $id,
            function (CreditNote $n) {
                $passerelle = app(MecefGatewayInterface::class);

                return $passerelle instanceof MecefAvoirGatewayInterface
                    ? $passerelle->transmitAvoir($n)
                    : ['success' => false, 'qr_ref' => null, 'message' => 'Cette passerelle ne transmet pas les avoirs.', 'etat' => MecefEtat::EN_ATTENTE];
            },
            'Avoir déjà transmis au MeCeF : aucune nouvelle transmission.',
            false,
        );
    }

    /**
     * @param  class-string<Model>  $classe
     * @param  callable(Model): array<string, mixed>  $appel
     */
    private function transmettre(string $classe, string $id, callable $appel, string $messageDeja, bool $estVente): array
    {
        $transmise = false;

        try {
            return DB::transaction(function () use ($classe, $id, $appel, $messageDeja, $estVente, &$transmise) {
                $objet = $classe::query()->whereKey($id)->lockForUpdate()->firstOrFail();

                if ($objet->mecef_status === MecefEtat::NORMALISEE) {
                    return ['transmise' => true, 'deja' => true, 'message' => $messageDeja];
                }

                try {
                    $resultat = $appel($objet);
                } catch (Throwable $e) {
                    report($e);
                    $resultat = [
                        'success' => false,
                        'qr_ref' => null,
                        'message' => 'Dispositif MeCeF injoignable : '.$e->getMessage(),
                    ];
                }

                $transmise = (bool) $resultat['success'];
                $etat = $transmise ? MecefEtat::NORMALISEE : ($resultat['etat'] ?? MecefEtat::REFUSEE);
                $details = (array) ($resultat['details'] ?? []);

                $colonnes = [
                    'mecef_qr_ref' => $resultat['qr_ref'],
                    'mecef_status' => $etat,
                    'mecef_message' => $transmise ? null : (string) $resultat['message'],
                ];

                if (array_key_exists('uid', $details)) {
                    $colonnes['mecef_uid'] = $details['uid'];
                }

                if ($transmise) {
                    $colonnes += [
                        'mecef_code' => $details['code'] ?? null,
                        'mecef_nim' => $details['nim'] ?? null,
                        'mecef_compteurs' => $details['compteurs'] ?? null,
                        'mecef_normalise_le' => $this->horodatage($details['date'] ?? null),
                    ];

                    // Le montant d'AIB que la DGI a calculé (une vente seulement : l'avoir n'a pas cette colonne).
                    if ($estVente && isset($details['aib'])) {
                        $colonnes['mecef_aib_montant'] = $details['aib'];
                    }
                }

                $objet->update($colonnes);

                return [
                    'transmise' => $transmise,
                    'deja' => false,
                    'message' => (string) $resultat['message'],
                ];
            });
        } catch (Throwable $e) {
            // La base elle-même a échoué (verrou, connexion) : le statut n'est pas noté, la vente reste `en_attente`
            // (sans bouton « Retransmettre » à l'écran Facturation). Si le dispositif avait DÉJÀ accepté la facture,
            // le dire : la retransmettre la déclarerait deux fois.
            report($e);

            return [
                'transmise' => false,
                'deja' => false,
                'message' => $transmise
                    ? 'Facture transmise au MeCeF, mais son statut n\'a pas pu être enregistré : ne pas la retransmettre avant vérification.'
                    : 'Statut MeCeF non enregistré : '.$e->getMessage(),
            ];
        }
    }

    /** L'horodatage de la DGI, ou l'instant présent s'il est absent ou illisible (la facture est bien normalisée). */
    private function horodatage(mixed $date): Carbon
    {
        try {
            return $date ? Carbon::parse((string) $date) : now();
        } catch (Throwable) {
            return now();
        }
    }
}
