<?php

namespace Tests\Feature;

use App\Livewire\RH\Attestations;
use App\Models\AttestationTemplate;
use App\Models\AuditLog;
use App\Models\Employee;
use App\Models\Internship;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\AttestationService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * ATT-2 (27/10/2026) — SIGNATAIRES SELON LA DURÉE, PARAMÉTRABLES, ET PDF FIDÈLE AU MODÈLE.
 *
 * Règle du client : d'un mois à un an, SEUL le promoteur (Directeur Général) signe ; au-delà d'un an, TROIS
 * personnes signent (Examinateur, Président du Jury, Directeur Général). Le seuil et le palier de chaque
 * signataire sont des colonnes du modèle — modifiables au web (Livewire) et au poste (`PUT /api/attestation-templates`).
 */
class AttestationSignatairesTest extends TestCase
{
    use RefreshDatabase;

    private AttestationService $service;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-24 10:00:00');
        $this->service = app(AttestationService::class);
    }

    private function positions(?string $debut, ?string $fin, string $type = 'stagiaire'): array
    {
        return array_column($this->service->signataires($type, $debut, $fin), 'position');
    }

    private function stagiaire(string $debut = '2025-10-15', string $fin = '2026-10-15'): Internship
    {
        return Internship::create([
            'first_name' => 'Sébastien Ichola Alaro', 'last_name' => 'FAGBOHOUN', 'school' => 'Agronomie',
            'start_date' => $debut, 'end_date' => $fin,
            'birth_date' => '2008-01-21', 'birth_place' => 'Kétou', 'civilite' => 'M.',
        ]);
    }

    public function test_jusqu_a_un_an_inclus_le_promoteur_seul_signe(): void
    {
        $this->assertSame([1], $this->positions('2026-09-24', '2026-10-24'), 'un mois : le promoteur seul');
        $this->assertSame([1], $this->positions('2025-10-15', '2026-10-15'), 'un an exactement : palier court');
        $this->assertSame([1], $this->positions('2026-10-20', '2026-10-24'), 'moins d\'un mois : le promoteur seul');
    }

    public function test_au_dela_d_un_an_trois_personnes_signent_dans_l_ordre_du_modele(): void
    {
        $this->assertSame([2, 3, 1], $this->positions('2025-10-15', '2026-10-16'), 'un an et un jour : trois signataires');
        $this->assertSame([2, 3, 1], $this->positions('2024-01-01', '2026-10-24'));
    }

    public function test_sans_date_de_fin_la_duree_court_jusqu_a_aujourd_hui(): void
    {
        $this->assertSame([2, 3, 1], $this->positions('2024-03-01', null), 'embauché depuis plus d\'un an');
        $this->assertSame([1], $this->positions('2026-06-01', null));
        $this->assertSame([1], $this->positions(null, null), 'sans date de début, rien n\'est mesurable : le promoteur');
    }

    public function test_le_seuil_se_parametre(): void
    {
        AttestationTemplate::forType('stagiaire')->update(['seuil_signature_mois' => 6]);

        $this->assertSame([1], $this->positions('2026-04-24', '2026-10-24'), 'six mois pile : court');
        $this->assertSame([2, 3, 1], $this->positions('2026-04-23', '2026-10-24'), 'six mois et un jour : long');
        $this->assertSame([1], $this->positions('2025-10-24', '2026-10-24', 'employe'), 'le seuil est PAR modèle : l\'employé garde 12 mois');
    }

    public function test_qui_signe_chaque_palier_se_parametre(): void
    {
        AttestationTemplate::forType('stagiaire')->update(['sig2_court' => true, 'sig1_long' => false]);

        $this->assertSame([2, 1], $this->positions('2026-09-24', '2026-10-24'), 'l\'Examinateur signe aussi les courtes');
        $this->assertSame([2, 3], $this->positions('2024-01-01', '2026-10-24'), 'le promoteur ne signe plus les longues');
    }

    public function test_un_signataire_sans_intitule_ni_nom_ni_fonction_n_est_pas_imprime(): void
    {
        AttestationTemplate::forType('stagiaire')->update([
            'sig2_titre' => '', 'sig2_nom' => '', 'sig2_fonction' => '',
        ]);

        $this->assertSame([3, 1], $this->positions('2024-01-01', '2026-10-24'));
    }

    public function test_les_modifications_de_l_emetteur_remplacent_le_modele_pour_cette_attestation_seulement(): void
    {
        $liste = $this->service->signataires('stagiaire', '2024-01-01', '2026-10-24', [
            'sig2' => ['nom' => 'KPOHAZOUNDE Jean', 'fonction' => 'Chef ATDA Pôle 5'],
        ]);

        $examinateur = collect($liste)->firstWhere('position', 2);
        $this->assertSame('KPOHAZOUNDE Jean', $examinateur['nom']);
        $this->assertSame('Chef ATDA Pôle 5', $examinateur['fonction']);
        $this->assertSame('Examinateur', $examinateur['titre'], 'l\'intitulé non modifié reste celui du modèle');
        $this->assertSame('SOGNIGBE Gbédjinou Serge Bruno', AttestationTemplate::forType('stagiaire')->sig2_nom, 'le modèle n\'est pas touché');

        // Un signataire que la règle n'appelle pas ne s'imprime pas parce qu'on l'a renseigné.
        $court = $this->service->signataires('stagiaire', '2026-09-24', '2026-10-24', ['sig2' => ['nom' => 'KPOHAZOUNDE Jean']]);
        $this->assertSame([1], array_column($court, 'position'));
    }

    public function test_les_valeurs_par_defaut_sont_celles_du_modele_fourni(): void
    {
        $m = AttestationTemplate::forType('stagiaire');

        $this->assertSame(12, $m->seuil_signature_mois);
        $this->assertSame('Hassimiyou O. OLOUKOUNLE', $m->sig1_nom);
        $this->assertSame('Directeur de la Ferme ÉCOLE OLOUWACHEGOUN', $m->sig1_fonction);
        $this->assertSame('', $m->sig1_titre, 'le Directeur n\'a pas d\'intitulé au-dessus de son nom');
        $this->assertSame('Examinateur', $m->sig2_titre);
        $this->assertSame('Président du Jury', $m->sig3_titre);
        $this->assertTrue($m->sig1_court && $m->sig1_long);
        $this->assertFalse($m->sig2_court || $m->sig3_court);
        $this->assertTrue($m->sig2_long && $m->sig3_long);
    }

    public function test_le_texte_du_modele_fourni_se_compose_avec_ses_balises(): void
    {
        $s = $this->stagiaire();

        $corps = $this->service->corps('stagiaire', $s, '', '2025-10-15', '2026-10-15', 'M.');

        $this->assertSame(
            'Je soussigné OLOUKOUNLE O. Hassimiyou, Directeur Général de la FERME ECOLE OLOUWACHEGOUN, atteste que le nommé '
            .'FAGBOHOUN Sébastien Ichola Alaro, né le 21 janvier 2008 à Kétou, a suivi une formation pratique d\'un (01) an '
            .'sur ladite ferme, du 15 octobre 2025 au 15 octobre 2026 dans les domaines ci-après :',
            $corps,
        );
        $this->assertStringContainsString('**FAGBOHOUN Sébastien Ichola Alaro,**', $this->service->corpsMarque('stagiaire', $s, '', '2025-10-15', '2026-10-15'));

        $feminin = $this->service->corps('stagiaire', $s, '', '2025-10-15', '2026-10-15', 'Mme');
        $this->assertStringContainsString('le nommée FAGBOHOUN', $feminin);
        $this->assertStringContainsString('née le 21 janvier 2008', $feminin);
    }

    public function test_l_appreciation_standard_s_imprime_sauf_si_le_modele_la_supprime(): void
    {
        $s = $this->stagiaire();

        $phrase = $this->service->appreciation('stagiaire', $s, null, '2025-10-15', '2026-10-15', 'M.');
        $this->assertSame('Au cours de sa formation, Monsieur **FAGBOHOUN Sébastien Ichola Alaro** s’est distingué par sa ponctualité, son esprit d’initiative, sa capacité d’adaptation et sa motivation à apprendre.', $phrase);

        $this->assertSame('Très assidu.', $this->service->appreciation('stagiaire', $s, '  Très assidu.  ', null, null));

        AttestationTemplate::forType('stagiaire')->update(['appreciation_imprimee' => false]);
        $this->assertNull($this->service->appreciation('stagiaire', $s, null, null, null));
        $this->assertSame('Très assidu.', $this->service->appreciation('stagiaire', $s, 'Très assidu.', null, null), 'la saisie de l\'émetteur s\'imprime toujours');

        $this->assertNull($this->service->appreciation('employe', Employee::create([
            'first_name' => 'Jean', 'last_name' => 'AGOSSOU', 'position' => 'Animalier', 'hire_date' => '2024-03-01', 'status' => 'actif', 'is_active' => true,
        ]), null, null, null), 'pas de phrase standard pour un employé');
    }

    public function test_deDuree_et_dates_longues(): void
    {
        $this->assertSame(" d'un (01) an", AttestationService::deDuree('2025-10-15', '2026-10-15'));
        $this->assertSame(" d'un (01) an et trois (03) mois", AttestationService::deDuree('2025-07-15', '2026-10-15'));
        $this->assertSame(' de six (06) mois', AttestationService::deDuree('2026-04-15', '2026-10-15'));
        $this->assertSame(' de deux (02) ans', AttestationService::deDuree('2024-10-15', '2026-10-15'));
        $this->assertSame('', AttestationService::deDuree('2026-10-20', '2026-10-24'), 'moins d\'un mois : pas de durée');
        $this->assertSame('15 octobre 2025', AttestationService::dateLongue(Carbon::parse('2025-10-15')));
        $this->assertSame('1 février 2026', AttestationService::dateLongue(Carbon::parse('2026-02-01')));
    }

    public function test_le_gras_du_modele_est_echappe_et_le_nom_de_la_ferme_passe_en_vert(): void
    {
        $html = AttestationService::enHtml('Je <b>soussigné</b> **OLOUKOUNLE** de la **FERME ECOLE OLOUWACHEGOUN,** atteste');

        $this->assertStringContainsString('&lt;b&gt;soussigné&lt;/b&gt;', $html, 'le HTML du texte est échappé');
        $this->assertStringContainsString('<strong>OLOUKOUNLE</strong>', $html);
        $this->assertStringContainsString('<strong class="vert">FERME ECOLE OLOUWACHEGOUN,</strong>', $html);
    }

    public function test_le_pdf_est_produit_pour_chaque_palier_et_journalise(): void
    {
        $s = $this->stagiaire();

        foreach ([['2026-09-24', '2026-10-24'], ['2024-01-01', '2026-10-24']] as [$debut, $fin]) {
            $r = $this->service->generer('stagiaire', $s, 'CDI', $debut, $fin, null, ['maraichage', 'elevage', 'rations', 'gestion'], 'M.');

            $this->assertStringStartsWith('%PDF', $r['octets']);
            $this->assertSame('attestation-fagbohoun-sebastien-ichola-alaro.pdf', $r['fichier']);
        }

        $this->assertSame(2, AuditLog::where('action', 'attestation.generated.stagiaire')->count());
    }

    public function test_le_pdf_d_un_employe_est_produit(): void
    {
        $e = Employee::create(['first_name' => 'Jean', 'last_name' => 'AGOSSOU', 'position' => 'Animalier', 'hire_date' => '2024-03-01', 'status' => 'actif', 'is_active' => true]);

        $r = $this->service->generer('employe', $e, 'CDI', '2024-03-01', null, null);

        $this->assertStringStartsWith('%PDF', $r['octets']);
    }

    public function test_les_ressources_du_pdf_existent(): void
    {
        foreach (['images/logo-ferme.png', 'images/filigrane.png', 'images/decor-floral.png', 'fonts/Caladea-400.ttf', 'fonts/Caladea-700.ttf',
            'fonts/Caladea-400i.ttf', 'fonts/Caladea-700i.ttf', 'fonts/Carlito-400.ttf', 'fonts/Carlito-700.ttf', 'fonts/Carlito-700i.ttf', 'fonts/Bevan-400.ttf'] as $f) {
            $this->assertFileExists(resource_path('attestation/'.$f), $f);
        }

        $this->assertSame(
            md5_file(public_path('assets/images/logo_ferme_ecole_officiel.png')),
            md5_file(resource_path('attestation/images/logo-ferme.png')),
            'le logo de l\'attestation est le logo officiel de la ferme',
        );
    }

    // ───────────── Web : réglage et émission ─────────────

    private ?User $compteRh = null;

    private function admin(): User
    {
        return $this->compteRh ??= $this->creerAdmin();
    }

    private function creerAdmin(): User
    {
        foreach (['view-rh', 'manage-rh'] as $p) {
            Permission::findOrCreate($p, 'web');
        }
        $role = Role::findOrCreate('rh-att', 'web');
        $role->givePermissionTo(['view-rh', 'manage-rh']);

        return User::create(['name' => 'Rh', 'username' => 'rh-att', 'email' => 'rh-att@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true])
            ->assignRole($role);
    }

    public function test_web_le_logo_de_l_apercu_a_une_largeur_en_style_et_les_activites_sont_sur_deux_lignes(): void
    {
        $html = Livewire::actingAs($this->admin())->test(Attestations::class)->html();

        // ⚠️ Largeur portée par `style`, jamais par une classe Tailwind : `w-14` absente du CSS compilé rendait le logo à sa
        // taille naturelle (476 px) et écrasait tout l'aperçu. Une classe de plus dans un Blade ne suffit pas sans `npm run build`.
        $this->assertMatchesRegularExpression('/<img[^>]*alt="Logo de la ferme"[^>]*style="[^"]*width:\s*17%/', $html);
        $this->assertStringNotContainsString('alt="Logo de la ferme" class="w-14', $html);

        foreach (config('attestation.activites') as $ligne) {
            $this->assertStringContainsString(e($ligne), $html, 'chaque ligne d\'activités est imprimée telle quelle, sur sa propre ligne');
        }
    }

    public function test_web_la_regle_de_signature_s_enregistre(): void
    {
        Livewire::actingAs($this->admin())->test(Attestations::class)
            ->set('tab', 'modeles')
            ->set('reglage.stagiaire.seuil_signature_mois', 9)
            ->set('reglage.stagiaire.sig2_nom', 'KPOHAZOUNDE Jean')
            ->set('reglage.stagiaire.sig2_court', true)
            ->set('reglage.stagiaire.appreciation_imprimee', false)
            ->call('saveReglage', 'stagiaire')
            ->assertHasNoErrors();

        $m = AttestationTemplate::forType('stagiaire')->fresh();
        $this->assertSame(9, $m->seuil_signature_mois);
        $this->assertSame('KPOHAZOUNDE Jean', $m->sig2_nom);
        $this->assertTrue($m->sig2_court);
        $this->assertFalse($m->appreciation_imprimee);
        $this->assertSame(12, AttestationTemplate::forType('employe')->seuil_signature_mois, 'l\'autre modèle n\'est pas touché');
        $this->assertDatabaseHas('audit_logs', ['action' => 'attestation_template.updated']);
    }

    public function test_web_un_seuil_invalide_est_refuse_et_rien_n_est_ecrit(): void
    {
        foreach ([0, 121, '', 'abc'] as $mauvais) {
            Livewire::actingAs($this->admin())->test(Attestations::class)
                ->set('reglage.stagiaire.seuil_signature_mois', $mauvais)
                ->call('saveReglage', 'stagiaire')
                ->assertHasErrors(['reglage.stagiaire.seuil_signature_mois']);
        }

        $this->assertSame(12, AttestationTemplate::forType('stagiaire')->seuil_signature_mois);
    }

    public function test_web_sans_le_droit_manage_rh_la_regle_n_est_pas_modifiable(): void
    {
        Permission::findOrCreate('view-rh', 'web');
        $lecteur = User::create(['name' => 'L', 'username' => 'lecteur-att', 'email' => 'l-att@fermeolouwachegoun.com', 'password' => bcrypt('x'), 'is_active' => true]);
        $lecteur->givePermissionTo('view-rh');

        Livewire::actingAs($lecteur)->test(Attestations::class)
            ->set('reglage.stagiaire.seuil_signature_mois', 3)
            ->call('saveReglage', 'stagiaire')
            ->assertForbidden();

        $this->assertSame(12, AttestationTemplate::forType('stagiaire')->seuil_signature_mois);
    }

    public function test_web_le_formulaire_montre_les_signataires_que_la_duree_appelle(): void
    {
        $s = $this->stagiaire('2025-10-15', '2026-10-15');

        $c = Livewire::actingAs($this->admin())->test(Attestations::class)
            ->call('setPersonType', 'stagiaire')
            ->set('personId', $s->id);

        $this->assertSame('court', $c->get('palier'));
        $this->assertSame([1], array_column($c->get('signatairesRequis'), 'position'));

        $c->set('endDate', '2026-12-01');
        $this->assertSame('long', $c->get('palier'));
        $this->assertSame([2, 3, 1], array_column($c->get('signatairesRequis'), 'position'));

        $c->set('sigs.sig2.nom', 'KPOHAZOUNDE Jean');
        $this->assertSame('KPOHAZOUNDE Jean', collect($c->get('signatairesRequis'))->firstWhere('position', 2)['nom']);
    }

    public function test_web_generer_telecharge_le_pdf(): void
    {
        $s = $this->stagiaire();

        Livewire::actingAs($this->admin())->test(Attestations::class)
            ->call('setPersonType', 'stagiaire')
            ->set('personId', $s->id)
            ->call('generateAttestation')
            ->assertFileDownloaded('attestation-fagbohoun-sebastien-ichola-alaro.pdf');
    }
}
