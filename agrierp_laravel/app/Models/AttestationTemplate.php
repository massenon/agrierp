<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class AttestationTemplate extends Model
{
    use HasUuids;

    /**
     * Texte du modèle « stagiaire » fourni par le client (attestation de formation du 24/10/2026).
     * `**gras**` : mis en gras au PDF (le nom de la ferme y passe en vert) ; l'aperçu l'affiche sans les astérisques.
     */
    public const CORPS_STAGIAIRE = 'Je soussigné **OLOUKOUNLE O. Hassimiyou**, Directeur Général de la **FERME ECOLE OLOUWACHEGOUN,** atteste que le nommé[ACCORD_E] **[NOM],** né[ACCORD_E] le [DATE_NAISSANCE_LONGUE] à [LIEU_NAISSANCE], a suivi une formation pratique[DE_DUREE] sur ladite ferme, du **[DATE_DEBUT_LONGUE] au [DATE_FIN_LONGUE]** dans les domaines ci-après :';

    public const CORPS_EMPLOYE = 'Nous soussigné, Ferme École OLOUWACHEGOUN, attestons que [NOM], est employé(e) au sein de notre structure en qualité de [POSTE] sous contrat [CONTRAT] du [DATE_DEBUT] au [DATE_FIN].';

    /** Phrase d’appréciation imprimée par défaut (modèle fourni) ; `appreciation_imprimee` faux = aucune. */
    public const APPRECIATION_STAGIAIRE = "Au cours de sa formation, [CIVILITE_LONGUE] **[NOM]** s’est distingué[ACCORD_E] par sa ponctualité, son esprit d’initiative, sa capacité d’adaptation et sa motivation à apprendre.";

    protected $fillable = [
        'type', 'body_text', 'format', 'show_watermark', 'show_header', 'show_signature', 'show_stamp',
        'numero_sequence',
        'sig1_titre', 'sig1_nom', 'sig1_fonction',
        'sig2_titre', 'sig2_nom', 'sig2_fonction',
        'sig3_titre', 'sig3_nom', 'sig3_fonction',
        // ATT-2 : règle de signature selon la durée (paramétrable).
        'seuil_signature_mois',
        'sig1_court', 'sig2_court', 'sig3_court',
        'sig1_long', 'sig2_long', 'sig3_long',
        'appreciation_text', 'appreciation_imprimee',
    ];

    protected function casts(): array
    {
        return [
            'show_watermark' => 'boolean',
            'show_header' => 'boolean',
            'show_signature' => 'boolean',
            'show_stamp' => 'boolean',
            'seuil_signature_mois' => 'integer',
            'sig1_court' => 'boolean',
            'sig2_court' => 'boolean',
            'sig3_court' => 'boolean',
            'sig1_long' => 'boolean',
            'sig2_long' => 'boolean',
            'sig3_long' => 'boolean',
            'appreciation_imprimee' => 'boolean',
        ];
    }

    /**
     * Le modèle tel que le poste le reçoit au tirage : texte, règle de signature (seuil, qui signe chaque palier),
     * signataires et appréciation. Un seul point de passage : ajouter un champ ici l'ajoute au tirage.
     *
     * @return array<string, mixed>
     */
    public function pourLePoste(): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type,
            'body_text' => $this->body_text,
            'seuil_signature_mois' => (int) $this->seuil_signature_mois,
            'appreciation_text' => $this->appreciation_text,
            'appreciation_imprimee' => (bool) $this->appreciation_imprimee,
            'sig1_titre' => $this->sig1_titre, 'sig1_nom' => $this->sig1_nom, 'sig1_fonction' => $this->sig1_fonction,
            'sig2_titre' => $this->sig2_titre, 'sig2_nom' => $this->sig2_nom, 'sig2_fonction' => $this->sig2_fonction,
            'sig3_titre' => $this->sig3_titre, 'sig3_nom' => $this->sig3_nom, 'sig3_fonction' => $this->sig3_fonction,
            'sig1_court' => (bool) $this->sig1_court, 'sig2_court' => (bool) $this->sig2_court, 'sig3_court' => (bool) $this->sig3_court,
            'sig1_long' => (bool) $this->sig1_long, 'sig2_long' => (bool) $this->sig2_long, 'sig3_long' => (bool) $this->sig3_long,
        ];
    }

    public static function forType(string $type): self
    {
        $corps = [
            'employe' => self::CORPS_EMPLOYE,
            'stagiaire' => self::CORPS_STAGIAIRE,
        ];

        return static::firstOrCreate(['type' => $type], [
            'body_text' => $corps[$type] ?? '',
            // Signataires du modèle fourni. Positions : 1 = Directeur Général (le promoteur),
            // 2 = Examinateur, 3 = Président du Jury.
            'sig1_titre' => '',
            'sig1_nom' => 'Hassimiyou O. OLOUKOUNLE',
            'sig1_fonction' => 'Directeur de la Ferme ÉCOLE OLOUWACHEGOUN',
            'sig2_titre' => 'Examinateur',
            'sig2_nom' => 'SOGNIGBE Gbédjinou Serge Bruno',
            'sig2_fonction' => "Chef Cellule Communale de l'ATDA Pôle 6(Plateau)",
            'sig3_titre' => 'Président du Jury',
            'sig3_nom' => 'Elisée Kocou HOUNKPONOU',
            'sig3_fonction' => 'Président de la Fédération Nationale des Coopératives de Cuniculteurs Modernes et Professionnel du Bénin FN-CCPB',
            // Règle de signature (ATT-2) : jusqu'à 12 mois, le promoteur seul ; au-delà, les trois.
            // ⚠️ Les valeurs sont passées ici ET portées par la migration : une ligne tout juste créée n'a pas
            // relu les défauts de la base, et un `null` y serait lu comme « personne ne signe ».
            'seuil_signature_mois' => 12,
            'sig1_court' => true, 'sig2_court' => false, 'sig3_court' => false,
            'sig1_long' => true, 'sig2_long' => true, 'sig3_long' => true,
            'appreciation_imprimee' => true,
        ]);
    }
}
