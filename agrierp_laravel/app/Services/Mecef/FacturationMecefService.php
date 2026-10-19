<?php

namespace App\Services\Mecef;

use App\Models\Sale;
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
 * Idempotent : la vente est relue SOUS VERROU ; déjà `transmise`, elle n'est pas retransmise (un second clic, une
 * retransmission depuis une page restée ouverte, deux appels simultanés : le second attend le premier, puis voit
 * `transmise`).
 *
 * Règle d'un échec (celle du projet depuis le ticket 7.1, reprise par l'envoi des postes au ticket 14.80) : la vente
 * n'est JAMAIS défaite — elle a eu lieu, l'argent est encaissé. Elle passe en `erreur` (« Erreur MeCeF » à l'écran
 * Facturation, bouton « Retransmettre au MeCeF »). Une exception du dispositif est traitée comme un échec de
 * transmission ; seule l'erreur de la base qui empêche même de noter l'échec laisse la vente `en_attente`.
 *
 * ⚠️ LIMITE, À TRANCHER AVEC LE VRAI DISPOSITIF : si le dispositif accepte la facture et que la réponse se perd (ou que
 * la base tombe juste après), la vente reste « à facturer » et une retransmission la redéclarerait. Seule
 * l'implémentation réelle (`RealMecefGateway`, non construite) peut l'empêcher, en passant l'identifiant de la vente
 * comme clé d'idempotence au dispositif (ou en le consultant avant de retransmettre).
 */
class FacturationMecefService
{
    /**
     * @return array{transmise: bool, deja: bool, message: string}
     */
    public function facturer(Sale|string $vente): array
    {
        $id = $vente instanceof Sale ? $vente->getKey() : $vente;
        $transmise = false;

        try {
            return DB::transaction(function () use ($id, &$transmise) {
                $sale = Sale::query()->whereKey($id)->lockForUpdate()->firstOrFail();

                if ($sale->mecef_status === 'transmise') {
                    return [
                        'transmise' => true,
                        'deja' => true,
                        'message' => 'Facture déjà transmise au MeCeF : aucune nouvelle transmission.',
                    ];
                }

                try {
                    $resultat = app(MecefGatewayInterface::class)->transmit($sale->load('lines'));
                } catch (Throwable $e) {
                    report($e);
                    $resultat = [
                        'success' => false,
                        'qr_ref' => null,
                        'message' => 'Dispositif MeCeF injoignable : '.$e->getMessage(),
                    ];
                }

                $transmise = (bool) $resultat['success'];
                $sale->update([
                    'mecef_qr_ref' => $resultat['qr_ref'],
                    'mecef_status' => $resultat['success'] ? 'transmise' : 'erreur',
                ]);

                return [
                    'transmise' => (bool) $resultat['success'],
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
}
