<?php

namespace App\Services;

use App\Exceptions\TransactionInterbloqueeException;
use Closure;
use Illuminate\Contracts\Database\ConcurrencyErrorDetector as DetecteurDeConcurrence;
use Illuminate\Database\ConcurrencyErrorDetector;
use Illuminate\Database\Connection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use PDOException;
use Throwable;

/**
 * Ticket S-T13 — LA TRANSACTION MÉTIER REJOUÉE SUR UN INTERBLOCAGE, EN UN SEUL ENDROIT.
 *
 * Sur MariaDB (jamais sur SQLite, qui sérialise tout), deux écritures simultanées sur les mêmes lignes — la fiche du
 * jour, la bande, le stock du produit — s'interbloquent : l'une est choisie comme victime (`1213 Deadlock found`) et
 * TOUTE sa transaction est annulée par le serveur ; ou elle attend un verrou trop longtemps (`1205 Lock wait timeout`).
 * S-T9 rejouait l'envoi des postes (`DB::transaction(…, 3)`) ; la caisse du web, elle, échouait et la vente était perdue
 * (graine 314 de l'essai à plusieurs postes). Les deux chemins passent maintenant par ce service.
 *
 * Règles :
 *  - chaque essai est une transaction ENTIÈRE : un échec annule tout ce que l'essai a écrit, le suivant repart de rien ;
 *  - seuls un interblocage ou une attente de verrou sont rejoués (au plus `ESSAIS` fois en tout, avec une courte pause
 *    croissante pour que les deux concurrents ne se retrouvent pas aussitôt) ; toute autre erreur remonte telle quelle ;
 *  - après le dernier essai : `TransactionInterbloqueeException`, au message rédigé pour l'utilisateur ;
 *  - ⚠️ LE TRAVAIL REJOUÉ NE DOIT RIEN FAIRE QUI NE S'ANNULE PAS AVEC LA TRANSACTION : pas d'appel au dispositif MeCeF
 *    (la facture partirait deux fois), pas de toast, pas de remise à zéro du panier — tout cela vient APRÈS ;
 *  - ⚠️ JAMAIS REJOUÉE À L'INTÉRIEUR D'UNE AUTRE TRANSACTION : MariaDB annule alors la transaction ENGLOBANTE entière,
 *    rejouer la seule partie interne écrirait hors de toute transaction. L'erreur remonte à l'englobante.
 *    `niveauDeBase` est le niveau de transaction où le service est « au sommet » : 0 en production ; les tests qui
 *    tournent dans la transaction de `RefreshDatabase` le posent à 1 (SQLite y annule vraiment l'essai par son point
 *    de sauvegarde, ce que MariaDB fait au sommet).
 */
class TransactionRejouable
{
    /** Essais au total (le premier compris) — la valeur de S-T9. */
    public const ESSAIS = 3;

    /** MariaDB / MySQL : interblocage, attente de verrou dépassée. Reconnus au CODE, quelle que soit la langue du serveur. */
    private const CODES_MYSQL = [1213, 1205];

    public function __construct(private readonly int $niveauDeBase = 0) {}

    /**
     * Exécute `$travail` dans une transaction, rejouée sur interblocage.
     *
     * @template T
     *
     * @param  Closure(): T  $travail
     * @param  string  $operation  ce qui est rejoué, pour le journal (« vente web », « envoi du poste »…)
     * @return T
     *
     * @throws TransactionInterbloqueeException après `ESSAIS` interblocages
     */
    public function executer(Closure $travail, string $operation, int $essais = self::ESSAIS): mixed
    {
        $connexion = DB::connection();
        $auSommet = $connexion->transactionLevel() === $this->niveauDeBase;

        for ($essai = 1; ; $essai++) {
            $niveau = $connexion->transactionLevel();
            $connexion->beginTransaction();

            try {
                $resultat = $travail();
                $connexion->commit();

                return $resultat;
            } catch (Throwable $e) {
                if (! $this->annuler($connexion, $niveau) || ! $auSommet || ! $this->estInterblocage($e)) {
                    throw $e;
                }

                if ($essai >= $essais) {
                    Log::warning("Interblocage : {$operation} abandonnée après {$essai} essais.", ['erreur' => $e->getMessage()]);

                    throw new TransactionInterbloqueeException($essais, $e);
                }

                Log::warning("Interblocage rejoué : {$operation}, essai {$essai}/{$essais} annulé.", ['erreur' => $e->getMessage()]);
                usleep(random_int(20, 60) * 1000 * $essai);
            }
        }
    }

    /** Interblocage ou attente de verrou, à n'importe quel niveau de la chaîne d'exceptions. */
    public function estInterblocage(Throwable $e): bool
    {
        $detecteur = app()->bound(DetecteurDeConcurrence::class)
            ? app(DetecteurDeConcurrence::class)
            : new ConcurrencyErrorDetector();

        for ($x = $e; $x !== null; $x = $x->getPrevious()) {
            if ($x instanceof PDOException && in_array((int) ($x->errorInfo[1] ?? 0), self::CODES_MYSQL, true)) {
                return true;
            }

            // SQLSTATE 40001 et les messages anglais de MySQL, PostgreSQL, SQLite, SQL Server (règle de Laravel).
            if ($detecteur->causedByConcurrencyError($x)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Annule l'essai (jusqu'au niveau d'avant lui). Faux si l'annulation elle-même échoue (connexion perdue, point de
     * sauvegarde disparu) : l'erreur d'origine remonte alors sans nouvel essai.
     */
    private function annuler(Connection $connexion, int $niveau): bool
    {
        if ($connexion->transactionLevel() <= $niveau) {
            return true;
        }

        try {
            $connexion->rollBack($niveau);

            return true;
        } catch (Throwable) {
            return false;
        }
    }
}
