<?php

namespace App\Services;

use App\Models\AdministrativeDocument;
use App\Models\ArchivedDocument;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Correspondence;
use App\Models\Customer;
use App\Models\Expense;
use App\Models\FeedRationStandard;
use App\Models\FeedType;
use App\Models\InternshipAbsence;
use App\Models\LivestockLot;
use App\Models\Product;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\Supplier;
use App\Models\VeterinaryRecord;
use Illuminate\Database\Eloquent\Model;

/**
 * Ticket 14.55 (Sprint 14) — CORBEILLE : voir et restaurer ce qui a été archivé.
 *
 * Le projet impose depuis toujours l'archivage logique (`is_active = false`)
 * plutôt que la suppression. Seize écrans l'appliquaient déjà — mais **rien ne
 * permettait de revoir ni de restaurer** un enregistrement archivé. La règle
 * protégeait la donnée sans jamais la rendre récupérable : en pratique, une
 * archive valait une suppression.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  DÉCISIONS DE SÉCURITÉ — ce qui n'entre PAS dans la corbeille, et pourquoi
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * ⚠️⚠️ **LES ÉCRITURES COMPTABLES EN SONT EXCLUES.** `JournalComptable` les
 * marque bien `is_active = false`, mais une écriture ne se supprime pas : elle
 * se **contre-passe**. La faire réapparaître depuis une corbeille modifierait
 * un grand livre — possiblement d'un exercice clos — sans écriture de
 * contrepartie, et le Bilan cesserait d'être équilibré. Une corbeille qui
 * proposerait de « restaurer » une écriture inviterait à casser la comptabilité
 * en un clic.
 *
 * ⚠️ **LES UTILISATEURS EN SONT EXCLUS.** Un compte désactivé n'est pas
 * supprimé : sa réactivation existe déjà sur l'écran Gestion des Utilisateurs,
 * avec le contrôle de rôle qui va avec. L'exposer ici créerait un second chemin
 * de réactivation de compte — c'est-à-dire une seconde porte d'entrée.
 *
 * ⚠️ **LES VENTES ET LES PAIES N'Y SONT PAS NON PLUS** : elles ne s'archivent
 * pas. Une vente s'annule par un avoir, une paie se corrige par un bulletin
 * rectificatif — les deux laissent une trace, une restauration n'en laisse
 * aucune.
 *
 * ⚠️ **ACCÈS RÉSERVÉ À L'ADMINISTRATEUR.** La corbeille agrège les archives de
 * TOUS les modules : un caissier y verrait des dépenses, un animalier des
 * documents administratifs. Le contrôle est posé sur les méthodes de l'écran,
 * pas seulement sur l'onglet.
 */
