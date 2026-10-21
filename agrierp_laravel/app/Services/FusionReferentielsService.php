<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\CorrespondanceIdentifiant;
use App\Models\Customer;
use App\Models\Product;
use App\Models\Supplier;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Str;

/**
 * Ticket S-T5 (méthode TATACORA) — FUSION PAR CLÉ NATURELLE DES RÉFÉRENTIELS SAISIS AU POSTE.
 *
 * « Le même article saisi sur deux postes n'existe qu'une fois ; le poste apprend l'identifiant du serveur. » Un
 * client, un fournisseur ou un produit créé hors ligne sur un poste, alors qu'une fiche ACTIVE de même clé naturelle
 * existe déjà au serveur sous un autre identifiant, ne crée pas de seconde fiche : la correspondance (id du poste →
 * id du serveur) est enregistrée (`correspondances_identifiants`) et l'acquittement la rend au poste.
 *
 * ⚠️⚠️ CETTE CLASSE EST LE SEUL ENDROIT QUI DIT CE QU'EST « LE MÊME » CLIENT, FOURNISSEUR OU PRODUIT, ET LE SEUL QUI
 * TRADUIT UN IDENTIFIANT DE POSTE FUSIONNÉ ([traduireEnvoi], appelé par `SyncController::push` pour chaque table
 * d'envoi de [REFERENCES]).
 *
 * ## Clés naturelles retenues — PRUDENTES : on ne fusionne que sur une correspondance CERTAINE
 *
 * Aucune contrainte d'unicité n'existe au schéma (`customers`, `suppliers` : aucun index ; `products` : `sku` seul) et
 * le web n'empêche aucun doublon (`CustomerCatalogService`, `SupplierCatalogService`, `ProductCatalogService` : aucune
 * règle `unique`). Les clés ci-dessous sont donc une décision de ce ticket, documentée ici :
 *
 * - **Client** : nom normalisé + téléphone normalisé. ⚠️ Le téléphone est FACULTATIF pour un client : SANS téléphone
 *   (ou avec moins de 8 chiffres), AUCUNE fusion — deux « Jean » sans téléphone ne sont pas la même personne.
 * - **Fournisseur** : nom normalisé + téléphone normalisé (le téléphone y est obligatoire, au web comme au poste ; la
 *   même règle des 8 chiffres s'applique). Le nom seul ne suffit pas : deux « Quincaillerie Centrale » de deux villes
 *   sont deux fournisseurs.
 * - **Produit** : nom normalisé + catégorie + unité normalisée + filière (espèce, nulle comprise). ⚠️ PAS LE SKU : il
 *   est ENGENDRÉ par le serveur à la création (`Product::generateSku`), celui du poste est provisoire et n'est jamais
 *   lu — deux postes ont donc deux SKU provisoires différents pour le même produit. Le même nom dans la même catégorie,
 *   à la même unité et pour la même filière désigne le même article du catalogue ; « Poulet » à la pièce et « Poulet »
 *   au kilo restent deux produits.
 *
 * Normalisation : nom en minuscules, sans accents (« Société » = « societe »), ponctuation et espaces multiples réduits
 * à un espace ; téléphone réduit à ses chiffres, préfixe international du Bénin (`+229`, `00229`) retiré. « 97 12 34 56 »
 * et « 01 97 12 34 56 » (ancienne et nouvelle numérotation) restent DIFFÉRENTS : pas de certitude, pas de fusion.
 *
 * ## Ce que la fusion fait, et ne fait pas
 *
 * - Seulement à la CRÉATION reçue d'un poste (identifiant inconnu du serveur), et seulement si la fiche reçue est
 *   active. Une modification ne fusionne jamais deux fiches existantes.
 * - La fiche du serveur est GARDÉE TELLE QUELLE : rien de la fiche du poste n'y est écrit (ni e-mail, ni ville, ni
 *   prix). ⚠️ Pour un produit, la QUANTITÉ INITIALE saisie au poste n'est PAS ajoutée : deux postes qui déclarent le
 *   même article déclarent le même stock physique ; l'additionner le compterait deux fois. Un écart se corrige par un
 *   ajustement d'inventaire. Le motif rendu au poste le dit.
 * - Plusieurs fiches actives de même clé au serveur (doublons d'avant ce ticket, ou saisis au web) : la plus ANCIENNE
 *   (création, puis identifiant) est retenue, toujours la même.
 * - Un RENVOI de l'identifiant du poste (accusé perdu, ou poste ancien qui modifie ou archive SA copie) est acquitté
 *   avec la même correspondance, SANS RIEN ÉCRIRE : archiver la copie locale d'un poste ancien n'archive pas la fiche
 *   partagée.
 * - La page web n'est pas concernée : elle crée comme avant (aucun critère d'unicité n'y existe).
 */
