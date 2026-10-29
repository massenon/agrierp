<?php

namespace Tests\Feature;

use App\Livewire\Auth\Login;
use App\Livewire\Elevage\RegistreReproducteurs;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\ImporterPlanSyscohadaService;
use App\Support\MessagesErreurFr;
use App\Support\MotifsRefusPush;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Validator;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U5 (décision D-U5 du 19/10/2026) — TOUS LES MESSAGES D'ERREUR DU WEB EN FRANÇAIS.
 *
 * Le dépôt n'avait pas de dossier `lang/`, et `config/app.php` retombait sur `en` : chaque
 * formulaire qui ne passait pas ses propres messages à `validate()` affichait « The identifier
 * field is required. », les pages d'erreur étaient celles de Laravel (« 404 | Not Found »), et
 * l'API renvoyait « Unauthenticated. ».
 *
 * Ces tests passent par de VRAIS écrans (composants Livewire, routes web et API) et vérifient à la
 * fois la présence du français et l'absence des phrases anglaises par défaut du framework.
 */
class MessagesErreurFrancaisTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Fragments des messages anglais par défaut de Laravel. Aucun ne doit plus sortir d'un écran.
     */
    private const ANGLAIS = [
        'field is required', 'field must be', 'must be a valid', 'has already been taken',
        'The selected', 'The given data was invalid', 'more error', 'These credentials',
        'Too many login attempts', 'This action is unauthorized', 'Unauthenticated',
        'Not Found', 'Forbidden', 'Page Expired', 'Server Error', 'Too Many',
    ];

    private function assertSansAnglais(string $contenu, string $ou): void
    {
        foreach (self::ANGLAIS as $fragment) {
            $this->assertStringNotContainsString($fragment, $contenu, "Message anglais « {$fragment} » dans {$ou}.");
        }
    }

    private function animalier(): User
    {
        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('animalier', 'web');
        $role->givePermissionTo(['view-elevage', 'manage-elevage']);

        $user = User::create([
            'name' => 'Animalier', 'username' => 'elevage', 'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $user->assignRole($role);

        return $user;
    }

    // ================================================================ configuration

    public function test_la_langue_par_defaut_est_le_francais_meme_sans_env(): void
    {
        $this->assertSame('fr', app()->getLocale());

        // Le DÉFAUT du fichier, pas seulement la valeur du `.env` : une installation sans
        // `APP_LOCALE` ne doit plus retomber sur l'anglais.
        $config = file_get_contents(config_path('app.php'));
        $this->assertStringContainsString("env('APP_LOCALE', 'fr')", $config);
        $this->assertStringContainsString("env('APP_FALLBACK_LOCALE', 'fr')", $config);
        $this->assertStringContainsString("env('APP_FAKER_LOCALE', 'fr_FR')", $config);
        $this->assertStringContainsString('APP_LOCALE=fr', file_get_contents(base_path('.env.example')));
    }

    /**
     * Chaque clé des fichiers anglais du framework INSTALLÉ existe en français : une règle ajoutée par
     * une future version de Laravel sortirait sinon en anglais, sans que rien ne le signale.
     */
    public function test_chaque_message_du_framework_a_sa_traduction_francaise(): void
    {
        $dossierAnglais = base_path('vendor/laravel/framework/src/Illuminate/Translation/lang/en');

        foreach (['validation', 'auth', 'passwords', 'pagination'] as $fichier) {
            $anglais = require "{$dossierAnglais}/{$fichier}.php";
            $francais = require lang_path("fr/{$fichier}.php");

            foreach (array_keys(\Illuminate\Support\Arr::dot($anglais)) as $cle) {
                if (str_starts_with($cle, 'custom.')) {
                    continue; // exemple du squelette (« attribute-name.rule-name »), pas une règle
                }
                $this->assertTrue(\Illuminate\Support\Arr::has($francais, $cle), "lang/fr/{$fichier}.php : clé « {$cle} » absente.");
                $texte = \Illuminate\Support\Arr::get($francais, $cle);
                if (is_string($texte)) {
                    $this->assertSansAnglais($texte, "lang/fr/{$fichier}.php ({$cle})");
                }
            }
        }

        $this->assertSame('Le champ nom est obligatoire.', __('validation.required', ['attribute' => 'nom']));
        $this->assertSame('Le champ quantité doit être au moins égal à 1.', __('validation.min.numeric', ['attribute' => 'quantité', 'min' => 1]));
        $this->assertSame('Le champ mot de passe doit contenir au moins un symbole.', __('validation.password.symbols', ['attribute' => 'mot de passe']));
    }

    /**
     * Chaque champ validé par un écran du web a un libellé français : sinon Laravel fabrique le
     * libellé à partir du nom ANGLAIS de la propriété (« Le champ new supplier name est
     * obligatoire. »). Un nouveau champ sans libellé fait échouer ce test.
     */
    public function test_chaque_champ_valide_par_le_web_a_un_libelle_francais(): void
    {
        $libelles = \Illuminate\Support\Arr::dot(__('validation.attributes'));
        $sources = array_merge(
            glob(app_path('Livewire/*/*.php')) ?: [],
            glob(app_path('Livewire/*.php')) ?: [],
            glob(app_path('Livewire/*/*/*.php')) ?: [],
            glob(app_path('Http/Controllers/*.php')) ?: [],
            glob(app_path('Http/Controllers/*/*.php')) ?: [],
        );
        $this->assertNotEmpty($sources);

        $manquants = [];
        foreach ($sources as $fichier) {
            $code = file_get_contents($fichier);
            preg_match_all('/(?:validate|Validator::make)\(\s*(?:\$[a-z]+,\s*)?\[(.*?)\n\s*\]/s', $code, $blocs);
            foreach ($blocs[1] as $bloc) {
                preg_match_all('/^\s*\'([A-Za-z0-9_.*]+)\'\s*=>\s*(?:\[|\'|")/m', $bloc, $cles);
                foreach ($cles[1] as $cle) {
                    if (! isset($libelles[$cle])) {
                        $manquants[] = basename($fichier).' : '.$cle;
                    }
                }
            }
        }

        $this->assertSame([], array_values(array_unique($manquants)), 'Champs sans libellé français dans lang/fr/validation.php (attributes).');
    }

    /** « :date » d'une règle de date : « aujourd'hui » et jj/mm/aaaa, plus « today » ni ISO. */
    public function test_la_date_de_comparaison_est_ecrite_en_francais(): void
    {
        $v = Validator::make(
            ['a' => '2999-01-01', 'b' => '2020-01-01', 'debut' => '2026-05-01', 'fin' => '2026-04-01'],
            ['a' => 'before_or_equal:today', 'b' => 'after:2026-10-01', 'fin' => 'after_or_equal:debut'],
        );
        $erreurs = $v->errors();

        $this->assertSame("Le champ a doit être une date antérieure ou égale à aujourd'hui.", $erreurs->first('a'));
        $this->assertSame('Le champ b doit être une date postérieure à 01/10/2026.', $erreurs->first('b'));
        $this->assertSame('Le champ fin doit être une date postérieure ou égale à debut.', $erreurs->first('fin'));
    }

    // ================================================================ formulaires réels

    /** Une validation ratée d'un vrai formulaire Livewire : message français, à l'écran compris. */
    public function test_un_formulaire_livewire_rate_affiche_ses_erreurs_en_francais(): void
    {
        $this->actingAs($this->animalier());
        $espece = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $page = Livewire::test(RegistreReproducteurs::class)
            ->set('identifier', '')
            ->set('species_id', $espece->id)
            ->set('sex', 'X')
            ->set('entry_date', '2999-01-01')
            ->set('breed', str_repeat('a', 101))
            ->call('saveAnimal')
            ->assertHasErrors(['identifier', 'sex', 'entry_date', 'breed']);

        $erreurs = $page->errors();
        $this->assertSame('Le champ identifiant est obligatoire.', $erreurs->first('identifier'));
        // Le nom ANGLAIS de la propriété (« sex », « breed ») ne sort plus : `validation.attributes`.
        $this->assertSame("La valeur sélectionnée pour le champ sexe n'est pas valide.", $erreurs->first('sex'));
        $this->assertSame("Le champ date d'entrée doit être une date antérieure ou égale à aujourd'hui.", $erreurs->first('entry_date'));
        $this->assertSame('Le champ race ne doit pas dépasser 100 caractères.', $erreurs->first('breed'));

        foreach ($erreurs->all() as $message) {
            $this->assertSansAnglais($message, 'Registre des reproducteurs');
        }
        $this->assertSansAnglais($page->html(), 'le rendu du Registre des reproducteurs');
    }

    /** Échec de connexion web, adresse de réinitialisation invalide et verrouillage : en français. */
    public function test_la_connexion_echouee_et_le_verrouillage_sont_en_francais(): void
    {
        RateLimiter::clear('elevage|127.0.0.1');
        $this->animalier();

        $tentative = fn () => Livewire::test(Login::class)
            ->set('identifiant', 'elevage')
            ->set('password', 'mauvais-mot-de-passe')
            ->call('submit');

        $echec = $tentative();
        $this->assertSame('Identifiants incorrects.', $echec->errors()->first('identifiant'));

        $vide = Livewire::test(Login::class)->call('submit');
        $this->assertSame("Le nom d'utilisateur ou l'adresse e-mail est obligatoire.", $vide->errors()->first('identifiant'));
        $this->assertSame('Le mot de passe est obligatoire.', $vide->errors()->first('password'));

        $oubli = Livewire::test(Login::class)->set('forgotEmail', 'pas-une-adresse')->call('sendResetLink');
        $this->assertSame('Le champ adresse e-mail doit être une adresse e-mail valide.', $oubli->errors()->first('forgotEmail'));

        // Quatre échecs de plus : le cinquième déclenche le verrouillage (5 tentatives / 15 min).
        foreach (range(1, 4) as $_) {
            $bloque = $tentative();
        }
        $this->assertNotNull($bloque->get('lockedSecondsRemaining'));
        $bloque->assertSee('Trop de tentatives de connexion. Accès bloqué pendant');
        $this->assertSansAnglais($bloque->html(), "l'écran de connexion verrouillé");

        $this->assertSame('Trop de tentatives de connexion. Veuillez réessayer dans 60 secondes.', __('auth.throttle', ['seconds' => 60]));
        $this->assertSame('Identifiants incorrects.', __('auth.failed'));
    }

    // ================================================================ pages d'erreur et API

    public function test_les_pages_d_erreur_sont_en_francais(): void
    {
        $introuvable = $this->get('/cette-page-n-existe-pas')->assertNotFound();
        $introuvable->assertSee('Page introuvable');
        $this->assertSansAnglais($introuvable->getContent(), 'la page 404');

        // Une route protégée par `can:` : l'exception du framework (« This action is unauthorized. »)
        // passe par `lang/fr.json`.
        $sansDroit = User::create([
            'name' => 'Sans droit', 'username' => 'sansdroit', 'email' => 'sansdroit@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        Permission::findOrCreate('view-elevage', 'web');
        $refus = $this->actingAs($sansDroit)->get(route('elevage.gestion'))->assertForbidden();
        $refus->assertSee('Accès refusé');
        $refus->assertSee('Votre rôle ne permet pas cette action.');
        $this->assertSansAnglais($refus->getContent(), 'la page 403');

        foreach ([401, 419, 429, 500, 503] as $code) {
            $html = view("errors.{$code}", ['exception' => new \Symfony\Component\HttpKernel\Exception\HttpException($code)])->render();
            $this->assertStringContainsString('<html lang="fr">', $html);
            $this->assertSansAnglais($html, "la page {$code}");
        }
    }

    /** L'API du poste : `message` d'erreur traduit, forme de la réponse inchangée. */
    public function test_les_erreurs_de_l_api_sont_en_francais(): void
    {
        $nonConnecte = $this->getJson('/api/auth/me')->assertUnauthorized();
        $this->assertSame('Session expirée ou absente : veuillez vous reconnecter.', $nonConnecte->json('message'));

        $incomplet = $this->postJson('/api/auth/login', [])->assertUnprocessable();
        $incomplet->assertJsonStructure(['message', 'errors' => ['password', 'device_name']]);
        $this->assertSame('Le champ mot de passe est obligatoire.', $incomplet->json('errors.password.0'));
        $this->assertSame('Le champ nom du poste est obligatoire.', $incomplet->json('errors.device_name.0'));
        $this->assertStringContainsString('autres erreurs)', $incomplet->json('message'));
        $this->assertSansAnglais($incomplet->getContent(), 'la réponse de /api/auth/login');

        $this->animalier();
        $refus = $this->postJson('/api/auth/login', ['identifiant' => 'elevage', 'password' => 'faux', 'device_name' => 'POSTE-1']);
        $this->assertSame('Identifiants incorrects.', $refus->json('errors.identifiant.0'));

        $route = $this->getJson('/api/route-inexistante')->assertNotFound();
        $this->assertSame('Ressource introuvable.', $route->json('message'));
    }

    // ================================================================ exceptions attrapées par les écrans

    /**
     * Un écran qui attrape `\Throwable` montre la phrase d'une exception de NOTRE code, mais jamais
     * le détail technique anglais d'une exception du framework.
     */
    public function test_une_exception_technique_devient_un_message_francais_generique(): void
    {
        try {
            app(ImporterPlanSyscohadaService::class)->lire('/chemin/inexistant.csv');
            $this->fail('Le service devait refuser un fichier absent.');
        } catch (\InvalidArgumentException $e) {
            $this->assertSame('Fichier du plan comptable introuvable : /chemin/inexistant.csv', MessagesErreurFr::pourUtilisateur($e));
        }

        try {
            \Illuminate\Support\Facades\DB::select('SELECT * FROM table_qui_n_existe_pas');
            $this->fail('La requête devait échouer.');
        } catch (\Illuminate\Database\QueryException $e) {
            $this->assertSame(MessagesErreurFr::GENERIQUE, MessagesErreurFr::pourUtilisateur($e));
        }
    }

    /** Les gabarits de l'API (ticket 15.33) restent prioritaires et inchangés. */
    public function test_les_motifs_de_refus_du_push_restent_les_memes(): void
    {
        $v = Validator::make(['sold_at' => '2999-01-01'], ['sold_at' => 'date|before_or_equal:now'], MotifsRefusPush::messages(), MotifsRefusPush::attributs());

        $this->assertSame('Vente refusée : la date de la vente (2999-01-01) est dans le futur.', $v->errors()->first('sold_at'));
    }

    /** La boîte « page expirée » de Livewire (anglaise, codée en dur dans son JS) est remplacée. */
    public function test_la_page_expiree_recharge_sans_boite_du_navigateur(): void
    {
        $js = file_get_contents(resource_path('js/app.js'));

        $this->assertStringContainsString("Livewire.hook('request'", $js);
        $this->assertStringContainsString('status !== 419', $js);
        $this->assertStringNotContainsString('window.confirm', $js, 'plus de boîte du navigateur sur une page expirée');
        $this->assertStringContainsString('window.location.reload()', $js);
    }
}
