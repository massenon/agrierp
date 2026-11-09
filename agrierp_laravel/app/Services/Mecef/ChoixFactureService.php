<?php

namespace App\Services\Mecef;

use App\Support\AibTaux;
use App\Support\FactureType;
use Illuminate\Validation\ValidationException;

/**
 * Le choix « Facture simple » / « Facture normalisée » d'une vente — LE POINT DE PASSAGE UNIQUE de sa validation (caisse
 * du web `PosInterface` ET envoi du poste `SyncController::pushSales`) : mêmes règles, mêmes motifs.
 *
 *  - type absent = FACTURE SIMPLE (défaut, aucune transmission) ; type inconnu = refus ;
 *  - facture simple : l'identité fiscale de l'acheteur n'a pas d'objet, elle n'est jamais gardée ;
 *  - facture normalisée : NOM ET PRÉNOM du client obligatoires ; IFU facultatif — vide = client SANS IFU (un client
 *    particulier : la DGI l'accepte, la facture part sans `ifu` de client) ; présent = 13 chiffres exactement ; AIB dans la
 *    liste (5 %, 1 %, N/A), jamais deviné quand il manque.
 *
 * Le poste ÉCRIT ces quatre champs à la saisie et les envoie avec la vente ; le serveur les REVALIDE ici.
 */
class ChoixFactureService
{
    public const MOTIF_TYPE = 'Type de facture inconnu : choisissez « Facture simple » ou « Facture normalisée ».';

    public const MOTIF_NOM = 'Le nom et prénom du client sont obligatoires pour une facture normalisée.';

    public const MOTIF_IFU = "L'IFU du client doit comporter 13 chiffres (laissez-le vide pour un client sans IFU).";

    public const MOTIF_AIB = "Choisissez le taux d'AIB : 5 %, 1 % ou Aucun (N/A).";

    /** Taille maximale du nom (colonne `sales.client_nom_facture`). */
    public const NOM_MAX = 150;

    /**
     * @param  array<string, mixed>|null  $donnees  `facture_type`, `client_ifu`, `client_nom_facture`, `aib_taux`
     * @return array{facture_type: string, client_ifu: ?string, client_nom_facture: ?string, aib_taux: ?string}
     *
     * @throws ValidationException refus motivé, par champ
     */
    public function valider(?array $donnees): array
    {
        $type = $donnees['facture_type'] ?? null;
        $type = is_string($type) && trim($type) !== '' ? trim($type) : FactureType::SIMPLE;

        if (! array_key_exists($type, FactureType::LIBELLES)) {
            throw ValidationException::withMessages(['facture_type' => self::MOTIF_TYPE]);
        }

        if ($type === FactureType::SIMPLE) {
            return ['facture_type' => $type, 'client_ifu' => null, 'client_nom_facture' => null, 'aib_taux' => null];
        }

        $nom = $this->texte($donnees['client_nom_facture'] ?? null);
        if ($nom === '' || mb_strlen($nom) > self::NOM_MAX) {
            throw ValidationException::withMessages(['client_nom_facture' => self::MOTIF_NOM]);
        }

        $ifu = $this->texte($donnees['client_ifu'] ?? null);
        $ifu = preg_replace('/\s+/', '', $ifu) ?? '';
        if ($ifu !== '' && ! preg_match('/^\d{13}$/', $ifu)) {
            throw ValidationException::withMessages(['client_ifu' => self::MOTIF_IFU]);
        }

        $aib = $donnees['aib_taux'] ?? null;
        if (! is_string($aib) || ! array_key_exists($aib, AibTaux::LIBELLES)) {
            throw ValidationException::withMessages(['aib_taux' => self::MOTIF_AIB]);
        }

        return [
            'facture_type' => $type,
            'client_ifu' => $ifu === '' ? null : $ifu,
            'client_nom_facture' => $nom,
            'aib_taux' => $aib,
        ];
    }

    private function texte(mixed $valeur): string
    {
        return is_scalar($valeur) ? trim((string) $valeur) : '';
    }
}