class FusionReferentielsService
{
    /** Tables référentielles fusionnables et leur modèle. */
    public const MODELES = [
        'customers' => Customer::class,
        'suppliers' => Supplier::class,
        'products' => Product::class,
    ];

    /**
     * ⚠️⚠️ TOUTE RÉFÉRENCE D'UN ENVOI DU POSTE VERS UN CLIENT, UN FOURNISSEUR OU UN PRODUIT, table d'envoi par table
     * d'envoi : chemin dans l'enregistrement (`*` = chaque élément d'une liste) → table référentielle. Un identifiant
     * de poste fusionné y est remplacé par celui du serveur AVANT le traitement de la table
     * (`SyncController::envoiTraduit`). Un garde-fou (`FusionReferentielsTest`) vérifie que chaque champ
     * `customer_id`, `supplier_id`, `*product_id` validé par `SyncController` figure ici, et que chaque table d'ici
     * est bien traduite par `push`.
     *
     * Les retours fournisseur (`purchase_id`), les imputations d'avances (`customer_advance_id`, `receivable_id`,
     * `sale_id`) et les remboursements passent par d'autres identifiants ; les remboursements portent `supplier_id`.
     *
     * @var array<string, array<string, string>>
     */
    public const REFERENCES = [
        'customer_advances' => ['customer_id' => 'customers'],
        'livestock_daily_entries' => ['feed_product_id' => 'products', 'treatment_product_id' => 'products'],
        'purchases' => ['supplier_id' => 'suppliers', 'lines.*.product_id' => 'products'],
        // Ticket DEV — le client d'un devis du poste.
        'quotes' => ['customer_id' => 'customers'],
        'supplier_payments' => ['supplier_id' => 'suppliers'],
        'supplier_refunds' => ['supplier_id' => 'suppliers'],
        'sales' => ['customer_id' => 'customers', 'lines.*.product_id' => 'products'],
        'stock_adjustments' => ['product_id' => 'products'],
    ];

    /** Nombre minimal de chiffres d'un téléphone pour qu'il identifie quelqu'un (ancienne numérotation béninoise). */
    public const CHIFFRES_MINIMUM_TELEPHONE = 8;

    /** @var array<string, string> libellé de l'audit par table */
    private const ACTION_AUDIT = [
        'customers' => 'customer.merged',
        'suppliers' => 'supplier.merged',
        'products' => 'product.merged',
    ];

    /** @var array<string, string> */
    private const MODULE_AUDIT = [
        'customers' => 'ventes',
        'suppliers' => 'achats',
        'products' => 'stocks',
    ];

    // ── Clés naturelles ─────────────────────────────────────────────────────────────────────────────────────────────

    /**
     * Clé naturelle normalisée d'une fiche (données envoyées par le poste ou colonnes d'un modèle), ou `null` quand
     * elle ne permet AUCUNE certitude (nom vide, téléphone absent ou trop court, catégorie ou unité absente).
     *
     * @param  array<string, mixed>  $donnees
     */
    public function cleNaturelle(string $table, array $donnees): ?string
    {
        $nom = $this->normaliserNom($donnees['name'] ?? null);
        if ($nom === '') {
            return null;
        }

        if ($table === 'customers' || $table === 'suppliers') {
            $telephone = $this->normaliserTelephone($donnees['phone'] ?? null);

            return $telephone === null ? null : $nom.'|'.$telephone;
        }

        if ($table === 'products') {
            $categorie = $donnees['category_id'] ?? null;
            $unite = $this->normaliserNom($donnees['unit'] ?? null);
            if (! is_string($categorie) || $categorie === '' || $unite === '') {
                return null;
            }
            $espece = $donnees['species_id'] ?? null;

            return $nom.'|'.$categorie.'|'.$unite.'|'.(is_string($espece) && $espece !== '' ? $espece : '-');
        }

        throw new \InvalidArgumentException("Table non fusionnable : {$table}.");
    }

    /** Minuscules, sans accents, ponctuation et espaces réduits à un seul espace. */
    public function normaliserNom(mixed $nom): string
    {
        if (! is_string($nom)) {
            return '';
        }

        $ascii = Str::lower(Str::ascii($nom));

        return trim((string) preg_replace('/[^a-z0-9]+/', ' ', $ascii));
    }

