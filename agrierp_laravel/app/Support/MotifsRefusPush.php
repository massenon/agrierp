<?php

namespace App\Support;

use Illuminate\Validation\ValidationException;

/**
 * Ticket 15.33 — MOTIFS DE REFUS DU PUSH EN FRANÇAIS.
 *
 * Le dépôt n'a pas de dossier `lang/` : avec `APP_LOCALE=fr`, Laravel retombe sur ses messages
 * ANGLAIS (« The sold at field must be a date before or equal to now. ») et, pour plusieurs
 * erreurs, ajoute « (and N more errors) ». Ces textes remontent au poste dans
 * `rejected[].reason`, puis au caissier.
 *
 * ⚠️ NE CHANGE AUCUNE RÈGLE : ce sont uniquement les TEXTES passés en 3e argument de
 * `validator()` (comme `ProductCatalogService::messages()`), et la façon de composer un motif
 * à partir d'une `ValidationException`. Le contrat de `/api/sync/*` (clés, forme) est intact.
 */
class MotifsRefusPush
{
    /**
     * Messages par RÈGLE (valables pour tous les champs) et par champ.
     *
     * @return array<string, string>
     */
    public static function messages(): array
    {
        return [
            'required' => 'Le champ :attribute est obligatoire.',
            'required_without' => 'Le champ :attribute est obligatoire (ou renseignez :values).',
            'uuid' => 'Le champ :attribute doit être un identifiant (UUID) valide.',
            'unique' => 'La valeur du champ :attribute existe déjà.',
            'exists' => 'La valeur du champ :attribute ne correspond à aucun enregistrement connu du serveur.',
            'string' => 'Le champ :attribute doit être un texte.',
            'numeric' => 'Le champ :attribute doit être un nombre.',
            'integer' => 'Le champ :attribute doit être un nombre entier.',
            'boolean' => 'Le champ :attribute doit être vrai ou faux.',
            'array' => 'Le champ :attribute doit être une liste.',
            'email' => 'Le champ :attribute doit être une adresse courriel valide.',
            'date' => 'Le champ :attribute doit être une date valide.',
            'date_format' => 'Le champ :attribute doit être une heure au format HH:MM ou HH:MM:SS.',
            'in' => 'La valeur du champ :attribute n\'est pas autorisée.',
            'min' => 'Le champ :attribute est inférieur au minimum autorisé (:min).',
            'max' => 'Le champ :attribute dépasse le maximum autorisé (:max).',
            'gt' => 'Le champ :attribute doit être strictement supérieur à :value.',
            'gte' => 'Le champ :attribute doit être supérieur ou égal à :value.',
            'before_or_equal' => 'La date du champ :attribute ne peut pas être postérieure à aujourd\'hui.',
            'after_or_equal' => 'La date du champ :attribute ne peut pas être antérieure à la date de départ.',
            // Ticket 15.33 — D1 : la date future d'une vente est jugée par `VerifySaleDateAction` (15.30)
            // ; cette règle de forme est conservée
            // (jamais retirée) et dit la même chose que l'action, en français. La date est rendue telle que
            // le poste l'a envoyée (`:input`) : la règle ne sait pas la mettre au format jj/mm/aaaa.
            'sold_at.before_or_equal' => 'Vente refusée : la date de la vente (:input) est dans le futur.',
        ];
    }

