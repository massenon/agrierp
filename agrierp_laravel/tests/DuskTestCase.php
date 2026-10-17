<?php

namespace Tests;

use Facebook\WebDriver\Chrome\ChromeOptions;
use Facebook\WebDriver\Remote\DesiredCapabilities;
use Facebook\WebDriver\Remote\RemoteWebDriver;
use Laravel\Dusk\TestCase as BaseTestCase;

/**
 * Ticket 13.1 (Sprint 13) — base standard Laravel Dusk. Aucune
 * particularité AgriERP ici volontairement : garder ce fichier
 * strictement conforme au boilerplate officiel facilite la maintenance
 * et évite toute divergence future difficile à diagnostiquer.
 *
 * ⚠️ HONNÊTETÉ SUR L'EXÉCUTION (note d'origine, ticket 13.1) : ces 8
 * parcours ont été écrits dans un environnement sans navigateur, donc
 * jamais exécutés. Leur exécution réelle était renvoyée à un poste
 * disposant de Chrome.
 *
 * 🔴→✅ TICKET 14.18 (Sprint 14) — PREMIÈRE EXÉCUTION RÉELLE. Le trait
 * `Tests\CreatesApplication` référencé ici n'existait pas : il a été
 * SUPPRIMÉ du squelette Laravel à partir de la version 11, où
 * `Tests\TestCase` étend directement le TestCase du framework. Ce fichier
 * était donc resté au format Laravel ≤10 et faisait échouer `php artisan
 * dusk` avant même le premier parcours, sur une erreur fatale
 * (« Trait "Tests\CreatesApplication" not found »).
 *
 * Même famille d'angle mort que `tests/TestCase.php` (absent, ticket 14.1)
 * et `app/Http/Controllers/Controller.php` (absent, Sprint 12) : un projet
 * livré en overlay sur un squelette assemblé à la main, où les fichiers
 * supposés « standards » ne le sont pas tous.
 *
 * Corrigé en s'alignant sur le squelette Laravel 12 réel — la classe
 * hérite du TestCase de Dusk, qui amorce lui-même l'application.
 */
abstract class DuskTestCase extends BaseTestCase
{

    /**
     * Prepare for Dusk test execution.
     */
    public static function prepare(): void
    {
        if (! static::runningInSail()) {
            static::startChromeDriver(['--port=9515']);
        }
    }

    /**
     * Create the RemoteWebDriver instance.
     */
    protected function driver(): RemoteWebDriver
    {
        $options = (new ChromeOptions)->addArguments(collect([
            $this->shouldStartMaximized() ? '--start-maximized' : '--window-size=1440,900',
        ])->unless($this->hasHeadlessDisabled(), function ($items) {
            return $items->merge([
                '--disable-gpu',
                '--headless=new',
            ]);
        })->all());

        return RemoteWebDriver::create(
            $_ENV['DUSK_DRIVER_URL'] ?? env('DUSK_DRIVER_URL') ?? 'http://localhost:9515',
            DesiredCapabilities::chrome()->setCapability(
                ChromeOptions::CAPABILITY, $options
            )
        );
    }
}
