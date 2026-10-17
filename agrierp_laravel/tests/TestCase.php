<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

/**
 * 🔴→✅ GAP DE SQUELETTE TROUVÉ AU TICKET 14.1 : ce fichier standard de
 * `laravel/laravel` n'avait jamais été livré, alors que les 3 tests Feature
 * existants (`AccountingEntryServiceTest`, `BilanTest`, `ClotureExerciceTest`,
 * Sprint 10) l'étendent tous. Conséquence réelle : `php artisan test`
 * échouait immédiatement sur « Class "Tests\TestCase" not found » — la suite
 * Feature n'a donc JAMAIS pu s'exécuter depuis son écriture, et les tests
 * écrits au Sprint 10 n'ont jamais rien prouvé.
 *
 * Même famille d'angle mort que les deux gaps déjà documentés dans
 * `README_SPRINT0.md` (squelette Laravel absent, puis
 * `app/Http/Controllers/Controller.php` absent) : un fichier supposé présent
 * parce qu'il l'est dans tout projet Laravel normal, mais qui ne l'était pas
 * ici, le projet ayant été livré comme un overlay et non comme une
 * installation complète.
 *
 * ⚠️ `tests/Unit` reste absent alors que `phpunit.xml` déclare cette suite —
 * `php artisan test` sans argument échoue donc encore. Non créé ici : aucun
 * test unitaire n'existe à ce jour, créer un dossier vide masquerait le fait
 * plutôt que de le régler. Lancer `php artisan test --testsuite=Feature` en
 * attendant, ou décider avec le client si la suite Unit doit exister.
 */
abstract class TestCase extends BaseTestCase
{
    //
}