    /**
     * Libellés français des champs les plus fréquents (sinon « sold_at » devient « sold at »).
     *
     * @return array<string, string>
     */
    public static function attributs(): array
    {
        return [
            'id' => 'identifiant', 'sold_at' => 'date de la vente', 'payment_mode' => 'mode de règlement',
            'total' => 'total', 'subtotal' => 'sous-total', 'discount' => 'remise', 'lines' => 'lignes',
            'lines.*.product_id' => 'produit de la ligne', 'lines.*.lot_id' => 'bande de la ligne',
            'lines.*.qty' => 'quantité de la ligne', 'lines.*.unit_price' => 'prix unitaire de la ligne',
            'lines.*.manual_total_amount' => 'montant de la ligne',
            'lot_id' => 'bande', 'entry_date' => 'date de la fiche', 'saillie_date' => 'date de saillie',
            'mother_ref' => 'référence de la mère', 'sire_ref' => 'référence du mâle',
            'supplier_id' => 'fournisseur', 'customer_id' => 'client', 'treasury_account_id' => 'compte de trésorerie',
            'amount' => 'montant', 'amount_paid' => 'montant payé', 'purchase_date' => 'date de l\'achat',
            'purchase_id' => 'achat', 'reason' => 'motif', 'return_date' => 'date du retour',
            'refund_date' => 'date du remboursement', 'payment_date' => 'date du règlement',
            'advance_date' => 'date de l\'avance', 'imputation_date' => 'date de l\'imputation',
            'customer_advance_id' => 'avance client', 'receivable_id' => 'créance', 'sale_id' => 'vente',
            'expense_date' => 'date de la dépense', 'label' => 'libellé', 'category' => 'catégorie',
            'employee_id' => 'employé', 'attendance_date' => 'date de pointage', 'check_in' => 'heure d\'arrivée',
            'check_out' => 'heure de départ', 'status' => 'statut', 'record_date' => 'date du soin',
            'action_type' => 'type de soin', 'withdrawal_days' => 'jours de retrait',
            'product_id' => 'produit', 'type' => 'type', 'quantity' => 'quantité', 'reference_type' => 'type de référence',
            'client_ref' => 'référence du poste', 'movement_date' => 'date du mouvement', 'name' => 'nom', 'phone' => 'téléphone', 'email' => 'courriel',
            'subject' => 'objet', 'party' => 'correspondant', 'mail_date' => 'date du courrier',
            'title' => 'titre', 'archived_date' => 'date d\'archivage', 'expiry_date' => 'date d\'expiration',
            'beneficiary' => 'bénéficiaire', 'doc_date' => 'date du document', 'is_active' => 'actif',
            'achat' => 'achats', 'ne' => 'naissances', 'mort' => 'mortalité', 'vente' => 'ventes', 'don' => 'dons',
            'ponte_total' => 'ponte totale', 'ponte_casses' => 'œufs cassés', 'feed_qty_kg' => 'aliment (kg)',
            'weight_sample_avg_g' => 'poids moyen (g)', 'motif' => 'motif',
            // Ticket 15.40 — ventilation par catégorie. Emplacements génériques (14.11/14.12), glossaire du 17/10/2026
            // (F0.99) : la 2e catégorie est Sous-mères (lapins) ou Porcelet (porcs), la 3e Jeune ou Porc Marchand.
            'mort_repro' => 'morts reproducteurs', 'mort_sevre' => 'morts sous-mères ou porcelets',
            'mort_jeune' => 'morts jeunes lapins ou porcs marchands',
            'don_repro' => 'dons reproducteurs', 'don_sevre' => 'dons sous-mères ou porcelets',
            'don_jeune' => 'dons jeunes lapins ou porcs marchands',
            'passage_sevre_jeune' => 'passage de stade',
            'cat_depart_repro' => 'effectif de départ reproducteurs', 'cat_depart_sevre' => 'effectif de départ sous-mères ou porcelets',
            'cat_depart_jeune' => 'effectif de départ jeunes lapins ou porcs marchands',
        ];
    }

    /**
     * Motif de rejet : TOUTES les erreurs, en une phrase. `getMessage()` n'en rapporte qu'une
     * et ajoute « (and N more errors) » en anglais.
     */
    public static function motif(ValidationException $e): string
    {
        return collect($e->errors())->flatten()->implode(' ');
    }

    /**
     * Ticket 15.34 — motif de refus d'une fiche élevage « réduite » (`id`, `lot_id`, `entry_date`
     * seulement) dont l'`id` est inconnu du serveur. Le poste renvoie cette forme réduite pour ne
     * pas écraser les corrections faites sur le web ; si la fiche a disparu côté serveur, l'écrire
     * créerait une fiche VIDE « acceptée », et la vente du même envoi ne serait pas comptée.
     */
    public static function ficheReduiteInconnue(): string
    {
        return 'Fiche refusée : elle ne porte aucune donnée de saisie et son identifiant est inconnu du serveur '
            .'(fiche supprimée ou base restaurée). Ressaisissez la fiche du jour.';
    }

    // ====================================================================== Ticket 15.40 — ventilation par catégorie

    /** Les trois catégories d'une ventilation (morts ou dons) doivent être renseignées ensemble. */
    public static function ventilationIncomplete(string $libelle): string
    {
        return "Ventilation incomplète : les trois catégories des {$libelle} (reproducteurs, jeunes ou porcelets, "
            .'lapins de chair ou porcs marchands) doivent être renseignées ensemble (0 si la catégorie est vide).';
    }