    /** Chiffres seuls, sans préfixe international du Bénin ; `null` sous [CHIFFRES_MINIMUM_TELEPHONE] chiffres. */
    public function normaliserTelephone(mixed $telephone): ?string
    {
        if (! is_string($telephone) && ! is_int($telephone)) {
            return null;
        }

        $chiffres = (string) preg_replace('/\D+/', '', (string) $telephone);
        if (str_starts_with($chiffres, '00')) {
            $chiffres = substr($chiffres, 2);
        }
        // +229 suivi d'un numéro national (8 chiffres, ou 10 depuis la nouvelle numérotation).
        if (str_starts_with($chiffres, '229') && strlen($chiffres) >= 11) {
            $chiffres = substr($chiffres, 3);
        }

        return strlen($chiffres) >= self::CHIFFRES_MINIMUM_TELEPHONE ? $chiffres : null;
    }

    /**
     * La fiche ACTIVE du serveur, d'un AUTRE identifiant, de même clé naturelle que [$donnees] — la plus ancienne s'il y
     * en a plusieurs —, ou `null`.
     *
     * @param  array<string, mixed>  $donnees
     */
    public function ficheExistante(string $table, array $donnees, string $idPoste): ?Model
    {
        $cle = $this->cleNaturelle($table, $donnees);
        if ($cle === null) {
            return null;
        }

        $modele = self::MODELES[$table];
        $requete = $modele::query()->where('is_active', true)->where('id', '!=', $idPoste);

        if ($table === 'products') {
            // Pré-filtre exact sur la catégorie ; le nom et l'unité se comparent normalisés, en PHP.
            $requete->where('category_id', $donnees['category_id']);
        } else {
            $requete->whereNotNull('phone');
        }

        return $requete->orderBy('created_at')->orderBy('id')->get()
            ->first(fn (Model $fiche) => $this->cleNaturelle($table, $fiche->getAttributes()) === $cle);
    }

    // ── Correspondances ─────────────────────────────────────────────────────────────────────────────────────────────

    /** L'identifiant du serveur que désigne [$idPoste], si une fusion l'a enregistré. */
    public function idServeur(string $table, string $idPoste): ?string
    {
        return CorrespondanceIdentifiant::query()
            ->where('table_referentiel', $table)
            ->where('id_poste', $idPoste)
            ->value('id_serveur');
    }

    /**
     * Fusion d'une création reçue d'un poste : rend la correspondance déjà enregistrée (renvoi), ou en enregistre une
     * nouvelle si une fiche active de même clé existe ; `null` sinon (la création suit son cours).
     *
     * @param  array<string, mixed>  $donnees  données VALIDÉES de la fiche reçue
     * @return array{id: string, id_serveur: string, motif: string}|null
     */
    public function fusionnerCreation(string $table, string $idPoste, array $donnees, ?string $poste, ?string $utilisateurId): ?array
    {
        if (array_key_exists('is_active', $donnees) && $donnees['is_active'] !== null && ! (bool) $donnees['is_active']) {
            return null;
        }

        $existante = $this->ficheExistante($table, $donnees, $idPoste);
        if ($existante === null) {
            return null;
        }

        try {
            CorrespondanceIdentifiant::create([
                'table_referentiel' => $table,
                'id_poste' => $idPoste,
                'id_serveur' => $existante->getKey(),
                'cle_naturelle' => Str::limit((string) $this->cleNaturelle($table, $donnees), 250, ''),
                'poste' => $poste,
                'user_id' => $utilisateurId,
                'fusionne_le' => now(),
            ]);
        } catch (UniqueConstraintViolationException) {
            // Deux envois simultanés du même identifiant : la première correspondance fait foi.
            return $this->correspondance($table, $idPoste);
        }

        AuditLog::record(self::ACTION_AUDIT[$table], self::MODULE_AUDIT[$table], $utilisateurId);

        return $this->ligneDeReponse($table, $idPoste, (string) $existante->getKey());
    }

    /**
     * La ligne `merged` d'un identifiant de poste DÉJÀ fusionné (renvoi), ou `null`.
     *
     * @return array{id: string, id_serveur: string, motif: string}|null
     */
    public function correspondance(string $table, string $idPoste): ?array
    {
        $idServeur = $this->idServeur($table, $idPoste);

        return $idServeur === null ? null : $this->ligneDeReponse($table, $idPoste, $idServeur);
    }

