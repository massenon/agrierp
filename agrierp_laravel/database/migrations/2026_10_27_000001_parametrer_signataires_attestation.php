<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ATT-2 (27/10/2026) — SIGNATAIRES SELON LA DURÉE, PARAMÉTRABLES.
 *
 * Demande du client : d'un mois à un an, SEUL le promoteur (le Directeur Général) signe ;
 * au-delà d'un an, TROIS personnes signent (Examinateur, Président du Jury, Directeur Général).
 * « Il faut paramétrer » : le seuil et, pour chaque signataire, les paliers où il signe sont des
 * colonnes du modèle, modifiables au web et au poste (jamais codés en dur).
 *
 * - `seuil_signature_mois`  : jusqu'à N mois INCLUS, palier « court » ; au-delà, palier « long ».
 * - `sigN_court` / `sigN_long` : le signataire N signe-t-il les attestations du palier court / long ?
 * - `sigN_fonction`          : fonction affichée sous le nom (modèle fourni : « Chef Cellule Communale de l'ATDA Pôle 6(Plateau) »).
 * - `appreciation_text`      : phrase d'appréciation imprimée par défaut (`null` = phrase standard du type).
 * - `appreciation_imprimee`  : imprimer cette phrase par défaut ? (non : seule l'appréciation saisie à l'émission s'imprime).
 *
 * Les intitulés et noms qui valaient encore les anciennes valeurs par défaut sont alignés sur le
 * modèle fourni par le client ; un texte modifié à la main n'est jamais touché.
 */
return new class extends Migration
{
    private const ANCIEN_CORPS_STAGIAIRE = 'Je soussigné OLOUKOUNLE O. Hassimiyou, Directeur Général de la FERME ECOLE OLOUWACHEGOUN, atteste que le nommé(e) [NOM], né(e) le [DATE_NAISSANCE] à [LIEU_NAISSANCE], a suivi une formation pratique sur ladite ferme, du [DATE_DEBUT] au [DATE_FIN] dans les domaines ci-après :';

    private const NOUVEAU_CORPS_STAGIAIRE = 'Je soussigné **OLOUKOUNLE O. Hassimiyou**, Directeur Général de la **FERME ECOLE OLOUWACHEGOUN,** atteste que le nommé[ACCORD_E] **[NOM],** né[ACCORD_E] le [DATE_NAISSANCE_LONGUE] à [LIEU_NAISSANCE], a suivi une formation pratique[DE_DUREE] sur ladite ferme, du **[DATE_DEBUT_LONGUE] au [DATE_FIN_LONGUE]** dans les domaines ci-après :';

    public function up(): void
    {
        Schema::table('attestation_templates', function (Blueprint $table) {
            $table->unsignedSmallInteger('seuil_signature_mois')->default(12);
            $table->text('sig1_fonction')->nullable();
            $table->text('sig2_fonction')->nullable();
            $table->text('sig3_fonction')->nullable();
            $table->boolean('sig1_court')->default(true);
            $table->boolean('sig2_court')->default(false);
            $table->boolean('sig3_court')->default(false);
            $table->boolean('sig1_long')->default(true);
            $table->boolean('sig2_long')->default(true);
            $table->boolean('sig3_long')->default(true);
            $table->text('appreciation_text')->nullable();
            $table->boolean('appreciation_imprimee')->default(true);
        });

        DB::table('attestation_templates')->where('sig1_titre', 'Le Directeur Général')->update(['sig1_titre' => '']);
        DB::table('attestation_templates')->where('sig2_titre', "L'Examinateur")->update(['sig2_titre' => 'Examinateur']);
        DB::table('attestation_templates')->where('sig3_titre', 'Le Président du Jury')->update(['sig3_titre' => 'Président du Jury']);
        DB::table('attestation_templates')->where('sig1_nom', 'M. Olouchègoun')->update(['sig1_nom' => 'Hassimiyou O. OLOUKOUNLE']);

        DB::table('attestation_templates')->update([
            'sig1_fonction' => 'Directeur de la Ferme ÉCOLE OLOUWACHEGOUN',
        ]);
        DB::table('attestation_templates')->whereNull('sig2_nom')->update([
            'sig2_nom' => 'SOGNIGBE Gbédjinou Serge Bruno',
            'sig2_fonction' => "Chef Cellule Communale de l'ATDA Pôle 6(Plateau)",
        ]);
        DB::table('attestation_templates')->whereNull('sig3_nom')->update([
            'sig3_nom' => 'Elisée Kocou HOUNKPONOU',
            'sig3_fonction' => 'Président de la Fédération Nationale des Coopératives de Cuniculteurs Modernes et Professionnel du Bénin FN-CCPB',
        ]);

        // Le texte du modèle « stagiaire » encore à sa valeur d'origine passe au texte du modèle fourni.
        DB::table('attestation_templates')
            ->where('type', 'stagiaire')
            ->where('body_text', self::ANCIEN_CORPS_STAGIAIRE)
            ->update(['body_text' => self::NOUVEAU_CORPS_STAGIAIRE]);
    }

    public function down(): void
    {
        Schema::table('attestation_templates', function (Blueprint $table) {
            $table->dropColumn([
                'seuil_signature_mois', 'sig1_fonction', 'sig2_fonction', 'sig3_fonction',
                'sig1_court', 'sig2_court', 'sig3_court', 'sig1_long', 'sig2_long', 'sig3_long',
                'appreciation_text', 'appreciation_imprimee',
            ]);
        });
    }
};