    /** Le total de la fiche doit égaler la somme de sa ventilation. */
    public static function ventilationIncoherente(string $libelle, int $total, int $somme): string
    {
        return "Ventilation incohérente : les {$libelle} de la fiche ({$total}) ne correspondent pas à la somme "
            ."des trois catégories ({$somme}).";
    }

    /** D7 : un ancien poste envoie des morts/dons non ventilés sur une bande qui suit son effectif par catégorie. */
    public static function ficheNonVentilee(string $libelle): string
    {
        return "Fiche refusée : cette bande suit son effectif par catégorie et les {$libelle} de la fiche ne sont pas "
            .'ventilés par catégorie. Votre poste est un ancien poste : une mise à jour du poste est nécessaire '
            .'avant de pouvoir saisir cette fiche.';
    }

    /** D4 : l'effectif de départ d'une bande ne se fixe qu'une fois. */
    public static function departDejaFixe(string $dateFr): string
    {
        return "Effectif de départ refusé : effectif de départ déjà fixé le {$dateFr} pour cette bande.";
    }

    /** L'effectif par catégorie n'est suivi que pour les lapins et les porcs. */
    public static function departEspeceNonPrise(): string
    {
        return "Effectif de départ refusé : l'effectif par catégorie n'est suivi que pour les lapins et les porcs.";
    }

    /** Ticket S1 : un compte de vente envoie une fiche qui contient des saisies d'élevage. */
    public static function ficheEleveurRequise(): string
    {
        return "Fiche refusée : elle contient des saisies d'élevage (morts, naissances, achats, alimentation…) que "
            .'votre rôle ne permet pas d\'envoyer. Elle reste sur le poste : un compte animalier doit la synchroniser.';
    }

    /**
     * Ticket 15.50 : le poste n'a pas encore tiré la réinitialisation des données — ses saisies en attente datent
     * d'une base effacée depuis.
     */
    public static function reinitialisationNonVue(\DateTimeInterface $le): string
    {
        return 'Envoi refusé : les données du serveur ont été réinitialisées le '
            .$le->format('d/m/Y à H:i').'. Mettez à jour le poste puis synchronisez : il effacera ses données '
            .'antérieures avant tout nouvel envoi.';
    }

    /**
     * Ticket S-T2 (méthode TATACORA) : le `device_id` envoyé n'est pas le poste auquel le jeton a été délivré — un
     * poste ne signe pas au nom d'un autre.
     */
    public static function posteDifferentDuJeton(string $envoye, string $jeton): string
    {
        return 'Synchronisation refusée : ce jeton a été délivré au poste « '.$jeton.' », mais la requête se '
            .'présente comme le poste « '.$envoye.' ». Un poste ne peut pas synchroniser au nom d\'un autre : '
            .'reconnectez-vous depuis ce poste. Les saisies en attente restent sur le poste.';
    }

    /** Ticket S1 : l'utilisateur connecté au poste n'a pas le droit d'écrire cette table. */
    public static function roleInsuffisant(string $table): string
    {
        $objet = [
            'livestock_daily_entries' => 'saisir une fiche d\'élevage',
            'livestock_transfers' => 'transférer des sujets entre bandes',
            'livestock_reproduction_events' => 'enregistrer un événement de reproduction',
            'veterinary_records' => 'enregistrer un soin vétérinaire',
            'infirmary_records' => 'enregistrer une entrée d\'infirmerie',
            'veterinary_calendar_events' => 'planifier une intervention vétérinaire',
            'feed_ration_standards' => 'modifier le barème de rationnement',
            'prophylaxis_schedule_standards' => 'modifier le calendrier de prophylaxie',
            'feed_types' => 'modifier les types de provende',
            'elevage_numbering' => 'modifier la numérotation des bandes et sujets',
            'company_settings' => 'modifier le délai de rappel des soins',
            'expenses' => 'enregistrer une dépense',
            'purchases' => 'enregistrer un achat',
            'attendance_records' => 'enregistrer un pointage',
            'sales' => 'enregistrer une vente',
            'stock_adjustments' => 'ajuster le stock',
        ][$table] ?? 'écrire ces données';

        return "Refusé : votre rôle ne permet pas de {$objet}. Connectez-vous au poste avec un compte autorisé.";
    }
}