    /** @return array{id: string, id_serveur: string, motif: string} */
    private function ligneDeReponse(string $table, string $idPoste, string $idServeur): array
    {
        return ['id' => $idPoste, 'id_serveur' => $idServeur, 'motif' => self::motif($table)];
    }

    /** Motif lisible rendu au poste avec chaque fusion. */
    public static function motif(string $table): string
    {
        return match ($table) {
            'customers' => 'Ce client existe déjà au serveur (même nom, même téléphone) : la fiche du serveur est gardée et le poste prend son identifiant.',
            'suppliers' => 'Ce fournisseur existe déjà au serveur (même nom, même téléphone) : la fiche du serveur est gardée et le poste prend son identifiant.',
            'products' => 'Ce produit existe déjà au serveur (même nom, catégorie, unité et filière) : la fiche du serveur est gardée et le poste prend son identifiant. La quantité initiale saisie au poste n\'est pas ajoutée au stock ; corrigez un écart par un ajustement d\'inventaire.',
            default => throw new \InvalidArgumentException("Table non fusionnable : {$table}."),
        };
    }

    // ── Traduction des références ───────────────────────────────────────────────────────────────────────────────────

    /**
     * ⚠️⚠️ POINT UNIQUE DE TRADUCTION : remplace, dans les enregistrements d'une table d'envoi, chaque référence à un
     * identifiant de poste fusionné par l'identifiant du serveur ([REFERENCES]). Une table d'envoi absente de
     * [REFERENCES], un enregistrement qui n'est pas un tableau ou une valeur qui n'est pas une chaîne sont rendus tels
     * quels (la validation du traitement les refusera avec son motif habituel).
     */
    public function traduireEnvoi(string $tableEnvoi, mixed $enregistrements): mixed
    {
        $chemins = self::REFERENCES[$tableEnvoi] ?? null;
        if ($chemins === null || ! is_array($enregistrements) || $enregistrements === []) {
            return $enregistrements;
        }

        // Une requête par table référentielle pour tout l'envoi.
        $aChercher = [];
        foreach ($enregistrements as $enregistrement) {
            foreach ($chemins as $chemin => $table) {
                foreach ($this->valeurs($enregistrement, $chemin) as $id) {
                    $aChercher[$table][$id] = true;
                }
            }
        }

        $traductions = [];
        foreach ($aChercher as $table => $ids) {
            $traductions[$table] = CorrespondanceIdentifiant::query()
                ->where('table_referentiel', $table)
                ->whereIn('id_poste', array_keys($ids))
                ->pluck('id_serveur', 'id_poste')
                ->all();
        }

        if (array_filter($traductions) === []) {
            return $enregistrements;
        }

        foreach (array_keys($enregistrements) as $i) {
            foreach ($chemins as $chemin => $table) {
                $enregistrements[$i] = $this->remplacer($enregistrements[$i], explode('.', $chemin), $traductions[$table] ?? []);
            }
        }

        return $enregistrements;
    }

    /** @return array<int, string> les identifiants (chaînes) trouvés au [$chemin] de [$donnee] */
    private function valeurs(mixed $donnee, string $chemin): array
    {
        $courants = [$donnee];
        foreach (explode('.', $chemin) as $segment) {
            $suivants = [];
            foreach ($courants as $c) {
                if (! is_array($c)) {
                    continue;
                }
                if ($segment === '*') {
                    array_push($suivants, ...array_values($c));
                } elseif (array_key_exists($segment, $c)) {
                    $suivants[] = $c[$segment];
                }
            }
            $courants = $suivants;
        }

        return array_values(array_filter($courants, fn ($v) => is_string($v) && $v !== ''));
    }

    /**
     * @param  array<int, string>  $segments
     * @param  array<string, string>  $traductions  id du poste → id du serveur
     */
    private function remplacer(mixed $donnee, array $segments, array $traductions): mixed
    {
        if ($traductions === [] || ! is_array($donnee)) {
            return $donnee;
        }

        $segment = array_shift($segments);
        if ($segment === '*') {
            foreach ($donnee as $k => $v) {
                $donnee[$k] = $this->remplacer($v, $segments, $traductions);
            }

            return $donnee;
        }

        if (! array_key_exists($segment, $donnee)) {
            return $donnee;
        }

        if ($segments === []) {
            $valeur = $donnee[$segment];
            if (is_string($valeur) && isset($traductions[$valeur])) {
                $donnee[$segment] = $traductions[$valeur];
            }

            return $donnee;
        }

        $donnee[$segment] = $this->remplacer($donnee[$segment], $segments, $traductions);

        return $donnee;
    }
}
