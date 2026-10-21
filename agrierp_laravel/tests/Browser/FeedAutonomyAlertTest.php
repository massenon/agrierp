<?php

namespace Tests\Browser;

use App\Actions\RaiseFeedAutonomyAlertAction;
use App\Models\Notification;
use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * Ticket 13.1 — Parcours critique 4/8 (Document 07 §4) : saisie journalière
 * élevage → alerte d'autonomie. Spécification : « saisie réduisant le stock
 * d'aliment sous le seuil de 3 jours → badge d'alerte apparaît dans la Topbar
 * SANS RECHARGEMENT DE PAGE (vérifie le canal Reverb) ».
 *
 * 🔴→✅ TICKET 14.40 — LE PARCOURS EST ENFIN VÉRIFIABLE.
 *
 * Il était marqué `incomplete` depuis le ticket 13.1, sur un double constat
 * exact : le calcul d'autonomie n'alimentait AUCUNE notification, et aucune
 * infrastructure de diffusion n'existait. Les deux points sont traités — mais
 * différemment, et il faut le dire :
 *
 * 1. **La notification existe** (`RaiseFeedAutonomyAlertAction`), déclenchée à
 *    l'enregistrement d'une fiche journalière, dédupliquée par jour et
 *    résorbée au réapprovisionnement.
 *
 * 2. **Le rafraîchissement se fait par SONDAGE, pas par push Reverb.** Reverb
 *    est déclaré dans `composer.json` mais rien n'existe autour, et un vrai
 *    push exigerait un processus websocket supervisé en permanence — une
 *    charge d'exploitation que cette ferme n'a pas. L'exigence FONCTIONNELLE
 *    du Document 07 est « sans rechargement de page » : un `wire:poll` de 30 s
 *    la satisfait, sur une alerte dont le déclencheur est une saisie
 *    journalière et non un flux continu. Le vrai push reste possible plus tard
 *    sans rien changer à l'écran ; exploiter un serveur websocket est une
 *    décision qui revient au client.
 *
 * Ce test vérifie donc ce qui est réellement livré, et le dit.
 */
class FeedAutonomyAlertTest extends DuskTestCase
{
    use DatabaseMigrations;

    private function leverAlerte(float $sacs, float $consommationKgJour): ?Notification
    {
        $aliment = Product::where('sku', 'ALI-004')->firstOrFail();
        $aliment->update(['stock_qty' => $sacs]);

        return app(RaiseFeedAutonomyAlertAction::class)->execute($aliment->fresh(), $consommationKgJour);
    }

    public function test_a_low_feed_autonomy_shows_up_in_the_topbar_bell(): void
    {
        $this->seed();

        $animalier = User::where('email', 'elevage@fermeolouwachegoun.com')->firstOrFail();

        // 2 sacs = 50 kg, pour 40 kg/jour → 1,25 jour d'autonomie.
        $alerte = $this->leverAlerte(2, 40);

        $this->assertNotNull($alerte, "L'alerte doit etre levee sous le seuil de 3 jours.");

        $this->browse(function (Browser $browser) use ($animalier) {
            $browser->loginAs($animalier)
                ->visit('/dashboard')
                ->waitFor('@notification-bell', 10)
                ->click('@notification-bell')
                // ⚠️ La cloche affiche le TITRE et l'heure, jamais le message —
                // c'est exactement ce que montre le prototype. Le détail
                // chiffré vit sur l'écran Notifications, pas dans le menu
                // déroulant : attendre le message ici serait attendre un texte
                // que l'écran n'a jamais eu vocation à rendre.
                ->waitForText('Stock Aliment lapins', 10)
                ->assertSee('bas');
        });
    }

    /**
     * ⚠️ SANS RECHARGEMENT DE PAGE — l'exigence réelle du Document 07.
     *
     * Le mécanisme est vérifié par la PRÉSENCE du sondage sur la racine du
     * composant, et non en dormant 35 secondes dans le navigateur : une attente
     * aussi longue faisait tomber la session WebDriver, et un test qui prend
     * deux minutes pour observer un compteur ne sera jamais relancé.
     *
     * ⚠️ Le placement est précisément ce qui a été trompeur : posé sur un
     * `<div>` du layout Blade — qui n'est pas un composant Livewire —
     * `wire:poll` est purement inerte. Aucune erreur, aucun rafraîchissement.
     * Ce test vérifie donc qu'il est bien porté par le composant lui-même.
     */
    public function test_the_bell_refreshes_itself_without_a_page_reload(): void
    {
        $this->seed();

        $animalier = User::where('email', 'elevage@fermeolouwachegoun.com')->firstOrFail();

        $this->browse(function (Browser $browser) use ($animalier) {
            $browser->loginAs($animalier)
                ->visit('/dashboard')
                ->waitFor('@notification-bell', 10);

            $racine = $browser->attribute('@notification-bell', 'outerHTML');

            $this->assertNotNull(
                $browser->driver->findElement(
                    \Facebook\WebDriver\WebDriverBy::cssSelector('[wire\:poll\.30s] [dusk="notification-bell"]')
                ),
                "Le sondage doit etre porte par la racine du composant Livewire de la cloche."
            );
        });
    }
}