class CorbeilleService
{
    /**
     * Registre des modèles restaurables.
     *
     * ⚠️ LISTE EXPLICITE, JAMAIS UNE DÉCOUVERTE AUTOMATIQUE des modèles portant
     * `is_active`. Un balayage automatique embarquerait la première table
     * sensible ajoutée au schéma, sans que personne ne l'ait décidé.
     *
     * @return array<string, array{modele: class-string<Model>, libelle: string, titre: string, module: string}>
     */
    public static function registre(): array
    {
        return [
            'produits' => ['modele' => Product::class, 'libelle' => 'Produit', 'titre' => 'name', 'module' => 'stocks'],
            'fournisseurs' => ['modele' => Supplier::class, 'libelle' => 'Fournisseur', 'titre' => 'name', 'module' => 'achats'],
            'clients' => ['modele' => Customer::class, 'libelle' => 'Client', 'titre' => 'name', 'module' => 'ventes'],
            'depenses' => ['modele' => Expense::class, 'libelle' => 'Dépense', 'titre' => 'label', 'module' => 'achats'],
            'bandes' => ['modele' => LivestockLot::class, 'libelle' => 'Bande', 'titre' => 'code', 'module' => 'elevage'],
            'soins' => ['modele' => VeterinaryRecord::class, 'libelle' => 'Soin vétérinaire', 'titre' => 'action_type', 'module' => 'elevage'],
            'rations' => ['modele' => FeedRationStandard::class, 'libelle' => 'Ration normative', 'titre' => 'stage_label', 'module' => 'elevage'],
            'provendes' => ['modele' => FeedType::class, 'libelle' => 'Type de provende', 'titre' => 'label', 'module' => 'elevage'],
            'prophylaxie' => ['modele' => ProphylaxisScheduleStandard::class, 'libelle' => 'Protocole prophylactique', 'titre' => 'treatment', 'module' => 'elevage'],
            'absences' => ['modele' => InternshipAbsence::class, 'libelle' => 'Absence de stagiaire', 'titre' => 'motif', 'module' => 'rh'],
            'documents' => ['modele' => AdministrativeDocument::class, 'libelle' => 'Document administratif', 'titre' => 'title', 'module' => 'administration'],
            'pieces' => ['modele' => ArchivedDocument::class, 'libelle' => 'Pièce archivée', 'titre' => 'title', 'module' => 'administration'],
            'courriers' => ['modele' => Correspondence::class, 'libelle' => 'Courrier', 'titre' => 'subject', 'module' => 'administration'],
            'comptes' => ['modele' => ChartOfAccount::class, 'libelle' => 'Compte du plan', 'titre' => 'label', 'module' => 'comptabilite'],
        ];
    }

    /**
     * Tout ce qui est archivé, du plus récemment archivé au plus ancien.
     *
     * @return array<int, array<string, mixed>>
     */
    public function elements(?string $typeFiltre = null): array
    {
        $elements = [];

        foreach (static::registre() as $cle => $definition) {
            if ($typeFiltre && $typeFiltre !== $cle) {
                continue;
            }

            /** @var class-string<Model> $modele */
            $modele = $definition['modele'];

            $lignes = $modele::query()
                ->where('is_active', false)
                ->orderByDesc('updated_at')
                ->get();

            foreach ($lignes as $ligne) {
                $elements[] = [
                    'type' => $cle,
                    'libelle_type' => $definition['libelle'],
                    'module' => $definition['module'],
                    'id' => $ligne->getKey(),
                    // Titre lisible : un identifiant UUID seul ne permet pas de
                    // décider si l'on veut restaurer.
                    'titre' => (string) ($ligne->{$definition['titre']} ?? '—'),
                    'archive_le' => $ligne->updated_at,
                ];
            }
        }

        usort($elements, function ($a, $b) {
            return ($b['archive_le']?->timestamp ?? 0) <=> ($a['archive_le']?->timestamp ?? 0);
        });

        return $elements;
    }

    public function compte(): int
    {
        return count($this->elements());
    }

    /**
     * Restaure un élément archivé.
     *
     * ⚠️ **LE TYPE EST VÉRIFIÉ CONTRE LE REGISTRE**, jamais interprété comme un
     * nom de classe. Accepter une classe fournie par l'appelant permettrait de
     * réactiver n'importe quel modèle du projet — y compris ceux volontairement
     * exclus ci-dessus.
     *
     * @return bool  `false` si le type est inconnu ou l'élément introuvable
     */
    public function restaurer(string $type, string $id): bool
    {
        $definition = static::registre()[$type] ?? null;

        if ($definition === null) {
            return false;
        }

        /** @var class-string<Model> $modele */
        $modele = $definition['modele'];
        $ligne = $modele::query()->where('is_active', false)->find($id);

        if ($ligne === null) {
            return false;
        }

        $ligne->update(['is_active' => true]);

        // La restauration est un acte administratif : elle se journalise, comme
        // l'archivage. Sans trace, personne ne peut expliquer la réapparition
        // d'un enregistrement.
        AuditLog::record('corbeille.restored', $definition['module']);

        return true;
    }
}
