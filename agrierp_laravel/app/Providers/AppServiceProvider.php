<?php

namespace App\Providers;

use App\Services\Mecef\FakeMecefGateway;
use App\Services\Mecef\MecefGatewayInterface;
use App\Support\DatesValidationFr;
use Illuminate\Support\ServiceProvider;
use Illuminate\Validation\Rules\Password;

/**
 * ⚠️ Ce fichier n'existait pas dans l'arborescence livrée jusqu'ici — le
 * squelette Laravel 11 standard en fournit une version vide par défaut.
 * À fusionner avec celle de votre installation locale (Laragon) : ce
 * contenu remplace l'éventuel fichier vide existant, il n'y a rien
 * d'autre à y conserver pour l'instant.
 *
 * Lie `MecefGatewayInterface` à `FakeMecefGateway` (Document 06 §7) —
 * seul point de configuration à changer pour brancher une future
 * `RealMecefGateway` sans toucher au reste de l'application.
 */
class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->bind(MecefGatewayInterface::class, FakeMecefGateway::class);
    }

    public function boot(): void
    {
        // Un champ numérique vidé au clavier vaut 0 au lieu de casser l'écran (voir la classe).
        \App\Support\ChampNumeriqueVide::enregistrer();

        // ⚠️⚠️ TICKET 14.65 — POLITIQUE DE MOT DE PASSE CENTRALISEE. Les deux
        // seuls endroits qui posent un mot de passe (`ResetPassword` et
        // `GestionUtilisateurs`) exigeaient `min:8` et rien d'autre :
        // « 12345678 » passait. La regle vit desormais en un seul endroit, et
        // les ecrans l'appellent par `Password::defaults()`.
        //
        // ⚠️ **`uncompromised()` VOLONTAIREMENT ABSENT.** Il interroge un
        // service en ligne (HaveIBeenPwned) : sur une ferme d'Ikpinle dont la
        // liaison tombe, la creation d'un compte deviendrait impossible. Une
        // regle de securite qui bloque l'exploitation hors ligne serait
        // contraire a la nature meme de ce projet.
        Password::defaults(fn () => Password::min(8)->letters()->numbers()->symbols());

        // Ticket U5 (D-U5) — « :date » des règles de date en français (« aujourd'hui », jj/mm/aaaa)
        // : les phrases viennent de `lang/fr/validation.php`, mais Laravel y collait « today ».
        DatesValidationFr::enregistrer();

        // Ticket POP1 — chaque CONNEXION (mot de passe ou jeton « se souvenir de moi ») redemande la fenêtre « Rappels du
        // jour » : le drapeau est consommé par sa première ouverture (`Livewire\Shared\RappelsDuJour::ouvrir`).
        \Illuminate\Support\Facades\Event::listen(\Illuminate\Auth\Events\Login::class, fn () => session()->put('rappels_forcer', true));

        // Ticket EX7 (EF10) — `@lectureSeule`, juste après `<button` d'un bouton de saisie (Nouveau, Modifier, Archiver,
        // Enregistrer) : grisé, désactivé, motif « Exercice 2026 clôturé — lecture seule » en info-bulle quand
        // l'exercice affiché est clos. Le motif est lu UNE fois par rendu de vue (`$__motifExercice`), pas à chaque
        // ligne d'une liste. Confort seulement : la garantie reste le refus du serveur (EX5).
        \Illuminate\Support\Facades\Blade::directive('lectureSeule', fn () => '<?php echo \App\Support\ExerciceChoisi::attributs(($__motifExercice ??= [\App\Support\ExerciceChoisi::motifLectureSeule()])[0]); ?>');
    }
}
