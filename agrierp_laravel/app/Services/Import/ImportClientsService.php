<?php

namespace App\Services\Import;

use App\Models\Customer;
use App\Services\CustomerCatalogService;
use App\Services\FusionReferentielsService;

/**
 * Ticket IMPORT-1 — MODULE « CLIENTS ».
 *
 * Point de passage UNIQUE : `CustomerCatalogService::creer` ; règles : `CustomerCatalogService::regles()` (nom obligatoire,
 * téléphone / e-mail / ville / IFU de 13 chiffres facultatifs), mot pour mot.
 *
 * IDEMPOTENCE — clé de ligne : nom normalisé + téléphone normalisé (≥ 8 chiffres, `FusionReferentielsService`). Un client
 * dont la clé existe déjà (fiche ACTIVE, ou identifiant déterministe d'un import précédent, archivée comprise) est IGNORÉ.
 * ⚠️ SANS téléphone exploitable, le serveur ne fusionne jamais (deux « Jean » sans téléphone ne sont pas la même
 * personne) : l'idempotence ne repose alors que sur l'identifiant déterministe (UUID v5 de nom + « sans téléphone ») — un
 * ré-import du MÊME fichier ne crée rien, mais « Jean » sans téléphone saisi au web puis importé existera deux fois.
 */
class ImportClientsService extends ModuleImport
{
    public const EMPREINTE_V1 = '6c5e88100059401585fff5c982453728452e52943f2e167c134dfa8cfb0aa6dd';

    private const CHAMPS = ['name' => 'nom', 'phone' => 'telephone', 'email' => 'email', 'city' => 'ville', 'ifu' => 'ifu'];

    public function cle(): string
    {
        return 'clients';
    }

    public function libelle(): string
    {
        return 'Clients';
    }

    public function description(): string
    {
        return 'Fiches clients : nom, téléphone, e-mail, ville et IFU.';
    }

    public function icone(): string
    {
        return 'groups';
    }

    public function permission(): string
    {
        return 'manage-ventes';
    }

    public function moduleAudit(): string
    {
        return 'ventes';
    }

    public function version(): int
    {
        return 1;
    }

    public function empreinteAttendue(): string
    {
        return self::EMPREINTE_V1;
    }

    public function colonnes(): array
    {
        return [
            new ColonneImport('nom', 'Nom', true, 'texte', '150 caractères au plus.'),
            new ColonneImport('telephone', 'Téléphone', false, 'telephone', '30 caractères au plus. Format texte : le zéro initial est conservé.'),
            new ColonneImport('email', 'E-mail', false, 'texte', 'Adresse e-mail valide, 150 caractères au plus.'),
            new ColonneImport('ville', 'Ville', false, 'texte', '100 caractères au plus.'),
            new ColonneImport('ifu', 'IFU', false, 'telephone', '13 chiffres (client assujetti) ; vide pour un client particulier.'),
        ];
    }

    public function exemples(): array
    {
        return [
            ['nom' => 'Boulangerie Le Bon Pain', 'telephone' => '0197123456', 'email' => 'contact@bonpain.example', 'ville' => 'Pobè', 'ifu' => '3201234567890'],
            ['nom' => 'Mme Adjovi Clarisse', 'telephone' => '', 'email' => '', 'ville' => 'Ikpinlè', 'ifu' => ''],
        ];
    }

    public function notes(): array
    {
        return [
            'Un client dont le nom ET le téléphone (8 chiffres au moins) existent déjà est IGNORÉ ; la fiche existante n\'est jamais modifiée.',
            'Sans téléphone, le client ne peut être reconnu que par un import précédent du même fichier : saisissez le téléphone pour éviter les doublons avec les fiches déjà au logiciel.',
            'Écrivez les téléphones et l\'IFU comme du texte : les cellules du modèle sont déjà au format texte.',
        ];
    }

    public function valider(array $brut): array
    {
        $erreurs = [];
        $ifu = LectureValeurs::texte($brut['ifu'] ?? null);

        $donnees = [
            'name' => LectureValeurs::texte($brut['nom'] ?? null),
            'phone' => ($t = LectureValeurs::texte($brut['telephone'] ?? null)) === '' ? null : $t,
            'email' => ($t = LectureValeurs::texte($brut['email'] ?? null)) === '' ? null : $t,
            'city' => ($t = LectureValeurs::texte($brut['ville'] ?? null)) === '' ? null : $t,
            'ifu' => $ifu === '' ? null : $ifu,
        ];

        $service = app(CustomerCatalogService::class);
        $this->appliquerRegles($donnees, array_intersect_key($service->regles(), self::CHAMPS), [], self::CHAMPS, $erreurs);

        return ['valeurs' => $donnees, 'erreurs' => $erreurs];
    }

    public function cleLigne(array $valeurs): string
    {
        $fusion = app(FusionReferentielsService::class);

        return LectureValeurs::cle((string) $valeurs['name']).'|'.($fusion->normaliserTelephone($valeurs['phone'] ?? null) ?? '-');
    }

    public function dejaPresente(array $valeurs): ?string
    {
        $id = $this->idLigne($valeurs);
        if (Customer::whereKey($id)->exists()) {
            return 'Ce client a déjà été importé : ignoré.';
        }

        if ($this->ficheNaturelle('customers', $valeurs) !== null) {
            return 'Ce client existe déjà (même nom, même téléphone) : ignoré, la fiche existante est gardée.';
        }

        return null;
    }

    public function ecrire(array $valeurs, string $id): void
    {
        app(CustomerCatalogService::class)->creer($valeurs, $id);
        $this->memoriserNaturelle('customers', $valeurs, $id);
    }
}
